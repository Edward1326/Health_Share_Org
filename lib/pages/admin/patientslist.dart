// User/Patient List Page with Admin Dashboard Theme and Status Management
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:health_share_org/functions/admin/admin_patientslist.dart';

class PatientListPage extends StatefulWidget {
  const PatientListPage({super.key});

  @override
  State<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends State<PatientListPage>
    with SingleTickerProviderStateMixin {
  // Instance of the functions class
  final AdminPatientListFunctions _functions = AdminPatientListFunctions();
  
  // UI state variables
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> availableDoctors = [];
  bool isLoading = true;
  String? errorMessage;
  String searchQuery = '';
  String selectedFilter = 'all';
  List<Map<String, dynamic>> searchResults = [];
  bool isSearching = false;
  String userSearchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
      value: 0.0,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _loadAllData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Load all data in sequence using functions from admin_patientslist.dart
  Future<void> _loadAllData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Get organization ID first
      final orgId = await _functions.getCurrentOrganizationId();
      if (orgId == null) {
        throw Exception('Unable to determine current organization');
      }

      // Load users and doctors using the functions
      final loadedUsers = await _functions.loadUsersFromSupabase();
      final loadedDoctors = await _functions.loadDoctorsFromSupabase();
      
      setState(() {
        users = loadedUsers;
        availableDoctors = loadedDoctors;
      });

      // Load assignments and apply to users
      await _functions.loadAssignmentsFromDatabase(users);
      
      setState(() {
        users = users; // Trigger rebuild with updated assignments
      });

      _animationController.forward();
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading data: $e';
        isLoading = false;
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Filtered users getter (kept in UI since it's UI-specific)
  List<Map<String, dynamic>> get filteredUsers {
    var filtered = users.where((user) {
      final email = user['email']?.toString() ?? '';
      final status = user['status']?.toString() ?? '';

      final matchesSearch =
          email.toLowerCase().contains(searchQuery.toLowerCase());

      switch (selectedFilter) {
        case 'invited':
          return matchesSearch && status == 'invited';
        case 'unassigned':
          return matchesSearch && status == 'unassigned';
        case 'assigned':
          return matchesSearch && status == 'assigned';
        default:
          return matchesSearch;
      }
    }).toList();

    // Sort by status priority
    filtered.sort((a, b) {
      const statusPriority = {'invited': 0, 'unassigned': 1, 'assigned': 2};
      final aStatus = a['status']?.toString() ?? '';
      final bStatus = b['status']?.toString() ?? '';
      final aPriority = statusPriority[aStatus] ?? 3;
      final bPriority = statusPriority[bStatus] ?? 3;

      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      final aEmail = a['email']?.toString() ?? '';
      final bEmail = b['email']?.toString() ?? '';
      return aEmail.compareTo(bEmail);
    });

    return filtered;
  }

  // Search users to invite using the functions
  Future<void> _searchUsersToInvite(String query) async {
    if (query.isEmpty) {
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    setState(() {
      isSearching = true;
    });

    try {
      final results = await _functions.searchUsersToInvite(query);
      setState(() {
        searchResults = results;
        isSearching = false;
      });
    } catch (e) {
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      _showSnackBar('Error searching users: $e', const Color(0xFFE53E3E));
    }
  }

  // Invite user using the functions
  Future<void> _inviteUser(Map<String, dynamic> userToInvite) async {
    try {
      final newPatient = await _functions.inviteUser(userToInvite);
      
      setState(() {
        users.insert(0, newPatient);
        searchResults = [];
        userSearchQuery = '';
      });

      Navigator.of(context).pop();
      _showSnackBar(
          '${userToInvite['name']} has been invited to join as a patient',
          const Color(0xFF38A169));
    } catch (e) {
      _showSnackBar('Failed to invite user: $e', const Color(0xFFE53E3E));
    }
  }

  // Approve pending patient using the functions
  Future<void> _approvePendingPatient(int userIndex) async {
    try {
      final patientId = users[userIndex]['id'];
      await _functions.approvePendingPatient(patientId);
      
      setState(() {
        users[userIndex]['status'] = 'unassigned';
      });

      _showSnackBar(
          'Patient ${users[userIndex]['name']} approved and ready for assignment',
          const Color(0xFF38A169));
    } catch (e) {
      _showSnackBar('Failed to approve patient: $e', const Color(0xFFE53E3E));
    }
  }

  // Reject pending patient using the functions
  Future<void> _rejectPendingPatient(int userIndex) async {
    try {
      final patientId = users[userIndex]['id'];
      await _functions.rejectPendingPatient(patientId);
      
      setState(() {
        users.removeAt(userIndex);
      });

      _showSnackBar('Patient rejected and removed from organization',
          const Color(0xFFD69E2E));
    } catch (e) {
      _showSnackBar('Failed to reject patient: $e', const Color(0xFFE53E3E));
    }
  }

  // Assign doctor using the functions
  void _assignDoctor(int userIndex, Map<String, dynamic> doctor) async {
    try {
      if (users[userIndex]['status'] == 'pending') {
        _showSnackBar(
            'Please approve this patient first before assigning a doctor',
            const Color(0xFFD69E2E));
        return;
      }

      if (!_functions.validateUserForAssignment(users[userIndex])) {
        _showSnackBar('Invalid user data for assignment', const Color(0xFFE53E3E));
        return;
      }

      // Determine the correct patient user ID
      String? patientUserId = users[userIndex]['userId'] ?? users[userIndex]['id'];
      final doctorOrgUserId = doctor['id'];

      if (patientUserId == null || patientUserId.isEmpty) {
        throw Exception('Could not determine valid patient User ID');
      }

      if (doctorOrgUserId == null || doctorOrgUserId.isEmpty) {
        throw Exception('Doctor organization user ID is missing');
      }

      // Show loading
      _showSnackBar('Assigning doctor...', const Color(0xFF3182CE),
          showProgress: true);

      // Save to database using functions
      await _functions.saveAssignmentToDatabase(patientUserId, doctorOrgUserId);

      // Update local state
      setState(() {
        users[userIndex]['assignedDoctor'] = doctor['name'];
        users[userIndex]['assignedDoctorId'] = doctor['id'];
        users[userIndex]['status'] = 'assigned';
      });

      // Show success message
      if (mounted) {
        _showSnackBar(
            'Successfully assigned ${users[userIndex]['name']} to ${doctor['name']}',
            const Color(0xFF38A169),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () => _removeAssignment(userIndex),
            ));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to assign doctor: $e', const Color(0xFFE53E3E));
      }
    }
  }

  // Remove assignment using the functions
  Future<void> _removeAssignment(int userIndex) async {
    try {
      await _functions.removeAssignment(users[userIndex]);
      
      setState(() {
        users[userIndex]['assignedDoctor'] = null;
        users[userIndex]['assignedDoctorId'] = null;
        users[userIndex]['assignmentId'] = null;
        users[userIndex]['status'] = 'unassigned';
      });

      _showSnackBar('Assignment removed successfully', const Color(0xFF38A169));
    } catch (e) {
      _showSnackBar('Failed to remove assignment: $e', const Color(0xFFE53E3E));
    }
  }

  // Search users with dialog state update
  Future<void> _searchUsersToInviteWithDialog(
      String query, StateSetter setDialogState) async {
    if (query.isEmpty) {
      setDialogState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    setDialogState(() {
      isSearching = true;
    });

    try {
      final results = await _functions.searchUsersToInvite(query);
      setDialogState(() {
        searchResults = results;
        isSearching = false;
      });
    } catch (e) {
      setDialogState(() {
        searchResults = [];
        isSearching = false;
      });
      _showSnackBar('Error searching users: $e', const Color(0xFFE53E3E));
    }
  }

  // Show snack bar helper method
  void _showSnackBar(String message, Color color,
      {SnackBarAction? action, bool showProgress = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (showProgress) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: action,
        duration: Duration(seconds: showProgress ? 2 : 4),
      ),
    );
  }

  // Show invite user dialog
  void _showInviteUserDialog() {
    userSearchQuery = '';
    searchResults = [];
    isSearching = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: Color(0xFF3182CE)),
              SizedBox(width: 8),
              Text('Invite User as Patient'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    onChanged: (value) {
                      setDialogState(() {
                        userSearchQuery = value;
                      });
                      _searchUsersToInviteWithDialog(value, setDialogState);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by email...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Colors.grey.shade400),
                      suffixIcon: userSearchQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  userSearchQuery = '';
                                  searchResults = [];
                                  isSearching = false;
                                });
                              },
                              icon: Icon(Icons.clear_rounded,
                                  color: Colors.grey.shade400),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Search Results
                Expanded(
                  child: isSearching
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                  color: Color(0xFF3182CE)),
                              SizedBox(height: 16),
                              Text('Searching users...'),
                            ],
                          ),
                        )
                      : userSearchQuery.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Start typing to search for users',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : searchResults.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person_search_rounded,
                                        size: 48,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No users found',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Try searching with a different name or email',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, index) {
                                    final user = searchResults[index];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.shade200),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        leading: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF3182CE),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            user['name']!.isNotEmpty
                                                ? user['name']![0].toUpperCase()
                                                : 'U',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          user['name']!,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (user['email'].isNotEmpty)
                                              Text(
                                                user['email'],
                                                style: const TextStyle(
                                                    color: Color(0xFF4A5568)),
                                              ),
                                            if (user['phone'].isNotEmpty)
                                              Text(
                                                user['phone'],
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF718096),
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: ElevatedButton(
                                          onPressed: () => _inviteUser(user),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF3182CE),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 8),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: const Text('Invite',
                                              style: TextStyle(fontSize: 12)),
                                        ),
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
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF718096))),
            ),
          ],
        ),
      ),
    );
  }

  // Show assign doctor dialog
  void _showAssignDoctorDialog(int userIndex) {
    // Check if patient is pending
    if (users[userIndex]['status'] == 'pending') {
      _showApprovalDialog(userIndex);
      return;
    }

    // Filter doctors to only show ones from current organization
    final organizationDoctors = availableDoctors
        .where((doctor) =>
            doctor['organization_id']?.toString() == _functions.currentOrganizationId)
        .toList();

    if (organizationDoctors.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Color(0xFFD69E2E)),
              SizedBox(width: 8),
              Text('No Doctors Available'),
            ],
          ),
          content: Text(
            'No doctors found in your organization (ID: ${_functions.currentOrganizationId}). Please add medical staff to your organization first.',
            style: const TextStyle(color: Color(0xFF4A5568)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('OK', style: TextStyle(color: Color(0xFF718096))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _loadAllData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3182CE),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child:
                  const Text('Refresh', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.medical_services_rounded,
                color: Color(0xFF3182CE)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Assign Doctor to ${users[userIndex]['name']}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3182CE).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Color(0xFF3182CE), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Showing ${organizationDoctors.length} doctors from your organization',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF3182CE)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: organizationDoctors.length,
                  itemBuilder: (context, index) {
                    final doctor = organizationDoctors[index];
                    final isCurrentlyAssigned =
                        users[userIndex]['assignedDoctorId'] == doctor['id'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isCurrentlyAssigned
                            ? const Color(0xFF38A169).withOpacity(0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrentlyAssigned
                              ? const Color(0xFF38A169)
                              : Colors.grey.shade200,
                          width: isCurrentlyAssigned ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isCurrentlyAssigned
                                ? const Color(0xFF38A169)
                                : const Color(0xFF3182CE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            doctor['name']!.isNotEmpty
                                ? doctor['name']![0].toUpperCase()
                                : 'D',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                doctor['name']!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isCurrentlyAssigned)
                              const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF38A169), size: 20),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doctor['specialization'] ??
                                  'General Practitioner',
                              style: const TextStyle(color: Color(0xFF4A5568)),
                            ),
                            if (doctor['department'] != null &&
                                doctor['department']!.isNotEmpty)
                              Text(
                                'Dept: ${doctor['department']}',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF718096)),
                              ),
                          ],
                        ),
                        trailing: isCurrentlyAssigned
                            ? const Text(
                                'Currently Assigned',
                                style: TextStyle(
                                  color: Color(0xFF38A169),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_ios_rounded,
                                size: 16),
                        onTap: () {
                          Navigator.pop(context);
                          _assignDoctor(userIndex, doctor);
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
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF718096))),
          ),
          if (users[userIndex]['assignedDoctor'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeAssignment(userIndex);
              },
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE53E3E)),
              child: const Text('Remove Assignment'),
            ),
        ],
      ),
    );
  }

  // Show approval dialog
  void _showApprovalDialog(int userIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.pending_actions_rounded, color: Color(0xFFD69E2E)),
            SizedBox(width: 8),
            Text('Patient Approval Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patient "${users[userIndex]['name']}" is pending approval.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'You need to approve this patient before they can be assigned to a doctor.',
              style: TextStyle(color: Color(0xFF4A5568)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF718096))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectPendingPatient(userIndex);
            },
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFE53E3E)),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approvePendingPatient(userIndex);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38A169),
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  // Show user details dialog
  void _showUserDetails(Map<String, dynamic> user, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF3182CE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_rounded, color: Color(0xFF3182CE)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(user['name']!, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Type', user['type'], Icons.badge_rounded),
            _buildDetailRow(
                'Last Visit', user['lastVisit'], Icons.calendar_today_rounded),
            _buildDetailRow('User ID', user['id'], Icons.tag_rounded),
            _buildDetailRow(
                'Email',
                user['email'].isNotEmpty ? user['email'] : 'Not provided',
                Icons.email_rounded),
            _buildDetailRow(
                'Phone',
                user['phone'].isNotEmpty ? user['phone'] : 'Not provided',
                Icons.phone_rounded),
            _buildDetailRow(
                'Address',
                user['address'].isNotEmpty ? user['address'] : 'Not provided',
                Icons.location_on_rounded),
            const SizedBox(height: 16),
            if (user['type'] == 'Patient') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: user['assignedDoctor'] == null
                      ? const Color(0xFFD69E2E).withOpacity(0.1)
                      : const Color(0xFF38A169).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.medical_services_rounded,
                      color: user['assignedDoctor'] == null
                          ? const Color(0xFFD69E2E)
                          : const Color(0xFF38A169),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Assigned Doctor: ${user['assignedDoctor'] ?? 'Not assigned'}',
                        style: TextStyle(
                          color: user['assignedDoctor'] == null
                              ? const Color(0xFFD69E2E)
                              : const Color(0xFF38A169),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (user['type'] == 'Patient')
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAssignDoctorDialog(index);
              },
              icon: const Icon(Icons.medical_services_rounded, size: 18),
              label: Text(user['assignedDoctor'] == null
                  ? 'Assign Doctor'
                  : 'Change Doctor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: user['assignedDoctor'] == null
                    ? const Color(0xFF3182CE)
                    : const Color(0xFFD69E2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Close', style: TextStyle(color: Color(0xFF718096))),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF718096)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF718096),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2D3748),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: _buildModernAppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(
                  color: Color(0xFF3B82F6),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading patients and doctors...',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: _buildModernAppBar(),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Error Loading Data',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadAllData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildModernAppBar(),
      body: users.isEmpty
          ? _buildModernEmptyState()
          : Column(
              children: [
                _buildSearchAndFilter(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadAllData,
                    color: const Color(0xFF3B82F6),
                    child: ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height * 0.12,
                      ),
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final userIndex = users.indexWhere(
                          (u) => u['id'] == filteredUsers[index]['id'],
                        );
                        return _buildEnhancedPatientCard(
                            filteredUsers[index], userIndex);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModernEmptyState() {
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
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF3B82F6).withOpacity(0.1),
                    const Color(0xFF1E40AF).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 64,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Patients Found',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Patients will appear here once they register\nin your healthcare system.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadAllData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    // Increased height to accommodate all content properly
    final double baseHeight = 180; // Increased from 140
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double totalHeight = baseHeight + statusBarHeight;

    return PreferredSize(
      preferredSize: Size.fromHeight(totalHeight),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E40AF),
              const Color(0xFF3B82F6),
              const Color(0xFF60A5FA),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                16, 8, 16, 16), // Increased bottom padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_rounded),
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Patient Management',
                        style: TextStyle(
                          fontSize: 22, // Slightly reduced font size
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: _loadAllData,
                        icon: const Icon(Icons.refresh_rounded),
                        color: Colors.white,
                        tooltip: 'Refresh',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Stats Cards Row - Made more compact
                Row(
                  children: [
                    Expanded(
                      child: _buildModernStatCard(
                        'Total Patients',
                        users.length.toString(),
                        Icons.group_rounded,
                        Colors.white.withOpacity(0.9),
                        const Color(0xFF1E40AF),
                      ),
                    ),
                    const SizedBox(width: 8), // Reduced spacing
                    Expanded(
                      child: _buildModernStatCard(
                        'Assigned',
                        users
                            .where((u) => u['assignedDoctor'] != null)
                            .length
                            .toString(),
                        Icons.assignment_turned_in_rounded,
                        const Color(0xFF10B981).withOpacity(0.9),
                        Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8), // Reduced spacing
                    Expanded(
                      child: _buildModernStatCard(
                        'Unassigned',
                        users
                            .where((u) => u['assignedDoctor'] == null)
                            .length
                            .toString(),
                        Icons.assignment_late_rounded,
                        const Color(0xFFEF4444).withOpacity(0.9),
                        Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Also update your _buildModernStatCard method to be more compact
  Widget _buildModernStatCard(String title, String value, IconData icon,
      Color backgroundColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 8), // Reduced padding
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: textColor,
            size: 18, // Reduced icon size
          ),
          const SizedBox(height: 4), // Reduced spacing
          Text(
            value,
            style: TextStyle(
              fontSize: 16, // Reduced font size
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10, // Reduced font size
              color: textColor.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Fix 1: Null safety in _buildSearchAndFilter method
  Widget _buildSearchAndFilter() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search Bar and Invite Button Row
          Row(
            children: [
              // Search Bar
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    onChanged: (value) => setState(() => searchQuery = value),
                    decoration: InputDecoration(
                      hintText:
                          'Search patients by email...', // Changed from "name or ID"
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Colors.grey.shade400),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () => setState(() => searchQuery = ''),
                              icon: Icon(Icons.clear_rounded,
                                  color: Colors.grey.shade400),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Invite User Button
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3182CE), Color(0xFF1E40AF)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3182CE).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _showInviteUserDialog,
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Icon(
                        Icons.person_add_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Updated Filter Chips with Invited
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Invited', 'invited',
                    color: const Color(0xFF8B5CF6),
                    icon: Icons.mail_outline_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('Unassigned', 'unassigned',
                    color: const Color(0xFFEF4444),
                    icon: Icons.person_off_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('Assigned', 'assigned',
                    color: const Color(0xFF10B981),
                    icon: Icons.person_add_alt_rounded),
                const SizedBox(width: 16),
                Text(
                  '${filteredUsers.length} patients',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value,
      {Color? color, IconData? icon}) {
    final isSelected = selectedFilter == value;
    final chipColor = color ?? const Color(0xFF3B82F6);

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 16, color: isSelected ? chipColor : Colors.grey.shade600),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) => setState(() => selectedFilter = value),
      backgroundColor: Colors.white,
      selectedColor: chipColor.withOpacity(0.1),
      checkmarkColor: chipColor,
      labelStyle: TextStyle(
        color: isSelected ? chipColor : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? chipColor : Colors.grey.shade300,
        ),
      ),
    );
  }

  // Fix 3: Safe string handling in _buildEnhancedPatientCard
  Widget _buildEnhancedPatientCard(Map<String, dynamic> user, int index) {
    final String status = user['status']?.toString() ?? 'pending';
    final bool hasAssignedDoctor = user['assignedDoctor'] != null;
    final String userName = user['name']?.toString() ?? 'Unknown Patient';
    final String userEmail = user['email']?.toString() ?? '';
    final String userPhone = user['phone']?.toString() ?? '';
    final String userId = user['id']?.toString() ?? '';
    final String userType = user['type']?.toString() ?? 'Patient';
    final String lastVisit = user['lastVisit']?.toString() ?? 'Unknown';

    // Define colors based on status
    Color statusColor;
    Color borderColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'pending':
        statusColor = const Color(0xFFF59E0B);
        borderColor = const Color(0xFFF59E0B).withOpacity(0.3);
        statusIcon = Icons.hourglass_empty_rounded;
        statusText = 'Pending Approval';
        break;
      case 'unassigned':
        statusColor = const Color(0xFFEF4444);
        borderColor = const Color(0xFFEF4444).withOpacity(0.3);
        statusIcon = Icons.person_off_rounded;
        statusText = 'Unassigned';
        break;
      case 'assigned':
        statusColor = const Color(0xFF10B981);
        borderColor = const Color(0xFF10B981).withOpacity(0.3);
        statusIcon = Icons.check_circle_rounded;
        statusText = 'Assigned';
        break;
      case 'invited':
        statusColor = const Color(0xFF8B5CF6);
        borderColor = const Color(0xFF8B5CF6).withOpacity(0.3);
        statusIcon = Icons.mail_outline_rounded;
        statusText = 'Invited';
        break;
      default:
        statusColor = Colors.grey;
        borderColor = Colors.grey.withOpacity(0.3);
        statusIcon = Icons.help_outline_rounded;
        statusText = 'Unknown';
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            (index * 0.1).clamp(0.0, 1.0),
            1.0,
            curve: Curves.easeOutBack,
          ),
        )),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey.shade50,
                  ],
                ),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showUserDetails(user, index),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row with Status Badge
                        Row(
                          children: [
                            Hero(
                              tag: 'patient_$userId',
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF3B82F6),
                                      Color(0xFF1E40AF),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF3B82F6)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    userName.isNotEmpty
                                        ? userName[0].toUpperCase()
                                        : 'P',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3B82F6)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          userType,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF3B82F6),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'ID: $userId',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Status Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: statusColor.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon,
                                      color: statusColor, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Status-specific content section
                        if (status == 'pending') ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      const Color(0xFFF59E0B).withOpacity(0.2)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.pending_actions_rounded,
                                        size: 20, color: Color(0xFFF59E0B)),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'This patient is awaiting your approval',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFF59E0B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Review patient information and approve to allow doctor assignment',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (status == 'invited') ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      const Color(0xFF8B5CF6).withOpacity(0.2)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.mail_outline_rounded,
                                        size: 20, color: Color(0xFF8B5CF6)),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Invitation sent to this user',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF8B5CF6),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'User will need to accept the invitation to become an active patient',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Doctor Assignment Section for non-pending patients
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: hasAssignedDoctor
                                  ? const Color(0xFF10B981).withOpacity(0.05)
                                  : const Color(0xFFEF4444).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasAssignedDoctor
                                    ? const Color(0xFF10B981).withOpacity(0.2)
                                    : const Color(0xFFEF4444).withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.medical_services_rounded,
                                      size: 20,
                                      color: hasAssignedDoctor
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        hasAssignedDoctor
                                            ? 'Assigned to: ${user['assignedDoctor'] ?? 'Unknown Doctor'}'
                                            : 'No doctor assigned',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: hasAssignedDoctor
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.schedule_rounded,
                                        size: 16, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Last visit: $lastVisit',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (userEmail.isNotEmpty) ...[
                                      Icon(Icons.email_outlined,
                                          size: 16,
                                          color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                    ],
                                    if (userPhone.isNotEmpty) ...[
                                      Icon(Icons.phone_outlined,
                                          size: 16,
                                          color: Colors.grey.shade600),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Status-specific Action Buttons
                        if (status == 'pending') ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _rejectPendingPatient(index),
                                  icon:
                                      const Icon(Icons.close_rounded, size: 18),
                                  label: const Text('Reject'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFEF4444),
                                    side: const BorderSide(
                                        color: Color(0xFFEF4444)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _approvePendingPatient(index),
                                  icon:
                                      const Icon(Icons.check_rounded, size: 18),
                                  label: const Text('Approve'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          // Regular action buttons for approved patients
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _showUserDetails(user, index),
                                  icon: const Icon(Icons.visibility_outlined,
                                      size: 18),
                                  label: const Text('View Details'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF3B82F6),
                                    side: const BorderSide(
                                        color: Color(0xFF3B82F6)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _showAssignDoctorDialog(index),
                                  icon: Icon(
                                    hasAssignedDoctor
                                        ? Icons.edit_rounded
                                        : Icons.person_add_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                      hasAssignedDoctor ? 'Change' : 'Assign'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: hasAssignedDoctor
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
