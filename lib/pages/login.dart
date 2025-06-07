import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin/admin_dashboard.dart';

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
  static const int _loginCooldownSeconds = 30;

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
    final input = _emailOrUsernameController.text.trim();
    final password = _passwordController.text;
    
    print('DEBUG: Input received: $input'); // DEBUG LINE
    
    String email = input;
    
    // If input doesn't contain @, it's likely a username - we need to find the email
    if (!input.contains('@')) {
      print('DEBUG: Treating input as username, looking up email...'); // DEBUG LINE
      
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
    final authResponse = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    print('DEBUG: Auth response received: ${authResponse.user?.id}'); // DEBUG LINE

    if (authResponse.user == null) {
      throw Exception('Login failed');
    }

    final user = authResponse.user!;
    print('Auth user signed in: ${user.id}');

    // ... rest of your existing code
    
  } catch (e) {
    print('Login error: $e');
    
    String errorMessage = 'Login failed: ';
    
    if (e.toString().contains('Username not found')) {
      errorMessage += 'Username not found. Please check your username.';
    } else if (e.toString().contains('Invalid login credentials') || 
               e.toString().contains('Email not confirmed')) {
      errorMessage += 'Invalid email or password. Please check your credentials.';
    } else if (e.toString().contains('Email not confirmed')) {
      errorMessage += 'Please verify your email address before signing in.';
    } else if (e.toString().contains('Too many requests')) {
      errorMessage += 'Too many login attempts. Please wait before trying again.';
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

      return await _getComprehensiveUserDetails(personId.toString(), userId.toString());
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
        personResponse['id'].toString(), 
        userResponse['id'].toString()
      );
    } catch (e) {
      print('Error getting user details by email: $e');
      throw Exception('Failed to load user information');
    }
  }

  Future<Map<String, dynamic>> _getComprehensiveUserDetails(String personId, String userId) async {
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

  Future<void> _storeUserSession(Map<String, dynamic> userDetails, User authUser) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Store auth user info
      await prefs.setString('auth_user_id', authUser.id);
      await prefs.setString('auth_user_email', authUser.email ?? '');
      
      // Store internal user info
      await prefs.setString('user_id', userDetails['user']['id']?.toString() ?? '');
      await prefs.setString('person_id', userDetails['person']['id']?.toString() ?? '');
      await prefs.setString('username', userDetails['user']['username']?.toString() ?? '');
      await prefs.setString('user_name', '${userDetails['person']['first_name'] ?? ''} ${userDetails['person']['last_name'] ?? ''}');
      await prefs.setString('user_email', userDetails['person']['email']?.toString() ?? '');
      
      if (userDetails['organization_users'].isNotEmpty) {
        await prefs.setBool('is_organization_user', true);
        await prefs.setString('organization_id', userDetails['organization_users'][0]['organization_id']?.toString() ?? '');
        await prefs.setString('user_position', userDetails['organization_users'][0]['position']?.toString() ?? '');
        await prefs.setString('user_department', userDetails['organization_users'][0]['department']?.toString() ?? '');
        await prefs.setString('organization_name', userDetails['organizations'][0]['name']?.toString() ?? '');
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
      
      // Send reset email using Supabase Auth
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      
      _showSuccessSnackBar('Password reset email sent to $email!');
      
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
                      // Email or Username Field
                      TextFormField(
                        controller: _emailOrUsernameController,
                        decoration: const InputDecoration(
                          labelText: 'Email or Username',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                          helperText: 'Enter your email address or username',
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