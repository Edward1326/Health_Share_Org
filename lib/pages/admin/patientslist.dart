// admin_patientslist.dart - Main Patient List Page
import 'package:flutter/material.dart';
import 'package:health_share_org/functions/admin/admin_patientslist.dart';
import 'package:health_share_org/widgets/admin_patientslist_widgets.dart';

class AdminPatientsListPage extends StatefulWidget {
  const AdminPatientsListPage({Key? key}) : super(key: key);

  @override
  State<AdminPatientsListPage> createState() => _AdminPatientsListPageState();
}

class _AdminPatientsListPageState extends State<AdminPatientsListPage>
    with TickerProviderStateMixin {
  // Controllers and animations
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Data and state management
  final AdminPatientListFunctions _functions = AdminPatientListFunctions();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _doctors = [];

  // UI state
  String _searchQuery = '';
  String _selectedFilter = 'all';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadData();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Get organization ID first
      final orgId = await _functions.getCurrentOrganizationId();
      if (orgId == null) {
        throw Exception('Unable to get organization ID');
      }

      // Load users and doctors
      final users = await _functions.loadUsersFromSupabase();
      final doctors = await _functions.loadDoctorsFromSupabase();

      // Load assignments
      await _functions.loadAssignmentsFromDatabase(users);

      setState(() {
        _users = users;
        _doctors = doctors;
        _isLoading = false;
      });

      _applyFilters();
      _animationController.forward();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_users);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        final email = user['email']?.toString().toLowerCase() ?? '';
        final name = user['name']?.toString().toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return email.contains(query) || name.contains(query);
      }).toList();
    }

    // Apply status filter
    switch (_selectedFilter) {
      case 'invited':
        filtered =
            filtered.where((user) => user['status'] == 'invited').toList();
        break;
      case 'unassigned':
        filtered = filtered
            .where((user) =>
                user['status'] == 'unassigned' ||
                (user['status'] != 'pending' && user['assignedDoctor'] == null))
            .toList();
        break;
      case 'assigned':
        filtered =
            filtered.where((user) => user['assignedDoctor'] != null).toList();
        break;
      case 'all':
      default:
        // No additional filtering
        break;
    }

    setState(() {
      _filteredUsers = filtered;
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    _applyFilters();
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
    _applyFilters();
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
    });
    _applyFilters();
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  void _onInviteUser() {
    _showInviteUserDialog();
  }

  void _onViewDetails(Map<String, dynamic> user) {
    _showUserDetailsDialog(user);
  }

  Future<void> _onAssignDoctor(Map<String, dynamic> user) async {
  if (!_functions.validateUserForAssignment(user)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cannot assign doctor to this patient'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  
}

  Future<void> _onApprove(Map<String, dynamic> user) async {
    try {
      // Use the Patient table's primary key (id)
      String patientId = user['id']?.toString() ?? '';

      if (patientId.isEmpty) {
        throw Exception('No valid patient ID found');
      }

      await _functions.approvePendingPatient(patientId);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['name']} has been approved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving patient: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _onReject(Map<String, dynamic> user) async {
    try {
      await _functions.rejectPendingPatient(user['patient_id'] ?? user['id']);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['name']} has been rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting patient: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showInviteUserDialog() {
    showDialog(
      context: context,
      builder: (context) => _InviteUserDialog(
        functions: _functions,
        onUserInvited: () => _loadData(),
      ),
    );
  }

  void _showUserDetailsDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => _UserDetailsDialog(user: user),
    );
  }

  void _showDoctorAssignmentDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => _DoctorAssignmentDialog(
        user: user,
        doctors: _doctors,
        functions: _functions,
        onAssignmentChanged: () => _loadData(),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: PatientListWidgets.buildModernAppBar(
        context,
        _users,
        _onRefresh,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return PatientListWidgets.buildLoadingIndicator();
    }

    if (_errorMessage != null) {
      return PatientListWidgets.buildErrorState(
        _errorMessage!,
        () => _loadData(),
      );
    }

    // Always show the search and filter section, even when no users
    return Column(
      children: [
        // Search and Filter Section - Always visible
        PatientListWidgets.buildSearchAndFilter(
          searchQuery: _searchQuery,
          onSearchChanged: _onSearchChanged,
          onClearSearch: _clearSearch,
          onInviteUser: _onInviteUser,
          selectedFilter: _selectedFilter,
          onFilterChanged: _onFilterChanged,
          filteredUsers: _filteredUsers,
        ),

        // Patient List or Empty State
        Expanded(
          child: _users.isEmpty
              ? PatientListWidgets.buildModernEmptyState(_onRefresh)
              : _filteredUsers.isEmpty
                  ? _buildEmptyFilteredState()
                  : ListView.builder(
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        return PatientListWidgets.buildEnhancedPatientCard(
  user: user,
  index: index,
  fadeAnimation: _fadeAnimation,
  animationController: _animationController,
  onViewDetails: () => _onViewDetails(user),
  onAssignDoctor: () => _onAssignDoctor(user),
  onApprove: user['status'] == 'pending'
      ? () => _onApprove(user)
      : null,
  onReject: user['status'] == 'pending'
      ? () => _onReject(user)
      : null,
  onRefresh: _onRefresh, // Add this line
);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyFilteredState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No patients found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filter settings',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _selectedFilter = 'all';
                });
                _applyFilters();
              },
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}

// Invite User Dialog
class _InviteUserDialog extends StatefulWidget {
  final AdminPatientListFunctions functions;
  final VoidCallback onUserInvited;

  const _InviteUserDialog({
    required this.functions,
    required this.onUserInvited,
  });

  @override
  State<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<_InviteUserDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchQuery = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });

    try {
      final results = await widget.functions.searchUsersToInvite(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _inviteUser(Map<String, dynamic> user) async {
    try {
      await widget.functions.inviteUser(user);
      widget.onUserInvited();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['name']} has been invited'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error inviting user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.person_add_rounded, color: Color(0xFF3B82F6)),
          const SizedBox(width: 12),
          const Text('Invite New Patient'),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by email...',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _searchUsers,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isEmpty
                                ? 'Start typing to search for users'
                                : 'No users found',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  child: Text(
                                    user['name']?.isNotEmpty == true
                                        ? user['name'][0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(user['name'] ?? 'Unknown User'),
                                subtitle: Text(user['email'] ?? ''),
                                trailing: ElevatedButton(
                                  onPressed: () => _inviteUser(user),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Invite'),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// User Details Dialog
class _UserDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> user;

  const _UserDetailsDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Hero(
            tag: 'patient_${user['patient_id'] ?? user['id']}',
            child: CircleAvatar(
              backgroundColor: const Color(0xFF3B82F6),
              child: Text(
                user['name']?.isNotEmpty == true
                    ? user['name'][0].toUpperCase()
                    : 'P',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(user['name'] ?? 'Unknown Patient'),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PatientListWidgets.buildUserDetailsRow(
              'Email',
              user['email'] ?? 'Not provided',
              Icons.email_outlined,
            ),
            PatientListWidgets.buildUserDetailsRow(
              'Phone',
              user['phone'] ?? 'Not provided',
              Icons.phone_outlined,
            ),
            PatientListWidgets.buildUserDetailsRow(
              'Address',
              user['address'] ?? 'Not provided',
              Icons.location_on_outlined,
            ),
            PatientListWidgets.buildUserDetailsRow(
              'Status',
              user['status'] ?? 'Unknown',
              Icons.info_outlined,
            ),
            PatientListWidgets.buildUserDetailsRow(
              'Last Visit',
              user['lastVisit'] ?? 'Unknown',
              Icons.schedule_outlined,
            ),
            if (user['assignedDoctor'] != null)
              PatientListWidgets.buildUserDetailsRow(
                'Assigned Doctor',
                user['assignedDoctor'],
                Icons.medical_services_outlined,
              ),
          ],
        ),
      ),
    );
  }
}

// Doctor Assignment Dialog
class _DoctorAssignmentDialog extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> doctors;
  final AdminPatientListFunctions functions;
  final VoidCallback onAssignmentChanged;

  const _DoctorAssignmentDialog({
    required this.user,
    required this.doctors,
    required this.functions,
    required this.onAssignmentChanged,
  });

  @override
  State<_DoctorAssignmentDialog> createState() =>
      _DoctorAssignmentDialogState();
}

class _DoctorAssignmentDialogState extends State<_DoctorAssignmentDialog> {
  String? _selectedDoctorId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDoctorId = widget.user['assignedDoctorId'];
  }

  Future<void> _assignDoctor() async {
    if (_selectedDoctorId == null) return;
    print("widget.user = ${widget.user}");

    setState(() {
      _isLoading = true;
    });

    try {
      String patientId = widget.user['patientId']?.toString() ?? '';

      if (patientId.isEmpty) {
        throw Exception('No valid patient ID found');
      }

      await widget.functions.saveAssignmentToDatabase(
        patientId,
        _selectedDoctorId!,
      );

      widget.onAssignmentChanged();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doctor assigned successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning doctor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeAssignment() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await widget.functions.removeAssignment(widget.user);

      widget.onAssignmentChanged();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doctor assignment removed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing assignment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.medical_services_rounded, color: Color(0xFF3B82F6)),
          const SizedBox(width: 12),
          const Expanded(child: Text('Assign Doctor')),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Patient: ${widget.user['name'] ?? 'Unknown'}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            if (widget.doctors.isEmpty)
              const Text(
                'No doctors available in your organization',
                style: TextStyle(color: Colors.grey),
              )
            else
              Column(
                children: widget.doctors.map((doctor) {
                  return RadioListTile<String>(
                    title: Text(doctor['name'] ?? 'Unknown Doctor'),
                    subtitle: Text(doctor['position'] ?? ''),
                    value: doctor['id'],
                    groupValue: _selectedDoctorId,
                    onChanged: (value) {
                      setState(() {
                        _selectedDoctorId = value;
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.user['assignedDoctor'] != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _removeAssignment,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Remove'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isLoading || _selectedDoctorId == null)
                        ? null
                        : _assignDoctor,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Assign'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
