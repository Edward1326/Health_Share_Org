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
  int _selectedIndex = 0;

  // Updated theme colors to match the sidebar design
  static const Color primaryGreen = Color(0xFF4A8B3A);
  static const Color lightGreen = Color(0xFF6BA85A);
  static const Color sidebarGray = Color(0xFFF8F9FA);
  static const Color textGray = Color(0xFF6C757D);
  static const Color darkGray = Color(0xFF495057);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color approvedGreen = Color(0xFF28A745);
  static const Color pendingOrange = Color(0xFFFF9500);

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

    print('=== DEBUG: Starting employee loading process (Email lookup only) ===');

    // Get current user's email
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) throw Exception("No user is logged in");

    print('Current user email: ${currentUser.email}');

    // Find organization by email lookup only
    print('Finding organization by email...');
    final userByEmailResponse = await supabase
        .from('Organization_User')
        .select('''
          organization_id,
          User!inner(email, id, person_id)
        ''')
        .eq('User.email', currentUser.email)
        .maybeSingle();

    if (userByEmailResponse == null) {
      throw Exception("Current user (${currentUser.email}) is not associated with any organization. Please contact your administrator to add you to an organization.");
    }

    final currentOrganizationId = userByEmailResponse['organization_id'];
    print('Found organization by email: $currentOrganizationId');

    // Fetch all employees in the same organization
    print('Fetching all employees in organization...');
    final employeesResponse = await supabase.from('Organization_User').select('''
      *,
      User!inner(
        *,
        Person!inner(*)
      )
    ''').eq('organization_id', currentOrganizationId);

    print('Organization_User records found: ${employeesResponse.length}');

    if (employeesResponse.isEmpty) {
      setState(() {
        employees = [];
        isLoading = false;
        errorMessage = 'No employees found in this organization.';
      });
      return;
    }

    // Build the employees list
    print('Building employee list...');
    final List<Map<String, dynamic>> loadedEmployees = [];

    for (var orgUser in employeesResponse) {
      final user = orgUser['User'];
      final person = user?['Person'];

      if (person != null) {
        // Build full name with fallbacks
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
          'id': orgUser['id'].toString(),
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
          'user_id': orgUser['user_id'],
          'person_id': person['id'].toString(),
          'organization_id': orgUser['organization_id'],
          'position': orgUser['position'] ?? 'Staff',
          'created_at': orgUser['created_at'],
        };

        loadedEmployees.add(employee);
        print('Added employee: ${employee['name']} (${employee['role']})');
      }
    }

    print('=== Total employees loaded: ${loadedEmployees.length} ===');

    setState(() {
      employees = loadedEmployees;
      isLoading = false;
    });
  } catch (e, stackTrace) {
    print('=== ERROR loading employees ===');
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
                    colors: [primaryGreen, lightGreen],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Medical professionals who signed up to join your organization',
                style: TextStyle(color: textGray, fontSize: 16),
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
                            color: textGray,
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
    // Get screen size for responsive design
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    return Scaffold(
      backgroundColor: sidebarGray,
      body: SafeArea(
        child: isSmallScreen 
          ? _buildMobileLayout() // Mobile layout (original design)
          : _buildDesktopLayout(), // Desktop layout with sidebar
      ),
    );
  }

  // Mobile layout - original design
  Widget _buildMobileLayout() {
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
              colors: [primaryGreen, lightGreen],
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
                    backgroundColor: primaryGreen,
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
            child: _buildEmployeeContent(),
          ),
        ],
      ),
    );
  }

  // Desktop layout - sidebar + main content (matches the dashboard design)
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Sidebar Navigation
        _buildSidebar(),
        
        // Main Content Area
        Expanded(
          child: Column(
            children: [
              // Top Header Bar (Green)
              _buildTopHeader(),
              
              // Main Content
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: _buildMainContent(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Left sidebar navigation
  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: sidebarGray,
      child: Column(
        children: [
          // Dashboard Title
          Container(
            padding: const EdgeInsets.all(24),
            child: const Text(
              'Dashboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: darkGray,
              ),
            ),
          ),
          
          // Navigation Items
          _buildNavItem(Icons.home, 'Dashboard', 0, false),
          _buildNavItem(Icons.people, 'Employees', 1, true),
          _buildNavItem(Icons.local_hospital, 'Patients', 2, false),
          _buildNavItem(Icons.folder, 'All Files', 3, false),
          _buildNavItem(Icons.settings, 'Settings', 4, false),
          
          const Spacer(),
          
          // Logout Button
          Container(
            padding: const EdgeInsets.all(24),
            child: InkWell(
              onTap: () {
                // Navigate back to dashboard
                Navigator.pop(context);
              },
              child: const Row(
                children: [
                  Icon(Icons.arrow_back, color: textGray, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Back to Dashboard',
                    style: TextStyle(
                      color: textGray,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Navigation item builder
  Widget _buildNavItem(IconData icon, String title, int index, bool isSelected) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? primaryGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });

          // Handle navigation based on index
          switch (index) {
            case 0: // Dashboard
              Navigator.pop(context);
              break;
            case 2: // Patients
              // Navigate to patients if you have that page
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Patients navigation coming soon!')),
              );
              break;
            case 3: // All Files
              // Navigate to files if you have that page
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Files navigation coming soon!')),
              );
              break;
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : textGray,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : textGray,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Top header bar (green)
  Widget _buildTopHeader() {
    return Container(
      height: 60,
      color: primaryGreen,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Icon(Icons.menu, color: Colors.white),
          const SizedBox(width: 16),
          const Icon(Icons.people, color: Colors.white),
          const SizedBox(width: 16),
          const Icon(Icons.refresh, color: Colors.white),
          
          const Spacer(),
          
          // Right side icons and actions
          Row(
            children: [
              const Text(
                'Employee Management',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _showOrganizationMembers,
                  icon: const Icon(Icons.people_outline, color: Colors.white, size: 20),
                  tooltip: 'Organization Members',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () {
                    _loadEmployeesFromSupabase();
                    _loadAvailablePatients();
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                  tooltip: 'Refresh',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Main content area
  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and Add new employee button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'List of employees',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Add employee feature coming soon!'),
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add new employee'),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Error message
          if (errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE57373)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Color(0xFFE57373)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Color(0xFFD32F2F)),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _loadEmployeesFromSupabase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE57373),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          
          // Data table or loading/empty state
          isLoading 
            ? _buildLoadingState()
            : employees.isEmpty 
              ? _buildEmptyState()
              : _buildEmployeesTable(),
        ],
      ),
    );
  }

  // Loading state for desktop
  Widget _buildLoadingState() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryGreen),
            SizedBox(height: 16),
            Text(
              'Loading employees...',
              style: TextStyle(
                fontSize: 16,
                color: textGray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Empty state for desktop
  Widget _buildEmptyState() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Color(0xFFBDBDBD)),
            SizedBox(height: 24),
            Text(
              'No employees found',
              style: TextStyle(
                fontSize: 20,
                color: textGray,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Add employees to your organization',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFFBDBDBD),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Employees data table for desktop
  Widget _buildEmployeesTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Employee', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textGray))),
                Expanded(flex: 1, child: Text('ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textGray))),
                Expanded(flex: 2, child: Text('Contact', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textGray))),
                Expanded(flex: 2, child: Text('Phone number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textGray))),
                Expanded(flex: 1, child: Text('Department', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textGray))),
                Expanded(flex: 1, child: Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textGray))),
                SizedBox(width: 40),
              ],
            ),
          ),
          
          // Table rows
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final employee = employees[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: index < employees.length - 1 ? const Color(0xFFE5E7EB) : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Employee name with avatar
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: _getAvatarColor(employee['role']),
                            child: Text(
                              employee['name']!.isNotEmpty ? employee['name']![0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  employee['name']!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                                Text(
                                  employee['role']!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: textGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // ID
                    Expanded(
                      flex: 1,
                      child: Text(
                        employee['id']!,
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                    ),
                    
                    // Email
                    Expanded(
                      flex: 2,
                      child: Text(
                        employee['email']!,
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                    ),
                    
                    // Phone
                    Expanded(
                      flex: 2,
                      child: Text(
                        employee['phone']!.isNotEmpty ? employee['phone']! : 'Not provided',
                        style: TextStyle(
                          fontSize: 14, 
                          color: employee['phone']!.isNotEmpty ? Colors.black : textGray,
                        ),
                      ),
                    ),
                    
                    // Department
                    Expanded(
                      flex: 1,
                      child: Text(
                        employee['department']!,
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                    ),
                    
                    // Status
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: employee['status'] == 'Active' 
                            ? const Color(0xFFDCFCE7) 
                            : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          employee['status']!,
                          style: TextStyle(
                            fontSize: 12,
                            color: employee['status'] == 'Active' 
                              ? approvedGreen 
                              : pendingOrange,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    
                    // Actions
                    SizedBox(
                      width: 40,
                      child: PopupMenuButton(
                        icon: const Icon(
                          Icons.more_horiz,
                          color: textGray,
                          size: 20,
                        ),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'view',
                            child: Row(
                              children: [
                                Icon(Icons.visibility, color: primaryGreen, size: 16),
                                SizedBox(width: 8),
                                Text('View Details'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, color: Colors.blue, size: 16),
                                SizedBox(width: 8),
                                Text('Edit Position'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 16),
                                SizedBox(width: 8),
                                Text('Remove', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          switch (value) {
                            case 'view':
                              _showEmployeeDetails(context, employee);
                              break;
                            case 'edit':
                              _showEditPositionDialog(context, employee);
                              break;
                            case 'delete':
                              _showDeleteConfirmation(context, employee);
                              break;
                          }
                        },
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

  // Employee content for mobile
  Widget _buildEmployeeContent() {
    if (isLoading) {
      return Center(
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
                valueColor: AlwaysStoppedAnimation<Color>(primaryGreen),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Loading employees...',
              style: TextStyle(
                fontSize: 16,
                color: textGray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    if (employees.isEmpty) {
      return Center(
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
                color: textGray,
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
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        await _loadEmployeesFromSupabase();
        await _loadAvailablePatients();
      },
      color: primaryGreen,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: employees.length,
        itemBuilder: (context, index) {
          final employee = employees[index];
          final assignedCount = (employee['assignedPatients'] as List).length;

          // Determine gradient colors based on role
          List<Color> gradientColors = _getGradientColors(employee['role']);

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
                onTap: () => _showEmployeeDetails(context, employee),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (employee['department'] != null &&
                                employee['department']!.isNotEmpty)
                              Text(
                                employee['department'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Patients: $assignedCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.9),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
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
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
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
                                    leading: Icon(Icons.edit, color: primaryGreen),
                                    title: Text('Edit Position'),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete, color: Color(0xFFE57373)),
                                    title: Text(
                                      'Remove Employee',
                                      style: TextStyle(color: Color(0xFFE57373)),
                                    ),
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditPositionDialog(context, employee);
                                } else if (value == 'delete') {
                                  _showDeleteConfirmation(context, employee);
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
    );
  }

  // Helper method to get avatar colors
  Color _getAvatarColor(String role) {
    if (role.toLowerCase().contains('doctor') || role.toLowerCase().contains('dr')) {
      return const Color(0xFF667EEA);
    } else if (role.toLowerCase().contains('nurse')) {
      return const Color(0xFF6B73FF);
    } else if (role.toLowerCase().contains('admin') || role.toLowerCase().contains('manager')) {
      return const Color(0xFF11998E);
    } else if (role.toLowerCase().contains('therapist')) {
      return const Color(0xFFFF8008);
    } else {
      return primaryGreen;
    }
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
      return [primaryGreen, lightGreen];
    }
  }

  void _showEditPositionDialog(BuildContext context, Map<String, dynamic> employee) {
    final TextEditingController controller = TextEditingController(text: employee['role']);

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
              labelStyle: TextStyle(color: textGray),
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
              foregroundColor: textGray,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [primaryGreen, lightGreen],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _updateEmployeePosition(employee['id'], controller.text.trim());
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

  void _showDeleteConfirmation(BuildContext context, Map<String, dynamic> employee) {
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
                    Icon(Icons.info_outline, color: Color(0xFFE57373), size: 20),
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
              foregroundColor: textGray,
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

  void _showEmployeeDetails(BuildContext context, Map<String, dynamic> employee) {
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
                        _buildDetailItem(Icons.email, 'Email', employee['email']),
                        _buildDetailItem(Icons.phone, 'Phone', employee['phone']),
                        _buildDetailItem(Icons.location_on, 'Address', employee['address']),
                      ]),
                      const SizedBox(height: 24),
                      _buildDetailSection('Employment Details', [
                        _buildDetailItem(Icons.work, 'Position', employee['role']),
                        _buildDetailItem(Icons.business, 'Department', employee['department']),
                        _buildDetailItem(Icons.calendar_today, 'Hire Date', employee['hireDate']),
                        _buildDetailItem(Icons.check_circle, 'Status', employee['status']),
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
                        _buildDetailItem(Icons.fingerprint, 'Employee ID', employee['id']),
                        _buildDetailItem(Icons.person, 'User ID', employee['user_id']?.toString() ?? 'N/A'),
                        _buildDetailItem(Icons.badge, 'Person ID', employee['person_id']?.toString() ?? 'N/A'),
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
                            colors: [primaryGreen, lightGreen],
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
              color: primaryGreen,
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
                    color: textGray,
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