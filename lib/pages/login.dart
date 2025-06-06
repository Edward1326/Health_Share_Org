import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameOrEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  DateTime? _lastLoginAttempt;
  static const int _loginCooldownSeconds = 30;

  @override
  void dispose() {
    _usernameOrEmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    // Check rate limiting
    if (_lastLoginAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(_lastLoginAttempt!).inSeconds;
      if (timeSinceLastAttempt < _loginCooldownSeconds) {
        final remainingTime = _loginCooldownSeconds - timeSinceLastAttempt;
        _showErrorSnackBar('Please wait $remainingTime seconds before trying again.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    _lastLoginAttempt = DateTime.now();

    try {
      final input = _usernameOrEmailController.text.trim();
      String? email;
      
      // Determine if input is email or username
      if (RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(input)) {
        // Input is email
        email = input;
      } else {
        // Input is username, need to find the associated email
        final userResponse = await Supabase.instance.client
            .from('User')
            .select('person_id')
            .eq('username', input)
            .maybeSingle();

        if (userResponse == null) {
          throw Exception('Username not found');
        }

        // Get the email from Person table
        final personResponse = await Supabase.instance.client
            .from('Person')
            .select('email')
            .eq('id', userResponse['person_id'])
            .single();

        email = personResponse['email'];
      }

      if (email == null) {
        throw Exception('Unable to find account');
      }

      // Authenticate with Supabase Auth using email
      final authResponse = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _passwordController.text,
      );

      if (authResponse.user == null) {
        throw Exception('Authentication failed');
      }

      // Get comprehensive user details including organization info
      final userDetails = await _getComprehensiveUserDetails(authResponse.user!.id);
      
      // Check if user is an organization user
      final isOrgUser = userDetails['organization_users'] != null && 
                       userDetails['organization_users'].isNotEmpty;
      
      String welcomeMessage = 'Login successful! Welcome ${userDetails['person']['first_name']}!';
      
      if (isOrgUser) {
        final orgUser = userDetails['organization_users'][0];
        final organization = userDetails['organizations'][0];
        welcomeMessage += ' (${orgUser['position']} at ${organization['name']})';
      }
      
      _showSuccessSnackBar(welcomeMessage);
      
      // Store user session data if needed
      await _storeUserSession(userDetails);
      
      // Navigate based on user type
      if (isOrgUser) {
        Navigator.pushReplacementNamed(context, '/organization_dashboard');
      } else {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }

    } catch (e) {
      print('Login error: $e');
      
      String errorMessage = 'Login failed: ';
      
      if (e.toString().contains('Invalid login credentials') || 
          e.toString().contains('Email not confirmed')) {
        errorMessage += 'Invalid username/email or password.';
      } else if (e.toString().contains('Username not found') || 
                 e.toString().contains('Unable to find account')) {
        errorMessage += 'Account not found. Please check your username or email.';
      } else if (e.toString().contains('Too many requests') || 
                 e.toString().contains('429')) {
        errorMessage += 'Too many login attempts. Please wait before trying again.';
      } else if (e.toString().contains('Email not confirmed')) {
        errorMessage += 'Please check your email and verify your account first.';
      } else if (e.toString().contains('AuthException')) {
        errorMessage += 'Authentication error. Please check your credentials.';
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

  Future<Map<String, dynamic>> _getComprehensiveUserDetails(String authUserId) async {
    try {
      // Get Person details
      final personResponse = await Supabase.instance.client
          .from('Person')
          .select('*')
          .eq('id', authUserId)
          .single();

      // Get User details
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('*')
          .eq('person_id', authUserId)
          .maybeSingle();

      if (userResponse == null) {
        // User might only exist in Person table
        return {
          'person': personResponse,
          'user': null,
          'organization_users': [],
          'organizations': [],
        };
      }

      // Get Organization_User details if they exist
      final orgUserResponse = await Supabase.instance.client
          .from('Organization_User')
          .select('*, Organization!organization_id(*)')
          .eq('user_id', userResponse['id']);

      List<Map<String, dynamic>> organizationUsers = [];
      List<Map<String, dynamic>> organizations = [];

      if (orgUserResponse.isNotEmpty) {
        for (var orgUser in orgUserResponse) {
          organizationUsers.add({
            'id': orgUser['id'],
            'position': orgUser['position'],
            'department': orgUser['department'],
            'organization_id': orgUser['organization_id'],
            'user_id': orgUser['user_id'],
            'created_at': orgUser['created_at'],
          });
          
          if (orgUser['Organization'] != null) {
            organizations.add(orgUser['Organization']);
          }
        }
      }

      return {
        'person': personResponse,
        'user': userResponse,
        'organization_users': organizationUsers,
        'organizations': organizations,
      };
    } catch (e) {
      print('Error fetching user details: $e');
      throw Exception('Failed to load user information');
    }
  }

  Future<void> _storeUserSession(Map<String, dynamic> userDetails) async {
    // You can store session data in SharedPreferences or another local storage
    // This is useful for maintaining user context throughout the app
    try {
      // Example: Store essential user info for quick access
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('user_id', userDetails['user']?['id']?.toString() ?? '');
      await prefs.setString('person_id', userDetails['person']['id'].toString());
      await prefs.setString('user_name', userDetails['person']['first_name'] + ' ' + userDetails['person']['last_name']);
      await prefs.setString('user_email', userDetails['person']['email']);
      
      if (userDetails['organization_users'].isNotEmpty) {
        await prefs.setBool('is_organization_user', true);
        await prefs.setString('organization_id', userDetails['organization_users'][0]['organization_id'].toString());
        await prefs.setString('user_position', userDetails['organization_users'][0]['position'] ?? '');
        await prefs.setString('user_department', userDetails['organization_users'][0]['department'] ?? '');
        await prefs.setString('organization_name', userDetails['organizations'][0]['name'] ?? '');
      } else {
        await prefs.setBool('is_organization_user', false);
      }
    } catch (e) {
      print('Error storing session data: $e');
      // Don't throw error here as login was successful
    }
  }

  Future<void> _forgotPassword() async {
    final input = _usernameOrEmailController.text.trim();
    
    if (input.isEmpty) {
      _showErrorSnackBar('Please enter your username or email first.');
      return;
    }

    try {
      String? email;
      
      // Determine if input is email or username
      if (RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(input)) {
        email = input;
      } else {
        // Find email by username
        final userResponse = await Supabase.instance.client
            .from('User')
            .select('person_id')
            .eq('username', input)
            .maybeSingle();

        if (userResponse != null) {
          final personResponse = await Supabase.instance.client
              .from('Person')
              .select('email')
              .eq('id', userResponse['person_id'])
              .single();
          email = personResponse['email'];
        }
      }

      if (email == null) {
        _showErrorSnackBar('Account not found.');
        return;
      }

      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      
      _showSuccessSnackBar('Password reset email sent! Please check your inbox.');
      
    } catch (e) {
      print('Password reset error: $e');
      _showErrorSnackBar('Failed to send password reset email. Please try again.');
    }
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
      appBar: AppBar(
        title: const Text('Employee Login'),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              
              // Welcome Text
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to your employee account',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Login Form Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // Username or Email Field
                      TextFormField(
                        controller: _usernameOrEmailController,
                        decoration: const InputDecoration(
                          labelText: 'Username or Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                          helperText: 'Enter your username or email address',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your username or email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
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
                      const SizedBox(height: 16),

                      // Forgot Password Link
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Login Button
                      ElevatedButton(
                        onPressed: _isLoading ? null : () {
                          // Check cooldown before attempting login
                          if (_lastLoginAttempt != null) {
                            final timeSinceLastAttempt = DateTime.now().difference(_lastLoginAttempt!).inSeconds;
                            if (timeSinceLastAttempt < _loginCooldownSeconds) {
                              final remainingTime = _loginCooldownSeconds - timeSinceLastAttempt;
                              _showErrorSnackBar('Please wait $remainingTime seconds before trying again.');
                              return;
                            }
                          }
                          _login();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Sign Up Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(fontSize: 14),
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
                      'Sign Up',
                      style: TextStyle(
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
    );
  }
}