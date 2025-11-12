import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup.dart';
import '../pages/admin/admin_dashboard.dart';
import '../pages/staff/staff_dashboard.dart';
import '../pages/reset_password.dart';
import 'login_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _isCheckingAuth = true; // Add this to show loading while checking

  @override
  void initState() {
    super.initState();
    _checkExistingAuth(); // Check if user is already logged in
    _setupAuthListener();
  }

  // Check if user is already authenticated
  Future<void> _checkExistingAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      final userId = prefs.getString('userId');
      final userPosition = prefs.getString('userPosition');
      final organizationId = prefs.getString('organizationId');

      // Also check Supabase session
      final session = Supabase.instance.client.auth.currentSession;

      if (isLoggedIn &&
          userId != null &&
          userPosition != null &&
          organizationId != null &&
          session != null) {
        // User is already logged in, navigate to appropriate dashboard
        if (mounted) {
          if (userPosition == 'administrator') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const Dashboard(),
                settings: RouteSettings(
                  arguments: {
                    'organizationId': organizationId,
                    'userId': userId,
                  },
                ),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffDashboard(),
                settings: RouteSettings(
                  arguments: {
                    'organizationId': organizationId,
                    'userId': userId,
                  },
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error checking auth: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingAuth = false;
        });
      }
    }
  }

  void _setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
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
      } else if (event == AuthChangeEvent.signedOut) {
        // Clear stored data when user signs out
        _clearLoginState();
      }
    });
  }

  // Save login state to SharedPreferences
  Future<void> _saveLoginState(
      String userId, String userPosition, String organizationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    await prefs.setString('userPosition', userPosition);
    await prefs.setString('organizationId', organizationId);
    await prefs.setBool('isLoggedIn', true);
  }

  // Clear login state from SharedPreferences
  Future<void> _clearLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userPosition');
    await prefs.remove('organizationId');
    await prefs.remove('isLoggedIn');
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
        // Get organization ID directly from the login result
        String? organizationId;

        if (result.userDetails != null &&
            result.userDetails!['organization_users'] != null &&
            result.userDetails!['organization_users'].isNotEmpty) {
          organizationId = result.userDetails!['organization_users'][0]
              ['organization_id'] as String?;
        }

        if (organizationId == null) {
          _showErrorSnackBar(
              'Failed to fetch organization data. Please try again.');
          await Supabase.instance.client.auth.signOut();
          return;
        }

        // Get user ID from Supabase session or userDetails
        final session = Supabase.instance.client.auth.currentSession;
        String? userId = session?.user.id;

        // Fallback: try to get from userDetails if session doesn't have it
        if (userId == null && result.userDetails != null) {
          userId = result.userDetails!['id'] as String?;
        }

        // If still null, show error
        if (userId == null) {
          _showErrorSnackBar(
              'Failed to get user information. Please try again.');
          await Supabase.instance.client.auth.signOut();
          return;
        }

        final userPosition = result.userPosition ?? '';

        // Save login state to SharedPreferences
        await _saveLoginState(userId, userPosition, organizationId);

        print('✅ Login successful for organization: $organizationId');
        print('✅ User ID: $userId');
        print('✅ User Position: $userPosition');

        // Navigate based on user position
        if (mounted) {
          if (result.userPosition == 'administrator') {
            // Navigate to admin dashboard and pass organization ID
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const Dashboard(),
                settings: RouteSettings(
                  arguments: {
                    'organizationId': organizationId,
                    'userDetails': result.userDetails,
                  },
                ),
              ),
            );
          } else {
            // Navigate to staff dashboard
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffDashboard(),
                settings: RouteSettings(
                  arguments: {
                    'organizationId': organizationId,
                    'userDetails': result.userDetails,
                  },
                ),
              ),
            );
          }
        }
      } else {
        _showErrorSnackBar(result.errorMessage ?? 'Login failed');
      }
    } catch (e) {
      print('Login error: $e');
      _showErrorSnackBar('An error occurred during login. Please try again.');
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Row(
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF6B8E5A),
            ),
            const SizedBox(width: 20),
            const Text('Sending reset email...'),
          ],
        ),
      ),
    );

    try {
      final result = await LoginService.resetPassword(
        emailOrUsername: input,
        redirectTo: 'your-app-scheme://reset-password',
      );

      Navigator.of(context).pop(); // Close loading dialog

      if (result.success) {
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
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B8E5A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_rounded,
                  color: Color(0xFF6B8E5A),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Check Your Email',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle
              const Text(
                'We\'ve sent a password reset link to',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6C757D),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Email
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  email,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),

              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFE1E5E9),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInstructionItem(
                      '1',
                      'Check your email inbox and spam folder',
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionItem(
                      '2',
                      'Click the password reset link',
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionItem(
                      '3',
                      'Create a new password for your account',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(
                          color: Color(0xFFE1E5E9),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Got it',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6C757D),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ResetPasswordPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B8E5A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Reset Now',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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

  Widget _buildInstructionItem(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF6B8E5A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF495057),
              height: 1.5,
            ),
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    // Show loading screen while checking authentication
    if (_isCheckingAuth) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6B8E5A),
          ),
        ),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: isSmallScreen ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 300,
            child: _buildIllustrationSection(),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildLoginFormSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _buildIllustrationSection(),
        ),
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

  Widget _buildIllustrationSection() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6B8E5A),
            Color(0xFF8FAD7A),
            Color(0xFFA3C28F),
          ],
        ),
      ),
      child: Stack(
        children: [
          _buildBackgroundDecorations(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHealthShareLogo(),
                const SizedBox(height: 40),
                const Text(
                  'Welcome to HealthShare',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your comprehensive healthcare management solution',
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

  Widget _buildBackgroundDecorations() {
    return Stack(
      children: [
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

  Widget _buildHealthShareLogo() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/healthshare_logo.png',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildLoginFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
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
            child: Image.asset(
              'assets/images/healthshare_logo.png',
              width: 60,
              height: 60,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 32),
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
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Email',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (!LoginService.canAttemptLogin()) {
                            final remainingTime =
                                LoginService.getRemainingCooldownTime();
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

// Custom painter for HealthShare logo
class HealthShareLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(size.width / 2, size.height / 2);

    final innerGap = size.width * 0.08;
    final armExtension = size.width * 0.38;

    paint.color = const Color(0xFF17A2B8);

    final leftBottomPath = Path();
    leftBottomPath.moveTo(center.dx - innerGap, center.dy - armExtension);
    leftBottomPath.lineTo(center.dx - innerGap, center.dy - innerGap);
    leftBottomPath.lineTo(center.dx - armExtension, center.dy - innerGap);

    canvas.drawPath(leftBottomPath, paint);

    paint.color = const Color(0xFF9E9E9E);

    final rightTopPath = Path();
    rightTopPath.moveTo(center.dx + innerGap, center.dy + armExtension);
    rightTopPath.lineTo(center.dx + innerGap, center.dy + innerGap);
    rightTopPath.lineTo(center.dx + armExtension, center.dy + innerGap);

    canvas.drawPath(rightTopPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
