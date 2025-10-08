import 'package:flutter/material.dart';
import 'package:health_share_org/services/signup_service.dart'; 

class SignupTheme {
  static const Color primaryGreen = Color(0xFF4A8B3A);
  static const Color lightGreen = Color(0xFF6BA85A);
  static const Color textGray = Color(0xFF6C757D);
  static const Color darkGray = Color(0xFF495057);
  static const Color lightGray = Color(0xFFF5F5F5);
}

class SignupPage extends StatefulWidget {
  const SignupPage({Key? key}) : super(key: key);

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _positionController = TextEditingController();
  final _departmentController = TextEditingController();
  final _otpController = TextEditingController();

  String? _selectedOrganizationId;
  List<Map<String, dynamic>> _organizations = [];
  bool _isLoading = false;
  bool _isLoadingOrgs = true;
  String _loadingStatus = '';
  
  // OTP verification state
  bool _isEmailVerified = false;
  bool _isVerifyingOTP = false;
  bool _isSendingOTP = false;
  bool _showOTPField = false;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _contactNumberController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizations() async {
    try {
      final organizations = await SignupService.loadOrganizations();
      setState(() {
        _organizations = organizations;
        _isLoadingOrgs = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingOrgs = false;
      });
      _showErrorSnackBar('Failed to load organizations: $e');
    }
  }

