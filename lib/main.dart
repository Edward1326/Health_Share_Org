import 'package:flutter/material.dart';
import 'package:health_share_org/pages/staff/staff_profile.dart';
import 'pages/admin/admin_dashboard.dart';
import 'services/signup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/login.dart';
import 'pages/health_share/create_organization.dart';
import 'pages/staff/staff_dashboard.dart';
import 'pages/reset_password.dart';
import 'pages/admin/hospital_profile.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'pages/admin/admin_profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthShare',
      theme: ThemeData(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/login', // Changed from '/' to '/login'
      routes: {
        '/': (context) => const LoginPage(), // Changed to LoginPage
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/admin_dashboard': (context) => const Dashboard(),
        '/create_organization': (context) => const CreateOrganizationPage(),
        '/health_share': (context) => const CreateOrganizationPage(),
        '/staff_dashboard': (context) => const StaffDashboard(),
        '/reset_password': (context) => const ResetPasswordPage(),
        '/profile': (context) => const HospitalProfileContentWidget(),
        '/staff_profile': (context) => const StaffProfilePage(),
        '/admin_profile': (context) => const AdminProfilePage(),
      },
    );
  }
}
