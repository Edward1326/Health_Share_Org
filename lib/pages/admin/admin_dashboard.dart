// main_dashboard_layout.dart
import 'package:flutter/material.dart';
import 'employeelist.dart';
import 'patientslist.dart';
import 'hospital_profile.dart';
import 'admin_profile.dart';

// Theme colors - shared across all dashboard components
class DashboardTheme {
  static const Color primaryGreen = Color(0xFF4A8B3A);
  static const Color lightGreen = Color(0xFF6BA85A);
  static const Color sidebarGray = Color(0xFFF8F9FA);
  static const Color textGray = Color(0xFF6C757D);
  static const Color darkGray = Color(0xFF495057);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color approvedGreen = Color(0xFF28A745);
  static const Color pendingOrange = Color(0xFFFF9500);
}

// Main Dashboard Layout Widget with Collapsible Sidebar
class MainDashboardLayout extends StatefulWidget {
  final Widget content;
  final String title;
  final List<Widget>? actions;
  final int selectedNavIndex;

  const MainDashboardLayout({
    Key? key,
    required this.content,
    required this.title,
    this.actions,
    this.selectedNavIndex = 0,
  }) : super(key: key);

  @override
  State<MainDashboardLayout> createState() => _MainDashboardLayoutState();
}

class _MainDashboardLayoutState extends State<MainDashboardLayout> {
  
  Future<void> _signOut() async {
    try {
      final shouldSignOut = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFFF8F9FA),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon header with gradient background
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.shade400,
                        Colors.red.shade600,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: DashboardTheme.darkGray,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Are you sure you want to sign out?\nYou will need to log in again to access your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: DashboardTheme.textGray,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: DashboardTheme.textGray,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade500,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Sign Out',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (shouldSignOut == true && mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    return Scaffold(
      backgroundColor: DashboardTheme.sidebarGray,
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
      color: DashboardTheme.sidebarGray,
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
                color: DashboardTheme.darkGray,
              ),
            ),
          ),
          
          // Navigation Items
          _buildNavItem(Icons.people, 'Employees', 0, widget.selectedNavIndex == 0),
          _buildNavItem(Icons.local_hospital, 'Patients', 1, widget.selectedNavIndex == 1),
          _buildNavItem(Icons.business, 'Hospital Profile', 2, widget.selectedNavIndex == 2),
          _buildNavItem(Icons.account_circle, 'My Profile', 3, widget.selectedNavIndex == 3),
          
          const Spacer(),
          
          // Logout Button
          Container(
            padding: const EdgeInsets.all(24),
            child: InkWell(
              onTap: _signOut,
              child: const Row(
                children: [
                  Icon(Icons.logout, color: DashboardTheme.textGray, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Log out',
                    style: TextStyle(
                      color: DashboardTheme.textGray,
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
        color: isSelected ? DashboardTheme.primaryGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          switch (index) {
            case 0: // Employees
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const MainDashboardLayout(
                    title: 'Employee Management',
                    selectedNavIndex: 0,
                    content: EmployeeContentWidget(),
                  ),
                ),
              );
              break;
            case 1: // Patients
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const MainDashboardLayout(
                    title: 'Patient Management',
                    selectedNavIndex: 1,
                    content: PatientContentWidget(),
                  ),
                ),
              );
              break;
            case 2: // Hospital Profile
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const MainDashboardLayout(
                    title: 'Hospital Profile',
                    selectedNavIndex: 2,
                    content: HospitalProfileContentWidget(),
                  ),
                ),
              );
              break;
            case 3: // My Profile
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminProfilePage(),
                ),
              );
              break;
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : DashboardTheme.textGray,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : DashboardTheme.textGray,
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
      color: DashboardTheme.primaryGreen,
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
          const Row(
            children: [
              Icon(Icons.person, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Admin',
                style: TextStyle(
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

// Dashboard - now directly shows Employees page
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Always go directly to Employees page
    return const MainDashboardLayout(
      title: 'Employee Management',
      selectedNavIndex: 0,
      content: EmployeeContentWidget(),
    );
  }
}