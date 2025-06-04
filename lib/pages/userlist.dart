// User/Patient List Page with Doctor Assignment Feature
import 'package:flutter/material.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  List<Map<String, dynamic>> users = [
    {
      'name': 'John Smith',
      'type': 'Patient',
      'lastVisit': '2024-05-28',
      'assignedDoctor': null,
      'id': 'PAT001',
      'email': 'john.smith@example.com',
      'phone': '+1 234-567-8901'
    },
    {
      'name': 'Mary Johnson',
      'type': 'Patient',
      'lastVisit': '2024-05-30',
      'assignedDoctor': 'Dr. Sarah Wilson',
      'id': 'PAT002',
      'email': 'mary.johnson@example.com',
      'phone': '+1 234-567-8902'
    },
    {
      'name': 'Admin User',
      'type': 'Administrator',
      'lastVisit': '2024-06-01',
      'assignedDoctor': null,
      'id': 'ADM001',
      'email': 'admin@example.com',
      'phone': '+1 234-567-8903'
    },
    {
      'name': 'Robert Davis',
      'type': 'Patient',
      'lastVisit': '2024-05-25',
      'assignedDoctor': null,
      'id': 'PAT003',
      'email': 'robert.davis@example.com',
      'phone': '+1 234-567-8904'
    },
    {
      'name': 'Staff User',
      'type': 'Staff',
      'lastVisit': '2024-06-02',
      'assignedDoctor': null,
      'id': 'STF001',
      'email': 'staff@example.com',
      'phone': '+1 234-567-8905'
    },
  ];

  final List<String> availableDoctors = [
    'Dr. Sarah Wilson',
    'Dr. Michael Brown',
    'Dr. Jennifer Lee',
    'Dr. David Martinez',
    'Dr. Emily Chen',
    'Dr. James Taylor',
  ];

  void _assignDoctor(int userIndex, String doctorName) {
    setState(() {
      users[userIndex]['assignedDoctor'] = doctorName;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Assigned ${users[userIndex]['name']} to $doctorName'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showAssignDoctorDialog(int userIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Assign Doctor to ${users[userIndex]['name']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableDoctors.length,
            itemBuilder: (context, index) {
              final doctor = availableDoctors[index];
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.medical_services, color: Colors.white),
                ),
                title: Text(doctor),
                subtitle: Text('Specialist • Available'),
                onTap: () {
                  Navigator.pop(context);
                  _assignDoctor(userIndex, doctor);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
    final patients = users.where((u) => u['type'] == 'Patient').toList();
    final unassignedPatients = patients.where((p) => p['assignedDoctor'] == null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users/Patients'),
        actions: [
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
                          const Text('Total Users', style: TextStyle(fontSize: 12)),
                          Text('${users.length}', 
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
            child: ListView.builder(
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