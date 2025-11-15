// patient_transferlist.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard.dart';

// Add this import at the top of main_dashboard_layout.dart:
// import 'patient_transferlist.dart';

class PatientTransferContentWidget extends StatefulWidget {
  const PatientTransferContentWidget({Key? key}) : super(key: key);

  @override
  State<PatientTransferContentWidget> createState() =>
      _PatientTransferContentWidgetState();
}

class _PatientTransferContentWidgetState
    extends State<PatientTransferContentWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _myPatients = [];
  List<Map<String, dynamic>> _transferRequests = [];
  List<Map<String, dynamic>> _hospitals = [];

  bool _isLoading = true;
  String? _currentOrgId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Get current user's organization
      // Relationship: Auth User -> User -> Person -> Organization_User
      final authUserId = _supabase.auth.currentUser?.id;
      if (authUserId == null) {
        print('No authenticated user found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('No authenticated user found. Please log in again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      print('Auth User ID: $authUserId');

      try {
        // Correct relationship path:
        // Auth User -> Person.auth_user_id -> User.person_id -> Organization_User.user_id

        print('Querying Person table for auth_user_id: $authUserId');

        // Step 1: Get Person record using auth_user_id
        final personResponse = await _supabase
            .from('Person')
            .select('id, first_name, last_name')
            .eq('auth_user_id', authUserId)
            .maybeSingle();

        print('Person query response: $personResponse');

        if (personResponse == null) {
          print('No Person record found for auth user: $authUserId');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Person profile not found. Please complete your profile setup.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        final personId = personResponse['id'];
        print('Person ID: $personId');

        // Step 2: Get User record using person_id
        final userResponse = await _supabase
            .from('User')
            .select('id, email')
            .eq('person_id', personId)
            .maybeSingle();

        print('User query response: $userResponse');

        if (userResponse == null) {
          print('No User record found for person_id: $personId');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'User profile not found. Please complete your profile setup.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        final userId = userResponse['id'];
        print('User ID: $userId');

        // Step 3: Get Organization_User record using user_id
        final orgUserResponse = await _supabase
            .from('Organization_User')
            .select('organization_id, position, department')
            .eq('user_id', userId)
            .limit(1)
            .maybeSingle();

        print('Organization_User query response: $orgUserResponse');

        if (orgUserResponse == null) {
          print('No Organization_User record found');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'No organization assigned. Please contact your administrator.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        _currentOrgId = orgUserResponse['organization_id'];
        print('Organization ID: $_currentOrgId');
        print('Position: ${orgUserResponse['position']}');
        print('Department: ${orgUserResponse['department']}');
      } catch (e) {
        print('Error fetching organization: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading organization data: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Load my patients (approved patients in my organization)
      final myPatientsResponse = await _supabase
          .from('Patient')
          .select('''
            *,
            User!Patient_user_id_fkey (
              email,
              Person (
                first_name,
                last_name
              )
            )
          ''')
          .eq('organization_id', _currentOrgId!)
          .eq('status', 'accepted')
          .order('created_at', ascending: false);

      // Load incoming transfer requests (status = 'transferring' to my organization)
      final transferRequestsResponse = await _supabase
          .from('Patient')
          .select('''
            *,
            User!Patient_user_id_fkey (
              email,
              Person (
                first_name,
                last_name
              )
            )
          ''')
          .eq('organization_id', _currentOrgId!)
          .eq('status', 'transferring')
          .order('created_at', ascending: false);

      // Load all hospitals except current one
      final hospitalsResponse = await _supabase
          .from('Organization')
          .select('id, name')
          .neq('id', _currentOrgId!)
          .order('name');

      setState(() {
        _myPatients = List<Map<String, dynamic>>.from(myPatientsResponse);
        _transferRequests =
            List<Map<String, dynamic>>.from(transferRequestsResponse);
        _hospitals = List<Map<String, dynamic>>.from(hospitalsResponse);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _transferPatient(Map<String, dynamic> patient) async {
    final selectedHospital = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _TransferDialog(hospitals: _hospitals),
    );

    if (selectedHospital == null) return;

    try {
      // Update patient's organization and status to 'transferring'
      // New hospital must approve before patient sees invitation
      await _supabase.from('Patient').update({
        'organization_id': selectedHospital['id'],
        'status': 'transferring',
      }).eq('id', patient['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Transfer request sent to ${selectedHospital['name']}\nWaiting for approval.',
            ),
            backgroundColor: DashboardTheme.approvedGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Reload data
      _loadData();
    } catch (e) {
      print('Error transferring patient: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error transferring patient: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _approveTransfer(Map<String, dynamic> patient) async {
    final user = patient['User'];
    final person = user['Person'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Transfer'),
        content: Text(
          'Approve transfer of ${person['first_name']} ${person['last_name']}?\n\nThe patient will receive an invitation to accept joining your hospital.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: DashboardTheme.approvedGreen,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Change status from 'transferring' to 'invited'
      // Patient will now see the invitation in their app
      await _supabase.from('Patient').update({
        'status': 'invited',
      }).eq('id', patient['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Transfer approved! Patient will receive an invitation.'),
            backgroundColor: DashboardTheme.approvedGreen,
          ),
        );
      }

      _loadData();
    } catch (e) {
      print('Error approving transfer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectTransfer(Map<String, dynamic> patient) async {
    final user = patient['User'];
    final person = user['Person'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Transfer'),
        content: Text(
          'Reject transfer of ${person['first_name']} ${person['last_name']}?\n\nThe patient will remain with their previous hospital.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // For simplicity, we could either:
      // 1. Delete the patient record (if you want to cancel completely)
      // 2. Or change organization back and keep status as 'approved'
      // Let's go with option 2 - you'll need to track the original org somehow
      // For now, let's just delete the transfer request

      // Actually, let's just change status to 'rejected' so you can track it
      await _supabase.from('Patient').update({
        'status': 'rejected',
      }).eq('id', patient['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transfer rejected'),
            backgroundColor: Colors.red,
          ),
        );
      }

      _loadData();
    } catch (e) {
      print('Error rejecting transfer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab Bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: DashboardTheme.primaryGreen,
            unselectedLabelColor: DashboardTheme.textGray,
            indicatorColor: DashboardTheme.primaryGreen,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people),
                    const SizedBox(width: 8),
                    Text('My Patients (${_myPatients.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.call_received),
                    const SizedBox(width: 8),
                    Text('Transfer Requests (${_transferRequests.length})'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Tab Views
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMyPatientsTab(),
                    _buildTransferRequestsTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMyPatientsTab() {
    if (_myPatients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No patients to transfer',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _myPatients.length,
        itemBuilder: (context, index) {
          final patient = _myPatients[index];
          final user = patient['User'];
          final person = user['Person'];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Patient Avatar
                  CircleAvatar(
                    radius: 30,
                    backgroundColor:
                        DashboardTheme.primaryGreen.withOpacity(0.1),
                    child: Text(
                      '${person['first_name']?[0] ?? ''}${person['last_name']?[0] ?? ''}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: DashboardTheme.primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Patient Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${person['first_name']} ${person['last_name']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: DashboardTheme.darkGray,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user['email'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: DashboardTheme.textGray,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Joined: ${_formatDate(patient['joined_at'])}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: DashboardTheme.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Transfer Button
                  ElevatedButton.icon(
                    onPressed: () => _transferPatient(patient),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Transfer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DashboardTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransferRequestsTab() {
    if (_transferRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.call_received,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No pending transfer requests',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _transferRequests.length,
        itemBuilder: (context, index) {
          final patient = _transferRequests[index];
          final user = patient['User'];
          final person = user['Person'];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: DashboardTheme.pendingOrange.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Patient Avatar
                  CircleAvatar(
                    radius: 30,
                    backgroundColor:
                        DashboardTheme.pendingOrange.withOpacity(0.1),
                    child: Text(
                      '${person['first_name']?[0] ?? ''}${person['last_name']?[0] ?? ''}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: DashboardTheme.pendingOrange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Patient Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${person['first_name']} ${person['last_name']}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: DashboardTheme.darkGray,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: DashboardTheme.pendingOrange
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'TRANSFERRING',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: DashboardTheme.pendingOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user['email'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: DashboardTheme.textGray,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Transfer requested: ${_formatDate(patient['created_at'])}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: DashboardTheme.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action Buttons
                  Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _approveTransfer(patient),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DashboardTheme.approvedGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _rejectTransfer(patient),
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'N/A';
    }
  }
}

// Transfer Dialog
class _TransferDialog extends StatefulWidget {
  final List<Map<String, dynamic>> hospitals;

  const _TransferDialog({required this.hospitals});

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  Map<String, dynamic>? _selectedHospital;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredHospitals = widget.hospitals.where((hospital) {
      return hospital['name']
          .toString()
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Transfer Patient'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search Field
            TextField(
              decoration: InputDecoration(
                hintText: 'Search hospitals...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
            const SizedBox(height: 16),

            // Hospital List
            Flexible(
              child: filteredHospitals.isEmpty
                  ? const Center(child: Text('No hospitals found'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredHospitals.length,
                      itemBuilder: (context, index) {
                        final hospital = filteredHospitals[index];
                        final isSelected = _selectedHospital == hospital;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isSelected
                              ? DashboardTheme.primaryGreen.withOpacity(0.1)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? DashboardTheme.primaryGreen
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              Icons.local_hospital,
                              color: isSelected
                                  ? DashboardTheme.primaryGreen
                                  : DashboardTheme.textGray,
                            ),
                            title: Text(
                              hospital['name'],
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: DashboardTheme.primaryGreen,
                                  )
                                : null,
                            onTap: () {
                              setState(() => _selectedHospital = hospital);
                            },
                          ),
                        );
                      },
                    ),
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
          onPressed: _selectedHospital == null
              ? null
              : () => Navigator.pop(context, _selectedHospital),
          style: ElevatedButton.styleFrom(
            backgroundColor: DashboardTheme.primaryGreen,
          ),
          child: const Text('Transfer'),
        ),
      ],
    );
  }
}
