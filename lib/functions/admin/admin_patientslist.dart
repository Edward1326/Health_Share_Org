// admin_patientslist.dart - Functions for Patient List Management
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPatientListFunctions {
  final SupabaseClient supabase = Supabase.instance.client;
  String? currentOrganizationId;

  /// Initialize with organization ID (call this immediately after login)
  void setOrganizationId(String? organizationId) {
    currentOrganizationId = organizationId;
    print('✅ Organization ID set to: $currentOrganizationId');
  }

  /// Get current organization ID with proper auth chain
  Future<String?> getCurrentOrganizationId() async {
    try {
      // If already set, return it
      if (currentOrganizationId != null) {
        print('✅ Using cached organization ID: $currentOrganizationId');
        return currentOrganizationId;
      }

      final authUser = supabase.auth.currentUser;
      if (authUser == null) {
        print('❌ No authenticated user found');
        return null;
      }

      print('🔍 Fetching organization for auth user: ${authUser.id}');

      // Step 1: Get Person record from auth user
      final personResponse = await supabase
          .from('Person')
          .select('id')
          .eq('auth_user_id', authUser.id)
          .single();

      final personId = personResponse['id'] as String;
      print('✅ Person ID: $personId');

      // Step 2: Get User record from Person
      final userResponse = await supabase
          .from('User')
          .select('id')
          .eq('person_id', personId)
          .single();

      final userId = userResponse['id'] as String;
      print('✅ User ID: $userId');

      // Step 3: Get organization from Organization_User
      final orgUserResponse = await supabase
          .from('Organization_User')
          .select('organization_id, position, department')
          .eq('user_id', userId)
          .single();

      currentOrganizationId = orgUserResponse['organization_id'] as String?;
      print('✅ Organization ID: $currentOrganizationId');
      print('   Position: ${orgUserResponse['position']}');
      print('   Department: ${orgUserResponse['department']}');

      return currentOrganizationId;
    } catch (e, stackTrace) {
      print('❌ Error getting organization ID: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get patient by user ID
  Future<Map<String, dynamic>?> getPatientByUserId(String userId) async {
    try {
      final response = await supabase
          .from('Patient')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error getting patient by user ID: $e');
      return null;
    }
  }

  /// Load patients from Supabase (filtered by organization)
  Future<List<Map<String, dynamic>>> loadUsersFromSupabase() async {
    try {
      print('=== DEBUG: Starting patient loading process ===');
      
      // Ensure we have organization ID
      if (currentOrganizationId == null) {
        print('⚠️ No organization ID set, fetching...');
        await getCurrentOrganizationId();
        
        if (currentOrganizationId == null) {
          print('❌ Failed to get organization ID');
          return [];
        }
      }
      
      print('✅ Current organization ID: $currentOrganizationId');

      // Fetch patients ONLY from the current organization
      print('Step 1: Fetching Patient records for organization...');
      final patientsResponse = await supabase.from('Patient').select('''
          *,
          User!inner(
            *,
            Person!inner(*)
          )
        ''').eq('organization_id', currentOrganizationId!);

      print('📋 Patient records found: ${patientsResponse.length}');

      if (patientsResponse.isEmpty) {
        print('ℹ️ No Patient records found for organization: $currentOrganizationId');
        return [];
      }

      // Build the patients list
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
            'organizationId': currentOrganizationId,
          };

          loadedUsers.add(userMap);
        }
      }

      print('\n=== DEBUG: Patient Loading Results ===');
      print('Organization: $currentOrganizationId');
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

  /// Load doctors from Supabase (filtered by organization)
  Future<List<Map<String, dynamic>>> loadDoctorsFromSupabase() async {
    try {
      print('=== DEBUG: Fetching Doctor/Employee records ===');
      
      // Ensure we have organization ID
      if (currentOrganizationId == null) {
        await getCurrentOrganizationId();
        if (currentOrganizationId == null) {
          print('❌ No organization ID available');
          return [];
        }
      }
      
      print('Current organization ID: $currentOrganizationId');

      // Fetch employees ONLY from current organization
      final orgUsersResponse = await supabase
          .from('Organization_User')
          .select('*, User!inner(*, Person!inner(*))')
          .eq('organization_id', currentOrganizationId!);

      print('Organization_User records found: ${orgUsersResponse.length}');

      if (orgUsersResponse.isEmpty) {
        return [];
      }

      // Build the doctors list
      final List<Map<String, dynamic>> loadedDoctors = [];

      print('\n=== DEBUG: Processing each Organization_User record ===');

      for (var orgUser in orgUsersResponse) {
        final user = orgUser['User'];
        final person = user?['Person'];

        final position = orgUser['position']?.toString().toLowerCase() ?? '';
        final department = orgUser['department']?.toString().toLowerCase() ?? '';

        print('Processing employee from org $currentOrganizationId:');
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
            department.contains('obgyn') ||
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
          print('  - ✅ ADDED as doctor: $doctorName');
        }
      }

      print('\n=== DEBUG: Doctor Loading Results ===');
      print('Organization: $currentOrganizationId');
      print('Total doctors identified: ${loadedDoctors.length}');

      return loadedDoctors;
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading doctors ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Load assignments from database
  Future<void> loadAssignmentsFromDatabase(
      List<Map<String, dynamic>> users) async {
    try {
      print('=== DEBUG: Loading assignments ===');

      // Extract patient IDs from users (these are Patient table IDs)
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

            print('    -> ✅ Updated user ${users[userIndex]['name']}');
          } else {
            print(
                '    -> ⚠️ WARNING: Could not find user with Patient ID $patientId');
          }
        }
      }

      print('=== Assignment loading complete ===');
    } catch (e) {
      print('Error loading assignments: $e');
      throw e;
    }
  }

  /// Search users to invite (excludes users already in this organization)
  Future<List<Map<String, dynamic>>> searchUsersToInvite(String query) async {
    if (query.isEmpty) {
      return [];
    }

    try {
      // Ensure we have organization ID
      if (currentOrganizationId == null) {
        await getCurrentOrganizationId();
        if (currentOrganizationId == null) {
          return [];
        }
      }

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

  /// Invite user to organization
  Future<Map<String, dynamic>> inviteUser(
      Map<String, dynamic> userToInvite) async {
    try {
      // Ensure we have organization ID
      if (currentOrganizationId == null) {
        await getCurrentOrganizationId();
        if (currentOrganizationId == null) {
          throw Exception('No organization ID available');
        }
      }

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
        'organizationId': currentOrganizationId,
      };
    } catch (e, stackTrace) {
      print('=== DEBUG: Error inviting user ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Approve pending patient
  Future<void> approvePendingPatient(String patientId) async {
    try {
      await supabase
          .from('Patient')
          .update({'status': 'unassigned'}).eq('id', patientId);
    } catch (e) {
      rethrow;
    }
  }

  /// Reject pending patient
  Future<void> rejectPendingPatient(String patientId) async {
    try {
      await supabase.from('Patient').update(
          {'organization_id': null, 'status': 'rejected'}).eq('id', patientId);
    } catch (e) {
      rethrow;
    }
  }

  /// Save assignment to database
  Future<void> saveAssignmentToDatabase(
      String patientId, String doctorId) async {
    try {
      print("=== DEBUG: Saving assignment to database ===");
      print("Patient ID (from Patient table): $patientId");
      print("Doctor Organization_User ID: $doctorId");

      final assignmentData = {
        'patient_id': patientId,
        'doctor_id': doctorId,
        'status': 'active',
        'assigned_at': DateTime.now().toIso8601String(),
      };

      print("=== DEBUG: Creating assignment with data: $assignmentData ===");

      await supabase.from('Doctor_User_Assignment').insert(assignmentData);

      print("=== DEBUG: Assignment saved successfully ===");
    } catch (e) {
      print("=== DEBUG: Error saving assignment ===");
      print("Error: $e");
      rethrow;
    }
  }

  /// Remove assignment
  Future<void> removeAssignment(Map<String, dynamic> user) async {
    try {
      String patientUserId = user['userId'] ?? user['id'];

      if (user['userId'] != null) {
        patientUserId = user['userId'];
      } else {
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

      final result = await supabase
          .from('Doctor_User_Assignment')
          .update({'status': 'inactive'})
          .eq('patient_id', patientUserId)
          .eq('status', 'active')
          .select();

      print('Updated ${result.length} assignment records to inactive');

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

  /// Validate user data before assignment
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