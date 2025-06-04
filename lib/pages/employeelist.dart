import 'package:flutter/material.dart';

// Employee List Page
class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  final List<Map<String, dynamic>> employees = [
    {
      'name': 'Dr. Sarah Johnson', 
      'role': 'Cardiologist', 
      'status': 'Active',
      'id': 'EMP001',
      'assignedPatients': ['John Smith', 'Mary Johnson'],
      'email': 'sarah.johnson@hospital.com',
      'phone': '+1 234-567-8901',
      'hireDate': '01/15/2022'
    },
    {
      'name': 'Dr. Michael Chen', 
      'role': 'Neurologist', 
      'status': 'Active',
      'id': 'EMP002',
      'assignedPatients': ['Robert Davis'],
      'email': 'michael.chen@hospital.com',
      'phone': '+1 234-567-8902',
      'hireDate': '03/20/2022'
    },
    {
      'name': 'Nurse Emma Wilson', 
      'role': 'Registered Nurse', 
      'status': 'Active',
      'id': 'EMP003',
      'assignedPatients': ['John Smith', 'Mary Johnson', 'Robert Davis'],
      'email': 'emma.wilson@hospital.com',
      'phone': '+1 234-567-8903',
      'hireDate': '05/10/2022'
    },
    {
      'name': 'Dr. James Rodriguez', 
      'role': 'Pediatrician', 
      'status': 'On Leave',
      'id': 'EMP004',
      'assignedPatients': [],
      'email': 'james.rodriguez@hospital.com',
      'phone': '+1 234-567-8904',
      'hireDate': '08/12/2021'
    },
    {
      'name': 'Tech Lisa Brown', 
      'role': 'Lab Technician', 
      'status': 'Active',
      'id': 'EMP005',
      'assignedPatients': [],
      'email': 'lisa.brown@hospital.com',
      'phone': '+1 234-567-8905',
      'hireDate': '11/05/2023'
    },
  ];

  // Organization members who signed up but aren't employees yet
  final List<Map<String, dynamic>> organizationMembers = [
    {
      'name': 'Dr. Amanda Davis',
      'specialization': 'Orthopedic Surgeon',
      'email': 'amanda.davis@email.com',
      'phone': '+1 555-0101',
      'signupDate': '2024-05-15',
      'verified': true,
      'experience': '8 years',
      'license': 'MD-12345',
      'location': 'New York, NY'
    },
    {
      'name': 'Nurse Patricia Lee',
      'specialization': 'ICU Nurse',
      'email': 'patricia.lee@email.com',
      'phone': '+1 555-0102',
      'signupDate': '2024-05-20',
      'verified': true,
      'experience': '5 years',
      'license': 'RN-67890',
      'location': 'Brooklyn, NY'
    },
    {
      'name': 'Dr. Robert Kim',
      'specialization': 'Radiologist',
      'email': 'robert.kim@email.com',
      'phone': '+1 555-0103',
      'signupDate': '2024-05-22',
      'verified': false,
      'experience': '12 years',
      'license': 'MD-54321',
      'location': 'Manhattan, NY'
    },
    {
      'name': 'Tech Monica Garcia',
      'specialization': 'X-Ray Technician',
      'email': 'monica.garcia@email.com',
      'phone': '+1 555-0104',
      'signupDate': '2024-05-25',
      'verified': true,
      'experience': '3 years',
      'license': 'RT-11111',
      'location': 'Queens, NY'
    },
  ];

  final List<String> availablePatients = [
    'John Smith',
    'Mary Johnson', 
    'Robert Davis',
    'Lisa Wilson',
    'David Brown',
    'Sarah Miller',
    'Tom Anderson'
  ];

  void _addEmployeeFromMember(Map<String, dynamic> member) {
    setState(() {
      final newEmployee = {
        'name': member['name'],
        'role': member['specialization'],
        'status': 'Active',
        'id': 'EMP${(employees.length + 1).toString().padLeft(3, '0')}',
        'assignedPatients': <String>[],
        'email': member['email'],
        'phone': member['phone'],
        'hireDate': DateTime.now().toString().substring(0, 10),
      };
      employees.add(newEmployee);
      organizationMembers.removeWhere((m) => m['email'] == member['email']);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${member['name']} has been added as an employee!'),
        backgroundColor: Colors.green,
      ),
    );
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
              Expanded(
                child: organizationMembers.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No pending organization members',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: organizationMembers.length,
                        itemBuilder: (context, index) {
                          final member = organizationMembers[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: member['verified'] ? Colors.green : Colors.orange,
                                child: Icon(
                                  member['name'].toString().startsWith('Dr.') 
                                      ? Icons.medical_services 
                                      : Icons.work,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(member['name']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(member['specialization']),
                                  Text(
                                    'Signed up: ${member['signupDate']}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (member['verified'])
                                    const Icon(Icons.verified, color: Colors.green, size: 16),
                                  if (!member['verified'])
                                    const Icon(Icons.pending, color: Colors.orange, size: 16),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: member['verified'] 
                                        ? () {
                                            Navigator.pop(context);
                                            _addEmployeeFromMember(member);
                                          }
                                        : null,
                                    icon: const Icon(Icons.person_add, size: 16),
                                    label: const Text('Hire'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    ),
                                  ),
                                ],
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.email, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(member['email']),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.phone, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(member['phone']),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(member['location']),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.work_history, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text('Experience: ${member['experience']}'),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.badge, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text('License: ${member['license']}'),
                                        ],
                                      ),
                                      if (!member['verified']) ...[
                                        const SizedBox(height: 16),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            children: [
                                              Icon(Icons.warning, color: Colors.orange, size: 16),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Profile verification pending. Complete verification before hiring.',
                                                  style: TextStyle(fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
    final pendingMembersCount = organizationMembers.where((m) => m['verified']).length;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Employees'),
        actions: [
          if (organizationMembers.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.people_outline),
                  onPressed: _showOrganizationMembers,
                  tooltip: 'View Organization Members',
                ),
                if (pendingMembersCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$pendingMembersCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
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
          if (organizationMembers.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${organizationMembers.length} Organization Member${organizationMembers.length != 1 ? 's' : ''} Available',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Text(
                          '$pendingMembersCount verified and ready to hire',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _showOrganizationMembers,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('View All'),
                  ),
                ],
              ),
            ),
          Expanded(
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
                      child: Text(employee['name']![0]),
                    ),
                    title: Text(employee['name']!),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(employee['role']!),
                        Text('Assigned Patients: $assignedCount', 
                             style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                        if (employee['role'].toString().contains('Dr.'))
                          IconButton(
                            icon: const Icon(Icons.person_add, color: Colors.blue),
                            onPressed: () => _showPatientAssignmentDialog(context, employee),
                            tooltip: 'Assign Patients',
                          ),
                      ],
                    ),
                    onTap: () => _showEmployeeDetails(context, employee),
                  ),
                );
              },
            ),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Role: ${employee['role']}'),
            Text('Status: ${employee['status']}'),
            Text('Employee ID: ${employee['id']}'),
            Text('Email: ${employee['email'] ?? 'Not provided'}'),
            Text('Phone: ${employee['phone'] ?? 'Not provided'}'),
            const Text('Department: Medical'),
            Text('Hire Date: ${employee['hireDate'] ?? '01/15/2022'}'),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (employee['role'].toString().contains('Dr.'))
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

// Patient Assignment Dialog (unchanged from original)
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