import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:health_share_org/functions/files/upload_file.dart';
import 'package:health_share_org/functions/files/decrypt_file.dart';
import 'package:health_share_org/services/file_preview.dart';

// Theme colors matching the staff dashboard
class PatientsTheme {
  static const Color primaryGreen = Color(0xFF4A8B3A);
  static const Color lightGreen = Color(0xFF6BA85A);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color textGray = Color(0xFF6C757D);
  static const Color darkGray = Color(0xFF495057);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color orange = Color(0xFFFF9500);
}

class ModernPatientsContentWidget extends StatefulWidget {
  const ModernPatientsContentWidget({Key? key}) : super(key: key);

  @override
  State<ModernPatientsContentWidget> createState() => _ModernPatientsContentWidgetState();
}

class _ModernPatientsContentWidgetState extends State<ModernPatientsContentWidget> {
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _selectedPatientFiles = [];
  Map<String, dynamic>? _selectedPatient;
  bool _loadingPatients = false;
  bool _loadingFiles = false;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loadingPatients = true;
    });

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null || currentUser.email == null) {
        throw Exception('No authenticated user found');
      }

      final userEmail = currentUser.email!;
      print('DEBUG: Looking up user with email: $userEmail');

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, person_id')
          .eq('email', userEmail)
          .single();

      print('DEBUG: User lookup response: $userResponse');
      final userId = userResponse['id'];

      final doctorLookupResponse = await Supabase.instance.client
          .from('Organization_User')
          .select('id, position, department')
          .eq('user_id', userId)
          .eq('position', 'Doctor');

      print('DEBUG: Doctor lookup response: $doctorLookupResponse');

      if (doctorLookupResponse.isEmpty) {
        throw Exception(
            'No doctor records found for this user. Make sure you have a Doctor position in Organization_User table.');
      }

      final doctorIds =
          doctorLookupResponse.map((doctor) => doctor['id']).toList();
      print('DEBUG: Doctor IDs for assignment lookup: $doctorIds');

      final response = await Supabase.instance.client
          .from('Doctor_User_Assignment')
          .select('''
          id,
          doctor_id,
          patient_id,
          status,
          assigned_at,
          Patient!patient_id(
            id,
            user_id,
            organization_id,
            User!user_id(
              id,
              person_id,
              email,
              Person!person_id(
                id,
                first_name,
                middle_name,
                last_name,
                address,
                contact_number
              )
            )
          )
        ''')
          .in_('doctor_id', doctorIds)
          .eq('status', 'active');

      print('DEBUG: Patients query response: $response');

      final transformedPatients =
          response.map<Map<String, dynamic>>((assignment) {
        final assignmentMap = assignment as Map<String, dynamic>;
        final patientData = assignmentMap['Patient'] as Map<String, dynamic>;

        return {
          'patient_id': assignmentMap['patient_id'],
          'doctor_id': assignmentMap['doctor_id'],
          'status': assignmentMap['status'],
          'assigned_at': assignmentMap['assigned_at'],
          'User': patientData['User'],
          'Patient': patientData,
        };
      }).toList();

      setState(() {
        _patients = List<Map<String, dynamic>>.from(transformedPatients);
        _loadingPatients = false;
      });
    } catch (e) {
      print('Error loading patients: $e');
      setState(() {
        _loadingPatients = false;
      });
      _showSnackBar('Error loading patients: $e');
    }
  }

  Future<void> _loadAllFilesForPatient(String patientId) async {
    setState(() {
      _loadingFiles = true;
    });

    try {
      final patientResponse = await Supabase.instance.client
          .from('Patient')
          .select('user_id')
          .eq('id', patientId)
          .single();

      final userId = patientResponse['user_id'];
      print('DEBUG: Patient ID: $patientId, User ID: $userId');

      final sharedFilesResponse = await Supabase.instance.client
          .from('File_Shares')
          .select('''
          id,
          shared_at,
          Files!inner(
            id,
            filename,
            category,
            file_type,
            uploaded_at,
            file_size,
            ipfs_cid,
            sha256_hash,
            uploaded_by,
            uploader:User!uploaded_by(
              Person!person_id(
                first_name,
                last_name
              )
            )
          )
        ''')
          .eq('shared_with_user_id', userId)
          .order('shared_at', ascending: false);

      final patientFilesResponse = await Supabase.instance.client
          .from('Files')
          .select('''
          id,
          filename,
          category,
          file_type,
          uploaded_at,
          file_size,
          ipfs_cid,
          sha256_hash,
          uploaded_by,
          uploader:User!uploaded_by(
            Person!person_id(
              first_name,
              last_name
            )
          )
        ''')
          .eq('uploaded_by', userId)
          .order('uploaded_at', ascending: false);

      List<Map<String, dynamic>> allFiles = [];

      for (var share in sharedFilesResponse) {
        allFiles.add(Map<String, dynamic>.from(share as Map));
      }

      for (var file in patientFilesResponse) {
        allFiles.add(<String, dynamic>{
          'id': null,
          'shared_at': null,
          'Files': Map<String, dynamic>.from(file as Map),
          'is_patient_file': true,
        });
      }

      allFiles.sort((a, b) {
        final aDate = DateTime.tryParse(
                a['shared_at'] ?? a['Files']['uploaded_at'] ?? '') ??
            DateTime.now();
        final bDate = DateTime.tryParse(
                b['shared_at'] ?? b['Files']['uploaded_at'] ?? '') ??
            DateTime.now();
        return bDate.compareTo(aDate);
      });

      setState(() {
        _selectedPatientFiles = allFiles;
        _loadingFiles = false;
      });

      final sharedCount = sharedFilesResponse.length;
      final patientCount = patientFilesResponse.length;
      print('Loaded $sharedCount shared files and $patientCount patient files');
    } catch (e) {
      print('Error loading all patient files: $e');
      setState(() {
        _loadingFiles = false;
      });
      _showSnackBar('Error loading files: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: PatientsTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _selectedPatient == null
        ? _buildPatientsListView()
        : _buildPatientDetailsView();
  }

  Widget _buildPatientsListView() {
    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Patients',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showSnackBar('Add patient feature coming soon!'),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add Patient'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PatientsTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: _loadingPatients
              ? const Center(
                  child: CircularProgressIndicator(color: PatientsTheme.primaryGreen))
              : _patients.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Patients Assigned',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Patients will appear here once assigned to you',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: _patients.length,
                      itemBuilder: (context, index) {
                        final patient = _patients[index];
                        final person = patient['User']['Person'];
                        final fullName = _buildFullName(person);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: _getPatientAvatarColor(index),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _getPatientInitials(fullName),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  patient['User']['email'] ?? '',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Patient ID: ${patient['patient_id']}',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                patient['status'] ?? 'active',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedPatient = patient;
                              });
                              final patientId = patient['patient_id'].toString();
                              _loadAllFilesForPatient(patientId);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPatientDetailsView() {
    final patient = _selectedPatient!;
    final person = patient['User']['Person'];
    final fullName = _buildFullName(person);

    return Column(
      children: [
        // Patient Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedPatient = null;
                    _selectedPatientFiles = [];
                  });
                },
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 12),
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  color: PatientsTheme.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _getPatientInitials(fullName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      patient['User']['email'] ?? '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => FileUploadService.uploadFileForPatient(
                  context,
                  _selectedPatient!,
                  _showSnackBar,
                  () => _loadAllFilesForPatient(
                      _selectedPatient!['patient_id'].toString()),
                ),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PatientsTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        // Files Section
        Expanded(
          child: _loadingFiles
              ? const Center(
                  child: CircularProgressIndicator(color: PatientsTheme.primaryGreen))
              : _selectedPatientFiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Files Shared',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Upload files to share with this patient',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: _selectedPatientFiles.length,
                      itemBuilder: (context, index) {
                        final fileShare = _selectedPatientFiles[index];
                        final file = fileShare['Files'];
                        return _buildFileCard(file);
                      },
                    ),
        ),
      ],
    );
  }

  // Helper methods
  Color _getPatientAvatarColor(int index) {
    final colors = [
      PatientsTheme.primaryGreen,
      PatientsTheme.coral,
      PatientsTheme.orange,
      Colors.purple,
      Colors.teal
    ];
    return colors[index % colors.length];
  }

  String _getPatientInitials(String fullName) {
    if (fullName.trim().isEmpty) {
      return 'P';
    }

    final names =
        fullName.trim().split(' ').where((name) => name.isNotEmpty).toList();

    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    } else if (names.isNotEmpty && names[0].isNotEmpty) {
      return names[0][0].toUpperCase();
    }
    return 'P';
  }

  String _buildFullName(Map<String, dynamic> person) {
    final parts = <String>[];

    if (person['first_name'] != null &&
        person['first_name'].toString().trim().isNotEmpty) {
      parts.add(person['first_name'].toString().trim());
    }

    if (person['middle_name'] != null &&
        person['middle_name'].toString().trim().isNotEmpty) {
      parts.add(person['middle_name'].toString().trim());
    }

    if (person['last_name'] != null &&
        person['last_name'].toString().trim().isNotEmpty) {
      parts.add(person['last_name'].toString().trim());
    }

    return parts.join(' ');
  }

  Color _getFileTypeColor(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.blue;
      case 'doc':
      case 'docx':
        return Colors.blue[700]!;
      case 'txt':
        return Colors.grey[600]!;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  IconData _getFileTypeIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'medical_report':
        return Colors.blue;
      case 'lab_result':
        return Colors.green;
      case 'prescription':
        return Colors.purple;
      case 'x_ray':
        return Colors.orange;
      case 'mri_scan':
        return Colors.red;
      case 'ct_scan':
        return Colors.indigo;
      case 'ultrasound':
        return Colors.teal;
      case 'blood_test':
        return Colors.pink;
      case 'discharge_summary':
        return Colors.brown;
      case 'consultation_notes':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1 year ago' : '$years years ago';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildFileCard(Map<String, dynamic> file) {
    final fileType = file['file_type'] ?? 'unknown';
    final category = file['category'] ?? 'other';
    final fileName = file['filename'] ?? 'Unknown File';
    final createdAt = DateTime.tryParse(file['uploaded_at'] ?? '') ?? DateTime.now();
    final uploader = file['uploader'];
    final uploaderName = uploader != null
        ? '${uploader['Person']['first_name']} ${uploader['Person']['last_name']}'
        : 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => SimpleFilePreviewService.previewFile(context, file, _showSnackBar),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getFileTypeColor(fileType),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getFileTypeIcon(fileType),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(category).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            category.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: _getCategoryColor(category),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_formatDate(createdAt)} • $uploaderName',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: PatientsTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () => SimpleFilePreviewService.previewFile(context, file, _showSnackBar),
                  icon: const Icon(Icons.visibility, color: PatientsTheme.primaryGreen, size: 20),
                  tooltip: 'Preview file',
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _showFileActions(file),
                icon: const Icon(Icons.more_vert, color: PatientsTheme.textGray),
                tooltip: 'More actions',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileActions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getFileTypeColor(file['file_type'] ?? '').withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getFileTypeIcon(file['file_type'] ?? ''),
                        color: _getFileTypeColor(file['file_type'] ?? ''),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file['filename'] ?? 'Unknown File',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatFileSize(file['file_size'] ?? 0)} • ${(file['file_type'] ?? '').toUpperCase()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildActionTile(
                      icon: Icons.visibility,
                      title: 'Preview File',
                      subtitle: 'View in app',
                      onTap: () {
                        Navigator.pop(context);
                        SimpleFilePreviewService.previewFile(context, file, _showSnackBar);
                      },
                    ),
                    _buildActionTile(
                      icon: Icons.download,
                      title: 'Download File',
                      subtitle: 'Save to device',
                      onTap: () {
                        Navigator.pop(context);
                        FileDecryptionService.downloadAndDecryptFile(context, file, _showSnackBar);
                      },
                    ),
                    _buildActionTile(
                      icon: Icons.info_outline,
                      title: 'File Details',
                      subtitle: 'View metadata',
                      onTap: () {
                        Navigator.pop(context);
                        _showFileDetails(file);
                      },
                      ),
                    _buildActionTile(
                      icon: Icons.share,
                      title: 'Share File',
                      subtitle: 'Share with other staff',
                      onTap: () {
                        Navigator.pop(context);
                        _showSnackBar('Share feature coming soon!');
                      },
                    ),
                    _buildActionTile(
                      icon: Icons.delete_outline,
                      title: 'Delete File',
                      subtitle: 'Remove from patient records',
                      color: Colors.red,
                      onTap: () {
                        Navigator.pop(context);
                        _confirmDeleteFile(file);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? PatientsTheme.darkGray;
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: effectiveColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: effectiveColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: effectiveColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  void _showFileDetails(Map<String, dynamic> file) {
    final uploadedAt = DateTime.tryParse(file['uploaded_at'] ?? '') ?? DateTime.now();
    final uploader = file['uploader'];
    final uploaderName = uploader != null
        ? '${uploader['Person']['first_name']} ${uploader['Person']['last_name']}'
        : 'Unknown';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              _getFileTypeIcon(file['file_type'] ?? ''),
              color: _getFileTypeColor(file['file_type'] ?? ''),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'File Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Filename', file['filename'] ?? 'Unknown'),
              _buildDetailRow('Category', (file['category'] ?? 'other').replaceAll('_', ' ').toUpperCase()),
              _buildDetailRow('File Type', (file['file_type'] ?? 'unknown').toUpperCase()),
              _buildDetailRow('File Size', _formatFileSize(file['file_size'] ?? 0)),
              _buildDetailRow('Uploaded By', uploaderName),
              _buildDetailRow('Uploaded At', _formatDateTime(uploadedAt)),
              _buildDetailRow('File ID', file['id'] ?? 'Unknown'),
              if (file['ipfs_cid'] != null)
                _buildDetailRow('IPFS CID', file['ipfs_cid'], monospace: true),
              if (file['sha256_hash'] != null)
                _buildDetailRow('SHA256 Hash', file['sha256_hash'], monospace: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: PatientsTheme.primaryGreen)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool monospace = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: PatientsTheme.darkGray,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFile(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${file['filename']}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: PatientsTheme.textGray)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteFile(file);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: PatientsTheme.primaryGreen),
        ),
      );

      // Delete from Files table
      await Supabase.instance.client
          .from('Files')
          .delete()
          .eq('id', file['id']);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      _showSnackBar('File deleted successfully');
      
      // Reload files
      if (_selectedPatient != null) {
        _loadAllFilesForPatient(_selectedPatient!['patient_id'].toString());
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      print('Error deleting file: $e');
      _showSnackBar('Error deleting file: $e');
    }
  }
}