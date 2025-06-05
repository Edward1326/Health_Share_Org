// User/Patient List Page with Dynamic Doctor Assignment Feature
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
  List<Map<String, dynamic>> availableDoctors = []; // Changed from hardcoded list
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsersFromSupabase();
    _loadDoctorsFromSupabase(); // Load doctors from database
  }

  Future<void> _loadUsersFromSupabase() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      print('=== DEBUG: Fetching User records ===');
      
      // Fetch all users from the User table
      final usersResponse = await supabase
          .from('User')
          .select('*');
      
      print('User records found: ${usersResponse.length}');
      print('User data: $usersResponse');

      if (usersResponse.isEmpty) {
        print('No User records found!');
        setState(() {
          users = []; // Clear the users list
          isLoading = false;
          errorMessage = 'No users found in database.';
        });
        return;
      }

      // Extract person IDs from users
      final personIds = usersResponse
          .map((user) => user['person_id'])
          .where((id) => id != null)
          .toList();
      
      print('Person IDs to fetch: $personIds');

      // Fetch corresponding Person records
      print('=== DEBUG: Fetching Person records ===');
      final personsResponse = await supabase
          .from('Person')
          .select('*')
          .in_('id', personIds);
      
      print('Person records found: ${personsResponse.length}');
      print('Person data: $personsResponse');

      // Create a map for quick person lookup
      final Map<dynamic, Map<String, dynamic>> personsMap = {};
      for (var person in personsResponse) {
        personsMap[person['id']] = person;
      }

      // Build the users list
      print('=== DEBUG: Building users list ===');
      final List<Map<String, dynamic>> loadedUsers = [];
      
      for (var user in usersResponse) {
        final person = personsMap[user['person_id']];
        
        if (person != null) {
          final userMap = {
            'id': user['id'].toString(),
            'name': person['first_name'] != null && person['last_name'] != null
                ? '${person['first_name']} ${person['last_name']}'
                : person['first_name'] ?? person['last_name'] ?? 'Unknown User',
            'type': 'Patient', // You can modify this based on your user role logic
            'email': person['contact_number'] ?? '', // Assuming you store email in contact_number or add email field
            'phone': person['contact_number'] ?? '',
            'address': person['address'] ?? '',
            'lastVisit': user['created_at'] != null 
                ? DateTime.parse(user['created_at']).toString().split(' ')[0]
                : '2024-01-01',
            'assignedDoctor': null, // You can add this logic if you have doctor assignments
          };
          
          loadedUsers.add(userMap);
          print('Built user: $userMap');
        } else {
          print('No person found for user_id: ${user['id']}');
          // Still add the user even without person details
          final userMap = {
            'id': user['id'].toString(),
            'name': 'User ${user['id']}',
            'type': 'Patient',
            'email': '',
            'phone': '',
            'address': '',
            'lastVisit': user['created_at'] != null 
                ? DateTime.parse(user['created_at']).toString().split(' ')[0]
                : '2024-01-01',
            'assignedDoctor': null,
          };
          loadedUsers.add(userMap);
        }
      }

      print('\n=== DEBUG: Final Results ===');
      print('Total users loaded: ${loadedUsers.length}');

      setState(() {
        users = loadedUsers; // Replace the hardcoded users with loaded data
        isLoading = false;
      });

    } catch (e, stackTrace) {
      print('=== DEBUG: Error occurred ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      
      setState(() {
        errorMessage = 'Error loading users: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _loadDoctorsFromSupabase() async {
    try {
      print('=== DEBUG: Fetching Doctor/Employee records ===');
      
      // Fetch employees from Organization_User table
      final orgUsersResponse = await supabase
          .from('Organization_User')
          .select('*');
      
      print('Organization_User records found: ${orgUsersResponse.length}');

      if (orgUsersResponse.isEmpty) {
        print('No Organization_User records found!');
        setState(() {
          availableDoctors = [];
        });
        return;
      }

      // Extract user IDs
      final userIds = orgUsersResponse.map((item) => item['user_id']).toList();
      
      // Fetch corresponding Person records
      final personsResponse = await supabase
          .from('Person')
          .select('*')
          .in_('id', userIds);

      // Create a map for quick person lookup
      final Map<dynamic, Map<String, dynamic>> personsMap = {};
      for (var person in personsResponse) {
        personsMap[person['id']] = person;
      }

      // Build the doctors list - filter for doctors/medical staff
      final List<Map<String, dynamic>> loadedDoctors = [];
      
      for (var orgUser in orgUsersResponse) {
        final person = personsMap[orgUser['user_id']];
        final position = orgUser['position']?.toString().toLowerCase() ?? '';
        
        // Check if the employee is a doctor or medical professional
        if (position.contains('doctor') || 
            position.contains('dr.') || 
            position.contains('physician') || 
            position.contains('specialist') ||
            position.contains('surgeon') ||
            position.contains('md')) {
          
          if (person != null) {
            final fullName = person['first_name'] != null && person['last_name'] != null
                ? '${person['first_name']} ${person['last_name']}'
                : person['first_name'] ?? person['last_name'] ?? 'Unknown Doctor';
            
            final doctorMap = {
              'id': orgUser['id'].toString(),
              'name': fullName,
              'position': orgUser['position'] ?? 'Doctor',
              'department': orgUser['department'] ?? 'General',
              'user_id': orgUser['user_id'],
              'specialization': orgUser['position'] ?? 'General Practitioner',
            };
            
            loadedDoctors.add(doctorMap);
            print('Built doctor: $doctorMap');
          }
        }
      }

      print('Total doctors loaded: ${loadedDoctors.length}');

      setState(() {
        availableDoctors = loadedDoctors;
      });

    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading doctors ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      
      // Set empty list on error so UI doesn't break
      setState(() {
        availableDoctors = [];
      });
    }
  }

  void _assignDoctor(int userIndex, Map<String, dynamic> doctor) {
    setState(() {
      users[userIndex]['assignedDoctor'] = doctor['name'];
      users[userIndex]['assignedDoctorId'] = doctor['id'];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Assigned ${users[userIndex]['name']} to ${doctor['name']}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showAssignDoctorDialog(int userIndex) {
    if (availableDoctors.isEmpty) {
      // Show dialog to inform no doctors available
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
                _loadDoctorsFromSupabase(); // Retry loading doctors
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
          child: availableDoctors.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medical_services_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No doctors available'),
                      Text(
                        'Add medical staff to your organization',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableDoctors.length,
                  itemBuilder: (context, index) {
                    final doctor = availableDoctors[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Text(
                            doctor['name']!.isNotEmpty 
                                ? doctor['name']![0].toUpperCase()
                                : 'D',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(doctor['name']!),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(doctor['specialization'] ?? 'General Practitioner'),
                            if (doctor['department'] != null && doctor['department']!.isNotEmpty)
                              Text(
                                'Dept: ${doctor['department']}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
          if (availableDoctors.isEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _loadDoctorsFromSupabase();
              },
              child: const Text('Refresh Doctors'),
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
            const SizedBox(height: 8),
            if (user['type'] == 'Patient') ...[
              Text(
                'Assigned Doctor: ${user['assignedDoctor'] ?? 'Not assigned'}',
                style: TextStyle(
                  color: user['assignedDoctor'] == null ? Colors.orange : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (user['type'] == 'Patient' && user['assignedDoctor'] == null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAssignDoctorDialog(index);
              },
              icon: const Icon(Icons.medical_services),
              label: const Text('Assign Doctor'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
          if (user['type'] == 'Patient' && user['assignedDoctor'] != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAssignDoctorDialog(index);
              },
              icon: const Icon(Icons.edit),
              label: const Text('Change Doctor'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange,
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
                onPressed: () {
                  _loadUsersFromSupabase();
                  _loadDoctorsFromSupabase();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final patients = users.where((u) => u['type'] == 'Patient').toList();
    final unassignedPatients = patients.where((p) => p['assignedDoctor'] == null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users/Patients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadUsersFromSupabase();
              _loadDoctorsFromSupabase();
            },
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
                          const Text('Total Patients', style: TextStyle(fontSize: 12)),
                          Text('${patients.length}', 
                               style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                          const Text('Unassigned', style: TextStyle(fontSize: 12)),
                          Text('$unassignedPatients', 
                               style: TextStyle(
                                 fontSize: 24, 
                                 fontWeight: FontWeight.bold,
                                 color: unassignedPatients > 0 ? Colors.orange : Colors.green,
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
                          const Text('Available Doctors', style: TextStyle(fontSize: 12)),
                          Text('${availableDoctors.length}', 
                               style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No users found',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Add some users to get started',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final isPatient = user['type'] == 'Patient';
                    final isUnassigned = isPatient && user['assignedDoctor'] == null;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: user['type'] == 'Patient' 
                              ? Colors.blue 
                              : user['type'] == 'Administrator' 
                                  ? Colors.red 
                                  : Colors.purple,
                          child: Icon(
                            user['type'] == 'Patient' 
                                ? Icons.person 
                                : user['type'] == 'Administrator' 
                                    ? Icons.admin_panel_settings 
                                    : Icons.work,
                            color: Colors.white,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(user['name']!)),
                            if (isUnassigned)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                            Text('${user['type']} • Last visit: ${user['lastVisit']}'),
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
                                icon: const Icon(Icons.medical_services, color: Colors.blue),
                                onPressed: () => _showAssignDoctorDialog(index),
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