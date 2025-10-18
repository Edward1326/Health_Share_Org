import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'patients_tab.dart';
import '/main.dart';
import 'staff_profile.dart';

// Theme colors - matching admin dashboard exactly
class StaffDashboardTheme {
  static const Color primaryGreen = Color(0xFF4A8B3A);
  static const Color lightGreen = Color(0xFF6BA85A);
  static const Color sidebarGray = Color(0xFFF8F9FA);
  static const Color textGray = Color(0xFF6C757D);
  static const Color darkGray = Color(0xFF495057);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color approvedGreen = Color(0xFF28A745);
  static const Color pendingOrange = Color(0xFFFF9500);
}

// Main Staff Dashboard Layout Widget with Collapsible Sidebar
class MainStaffDashboardLayout extends StatefulWidget {
  final Widget content;
  final String title;
  final List<Widget>? actions;
  final int selectedNavIndex;

  const MainStaffDashboardLayout({
    Key? key,
    required this.content,
    required this.title,
    this.actions,
    this.selectedNavIndex = 0,
  }) : super(key: key);

  @override
  State<MainStaffDashboardLayout> createState() => _MainStaffDashboardLayoutState();
}

class _MainStaffDashboardLayoutState extends State<MainStaffDashboardLayout> {
  String _userName = '';
  String _userEmail = '';
  String _organizationName = '';
  String _userPosition = '';
  String _userDepartment = '';
  String _userId = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Staff Member';
        _userEmail = prefs.getString('user_email') ?? '';
        _organizationName = prefs.getString('organization_name') ?? 'Hospital';
        _userPosition = prefs.getString('user_position') ?? 'Staff';
        _userDepartment = prefs.getString('user_department') ?? '';
        _userId = prefs.getString('user_id') ?? '';
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      final shouldSignOut = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: StaffDashboardTheme.textGray)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      );

      if (shouldSignOut == true) {
        await Supabase.instance.client.auth.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      print('Error signing out: $e');
      _showSnackBar('Error signing out. Please try again.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: StaffDashboardTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: StaffDashboardTheme.sidebarGray,
        body: Center(child: CircularProgressIndicator(color: StaffDashboardTheme.primaryGreen)),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    return Scaffold(
      backgroundColor: StaffDashboardTheme.sidebarGray,
      body: SafeArea(
        child: isSmallScreen 
          ? widget.content // Mobile: Just show content directly
          : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Sidebar Navigation - Fixed width
        Container(
          width: 250.0,
          child: _buildSidebar(),
        ),
        
        // Main Content Area
        Expanded(
          child: Column(
            children: [
              // Top Header Bar (Green)
              _buildTopHeader(),
              
              // Main Content
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: widget.content,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      color: StaffDashboardTheme.sidebarGray,
      child: Column(
        children: [
          // Dashboard Title
          Container(
            padding: const EdgeInsets.all(24),
            child: const Text(
              'Dashboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: StaffDashboardTheme.darkGray,
              ),
            ),
          ),
          
          // Navigation Items - Only Patients and Profile
          _buildNavItem(Icons.people, 'Patients', 0, widget.selectedNavIndex == 0),
          _buildNavItem(Icons.person, 'Profile', 1, widget.selectedNavIndex == 1),
          
          const Spacer(),
          
          // Logout Button
          Container(
            padding: const EdgeInsets.all(24),
            child: InkWell(
              onTap: _signOut,
              child: const Row(
                children: [
                  Icon(Icons.logout, color: StaffDashboardTheme.textGray, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Log out',
                    style: TextStyle(
                      color: StaffDashboardTheme.textGray,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title, int index, bool isSelected) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? StaffDashboardTheme.primaryGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          if (index == 0) {
            // Patients
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const StaffDashboard()),
            );
          } else if (index == 1) {
            // Profile
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const StaffProfilePage()),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : StaffDashboardTheme.textGray,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : StaffDashboardTheme.textGray,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      height: 60,
      color: StaffDashboardTheme.primaryGreen,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Icon(Icons.show_chart, color: Colors.white),
          const SizedBox(width: 16),
          const Icon(Icons.people, color: Colors.white),
          
          const Spacer(),
          
          // Title and actions
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Actions
          if (widget.actions != null) ...widget.actions!,
          
          const SizedBox(width: 16),
          
          // User info
          Row(
            children: [
              const Icon(Icons.person, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                _userName.split(' ').first,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

// Updated Staff Dashboard - now defaults to Patients tab
class StaffDashboard extends StatelessWidget {
  const StaffDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Mobile layout
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;
    
    if (isSmallScreen) {
      return _buildMobileLayout(context);
    }

    // Desktop layout - Default to Patients tab (selectedNavIndex: 0)
    return const MainStaffDashboardLayout(
      title: 'Patient Management',
      selectedNavIndex: 0,
      content: ModernPatientsContentWidget(),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: StaffDashboardTheme.sidebarGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Patients',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Notifications coming soon!'),
                  backgroundColor: StaffDashboardTheme.primaryGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffProfilePage()),
                  );
                  break;
                case 'signout':
                  _signOut(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Sign Out', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const ModernPatientsContentWidget(),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      final shouldSignOut = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: StaffDashboardTheme.textGray)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      );

      if (shouldSignOut == true) {
        await Supabase.instance.client.auth.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      print('Error signing out: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error signing out. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }
}