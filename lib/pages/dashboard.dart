import 'package:flutter/material.dart';
import 'employeelist.dart';
import 'userlist.dart';
import 'allfiles.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Manage Employees'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeListPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.supervised_user_circle),
            title: const Text('Manage Users/Patients'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const UserListPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_shared),
            title: const Text('View All Files'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AllFilesPage()));
            },
          ),
        ],
      ),
    );
  }
}
