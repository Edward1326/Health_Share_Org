import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({Key? key}) : super(key: key);

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _positionController = TextEditingController();
  final _departmentController = TextEditingController();
  
  String? _selectedOrganizationId;
  List<Map<String, dynamic>> _organizations = [];
  bool _isLoading = false;
  bool _isLoadingOrgs = true;
  DateTime? _lastSignupAttempt;
  static const int _signupCooldownSeconds = 45;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _contactNumberController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizations() async {
    try {
      final response = await Supabase.instance.client
          .from('Organization')
          .select('id, name')
          .order('name');
      
      setState(() {
        _organizations = List<Map<String, dynamic>>.from(response);
        _isLoadingOrgs = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingOrgs = false;
      });
      _showErrorSnackBar('Failed to load organizations: $e');
    }
  }

Future<void> _signup() async {
  if (!_formKey.currentState!.validate()) return;
  if (_selectedOrganizationId == null) {
    _showErrorSnackBar('Please select an organization');
    return;
  }

  // Check rate limiting
  if (_lastSignupAttempt != null) {
    final timeSinceLastAttempt = DateTime.now().difference(_lastSignupAttempt!).inSeconds;
    if (timeSinceLastAttempt < _signupCooldownSeconds) {
      final remainingTime = _signupCooldownSeconds - timeSinceLastAttempt;
      _showErrorSnackBar('Please wait $remainingTime seconds before trying again.');
      return;
    }
  }

  setState(() {
    _isLoading = true;
  });

  _lastSignupAttempt = DateTime.now();

  try {
    // Step 1: Create user account with Supabase Auth
    final authResponse = await Supabase.instance.client.auth.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      emailRedirectTo: null,
    );

    if (authResponse.user == null) {
      throw Exception('Failed to create user account');
    }

    final authUserId = authResponse.user!.id; // This is the UUID from Supabase Auth
    final currentTime = DateTime.now().toIso8601String();

    // Step 2: Create Person record (let database auto-generate the ID)
    final personResponse = await Supabase.instance.client.from('Person').insert({
      // Don't include 'id' - let it auto-generate
      'first_name': _firstNameController.text.trim(),
      'middle_name': _middleNameController.text.trim().isEmpty 
          ? null 
          : _middleNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'address': _addressController.text.trim(),
      'contact_number': _contactNumberController.text.trim(),
      'email': _emailController.text.trim(),
      'created_at': currentTime,
    }).select().single();

    final personId = personResponse['id']; // Get the auto-generated Person ID
    print('Person created with ID: $personId');

    // Step 3: Create User record (let database auto-generate the ID)
    final userResponse = await Supabase.instance.client.from('User').insert({
      // Don't include 'id' - let it auto-generate
      'username': _usernameController.text.trim(),
      'password': null, // Let Supabase Auth handle password
      'person_id': personId, // Use the auto-generated Person ID
      'created_at': currentTime,
      'connected_organization_id': int.parse(_selectedOrganizationId!),
    }).select().single();

    final userId = userResponse['id']; // Get the auto-generated User ID
    print('User created with ID: $userId');

    // Step 4: Create Organization_User record
    await Supabase.instance.client.from('Organization_User').insert({
      'position': _positionController.text.trim(),
      'department': _departmentController.text.trim(),
      'created_at': currentTime,
      'organization_id': int.parse(_selectedOrganizationId!),
      'user_id': userId, // Use the auto-generated User ID
    });

    print('Organization_User created successfully');

    _showSuccessSnackBar('Employee account created successfully! Please check your email to verify your account.');
    
    // Navigate back or to login page after successful signup
    Navigator.pop(context);

  } catch (e) {
    print('Signup error: $e');
    print('Error type: ${e.runtimeType}');
    
    // Handle specific Supabase errors
    String errorMessage = 'Signup failed: ';
    
    if (e.toString().contains('duplicate key')) {
      if (e.toString().contains('email')) {
        errorMessage += 'An account with this email already exists.';
      } else if (e.toString().contains('username')) {
        errorMessage += 'This username is already taken. Please choose another.';
      } else {
        errorMessage += 'An account with this information already exists.';
      }
    } else if (e.toString().contains('foreign key') || e.toString().contains('violates foreign key constraint')) {
      errorMessage += 'Invalid organization selected or database constraint violation.';
    } else if (e.toString().contains('invalid input syntax')) {
      errorMessage += 'Invalid data format. Please check your input.';
    } else if (e.toString().contains('For security purposes') || e.toString().contains('429')) {
      errorMessage += 'Too many signup attempts. Please wait a moment before trying again.';
    } else if (e.toString().contains('AuthException')) {
      errorMessage += 'Authentication error. Please check your email and password.';
    } else if (e.toString().contains('invalid UUID')) {
      errorMessage += 'System error with user ID generation. Please try again.';
    } else if (e.toString().contains('400')) {
      errorMessage += 'Bad request. Please check all required fields are filled correctly.';
    } else {
      errorMessage += e.toString();
    }
    
    _showErrorSnackBar(errorMessage);
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}

