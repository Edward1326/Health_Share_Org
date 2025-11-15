// patient_transferlist.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard.dart';

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

  // Sorting state for My Patients tab
  String _myPatientsSortColumn = 'name';
  bool _myPatientsSortAscending = true;

  // Sorting state for Transfer Requests tab
  String _transferRequestsSortColumn = 'name';
  bool _transferRequestsSortAscending = true;

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
        print('Querying Person table for auth_user_id: $authUserId');

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

      final myPatientsResponse = await _supabase.from('Patient').select('''
            *,
            User!Patient_user_id_fkey (
              email,
              Person (
                first_name,
                last_name
              )
            )
          ''').eq('organization_id', _currentOrgId!).eq('status', 'accepted');

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
          .eq('status', 'transferring');

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
        _sortMyPatients();
        _sortTransferRequests();
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

  void _sortMyPatients() {
    _myPatients.sort((a, b) {
      int compare = 0;
      final userA = a['User'];
      final userB = b['User'];
      final personA = userA?['Person'];
      final personB = userB?['Person'];

      switch (_myPatientsSortColumn) {
        case 'name':
          final nameA =
              '${personA?['first_name'] ?? ''} ${personA?['last_name'] ?? ''}'
                  .trim();
          final nameB =
              '${personB?['first_name'] ?? ''} ${personB?['last_name'] ?? ''}'
                  .trim();
          compare = nameA.compareTo(nameB);
          break;
        case 'email':
          compare = (userA?['email'] ?? '').compareTo(userB?['email'] ?? '');
          break;
        case 'joined':
          final dateA = a['joined_at'] ?? '';
          final dateB = b['joined_at'] ?? '';
          compare = dateA.toString().compareTo(dateB.toString());
          break;
      }
      return _myPatientsSortAscending ? compare : -compare;
    });
  }

  void _sortTransferRequests() {
    _transferRequests.sort((a, b) {
      int compare = 0;
      final userA = a['User'];
      final userB = b['User'];
      final personA = userA?['Person'];
      final personB = userB?['Person'];

      switch (_transferRequestsSortColumn) {
        case 'name':
          final nameA =
              '${personA?['first_name'] ?? ''} ${personA?['last_name'] ?? ''}'
                  .trim();
          final nameB =
              '${personB?['first_name'] ?? ''} ${personB?['last_name'] ?? ''}'
                  .trim();
          compare = nameA.compareTo(nameB);
          break;
        case 'email':
          compare = (userA?['email'] ?? '').compareTo(userB?['email'] ?? '');
          break;
        case 'requested':
          final dateA = a['created_at'] ?? '';
          final dateB = b['created_at'] ?? '';
          compare = dateA.toString().compareTo(dateB.toString());
          break;
      }
      return _transferRequestsSortAscending ? compare : -compare;
    });
  }

  void _onSortMyPatients(String column) {
    setState(() {
      if (_myPatientsSortColumn == column) {
        _myPatientsSortAscending = !_myPatientsSortAscending;
      } else {
        _myPatientsSortColumn = column;
        _myPatientsSortAscending = true;
      }
      _sortMyPatients();
    });
  }

  void _onSortTransferRequests(String column) {
    setState(() {
      if (_transferRequestsSortColumn == column) {
        _transferRequestsSortAscending = !_transferRequestsSortAscending;
      } else {
        _transferRequestsSortColumn = column;
        _transferRequestsSortAscending = true;
      }
      _sortTransferRequests();
    });
  }

  Future<void> _transferPatient(Map<String, dynamic> patient) async {
    final selectedHospital = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _TransferDialog(hospitals: _hospitals),
    );

    if (selectedHospital == null) return;

    try {
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

  Widget _buildSortableHeader(
      String label, String column, bool isMyPatientsTab) {
    final isActive = isMyPatientsTab
        ? _myPatientsSortColumn == column
        : _transferRequestsSortColumn == column;
    final isAscending = isMyPatientsTab
        ? _myPatientsSortAscending
        : _transferRequestsSortAscending;

    return InkWell(
      onTap: () {
        if (isMyPatientsTab) {
          _onSortMyPatients(column);
        } else {
          _onSortTransferRequests(column);
        }
      },
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? DashboardTheme.primaryGreen
                  : DashboardTheme.darkGray,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            isActive
                ? (isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 16,
            color: isActive ? DashboardTheme.primaryGreen : Colors.grey,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Sortable Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const SizedBox(width: 60), // Avatar space
                Expanded(
                  flex: 2,
                  child: _buildSortableHeader('Patient Name', 'name', true),
                ),
                Expanded(
                  flex: 2,
                  child: _buildSortableHeader('Email', 'email', true),
                ),
                Expanded(
                  child: _buildSortableHeader('Joined Date', 'joined', true),
                ),
                const SizedBox(width: 120), // Action button space
              ],
            ),
          ),
          // Patient List
          ...List.generate(_myPatients.length, (index) {
            final patient = _myPatients[index];
            final user = patient['User'];
            final person = user['Person'];
            final isLast = index == _myPatients.length - 1;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Colors.grey.shade200),
                  right: BorderSide(color: Colors.grey.shade200),
                  bottom: BorderSide(
                    color: isLast ? Colors.grey.shade200 : Colors.grey.shade100,
                  ),
                ),
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(12))
                    : null,
              ),
              child: Row(
                children: [
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
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${person['first_name']} ${person['last_name']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DashboardTheme.darkGray,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      user['email'] ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        color: DashboardTheme.textGray,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _formatDate(patient['joined_at']),
                      style: const TextStyle(
                        fontSize: 14,
                        color: DashboardTheme.textGray,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: ElevatedButton.icon(
                      onPressed: () => _transferPatient(patient),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Transfer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DashboardTheme.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Sortable Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const SizedBox(width: 60), // Avatar space
                Expanded(
                  flex: 2,
                  child: _buildSortableHeader('Patient Name', 'name', false),
                ),
                Expanded(
                  flex: 2,
                  child: _buildSortableHeader('Email', 'email', false),
                ),
                Expanded(
                  child: _buildSortableHeader('Requested', 'requested', false),
                ),
                const SizedBox(width: 180), // Action buttons space
              ],
            ),
          ),
          // Transfer Request List
          ...List.generate(_transferRequests.length, (index) {
            final patient = _transferRequests[index];
            final user = patient['User'];
            final person = user['Person'];
            final isLast = index == _transferRequests.length - 1;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(
                      color: DashboardTheme.pendingOrange.withOpacity(0.3),
                      width: 2),
                  right: BorderSide(color: Colors.grey.shade200),
                  bottom: BorderSide(
                    color: isLast ? Colors.grey.shade200 : Colors.grey.shade100,
                  ),
                ),
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(12))
                    : null,
              ),
              child: Row(
                children: [
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
                  Expanded(
                    flex: 2,
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
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      user['email'] ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        color: DashboardTheme.textGray,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _formatDate(patient['created_at']),
                      style: const TextStyle(
                        fontSize: 14,
                        color: DashboardTheme.textGray,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _approveTransfer(patient),
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DashboardTheme.approvedGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _rejectTransfer(patient),
                          icon: const Icon(Icons.cancel, size: 16),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
