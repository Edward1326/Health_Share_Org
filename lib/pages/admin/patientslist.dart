import 'package:flutter/material.dart';
import 'package:health_share_org/functions/admin/admin_patientslist.dart';
import 'admin_dashboard.dart'; // Import your main layout

// Clean, modular Patient Content Widget - just the content part
class PatientContentWidget extends StatefulWidget {
  const PatientContentWidget({Key? key}) : super(key: key);

  @override
  State<PatientContentWidget> createState() => _PatientContentWidgetState();
}

class _PatientContentWidgetState extends State<PatientContentWidget>
    with TickerProviderStateMixin {
  // Controllers and data
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  final AdminPatientListFunctions _functions = AdminPatientListFunctions();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _doctors = [];
  
  // UI state
  String _searchQuery = '';
  String _selectedFilter = 'all';
  bool _isLoading = true;
  String? _errorMessage;

  // Use DashboardTheme colors
  static const primaryGreen = DashboardTheme.primaryGreen;
  static const textGray = DashboardTheme.textGray;
  static const approvedGreen = DashboardTheme.approvedGreen;
  static const pendingOrange = DashboardTheme.pendingOrange;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() { _isLoading = true; _errorMessage = null; });

      final orgId = await _functions.getCurrentOrganizationId();
      if (orgId == null) throw Exception('Unable to get organization ID');

      final users = await _functions.loadUsersFromSupabase();
      final doctors = await _functions.loadDoctorsFromSupabase();
      await _functions.loadAssignmentsFromDatabase(users);

      setState(() {
        _users = users;
        _doctors = doctors;
        _isLoading = false;
      });

      _applyFilters();
      _animationController.forward();
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
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
        filtered = filtered.where((user) => user['status'] == 'invited').toList();
        break;
      case 'unassigned':
        filtered = filtered.where((user) =>
            user['status'] == 'unassigned' || 
            (user['status'] != 'pending' && user['assignedDoctor'] == null)).toList();
        break;
      case 'assigned':
        filtered = filtered.where((user) => user['assignedDoctor'] != null).toList();
        break;
      case 'pending':
        filtered = filtered.where((user) => user['status'] == 'pending').toList();
        break;
      case 'all':
      default:
        break;
    }

    setState(() { _filteredUsers = filtered; });
  }

  Future<void> _onApprove(Map<String, dynamic> user) async {
    try {
      String patientId = user['id']?.toString() ?? '';
      if (patientId.isEmpty) throw Exception('No valid patient ID found');
      
      await _functions.approvePendingPatient(patientId);
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user['name']} approved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('${user['name']} rejected'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _onAssignDoctor(Map<String, dynamic> user) async {
    if (!_functions.validateUserForAssignment(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot assign doctor to this patient'), backgroundColor: Colors.red),
      );
      return;
    }
    _showDoctorAssignmentDialog(user);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with search and filters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Patient Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryGreen,
                      side: const BorderSide(color: primaryGreen),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _showInviteDialog,
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Invite Patient'),
                    style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Search and filter row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search patients...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: _searchQuery.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() { _searchQuery = ''; });
                            _applyFilters();
                          },
                        )
                      : null,
                  ),
                  onChanged: (value) {
                    setState(() { _searchQuery = value; });
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _selectedFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'assigned', child: Text('Assigned')),
                  DropdownMenuItem(value: 'unassigned', child: Text('Unassigned')),
                  DropdownMenuItem(value: 'invited', child: Text('Invited')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() { _selectedFilter = value; });
                    _applyFilters();
                  }
                },
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Error message
          if (_errorMessage != null) ...[
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
                  Expanded(child: Text(_errorMessage!)),
                  ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Content
          if (_isLoading)
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
                    Text('Loading patients...'),
                  ],
                ),
              ),
            )
          else if (_users.isEmpty)
            _buildEmptyState()
          else if (_filteredUsers.isEmpty)
            _buildEmptyFilterState()
          else
            _buildPatientTable(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            const Text('No patients found', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _showInviteDialog,
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
              child: const Text('Invite First Patient'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFilterState() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No patients match your search', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() { _searchQuery = ''; _selectedFilter = 'all'; });
                _applyFilters();
              },
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientTable() {
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
                Expanded(flex: 2, child: Text('Patient', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Status', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Doctor', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(child: Text('Last Visit', style: TextStyle(fontWeight: FontWeight.w500))),
                SizedBox(width: 40),
              ],
            ),
          ),
          
          // Rows
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredUsers.length,
            itemBuilder: (context, index) {
              final user = _filteredUsers[index];
              return AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: index < _filteredUsers.length - 1 ? Colors.grey.shade200 : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Patient info
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: _getStatusColor(user['status']),
                                  child: Text(
                                    user['name']?.isNotEmpty == true ? user['name'][0] : 'P',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(user['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w500)),
                                      Text(user['email'] ?? '', style: TextStyle(fontSize: 12, color: textGray)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Status
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(user['status']).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                user['status'] ?? 'Unknown',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _getStatusColor(user['status']),
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          
                          // Doctor
                          Expanded(
                            child: Text(
                              user['assignedDoctor'] ?? 'Unassigned',
                              style: TextStyle(
                                fontSize: 14,
                                color: user['assignedDoctor'] != null ? Colors.black : textGray,
                              ),
                            ),
                          ),
                          
                          // Last Visit
                          Expanded(
                            child: Text(
                              user['lastVisit'] ?? 'Never',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          
                          // Actions
                          SizedBox(
                            width: 40,
                            child: PopupMenuButton(
                              icon: const Icon(Icons.more_horiz, color: textGray),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'view',
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility, size: 16),
                                      SizedBox(width: 8),
                                      Text('View'),
                                    ],
                                  ),
                                ),
                                if (user['status'] != 'pending')
                                  const PopupMenuItem(
                                    value: 'assign',
                                    child: Row(
                                      children: [
                                        Icon(Icons.medical_services, size: 16),
                                        SizedBox(width: 8),
                                        Text('Assign Doctor'),
                                      ],
                                    ),
                                  ),
                                if (user['status'] == 'pending') ...[
                                  const PopupMenuItem(
                                    value: 'approve',
                                    child: Row(
                                      children: [
                                        Icon(Icons.check, color: Colors.green, size: 16),
                                        SizedBox(width: 8),
                                        Text('Approve'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'reject',
                                    child: Row(
                                      children: [
                                        Icon(Icons.close, color: Colors.red, size: 16),
                                        SizedBox(width: 8),
                                        Text('Reject', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                              onSelected: (value) {
                                switch (value) {
                                  case 'view':
                                    _showDetailsDialog(user);
                                    break;
                                  case 'assign':
                                    _onAssignDoctor(user);
                                    break;
                                  case 'approve':
                                    _onApprove(user);
                                    break;
                                  case 'reject':
                                    _onReject(user);
                                    break;
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending': return pendingOrange;
      case 'approved': return approvedGreen;
      case 'assigned': return Colors.blue;
      case 'invited': return Colors.purple;
      default: return Colors.grey;
    }
  }

  void _showInviteDialog() {
    showDialog(
      context: context,
      builder: (context) => _InvitePatientDialog(
        functions: _functions,
        onPatientInvited: _loadData,
      ),
    );
  }

  void _showDetailsDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => _PatientDetailsDialog(user: user),
    );
  }

  void _showDoctorAssignmentDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => _DoctorAssignmentDialog(
        user: user,
        doctors: _doctors,
        functions: _functions,
        onAssignmentChanged: _loadData,
      ),
    );
  }
}

// Simple dialogs
class _InvitePatientDialog extends StatefulWidget {
  final AdminPatientListFunctions functions;
  final VoidCallback onPatientInvited;

  const _InvitePatientDialog({required this.functions, required this.onPatientInvited});

  @override
  State<_InvitePatientDialog> createState() => _InvitePatientDialogState();
}

class _InvitePatientDialogState extends State<_InvitePatientDialog> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() { _searchResults = []; });
      return;
    }

    setState(() { _isSearching = true; });
    try {
      final results = await widget.functions.searchUsersToInvite(query);
      setState(() { _searchResults = results; _isSearching = false; });
    } catch (e) {
      setState(() { _isSearching = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('Invite Patient'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Search by email...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _searchUsers,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                  ? const Center(child: Text('Start typing to search'))
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text(user['name']?[0] ?? 'U')),
                          title: Text(user['name'] ?? 'Unknown'),
                          subtitle: Text(user['email'] ?? ''),
                          trailing: ElevatedButton(
                            onPressed: () async {
                              try {
                                await widget.functions.inviteUser(user);
                                widget.onPatientInvited();
                                if (mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Patient invited!')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            },
                            child: const Text('Invite'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _PatientDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> user;
  const _PatientDetailsDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(user['name'] ?? 'Patient Details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('Email', user['email']),
          _buildDetailRow('Phone', user['phone']),
          _buildDetailRow('Status', user['status']),
          _buildDetailRow('Doctor', user['assignedDoctor']),
          _buildDetailRow('Last Visit', user['lastVisit']),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value ?? 'Not provided')),
        ],
      ),
    );
  }
}

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
  State<_DoctorAssignmentDialog> createState() => _DoctorAssignmentDialogState();
}

class _DoctorAssignmentDialogState extends State<_DoctorAssignmentDialog> {
  String? _selectedDoctorId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDoctorId = widget.user['assignedDoctorId'];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('Assign Doctor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Patient: ${widget.user['name'] ?? 'Unknown'}'),
          const SizedBox(height: 16),
          if (widget.doctors.isEmpty)
            const Text('No doctors available')
          else
            ...widget.doctors.map((doctor) {
              return RadioListTile<String>(
                title: Text(doctor['name'] ?? 'Unknown Doctor'),
                subtitle: Text(doctor['position'] ?? ''),
                value: doctor['id'],
                groupValue: _selectedDoctorId,
                onChanged: (value) => setState(() { _selectedDoctorId = value; }),
              );
            }).toList(),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _selectedDoctorId == null || _isLoading ? null : () async {
            setState(() { _isLoading = true; });
            try {
              String patientId = widget.user['patientId']?.toString() ?? '';
              if (patientId.isEmpty) throw Exception('No valid patient ID found');
              
              await widget.functions.saveAssignmentToDatabase(patientId, _selectedDoctorId!);
              widget.onAssignmentChanged();
              
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Doctor assigned!')),
                );
              }
            } catch (e) {
              setState(() { _isLoading = false; });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            }
          },
          child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Assign'),
        ),
      ],
    );
  }
}

// Updated Patients List Page - super clean now
class AdminPatientsListPage extends StatelessWidget {
  const AdminPatientsListPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    if (isSmallScreen) {
      // Mobile - simple fallback
      return Scaffold(
        appBar: AppBar(
          title: const Text('Patients'),
          backgroundColor: DashboardTheme.primaryGreen,
          foregroundColor: Colors.white,
        ),
        body: const PatientContentWidget(),
      );
    }

    // Desktop - use modular layout
    return const MainDashboardLayout(
      title: 'Patient Management',
      selectedNavIndex: 2,
      content: PatientContentWidget(),
    );
  }
}