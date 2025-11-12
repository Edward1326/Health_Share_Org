import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:health_share_org/functions/files/upload_file.dart';
import 'package:health_share_org/functions/files/decrypt_file.dart';

// Theme colors matching the patients dashboard
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

class PatientProfileView extends StatefulWidget {
  final Map<String, dynamic> patientData;
  final VoidCallback onBack;

  const PatientProfileView({
    Key? key,
    required this.patientData,
    required this.onBack,
  }) : super(key: key);

  @override
  State<PatientProfileView> createState() => _PatientProfileViewState();
}

class _PatientProfileViewState extends State<PatientProfileView> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? patientDetails;
  List<Map<String, dynamic>> selectedPatientFiles = [];
  List<Map<String, dynamic>> assignedDoctors = [];
  bool isLoadingDetails = true;
  bool isLoadingFiles = true;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPatientDetails();
    _loadPatientFiles();
  }

  Future<void> _loadPatientDetails() async {
    try {
      setState(() => isLoadingDetails = true);

      final patientId = widget.patientData['patient_id']?.toString() ?? '';
      final userId = widget.patientData['User']?['id']?.toString() ?? '';

      if (patientId.isEmpty) {
        throw Exception('No valid patient ID found');
      }

      // Load patient personal information
      Map<String, dynamic>? personData;
      if (userId.isNotEmpty) {
        try {
          final personResponse = await supabase
              .from('User')
              .select('Person!inner(*)')
              .eq('id', userId)
              .single();

          if (personResponse['Person'] != null) {
            personData = personResponse['Person'];
          }
        } catch (e) {
          print('Error loading person data: $e');
        }
      }

      // Load assigned doctors for this patient
      final assignments = await supabase
          .from('Doctor_User_Assignment')
          .select('doctor_id')
          .eq('patient_id', patientId)
          .eq('status', 'active');

      if (assignments.isNotEmpty) {
        final doctorIds =
            assignments.map((a) => a['doctor_id'].toString()).toSet().toList();

        final doctorResponse =
            await supabase.from('Organization_User').select('''
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
        assignedDoctors = doctors;
      }

      setState(() {
        patientDetails = {
          ...widget.patientData,
          if (personData != null) ...personData,
        };
        isLoadingDetails = false;
      });
    } catch (e) {
      print('Error loading patient details: $e');
      setState(() => isLoadingDetails = false);
      _showSnackBar('Error loading patient details: $e');
    }
  }

  Future<void> _loadPatientFiles() async {
    setState(() => isLoadingFiles = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null || currentUser.email == null) {
        throw Exception('No authenticated user found');
      }

      final userEmail = currentUser.email!;

      final currentUserResponse = await supabase
          .from('User')
          .select('id')
          .eq('email', userEmail)
          .single();

      final currentDoctorUserId = currentUserResponse['id'];

      final patientUserId = widget.patientData['User']?['id'];

      if (patientUserId == null) {
        throw Exception('Patient user ID not found');
      }

      final allShares = await supabase
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
                email,
                Person!person_id(
                  first_name,
                  last_name
                )
              )
            )
          ''')
          .or('and(shared_by_user_id.eq.$currentDoctorUserId,shared_with_user_id.eq.$patientUserId),and(shared_by_user_id.eq.$patientUserId,shared_with_user_id.eq.$currentDoctorUserId),and(shared_by_user_id.eq.$patientUserId,shared_with_doctor.eq.$currentDoctorUserId)')
          .order('shared_at', ascending: false);

      List<Map<String, dynamic>> filesList = [];
      for (var share in allShares) {
        filesList.add(Map<String, dynamic>.from(share as Map));
      }

      setState(() {
        selectedPatientFiles = filesList;
        isLoadingFiles = false;
      });
    } catch (e) {
      print('Error loading files: $e');
      setState(() => isLoadingFiles = false);
      _showSnackBar('Error loading files: $e');
    }
  }

  String _getFullName() {
    final person = widget.patientData['User']?['Person'];
    if (person == null) return 'Unknown Patient';

    final firstName = person['first_name'] ?? '';
    final middleName = person['middle_name'] ?? '';
    final lastName = person['last_name'] ?? '';

    if (firstName.isEmpty && lastName.isEmpty) {
      return 'Unknown Patient';
    }

    return '$firstName ${middleName.isNotEmpty ? '$middleName ' : ''}$lastName'
        .trim();
  }

  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null) return 'Not available';
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final year = dateTime.year;
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$day/$month/$year $hour:$minute';
    } catch (e) {
      return 'Invalid date';
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
    final person = widget.patientData['User']?['Person'];

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
                    onPressed: widget.onBack,
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
                        _getFullName(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: PatientsTheme.darkGray,
                        ),
                      ),
                      Text(
                        widget.patientData['User']?['email'] ?? '',
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
                  widget.patientData,
                  _showSnackBar,
                  _loadPatientFiles,
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
    if (isLoadingDetails) {
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

    final person = patientDetails?['User']?['Person'] ??
        widget.patientData['User']?['Person'];

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
                _getFullName(),
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
                  widget.patientData['status']?.toUpperCase() ?? 'ACTIVE',
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

        // Contact Information
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
          widget.patientData['User']?['email'] ?? 'Not specified',
          Icons.email,
          PatientsTheme.lightGreen,
        ),
        const SizedBox(height: 12),

        _buildInfoCard(
          'Contact Number',
          person?['contact_number'] ?? 'Not specified',
          Icons.phone,
          Colors.blue,
        ),
        const SizedBox(height: 12),

        _buildInfoCard(
          'Address',
          person?['address'] ?? 'Not specified',
          Icons.location_on,
          PatientsTheme.orange,
          isMultiline: true,
        ),

        const SizedBox(height: 24),

        // Assigned Doctors Section
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

        if (assignedDoctors.isEmpty)
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
              itemCount: assignedDoctors.length,
              itemBuilder: (context, index) {
                final doctor = assignedDoctors[index];
                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: index < assignedDoctors.length - 1
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
    if (isLoadingFiles) {
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

    if (selectedPatientFiles.isEmpty) {
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

  Widget _buildMedicalInfoTab() {
    if (isLoadingDetails) {
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

    final person = patientDetails?['User']?['Person'] ??
        widget.patientData['User']?['Person'];

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
          person?['blood_type'] ?? 'Not specified',
          Icons.bloodtype,
          Colors.red,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Allergies',
          person?['allergies'] ?? 'None specified',
          Icons.warning,
          PatientsTheme.orange,
          isMultiline: true,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Medical Conditions',
          person?['medical_conditions'] ?? 'None specified',
          Icons.medical_services,
          Colors.purple,
          isMultiline: true,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Disabilities',
          person?['disabilities'] ?? 'None specified',
          Icons.accessibility,
          Colors.blue,
          isMultiline: true,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          'Date of Birth',
          person?['date_of_birth'] != null
              ? _formatDateTime(person!['date_of_birth'])
              : 'Not specified',
          Icons.cake,
          Colors.pink,
        ),
      ],
    );
  }

  Widget _buildPatientAvatar(Map<String, dynamic>? person,
      {double radius = 20}) {
    final imageUrl = person?['image'] as String?;
    final fullName = _getFullName();

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: PatientsTheme.primaryGreen, width: 3),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: PatientsTheme.primaryGreen,
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
                        fontSize: radius * 0.6,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: PatientsTheme.primaryGreen, width: 3),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: PatientsTheme.primaryGreen,
          child: Text(
            _getPatientInitials(fullName),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.6,
            ),
          ),
        ),
      );
    }
  }

  String _getPatientInitials(String fullName) {
    if (fullName.trim().isEmpty) return 'P';
    final names =
        fullName.trim().split(' ').where((name) => name.isNotEmpty).toList();
    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    } else if (names.isNotEmpty && names[0].isNotEmpty) {
      return names[0][0].toUpperCase();
    }
    return 'P';
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

  Widget _buildFilesTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('File Name',
                        style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(
                    child: Text('Category',
                        style: TextStyle(fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('Type',
                        style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(
                    child: Text('Uploaded By',
                        style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(
                    child: Text('Date',
                        style: TextStyle(fontWeight: FontWeight.w500))),
                SizedBox(width: 100),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: selectedPatientFiles.length,
            itemBuilder: (context, index) {
              final fileShare = selectedPatientFiles[index];
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
                      color: index < selectedPatientFiles.length - 1
                          ? Colors.grey.shade200
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
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
                    Expanded(
                      child: Center(
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
                    ),
                    Expanded(
                      child: Text(
                        fileType.toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        uploaderName,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _formatDate(createdAt),
                        style: const TextStyle(
                            fontSize: 12, color: PatientsTheme.textGray),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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

  // Helper methods
  bool _canDeleteFile(Map<String, dynamic> file) {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null || currentUser.email == null) return false;

      final uploader = file['uploader'];
      if (uploader == null) return false;

      String? uploaderEmail;
      if (uploader is Map) {
        uploaderEmail = uploader['email'] as String?;
      }

      if (uploaderEmail == null) return false;
      return currentUser.email == uploaderEmail;
    } catch (e) {
      print('Error checking file delete permission: $e');
      return false;
    }
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
        return PatientsTheme.orange;
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
        return PatientsTheme.orange;
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
                  color: PatientsTheme.darkGray,
                ),
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
              _buildDetailRow(
                  'Uploaded At', _formatDateTime(uploadedAt.toIso8601String())),
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
                foregroundColor: PatientsTheme.primaryGreen),
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
            style:
                TextButton.styleFrom(foregroundColor: PatientsTheme.textGray),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: PatientsTheme.primaryGreen),
        ),
      );

      await supabase.from('Files').delete().eq('id', file['id']);

      if (mounted) Navigator.pop(context);
      _showSnackBar('File deleted successfully');
      _loadPatientFiles();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      print('Error deleting file: $e');
      _showSnackBar('Error deleting file: $e');
    }
  }
}
