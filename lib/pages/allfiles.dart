import 'package:flutter/material.dart';

// All Files Page
class AllFilesPage extends StatelessWidget {
  const AllFilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final files = [
      {'name': 'Patient_Records_May2024.pdf', 'size': '2.3 MB', 'type': 'PDF', 'date': '2024-05-30'},
      {'name': 'Lab_Results_Johnson.pdf', 'size': '1.1 MB', 'type': 'PDF', 'date': '2024-05-28'},
      {'name': 'X-Ray_Smith_Chest.jpg', 'size': '4.7 MB', 'type': 'Image', 'date': '2024-05-27'},
      {'name': 'Medical_Report_Davis.docx', 'size': '856 KB', 'type': 'Document', 'date': '2024-05-25'},
      {'name': 'Prescription_Wilson.pdf', 'size': '324 KB', 'type': 'PDF', 'date': '2024-05-24'},
      {'name': 'Blood_Test_Results.xlsx', 'size': '1.8 MB', 'type': 'Spreadsheet', 'date': '2024-05-23'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('View All Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Upload feature coming soon!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Filter feature coming soon!')),
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
                          const Text('Total Files', style: TextStyle(fontSize: 12)),
                          Text('${files.length}', 
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
                          const Text('Storage Used', style: TextStyle(fontSize: 12)),
                          const Text('12.4 MB', 
                               style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                IconData fileIcon;
                Color iconColor;
                
                switch (file['type']) {
                  case 'PDF':
                    fileIcon = Icons.picture_as_pdf;
                    iconColor = Colors.red;
                    break;
                  case 'Image':
                    fileIcon = Icons.image;
                    iconColor = Colors.green;
                    break;
                  case 'Document':
                    fileIcon = Icons.description;
                    iconColor = Colors.blue;
                    break;
                  case 'Spreadsheet':
                    fileIcon = Icons.table_chart;
                    iconColor = Colors.orange;
                    break;
                  default:
                    fileIcon = Icons.insert_drive_file;
                    iconColor = Colors.grey;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(fileIcon, color: iconColor, size: 32),
                    title: Text(file['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${file['size']} • ${file['date']}'),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'download',
                          child: Row(
                            children: [
                              Icon(Icons.download),
                              SizedBox(width: 8),
                              Text('Download'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share),
                              SizedBox(width: 8),
                              Text('Share'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$value feature coming soon!')),
                        );
                      },
                    ),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(file['name']!),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Type: ${file['type']}'),
                              Text('Size: ${file['size']}'),
                              Text('Date: ${file['date']}'),
                              const SizedBox(height: 8),
                              const Text('Location: /medical_files/'),
                              const Text('Owner: Admin'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Opening file...')),
                                );
                              },
                              child: const Text('Open'),
                            ),
                          ],
                        ),
                      );
                    },
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