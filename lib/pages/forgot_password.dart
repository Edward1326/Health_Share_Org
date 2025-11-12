import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _isLoading = false;
  bool _isResending = false;
  bool _isObscured1 = true;
  bool _isObscured2 = true;
  bool _otpSent = false;
  String _userEmail = '';

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (_emailController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your email address');
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
        .hasMatch(_emailController.text.trim())) {
      _showErrorSnackBar('Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _supabase.auth.signInWithOtp(
        email: _emailController.text.trim(),
        emailRedirectTo: null,
      );

      if (mounted) {
        setState(() {
          _otpSent = true;
          _userEmail = _emailController.text.trim();
        });
        _showSuccessSnackBar('Verification code sent to your email');
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showErrorSnackBar(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
            'Failed to send verification code. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyAndResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Verify OTP and sign in
      final response = await _supabase.auth.verifyOTP(
        email: _userEmail,
        token: _otpController.text.trim(),
        type: OtpType.email,
      );

      if (response.session == null) {
        throw Exception('Invalid or expired verification code');
      }

      // Update password
      await _supabase.auth.updateUser(
        UserAttributes(
          password: _newPasswordController.text,
        ),
      );

      if (mounted) {
        _showSuccessDialog();
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showErrorSnackBar(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
          'Failed to reset password. Please check your code and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendOTP() async {
    setState(() {
      _isResending = true;
    });

    try {
      await _supabase.auth.signInWithOtp(
        email: _userEmail,
        emailRedirectTo: null,
      );

      if (mounted) {
        _showSuccessSnackBar('New verification code sent');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to resend code. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF6B8E5A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6B8E5A).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Color(0xFF6B8E5A),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Success!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your password has been reset successfully. You can now login with your new password.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6C757D),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B8E5A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(_otpSent ? 'Reset Password' : 'Forgot Password'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2C3E50),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_otpSent) {
              setState(() {
                _otpSent = false;
                _otpController.clear();
                _newPasswordController.clear();
                _confirmPasswordController.clear();
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(32.0),
              child: _otpSent ? _buildResetPasswordForm() : _buildEmailForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF6B8E5A).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline,
              size: 40,
              color: Color(0xFF6B8E5A),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Title
        const Text(
          'Forgot Password?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        // Subtitle
        const Text(
          'Enter your email address and we\'ll send you a verification code',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6C757D),
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 32),

        // Email Label
        const Text(
          'Email Address',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2C3E50),
          ),
        ),

        const SizedBox(height: 8),

        // Email Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFE1E5E9),
              width: 1,
            ),
          ),
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'Enter your email',
              hintStyle: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.email_outlined,
                color: Color(0xFF6C757D),
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Send Code Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendOTP,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B8E5A),
              foregroundColor: Colors.white,
              elevation: 0,
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
                    'Send Verification Code',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 24),

        // Back to Login
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Back to Login',
              style: TextStyle(
                color: Color(0xFF6B8E5A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResetPasswordForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF6B8E5A).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user,
                size: 40,
                color: Color(0xFF6B8E5A),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Title
          const Text(
            'Reset Your Password',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Subtitle
          Text(
            'Enter the code sent to $_userEmail',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6C757D),
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // OTP Code Label
          const Text(
            'Verification Code',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2C3E50),
            ),
          ),

          const SizedBox(height: 8),

          // OTP Code Field
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFE1E5E9),
                width: 1,
              ),
            ),
            child: TextFormField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                hintText: 'Enter 6-digit code',
                hintStyle: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.pin,
                  color: Color(0xFF6C757D),
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter the verification code';
                }
                if (value.length != 6) {
                  return 'Code must be 6 digits';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 16),

          // Resend Code
          Center(
            child: TextButton(
              onPressed: _isResending ? null : _resendOTP,
              child: _isResending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF6B8E5A),
                        ),
                      ),
                    )
                  : const Text(
                      'Didn\'t receive code? Resend',
                      style: TextStyle(
                        color: Color(0xFF6B8E5A),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 24),

          // Divider
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0xFFE1E5E9))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Set New Password',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6C757D),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Color(0xFFE1E5E9))),
            ],
          ),

          const SizedBox(height: 24),

          // New Password Label
          const Text(
            'New Password',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2C3E50),
            ),
          ),

          const SizedBox(height: 8),

          // New Password Field
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFE1E5E9),
                width: 1,
              ),
            ),
            child: TextFormField(
              controller: _newPasswordController,
              obscureText: _isObscured1,
              decoration: InputDecoration(
                hintText: 'Enter your new password',
                hintStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscured1
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF6C757D),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isObscured1 = !_isObscured1;
                    });
                  },
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a new password';
                }
                if (value.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                if (!value.contains(RegExp(r'[A-Z]'))) {
                  return 'Must contain at least one uppercase letter';
                }
                if (!value.contains(RegExp(r'[0-9]'))) {
                  return 'Must contain at least one number';
                }
                if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
                  return 'Must contain at least one special character';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 20),

          // Confirm Password Label
          const Text(
            'Confirm New Password',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2C3E50),
            ),
          ),

          const SizedBox(height: 8),

          // Confirm Password Field
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFE1E5E9),
                width: 1,
              ),
            ),
            child: TextFormField(
              controller: _confirmPasswordController,
              obscureText: _isObscured2,
              decoration: InputDecoration(
                hintText: 'Re-enter your new password',
                hintStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscured2
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF6C757D),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isObscured2 = !_isObscured2;
                    });
                  },
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _newPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 32),

          // Reset Password Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyAndResetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B8E5A),
                foregroundColor: Colors.white,
                elevation: 0,
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
                      'Reset Password',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
