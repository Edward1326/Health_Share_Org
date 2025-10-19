import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard.dart'; // Import your main layout

// Clean, modular Employee Content Widget - just the content part
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

  // Use DashboardTheme colors
  static const primaryGreen = DashboardTheme.primaryGreen;
  static const textGray = DashboardTheme.textGray;
  static const approvedGreen = DashboardTheme.approvedGreen;
  static const pendingOrange = DashboardTheme.pendingOrange;

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

      // Get organization
      final orgResponse = await supabase
          .from('Organization_User')
          .select('organization_id, User!inner(email)')
          .eq('User.email', currentUser.email)
          .maybeSingle();

      if (orgResponse == null) {
        throw Exception("User not in organization");
      }

      // Get employees with proper nested query
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
                contact_number
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
      // Find the user by email first
      final userResponse = await supabase
          .from('User')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      
      if (userResponse != null) {
        await supabase
            .from('Organization_User')
            .delete()
            .eq('user_id', userResponse['id']);
        
        _loadEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Employee removed successfully!')),
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

  Future<void> _updatePosition(String email, String newPosition) async {
    try {
      // Find the user by email first
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
          
          // Error message
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
          
          // Content
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
          // Header
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
                SizedBox(width: 40),
              ],
            ),
          ),
          
          // Rows
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
                    // Name with avatar
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: primaryGreen,
                            child: Text(
                              employee['name']!.isNotEmpty ? employee['name']![0] : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
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
                    
                    // Email
                    Expanded(
                      flex: 2,
                      child: Text(
                        employee['email']!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Phone
                    Expanded(
                      flex: 2,
                      child: Text(
                        employee['phone']!.isNotEmpty ? employee['phone']! : 'N/A',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Department
                    Expanded(
                      child: Text(
                        employee['department']!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Status
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
                    
                    // Actions
                    SizedBox(
                      width: 40,
                      child: PopupMenuButton(
                        icon: const Icon(Icons.more_horiz, color: textGray),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
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
                          if (value == 'edit') {
                            _showEditDialog(employee);
                          } else if (value == 'delete') {
                            _showDeleteDialog(employee);
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

  void _showEditDialog(Map<String, dynamic> employee) {
    final controller = TextEditingController(text: employee['role']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${employee['name']}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Position'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _updatePosition(employee['email'], controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Employee'),
        content: Text('Remove ${employee['name']} from the organization?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _deleteEmployee(employee['email']);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// Updated Employee List Page - super clean now
class EmployeeListPage extends StatelessWidget {
  const EmployeeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    if (isSmallScreen) {
      // Mobile - use your existing mobile layout
      return _MobileEmployeeView();
    }

    // Desktop - use modular layout
    return const MainDashboardLayout(
      title: 'Employee Management',
      selectedNavIndex: 1,
      content: EmployeeContentWidget(),
    );
  }
}

// Simple mobile fallback (you can expand this later)
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