import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:health_share_org/functions/files/upload_file.dart';
import 'package:health_share_org/functions/files/decrypt_file.dart';
import 'package:health_share_org/functions/files/delete_file.dart';

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
  State<ModernPatientsContentWidget> createState() =>
      _ModernPatientsContentWidgetState();
}

class _ModernPatientsContentWidgetState
    extends State<ModernPatientsContentWidget> {
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _selectedPatientFiles = [];
  Map<String, dynamic>? _selectedPatient;
  bool _loadingPatients = false;
  bool _loadingFiles = false;
  List<Map<String, dynamic>> _assignedDoctors = [];
  bool _loadingDetails = false;
  int _selectedTabIndex = 0;

  // Sorting state for patients table
  String _patientsSortColumn = 'name';
  bool _patientsSortAscending = true;

  // Sorting state for files table
  String _filesSortColumn = 'uploaded_at';
  bool _filesSortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  void _sortPatients(String column) {
    setState(() {
      if (_patientsSortColumn == column) {
        _patientsSortAscending = !_patientsSortAscending;
      } else {
        _patientsSortColumn = column;
        _patientsSortAscending = true;
      }

      _patients.sort((a, b) {
        dynamic aValue;
        dynamic bValue;

        switch (column) {
          case 'name':
            aValue = _buildFullName(a['User']['Person']).toLowerCase();
            bValue = _buildFullName(b['User']['Person']).toLowerCase();
            break;
          case 'email':
            aValue = (a['User']['email'] ?? '').toLowerCase();
            bValue = (b['User']['email'] ?? '').toLowerCase();
            break;
          case 'status':
            aValue = (a['status'] ?? '').toLowerCase();
            bValue = (b['status'] ?? '').toLowerCase();
            break;
          default:
            return 0;
        }

        final comparison = aValue.compareTo(bValue);
        return _patientsSortAscending ? comparison : -comparison;
      });
    });
  }

  void _sortFiles(String column) {
    setState(() {
      if (_filesSortColumn == column) {
        _filesSortAscending = !_filesSortAscending;
      } else {
        _filesSortColumn = column;
        _filesSortAscending = true;
      }

      _selectedPatientFiles.sort((a, b) {
        final fileA = a['Files'];
        final fileB = b['Files'];
        dynamic aValue;
        dynamic bValue;

        switch (column) {
          case 'filename':
            aValue = (fileA['filename'] ?? '').toLowerCase();
            bValue = (fileB['filename'] ?? '').toLowerCase();
            break;
          case 'category':
            aValue = (fileA['category'] ?? '').toLowerCase();
            bValue = (fileB['category'] ?? '').toLowerCase();
            break;
          case 'file_type':
            aValue = (fileA['file_type'] ?? '').toLowerCase();
            bValue = (fileB['file_type'] ?? '').toLowerCase();
            break;
          case 'uploader':
            final uploaderA = fileA['uploader'];
            final uploaderB = fileB['uploader'];
            aValue = uploaderA != null
                ? '${uploaderA['Person']['first_name']} ${uploaderA['Person']['last_name']}'
                    .toLowerCase()
                : '';
            bValue = uploaderB != null
                ? '${uploaderB['Person']['first_name']} ${uploaderB['Person']['last_name']}'
                    .toLowerCase()
                : '';
            break;
          case 'uploaded_at':
            aValue =
                DateTime.tryParse(fileA['uploaded_at'] ?? '') ?? DateTime(1970);
            bValue =
                DateTime.tryParse(fileB['uploaded_at'] ?? '') ?? DateTime(1970);
            break;
          default:
            return 0;
        }

        final comparison = aValue is DateTime
            ? aValue.compareTo(bValue)
            : aValue.toString().compareTo(bValue.toString());
        return _filesSortAscending ? comparison : -comparison;
      });
    });
  }

  Widget _buildSortableHeader(String label, String column, bool isFilesTable) {
    final isSorted = isFilesTable
        ? _filesSortColumn == column
        : _patientsSortColumn == column;
    final isAscending =
        isFilesTable ? _filesSortAscending : _patientsSortAscending;

    return InkWell(
      onTap: () {
        if (isFilesTable) {
          _sortFiles(column);
        } else {
          _sortPatients(column);
        }
      },
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          if (isSorted)
            Icon(
              isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: PatientsTheme.primaryGreen,
            )
          else
            const Icon(
              Icons.unfold_more,
              size: 16,
              color: PatientsTheme.textGray,
            ),
        ],
      ),
    );
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
            image,
            blood_type,
            allergies,
            medical_conditions,
            disabilities
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
          revoked_at,
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
            deleted_at,
            uploader:User!uploaded_by(
              email,
              Person!person_id(
                first_name,
                last_name
              )
            )
          )
        ''')
          .or('and(shared_by_user_id.eq.$currentDoctorUserId,shared_with_user_id.eq.$patientUserId),and(shared_by_user_id.eq.$patientUserId,shared_with_user_id.eq.$currentDoctorUserId),and(shared_by_user_id.eq.$patientUserId,shared_with_doctor.eq.$currentDoctorUserId)')
          .is_('revoked_at', null) // Filter out revoked shares
          .order('shared_at', ascending: false);

      print(
          'DEBUG: Doctor user_id: $currentDoctorUserId, Patient user_id: $patientUserId');
      print(
          'DEBUG: Found ${allShares.length} file shares between doctor and patient');

      // Filter out deleted files and convert to list
      List<Map<String, dynamic>> filesList = [];
      for (var share in allShares) {
        final shareMap = Map<String, dynamic>.from(share as Map);
        final file = shareMap['Files'] as Map<String, dynamic>?;

        // Check if file exists and is not deleted
        if (file != null && file['deleted_at'] == null) {
          filesList.add(shareMap);
          print(
              'DEBUG: Share - shared_by: ${shareMap['shared_by_user_id']}, shared_with: ${shareMap['shared_with_user_id']}');
        } else {
          print('DEBUG: Skipping share - file is deleted or null');
        }
      }

      setState(() {
        _selectedPatientFiles = filesList;
        _loadingFiles = false;
      });

      print(
          'Loaded ${filesList.length} files for this patient (after filtering deleted/revoked)');
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

  Future<void> _loadPatientDetails() async {
    if (_selectedPatient == null) return;

    setState(() => _loadingDetails = true);

    try {
      final patientId = _selectedPatient!['patient_id']?.toString() ?? '';

      if (patientId.isEmpty) {
        throw Exception('No valid patient ID found');
      }

      // Load assigned doctors for this patient
      final assignments = await Supabase.instance.client
          .from('Doctor_User_Assignment')
          .select('doctor_id')
          .eq('patient_id', patientId)
          .eq('status', 'active');

      if (assignments.isNotEmpty) {
        final doctorIds =
            assignments.map((a) => a['doctor_id'].toString()).toSet().toList();

        final doctorResponse =
            await Supabase.instance.client.from('Organization_User').select('''
            id,
            position,
            department,
            User!inner(
              Person!inner(
                first_name,
                last_name,
                image
              )
            )
          ''').in_('id', doctorIds);

        final List<Map<String, dynamic>> doctors = [];
        for (final doctor in doctorResponse) {
          final person = doctor['User']['Person'];
          final doctorName = person != null &&
                  person['first_name'] != null &&
                  person['last_name'] != null
              ? '${person['first_name']} ${person['last_name']}'
              : 'Dr. ${doctor['position'] ?? 'Unknown'}';

          doctors.add({
            'id': doctor['id'],
            'name': doctorName,
            'position': doctor['position'] ?? 'Medical Staff',
            'department': doctor['department'] ?? 'General',
            'image': person['image'],
          });
        }

        setState(() {
          _assignedDoctors = doctors;
        });
      }

      setState(() => _loadingDetails = false);
    } catch (e) {
      print('Error loading patient details: $e');
      setState(() => _loadingDetails = false);
      _showSnackBar('Error loading patient details: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _selectedPatient == null
        ? _buildPatientsListView()
        : _buildPatientProfileView();
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
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: PatientsTheme.darkGray),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                    CircularProgressIndicator(
                        color: PatientsTheme.primaryGreen),
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
                    Text('No patients assigned',
                        style: TextStyle(fontSize: 18)),
                    SizedBox(height: 8),
                    Text(
                      'Patients will appear here once assigned to you',
                      style: TextStyle(
                          fontSize: 14, color: PatientsTheme.textGray),
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

  Widget _buildPatientAvatar(Map<String, dynamic> person,
      {double radius = 16}) {
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: _buildSortableHeader('Patient', 'name', false)),
                Expanded(
                    flex: 2,
                    child: _buildSortableHeader('Contact', 'email', false)),
                Expanded(
                    child: Center(
                  child: _buildSortableHeader('Status', 'status', false),
                )),
                const SizedBox(width: 100),
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
                      color: index < _patients.length - 1
                          ? Colors.grey.shade200
                          : Colors.transparent,
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  person['contact_number'] ?? 'No phone',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: PatientsTheme.textGray),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
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

                    // Status (Centered)
                    // Status (flex: 1)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          patient['status']?.toUpperCase() ?? 'UNKNOWN',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.left,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                    // Actions
                    SizedBox(
                      width: 100,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedPatient = patient;
                                _selectedTabIndex = 0;
                              });
                              final patientId =
                                  patient['patient_id'].toString();
                              _loadPatientDetails();
                              _loadAllFilesForPatient(patientId);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PatientsTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: const Text('View',
                                style: TextStyle(fontSize: 13)),
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

  Widget _buildPatientProfileView() {
    final person = _selectedPatient!['User']['Person'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
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
                        _assignedDoctors = [];
                        _selectedTabIndex = 0;
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                    style: IconButton.styleFrom(
                      foregroundColor: PatientsTheme.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildPatientAvatar(person, radius: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _buildFullName(person),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: PatientsTheme.darkGray,
                        ),
                      ),
                      Text(
                        _selectedPatient!['User']['email'] ?? '',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Tab Navigation
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                _buildTabButton('Profile', 0, Icons.person_outline),
                _buildTabButton('Medical Files', 1, Icons.folder_outlined),
                _buildTabButton(
                    'Medical Info', 2, Icons.medical_services_outlined),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Tab Content
          if (_selectedTabIndex == 0) _buildProfileTab(),
          if (_selectedTabIndex == 1) _buildFilesTab(),
          if (_selectedTabIndex == 2) _buildMedicalInfoTab(),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index, IconData icon) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? PatientsTheme.primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : PatientsTheme.textGray,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : PatientsTheme.textGray,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    if (_loadingDetails) {
      return Container(
        height: 400,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: PatientsTheme.primaryGreen),
        ),
      );
    }

    final person = _selectedPatient!['User']['Person'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
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
          child: Column(
            children: [
              _buildPatientAvatar(person, radius: 50),
              const SizedBox(height: 16),
              Text(
                _buildFullName(person),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: PatientsTheme.darkGray,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: PatientsTheme.approvedGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _selectedPatient!['status']?.toUpperCase() ?? 'ACTIVE',
                  style: const TextStyle(
                    fontSize: 14,
                    color: PatientsTheme.approvedGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Contact Information',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PatientsTheme.darkGray,
          ),
        ),
        const SizedBox(height: 12),

        _buildInfoCard(
          'Email Address',
          _selectedPatient!['User']['email'] ?? 'Not specified',
          Icons.email,
          PatientsTheme.lightGreen,
        ),
        const SizedBox(height: 12),

        _buildInfoCard(
          'Contact Number',
          person['contact_number'] ?? 'Not specified',
          Icons.phone,
          Colors.blue,
        ),
        const SizedBox(height: 12),

        _buildInfoCard(
          'Address',
          person['address'] ?? 'Not specified',
          Icons.location_on,
          PatientsTheme.orange,
          isMultiline: true,
        ),

        const SizedBox(height: 24),

        Row(
          children: [
            const Icon(Icons.medical_services,
                size: 18, color: PatientsTheme.primaryGreen),
            const SizedBox(width: 8),
            const Text(
              'Care Team',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: PatientsTheme.darkGray,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_assignedDoctors.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: PatientsTheme.textGray),
                SizedBox(width: 8),
                Text('No other doctors assigned',
                    style: TextStyle(color: PatientsTheme.textGray)),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _assignedDoctors.length,
              itemBuilder: (context, index) {
                final doctor = _assignedDoctors[index];
                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: index < _assignedDoctors.length - 1
                            ? Colors.grey.shade200
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: PatientsTheme.primaryGreen,
                      radius: 20,
                      child: Text(
                        doctor['name']?[0] ?? 'D',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    title: Text(
                      doctor['name'] ?? 'Unknown Doctor',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (doctor['position'] != null)
                          Text(
                            doctor['position'],
                            style: const TextStyle(
                                fontSize: 12, color: PatientsTheme.textGray),
                          ),
                        if (doctor['department'] != null)
                          Text(
                            doctor['department'],
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: PatientsTheme.approvedGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 11,
                          color: PatientsTheme.approvedGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFilesTab() {
    if (_loadingFiles) {
      return Container(
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
      );
    }

    if (_selectedPatientFiles.isEmpty) {
      return Container(
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
      );
    }

    return _buildFilesTable();
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: _buildSortableHeader('File Name', 'filename', true)),
                Expanded(
                    flex: 2,
                    child: _buildSortableHeader('Category', 'category', true)),
                Expanded(
                    child: _buildSortableHeader('Type', 'file_type', true)),
                Expanded(
                    flex: 2,
                    child:
                        _buildSortableHeader('Uploaded By', 'uploader', true)),
                Expanded(
                    child: _buildSortableHeader('Date', 'uploaded_at', true)),
                const SizedBox(width: 100),
              ],
            ),
          ),

          // Files list
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
              final createdAt = DateTime.tryParse(file['uploaded_at'] ?? '') ??
                  DateTime.now();
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
                              color:
                                  _getFileTypeColor(fileType).withOpacity(0.1),
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Category
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
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

                    // File type
                    Expanded(
                      child: Text(
                        fileType.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Uploader name
                    Expanded(
                      flex: 2,
                      child: Text(
                        uploaderName,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Upload date
                    Expanded(
                      child: Text(
                        _formatDate(createdAt),
                        style: const TextStyle(
                            fontSize: 12, color: PatientsTheme.textGray),
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
                            icon: const Icon(Icons.more_vert,
                                size: 18, color: PatientsTheme.textGray),
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
                              if (_canDeleteFile(file))
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete,
                                          color: Colors.red, size: 16),
                                      SizedBox(width: 8),
                                      Text('Delete',
                                          style: TextStyle(color: Colors.red)),
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

  Widget _buildMedicalInfoTab() {
    if (_loadingDetails) {
      return Container(
        height: 400,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: PatientsTheme.primaryGreen),
        ),
      );
    }

    final person = _selectedPatient!['User']['Person'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Medical Information',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PatientsTheme.darkGray,
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Blood Type',
          person['blood_type'] ?? 'Not specified',
          Icons.bloodtype,
          Colors.red,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Allergies',
          person['allergies'] ?? 'None specified',
          Icons.warning,
          PatientsTheme.orange,
          isMultiline: true,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Medical Conditions',
          person['medical_conditions'] ?? 'None specified',
          Icons.medical_services,
          Colors.purple,
          isMultiline: true,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Disabilities',
          person['disabilities'] ?? 'None specified',
          Icons.accessibility,
          Colors.blue,
          isMultiline: true,
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    String title,
    String content,
    IconData icon,
    Color iconColor, {
    bool isMultiline = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment:
            isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: PatientsTheme.textGray,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: PatientsTheme.darkGray,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: isMultiline ? null : 2,
                  overflow: isMultiline ? null : TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods

  bool _canDeleteFile(Map<String, dynamic> file) {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null || currentUser.email == null) {
        return false;
      }

      final uploader = file['uploader'];
      if (uploader == null) {
        return false;
      }

      String? uploaderEmail;
      if (uploader is Map) {
        uploaderEmail = uploader['email'] as String?;
      }

      if (uploaderEmail == null) {
        return false;
      }

      return currentUser.email == uploaderEmail;
    } catch (e) {
      print('Error checking file delete permission: $e');
      return false;
    }
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
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
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
    final uploadedAt =
        DateTime.tryParse(file['uploaded_at'] ?? '') ?? DateTime.now();
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
                color:
                    _getFileTypeColor(file['file_type'] ?? '').withOpacity(0.1),
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
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: PatientsTheme.darkGray),
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
              _buildDetailRow(
                  'Category',
                  (file['category'] ?? 'other')
                      .replaceAll('_', ' ')
                      .toUpperCase()),
              _buildDetailRow(
                  'File Type', (file['file_type'] ?? 'unknown').toUpperCase()),
              _buildDetailRow(
                  'File Size', _formatFileSize(file['file_size'] ?? 0)),
              _buildDetailRow('Uploaded By', uploaderName),
              _buildDetailRow('Uploaded At', _formatDateTime(uploadedAt)),
              _buildDetailRow('File ID', file['id'] ?? 'Unknown'),
              if (file['ipfs_cid'] != null)
                _buildDetailRow('IPFS CID', file['ipfs_cid'], monospace: true),
              if (file['sha256_hash'] != null)
                _buildDetailRow('SHA256 Hash', file['sha256_hash'],
                    monospace: true),
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
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'Delete File',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to delete this file?',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file['filename'] ?? 'Unknown File',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This action will:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Delete all encryption keys',
                    style: TextStyle(fontSize: 11),
                  ),
                  const Text(
                    '• Revoke all file shares',
                    style: TextStyle(fontSize: 11),
                  ),
                  const Text(
                    '• Mark the file as deleted',
                    style: TextStyle(fontSize: 11),
                  ),
                  const Text(
                    '• Log deletion to Hive blockchain',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Close confirmation dialog
              Navigator.pop(dialogContext);

              // Check if the original context is still valid before proceeding
              if (!context.mounted) return;

              // Call delete with the original context
              await FileDeleteService.deleteFile(
                context: context,
                file: file,
                showSnackBar: _showSnackBar,
                onDeleteSuccess: () {
                  // Reload files after successful deletion
                  if (_selectedPatient != null) {
                    _loadAllFilesForPatient(
                        _selectedPatient!['patient_id'].toString());
                  }
                },
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
