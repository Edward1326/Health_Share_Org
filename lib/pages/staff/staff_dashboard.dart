import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:html' as html show InputElement, FileReader;

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({Key? key}) : super(key: key);

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  String _userName = '';
  String _userEmail = '';
  String _organizationName = '';
  String _userPosition = '';
  String _userDepartment = '';
  String _userId = '';
  bool _isLoading = true;
  int _selectedIndex = 0;

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
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Staff Member';
        _userEmail = prefs.getString('user_email') ?? '';
        _organizationName = prefs.getString('organization_name') ?? 'Hospital';
        _userPosition = prefs.getString('user_position') ?? 'Staff';
        _userDepartment = prefs.getString('user_department') ?? '';
        _userId = prefs.getString('user_id') ?? '';
        _isLoading = false;
      });
      _loadPatients();
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loadingPatients = true;
    });

    try {
      // Get the current authenticated user
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null || currentUser.email == null) {
        throw Exception('No authenticated user found');
      }

      final userEmail = currentUser.email!;
      print('DEBUG: Looking up user with email: $userEmail');

      // Step 1: First find the Person record with the email
      final personResponse = await Supabase.instance.client
          .from('Person')
          .select('id')
          .eq('email', userEmail)
          .single(); // Use single() since email should be unique

      print('DEBUG: Person lookup response: $personResponse');

      final personId = personResponse['id'];

      // Step 2: Find the User record linked to this Person
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id')
          .eq('person_id', personId)
          .single(); // Assuming one User per Person

      print('DEBUG: User lookup response: $userResponse');

      final userId = userResponse['id'];

      // Step 3: Find Organization_User records where this user is a Doctor
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

      // Get the Organization_User IDs (these are what should be used as doctor_id)
      final doctorIds =
          doctorLookupResponse.map((doctor) => doctor['id']).toList();
      print('DEBUG: Doctor IDs for assignment lookup: $doctorIds');

      // Step 4: Query Doctor_User_Assignment table
      final response = await Supabase.instance.client
          .from('Doctor_User_Assignment')
          .select('''
      id,
      doctor_id,
      patient_id,
      status,
      assigned_at,
      assigned_by,
      patient_user:User!patient_id(
        id,
        person_id,
        Person!person_id(
          id,
          first_name,
          middle_name,
          last_name,
          email,
          contact_number
        )
      )
    ''')
          .in_('doctor_id', doctorIds)
          .eq('status', 'active');

      print('DEBUG: Patients query response: $response');

      // Transform the response
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

  Future<void> _loadPatientFiles(String patientId) async {
    setState(() {
      _loadingFiles = true;
    });

    try {
      // Get files shared with this patient
      final response = await Supabase.instance.client
          .from('File_Shares')
          .select('''
          id,
          created_at,
          Files!inner(
            id,
            name,
            description,
            file_type,
            category,
            file_url,
            created_at,
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
          .order('created_at', ascending: false);

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

  Future<void> _uploadFileForPatient() async {
    if (_selectedPatient == null) return;

    try {
      // Step 1: Create HTML file input for web compatibility
      final html.InputElement uploadInput = html.InputElement(type: 'file');
      uploadInput.accept = '.pdf,.jpg,.jpeg,.png,.doc,.docx,.txt';
      uploadInput.click();

      // Wait for file selection
      await uploadInput.onChange.first;

      if (uploadInput.files == null || uploadInput.files!.isEmpty) {
        _showSnackBar('No file selected');
        return;
      }

      final file = uploadInput.files!.first;
      final fileName = file.name;
      final fileSize = file.size;
      final fileExtension = fileName.split('.').last.toLowerCase();

      // Step 2: Read file as bytes
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final Uint8List fileBytes = reader.result as Uint8List;

      // Step 3: Show file details dialog and get description
      final fileDetails = await _showFileDetailsDialog(fileName, fileSize);
      if (fileDetails == null) return;

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Row(
            children: [
              CircularProgressIndicator(color: primaryBlue),
              SizedBox(width: 16),
              Text('Uploading file...'),
            ],
          ),
        ),
      );

      // Step 4: Get current user info for uploaded_by field
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        Navigator.pop(context); // Close loading dialog
        _showSnackBar('Authentication error');
        return;
      }

      // Get current user's ID from the database
      final personResponse = await Supabase.instance.client
          .from('Person')
          .select('id')
          .eq('email', currentUser.email!)
          .single();

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id')
          .eq('person_id', personResponse['id'])
          .single();

      final uploaderId = userResponse['id'];

      // Step 5: Upload file to Supabase Storage
      String fileUrl = '';

      try {
        // Upload to Supabase Storage
        final patientId = _selectedPatient!['patient_id'].toString();
        final filePath =
            'patient_files/${patientId}/${DateTime.now().millisecondsSinceEpoch}_$fileName';

        await Supabase.instance.client.storage
            .from('medical-files')
            .uploadBinary(
              filePath,
              fileBytes,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: false,
              ),
            );

        fileUrl = Supabase.instance.client.storage
            .from('medical-files')
            .getPublicUrl(filePath);

        print('File uploaded successfully to: $fileUrl');
      } catch (storageError) {
        print('Storage upload failed: $storageError');
        Navigator.pop(context); // Close loading dialog
        _showSnackBar('Error uploading file to storage: $storageError');
        return;
      }

      // Step 6: Create file record in Files table (without ipfs_hash)
      final fileResponse = await Supabase.instance.client
          .from('Files')
          .insert({
            'name': fileDetails['fileName'],
            'description': fileDetails['description'],
            'file_type': fileExtension,
            'category': fileDetails['category'],
            'file_url': fileUrl,
            'uploaded_by': uploaderId,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final fileId = fileResponse['id'];

      // Step 7: Create File_Shares record to share with patient
      final patientId = _selectedPatient!['patient_id'].toString();

      await Supabase.instance.client.from('File_Shares').insert({
        'file_id': fileId,
        'shared_with_user_id': patientId,
        'shared_by_user_id': uploaderId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Close loading dialog
      Navigator.pop(context);

      // Step 8: Refresh patient files and show success
      await _loadPatientFiles(patientId);
      _showSnackBar('File uploaded and shared successfully!');
    } catch (e) {
      // Close loading dialog if open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      print('Error uploading file: $e');
      _showSnackBar('Error uploading file: $e');
    }
  }

  Future<Map<String, String>?> _showFileDetailsDialog(
      String fileName, int fileSize) async {
    final nameController = TextEditingController(text: fileName);
    final descriptionController = TextEditingController();
    String selectedCategory = 'medical_report';

    final categories = [
      'medical_report',
      'lab_result',
      'prescription',
      'x_ray',
      'mri_scan',
      'ct_scan',
      'ultrasound',
      'blood_test',
      'discharge_summary',
      'consultation_notes',
      'other'
    ];

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('File Upload Details',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: primaryBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'File: $fileName',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                            style:
                                const TextStyle(color: darkGray, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Display Name *',
                  hintText: 'Enter a descriptive name for the file',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryBlue, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.edit, color: primaryBlue),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add notes about this file (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryBlue, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.notes, color: primaryBlue),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Medical Category *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryBlue, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.category, color: primaryBlue),
                ),
                items: categories.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category
                        .replaceAll('_', ' ')
                        .split(' ')
                        .map(
                            (word) => word[0].toUpperCase() + word.substring(1))
                        .join(' ')),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    selectedCategory = value;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: darkGray)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Please enter a display name for the file')),
                );
                return;
              }
              Navigator.pop(context, {
                'fileName': nameController.text.trim(),
                'description': descriptionController.text.trim(),
                'category': selectedCategory,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Upload File'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      final shouldSignOut = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: darkGray)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: coral,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      );

      if (shouldSignOut == true) {
        await Supabase.instance.client.auth.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      print('Error signing out: $e');
      _showSnackBar('Error signing out. Please try again.');
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
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: lightGray,
        body: Center(child: CircularProgressIndicator(color: primaryBlue)),
      );
    }

    return Scaffold(
      backgroundColor: lightGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _organizationName,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () => _showSnackBar('Notifications coming soon!'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _showProfileDialog();
                  break;
                case 'settings':
                  _showSnackBar('Settings coming soon!');
                  break;
                case 'signout':
                  _signOut();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: coral),
                  title: Text('Sign Out', style: TextStyle(color: coral)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardTab(),
          _buildPatientsTab(),
          _buildGroupsTab(),
          _buildTasksTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, -2),
            )
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: primaryBlue,
          unselectedItemColor: darkGray,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
              if (index == 1) _loadPatients();
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Patients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.group_outlined),
              activeIcon: Icon(Icons.group),
              label: 'Groups',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment),
              label: 'Tasks',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Text(
                  'Hello,',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _userName.split(' ').first,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '👋',
                      style: TextStyle(fontSize: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$_userPosition • $_userDepartment',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Quick Action Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    'Patients',
                    Icons.people,
                    primaryBlue,
                    () => setState(() => _selectedIndex = 1),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionCard(
                    'Categories',
                    Icons.category,
                    coral,
                    () => _showSnackBar('Categories coming soon!'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionCard(
                    'Medicine',
                    Icons.medical_services,
                    orange,
                    () => _showSnackBar('Medicine tracking coming soon!'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Recent Check Ups Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Check Ups',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedIndex = 1),
                  child: const Text(
                    'View All',
                    style: TextStyle(color: primaryBlue),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Patient List Preview
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _patients.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No Recent Check Ups',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _patients.length > 5 ? 5 : _patients.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Colors.grey[200],
                    ),
                    itemBuilder: (context, index) {
                      final patient = _patients[index];
                      final person = patient['User']['Person'];
                      final fullName =
                          '${person['first_name']} ${person['middle_name'] ?? ''} ${person['last_name']}'
                              .trim();

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getPatientAvatarColor(index),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              _getPatientIcon(index),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        title: Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          _getPatientSubtitle(index),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: darkGray,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedIndex = 1;
                            _selectedPatient = patient;
                          });
                          final patientId = patient['patient_id'].toString();
                          _loadPatientFiles(patientId);
                        },
                      );
                    },
                  ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildActionCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientsTab() {
    return Column(
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
    );
  }

  Widget _buildPatientsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _patients.length,
      itemBuilder: (context, index) {
        final patient = _patients[index];
        final person = patient['User']['Person'];
        final fullName =
            '${person['first_name']} ${person['middle_name'] ?? ''} ${person['last_name']}'
                .trim();

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
                  person['email'] ?? '',
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
              _loadPatientFiles(patientId);
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
                      person['email'] ?? '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _uploadFileForPatient,
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
    final fileName = file['name'] ?? 'Unknown File';
    final description = file['description'] ?? '';
    final createdAt =
        DateTime.tryParse(file['created_at'] ?? '') ?? DateTime.now();
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
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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

  Widget _buildGroupsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Groups Feature',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming Soon!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Tasks & Reminders',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming Soon!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  Color _getPatientAvatarColor(int index) {
    final colors = [primaryBlue, coral, orange, Colors.purple, Colors.teal];
    return colors[index % colors.length];
  }

  IconData _getPatientIcon(int index) {
    final icons = [
      Icons.person,
      Icons.favorite,
      Icons.medical_services,
      Icons.healing,
      Icons.health_and_safety
    ];
    return icons[index % icons.length];
  }

  String _getPatientSubtitle(int index) {
    final subtitles = [
      'Last visit: 2 days ago',
      'Check-up pending',
      'Follow-up required',
      'All clear',
      'Medication review'
    ];
    return subtitles[index % subtitles.length];
  }

  String _getPatientInitials(String fullName) {
    final names = fullName.split(' ');
    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    } else if (names.isNotEmpty) {
      return names[0][0].toUpperCase();
    }
    return 'P';
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
        return Colors.indigo;
      default:
        return Colors.grey;
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
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'medical_report':
        return Colors.blue;
      case 'lab_result':
        return Colors.green;
      case 'prescription':
        return Colors.orange;
      case 'x_ray':
      case 'mri_scan':
      case 'ct_scan':
        return Colors.purple;
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
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showFileActions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility, color: primaryBlue),
              title: const Text('View File'),
              onTap: () {
                Navigator.pop(context);
                _viewFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: primaryBlue),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: primaryBlue),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                _shareFile(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _viewFile(Map<String, dynamic> file) {
    final fileUrl = file['file_url'];
    if (fileUrl != null) {
      // Open file URL in browser or viewer
      _showSnackBar('Opening file: ${file['name']}');
    }
  }

  void _downloadFile(Map<String, dynamic> file) {
    _showSnackBar('Download started: ${file['name']}');
  }

  void _shareFile(Map<String, dynamic> file) {
    _showSnackBar('Share feature coming soon!');
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Profile Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileRow('Name', _userName),
            _buildProfileRow('Email', _userEmail),
            _buildProfileRow('Position', _userPosition),
            _buildProfileRow('Department', _userDepartment),
            _buildProfileRow('Organization', _organizationName),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: primaryBlue)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'Not provided',
              style: TextStyle(
                color: value.isNotEmpty ? Colors.black : Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
