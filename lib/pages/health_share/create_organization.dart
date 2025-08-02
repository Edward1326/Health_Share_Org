import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateOrganizationPage extends StatefulWidget {
  const CreateOrganizationPage({Key? key}) : super(key: key);

  @override
  State<CreateOrganizationPage> createState() => _CreateOrganizationPageState();
}

class _CreateOrganizationPageState extends State<CreateOrganizationPage> {
  final _formKey = GlobalKey<FormState>();
  final _organizationNameController = TextEditingController();
  final _organizationDescriptionController = TextEditingController();
  final _organizationLicenseController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminFirstNameController = TextEditingController();
  final _adminMiddleNameController = TextEditingController();
  final _adminLastNameController = TextEditingController();
  final _adminAddressController = TextEditingController();
  final _adminContactNumberController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  DateTime? _lastCreationAttempt;
  static const int _creationCooldownSeconds = 10;

  @override
  void dispose() {
    _organizationNameController.dispose();
    _organizationDescriptionController.dispose();
    _organizationLicenseController.dispose();
    _adminEmailController.dispose();
    _adminFirstNameController.dispose();
    _adminMiddleNameController.dispose();
    _adminLastNameController.dispose();
    _adminAddressController.dispose();
    _adminContactNumberController.dispose();
    _adminPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createOrganization() async {
    if (!_formKey.currentState!.validate()) return;

    // Check rate limiting
    if (_lastCreationAttempt != null) {
      final timeSinceLastAttempt =
          DateTime.now().difference(_lastCreationAttempt!).inSeconds;
      if (timeSinceLastAttempt < _creationCooldownSeconds) {
        final remainingTime = _creationCooldownSeconds - timeSinceLastAttempt;
        _showErrorSnackBar(
            'Please wait $remainingTime seconds before trying again.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    _lastCreationAttempt = DateTime.now();

    try {
      final currentTime = DateTime.now().toIso8601String();

      // Step 1: Create the Organization
      print('Creating Organization...');
      final organizationResponse = await Supabase.instance.client
          .from('Organization')
          .insert({
            'name': _organizationNameController.text.trim(),
            'organization_license':
                _organizationLicenseController.text.trim().isEmpty
                    ? null
                    : _organizationLicenseController.text.trim(),
            'created_at': currentTime,
          })
          .select()
          .single();

      final organizationUuid = organizationResponse['id'];
      print('Organization created with ID: $organizationUuid');

      // Step 2: Create Supabase Auth user for admin
      print('Creating Auth user for admin...');
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: _adminEmailController.text.trim(),
        password: _adminPasswordController.text,
        data: {
          'first_name': _adminFirstNameController.text.trim(),
          'last_name': _adminLastNameController.text.trim(),
          'role': 'admin',
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create authentication account for admin');
      }

      final authUserId = authResponse.user!.id;
      print('Auth user created with ID: $authUserId');

      // Step 3: Create Person record for admin
      print('Creating Person record for admin...');
      final personResponse = await Supabase.instance.client
          .from('Person')
          .insert({
            'first_name': _adminFirstNameController.text.trim(),
            'middle_name': _adminMiddleNameController.text.trim().isEmpty
                ? null
                : _adminMiddleNameController.text.trim(),
            'last_name': _adminLastNameController.text.trim(),
            'address': _adminAddressController.text.trim(),
            'contact_number': _adminContactNumberController.text.trim(),
            'auth_user_id': authUserId,
            'created_at': currentTime,
          })
          .select()
          .single();

      final personUuid = personResponse['id'];
      print('Person created with UUID: $personUuid');

      // Step 4: Create User record for admin
      print('Creating User record for admin...');
      final userResponse = await Supabase.instance.client
          .from('User')
          .insert({
            'person_id': personUuid,
            'created_at': currentTime,
            'email': _adminEmailController.text.trim(),
          })
          .select()
          .single();

      final userUuid = userResponse['id'];
      print('User created with numeric ID: $userUuid');

      // Step 5: Create Organization_User record with admin position
      print('Creating Organization_User record for admin...');
      await Supabase.instance.client.from('Organization_User').insert({
        'position': 'Administrator',
        'department': 'Administration',
        'created_at': currentTime,
        'organization_id': organizationUuid,
        'user_id': userUuid,
      });

      print('Organization_User created successfully with admin privileges');

      _showSuccessSnackBar(
          'Organization "${_organizationNameController.text.trim()}" created successfully! Admin account has been set up. Please check the admin email to verify the account.');

      // Navigate back or to a success page
      if (mounted) {
        Navigator.pop(context, {
          'organization_id': organizationUuid,
          'organization_name': _organizationNameController.text.trim(),
          'admin_email': _adminEmailController.text.trim(),
        });
      }
    } catch (e) {
      print('Organization creation error: $e');
      print('Error type: ${e.runtimeType}');

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
      if (errorString.contains('organization') &&
          errorString.contains('name')) {
        return 'An organization with this name already exists.';
      } else if (errorString.contains('email') ||
          errorString.contains('users_email_key')) {
        return 'An account with this admin email already exists.';
      } else if (errorString.contains('username')) {
        return 'This admin username is already taken. Please choose another.';
      } else {
        return 'An organization or account with this information already exists.';
      }
    } else if (errorString.contains('invalid input syntax')) {
      return 'Invalid data format. Please check your input.';
    } else if (errorString.contains('rate limit') ||
        errorString.contains('429') ||
        errorString.contains('too many')) {
      return 'Too many creation attempts. Please wait a moment before trying again.';
    } else if (errorString.contains('weak password') ||
        errorString.contains('password')) {
      return 'Admin password is too weak. Please use a stronger password with at least 6 characters.';
    } else if (errorString.contains('invalid email') ||
        errorString.contains('email')) {
      return 'Invalid admin email address. Please check the email and try again.';
    } else if (errorString.contains('network') ||
        errorString.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    } else {
      return 'Organization creation failed. Please check your information and try again.';
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
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with illustration
                Container(
                  height: 200,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Background pattern
                      Positioned(
                        top: -20,
                        right: -20,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0891B2).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -30,
                        left: -30,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0891B2).withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      // Content
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0891B2).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.business,
                                size: 40,
                                color: Color(0xFF0891B2),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Create Organization',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Set up your medical organization and admin account',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF64748B),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Organization Details Section
                const Text(
                  'Organization Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),

                // Organization Name
                _buildInputField(
                  child: TextFormField(
                    controller: _organizationNameController,
                    decoration: InputDecoration(
                      hintText: 'Organization Name',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? 'Please enter organization name'
                        : null,
                  ),
                  icon: Icons.business,
                ),

                // Organization License (Optional)
                _buildInputField(
                  child: TextFormField(
                    controller: _organizationLicenseController,
                    decoration: InputDecoration(
                      hintText: 'Organization License (Optional)',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  icon: Icons.verified,
                ),

                const SizedBox(height: 32),

                // Admin Account Section
                const Text(
                  'Administrator Account',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),

                // Admin First Name
                _buildInputField(
                  child: TextFormField(
                    controller: _adminFirstNameController,
                    decoration: InputDecoration(
                      hintText: 'Admin First Name',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? 'Please enter admin first name'
                        : null,
                  ),
                  icon: Icons.person,
                ),

                // Admin Middle Name
                _buildInputField(
                  child: TextFormField(
                    controller: _adminMiddleNameController,
                    decoration: InputDecoration(
                      hintText: 'Admin Middle Name (Optional)',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  icon: Icons.person_outline,
                ),

                // Admin Last Name
                _buildInputField(
                  child: TextFormField(
                    controller: _adminLastNameController,
                    decoration: InputDecoration(
                      hintText: 'Admin Last Name',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? 'Please enter admin last name'
                        : null,
                  ),
                  icon: Icons.person,
                ),

                // Admin Email
                _buildInputField(
                  child: TextFormField(
                    controller: _adminEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Admin Email',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) {
                      if (value?.trim().isEmpty ?? true) {
                        return 'Please enter admin email';
                      }
                      if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$')
                          .hasMatch(value!)) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  icon: Icons.alternate_email,
                ),

                // Admin Phone Number
                _buildInputField(
                  child: TextFormField(
                    controller: _adminContactNumberController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Admin Phone Number',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) {
                      if (value?.trim().isEmpty ?? true) {
                        return 'Please enter admin contact number';
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
                  icon: Icons.phone,
                ),

                // Admin Address
                _buildInputField(
                  child: TextFormField(
                    controller: _adminAddressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Admin Address',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? 'Please enter admin address'
                        : null,
                  ),
                  icon: Icons.location_on,
                ),

                // Admin Password
                _buildInputField(
                  child: TextFormField(
                    controller: _adminPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Admin Password',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Please enter admin password';
                      }
                      if (value!.length < 6) {
                        return 'Password must be at least 6 characters long';
                      }
                      return null;
                    },
                  ),
                  icon: Icons.lock,
                ),

                // Confirm Admin Password
                _buildInputField(
                  child: TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Confirm Admin Password',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Please confirm admin password';
                      }
                      if (value != _adminPasswordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  icon: Icons.lock_outline,
                ),

                const SizedBox(height: 32),

                // Create Organization Button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0891B2), Color(0xFF0E7490)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0891B2).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createOrganization,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Create Organization',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // Back Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        '← Back to Login',
                        style: TextStyle(
                          color: Color(0xFF0891B2),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required Widget child,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Icon(
              icon,
              color: const Color(0xFF0891B2),
              size: 20,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
