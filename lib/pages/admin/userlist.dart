// User/Patient List Page with Persistent Doctor Assignment Feature
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> availableDoctors = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // Load all data in sequence
  Future<void> _loadAllData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await _loadUsersFromSupabase();
      await _loadDoctorsFromSupabase();
      await _loadAssignmentsFromDatabase();
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading data: $e';
        isLoading = false;
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadUsersFromSupabase() async {
    try {
      print('=== DEBUG: Starting user loading process ===');

      // First, get all Organization_User records to identify employees
      print('Step 1: Fetching Organization_User records...');
      final orgUsersResponse =
          await supabase.from('Organization_User').select('*');

      print('Organization_User records found: ${orgUsersResponse.length}');

      // Extract user IDs from Organization_User table
      final employeeUserIds = <dynamic>{};
      for (var orgUser in orgUsersResponse) {
        if (orgUser['user_id'] != null) {
          employeeUserIds.add(orgUser['user_id']);
        }
      }

      print('Employee user IDs extracted: $employeeUserIds');

      // Fetch all users from the User table
      print('\nStep 2: Fetching User records...');
      final usersResponse = await supabase.from('User').select('*');

      print('User records found: ${usersResponse.length}');

      if (usersResponse.isEmpty) {
        print('No User records found!');
        setState(() {
          users = [];
        });
        return;
      }

      // Filter users - exclude employees
      final List<Map<String, dynamic>> potentialPatients = [];

      for (var user in usersResponse) {
        final isEmployee = employeeUserIds.contains(user['id']);

        if (!isEmployee) {
          potentialPatients.add(user);
        }
      }

      print('Filtered patient users: ${potentialPatients.length}');

      // Extract person IDs from patient users only
      final personIds = potentialPatients
          .map((user) => user['person_id'])
          .where((id) => id != null)
          .toList();

      print('Person IDs to fetch: $personIds');

      // Fetch corresponding Person records
      print('\nStep 3: Fetching Person records...');
      final personsResponse =
          await supabase.from('Person').select('*').in_('id', personIds);

      print('Person records found: ${personsResponse.length}');

      // Create a map for quick person lookup
      final Map<dynamic, Map<String, dynamic>> personsMap = {};
      for (var person in personsResponse) {
        personsMap[person['id']] = person;
      }

      // Build the users list (only patients now)
      print('\nStep 4: Building final users list...');
      final List<Map<String, dynamic>> loadedUsers = [];

      for (var user in potentialPatients) {
        final person = personsMap[user['person_id']];

        if (person != null) {
          final fullName = person['first_name'] != null &&
                  person['last_name'] != null
              ? '${person['first_name']} ${person['last_name']}'
              : person['first_name'] ?? person['last_name'] ?? 'Unknown User';

          final userMap = {
            'id': user['id'].toString(),
            'name': fullName,
            'type': 'Patient',
            'email': person['email'] ?? '',
            'phone': person['contact_number'] ?? '',
            'address': person['address'] ?? '',
            'lastVisit': user['created_at'] != null
                ? DateTime.parse(user['created_at']).toString().split(' ')[0]
                : '2024-01-01',
            'assignedDoctor': null,
            'assignedDoctorId': null,
            'assignmentId': null,
          };

          loadedUsers.add(userMap);
        }
      }

      print('\n=== DEBUG: User Loading Results ===');
      print('Total patients loaded: ${loadedUsers.length}');

      setState(() {
        users = loadedUsers;
      });
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading users ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _loadDoctorsFromSupabase() async {
    try {
      print('=== DEBUG: Fetching Doctor/Employee records ===');

      // Fetch employees from Organization_User table
      final orgUsersResponse =
          await supabase.from('Organization_User').select('*');

      print('Organization_User records found: ${orgUsersResponse.length}');

      if (orgUsersResponse.isEmpty) {
        setState(() {
          availableDoctors = [];
        });
        return;
      }

      // Extract user IDs from Organization_User
      final userIds = orgUsersResponse
          .map((item) => item['user_id'])
          .where((id) => id != null)
          .toList();

      print('User IDs from Organization_User: $userIds');

      // Get User records that match the Organization_User.user_id
      final usersResponse =
          await supabase.from('User').select('*').in_('id', userIds);
      print('User records found: ${usersResponse.length}');

      // Extract person_ids from the User records
      final personIds = usersResponse
          .map((user) => user['person_id'])
          .where((id) => id != null)
          .toList();

      print('Person IDs to fetch: $personIds');

      // Get Person records using the person_ids
      final personsResponse =
          await supabase.from('Person').select('*').in_('id', personIds);
      print('Person records found: ${personsResponse.length}');

      // Create lookup maps
      final Map<dynamic, Map<String, dynamic>> usersMap = {};
      for (var user in usersResponse) {
        usersMap[user['id']] = user;
      }

      final Map<dynamic, Map<String, dynamic>> personsMap = {};
      for (var person in personsResponse) {
        personsMap[person['id']] = person;
      }

      // Build the doctors list
      final List<Map<String, dynamic>> loadedDoctors = [];

      print('\n=== DEBUG: Processing each Organization_User record ===');

      for (var orgUser in orgUsersResponse) {
        final user = usersMap[orgUser['user_id']];
        final person = user != null ? personsMap[user['person_id']] : null;

        final position = orgUser['position']?.toString().toLowerCase() ?? '';
        final department =
            orgUser['department']?.toString().toLowerCase() ?? '';

        print('Processing employee:');
        print('  - Position: ${orgUser['position']}');
        print('  - Department: ${orgUser['department']}');

        // Doctor identification
        bool isDoctor = false;

        // Check position field
        if (position.contains('doctor') ||
            position.contains('dr.') ||
            position.contains('dr ') ||
            position.contains('physician') ||
            position.contains('specialist') ||
            position.contains('surgeon') ||
            position.contains('md') ||
            position.contains('medical')) {
          isDoctor = true;
          print('  - Identified as doctor by POSITION: "$position"');
        }

        // Check department field
        if (department.contains('medical') ||
            department.contains('clinical') ||
            department.contains('surgery') ||
            department.contains('cardiology') ||
            department.contains('neurology') ||
            department.contains('pediatrics') ||
            department.contains('internal medicine') ||
            department.contains('emergency')) {
          isDoctor = true;
          print('  - Identified as doctor by DEPARTMENT: "$department"');
        }

        if (isDoctor) {
          String doctorName = 'Unknown Doctor';

          if (person != null) {
            doctorName =
                person['first_name'] != null && person['last_name'] != null
                    ? '${person['first_name']} ${person['last_name']}'
                    : person['first_name'] ??
                        person['last_name'] ??
                        'Dr. ${orgUser['position']}';
          } else {
            doctorName = 'Dr. ${orgUser['position'] ?? 'Unknown'}';
          }

          final doctorMap = {
            'id': orgUser['id'].toString(),
            'name': doctorName,
            'position': orgUser['position'] ?? 'Medical Staff',
            'department': orgUser['department'] ?? 'General',
            'user_id': orgUser['user_id'],
            'specialization': orgUser['position'] ?? 'General Practitioner',
          };

          loadedDoctors.add(doctorMap);
          print('  - ADDED as doctor: $doctorMap');
        }
      }

      print('\n=== DEBUG: Doctor Loading Results ===');
      print('Total doctors identified: ${loadedDoctors.length}');

      setState(() {
        availableDoctors = loadedDoctors;
      });
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading doctors ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');

      setState(() {
        availableDoctors = [];
      });
    }
  }

  Future<void> _loadAssignmentsFromDatabase() async {
    try {
      print('=== DEBUG: Loading assignments from database ===');

      // Get all active assignments
      final assignmentsResponse = await supabase
          .from('Doctor_User_Assignment')
          .select('*')
          .eq('status', 'active');

      print('Assignments found: ${assignmentsResponse.length}');
      print('Assignments data: $assignmentsResponse');

      if (assignmentsResponse.isEmpty) {
        print('No active assignments found');
        return;
      }

      // Create a map of doctor assignments for quick lookup
      final Map<String, Map<String, dynamic>> patientAssignments = {};

      for (var assignment in assignmentsResponse) {
        final patientId = assignment['patient_id'].toString();
        final doctorId = assignment['doctor_id'].toString();

        // Find the doctor info
        final doctor = availableDoctors.firstWhere(
          (doc) => doc['id'] == doctorId,
          orElse: () => {},
        );

        if (doctor.isNotEmpty) {
          patientAssignments[patientId] = {
            'doctorName': doctor['name'],
            'doctorId': doctorId,
            'assignmentId': assignment['id'],
          };
        }
      }

      // Apply assignments to users
      print('Applying assignments to users...');
      for (int i = 0; i < users.length; i++) {
        final patientId = users[i]['id'];
        final assignment = patientAssignments[patientId];

        if (assignment != null) {
          users[i]['assignedDoctor'] = assignment['doctorName'];
          users[i]['assignedDoctorId'] = assignment['doctorId'];
          users[i]['assignmentId'] = assignment['assignmentId'];

          print(
              'Applied assignment: ${users[i]['name']} -> ${assignment['doctorName']}');
        }
      }

      print('=== DEBUG: Assignment loading completed ===');
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading assignments ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _saveAssignmentToDatabase(
      String patientUserId, String doctorOrgUserId) async {
    try {
      print('=== DEBUG: Saving assignment to database ===');
      print('Patient User ID: $patientUserId');
      print('Doctor Organization_User ID: $doctorOrgUserId');

      // Get the current logged-in user's ID (this is the auth UUID)
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user found');
      }

      final currentAuthUserId = currentUser.id;
      print('Current logged-in auth user ID: $currentAuthUserId');

      // First, check if an assignment already exists for this patient
      final existingAssignment = await supabase
          .from('Doctor_User_Assignment')
          .select('*')
          .eq('patient_id', patientUserId)
          .eq('status', 'active')
          .maybeSingle();

      final assignmentData = {
        'doctor_id': doctorOrgUserId,
        'assigned_at': DateTime.now().toIso8601String(),
        'assigned_by': currentAuthUserId, // Use auth UUID directly
      };

      if (existingAssignment != null) {
        // Update existing assignment
        print(
            'Updating existing assignment with ID: ${existingAssignment['id']}');

        await supabase
            .from('Doctor_User_Assignment')
            .update(assignmentData)
            .eq('id', existingAssignment['id']);

        print('Assignment updated successfully');
      } else {
        // Create new assignment
        print('Creating new assignment...');

        // Add required fields for new assignment
        assignmentData.addAll({
          'patient_id': patientUserId,
          'status': 'active',
        });

        await supabase.from('Doctor_User_Assignment').insert(assignmentData);

        print('New assignment created successfully');
      }
    } catch (e, stackTrace) {
      print('=== DEBUG: Error saving assignment ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save assignment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  void _assignDoctor(int userIndex, Map<String, dynamic> doctor) async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16),
              Text('Assigning doctor...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Save to database first
      await _saveAssignmentToDatabase(users[userIndex]['id'], doctor['id']);

      // Update local state
      setState(() {
        users[userIndex]['assignedDoctor'] = doctor['name'];
        users[userIndex]['assignedDoctorId'] = doctor['id'];
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully assigned ${users[userIndex]['name']} to ${doctor['name']}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () => _removeAssignment(userIndex),
            ),
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to assign doctor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeAssignment(int userIndex) async {
    try {
      final assignmentId = users[userIndex]['assignmentId'];

      if (assignmentId != null) {
        // Remove from database
        await supabase
            .from('Doctor_User_Assignment')
            .update({'status': 'inactive'}).eq('id', assignmentId);
      }

      // Update local state
      setState(() {
        users[userIndex]['assignedDoctor'] = null;
        users[userIndex]['assignedDoctorId'] = null;
        users[userIndex]['assignmentId'] = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Removed doctor assignment for ${users[userIndex]['name']}'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove assignment: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAssignDoctorDialog(int userIndex) {
    if (availableDoctors.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Doctors Available'),
          content: const Text(
            'No doctors found in the system. Please add medical staff to your organization first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _loadAllData();
              },
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Assign Doctor to ${users[userIndex]['name']}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableDoctors.length,
            itemBuilder: (context, index) {
              final doctor = availableDoctors[index];
              final isCurrentlyAssigned =
                  users[userIndex]['assignedDoctorId'] == doctor['id'];

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: isCurrentlyAssigned ? Colors.green.shade50 : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        isCurrentlyAssigned ? Colors.green : Colors.blue,
                    child: Text(
                      doctor['name']!.isNotEmpty
                          ? doctor['name']![0].toUpperCase()
                          : 'D',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(doctor['name']!)),
                      if (isCurrentlyAssigned)
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 20),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doctor['specialization'] ?? 'General Practitioner'),
                      if (doctor['department'] != null &&
                          doctor['department']!.isNotEmpty)
                        Text(
                          'Dept: ${doctor['department']}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                  trailing: isCurrentlyAssigned
                      ? const Text('Currently Assigned',
                          style: TextStyle(color: Colors.green, fontSize: 12))
                      : const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    _assignDoctor(userIndex, doctor);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (users[userIndex]['assignedDoctor'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeAssignment(userIndex);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove Assignment'),
            ),
        ],
      ),
    );
  }

  void _showUserDetails(Map<String, dynamic> user, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user['name']!),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${user['type']}'),
            Text('Last Visit: ${user['lastVisit']}'),
            const SizedBox(height: 8),
            Text('User ID: ${user['id']}'),
            Text('Email: ${user['email']}'),
            Text('Phone: ${user['phone']}'),
            Text('Address: ${user['address']}'),
            const SizedBox(height: 8),
            if (user['type'] == 'Patient') ...[
              Text(
                'Assigned Doctor: ${user['assignedDoctor'] ?? 'Not assigned'}',
                style: TextStyle(
                  color: user['assignedDoctor'] == null
                      ? Colors.orange
                      : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (user['type'] == 'Patient')
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAssignDoctorDialog(index);
              },
              icon: const Icon(Icons.medical_services),
              label: Text(user['assignedDoctor'] == null
                  ? 'Assign Doctor'
                  : 'Change Doctor'),
              style: TextButton.styleFrom(
                foregroundColor: user['assignedDoctor'] == null
                    ? Colors.blue
                    : Colors.orange,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Users/Patients'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading users and doctors...'),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Users/Patients'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Error loading users',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAllData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final patients = users.where((u) => u['type'] == 'Patient').toList();
    final unassignedPatients =
        patients.where((p) => p['assignedDoctor'] == null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users/Patients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search feature coming soon!')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text('Total Patients',
                              style: TextStyle(fontSize: 12)),
                          Text('${patients.length}',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text('Unassigned',
                              style: TextStyle(fontSize: 12)),
                          Text('$unassignedPatients',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: unassignedPatients > 0
                                    ? Colors.orange
                                    : Colors.green,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text('Available Doctors',
                              style: TextStyle(fontSize: 12)),
                          Text('${availableDoctors.length}',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: users.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No users found',
                            style: TextStyle(fontSize: 18, color: Colors.grey)),
                        SizedBox(height: 8),
                        Text('Add some users to get started',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final isPatient = user['type'] == 'Patient';
                      final isUnassigned =
                          isPatient && user['assignedDoctor'] == null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: user['type'] == 'Patient'
                                ? Colors.blue
                                : Colors.purple,
                            child: Icon(
                              user['type'] == 'Patient'
                                  ? Icons.person
                                  : Icons.work,
                              color: Colors.white,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(user['name']!)),
                              if (isUnassigned)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Unassigned',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${user['type']} • Last visit: ${user['lastVisit']}'),
                              if (isPatient && user['assignedDoctor'] != null)
                                Text(
                                  'Doctor: ${user['assignedDoctor']}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isUnassigned)
                                IconButton(
                                  icon: const Icon(Icons.medical_services,
                                      color: Colors.blue),
                                  onPressed: () =>
                                      _showAssignDoctorDialog(index),
                                  tooltip: 'Assign Doctor',
                                ),
                              const Icon(Icons.arrow_forward_ios, size: 16),
                            ],
                          ),
                          onTap: () => _showUserDetails(user, index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
