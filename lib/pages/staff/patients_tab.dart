import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:health_share_org/functions/files/upload_file.dart';
import 'package:health_share_org/functions/files/decrypt_file.dart';

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
  static const Color approvedGreen = Color(0xFF22C55E);
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
                contact_number,
                image
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
    // Get the current doctor's user ID
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null || currentUser.email == null) {
      throw Exception('No authenticated user found');
    }

    final userEmail = currentUser.email!;
    
    // Get current doctor's user_id
    final currentUserResponse = await Supabase.instance.client
        .from('User')
        .select('id')
        .eq('email', userEmail)
        .single();
    
    final currentDoctorUserId = currentUserResponse['id'];
    print('DEBUG: Current doctor user ID: $currentDoctorUserId');

    // Get patient's user_id
    final patientResponse = await Supabase.instance.client
        .from('Patient')
        .select('user_id')
        .eq('id', patientId)
        .single();

    final patientUserId = patientResponse['user_id'];
    print('DEBUG: Patient user ID: $patientUserId');

    // Get all File_Shares where either:
    // - Doctor shared with patient (shared_by_user_id = doctor AND shared_with_user_id = patient)
    // - Patient shared with doctor (shared_by_user_id = patient AND (shared_with_user_id = doctor OR shared_with_doctor = doctor))
    final allShares = await Supabase.instance.client
        .from('File_Shares')
        .select('''
          id,
          shared_at,
          shared_by_user_id,
          shared_with_user_id,
          shared_with_doctor,
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
        .or('and(shared_by_user_id.eq.$currentDoctorUserId,shared_with_user_id.eq.$patientUserId),and(shared_by_user_id.eq.$patientUserId,shared_with_user_id.eq.$currentDoctorUserId),and(shared_by_user_id.eq.$patientUserId,shared_with_doctor.eq.$currentDoctorUserId)')
        .order('shared_at', ascending: false);

    print('DEBUG: Doctor user_id: $currentDoctorUserId, Patient user_id: $patientUserId');
    print('DEBUG: Found ${allShares.length} file shares between doctor and patient');
    
    // Debug: print the actual shares found
    for (var share in allShares) {
      print('DEBUG: Share - shared_by: ${share['shared_by_user_id']}, shared_with: ${share['shared_with_user_id']}');
    }

    List<Map<String, dynamic>> filesList = [];
    for (var share in allShares) {
      filesList.add(Map<String, dynamic>.from(share as Map));
    }

    setState(() {
      _selectedPatientFiles = filesList;
      _loadingFiles = false;
    });

    print('Loaded ${filesList.length} files for this patient');
  } catch (e) {
    print('Error loading files for patient: $e');
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Patients',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: PatientsTheme.darkGray),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadPatients,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PatientsTheme.primaryGreen,
                      side: const BorderSide(color: PatientsTheme.primaryGreen),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showSnackBar('Add patient feature coming soon!'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Patient'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PatientsTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Content
          if (_loadingPatients)
            Container(
              height: 400,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: PatientsTheme.primaryGreen),
                    SizedBox(height: 16),
                    Text('Loading patients...'),
                  ],
                ),
              ),
            )
          else if (_patients.isEmpty)
            Container(
              height: 400,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 80, color: Colors.grey),
                    SizedBox(height: 24),
                    Text('No patients assigned', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 8),
                    Text(
                      'Patients will appear here once assigned to you',
                      style: TextStyle(fontSize: 14, color: PatientsTheme.textGray),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildPatientsTable(),
        ],
      ),
    );
  }

  Widget _buildPatientAvatar(Map<String, dynamic> person, {double radius = 16}) {
    final imageUrl = person['image'] as String?;
    final fullName = _buildFullName(person);
    
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(imageUrl),
        onBackgroundImageError: (_, __) {
          // Fallback to initials if image fails to load
        },
        child: ClipOval(
          child: Image.network(
            imageUrl,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: radius * 2,
                height: radius * 2,
                color: PatientsTheme.primaryGreen,
                child: Center(
                  child: Text(
                    _getPatientInitials(fullName),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: radius * 0.75,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      // Fallback to initials avatar
      return CircleAvatar(
        radius: radius,
        backgroundColor: PatientsTheme.primaryGreen,
        child: Text(
          _getPatientInitials(fullName),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.75,
          ),
        ),
      );
    }
  }

  Widget _buildPatientsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Patient', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Patient ID', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(flex: 2, child: Text('Contact', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Status', style: TextStyle(fontWeight: FontWeight.w500))),
                SizedBox(width: 100),
              ],
            ),
          ),

          // Rows
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _patients.length,
            itemBuilder: (context, index) {
              final patient = _patients[index];
              final person = patient['User']['Person'];
              final fullName = _buildFullName(person);

              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: index < _patients.length - 1 ? Colors.grey.shade200 : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Name with avatar
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          _buildPatientAvatar(person, radius: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  person['contact_number'] ?? 'No phone',
                                  style: const TextStyle(fontSize: 12, color: PatientsTheme.textGray),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Patient ID
                    Expanded(
                      child: Text(
                        patient['patient_id'].toString(),
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Email
                    Expanded(
                      flex: 2,
                      child: Text(
                        patient['User']['email'] ?? '',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Status
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          patient['status'] ?? 'active',
                          style: const TextStyle(
                            fontSize: 12,
                            color: PatientsTheme.approvedGreen,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    // Actions
                    SizedBox(
                      width: 100,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedPatient = patient;
                              });
                              final patientId = patient['patient_id'].toString();
                              _loadAllFilesForPatient(patientId);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: PatientsTheme.primaryGreen,
                            ),
                            child: const Text('View'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPatientDetailsView() {
    final patient = _selectedPatient!;
    final person = patient['User']['Person'];
    final fullName = _buildFullName(person);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button and header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
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
                  _buildPatientAvatar(person, radius: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        patient['User']['email'] ?? '',
                        style: const TextStyle(
                          color: PatientsTheme.textGray,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Files Section
          if (_loadingFiles)
            Container(
              height: 400,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: PatientsTheme.primaryGreen),
                    SizedBox(height: 16),
                    Text('Loading files...'),
                  ],
                ),
              ),
            )
          else if (_selectedPatientFiles.isEmpty)
            Container(
              height: 400,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_outlined, size: 80, color: Colors.grey),
                    SizedBox(height: 24),
                    Text('No files shared', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 8),
                    Text(
                      'Upload files to share with this patient',
                      style: TextStyle(fontSize: 14, color: PatientsTheme.textGray),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildFilesTable(),
        ],
      ),
    );
  }

  Widget _buildFilesTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('File Name', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Category', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Type', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Uploaded By', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Date', style: TextStyle(fontWeight: FontWeight.w500))),
                SizedBox(width: 100),
              ],
            ),
          ),

          // Rows
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _selectedPatientFiles.length,
            itemBuilder: (context, index) {
              final fileShare = _selectedPatientFiles[index];
              final file = fileShare['Files'];
              final fileType = file['file_type'] ?? 'unknown';
              final category = file['category'] ?? 'other';
              final fileName = file['filename'] ?? 'Unknown File';
              final createdAt = DateTime.tryParse(file['uploaded_at'] ?? '') ?? DateTime.now();
              final uploader = file['uploader'];
              final uploaderName = uploader != null
                  ? '${uploader['Person']['first_name']} ${uploader['Person']['last_name']}'
                  : 'Unknown';

              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: index < _selectedPatientFiles.length - 1
                          ? Colors.grey.shade200
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // File name with icon
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _getFileTypeColor(fileType).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              _getFileTypeIcon(fileType),
                              color: _getFileTypeColor(fileType),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              fileName,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Category
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                    // Type
                    Expanded(
                      child: Text(
                        fileType.toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Uploader
                    Expanded(
                      child: Text(
                        uploaderName,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Date
                    Expanded(
                      child: Text(
                        _formatDate(createdAt),
                        style: const TextStyle(fontSize: 12, color: PatientsTheme.textGray),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Actions
                    SizedBox(
                      width: 100,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            onPressed: () => FileDecryptionService.previewFile(
                                context, file, _showSnackBar),
                            icon: const Icon(Icons.visibility, size: 18),
                            color: PatientsTheme.primaryGreen,
                            tooltip: 'Preview',
                          ),
                          PopupMenuButton(
                            icon: const Icon(Icons.more_vert, size: 18, color: PatientsTheme.textGray),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'details',
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 16),
                                    SizedBox(width: 8),
                                    Text('Details'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red, size: 16),
                                    SizedBox(width: 8),
                                    Text('Delete', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'details') {
                                _showFileDetails(file);
                              } else if (value == 'delete') {
                                _confirmDeleteFile(file);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
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

  void _showFileDetails(Map<String, dynamic> file) {
    final uploadedAt = DateTime.tryParse(file['uploaded_at'] ?? '') ?? DateTime.now();
    final uploader = file['uploader'];
    final uploaderName = uploader != null
        ? '${uploader['Person']['first_name']} ${uploader['Person']['last_name']}'
        : 'Unknown';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: const Color(0xFFF8F9FA),
        title: Row(
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
            const Expanded(
              child: Text(
                'File Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: PatientsTheme.darkGray),
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
            style: TextButton.styleFrom(
              foregroundColor: PatientsTheme.primaryGreen,
            ),
            child: const Text('Close'),
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
            style: const TextStyle(
              fontSize: 12,
              color: PatientsTheme.textGray,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: const Color(0xFFF8F9FA),
        title: const Text(
          'Delete File',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: PatientsTheme.darkGray,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${file['filename']}"? This action cannot be undone.',
          style: const TextStyle(color: PatientsTheme.darkGray),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: PatientsTheme.textGray,
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteFile(file);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
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