// admin_patientslist.dart - Functions for Patient List Management
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPatientListFunctions {
  final SupabaseClient supabase = Supabase.instance.client;
  String? currentOrganizationId;

  // Helper function to get current organization ID
  Future<Map<String, dynamic>?> getPatientByUserId(String userId) async {
    try {
      final response = await supabase
          .from('Patient')
          .select('id')
          .eq('user_id',
              userId) // This assumes Patient table has a user_id field
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error getting patient by user ID: $e');
      return null;
    }
  }

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

  // Load users from Supabase
  Future<List<Map<String, dynamic>>> loadUsersFromSupabase() async {
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
        return [];
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
            'email': user['email'] ?? '',
            'phone': person['contact_number'] ?? '',
            'address': person['address'] ?? '',
            'lastVisit': patient['created_at'] != null
                ? DateTime.parse(patient['created_at']).toString().split(' ')[0]
                : '2024-01-01',
            'status': patient['status'] ?? 'pending',
            'assignedDoctor': null,
            'assignedDoctorId': null,
            'assignmentId': null,
            'patientId': patient['id'].toString(),
            'personId': person['id'].toString(),
            'userId': user['id'].toString(),
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

      return loadedUsers;
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading patients ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Add this method to your AdminPatientListFunctions class

  // Load doctors from Supabase
  Future<List<Map<String, dynamic>>> loadDoctorsFromSupabase() async {
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
        return [];
      }

      // Build the doctors list
      final List<Map<String, dynamic>> loadedDoctors = [];

      print('\n=== DEBUG: Processing each Organization_User record ===');

      for (var orgUser in orgUsersResponse) {
        final user = orgUser['User'];
        final person = user?['Person'];

        // IMPORTANT: Verify this record belongs to current organization
        if (orgUser['organization_id']?.toString() != currentOrganizationId) {
          print(
              '  - SKIPPING: Wrong organization ${orgUser['organization_id']}');
          continue;
        }

        final position = orgUser['position']?.toString().toLowerCase() ?? '';
        final department =
            orgUser['department']?.toString().toLowerCase() ?? '';

        print('Processing employee from org $currentOrganizationId:');
        print('  - Position: ${orgUser['position']}');
        print('  - Department: ${orgUser['department']}');
        print('  - Organization ID: ${orgUser['organization_id']}');

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
            'user_id': orgUser['user_id'],
            'name': doctorName,
            'position': orgUser['position'] ?? 'Medical Staff',
            'department': orgUser['department'] ?? 'General',
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

      return loadedDoctors;
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading doctors ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  Future<void> loadAssignmentsFromDatabase(
    List<Map<String, dynamic>> users) async {
  try {
    print('=== DEBUG: Loading assignments ===');

    // Extract patient IDs from users (these are Patient table IDs)
    // FIX: Explicitly cast to Set<String> to avoid type issues
    final Set<String> patientIds = users
        .map((user) => user['id'].toString())
        .toSet()
        .cast<String>();

    if (patientIds.isEmpty) {
      print('No patient IDs found');
      return;
    }

    print('Looking for assignments for Patient IDs: $patientIds');

    // Query assignments using Patient IDs directly
    final response = await supabase.from('Doctor_User_Assignment').select('''
        patient_id,
        doctor_id,
        status,
        assigned_at
      ''').in_('patient_id', patientIds.toList()).eq('status', 'active');

    print('Found ${response.length} active assignments');

    // Get doctor details for all assigned doctors
    // FIX: Explicitly cast to Set<String>
    final Set<String> doctorIds = response
        .map((assignment) => assignment['doctor_id'].toString())
        .toSet()
        .cast<String>();

    if (doctorIds.isNotEmpty) {
      final doctorResponse =
          await supabase.from('Organization_User').select('''
          id,
          User!inner(
            Person!inner(
              first_name,
              last_name
            )
          ),
          position,
          department
        ''').in_('id', doctorIds.toList());

      // Create doctor lookup map
      final doctorMap = <String, Map<String, dynamic>>{};
      for (final doctor in doctorResponse) {
        final person = doctor['User']['Person'];
        final doctorName = person != null &&
                person['first_name'] != null &&
                person['last_name'] != null
            ? '${person['first_name']} ${person['last_name']}'
            : 'Dr. ${doctor['position'] ?? 'Unknown'}';

        doctorMap[doctor['id'].toString()] = {
          'id': doctor['id'],
          'name': doctorName,
          'position': doctor['position'],
          'department': doctor['department'],
        };
      }

      // Process assignments and update users
      for (final assignment in response) {
        final patientId = assignment['patient_id'].toString();
        final doctorId = assignment['doctor_id'].toString();
        final doctorInfo = doctorMap[doctorId];

        print(
            '  Patient ID: $patientId -> Doctor ID: $doctorId (${doctorInfo?['name']})');

        // Find and update the user
        final userIndex = users.indexWhere((user) => user['id'] == patientId);
        if (userIndex != -1) {
          final doctorName = doctorInfo?['name'] ?? 'Unknown Doctor';
          
          users[userIndex]['doctor_id'] = doctorId;
          users[userIndex]['doctor_name'] = doctorName;
          users[userIndex]['assignedDoctor'] = doctorName;
          users[userIndex]['assignedDoctorId'] = doctorId;
          users[userIndex]['assignmentId'] = assignment['patient_id'];

          print('    -> ✅ Updated user ${users[userIndex]['name']}:');
          print('       - assignedDoctor: ${users[userIndex]['assignedDoctor']}');
          print('       - doctor_name: ${users[userIndex]['doctor_name']}');
          print('       - assignedDoctorId: ${users[userIndex]['assignedDoctorId']}');
        } else {
          print('    -> ❌ WARNING: Could not find user with Patient ID $patientId');
        }
      }
    }

    print('=== Assignment loading complete ===');
  } catch (e) {
    print('Error loading assignments: $e');
    throw e;
  }
}

  // Search users to invite
  Future<List<Map<String, dynamic>>> searchUsersToInvite(String query) async {
    if (query.isEmpty) {
      return [];
    }

    try {
      print('=== DEBUG: Searching for users to invite ===');
      print('Search query: $query');
      print('Current organization ID: $currentOrganizationId');

      // Get users that match the EMAIL search query
      final searchResponse = await supabase.from('User').select('''
      *,
      Person(*)
    ''').like('email', '$query%');

      print('Search response: ${searchResponse.length} users found');

      if (searchResponse.isEmpty) {
        return [];
      }

      // Get list of user IDs already in this organization as patients
      final existingPatients = await supabase
          .from('Patient')
          .select('user_id')
          .eq('organization_id', currentOrganizationId!);

      final existingUserIds =
          existingPatients.map((p) => p['user_id'].toString()).toSet();

      print('Existing patient user IDs in org: $existingUserIds');

      // Build available users list
      final List<Map<String, dynamic>> availableUsers = [];

      for (var user in searchResponse) {
        final person = user['Person'];
        final userId = user['id'].toString();

        // Skip if user is already a patient in this organization
        if (existingUserIds.contains(userId)) {
          print('Skipping existing patient: $userId');
          continue;
        }

        if (person != null) {
          final firstName = person['first_name']?.toString() ?? '';
          final lastName = person['last_name']?.toString() ?? '';
          final email = user['email']?.toString() ?? '';

          final fullName = firstName.isNotEmpty && lastName.isNotEmpty
              ? '$firstName $lastName'
              : firstName.isNotEmpty
                  ? firstName
                  : lastName.isNotEmpty
                      ? lastName
                      : 'Unknown User';

          availableUsers.add({
            'id': userId,
            'user_id': userId,
            'name': fullName,
            'email': email,
            'phone': person['contact_number'] ?? '',
            'address': person['address'] ?? '',
            'person': person,
          });

          print('Added user to search results: $fullName ($email)');
        }
      }

      print('Available users to invite: ${availableUsers.length}');
      return availableUsers;
    } catch (e, stackTrace) {
      print('=== DEBUG: Error searching users ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Invite user to organization
  Future<Map<String, dynamic>> inviteUser(
      Map<String, dynamic> userToInvite) async {
    try {
      print('=== DEBUG: Inviting user to organization ===');
      print('User to invite: ${userToInvite['name']}');
      print('User ID: ${userToInvite['user_id']}');
      print('Organization ID: $currentOrganizationId');

      // Check if user is already a patient in this organization
      final existingPatient = await supabase
          .from('Patient')
          .select('*')
          .eq('user_id', userToInvite['user_id'])
          .eq('organization_id', currentOrganizationId!)
          .maybeSingle();

      if (existingPatient != null) {
        throw Exception(
            '${userToInvite['name']} is already a patient in this organization');
      }

      // Create patient record with invited status
      final patientData = {
        'user_id': userToInvite['user_id'],
        'organization_id': currentOrganizationId,
        'status': 'invited',
        'created_at': DateTime.now().toIso8601String(),
      };

      print('Creating patient record: $patientData');

      final result =
          await supabase.from('Patient').insert(patientData).select().single();

      print('Patient record created: $result');

      // Return new patient data
      return {
        'id': result['id'].toString(),
        'name': userToInvite['name'],
        'type': 'Patient',
        'email': userToInvite['email'],
        'phone': userToInvite['phone'],
        'address': userToInvite['address'],
        'lastVisit': DateTime.now().toString().split(' ')[0],
        'status': 'invited',
        'assignedDoctor': null,
        'assignedDoctorId': null,
        'assignmentId': null,
        'patientId': result['id'].toString(),
        'personId': userToInvite['person']['id'].toString(),
        'userId': userToInvite['user_id'],
      };
    } catch (e, stackTrace) {
      print('=== DEBUG: Error inviting user ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Approve pending patient
  Future<void> approvePendingPatient(String patientId) async {
    try {
      await supabase
          .from('Patient')
          .update({'status': 'unassigned'}).eq('id', patientId);
    } catch (e) {
      rethrow;
    }
  }

  // Reject pending patient
  Future<void> rejectPendingPatient(String patientId) async {
    try {
      await supabase.from('Patient').update(
          {'organization_id': null, 'status': 'rejected'}).eq('id', patientId);
    } catch (e) {
      rethrow;
    }
  }

  // Save assignment to database
  Future<void> saveAssignmentToDatabase(
      String patientId, String doctorId) async {
    try {
      print("=== DEBUG: Saving assignment to database ===");
      print("Patient ID (from Patient table): $patientId");
      print("Doctor Organization_User ID: $doctorId");

      // Since you've already corrected the FK to reference Patient.id directly,
      // we can insert the patientId directly without any resolution
      final assignmentData = {
        'patient_id': patientId, // This is now the Patient table's id
        'doctor_id': doctorId, // Organization_User table's id
        'status': 'active',
        'assigned_at': DateTime.now().toIso8601String(),
      };

      print("=== DEBUG: Creating assignment with data: $assignmentData ===");

      final response =
          await supabase.from('Doctor_User_Assignment').insert(assignmentData);

      print("=== DEBUG: Assignment saved successfully ===");
    } catch (e) {
      print("=== DEBUG: Error saving assignment ===");
      print("Error: $e");
      rethrow;
    }
  }

  // Remove assignment
  Future<void> removeAssignment(Map<String, dynamic> user) async {
    try {
      // Get the correct patient user ID
      String patientUserId = user['userId'] ?? user['id'];

      // Check if this is a Patient table ID that needs to be converted to User ID
      if (user['userId'] != null) {
        patientUserId = user['userId'];
      } else {
        // Check if the ID is from Patient table
        final patientCheck = await supabase
            .from('Patient')
            .select('user_id')
            .eq('id', user['id'])
            .maybeSingle();

        if (patientCheck != null) {
          patientUserId = patientCheck['user_id'];
          print('Using patient user_id for removal: $patientUserId');
        }
      }

      print('=== DEBUG: Removing assignment for patient: $patientUserId ===');

      // Remove from database
      final result = await supabase
          .from('Doctor_User_Assignment')
          .update({'status': 'inactive'})
          .eq('patient_id', patientUserId)
          .eq('status', 'active')
          .select();

      print('Updated ${result.length} assignment records to inactive');

      // Update patient status back to unassigned
      try {
        final originalPatientId = user['patientId'] ?? user['id'];
        await supabase
            .from('Patient')
            .update({'status': 'unassigned'}).eq('id', originalPatientId);
        print('Updated patient status to unassigned');
      } catch (e) {
        print('Warning: Could not update Patient table status: $e');
      }
    } catch (e) {
      print('Error removing assignment: $e');
      rethrow;
    }
  }

  // Validate user data before assignment
  bool validateUserForAssignment(Map<String, dynamic> user) {
    if (user['id'] == null || user['id'].toString().isEmpty) {
      print('User validation failed: Missing user ID');
      return false;
    }

    if (user['status'] == 'pending') {
      print('User validation failed: User status is pending');
      return false;
    }

    return true;
  }
}
