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
              onTap: () {
                Navigator.pushReplacementNamed(context, '/login');
              },
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