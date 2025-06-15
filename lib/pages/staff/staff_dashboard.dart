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
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
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
        title: const Text('File Upload Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'File: $fileName',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name *',
                  hintText: 'Enter a descriptive name for the file',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add notes about this file (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Medical Category *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
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
            child: const Text('Cancel'),
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
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Upload File'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showFileNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'File Name',
            hintText: 'Enter file name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Upload'),
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
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
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
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_organizationName),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => _showSnackBar('Notifications coming soon!'),
          ),
          PopupMenuButton<String>(
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
                  leading: Icon(Icons.person),
                  title: Text('Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Sign Out', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
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
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            if (index == 1)
              _loadPatients(); // Refresh patients when tab is selected
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group),
            label: 'Groups',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Tasks',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : 'S',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _userName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Quick Stats
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.people, size: 40, color: Colors.blue),
                        const SizedBox(height: 8),
                        Text(
                          '${_patients.length}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text('Patients'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.folder, size: 40, color: Colors.green),
                        const SizedBox(height: 8),
                        const Text(
                          '0',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text('Files Today'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Quick Actions
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              _buildQuickActionCard(
                'View Patients',
                Icons.people,
                Colors.blue,
                () => setState(() => _selectedIndex = 1),
              ),
              _buildQuickActionCard(
                'Upload File',
                Icons.upload_file,
                Colors.green,
                () => _showSnackBar('Select a patient first to upload files'),
              ),
              _buildQuickActionCard(
                'Secure Share',
                Icons.security,
                Colors.orange,
                () => _showSnackBar('Blockchain sharing coming soon!'),
              ),
              _buildQuickActionCard(
                'IPFS Storage',
                Icons.cloud,
                Colors.purple,
                () => _showSnackBar('IPFS integration coming soon!'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatientsTab() {
    if (_selectedPatient != null) {
      return _buildPatientDetailsView();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'My Patients',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadPatients,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingPatients
              ? const Center(child: CircularProgressIndicator())
              : _patients.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline,
                              size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No Patients Assigned',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          Text(
                            'Patients will appear here when assigned to you',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _patients.length,
                      itemBuilder: (context, index) {
                        final patient = _patients[index];
                        // Updated path to access Person data through User
                        final person = patient['User']['Person'];
                        final fullName =
                            '${person['first_name']} ${person['middle_name'] ?? ''} ${person['last_name']}'
                                .trim();

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                fullName.isNotEmpty
                                    ? fullName[0].toUpperCase()
                                    : 'P',
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(fullName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (person['email'] != null)
                                  Text(person['email']),
                                if (person['contact_number'] != null)
                                  Text(person['contact_number']),
                              ],
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () {
                              setState(() {
                                _selectedPatient = patient;
                              });
                              // Convert patient_id to string if it's an int
                              final patientId =
                                  patient['patient_id'].toString();
                              _loadPatientFiles(patientId);
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
    // Updated path to access Person data through User
    final person = _selectedPatient!['User']['Person'];
    final fullName =
        '${person['first_name']} ${person['middle_name'] ?? ''} ${person['last_name']}'
            .trim();

    return Column(
      children: [
        // Patient Header
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _selectedPatient = null;
                        _selectedPatientFiles = [];
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.blue.shade200,
                    child: Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : 'P',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
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
                        if (person['email'] != null) Text(person['email']),
                        if (person['contact_number'] != null)
                          Text(person['contact_number']),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _uploadFileForPatient,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Files Section
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Medical Files',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loadingFiles
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedPatientFiles.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_open,
                                      size: 80, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text(
                                    'No Files Available',
                                    style: TextStyle(
                                        fontSize: 18, color: Colors.grey),
                                  ),
                                  Text(
                                    'Upload files to share with this patient',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _selectedPatientFiles.length,
                              itemBuilder: (context, index) {
                                final fileShare = _selectedPatientFiles[index];
                                final file = fileShare['Files'];

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.green.shade100,
                                      child: Icon(
                                        _getFileIcon(file['file_type']),
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                    title: Text(file['name']),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (file['description'] != null)
                                          Text(file['description']),
                                        Text(
                                          'Type: ${file['file_type']}',
                                          style: TextStyle(
                                              color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'download':
                                            _showSnackBar(
                                                'Download from IPFS coming soon!');
                                            break;
                                          case 'share':
                                            _showSnackBar(
                                                'Secure sharing coming soon!');
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'download',
                                          child: ListTile(
                                            leading: Icon(Icons.download),
                                            title: Text('Download'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'share',
                                          child: ListTile(
                                            leading: Icon(Icons.share),
                                            title: Text('Share'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildGroupsTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Groups & Teams',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Team collaboration features\ncoming soon',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Task Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Task assignment and tracking\nfeatures coming soon',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar('Edit Profile coming soon!');
            },
            child: const Text('Edit Profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
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
            child: Text(value.isEmpty ? 'Not set' : value),
          ),
        ],
      ),
    );
  }
}
