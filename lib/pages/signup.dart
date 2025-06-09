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
      final timeSinceLastAttempt =
          DateTime.now().difference(_lastSignupAttempt!).inSeconds;
      if (timeSinceLastAttempt < _signupCooldownSeconds) {
        final remainingTime = _signupCooldownSeconds - timeSinceLastAttempt;
        _showErrorSnackBar(
            'Please wait $remainingTime seconds before trying again.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    _lastSignupAttempt = DateTime.now();

    try {
      final currentTime = DateTime.now().toIso8601String();

      // Step 1: Create Supabase Auth user FIRST
      print('Creating Auth user...');
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {
          'username': _usernameController.text.trim(),
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'role': 'employee',
          // We'll update these after creating the database records
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create authentication account');
      }

      final authUserId = authResponse.user!.id;
      print('Auth user created with ID: $authUserId');

      // Step 2: Create Person record
      print('Creating Person record...');
      final personResponse = await Supabase.instance.client
          .from('Person')
          .insert({
            'first_name': _firstNameController.text.trim(),
            'middle_name': _middleNameController.text.trim().isEmpty
                ? null
                : _middleNameController.text.trim(),
            'last_name': _lastNameController.text.trim(),
            'address': _addressController.text.trim(),
            'contact_number': _contactNumberController.text.trim(),
            'email': _emailController.text.trim(),
            'auth_user_id': authUserId, // Link to Auth user
            'created_at': currentTime,
          })
          .select()
          .single();

      final numericPersonId = personResponse['id'];
      print('Person created with numeric ID: $numericPersonId');

      // Step 3: Create User record
      print('Creating User record...');
      final userResponse = await Supabase.instance.client
          .from('User')
          .insert({
            'username': _usernameController.text.trim(),
            'person_id': numericPersonId,
            'created_at': currentTime,
            'connected_organization_id': int.parse(_selectedOrganizationId!),
          })
          .select()
          .single();

      final numericUserId = userResponse['id'];
      print('User created with numeric ID: $numericUserId');

      // Step 4: The metadata was already set during signUp, so we're good
      // The user will need to verify their email before they can sign in
      print('Auth user metadata already set during signup');

      // Step 5: Create Organization_User record
      print('Creating Organization_User record...');
      await Supabase.instance.client.from('Organization_User').insert({
        'position': _positionController.text.trim(),
        'department': _departmentController.text.trim(),
        'created_at': currentTime,
        'organization_id': int.parse(_selectedOrganizationId!),
        'user_id': numericUserId,
      });

      print('Organization_User created successfully');

      _showSuccessSnackBar(
          'Employee account created successfully! Please check your email to verify your account before signing in.');

      // Navigate back to login page
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Signup error: $e');
      print('Error type: ${e.runtimeType}');

      // If we get here and created an Auth user, we should clean it up
      // Note: In production, you might want more sophisticated cleanup

      String errorMessage = _getErrorMessage(e);
      _showErrorSnackBar(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    String errorString = error.toString().toLowerCase();

    if (errorString.contains('duplicate key')) {
      if (errorString.contains('email') ||
          errorString.contains('users_email_key')) {
        return 'An account with this email already exists.';
      } else if (errorString.contains('username')) {
        return 'This username is already taken. Please choose another.';
      } else {
        return 'An account with this information already exists.';
      }
    } else if (errorString.contains('foreign key') ||
        errorString.contains('violates foreign key constraint')) {
      return 'Invalid organization selected. Please try again.';
    } else if (errorString.contains('invalid input syntax')) {
      return 'Invalid data format. Please check your input.';
    } else if (errorString.contains('rate limit') ||
        errorString.contains('429') ||
        errorString.contains('too many')) {
      return 'Too many signup attempts. Please wait a moment before trying again.';
    } else if (errorString.contains('weak password') ||
        errorString.contains('password')) {
      return 'Password is too weak. Please use a stronger password with at least 6 characters.';
    } else if (errorString.contains('invalid email') ||
        errorString.contains('email')) {
      return 'Invalid email address. Please check your email and try again.';
    } else if (errorString.contains('network') ||
        errorString.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    } else {
      return 'Signup failed. Please check your information and try again.';
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Registration'),
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
                      'Create Your Account',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Join your organization\'s hospital management system',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Organization Selection
                    _buildSectionCard(
                      title: 'Organization',
                      icon: Icons.business,
                      children: [
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

                    // Personal Information
                    _buildSectionCard(
                      title: 'Personal Information',
                      icon: Icons.person,
                      children: [
                        _buildTextField(
                          controller: _firstNameController,
                          label: 'First Name',
                          icon: Icons.person,
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your first name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _middleNameController,
                          label: 'Middle Name (Optional)',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _lastNameController,
                          label: 'Last Name',
                          icon: Icons.person,
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your last name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _addressController,
                          label: 'Address',
                          icon: Icons.home,
                          maxLines: 2,
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your address'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _contactNumberController,
                          label: 'Contact Number',
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value?.trim().isEmpty ?? true) {
                              return 'Please enter your contact number';
                            }
                            final cleanNumber =
                                value!.replaceAll(RegExp(r'[\s\-\(\)]'), '');
                            if (!RegExp(r'^[\+]?[0-9]{10,15}$')
                                .hasMatch(cleanNumber)) {
                              return 'Please enter a valid contact number';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),

                    // Work Information
                    _buildSectionCard(
                      title: 'Work Information',
                      icon: Icons.work,
                      children: [
                        _buildTextField(
                          controller: _positionController,
                          label: 'Position/Job Title',
                          icon: Icons.work,
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your position'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _departmentController,
                          label: 'Department',
                          icon: Icons.group_work,
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your department'
                              : null,
                        ),
                      ],
                    ),

                    // Account Credentials
                    _buildSectionCard(
                      title: 'Account Credentials',
                      icon: Icons.security,
                      children: [
                        _buildTextField(
                          controller: _usernameController,
                          label: 'Username',
                          icon: Icons.account_circle,
                          helperText: 'Choose a unique username for login',
                          validator: (value) {
                            if (value?.trim().isEmpty ?? true) {
                              return 'Please enter a username';
                            }
                            if (value!.trim().length < 3) {
                              return 'Username must be at least 3 characters long';
                            }
                            if (!RegExp(r'^[a-zA-Z0-9_]+$')
                                .hasMatch(value.trim())) {
                              return 'Username can only contain letters, numbers, and underscores';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email Address',
                          icon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                          helperText:
                              'Used for account verification and notifications',
                          validator: (value) {
                            if (value?.trim().isEmpty ?? true) {
                              return 'Please enter your email';
                            }
                            if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$')
                                .hasMatch(value!)) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock,
                          obscureText: true,
                          helperText: 'Minimum 6 characters',
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
                              return 'Please enter a password';
                            }
                            if (value!.length < 6) {
                              return 'Password must be at least 6 characters long';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _confirmPasswordController,
                          label: 'Confirm Password',
                          icon: Icons.lock_outline,
                          obscureText: true,
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
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

                    const SizedBox(height: 32),

                    // Sign Up Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _signup,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
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
                      onPressed: () => Navigator.pop(context),
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

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    int maxLines = 1,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        helperText: helperText,
      ),
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      validator: validator,
    );
  }
}
