import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Employee List Page
class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> employees = [];
  List<Map<String, dynamic>> organizationMembers = [];
  List<Map<String, dynamic>> availablePatients = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadEmployeesFromSupabase();
    _loadAvailablePatients();
  }

  // New method to load actual patients (excluding employees)
  Future<void> _loadAvailablePatients() async {
    try {
      // First, get all employee person_ids to exclude them
      final orgUsersResponse =
          await supabase.from('Organization_User').select('*');
      final userIds = orgUsersResponse.map((item) => item['user_id']).toList();

      final usersResponse = await supabase
          .from('User')
          .select('id, person_id')
          .in_('id', userIds);

      final employeePersonIds =
          usersResponse.map((user) => user['person_id']).toList();

      // Get all persons who are NOT employees
      final patientsResponse = await supabase
          .from('Person')
          .select('*')
          .not('id', 'in', '(${employeePersonIds.join(',')})');

      final List<Map<String, dynamic>> patients = [];
      for (var person in patientsResponse) {
        // Build patient name
        String fullName = 'Unknown Patient';
        if (person['first_name'] != null && person['last_name'] != null) {
          fullName = '${person['first_name']} ${person['last_name']}';
        } else if (person['name'] != null) {
          fullName = person['name'];
        } else if (person['first_name'] != null) {
          fullName = person['first_name'];
        }

        patients.add({
          'id': person['id'],
          'name': fullName,
          'email': person['email'] ?? '',
          'phone': person['contact_number'] ?? '',
          'address': person['address'] ?? '',
        });
      }

      setState(() {
        availablePatients = patients;
      });

      print('Available patients loaded: ${patients.length}');
    } catch (e) {
      print('Error loading patients: $e');
    }
  }

  Future<void> _loadEmployeesFromSupabase() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      print('=== DEBUG: Starting employee loading process ===');

      // Get current user's organization ID
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception("No user is logged in");

      final currentUserOrgResponse = await supabase
          .from('Organization_User')
          .select('organization_id')
          .eq('user_id', currentUser.id)
          .maybeSingle();

      if (currentUserOrgResponse == null) {
        throw Exception("Current user is not associated with any organization");
      }

      final currentOrganizationId = currentUserOrgResponse['organization_id'];
      print('Current organization ID: $currentOrganizationId');

      // Fetch employees using proper joins (similar to patient loading)
      print('Step 1: Fetching Organization_User records with joins...');
      final employeesResponse =
          await supabase.from('Organization_User').select('''
          *,
          User!inner(
            *,
            Person!inner(*)
          )
        ''').eq('organization_id', currentOrganizationId);

      print('Organization_User records found: ${employeesResponse.length}');

      if (employeesResponse.isEmpty) {
        print('No Organization_User records found for organization!');
        setState(() {
          employees = [];
          isLoading = false;
          errorMessage = 'No employees found in this organization.';
        });
        return;
      }

      // Build the employees list
      print('\nStep 2: Building final employee list...');
      final List<Map<String, dynamic>> loadedEmployees = [];

      for (var orgUser in employeesResponse) {
        final user = orgUser['User'];
        final person = user?['Person'];

        print('\nProcessing Organization_User ID: ${orgUser['id']}');
        print('  - Position: ${orgUser['position']}');
        print('  - Department: ${orgUser['department']}');
        print('  - User ID: ${orgUser['user_id']}');
        print('  - Person data: $person');

        if (person != null) {
          // Build full name with multiple fallback options
          String fullName = 'Unknown Employee';

          if (person['first_name'] != null && person['last_name'] != null) {
            fullName = '${person['first_name']} ${person['last_name']}';
          } else if (person['first_name'] != null) {
            fullName = person['first_name'];
          } else if (person['last_name'] != null) {
            fullName = person['last_name'];
          } else if (person['name'] != null) {
            fullName = person['name'];
          }

          final employee = {
            'id': orgUser['id'].toString(), // Organization_User ID
            'name': fullName,
            'role': orgUser['position'] ?? 'Staff',
            'department': orgUser['department'] ?? 'General',
            'status': 'Active',
            'assignedPatients': <String>[],
            'email': person['email'] ?? '',
            'phone': person['contact_number'] ?? '',
            'address': person['address'] ?? '',
            'hireDate': orgUser['created_at'] != null
                ? DateTime.parse(orgUser['created_at'])
                    .toString()
                    .substring(0, 10)
                : DateTime.now().toString().substring(0, 10),
            'user_id': orgUser['user_id'], // Actual User ID
            'person_id': person['id'].toString(), // Person ID
            'organization_id': orgUser['organization_id'],
            // Additional useful fields
            'position': orgUser['position'] ?? 'Staff',
            'created_at': orgUser['created_at'],
          };

          loadedEmployees.add(employee);
          print(
              '  - ADDED employee: ${employee['name']} (${employee['role']})');
        } else {
          print(
              '  - SKIPPED: No person data found for user_id ${orgUser['user_id']}');
        }
      }

      print('\n=== DEBUG: Employee Loading Results ===');
      print('Total employees loaded: ${loadedEmployees.length}');

      // Print summary by department
      final deptCounts = <String, int>{};
      for (var emp in loadedEmployees) {
        final dept = emp['department'] ?? 'Unknown';
        deptCounts[dept] = (deptCounts[dept] ?? 0) + 1;
      }
      print('Department breakdown:');
      deptCounts.forEach((dept, count) {
        print('  - $dept: $count');
      });

      setState(() {
        employees = loadedEmployees;
        isLoading = false;
      });
    } catch (e, stackTrace) {
      print('=== DEBUG: Error loading employees ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');

      setState(() {
        errorMessage = 'Error loading employees: $e';
        isLoading = false;
        employees = [];
      });
    }
  }

