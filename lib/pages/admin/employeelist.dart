import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard.dart';
import 'employee_profile.dart'; // Import the employee profile view

class EmployeeContentWidget extends StatefulWidget {
  const EmployeeContentWidget({Key? key}) : super(key: key);

  @override
  State<EmployeeContentWidget> createState() => _EmployeeContentWidgetState();
}

class _EmployeeContentWidgetState extends State<EmployeeContentWidget> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> employees = [];
  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? _selectedEmployee; // Track selected employee for profile view

  static const primaryGreen = DashboardTheme.primaryGreen;
  static const textGray = DashboardTheme.textGray;
  static const approvedGreen = DashboardTheme.approvedGreen;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      setState(() { isLoading = true; errorMessage = null; });

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception("No user logged in");

      final orgResponse = await supabase
          .from('Organization_User')
          .select('organization_id, User!inner(email)')
          .eq('User.email', currentUser.email)
          .maybeSingle();

      if (orgResponse == null) {
        throw Exception("User not in organization");
      }

      final employeesResponse = await supabase
          .from('Organization_User')
          .select('''
            position,
            department,
            User!inner(
              email,
              Person!inner(
                first_name,
                last_name,
                contact_number,
                image
              )
            )
          ''')
          .eq('organization_id', orgResponse['organization_id']);

      final loadedEmployees = <Map<String, dynamic>>[];
      for (var orgUser in employeesResponse) {
        final user = orgUser['User'];
        final person = user?['Person'];
        
        if (person != null && user != null) {
          String name = 'Unknown';
          if (person['first_name'] != null && person['last_name'] != null) {
            name = '${person['first_name']} ${person['last_name']}'.trim();
          }

          loadedEmployees.add({
            'name': name,
            'role': orgUser['position'] ?? 'Staff',
            'department': orgUser['department'] ?? 'General',
            'status': 'Active',
            'email': user['email'] ?? '',
            'phone': person['contact_number'] ?? '',
            'image': person['image'],
          });
        }
      }

      setState(() { employees = loadedEmployees; isLoading = false; });
    } catch (e) {
      print('Error loading employees: $e');
      setState(() { errorMessage = 'Error: $e'; isLoading = false; });
    }
  }

  Future<void> _deleteEmployee(String email) async {
  try {
    // First, get the user_id and person_id
    final userResponse = await supabase
        .from('User')
        .select('id, person_id')
        .eq('email', email)
        .maybeSingle();
    
    if (userResponse != null) {
      final userId = userResponse['id'];
      final personId = userResponse['person_id'];
      
      // Delete in order: Organization_User -> User -> Person
      // 1. Delete from Organization_User
      await supabase
          .from('Organization_User')
          .delete()
          .eq('user_id', userId);
      
      // 2. Delete from User
      await supabase
          .from('User')
          .delete()
          .eq('id', userId);
      
      // 3. Delete from Person (if person_id exists)
      if (personId != null) {
        await supabase
            .from('Person')
            .delete()
            .eq('id', personId);
      }
      
      _loadEmployees();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee removed successfully!')),
        );
      }
    }
  } catch (e) {
    print('Error deleting employee: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

  Future<void> _updatePosition(String email, String newPosition) async {
    try {
      final userResponse = await supabase
          .from('User')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      
      if (userResponse != null) {
        await supabase
            .from('Organization_User')
            .update({'position': newPosition})
            .eq('user_id', userResponse['id']);
        
        _loadEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Position updated!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildEmployeeAvatar(Map<String, dynamic> employee, {double radius = 16}) {
    final imageUrl = employee['image'] as String?;
    final name = employee['name'] as String;
    
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(imageUrl),
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
                color: primaryGreen,
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: radius * 0.75,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      return CircleAvatar(
        radius: radius,
        backgroundColor: primaryGreen,
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.75,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show employee profile if one is selected
    if (_selectedEmployee != null) {
      return EmployeeProfileView(
        employeeData: _selectedEmployee!,
        onBack: () {
          setState(() {
            _selectedEmployee = null;
          });
          _loadEmployees(); // Refresh list in case data was updated
        },
        isViewOnly: true, // Admin viewing only
      );
    }

    // Show employee list
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'List of employees',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _loadEmployees,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryGreen,
                      side: const BorderSide(color: primaryGreen),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          if (errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(errorMessage!)),
                  ElevatedButton(
                    onPressed: _loadEmployees,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          if (isLoading)
            Container(
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
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading employees...'),
                  ],
                ),
              ),
            )
          else if (employees.isEmpty)
            Container(
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
                    Icon(Icons.people_outline, size: 80, color: Colors.grey),
                    SizedBox(height: 24),
                    Text('No employees found', style: TextStyle(fontSize: 18)),
                  ],
                ),
              ),
            )
          else
            _buildEmployeeTable(),
        ],
      ),
    );
  }

  Widget _buildEmployeeTable() {
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Employee', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(flex: 2, child: Text('Email', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(flex: 2, child: Text('Phone', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Department', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Status', style: TextStyle(fontWeight: FontWeight.w500))),
                SizedBox(width: 120), // Increased for View button + menu
              ],
            ),
          ),
          
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final employee = employees[index];
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: index < employees.length - 1 ? Colors.grey.shade200 : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          _buildEmployeeAvatar(employee, radius: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  employee['name']!,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  employee['role']!,
                                  style: TextStyle(fontSize: 12, color: textGray),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    Expanded(
                      flex: 2,
                      child: Text(employee['email']!, overflow: TextOverflow.ellipsis),
                    ),
                    
                    Expanded(
                      flex: 2,
                      child: Text(
                        employee['phone']!.isNotEmpty ? employee['phone']! : 'N/A',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    Expanded(
                      child: Text(employee['department']!, overflow: TextOverflow.ellipsis),
                    ),
                    
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          employee['status']!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: approvedGreen,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    
                    // Actions - View button + Menu
                    SizedBox(
                      width: 120,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // View Button
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedEmployee = employee;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: const Text('View', style: TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          // Menu Button
                          PopupMenuButton(
                            icon: const Icon(Icons.more_horiz, color: textGray),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 8,
                            color: Colors.white,
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: primaryGreen.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.edit_rounded, size: 18, color: primaryGreen),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text('Edit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text('Remove', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showEditDialog(employee);
                              } else if (value == 'delete') {
                                _showDeleteDialog(employee);
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

  void _showEditDialog(Map<String, dynamic> employee) {
    final controller = TextEditingController(text: employee['role']);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFFF8F9FA),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryGreen, const Color(0xFF6BA85A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 40),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text('Edit Employee', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                    const SizedBox(height: 8),
                    Text(employee['name']!, style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: 'Position',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: primaryGreen, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (controller.text.trim().isNotEmpty) {
                                _updatePosition(employee['email'], controller.text.trim());
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Update', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
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

  void _showDeleteDialog(Map<String, dynamic> employee) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFFF8F9FA),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_remove_rounded, color: Colors.white, size: 40),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('Remove Employee', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                      'Are you sure you want to remove ${employee['name']} from the organization?\n\nThis action cannot be undone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              _deleteEmployee(employee['email']);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade500,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Remove', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
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
}

class EmployeeListPage extends StatelessWidget {
  const EmployeeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    if (isSmallScreen) {
      return _MobileEmployeeView();
    }

    return const MainDashboardLayout(
      title: 'Employee Management',
      selectedNavIndex: 1,
      content: EmployeeContentWidget(),
    );
  }
}

class _MobileEmployeeView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        backgroundColor: DashboardTheme.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: const EmployeeContentWidget(),
    );
  }
}