Future<void> _debugSignup() async {
  if (!_formKey.currentState!.validate()) return;
  if (_selectedOrganizationId == null) {
    _showErrorSnackBar('Please select an organization');
    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    print('=== Starting signup process ===');
    
    // Step 1: Create user account with Supabase Auth
    print('Step 1: Creating auth user...');
    final authResponse = await Supabase.instance.client.auth.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      emailRedirectTo: null,
    );

    if (authResponse.user == null) {
      throw Exception('Failed to create user account');
    }

    final userId = authResponse.user!.id;
    final currentTime = DateTime.now().toIso8601String();
    print('Auth user created with ID: $userId');

    // Step 2: Create Person record
    print('Step 2: Creating Person record...');
    try {
      final personResponse = await Supabase.instance.client.from('Person').insert({
        'id': userId,
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim().isEmpty 
            ? null 
            : _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'address': _addressController.text.trim(),
        'contact_number': _contactNumberController.text.trim(),
        'email': _emailController.text.trim(),
        'created_at': currentTime,
      }).select();
      print('Person created successfully: $personResponse');
    } catch (e) {
      print('ERROR in Person creation: $e');
      throw Exception('Failed to create Person record: $e');
    }

    // Step 3: Create User record (test different approaches)
    print('Step 3: Creating User record...');
    try {
      // First, let's try without the 'id' field
      final userResponse = await Supabase.instance.client.from('User').insert({
        'username': _usernameController.text.trim(),
        'password': null,
        'person_id': userId,
        'created_at': currentTime,
        'connected_organization_id': int.parse(_selectedOrganizationId!),
      }).select().single();
      
      print('User created successfully: $userResponse');
      final numericUserId = userResponse['id'];
      print('Numeric user ID: $numericUserId');
      
      // Step 4: Create Organization_User record
      print('Step 4: Creating Organization_User record...');
      try {
        final orgUserResponse = await Supabase.instance.client.from('Organization_User').insert({
          'position': _positionController.text.trim(),
          'department': _departmentController.text.trim(),
          'created_at': currentTime,
          'organization_id': int.parse(_selectedOrganizationId!),
          'user_id': numericUserId,
        }).select();
        
        print('Organization_User created successfully: $orgUserResponse');
        
      } catch (e) {
        print('ERROR in Organization_User creation: $e');
        throw Exception('Failed to create Organization_User record: $e');
      }
      
    } catch (e) {
      print('ERROR in User creation: $e');
      throw Exception('Failed to create User record: $e');
    }

    _showSuccessSnackBar('Employee account created successfully! Please check your email to verify your account.');
    Navigator.pop(context);

  } catch (e) {
    print('=== FINAL ERROR ===');
    print('Error: $e');
    print('Error type: ${e.runtimeType}');
    
    String errorMessage = 'Signup failed: ';
    if (e.toString().contains('PostgrestException')) {
      if (e.toString().contains('invalid input syntax for type bigint')) {
        errorMessage += 'Database column type mismatch. Please contact support.';
      } else {
        errorMessage += e.toString();
      }
    } else {
      errorMessage += e.toString();
    }
    
    _showErrorSnackBar(errorMessage);
  } finally {
    setState(() {
      _isLoading = false;
    });
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
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        elevation: 0,
      ),
      body: _isLoadingOrgs
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Employee Registration',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Text(
                      'Create your employee account',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Organization Selection
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Organization',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedOrganizationId,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Select your organization',
                                prefixIcon: Icon(Icons.business),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select an organization';
                                }
                                return null;
                              },
                              items: _organizations.map((org) {
                                return DropdownMenuItem<String>(
                                  value: org['id'].toString(),
                                  child: Text(org['name']),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedOrganizationId = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Personal Information
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Personal Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _firstNameController,
                              decoration: const InputDecoration(
                                labelText: 'First Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your first name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _middleNameController,
                              decoration: const InputDecoration(
                                labelText: 'Middle Name (Optional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Last Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your last name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.home),
                              ),
                              maxLines: 2,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _contactNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Contact Number',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.phone),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your contact number';
                                }
                                // Basic phone number validation
                                if (!RegExp(r'^[\+]?[0-9]{10,15}$').hasMatch(value.replaceAll(RegExp(r'[\s\-\(\)]'), ''))) {
                                  return 'Please enter a valid contact number';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Work Information
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Work Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _positionController,
                              decoration: const InputDecoration(
                                labelText: 'Position/Job Title',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.work),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your position';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _departmentController,
                              decoration: const InputDecoration(
                                labelText: 'Department',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.group_work),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your department';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Account Credentials
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Employee Credentials',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.account_circle),
                                helperText: 'Choose a unique username for login',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a username';
                                }
                                if (value.trim().length < 3) {
                                  return 'Username must be at least 3 characters long';
                                }
                                if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                                  return 'Username can only contain letters, numbers, and underscores';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email Address',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email),
                                helperText: 'Used for account verification and notifications',
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your email';
                                }
                                if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(value)) {
                                  return 'Please enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lock),
                                helperText: 'Minimum 6 characters',
                              ),
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a password';
                                }
                                if (value.length < 6) {
                                  return 'Password must be at least 6 characters long';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              decoration: const InputDecoration(
                                labelText: 'Confirm Password',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please confirm your password';
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Sign Up Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : () {
                        // Check if we're still in cooldown
                        if (_lastSignupAttempt != null) {
                          final timeSinceLastAttempt = DateTime.now().difference(_lastSignupAttempt!).inSeconds;
                          if (timeSinceLastAttempt < _signupCooldownSeconds) {
                            final remainingTime = _signupCooldownSeconds - timeSinceLastAttempt;
                            _showErrorSnackBar('Please wait $remainingTime seconds before trying again.');
                            return;
                          }
                        }
                        _signup();
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
                              'Create Employee Account',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Login Link
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Already have an account? Sign In',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}