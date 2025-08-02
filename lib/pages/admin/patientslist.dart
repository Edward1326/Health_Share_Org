// User/Patient List Page with Admin Dashboard Theme and Status Management
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PatientListPage extends StatefulWidget {
  const PatientListPage({super.key});

  @override
  State<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends State<PatientListPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> availableDoctors = [];
  bool isLoading = true;
  String? errorMessage;
  String searchQuery = '';
  String selectedFilter = 'all';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? currentOrganizationId;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
      value: 0.0,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _loadAllData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Helper function to get current organization ID
  Future<String?> getCurrentOrganizationId() async {
    try {
      if (currentOrganizationId != null) {
        return currentOrganizationId;
      }

      final user = supabase.auth.currentUser;
      if (user == null) {
        print('❌ No authenticated user found');
        return null;
      }

      print('🔍 ADMIN LOGIN DEBUG - Current authenticated user ID: ${user.id}');
      print('📧 Admin email: ${user.email}');

      final adminOrgResponse = await supabase
          .from('Organization_User')
          .select('organization_id, department, id, position')
          .eq('user_id', user.id);

      print('🎯 Organization query result for admin user: $adminOrgResponse');

      if (adminOrgResponse.isEmpty) {
        print(
            '❌ PROBLEM FOUND: Admin user ${user.id} is NOT in Organization_User table');

        // TEMPORARY FIX: Get any organization if admin not properly linked
        final allOrgUsers = await supabase
            .from('Organization_User')
            .select('organization_id')
            .limit(1);

        if (allOrgUsers.isNotEmpty) {
          final firstOrgId = allOrgUsers.first['organization_id']?.toString();
          print(
              '🚨 TEMPORARY FIX: Using first available organization: $firstOrgId');
          currentOrganizationId = firstOrgId;
          return currentOrganizationId;
        }
        return null;
      }

      final organizationId =
          adminOrgResponse.first['organization_id']?.toString();
      if (organizationId == null) {
        print('❌ Organization ID is null in the response');
        return null;
      }

      currentOrganizationId = organizationId;
      print('✅ Admin organization ID found: $currentOrganizationId');
      return currentOrganizationId;
    } catch (e) {
      print('❌ Error getting current organization ID: $e');
      return null;
    }
  }

  // Load all data in sequence
  Future<void> _loadAllData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Get organization ID first
      currentOrganizationId = await getCurrentOrganizationId();

      if (currentOrganizationId == null) {
        throw Exception('Unable to determine current organization');
      }

      await _loadUsersFromSupabase();
      await _loadDoctorsFromSupabase();
      await _loadAssignmentsFromDatabase();
      _animationController.forward();
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

  List<Map<String, dynamic>> get filteredUsers {
    var filtered = users.where((user) {
      final matchesSearch =
          user['name']!.toLowerCase().contains(searchQuery.toLowerCase()) ||
              user['id'].toString().contains(searchQuery);

      switch (selectedFilter) {
        case 'pending':
          return matchesSearch && user['status'] == 'pending';
        case 'unassigned':
          return matchesSearch && user['status'] == 'unassigned';
        case 'assigned':
          return matchesSearch && user['status'] == 'assigned';
        default:
          return matchesSearch;
      }
    }).toList();

    // Sort by status priority (pending first, then unassigned, then assigned)
    filtered.sort((a, b) {
      const statusPriority = {'pending': 0, 'unassigned': 1, 'assigned': 2};
      final aPriority = statusPriority[a['status']] ?? 3;
      final bPriority = statusPriority[b['status']] ?? 3;

      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      return a['name']!.compareTo(b['name']!);
    });

    return filtered;
  }

  Future<void> _loadUsersFromSupabase() async {
    try {
      print('=== DEBUG: Starting patient loading process ===');
      print('Current organization ID: $currentOrganizationId');

      // Fetch patients from the organization with proper joins
      print('Step 1: Fetching Patient records for organization...');
      final patientsResponse = await supabase.from('Patient').select('''
            *,
            User!inner(
              *,
              Person!inner(*)
            )
          ''').eq('organization_id', currentOrganizationId!);

      print('Patient records found: ${patientsResponse.length}');

      if (patientsResponse.isEmpty) {
        print('No Patient records found for organization!');
        setState(() {
          users = [];
        });
        return;
      }

      // Build the users list from patients
      print('\nStep 2: Building final patient list...');
      final List<Map<String, dynamic>> loadedUsers = [];

      for (var patient in patientsResponse) {
        final user = patient['User'];
        final person = user?['Person'];

        if (person != null) {
          final fullName =
              person['first_name'] != null && person['last_name'] != null
                  ? '${person['first_name']} ${person['last_name']}'
                  : person['first_name'] ??
                      person['last_name'] ??
                      'Unknown Patient';

          final userMap = {
            'id': patient['id'].toString(),
            'name': fullName,
            'type': 'Patient',
            'email': person['email'] ?? '',
            'phone': person['contact_number'] ?? '',
            'address': person['address'] ?? '',
            'lastVisit': patient['created_at'] != null
                ? DateTime.parse(patient['created_at']).toString().split(' ')[0]
                : '2024-01-01',
            'status':
                patient['status'] ?? 'pending', // Get status from Patient table
            'assignedDoctor': null,
            'assignedDoctorId': null,
            'assignmentId': null,
            'patientId': patient['id'].toString(),
            'personId':
                person['id'].toString(), // Use person ID from Person table
            'userId': user['id'].toString(), // Also store user ID if needed
          };

          loadedUsers.add(userMap);
        }
      }

      print('\n=== DEBUG: Patient Loading Results ===');
      print('Total patients loaded: ${loadedUsers.length}');
      print('Status breakdown:');
      final statusCounts = <String, int>{};
      for (var user in loadedUsers) {
        statusCounts[user['status']] = (statusCounts[user['status']] ?? 0) + 1;
      }
      statusCounts.forEach((status, count) {
        print('  - $status: $count');
      });

      setState(() {
        users = loadedUsers;
      });
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading patients ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _loadDoctorsFromSupabase() async {
    try {
      print('=== DEBUG: Fetching Doctor/Employee records ===');
      print('Current organization ID: $currentOrganizationId');

      // Fetch employees from Organization_User table filtered by current organization
      final orgUsersResponse = await supabase
          .from('Organization_User')
          .select('*, User!inner(*, Person!inner(*))')
          .eq('organization_id', currentOrganizationId!);

      print(
          'Organization_User records found for current org: ${orgUsersResponse.length}');

      if (orgUsersResponse.isEmpty) {
        setState(() {
          availableDoctors = [];
        });
        return;
      }

      // Build the doctors list
      final List<Map<String, dynamic>> loadedDoctors = [];

      print('\n=== DEBUG: Processing each Organization_User record ===');

      for (var orgUser in orgUsersResponse) {
        final user = orgUser['User'];
        final person = user?['Person'];

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
            'organization_id': orgUser['organization_id'],
            'specialization': orgUser['position'] ?? 'General Practitioner',
          };

          loadedDoctors.add(doctorMap);
          print('  - ADDED as doctor: $doctorMap');
        }
      }

      print('\n=== DEBUG: Doctor Loading Results ===');
      print(
          'Total doctors identified for org $currentOrganizationId: ${loadedDoctors.length}');

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

      if (assignmentsResponse.isEmpty) {
        print('No active assignments found');
        return;
      }

      // Create a map of doctor assignments for quick lookup
      final Map<String, Map<String, dynamic>> patientAssignments = {};

      for (var assignment in assignmentsResponse) {
        final patientId = assignment['patient_id'].toString();
        final doctorId = assignment['doctor_id'].toString();

        // Find the doctor info from current organization only
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

      // Apply assignments to users and update status
      print('Applying assignments to users...');
      for (int i = 0; i < users.length; i++) {
        final patientId = users[i]['id'];
        final assignment = patientAssignments[patientId];

        if (assignment != null) {
          users[i]['assignedDoctor'] = assignment['doctorName'];
          users[i]['assignedDoctorId'] = assignment['doctorId'];
          users[i]['assignmentId'] = assignment['assignmentId'];
          users[i]['status'] =
              'assigned'; // Override status if doctor is assigned

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

  // Approve pending patient (change status from pending to unassigned)
  Future<void> _approvePendingPatient(int userIndex) async {
    try {
      final patientId = users[userIndex]['id'];

      // Update status in database
      await supabase
          .from('Patient')
          .update({'status': 'unassigned'}).eq('id', patientId);

      // Update local state
      setState(() {
        users[userIndex]['status'] = 'unassigned';
      });

      _showSnackBar(
          'Patient ${users[userIndex]['name']} approved and ready for assignment',
          const Color(0xFF38A169));
    } catch (e) {
      _showSnackBar('Failed to approve patient: $e', const Color(0xFFE53E3E));
    }
  }

  // Reject pending patient (remove from organization)
  Future<void> _rejectPendingPatient(int userIndex) async {
    try {
      final patientId = users[userIndex]['id'];

      // Remove patient from organization (set organization_id to null or delete)
      await supabase.from('Patient').update(
          {'organization_id': null, 'status': 'rejected'}).eq('id', patientId);

      // Remove from local state
      setState(() {
        users.removeAt(userIndex);
      });

      _showSnackBar('Patient rejected and removed from organization',
          const Color(0xFFD69E2E));
    } catch (e) {
      _showSnackBar('Failed to reject patient: $e', const Color(0xFFE53E3E));
    }
  }

  Future<void> _saveAssignmentToDatabase(
      String patientUserId, String doctorOrgUserId) async {
    try {
      print('=== DEBUG: Saving assignment to database ===');
      print('Patient User ID: $patientUserId');
      print('Doctor Organization_User ID: $doctorOrgUserId');

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user found');
      }

      final currentAuthUserId = currentUser.id;

      // Check if an assignment already exists for this patient
      final existingAssignment = await supabase
          .from('Doctor_User_Assignment')
          .select('*')
          .eq('patient_id', patientUserId)
          .eq('status', 'active')
          .maybeSingle();

      final assignmentData = {
        'doctor_id': doctorOrgUserId,
        'assigned_at': DateTime.now().toIso8601String(),
        'assigned_by': currentAuthUserId,
      };

      if (existingAssignment != null) {
        // Update existing assignment
        await supabase
            .from('Doctor_User_Assignment')
            .update(assignmentData)
            .eq('id', existingAssignment['id']);
      } else {
        // Create new assignment
        assignmentData.addAll({
          'patient_id': patientUserId,
          'status': 'active',
        });

        await supabase.from('Doctor_User_Assignment').insert(assignmentData);
      }

      // Update patient status to 'assigned'
      await supabase
          .from('Patient')
          .update({'status': 'assigned'}).eq('id', patientUserId);

      print('Assignment saved successfully');
    } catch (e, stackTrace) {
      print('=== DEBUG: Error saving assignment ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        _showSnackBar('Failed to save assignment: $e', Colors.red);
      }
      rethrow;
    }
  }

  void _assignDoctor(int userIndex, Map<String, dynamic> doctor) async {
    try {
      // Check if patient is approved first
      if (users[userIndex]['status'] == 'pending') {
        _showSnackBar(
            'Please approve this patient first before assigning a doctor',
            const Color(0xFFD69E2E));
        return;
      }

      // Show loading
      _showSnackBar('Assigning doctor...', const Color(0xFF3182CE),
          showProgress: true);

      // Save to database first
      await _saveAssignmentToDatabase(users[userIndex]['id'], doctor['id']);

      // Update local state
      setState(() {
        users[userIndex]['assignedDoctor'] = doctor['name'];
        users[userIndex]['assignedDoctorId'] = doctor['id'];
        users[userIndex]['status'] = 'assigned';
      });

      // Show success message
      if (mounted) {
        _showSnackBar(
            'Successfully assigned ${users[userIndex]['name']} to ${doctor['name']}',
            const Color(0xFF38A169),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () => _removeAssignment(userIndex),
            ));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to assign doctor: $e', const Color(0xFFE53E3E));
      }
    }
  }

  Future<void> _removeAssignment(int userIndex) async {
    try {
      final assignmentId = users[userIndex]['assignmentId'];
      final patientId = users[userIndex]['id'];

      if (assignmentId != null) {
        // Remove from database
        await supabase
            .from('Doctor_User_Assignment')
            .update({'status': 'inactive'}).eq('id', assignmentId);
      }

      // Update patient status back to unassigned
      await supabase
          .from('Patient')
          .update({'status': 'unassigned'}).eq('id', patientId);

      // Update local state
      setState(() {
        users[userIndex]['assignedDoctor'] = null;
        users[userIndex]['assignedDoctorId'] = null;
        users[userIndex]['assignmentId'] = null;
        users[userIndex]['status'] = 'unassigned';
      });

      _showSnackBar('Removed doctor assignment for ${users[userIndex]['name']}',
          const Color(0xFFD69E2E));
    } catch (e) {
      _showSnackBar('Failed to remove assignment: $e', const Color(0xFFE53E3E));
    }
  }

  void _showSnackBar(String message, Color color,
      {SnackBarAction? action, bool showProgress = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (showProgress) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: action,
        duration: Duration(seconds: showProgress ? 2 : 4),
      ),
    );
  }

  void _showAssignDoctorDialog(int userIndex) {
    // Check if patient is pending
    if (users[userIndex]['status'] == 'pending') {
      _showApprovalDialog(userIndex);
      return;
    }

    if (availableDoctors.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Color(0xFFD69E2E)),
              SizedBox(width: 8),
              Text('No Doctors Available'),
            ],
          ),
          content: const Text(
            'No doctors found in the system. Please add medical staff to your organization first.',
            style: TextStyle(color: Color(0xFF4A5568)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('OK', style: TextStyle(color: Color(0xFF718096))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _loadAllData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3182CE),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child:
                  const Text('Refresh', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.medical_services_rounded,
                color: Color(0xFF3182CE)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Assign Doctor to ${users[userIndex]['name']}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
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

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isCurrentlyAssigned
                      ? const Color(0xFF38A169).withOpacity(0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrentlyAssigned
                        ? const Color(0xFF38A169)
                        : Colors.grey.shade200,
                    width: isCurrentlyAssigned ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCurrentlyAssigned
                          ? const Color(0xFF38A169)
                          : const Color(0xFF3182CE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      doctor['name']!.isNotEmpty
                          ? doctor['name']![0].toUpperCase()
                          : 'D',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                          child: Text(doctor['name']!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      if (isCurrentlyAssigned)
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF38A169), size: 20),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doctor['specialization'] ?? 'General Practitioner',
                          style: const TextStyle(color: Color(0xFF4A5568))),
                      if (doctor['department'] != null &&
                          doctor['department']!.isNotEmpty)
                        Text(
                          'Dept: ${doctor['department']}',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF718096)),
                        ),
                    ],
                  ),
                  trailing: isCurrentlyAssigned
                      ? const Text('Currently Assigned',
                          style: TextStyle(
                              color: Color(0xFF38A169),
                              fontSize: 12,
                              fontWeight: FontWeight.w500))
                      : const Icon(Icons.arrow_forward_ios_rounded, size: 16),
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
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF718096))),
          ),
          if (users[userIndex]['assignedDoctor'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeAssignment(userIndex);
              },
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE53E3E)),
              child: const Text('Remove Assignment'),
            ),
        ],
      ),
    );
  }

  void _showApprovalDialog(int userIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.pending_actions_rounded, color: Color(0xFFD69E2E)),
            SizedBox(width: 8),
            Text('Patient Approval Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patient "${users[userIndex]['name']}" is pending approval.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'You need to approve this patient before they can be assigned to a doctor.',
              style: TextStyle(color: Color(0xFF4A5568)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF718096))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectPendingPatient(userIndex);
            },
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFE53E3E)),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approvePendingPatient(userIndex);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38A169),
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showUserDetails(Map<String, dynamic> user, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF3182CE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_rounded, color: Color(0xFF3182CE)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(user['name']!, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Type', user['type'], Icons.badge_rounded),
            _buildDetailRow(
                'Last Visit', user['lastVisit'], Icons.calendar_today_rounded),
            _buildDetailRow('User ID', user['id'], Icons.tag_rounded),
            _buildDetailRow(
                'Email',
                user['email'].isNotEmpty ? user['email'] : 'Not provided',
                Icons.email_rounded),
            _buildDetailRow(
                'Phone',
                user['phone'].isNotEmpty ? user['phone'] : 'Not provided',
                Icons.phone_rounded),
            _buildDetailRow(
                'Address',
                user['address'].isNotEmpty ? user['address'] : 'Not provided',
                Icons.location_on_rounded),
            const SizedBox(height: 16),
            if (user['type'] == 'Patient') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: user['assignedDoctor'] == null
                      ? const Color(0xFFD69E2E).withOpacity(0.1)
                      : const Color(0xFF38A169).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.medical_services_rounded,
                      color: user['assignedDoctor'] == null
                          ? const Color(0xFFD69E2E)
                          : const Color(0xFF38A169),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Assigned Doctor: ${user['assignedDoctor'] ?? 'Not assigned'}',
                        style: TextStyle(
                          color: user['assignedDoctor'] == null
                              ? const Color(0xFFD69E2E)
                              : const Color(0xFF38A169),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (user['type'] == 'Patient')
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAssignDoctorDialog(index);
              },
              icon: const Icon(Icons.medical_services_rounded, size: 18),
              label: Text(user['assignedDoctor'] == null
                  ? 'Assign Doctor'
                  : 'Change Doctor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: user['assignedDoctor'] == null
                    ? const Color(0xFF3182CE)
                    : const Color(0xFFD69E2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Close', style: TextStyle(color: Color(0xFF718096))),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF718096)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF718096),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2D3748),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: _buildModernAppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(
                  color: Color(0xFF3B82F6),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading patients and doctors...',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: _buildModernAppBar(),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Error Loading Data',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadAllData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildModernAppBar(),
      body: users.isEmpty
          ? _buildModernEmptyState()
          : Column(
              children: [
                _buildSearchAndFilter(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadAllData,
                    color: const Color(0xFF3B82F6),
                    child: ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height * 0.12,
                      ),
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final userIndex = users.indexWhere(
                          (u) => u['id'] == filteredUsers[index]['id'],
                        );
                        return _buildEnhancedPatientCard(
                            filteredUsers[index], userIndex);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModernEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF3B82F6).withOpacity(0.1),
                    const Color(0xFF1E40AF).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 64,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Patients Found',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Patients will appear here once they register\nin your healthcare system.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadAllData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    // Increased height to accommodate all content properly
    final double baseHeight = 180; // Increased from 140
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double totalHeight = baseHeight + statusBarHeight;

    return PreferredSize(
      preferredSize: Size.fromHeight(totalHeight),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E40AF),
              const Color(0xFF3B82F6),
              const Color(0xFF60A5FA),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                16, 8, 16, 16), // Increased bottom padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_rounded),
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Patient Management',
                        style: TextStyle(
                          fontSize: 22, // Slightly reduced font size
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: _loadAllData,
                        icon: const Icon(Icons.refresh_rounded),
                        color: Colors.white,
                        tooltip: 'Refresh',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Stats Cards Row - Made more compact
                Row(
                  children: [
                    Expanded(
                      child: _buildModernStatCard(
                        'Total Patients',
                        users.length.toString(),
                        Icons.group_rounded,
                        Colors.white.withOpacity(0.9),
                        const Color(0xFF1E40AF),
                      ),
                    ),
                    const SizedBox(width: 8), // Reduced spacing
                    Expanded(
                      child: _buildModernStatCard(
                        'Assigned',
                        users
                            .where((u) => u['assignedDoctor'] != null)
                            .length
                            .toString(),
                        Icons.assignment_turned_in_rounded,
                        const Color(0xFF10B981).withOpacity(0.9),
                        Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8), // Reduced spacing
                    Expanded(
                      child: _buildModernStatCard(
                        'Unassigned',
                        users
                            .where((u) => u['assignedDoctor'] == null)
                            .length
                            .toString(),
                        Icons.assignment_late_rounded,
                        const Color(0xFFEF4444).withOpacity(0.9),
                        Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Also update your _buildModernStatCard method to be more compact
  Widget _buildModernStatCard(String title, String value, IconData icon,
      Color backgroundColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 8), // Reduced padding
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: textColor,
            size: 18, // Reduced icon size
          ),
          const SizedBox(height: 4), // Reduced spacing
          Text(
            value,
            style: TextStyle(
              fontSize: 16, // Reduced font size
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10, // Reduced font size
              color: textColor.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search Bar (existing code remains the same)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              onChanged: (value) => setState(() => searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search patients by name or ID...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon:
                    Icon(Icons.search_rounded, color: Colors.grey.shade400),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () => setState(() => searchQuery = ''),
                        icon: Icon(Icons.clear_rounded,
                            color: Colors.grey.shade400),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Updated Filter Chips with Pending
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Pending', 'pending',
                    color: const Color(0xFFF59E0B), // Orange for pending
                    icon: Icons.hourglass_empty_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('Unassigned', 'unassigned',
                    color: const Color(0xFFEF4444), // Red for unassigned
                    icon: Icons.person_off_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('Assigned', 'assigned',
                    color: const Color(0xFF10B981), // Green for assigned
                    icon: Icons.person_add_alt_rounded),
                const SizedBox(width: 16),
                Text(
                  '${filteredUsers.length} patients',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value,
      {Color? color, IconData? icon}) {
    final isSelected = selectedFilter == value;
    final chipColor = color ?? const Color(0xFF3B82F6);

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 16, color: isSelected ? chipColor : Colors.grey.shade600),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) => setState(() => selectedFilter = value),
      backgroundColor: Colors.white,
      selectedColor: chipColor.withOpacity(0.1),
      checkmarkColor: chipColor,
      labelStyle: TextStyle(
        color: isSelected ? chipColor : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? chipColor : Colors.grey.shade300,
        ),
      ),
    );
  }

  Widget _buildEnhancedPatientCard(Map<String, dynamic> user, int index) {
    final String status = user['status'] ?? 'pending';
    final bool hasAssignedDoctor = user['assignedDoctor'] != null;

    // Define colors based on status
    Color statusColor;
    Color borderColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'pending':
        statusColor = const Color(0xFFF59E0B);
        borderColor = const Color(0xFFF59E0B).withOpacity(0.3);
        statusIcon = Icons.hourglass_empty_rounded;
        statusText = 'Pending Approval';
        break;
      case 'unassigned':
        statusColor = const Color(0xFFEF4444);
        borderColor = const Color(0xFFEF4444).withOpacity(0.3);
        statusIcon = Icons.person_off_rounded;
        statusText = 'Unassigned';
        break;
      case 'assigned':
        statusColor = const Color(0xFF10B981);
        borderColor = const Color(0xFF10B981).withOpacity(0.3);
        statusIcon = Icons.check_circle_rounded;
        statusText = 'Assigned';
        break;
      default:
        statusColor = Colors.grey;
        borderColor = Colors.grey.withOpacity(0.3);
        statusIcon = Icons.help_outline_rounded;
        statusText = 'Unknown';
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            (index * 0.1).clamp(0.0, 1.0),
            1.0,
            curve: Curves.easeOutBack,
          ),
        )),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey.shade50,
                  ],
                ),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showUserDetails(user, index),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row with Status Badge
                        Row(
                          children: [
                            Hero(
                              tag: 'patient_${user['id']}',
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF3B82F6),
                                      const Color(0xFF1E40AF),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF3B82F6)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    user['name']!.isNotEmpty
                                        ? user['name']![0].toUpperCase()
                                        : 'P',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
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
                                    user['name']!,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3B82F6)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          user['type']!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF3B82F6),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'ID: ${user['id']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Status Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: statusColor.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon,
                                      color: statusColor, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Status-specific content section
                        if (status == 'pending') ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      const Color(0xFFF59E0B).withOpacity(0.2)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.pending_actions_rounded,
                                        size: 20,
                                        color: const Color(0xFFF59E0B)),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'This patient is awaiting your approval',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFF59E0B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Review patient information and approve to allow doctor assignment',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Doctor Assignment Section for non-pending patients
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: hasAssignedDoctor
                                  ? const Color(0xFF10B981).withOpacity(0.05)
                                  : const Color(0xFFEF4444).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasAssignedDoctor
                                    ? const Color(0xFF10B981).withOpacity(0.2)
                                    : const Color(0xFFEF4444).withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.medical_services_rounded,
                                      size: 20,
                                      color: hasAssignedDoctor
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        hasAssignedDoctor
                                            ? 'Assigned to: ${user['assignedDoctor']}'
                                            : 'No doctor assigned',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: hasAssignedDoctor
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.schedule_rounded,
                                        size: 16, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Last visit: ${user['lastVisit']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (user['email'].isNotEmpty) ...[
                                      Icon(Icons.email_outlined,
                                          size: 16,
                                          color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                    ],
                                    if (user['phone'].isNotEmpty) ...[
                                      Icon(Icons.phone_outlined,
                                          size: 16,
                                          color: Colors.grey.shade600),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Status-specific Action Buttons
                        if (status == 'pending') ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _rejectPendingPatient(index),
                                  icon:
                                      const Icon(Icons.close_rounded, size: 18),
                                  label: const Text('Reject'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFEF4444),
                                    side: const BorderSide(
                                        color: Color(0xFFEF4444)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _approvePendingPatient(index),
                                  icon:
                                      const Icon(Icons.check_rounded, size: 18),
                                  label: const Text('Approve'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          // Regular action buttons for approved patients
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _showUserDetails(user, index),
                                  icon: const Icon(Icons.visibility_outlined,
                                      size: 18),
                                  label: const Text('View Details'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF3B82F6),
                                    side: const BorderSide(
                                        color: Color(0xFF3B82F6)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _showAssignDoctorDialog(index),
                                  icon: Icon(
                                    hasAssignedDoctor
                                        ? Icons.edit_rounded
                                        : Icons.person_add_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                      hasAssignedDoctor ? 'Change' : 'Assign'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: hasAssignedDoctor
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
