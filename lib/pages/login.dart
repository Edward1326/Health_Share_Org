import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup.dart';
import 'admin/admin_dashboard.dart';
import 'staff/staff_dashboard.dart';
import 'reset_password.dart';
import 'package:health_share_org/functions/login_function.dart'; // Import your new service

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailOrUsernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    // Listen for auth state changes (like password reset)
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        // Navigate to reset password page when recovery link is clicked
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ResetPasswordPage(),
              ),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _emailOrUsernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    // Check rate limiting before attempting login
    if (!LoginService.canAttemptLogin()) {
      final remainingTime = LoginService.getRemainingCooldownTime();
      _showErrorSnackBar(
          'Please wait $remainingTime seconds before trying again.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await LoginService.login(
        emailOrUsername: _emailOrUsernameController.text,
        password: _passwordController.text,
      );

      if (result.success) {
        // Navigate based on user position
        if (mounted) {
          if (result.userPosition == 'administrator') {
            // Navigate to admin dashboard
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const Dashboard(), // Your admin dashboard
              ),
            );
          } else {
            // Navigate to staff dashboard for all other positions
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffDashboard(),
              ),
            );
          }
        }
      } else {
        _showErrorSnackBar(result.errorMessage ?? 'Login failed');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    final input = _emailOrUsernameController.text.trim();

    if (input.isEmpty) {
      _showErrorSnackBar('Please enter your email first.');
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Sending reset email...'),
          ],
        ),
      ),
    );

    try {
      final result = await LoginService.resetPassword(
        emailOrUsername: input,
        redirectTo:
            'your-app-scheme://reset-password', // Replace with your app's deep link scheme
      );

      Navigator.of(context).pop(); // Close loading dialog

      if (result.success) {
        // Show success dialog with instructions
        _showPasswordResetDialog(result.email!);
      } else {
        _showErrorSnackBar(result.errorMessage ?? 'Failed to send reset email');
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _showErrorSnackBar(
          'Failed to send password reset email. Please try again.');
    }
  }

  void _showPasswordResetDialog(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.email, color: Colors.green),
            SizedBox(width: 8),
            Text('Reset Email Sent'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A password reset email has been sent to:'),
            const SizedBox(height: 8),
            Text(
              email,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Please follow these steps:'),
            const SizedBox(height: 8),
            const Text('1. Check your email inbox (and spam folder)'),
            const Text('2. Click the reset link in the email'),
            const Text('3. Return to the app to set your new password'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ResetPasswordPage(),
                ),
              );
            },
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Medical Illustration
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4F8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    children: [
                      // Background shapes
                      Positioned(
                        top: 20,
                        left: 30,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Color(0xFFB8E6F0),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 40,
                        right: 40,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xFFB8E6F0),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 30,
                        left: 50,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Color(0xFFB8E6F0),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),

                      // Medical icons
                      const Positioned(
                        top: 60,
                        left: 60,
                        child: Icon(
                          Icons.medical_services,
                          size: 40,
                          color: Color(0xFF4A90E2),
                        ),
                      ),
                      const Positioned(
                        top: 80,
                        right: 80,
                        child: Icon(
                          Icons.health_and_safety,
                          size: 30,
                          color: Color(0xFF4A90E2),
                        ),
                      ),
                      const Positioned(
                        bottom: 60,
                        right: 60,
                        child: Icon(
                          Icons.local_hospital,
                          size: 35,
                          color: Color(0xFF4A90E2),
                        ),
                      ),

                      // Central medical professional icon
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4A90E2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.medical_information,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Login Title
                const Text(
                  'Staff Login',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),

                const SizedBox(height: 48),

                // Login Form
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Email/Username Field
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE9ECEF),
                                width: 1,
                              ),
                            ),
                            child: TextFormField(
                              controller: _emailOrUsernameController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                labelStyle: TextStyle(
                                  color: Color(0xFF6C757D),
                                  fontSize: 16,
                                ),
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: Color(0xFF4A90E2),
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your email';
                                }
                                return null;
                              },
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Password Field
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE9ECEF),
                                width: 1,
                              ),
                            ),
                            child: TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: const TextStyle(
                                  color: Color(0xFF6C757D),
                                  fontSize: 16,
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFF4A90E2),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF6C757D),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) {
                                if (!_isLoading) _login();
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Forgot Password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _forgotPassword,
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Color(0xFF4A90E2),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Login Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      // Check cooldown before attempting login
                                      if (!LoginService.canAttemptLogin()) {
                                        final remainingTime = LoginService
                                            .getRemainingCooldownTime();
                                        _showErrorSnackBar(
                                            'Please wait $remainingTime seconds before trying again.');
                                        return;
                                      }
                                      _login();
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A90E2),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Login',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Sign Up Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'New to this platform? ',
                      style: TextStyle(
                        color: Color(0xFF6C757D),
                        fontSize: 14,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SignupPage(),
                          ),
                        );
                      },
                      child: const Text(
                        'Register',
                        style: TextStyle(
                          color: Color(0xFF4A90E2),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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
}
