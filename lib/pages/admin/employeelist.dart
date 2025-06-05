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
  bool isLoading = true;
  String? errorMessage;

  final List<String> availablePatients = [
    'John Smith',
    'Mary Johnson', 
    'Robert Davis',
    'Lisa Wilson',
    'David Brown',
    'Sarah Miller',
    'Tom Anderson'
  ];

  @override
  void initState() {
    super.initState();
    _loadEmployeesFromSupabase();
  }

  Future<void> _loadEmployeesFromSupabase() async {
  try {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    // STEP 1: Debug - Check Organization_User table
    print('=== DEBUG: Fetching Organization_User records ===');
    final orgUsersResponse = await supabase
        .from('Organization_User')
        .select('*');
    
    print('Organization_User records found: ${orgUsersResponse.length}');
    print('Organization_User data: $orgUsersResponse');

    if (orgUsersResponse.isEmpty) {
      print('No Organization_User records found!');
      setState(() {
        employees = [];
        isLoading = false;
        errorMessage = 'No Organization_User records found. Please check if employees are properly added to the organization.';
      });
      return;
    }

    // STEP 2: Debug - Extract user IDs
    final userIds = orgUsersResponse.map((item) => item['user_id']).toList();
    print('User IDs to fetch: $userIds');

    // STEP 3: Debug - Check Person records
    print('=== DEBUG: Fetching Person records ===');
    final personsResponse = await supabase
        .from('Person')
        .select('*')
        .in_('id', userIds);
    
    print('Person records found: ${personsResponse.length}');
    print('Person data: $personsResponse');

    // STEP 4: Debug - Check if user_ids match person ids
    final personIds = personsResponse.map((p) => p['id']).toList();
    print('Person IDs found: $personIds');
    print('Missing Person records for user_ids: ${userIds.where((id) => !personIds.contains(id)).toList()}');

    // Create a map for quick person lookup
    final Map<dynamic, Map<String, dynamic>> personsMap = {};
    for (var person in personsResponse) {
      personsMap[person['id']] = person;
      print('Person mapped: ID=${person['id']}, Name=${person['name']}');
    }

    // STEP 5: Debug - Build employee list
    print('=== DEBUG: Building employee list ===');
    final List<Map<String, dynamic>> builtEmployees = [];
    
    for (var orgUser in orgUsersResponse) {
      print('\nProcessing Organization_User: $orgUser');
      final person = personsMap[orgUser['user_id']];
      print('Found Person for user_id ${orgUser['user_id']}: $person');
      
      final fullName = person != null 
          ? (person['name'] ?? person['first_name'] ?? 'Unknown') // Try both 'name' and 'first_name'
          : 'Unknown User ID: ${orgUser['user_id']}';
      
      final employee = {
        'id': orgUser['id'].toString(),
        'name': fullName,
        'role': orgUser['position'] ?? 'Staff',
        'department': orgUser['department'] ?? 'General',
        'status': 'Active',
        'assignedPatients': <String>[],
        'email': person?['email'] ?? '', // Check if email exists in Person table
        'phone': person?['contact_number'] ?? '',
        'address': person?['address'] ?? '',
        'hireDate': orgUser['created_at'] != null 
            ? DateTime.parse(orgUser['created_at']).toString().substring(0, 10)
            : DateTime.now().toString().substring(0, 10),
        'user_id': orgUser['user_id'],
        'organization_id': orgUser['organization_id'],
      };
      
      print('Built employee: $employee');
      builtEmployees.add(employee);
    }

    print('\n=== DEBUG: Final Results ===');
    print('Total employees built: ${builtEmployees.length}');

    setState(() {
      employees = builtEmployees;
      isLoading = false;
    });

  } catch (e, stackTrace) {
    print('=== DEBUG: Error occurred ===');
    print('Error: $e');
    print('Stack trace: $stackTrace');
    
    setState(() {
      errorMessage = 'Error loading employees: $e';
      isLoading = false;
    });
  }
}

  Future<void> _addEmployeeFromMember(Map<String, dynamic> member) async {
    try {
      // Insert new employee into Organization_User table
      final response = await supabase
          .from('Organization_User')
          .insert({
            'user_id': member['user_id'], // You'll need to get this from the member data
            'organization_id': 1, // Replace with actual organization ID
            'position': member['specialization'],
            'department': member['department'] ?? 'Medical',
          })
          .select()
          .single();

      if (response != null) {
        // Reload the employees list
        await _loadEmployeesFromSupabase();
        
        // Remove from organization members (if you have a separate table for pending members)
        setState(() {
          organizationMembers.removeWhere((m) => m['email'] == member['email']);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member['name']} has been added as an employee!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error adding employee: $e');
    }
  }

  Future<void> _deleteEmployee(String employeeId) async {
    try {
      await supabase
          .from('Organization_User')
          .delete()
          .eq('id', employeeId);
      
      // Reload the employees list
      await _loadEmployeesFromSupabase();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee removed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error deleting employee: $e');
    }
  }

  Future<void> _updateEmployeePosition(String employeeId, String newPosition) async {
    try {
      await supabase
          .from('Organization_User')
          .update({'position': newPosition})
          .eq('id', employeeId);
      
      // Reload the employees list
      await _loadEmployeesFromSupabase();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee position updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating employee: $e'),
            backgroundColor: Colors.red,
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
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Organization Members',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const Text(
                'Medical professionals who signed up to join your organization',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No pending organization members',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'You can add members directly from your user management system',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
      appBar: AppBar(
        title: const Text('Manage Employees'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: _showOrganizationMembers,
            tooltip: 'View Organization Members',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployeesFromSupabase,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Manual add employee feature coming soon!')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (errorMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadEmployeesFromSupabase,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading employees...'),
                      ],
                    ),
                  )
                : employees.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No employees found',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Add employees to your organization',
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadEmployeesFromSupabase,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: employees.length,
                          itemBuilder: (context, index) {
                            final employee = employees[index];
                            final assignedCount = (employee['assignedPatients'] as List).length;
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: employee['status'] == 'Active' ? Colors.green : Colors.orange,
                                  child: Text(
                                    employee['name']!.isNotEmpty 
                                        ? employee['name']![0].toUpperCase()
                                        : '?',
                                  ),
                                ),
                                title: Text(employee['name']!),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(employee['role']!),
                                    if (employee['department'] != null && employee['department']!.isNotEmpty)
                                      Text(
                                        'Department: ${employee['department']}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    Text(
                                      'Assigned Patients: $assignedCount', 
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(employee['status']!),
                                      backgroundColor: employee['status'] == 'Active' 
                                          ? Colors.green.withOpacity(0.2) 
                                          : Colors.orange.withOpacity(0.2),
                                    ),
                                    const SizedBox(width: 8),
                                    PopupMenuButton(
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: ListTile(
                                            leading: Icon(Icons.edit),
                                            title: Text('Edit Position'),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: ListTile(
                                            leading: Icon(Icons.delete, color: Colors.red),
                                            title: Text('Remove Employee', style: TextStyle(color: Colors.red)),
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
                                  ],
                                ),
                                onTap: () => _showEmployeeDetails(context, employee),
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

  void _showEditPositionDialog(BuildContext context, Map<String, dynamic> employee) {
    final TextEditingController controller = TextEditingController(text: employee['role']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Position for ${employee['name']}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Position',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateEmployeePosition(employee['id'], controller.text);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Employee'),
        content: Text('Are you sure you want to remove ${employee['name']} from the organization?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteEmployee(employee['id']);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEmployeeDetails(BuildContext context, Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(employee['name']!),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Position: ${employee['role']}'),
              Text('Department: ${employee['department'] ?? 'Not specified'}'),
              Text('Status: ${employee['status']}'),
              Text('Employee ID: ${employee['id']}'),
              Text('Phone: ${employee['phone'] ?? 'Not provided'}'),
              Text('Address: ${employee['address'] ?? 'Not provided'}'),
              Text('Hire Date: ${employee['hireDate']}'),
              const SizedBox(height: 16),
              const Text('Assigned Patients:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...(employee['assignedPatients'] as List<String>).map(
                (patient) => Text('• $patient'),
              ),
              if ((employee['assignedPatients'] as List).isEmpty)
                const Text('No patients assigned', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (employee['role'].toString().toLowerCase().contains('dr') || 
              employee['role'].toString().toLowerCase().contains('doctor'))
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showPatientAssignmentDialog(context, employee);
              },
              child: const Text('Assign Patients'),
            ),
        ],
      ),
    );
  }

  void _showPatientAssignmentDialog(BuildContext context, Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => PatientAssignmentDialog(
        employee: employee,
        availablePatients: availablePatients,
        onAssignmentChanged: (updatedEmployee) {
          setState(() {
            final index = employees.indexWhere((e) => e['id'] == updatedEmployee['id']);
            if (index != -1) {
              employees[index] = updatedEmployee;
            }
          });
        },
      ),
    );
  }
}

