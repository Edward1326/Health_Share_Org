import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:health_share_org/services/aes_helper.dart';
import 'package:health_share_org/services/crypto_utils.dart';
import 'dart:html' as html;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:math';
import 'package:pointycastle/export.dart' as pc;
import 'package:crypto/crypto.dart';
import 'package:health_share_org/functions/files/upload_file.dart';
import 'package:health_share_org/functions/files/decrypt_file.dart';
import 'dart:async';

class PatientsTab extends StatefulWidget {
  const PatientsTab({Key? key}) : super(key: key);

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _selectedPatientFiles = [];
  Map<String, dynamic>? _selectedPatient;
  bool _loadingPatients = false;
  bool _loadingFiles = false;

  // Define app theme colors
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color orange = Color(0xFFFF9500);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color darkGray = Color(0xFF757575);
  static const Color cardBackground = Color(0xFFFFFFFF);

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
      patient_user:User!patient_id(
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
    ''')
          .in_('doctor_id', doctorIds)
          .eq('status', 'active');

      print('DEBUG: Patients query response: $response');

      final transformedPatients =
          response.map<Map<String, dynamic>>((assignment) {
        final assignmentMap = assignment as Map<String, dynamic>;
        return {
          'patient_id': assignmentMap['patient_id'],
          'doctor_id': assignmentMap['doctor_id'],
          'status': assignmentMap['status'],
          'assigned_at': assignmentMap['assigned_at'],
          'User': assignmentMap['patient_user'],
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

// Add this function to your _PatientsTabState class - loads ALL files for the patient
  // Add this function to your _PatientsTabState class - loads ALL files for the patient
  Future<void> _loadAllFilesForPatient(String patientId) async {
    setState(() {
      _loadingFiles = true;
    });

    try {
      // Load files shared with the patient
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
          .eq('shared_with_user_id', patientId)
          .order('shared_at', ascending: false);

      // Load files uploaded by the patient
      final patientFilesResponse =
          await Supabase.instance.client.from('Files').select('''
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
      ''').eq('uploaded_by', patientId).order('uploaded_at', ascending: false);

      // Combine both lists
      List<Map<String, dynamic>> allFiles = [];

      // Add shared files - cast each item properly
      for (var share in sharedFilesResponse) {
        allFiles.add(Map<String, dynamic>.from(share as Map));
      }

      // Add patient's own files - transform to match structure
      for (var file in patientFilesResponse) {
        allFiles.add(<String, dynamic>{
          'id': null, // No File_Shares id
          'shared_at': null,
          'Files': Map<String, dynamic>.from(file as Map),
          'is_patient_file': true, // Flag to identify patient's own files
        });
      }

      // Sort all files by date (most recent first)
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
      print(
          'Loaded $sharedCount shared files and $patientCount patient files for patient $patientId');
    } catch (e) {
      print('Error loading all patient files: $e');
      setState(() {
        _loadingFiles = false;
      });
      _showSnackBar('Error loading files: $e');
    }
  }

  Future<void> _loadPatientFiles(String patientId) async {
    setState(() {
      _loadingFiles = true;
    });

    try {
      final response = await Supabase.instance.client
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
          .eq('shared_with_user_id', patientId)
          .order('shared_at', ascending: false);

      setState(() {
        _selectedPatientFiles = List<Map<String, dynamic>>.from(response);
        _loadingFiles = false;
      });

      print(
          'Loaded ${_selectedPatientFiles.length} files for patient $patientId');
    } catch (e) {
      print('Error loading patient files: $e');
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
        backgroundColor: primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header with Add Patient button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
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
                  onPressed: () =>
                      _showSnackBar('Add patient feature coming soon!'),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _loadingPatients
                ? const Center(
                    child: CircularProgressIndicator(color: primaryBlue))
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
                    : _selectedPatient == null
                        ? _buildPatientsList()
                        : _buildPatientDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
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
                blurRadius: 8,
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }

  Widget _buildPatientDetails() {
    final patient = _selectedPatient!;
    final person = patient['User']['Person'];
    final fullName =
        '${person['first_name']} ${person['middle_name'] ?? ''} ${person['last_name']}'
            .trim();

    return Column(
      children: [
        // Patient Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
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
                decoration: BoxDecoration(
                  color: primaryBlue,
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
                  () => _loadPatientFiles(
                      _selectedPatient!['patient_id'].toString()),
                ),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // Files Section
        Expanded(
          child: _loadingFiles
              ? const Center(
                  child: CircularProgressIndicator(color: primaryBlue))
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
                      padding: const EdgeInsets.all(20),
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

  Widget _buildFileCard(Map<String, dynamic> file) {
    final fileType = file['file_type'] ?? 'unknown';
    final category = file['category'] ?? 'other';
    final fileName = file['filename'] ?? 'Unknown File';
    // Remove this line since description doesn't exist:
    // final description = file['description'] ?? '';
    final createdAt =
        DateTime.tryParse(file['uploaded_at'] ?? '') ?? DateTime.now();
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
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
                  // Remove the description section since it doesn't exist
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
                      Text(
                        '${_formatDate(createdAt)} • $uploaderName',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _showFileActions(file),
              icon: const Icon(Icons.more_vert, color: darkGray),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods
  Color _getPatientAvatarColor(int index) {
    final colors = [primaryBlue, coral, orange, Colors.purple, Colors.teal];
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

  void _showFileActions(Map<String, dynamic> file) {
    FileDecryptionService.showFileActions(
      context,
      file,
      _showSnackBar,
      onRemoveShare: () => _removeFileShare(file),
      onShare: () => _shareFile(file),
      showRemoveShare: true,
    );
  }

  void _shareFile(Map<String, dynamic> file) {
    _showSnackBar('Share functionality coming soon!');
  }

  void _removeFileShare(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove File Share'),
        content: const Text(
            'Are you sure you want to remove this file share? The patient will no longer have access to this file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performRemoveFileShare(file);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: coral,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _performRemoveFileShare(Map<String, dynamic> file) async {
    try {
      // Find and delete the file share record
      await Supabase.instance.client
          .from('File_Shares')
          .delete()
          .eq('file_id', file['id'])
          .eq('shared_with_user_id', _selectedPatient!['patient_id']);

      // Refresh the patient files
      final patientId = _selectedPatient!['patient_id'].toString();
      await _loadPatientFiles(patientId);

      _showSnackBar('File share removed successfully');
    } catch (e) {
      print('Error removing file share: $e');
      _showSnackBar('Error removing file share: $e');
    }
  }
}
