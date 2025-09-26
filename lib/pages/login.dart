import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/signup.dart';
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
    // Get screen size for responsive design
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: isSmallScreen 
          ? _buildMobileLayout() // Mobile layout (stacked)
          : _buildDesktopLayout(), // Desktop layout (side by side)
      ),
    );
  }

  // Mobile layout - stacked vertically
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Left illustration section (top on mobile)
          Container(
            height: 300,
            child: _buildIllustrationSection(),
          ),
          
          // Right login form section (bottom on mobile)
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildLoginFormSection(),
          ),
        ],
      ),
    );
  }

  // Desktop layout - side by side
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left side - Illustration with green background and decorative elements
        Expanded(
          flex: 3,
          child: _buildIllustrationSection(),
        ),
        
        // Right side - Login form
        Expanded(
          flex: 2,
          child: Container(
            color: const Color(0xFFF8F9FA),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildLoginFormSection(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Left illustration section with green background
  Widget _buildIllustrationSection() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6B8E5A), // Dark green
            Color(0xFF8FAD7A), // Medium green  
            Color(0xFFA3C28F), // Light green
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background decorative elements
          _buildBackgroundDecorations(),
          
          // Main illustration content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Doctor illustration
                _buildDoctorIllustration(),
                
                const SizedBox(height: 40),
                
                // Main heading
                const Text(
                  'Turn your ideas into reality.',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // Subheading
                const Text(
                  'Start for free and get attractive offers from the community',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Background decorative elements (circles and shapes)
  Widget _buildBackgroundDecorations() {
    return Stack(
      children: [
        // Top left large circle (red-orange)
        Positioned(
          top: -50,
          left: -100,
          child: Container(
            width: 200,
            height: 200,
            decoration: const BoxDecoration(
              color: Color(0xFFE74C3C),
              shape: BoxShape.circle,
            ),
          ),
        ),
        
        // Top right circle (pink)
        Positioned(
          top: 80,
          right: -30,
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFE8A5C7),
              shape: BoxShape.circle,
            ),
          ),
        ),
        
        // Bottom right large circle (pink)
        Positioned(
          bottom: -80,
          right: -120,
          child: Container(
            width: 250,
            height: 250,
            decoration: const BoxDecoration(
              color: Color(0xFFE8A5C7),
              shape: BoxShape.circle,
            ),
          ),
        ),
        
        // Bottom left circle (darker pink)
        Positioned(
          bottom: 60,
          left: -20,
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFFD48FA8),
              shape: BoxShape.circle,
            ),
          ),
        ),
        
        // Small floating elements
        Positioned(
          top: 120,
          left: 80,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFE8A5C7),
              shape: BoxShape.circle,
            ),
          ),
        ),
        
        // Diagonal lines/dashes
        Positioned(
          top: 100,
          left: 200,
          child: Transform.rotate(
            angle: 0.5,
            child: Container(
              width: 30,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        
        Positioned(
          top: 200,
          right: 150,
          child: Transform.rotate(
            angle: -0.5,
            child: Container(
              width: 25,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        
        Positioned(
          bottom: 150,
          left: 100,
          child: Transform.rotate(
            angle: 1.0,
            child: Container(
              width: 35,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Doctor illustration with speech bubbles
  Widget _buildDoctorIllustration() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Left speech bubble with dots
        Positioned(
          left: 20,
          top: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
              ],
            ),
          ),
        ),
        
        // Right speech bubble with dots
        Positioned(
          right: 20,
          top: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
                SizedBox(width: 4),
                CircleAvatar(radius: 3, backgroundColor: Color(0xFF95A5A6)),
              ],
            ),
          ),
        ),
        
        // Main doctor figure
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Doctor's head
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFDDBEA9), // Skin tone
                shape: BoxShape.circle,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Doctor's coat
            Container(
              width: 100,
              height: 120,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(50),
                  topRight: Radius.circular(50),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Stack(
                children: [
                  // Stethoscope
                  Positioned(
                    top: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3498DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Doctor's legs/pants
            Container(
              width: 80,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFF2C3E50),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
            ),
            
            // Shadow
            Container(
              width: 120,
              height: 20,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(60),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Right login form section
  Widget _buildLoginFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo/Icon section
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFF6B8E5A),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Login to your Account heading
        const Center(
          child: Text(
            'Login to your Account',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Subtext
        const Center(
          child: Text(
            'See what is going on with your business',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6C757D),
            ),
          ),
        ),
        
        const SizedBox(height: 40),
        
        // Login Form
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Email label
              const Text(
                'Email',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2C3E50),
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Email/Username Field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFE1E5E9),
                    width: 1,
                  ),
                ),
                child: TextFormField(
                  controller: _emailOrUsernameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter your email address',
                    hintStyle: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    return null;
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Password label and forgot password link
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Password',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  TextButton(
                    onPressed: _forgotPassword,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Color(0xFF6B8E5A),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Password Field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFE1E5E9),
                    width: 1,
                  ),
                ),
                child: TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    hintStyle: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF6C757D),
                        size: 20,
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

              const SizedBox(height: 24),

              // Remember Me checkbox
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B8E5A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Remember Me',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6C757D),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Login Button
              SizedBox(
                width: double.infinity,
                height: 50,
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 32),

              // Sign Up Link
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Not Registered Yet? ',
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
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Create an account',
                        style: TextStyle(
                          color: Color(0xFF6B8E5A),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}