// Optional: Add a method to get employee assignment counts
  Future<void> _loadEmployeeAssignments() async {
    try {
      print('=== DEBUG: Loading employee assignments ===');

      // Get all active assignments
      final assignmentsResponse = await supabase
          .from('Doctor_User_Assignment')
          .select('doctor_id, patient_id')
          .eq('status', 'active');

      print('Active assignments found: ${assignmentsResponse.length}');

      // Count assignments per doctor
      final Map<String, List<String>> doctorAssignments = {};
      for (var assignment in assignmentsResponse) {
        final doctorId = assignment['doctor_id'].toString();
        final patientId = assignment['patient_id'].toString();

        if (!doctorAssignments.containsKey(doctorId)) {
          doctorAssignments[doctorId] = [];
        }
        doctorAssignments[doctorId]!.add(patientId);
      }

      // Update employee records with assignment counts
      for (int i = 0; i < employees.length; i++) {
        final employeeId = employees[i]['id'];
        final assignedPatients = doctorAssignments[employeeId] ?? [];

        setState(() {
          employees[i]['assignedPatients'] = assignedPatients;
          employees[i]['patientCount'] = assignedPatients.length;
        });
      }

      print('Employee assignments updated');
    } catch (e) {
      print('Error loading employee assignments: $e');
    }
  }