// Patient Assignment Dialog (unchanged)
class PatientAssignmentDialog extends StatefulWidget {
  final Map<String, dynamic> employee;
  final List<String> availablePatients;
  final Function(Map<String, dynamic>) onAssignmentChanged;

  const PatientAssignmentDialog({
    super.key,
    required this.employee,
    required this.availablePatients,
    required this.onAssignmentChanged,
  });

  @override
  State<PatientAssignmentDialog> createState() => _PatientAssignmentDialogState();
}

class _PatientAssignmentDialogState extends State<PatientAssignmentDialog> {
  late List<String> selectedPatients;

  @override
  void initState() {
    super.initState();
    selectedPatients = List<String>.from(widget.employee['assignedPatients']);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Assign Patients to ${widget.employee['name']}'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Text('Select patients to assign to ${widget.employee['name']}:',
                 style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: widget.availablePatients.length,
                itemBuilder: (context, index) {
                  final patient = widget.availablePatients[index];
                  final isSelected = selectedPatients.contains(patient);
                  
                  return CheckboxListTile(
                    title: Text(patient),
                    subtitle: Text('Patient ID: PAT${(index + 1).toString().padLeft(3, '0')}'),
                    value: isSelected,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedPatients.add(patient);
                        } else {
                          selectedPatients.remove(patient);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Selected: ${selectedPatients.length} patients'),
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
            final updatedEmployee = Map<String, dynamic>.from(widget.employee);
            updatedEmployee['assignedPatients'] = selectedPatients;
            widget.onAssignmentChanged(updatedEmployee);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully assigned ${selectedPatients.length} patients to ${widget.employee['name']}'),
                backgroundColor: Colors.green,
              ),
            );
          },
          child: const Text('Save Assignment'),
        ),
      ],
    );
  }
}