  Future<void> _sendOTP() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      _showErrorSnackBar('Please enter your email address');
      return;
    }

    if (!SignupService.isValidEmail(email)) {
      _showErrorSnackBar('Please enter a valid email address');
      return;
    }

    if (!SignupService.canResendOTP()) {
      final remainingTime = SignupService.getRemainingOTPCooldownTime();
      _showErrorSnackBar('Please wait $remainingTime seconds before resending');
      return;
    }

    setState(() {
      _isSendingOTP = true;
    });

    try {
      final result = await SignupService.sendOTPToEmail(email);
      
      if (result.success) {
        setState(() {
          _showOTPField = true;
        });
        _showSuccessSnackBar(result.message ?? 'Verification code sent!');
      } else {
        _showErrorSnackBar(result.errorMessage ?? 'Failed to send verification code');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to send verification code: $e');
    } finally {
      setState(() {
        _isSendingOTP = false;
      });
    }
  }

  Future<void> _verifyOTP() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final password = _passwordController.text;
    
    if (otp.isEmpty) {
      _showErrorSnackBar('Please enter the verification code');
      return;
    }

    if (password.isEmpty) {
      _showErrorSnackBar('Please enter a password first');
      return;
    }

    if (!SignupService.isValidPassword(password)) {
      _showErrorSnackBar('Password must be 8+ chars with uppercase, lowercase, and numbers');
      return;
    }

    if (password != _confirmPasswordController.text) {
      _showErrorSnackBar('Passwords do not match');
      return;
    }

    setState(() {
      _isVerifyingOTP = true;
    });

    try {
      final result = await SignupService.verifyOTP(email, otp, password);
      
      if (result.success) {
        setState(() {
          _isEmailVerified = true;
        });
        _showSuccessSnackBar('Email verified and password set! You can now complete registration.');
      } else {
        _showErrorSnackBar(result.errorMessage ?? 'Verification failed');
      }
    } catch (e) {
      _showErrorSnackBar('Verification failed: $e');
    } finally {
      setState(() {
        _isVerifyingOTP = false;
      });
    }
  }

  // THIS IS THE MISSING _signup METHOD
  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Please fill in all required fields correctly');
      return;
    }

    if (!_isEmailVerified) {
      _showErrorSnackBar('Please verify your email before signing up');
      return;
    }

    if (!SignupService.canAttemptSignup()) {
      final remainingTime = SignupService.getRemainingSignupCooldownTime();
      _showErrorSnackBar('Please wait $remainingTime seconds before trying again');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingStatus = 'Creating your account...';
    });

    try {
      final result = await SignupService.signup(
        email: _emailController.text.trim(),
        password: _passwordController.text, // Not used for setting, just validation
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        address: _addressController.text.trim(),
        contactNumber: _contactNumberController.text.trim(),
        position: _positionController.text.trim(),
        department: _departmentController.text.trim(),
        organizationId: _selectedOrganizationId!,
        emailVerified: _isEmailVerified,
      );

      if (!mounted) return;

      if (result.success) {
        _showSuccessSnackBar(result.message ?? 'Account created successfully!');
        
        // Navigate to login after short delay
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        _showErrorSnackBar(result.errorMessage ?? 'Failed to create account');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('An error occurred: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingStatus = '';
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red[600],
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: SignupTheme.primaryGreen,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SignupTheme.lightGray,
      body: _isLoadingOrgs
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: SignupTheme.primaryGreen),
                  SizedBox(height: 16),
                  Text(
                    'Loading organizations...',
                    style: TextStyle(color: SignupTheme.textGray, fontSize: 16),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(32),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: SignupTheme.primaryGreen.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.enhanced_encryption,
                                size: 48,
                                color: SignupTheme.primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Create Account',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: SignupTheme.darkGray,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Join your organization with secure encryption',
                              style: TextStyle(fontSize: 15, color: SignupTheme.textGray),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: SignupTheme.primaryGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'RSA-2048 Encryption',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: SignupTheme.primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Email Verification Section
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: _isEmailVerified 
                              ? SignupTheme.primaryGreen.withOpacity(0.1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isEmailVerified 
                                ? SignupTheme.primaryGreen 
                                : Colors.grey.shade200,
                            width: _isEmailVerified ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _isEmailVerified ? Icons.check_circle : Icons.email,
                                  color: _isEmailVerified 
                                      ? SignupTheme.primaryGreen 
                                      : SignupTheme.textGray,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _isEmailVerified 
                                        ? 'Email Verified ✓' 
                                        : 'Step 1: Verify Your Email',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _isEmailVerified 
                                          ? SignupTheme.primaryGreen 
                                          : SignupTheme.darkGray,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!_isEmailVerified) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      enabled: !_isEmailVerified,
                                      decoration: InputDecoration(
                                        hintText: 'Enter your email',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                      validator: (value) {
                                        if (value?.trim().isEmpty ?? true) {
                                          return 'Please enter your email';
                                        }
                                        if (!SignupService.isValidEmail(value!)) {
                                          return 'Please enter a valid email';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: _isSendingOTP ? null : _sendOTP,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: SignupTheme.primaryGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: _isSendingOTP
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.white),
                                            ),
                                          )
                                        : const Text('Send Code'),
                                  ),
                                ],
                              ),
                              if (_showOTPField) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _otpController,
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: 'Enter 6-digit code',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: _isVerifyingOTP ? null : _verifyOTP,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: SignupTheme.primaryGreen,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: _isVerifyingOTP
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<Color>(
                                                        Colors.white),
                                              ),
                                            )
                                          : const Text('Verify'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),

                      // Organization Selection
                      _buildInputField(
                        child: DropdownButtonFormField<String>(
                          value: _selectedOrganizationId,
                          decoration: const InputDecoration(
                            hintText: 'Select your organization',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select an organization';
                            }
                            return null;
                          },
                          items: _organizations.map((org) {
                            return DropdownMenuItem<String>(
                              value: org['id'],
                              child: Text(org['name']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedOrganizationId = value;
                            });
                          },
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: SignupTheme.textGray),
                        ),
                        icon: Icons.business,
                      ),

                      // Name fields
                      _buildInputField(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(
                            hintText: 'First Name',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your first name'
                              : null,
                        ),
                        icon: Icons.person,
                      ),

                      _buildInputField(
                        child: TextFormField(
                          controller: _middleNameController,
                          decoration: const InputDecoration(
                            hintText: 'Middle Name (Optional)',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                        icon: Icons.person_outline,
                      ),

                      _buildInputField(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(
                            hintText: 'Last Name',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your last name'
                              : null,
                        ),
                        icon: Icons.person,
                      ),

                      // Contact info
                      _buildInputField(
                        child: TextFormField(
                          controller: _contactNumberController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            hintText: 'Phone Number',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) {
                            if (value?.trim().isEmpty ?? true) {
                              return 'Please enter your contact number';
                            }
                            if (!SignupService.isValidPhoneNumber(value!)) {
                              return 'Please enter a valid contact number';
                            }
                            return null;
                          },
                        ),
                        icon: Icons.phone,
                      ),

                      _buildInputField(
                        child: TextFormField(
                          controller: _addressController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Address',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your address'
                              : null,
                        ),
                        icon: Icons.location_on,
                      ),

                      _buildInputField(
                        child: TextFormField(
                          controller: _positionController,
                          decoration: const InputDecoration(
                            hintText: 'Position/Job Title',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your position'
                              : null,
                        ),
                        icon: Icons.work,
                      ),

                      _buildInputField(
                        child: TextFormField(
                          controller: _departmentController,
                          decoration: const InputDecoration(
                            hintText: 'Department',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your department'
                              : null,
                        ),
                        icon: Icons.group_work,
                      ),

                      // Password fields
                      _buildInputField(
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            hintText: 'Password',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
                              return 'Please enter a password';
                            }
                            if (!SignupService.isValidPassword(value!)) {
                              return 'Password must be 8+ chars with uppercase, lowercase, and numbers';
                            }
                            return null;
                          },
                        ),
                        icon: Icons.lock,
                      ),

                      _buildInputField(
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            hintText: 'Confirm Password',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
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
                        icon: Icons.lock_outline,
                      ),

                      const SizedBox(height: 24),

                      // Sign Up Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_isLoading || !_isEmailVerified) ? null : _signup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SignupTheme.primaryGreen,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Text(
                                  _isEmailVerified 
                                      ? 'Create Account' 
                                      : 'Verify Email First',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Security Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: SignupTheme.primaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: SignupTheme.primaryGreen.withOpacity(0.2),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.security,
                              color: SignupTheme.primaryGreen,
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your account will be secured with RSA-2048 encryption keys generated during signup.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: SignupTheme.darkGray,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Login Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Already have an account? ',
                            style: TextStyle(
                              color: SignupTheme.textGray,
                              fontSize: 15,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              'Login',
                              style: TextStyle(
                                color: SignupTheme.primaryGreen,
                                fontSize: 15,
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Icon(
              icon,
              color: SignupTheme.textGray,
              size: 20,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}