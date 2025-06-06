import 'package:flutter/material.dart';
import 'pages/admin/admin_dashboard.dart';
import 'pages/signup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/login.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://iqrlfiwtgdnmsxhyoiaw.supabase.co', // Supabase project URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlxcmxmaXd0Z2RubXN4aHlvaWF3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDg3Mzc3MDEsImV4cCI6MjA2NDMxMzcwMX0._N_v5dh3RXbBIdpngAZGd7cqLIRR-WagQbJ65laZvX8',       // From your Supabase project settings
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
      ),
      home: const LoginPage(),

    );
  }
}

