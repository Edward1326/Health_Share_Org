import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Input Formatters and Validators
class InputFormatters {
  /// Only allow letters, spaces, hyphens, and apostrophes for names
  static final nameFormatter = FilteringTextInputFormatter.allow(
    RegExp(r"[a-zA-ZñÑáéíóúÁÉÍÓÚ\s\-']"),
  );

  /// Only allow numbers, spaces, parentheses, hyphens, and plus sign for phone
  static final phoneFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[0-9\s\-\(\)\+]'),
  );

  /// Only allow alphanumeric, spaces, and common punctuation for organization name
  static final organizationNameFormatter = FilteringTextInputFormatter.allow(
    RegExp(r"[a-zA-Z0-9ñÑáéíóúÁÉÍÓÚ\s\-'.,&()]"),
  );

  /// Only allow alphanumeric and hyphens for license
  static final licenseFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[a-zA-Z0-9\-]'),
  );
}

class InputValidators {
  /// Validate name (no numbers, no special characters except hyphen and apostrophe)
  static String? validateName(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter $fieldName';
    }
    
    final trimmedValue = value.trim();
    
    if (trimmedValue.length < 2) {
      return '$fieldName must be at least 2 characters';
    }
    
    if (RegExp(r'[0-9]').hasMatch(trimmedValue)) {
      return '$fieldName cannot contain numbers';
    }
    
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>+=_\[\]\\\/;`~]').hasMatch(trimmedValue)) {
      return '$fieldName cannot contain special characters';
    }
    
    return null;
  }

  /// Validate Philippine phone number
  static String? validatePhilippinePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter phone number';
    }

    // Remove all non-digit characters
    final cleanNumber = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Check for Philippine mobile formats
    // Format 1: 09XXXXXXXXX (11 digits starting with 09)
    // Format 2: +639XXXXXXXXX (13 characters with +63)
    // Format 3: 639XXXXXXXXX (12 digits starting with 63)
    
    if (cleanNumber.startsWith('+63')) {
      // +639XXXXXXXXX format
      if (cleanNumber.length != 13) {
        return 'Invalid Philippine number format';
      }
      if (!RegExp(r'^\+639[0-9]{9}$').hasMatch(cleanNumber)) {
        return 'Invalid Philippine mobile number';
      }
    } else if (cleanNumber.startsWith('63')) {
      // 639XXXXXXXXX format
      if (cleanNumber.length != 12) {
        return 'Invalid Philippine number format';
      }
      if (!RegExp(r'^639[0-9]{9}$').hasMatch(cleanNumber)) {
        return 'Invalid Philippine mobile number';
      }
    } else if (cleanNumber.startsWith('09')) {
      // 09XXXXXXXXX format
      if (cleanNumber.length != 11) {
        return 'Philippine mobile number must be 11 digits';
      }
      if (!RegExp(r'^09[0-9]{9}$').hasMatch(cleanNumber)) {
        return 'Invalid Philippine mobile number';
      }
    } else {
      return 'Please enter a valid Philippine mobile number (09XX XXX XXXX)';
    }

    return null;
  }

  /// Validate email with strict format
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter email address';
    }

    final email = value.trim().toLowerCase();

    // Must contain exactly one @
    if (email.split('@').length != 2) {
      return 'Email must contain exactly one @';
    }

    // Basic email regex
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      return 'Please enter a valid email address';
    }

    // Check for consecutive dots
    if (email.contains('..')) {
      return 'Email cannot contain consecutive dots';
    }

    // Check if starts or ends with dot
    final parts = email.split('@');
    if (parts[0].startsWith('.') || parts[0].endsWith('.')) {
      return 'Email username cannot start or end with a dot';
    }

    return null;
  }

  /// Validate organization name
  static String? validateOrganizationName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter organization name';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length < 3) {
      return 'Organization name must be at least 3 characters';
    }

    if (trimmedValue.length > 100) {
      return 'Organization name is too long (max 100 characters)';
    }

    return null;
  }

  /// Validate address
  static String? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter address';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length < 10) {
      return 'Please enter a complete address';
    }

    return null;
  }
}

class SignupService {
  static const int _signupCooldownSeconds = 45;
  static DateTime? _lastSignupAttempt;

  static bool canAttemptSignup() {
    if (_lastSignupAttempt == null) return true;
    
    final timeSinceLastAttempt = DateTime.now().difference(_lastSignupAttempt!).inSeconds;
    return timeSinceLastAttempt >= _signupCooldownSeconds;
  }

  static int getRemainingCooldown() {
    if (_lastSignupAttempt == null) return 0;
    
    final timeSinceLastAttempt = DateTime.now().difference(_lastSignupAttempt!).inSeconds;
    final remaining = _signupCooldownSeconds - timeSinceLastAttempt;
    return remaining > 0 ? remaining : 0;
  }

  static void recordSignupAttempt() {
    _lastSignupAttempt = DateTime.now();
  }

  static String? validatePassword(String password) {
    if (password.isEmpty) {
      return 'Please enter a password';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character';
    }
    return null;
  }
}

class OTPService {
  static final _supabase = Supabase.instance.client;
  static const int _otpCooldownSeconds = 60;
  static DateTime? _otpSentTime;
  static String? _pendingEmail;

  static bool canResendOTP() {
    if (_otpSentTime == null) return true;
    
    final timeSinceLastOTP = DateTime.now().difference(_otpSentTime!).inSeconds;
    return timeSinceLastOTP >= _otpCooldownSeconds;
  }

  static int getRemainingOTPCooldownTime() {
    if (_otpSentTime == null) return 0;
    
    final timeSinceLastOTP = DateTime.now().difference(_otpSentTime!).inSeconds;
    final remaining = _otpCooldownSeconds - timeSinceLastOTP;
    return remaining > 0 ? remaining : 0;
  }

  static Future<bool> checkEmailExists(String email) async {
    try {
      final response = await _supabase
          .from('User')
          .select('id')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();
      return response != null;
    } catch (e) {
      print('Error checking email: $e');
      return false;
    }
  }

  static Future<OTPVerificationResult> sendOTPToEmail(String email) async {
    try {
      if (!canResendOTP()) {
        final remainingTime = getRemainingOTPCooldownTime();
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Please wait $remainingTime seconds before resending OTP',
        );
      }

      final emailValidation = InputValidators.validateEmail(email);
      if (emailValidation != null) {
        return OTPVerificationResult(
          success: false,
          errorMessage: emailValidation,
        );
      }

      final emailExists = await checkEmailExists(email);
      if (emailExists) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'An account with this email already exists',
        );
      }

      print('Sending OTP to email: $email');
      
      await _supabase.auth.signInWithOtp(
        email: email.toLowerCase().trim(),
        shouldCreateUser: true,
      );

      _pendingEmail = email.toLowerCase().trim();
      _otpSentTime = DateTime.now();

      return OTPVerificationResult(
        success: true,
        message: 'Verification code sent to your email',
      );
    } on AuthException catch (e) {
      print('OTP send error: ${e.message}');
      
      if (e.message.contains('already registered') || 
          e.message.contains('already exists')) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'An account with this email already exists',
        );
      }
      
      return OTPVerificationResult(
        success: false,
        errorMessage: 'Failed to send verification code: ${e.message}',
      );
    } catch (e) {
      print('OTP send error: $e');
      return OTPVerificationResult(
        success: false,
        errorMessage: 'Failed to send verification code. Please try again.',
      );
    }
  }

  static Future<OTPVerificationResult> verifyOTP(String email, String otp) async {
    try {
      if (_pendingEmail == null || _pendingEmail != email.toLowerCase().trim()) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Please request a new verification code',
        );
      }

      print('Verifying OTP for email: $email');
      
      final response = await _supabase.auth.verifyOTP(
        email: email.toLowerCase().trim(),
        token: otp.trim(),
        type: OtpType.email,
      );

      if (response.session != null && response.user != null) {
        print('OTP verified successfully');
        return OTPVerificationResult(
          success: true,
          message: 'Email verified successfully',
        );
      } else {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Invalid or expired verification code',
        );
      }
    } on AuthException catch (e) {
      print('OTP verification error: ${e.message}');
      
      if (e.message.contains('invalid') || e.message.contains('expired')) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Invalid or expired verification code',
        );
      }
      
      return OTPVerificationResult(
        success: false,
        errorMessage: 'Verification failed: ${e.message}',
      );
    } catch (e) {
      print('OTP verification error: $e');
      return OTPVerificationResult(
        success: false,
        errorMessage: 'Verification failed. Please try again.',
      );
    }
  }
}

class OTPVerificationResult {
  final bool success;
  final String? message;
  final String? errorMessage;

  OTPVerificationResult({
    required this.success,
    this.message,
    this.errorMessage,
  });
}

class CreateOrganizationPage extends StatefulWidget {
  const CreateOrganizationPage({Key? key}) : super(key: key);

  @override
  State<CreateOrganizationPage> createState() => _CreateOrganizationPageState();
}

class _CreateOrganizationPageState extends State<CreateOrganizationPage> {
  static const Color primaryGreen = Color(0xFF6B8E5A);
  static const Color lightGreen = Color(0xFFF5F8F3);
  static const Color darkText = Color(0xFF2C3E50);
  static const Color textGray = Color(0xFF6C757D);
  static const Color borderColor = Color(0xFFD5E1CF);

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
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _sendingOTP = false;

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
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    final emailValidation = InputValidators.validateEmail(_adminEmailController.text);
    if (emailValidation != null) {
      _showErrorSnackBar(emailValidation);
      return;
    }

    setState(() {
      _sendingOTP = true;
    });

    final result = await OTPService.sendOTPToEmail(_adminEmailController.text.trim());

    setState(() {
      _sendingOTP = false;
    });

    if (result.success) {
      setState(() {
        _otpSent = true;
      });
      _showSuccessSnackBar(result.message ?? 'Verification code sent to your email');
    } else {
      _showErrorSnackBar(result.errorMessage ?? 'Failed to send verification code');
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter the verification code');
      return;
    }

    if (_otpController.text.trim().length != 6) {
      _showErrorSnackBar('Verification code must be 6 digits');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await OTPService.verifyOTP(
      _adminEmailController.text.trim(),
      _otpController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      setState(() {
        _otpVerified = true;
      });
      _showSuccessSnackBar('Email verified! You can now complete the registration.');
    } else {
      _showErrorSnackBar(result.errorMessage ?? 'Verification failed');
    }
  }

  Future<void> _createOrganization() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_otpVerified) {
      _showErrorSnackBar('Please verify your email first');
      return;
    }

    if (!SignupService.canAttemptSignup()) {
      final remainingTime = SignupService.getRemainingCooldown();
      _showErrorSnackBar(
          'Please wait $remainingTime seconds before trying again.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    SignupService.recordSignupAttempt();

    try {
      final currentTime = DateTime.now().toIso8601String();

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('Authentication session expired. Please verify email again.');
      }

      print('Setting password for admin user...');
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _adminPasswordController.text),
      );

      final authUserId = currentUser.id;
      print('Auth user ID: $authUserId');

      print('Creating Organization...');
      final organizationResponse = await Supabase.instance.client
          .from('Organization')
          .insert({
            'name': _organizationNameController.text.trim(),
            'organization_license':
                _organizationLicenseController.text.trim().isEmpty
                    ? null
                    : _organizationLicenseController.text.trim().toUpperCase(),
            'created_at': currentTime,
          })
          .select()
          .single();

      final organizationUuid = organizationResponse['id'];
      print('Organization created with ID: $organizationUuid');

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

      print('Creating User record for admin...');
      final userResponse = await Supabase.instance.client
          .from('User')
          .insert({
            'person_id': personUuid,
            'created_at': currentTime,
            'email': _adminEmailController.text.trim().toLowerCase(),
          })
          .select()
          .single();

      final userUuid = userResponse['id'];
      print('User created with numeric ID: $userUuid');

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
          'Organization "${_organizationNameController.text.trim()}" created successfully!');

      if (mounted) {
        Navigator.pop(context, {
          'organization_id': organizationUuid,
          'organization_name': _organizationNameController.text.trim(),
          'admin_email': _adminEmailController.text.trim().toLowerCase(),
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
      return 'Admin password is too weak. Please use a stronger password.';
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
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGreen,
      body: SafeArea(
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
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: primaryGreen.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: lightGreen,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.business_rounded,
                          size: 48,
                          color: primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Create Organization',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set up your medical organization and admin account',
                        style: TextStyle(
                          fontSize: 15,
                          color: textGray,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Organization Details Section
                const Text(
                  'Organization Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 16),

                // Organization Name
                _buildInputField(
                  child: TextFormField(
                    controller: _organizationNameController,
                    inputFormatters: [InputFormatters.organizationNameFormatter],
                    style: const TextStyle(color: darkText, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Organization Name',
                      hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    validator: InputValidators.validateOrganizationName,
                  ),
                  icon: Icons.business_rounded,
                ),

                // Organization License (Optional)
                _buildInputField(
                  child: TextFormField(
                    controller: _organizationLicenseController,
                    inputFormatters: [
                      InputFormatters.licenseFormatter,
                      LengthLimitingTextInputFormatter(50),
                    ],
                    style: const TextStyle(color: darkText, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Organization License (Optional)',
                      hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  icon: Icons.verified_rounded,
                ),

                const SizedBox(height: 24),

                // Admin Account Section
                const Text(
                  'Administrator Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 16),

                // Admin Email with OTP button
                _buildInputField(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _adminEmailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_otpVerified,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')), // No spaces
                            LengthLimitingTextInputFormatter(100),
                          ],
                          style: TextStyle(
                            color: _otpVerified ? textGray : darkText,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Admin Email',
                            hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            suffixIcon: _otpVerified
                                ? Icon(Icons.check_circle, color: primaryGreen, size: 20)
                                : null,
                          ),
                          validator: InputValidators.validateEmail,
                        ),
                      ),
                      if (!_otpVerified)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextButton(
                            onPressed: _sendingOTP ? null : _sendOTP,
                            style: TextButton.styleFrom(
                              foregroundColor: primaryGreen,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: _sendingOTP
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryGreen,
                                    ),
                                  )
                                : Text(
                                    _otpSent ? 'Resend' : 'Send OTP',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                  icon: Icons.email_rounded,
                ),

                // OTP Input Field
                if (_otpSent && !_otpVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: 0),
                    child: Column(
                      children: [
                        _buildInputField(
                          child: TextFormField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: const TextStyle(color: darkText, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Enter 6-digit verification code',
                              hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                          icon: Icons.security_rounded,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _verifyOTP,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Verify Code',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                // Show remaining fields only after OTP is verified
                if (_otpVerified) ...[
                  // Admin First Name
                  _buildInputField(
                    child: TextFormField(
                      controller: _adminFirstNameController,
                      inputFormatters: [
                        InputFormatters.nameFormatter,
                        LengthLimitingTextInputFormatter(50),
                      ],
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: darkText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Admin First Name',
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (value) => InputValidators.validateName(value, 'First name'),
                    ),
                    icon: Icons.person_rounded,
                  ),

                  // Admin Middle Name
                  _buildInputField(
                    child: TextFormField(
                      controller: _adminMiddleNameController,
                      inputFormatters: [
                        InputFormatters.nameFormatter,
                        LengthLimitingTextInputFormatter(50),
                      ],
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: darkText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Admin Middle Name (Optional)',
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                    icon: Icons.person_outline_rounded,
                  ),

                  // Admin Last Name
                  _buildInputField(
                    child: TextFormField(
                      controller: _adminLastNameController,
                      inputFormatters: [
                        InputFormatters.nameFormatter,
                        LengthLimitingTextInputFormatter(50),
                      ],
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: darkText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Admin Last Name',
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: (value) => InputValidators.validateName(value, 'Last name'),
                    ),
                    icon: Icons.person_rounded,
                  ),

                  // Admin Phone Number
                  _buildInputField(
                    child: TextFormField(
                      controller: _adminContactNumberController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        InputFormatters.phoneFormatter,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      style: const TextStyle(color: darkText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Admin Phone Number (09XX XXX XXXX)',
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: InputValidators.validatePhilippinePhone,
                    ),
                    icon: Icons.phone_rounded,
                  ),

                  // Admin Address
                  _buildInputField(
                    child: TextFormField(
                      controller: _adminAddressController,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(200),
                      ],
                      style: const TextStyle(color: darkText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Admin Address',
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      validator: InputValidators.validateAddress,
                    ),
                    icon: Icons.location_on_rounded,
                  ),

                  // Admin Password
                  _buildInputField(
                    child: TextFormField(
                      controller: _adminPasswordController,
                      obscureText: _obscurePassword,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')), // No spaces
                        LengthLimitingTextInputFormatter(100),
                      ],
                      style: const TextStyle(color: darkText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Admin Password',
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: textGray,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) => SignupService.validatePassword(value ?? ''),
                    ),
                    icon: Icons.lock_rounded,
                  ),

                  // Password requirements hint
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 14),
                    child: Text(
                      'Password must contain:\n• At least 8 characters\n• One uppercase letter\n• One number\n• One special character',
                      style: TextStyle(
                        fontSize: 11,
                        color: textGray,
                        height: 1.4,
                      ),
                    ),
                  ),

                  // Confirm Admin Password
                  _buildInputField(
                    child: TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')), // No spaces
                        LengthLimitingTextInputFormatter(100),
                      ],
                      style: const TextStyle(color: darkText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Confirm Admin Password',
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: textGray,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
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
                    icon: Icons.lock_outline_rounded,
                  ),

                  const SizedBox(height: 16),

                  // Create Organization Button
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: primaryGreen,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: primaryGreen.withOpacity(0.3),
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
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Create Organization',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Back Link
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      '← Back to Login',
                      style: TextStyle(
                        color: primaryGreen,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withOpacity(0.05),
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
              color: primaryGreen,
              size: 20,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}