// Updated method to call both functions
  Future<void> _loadAllEmployeeData() async {
    await _loadEmployeesFromSupabase();
    if (employees.isNotEmpty) {
      await _loadEmployeeAssignments();
    }
  }

  Future<void> _addEmployeeFromMember(Map<String, dynamic> member) async {
    try {
      // Insert new employee into Organization_User table
      final response = await supabase
          .from('Organization_User')
          .insert({
            'user_id': member[
                'user_id'], // You'll need to get this from the member data
            'organization_id': 1, // Replace with actual organization ID
            'position': member['specialization'],
            'department': member['department'] ?? 'Medical',
          })
          .select()
          .single();

      if (response != null) {
        // Reload the employees list
        await _loadEmployeesFromSupabase();
        await _loadAvailablePatients(); // Reload patients to exclude new employee

        // Remove from organization members (if you have a separate table for pending members)
        setState(() {
          organizationMembers.removeWhere((m) => m['email'] == member['email']);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member['name']} has been added as an employee!'),
              backgroundColor: const Color(0xFF4CAF50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding employee: $e'),
            backgroundColor: const Color(0xFFE57373),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      print('Error adding employee: $e');
    }
  }

  Future<void> _deleteEmployee(String employeeId) async {
    try {
      await supabase.from('Organization_User').delete().eq('id', employeeId);

      // Reload the employees list
      await _loadEmployeesFromSupabase();
      await _loadAvailablePatients(); // Reload patients to include removed employee as patient

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Employee removed successfully!'),
            backgroundColor: const Color(0xFF4CAF50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing employee: $e'),
            backgroundColor: const Color(0xFFE57373),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      print('Error deleting employee: $e');
    }
  }

  Future<void> _updateEmployeePosition(
      String employeeId, String newPosition) async {
    try {
      await supabase
          .from('Organization_User')
          .update({'position': newPosition}).eq('id', employeeId);

      // Reload the employees list
      await _loadEmployeesFromSupabase();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Employee position updated successfully!'),
            backgroundColor: const Color(0xFF4CAF50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating employee: $e'),
            backgroundColor: const Color(0xFFE57373),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      print('Error updating employee: $e');
    }
  }

  void _showOrganizationMembers() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF8F9FA), Color(0xFFE3F2FD)],
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Organization Members',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Color(0xFF6C7B7F)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Medical professionals who signed up to join your organization',
                style: TextStyle(color: Color(0xFF6C7B7F), fontSize: 16),
              ),
              const SizedBox(height: 24),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline,
                          size: 80, color: Color(0xFFBDBDBD)),
                      SizedBox(height: 24),
                      Text(
                        'No pending organization members',
                        style: TextStyle(
                            fontSize: 18,
                            color: Color(0xFF6C7B7F),
                            fontWeight: FontWeight.w500),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'You can add members directly from your user management system',
                        style:
                            TextStyle(fontSize: 14, color: Color(0xFFBDBDBD)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Manage Employees',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.people_outline, color: Colors.white),
              onPressed: _showOrganizationMembers,
              tooltip: 'View Organization Members',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                _loadEmployeesFromSupabase();
                _loadAvailablePatients();
              },
              tooltip: 'Refresh',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        const Text('Manual add employee feature coming soon!'),
                    backgroundColor: const Color(0xFF2196F3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (errorMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFEBEE),
                    const Color(0xFFFFCDD2).withOpacity(0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFFE57373).withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE57373),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.error, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                          color: Color(0xFFD32F2F), fontSize: 14),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _loadEmployeesFromSupabase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE57373),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Retry',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF667EEA)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Loading employees...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF6C7B7F),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : employees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
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
                              child: const Icon(
                                Icons.people_outline,
                                size: 80,
                                color: Color(0xFFBDBDBD),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'No employees found',
                              style: TextStyle(
                                fontSize: 20,
                                color: Color(0xFF6C7B7F),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Add employees to your organization',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFFBDBDBD),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _loadEmployeesFromSupabase();
                          await _loadAvailablePatients();
                        },
                        color: const Color(0xFF667EEA),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: employees.length,
                          itemBuilder: (context, index) {
                            final employee = employees[index];
                            final assignedCount =
                                (employee['assignedPatients'] as List).length;

                            // Determine gradient colors based on role
                            List<Color> gradientColors =
                                _getGradientColors(employee['role']);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: gradientColors,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: gradientColors[0].withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () =>
                                      _showEmployeeDetails(context, employee),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.1),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              employee['name']!.isNotEmpty
                                                  ? employee['name']![0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: gradientColors[0],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                employee['name']!,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                employee['role']!,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.white
                                                      .withOpacity(0.9),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (employee['department'] !=
                                                      null &&
                                                  employee['department']!
                                                      .isNotEmpty)
                                                Text(
                                                  employee['department'],
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white
                                                        .withOpacity(0.7),
                                                  ),
                                                ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Patients: $assignedCount',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white
                                                        .withOpacity(0.9),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.9),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                employee['status']!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: gradientColors[0],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: PopupMenuButton(
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                  color: Colors.white,
                                                ),
                                                itemBuilder: (context) => [
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: ListTile(
                                                      leading: Icon(Icons.edit,
                                                          color: Color(
                                                              0xFF667EEA)),
                                                      title:
                                                          Text('Edit Position'),
                                                    ),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: ListTile(
                                                      leading: Icon(
                                                          Icons.delete,
                                                          color: Color(
                                                              0xFFE57373)),
                                                      title: Text(
                                                        'Remove Employee',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFFE57373)),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                onSelected: (value) {
                                                  if (value == 'edit') {
                                                    _showEditPositionDialog(
                                                        context, employee);
                                                  } else if (value ==
                                                      'delete') {
                                                    _showDeleteConfirmation(
                                                        context, employee);
                                                  }
                                                },
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
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  List<Color> _getGradientColors(String role) {
    if (role.toLowerCase().contains('doctor') ||
        role.toLowerCase().contains('dr')) {
      return [const Color(0xFF667EEA), const Color(0xFF764BA2)];
    } else if (role.toLowerCase().contains('nurse')) {
      return [const Color(0xFF6B73FF), const Color(0xFF9B59B6)];
    } else if (role.toLowerCase().contains('admin') ||
        role.toLowerCase().contains('manager')) {
      return [const Color(0xFF11998E), const Color(0xFF38EF7D)];
    } else if (role.toLowerCase().contains('therapist')) {
      return [const Color(0xFFFF8008), const Color(0xFFFFC837)];
    } else {
      return [const Color(0xFF667EEA), const Color(0xFF764BA2)];
    }
  }

  void _showEditPositionDialog(
      BuildContext context, Map<String, dynamic> employee) {
    final TextEditingController controller =
        TextEditingController(text: employee['role']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Edit Position for ${employee['name']}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        content: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE3F2FD)),
          ),
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Position/Role',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              labelStyle: TextStyle(color: Color(0xFF6C7B7F)),
            ),
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF2C3E50),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6C7B7F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _updateEmployeePosition(
                      employee['id'], controller.text.trim());
                  Navigator.pop(context);
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Update'),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(
      BuildContext context, Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFE57373),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Remove Employee',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFEBEE)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to remove ${employee['name']} from the organization?',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF2C3E50),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Color(0xFFE57373), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone. The employee will be removed from all assignments.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6C7B7F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE57373), Color(0xFFEF5350)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteEmployee(employee['id']);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Remove'),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmployeeDetails(
      BuildContext context, Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF8F9FA), Color(0xFFE3F2FD)],
            ),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _getGradientColors(employee['role']),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Employee Details',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              employee['name']!.isNotEmpty
                                  ? employee['name']![0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: _getGradientColors(employee['role'])[0],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee['name']!,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                employee['role']!,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (employee['department'] != null &&
                                  employee['department']!.isNotEmpty)
                                Text(
                                  employee['department'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailSection('Contact Information', [
                        _buildDetailItem(
                            Icons.email, 'Email', employee['email']),
                        _buildDetailItem(
                            Icons.phone, 'Phone', employee['phone']),
                        _buildDetailItem(
                            Icons.location_on, 'Address', employee['address']),
                      ]),
                      const SizedBox(height: 24),
                      _buildDetailSection('Employment Details', [
                        _buildDetailItem(
                            Icons.work, 'Position', employee['role']),
                        _buildDetailItem(Icons.business, 'Department',
                            employee['department']),
                        _buildDetailItem(Icons.calendar_today, 'Hire Date',
                            employee['hireDate']),
                        _buildDetailItem(
                            Icons.check_circle, 'Status', employee['status']),
                      ]),
                      const SizedBox(height: 24),
                      _buildDetailSection('Patient Assignments', [
                        _buildDetailItem(
                          Icons.people,
                          'Assigned Patients',
                          '${(employee['assignedPatients'] as List).length} patients',
                        ),
                      ]),
                      const SizedBox(height: 24),
                      _buildDetailSection('System Information', [
                        _buildDetailItem(
                            Icons.fingerprint, 'Employee ID', employee['id']),
                        _buildDetailItem(Icons.person, 'User ID',
                            employee['user_id']?.toString() ?? 'N/A'),
                        _buildDetailItem(Icons.badge, 'Person ID',
                            employee['person_id']?.toString() ?? 'N/A'),
                        _buildDetailItem(
                            Icons.business_center,
                            'Organization ID',
                            employee['organization_id']?.toString() ?? 'N/A'),
                      ]),
                    ],
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showEditPositionDialog(context, employee);
                          },
                          icon: const Icon(Icons.edit, color: Colors.white),
                          label: const Text(
                            'Edit Position',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE57373), Color(0xFFEF5350)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showDeleteConfirmation(context, employee);
                          },
                          icon: const Icon(Icons.delete, color: Colors.white),
                          label: const Text(
                            'Remove',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 16),
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
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String? value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFF0F0F0),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF667EEA),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6C7B7F),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value ?? 'Not provided',
                  style: TextStyle(
                    fontSize: 16,
                    color: value != null
                        ? const Color(0xFF2C3E50)
                        : const Color(0xFFBDBDBD),
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
}
