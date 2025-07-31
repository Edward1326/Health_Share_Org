import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin/admin_dashboard.dart';
import 'staff/staff_dashboard.dart';
import 'reset_password.dart';

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
  DateTime? _lastLoginAttempt;
  static const int _loginCooldownSeconds = 5;

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

    // Check rate limiting
    if (_lastLoginAttempt != null) {
      final timeSinceLastAttempt =
          DateTime.now().difference(_lastLoginAttempt!).inSeconds;
      if (timeSinceLastAttempt < _loginCooldownSeconds) {
        final remainingTime = _loginCooldownSeconds - timeSinceLastAttempt;
        _showErrorSnackBar(
            'Please wait $remainingTime seconds before trying again.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    _lastLoginAttempt = DateTime.now();

    try {
      final input = _emailOrUsernameController.text.trim();
      final password = _passwordController.text;

      print('DEBUG: Input received: $input'); // DEBUG LINE

      String email = input;

      // If input doesn't contain @, it's likely a username - we need to find the email
      if (!input.contains('@')) {
        print(
            'DEBUG: Treating input as username, looking up email...'); // DEBUG LINE

        // Query the User table to find the email associated with this username
        final userResponse = await Supabase.instance.client
            .from('User')
            .select('person_id')
            .eq('username', input)
            .maybeSingle();

        print('DEBUG: User lookup response: $userResponse'); // DEBUG LINE

        if (userResponse == null) {
          print('DEBUG: Username not found in database'); // DEBUG LINE
          throw Exception('Username not found');
        }

        // Get email from Person table
        final personId = userResponse['person_id'];
        print('DEBUG: Found person_id: $personId'); // DEBUG LINE

        final personResponse = await Supabase.instance.client
            .from('Person')
            .select('email')
            .eq('id', personId)
            .single();

        print('DEBUG: Person lookup response: $personResponse'); // DEBUG LINE
        email = personResponse['email'];
        print('DEBUG: Email found: $email'); // DEBUG LINE
      } else {
        print('DEBUG: Treating input as email directly'); // DEBUG LINE
      }

      print('DEBUG: Attempting to sign in with email: $email'); // DEBUG LINE

      // Use Supabase Auth to sign in
      final authResponse =
          await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      print(
          'DEBUG: Auth response received: ${authResponse.user?.id}'); // DEBUG LINE

      if (authResponse.user == null) {
        throw Exception('Login failed');
      }

      final user = authResponse.user!;
      print('Auth user signed in: ${user.id}');

      // Get comprehensive user details after successful authentication
      final userDetails = await _getUserDetailsFromMetadata(user);

      // Store user session
      await _storeUserSession(userDetails, user);

      print('Login successful, navigating to dashboard...');

      // Navigate to staff dashboard
      String userPosition = '';
      if (userDetails['organization_users'].isNotEmpty) {
        userPosition = userDetails['organization_users'][0]['position']
                ?.toString()
                .toLowerCase() ??
            '';
      }

      if (mounted) {
        if (userPosition == 'administrator') {
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
    } catch (e) {
      print('Login error: $e');

      String errorMessage = 'Login failed: ';

      if (e.toString().contains('Username not found')) {
        errorMessage += 'Username not found. Please check your username.';
      } else if (e.toString().contains('Invalid login credentials') ||
          e.toString().contains('Email not confirmed')) {
        errorMessage +=
            'Invalid email or password. Please check your credentials.';
      } else if (e.toString().contains('Email not confirmed')) {
        errorMessage += 'Please verify your email address before signing in.';
      } else if (e.toString().contains('Too many requests')) {
        errorMessage +=
            'Too many login attempts. Please wait before trying again.';
      } else {
        errorMessage += 'Something went wrong. Please try again.';
      }

      _showErrorSnackBar(errorMessage);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _getUserDetailsFromMetadata(User user) async {
    try {
      final userId = user.userMetadata?['user_id'];
      final personId = user.userMetadata?['person_id'];

      if (userId == null || personId == null) {
        throw Exception('User metadata incomplete');
      }

      return await _getComprehensiveUserDetails(
          personId.toString(), userId.toString());
    } catch (e) {
      print('Error getting user details from metadata: $e');
      // Fallback to email lookup
      return await _getUserDetailsByEmail(user.email!);
    }
  }

  Future<Map<String, dynamic>> _getUserDetailsByEmail(String email) async {
    try {
      // Find Person by email
      final personResponse = await Supabase.instance.client
          .from('Person')
          .select('*')
          .eq('email', email)
          .single();

      // Find User by person_id
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('*')
          .eq('person_id', personResponse['id'])
          .single();

      return await _getComprehensiveUserDetails(
          personResponse['id'].toString(), userResponse['id'].toString());
    } catch (e) {
      print('Error getting user details by email: $e');
      throw Exception('Failed to load user information');
    }
  }

  Future<Map<String, dynamic>> _getComprehensiveUserDetails(
      String personId, String userId) async {
    try {
      // Get Person details
      final personResponse = await Supabase.instance.client
          .from('Person')
          .select('*')
          .eq('id', personId)
          .single();

      // Get User details
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('*')
          .eq('id', userId)
          .single();

      // Get Organization_User details if they exist
      final orgUserResponse = await Supabase.instance.client
          .from('Organization_User')
          .select('*')
          .eq('user_id', userId);

      List<Map<String, dynamic>> organizationUsers = [];
      List<Map<String, dynamic>> organizations = [];

      if (orgUserResponse.isNotEmpty) {
        for (var orgUser in orgUserResponse) {
          organizationUsers.add(orgUser);

          // Get organization details
          final orgId = orgUser['organization_id'].toString();
          final orgResponse = await Supabase.instance.client
              .from('Organization')
              .select('*')
              .eq('id', orgId)
              .single();

          organizations.add(orgResponse);
        }
      }

      return {
        'person': personResponse,
        'user': userResponse,
        'organization_users': organizationUsers,
        'organizations': organizations,
      };
    } catch (e) {
      print('Error fetching comprehensive user details: $e');
      throw Exception('Failed to load user information');
    }
  }

  Future<void> _storeUserSession(
      Map<String, dynamic> userDetails, User authUser) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Store auth user info
      await prefs.setString('auth_user_id', authUser.id);
      await prefs.setString('auth_user_email', authUser.email ?? '');

      // Store internal user info
      await prefs.setString(
          'user_id', userDetails['user']['id']?.toString() ?? '');
      await prefs.setString(
          'person_id', userDetails['person']['id']?.toString() ?? '');
      await prefs.setString(
          'username', userDetails['user']['username']?.toString() ?? '');
      await prefs.setString('user_name',
          '${userDetails['person']['first_name'] ?? ''} ${userDetails['person']['last_name'] ?? ''}');
      await prefs.setString(
          'user_email', userDetails['person']['email']?.toString() ?? '');

      if (userDetails['organization_users'].isNotEmpty) {
        await prefs.setBool('is_organization_user', true);
        await prefs.setString(
            'organization_id',
            userDetails['organization_users'][0]['organization_id']
                    ?.toString() ??
                '');
        await prefs.setString('user_position',
            userDetails['organization_users'][0]['position']?.toString() ?? '');
        await prefs.setString(
            'user_department',
            userDetails['organization_users'][0]['department']?.toString() ??
                '');
        await prefs.setString('organization_name',
            userDetails['organizations'][0]['name']?.toString() ?? '');
      } else {
        await prefs.setBool('is_organization_user', false);
      }
    } catch (e) {
      print('Error storing session data: $e');
    }
  }

  Future<void> _forgotPassword() async {
    final input = _emailOrUsernameController.text.trim();

    if (input.isEmpty) {
      _showErrorSnackBar('Please enter your email or username first.');
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
      String email = input;

      // If input doesn't contain @, it's likely a username - we need to find the email
      if (!input.contains('@')) {
        // Get user by username
        final userResponse = await Supabase.instance.client
            .from('User')
            .select('person_id')
            .eq('username', input)
            .maybeSingle();

        if (userResponse == null) {
          Navigator.of(context).pop(); // Close loading dialog
          _showErrorSnackBar('Username not found.');
          return;
        }

        // Get email from Person table
        final personId = userResponse['person_id'];
        final personResponse = await Supabase.instance.client
            .from('Person')
            .select('email')
            .eq('id', personId)
            .single();

        email = personResponse['email'];
      }

      // Send reset email using Supabase Auth with redirect URL
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo:
            'your-app-scheme://reset-password', // Replace with your app's deep link scheme
      );

      Navigator.of(context).pop(); // Close loading dialog

      // Show success dialog with instructions
      _showPasswordResetDialog(email);
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      print('Password reset error: $e');
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
                                labelText: 'Email or Username',
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
                                  return 'Please enter your email or username';
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
                                      if (_lastLoginAttempt != null) {
                                        final timeSinceLastAttempt =
                                            DateTime.now()
                                                .difference(_lastLoginAttempt!)
                                                .inSeconds;
                                        if (timeSinceLastAttempt <
                                            _loginCooldownSeconds) {
                                          final remainingTime =
                                              _loginCooldownSeconds -
                                                  timeSinceLastAttempt;
                                          _showErrorSnackBar(
                                              'Please wait $remainingTime seconds before trying again.');
                                          return;
                                        }
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
