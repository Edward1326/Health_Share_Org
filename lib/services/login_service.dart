import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:health_share_org/services/crypto_utils.dart' as crypto;

class LoginService {
  static const int _loginCooldownSeconds = 5;

  // Rate limiting tracking
  static DateTime? _lastLoginAttempt;

  /// Main login function
  static Future<LoginResult> login({
  required String emailOrUsername,
  required String password,
}) async {
  // Check rate limiting
  if (_lastLoginAttempt != null) {
    final timeSinceLastAttempt =
        DateTime.now().difference(_lastLoginAttempt!).inSeconds;
    if (timeSinceLastAttempt < _loginCooldownSeconds) {
      final remainingTime = _loginCooldownSeconds - timeSinceLastAttempt;
      return LoginResult.failure(
          'Please wait $remainingTime seconds before trying again.');
    }
  }

  _lastLoginAttempt = DateTime.now();

  try {
    final input = emailOrUsername.trim();

    print('DEBUG: Input received: $input');

    String email = input;

    // If input doesn't contain @, it's likely a username
    if (!input.contains('@')) {
      print('DEBUG: Treating input as username, looking up email...');
      throw Exception(
          'Username login not supported. Please use email address.');
    } else {
      print('DEBUG: Treating input as email directly');
    }

    print('DEBUG: Attempting to sign in with email: $email');

    // Use Supabase Auth to sign in
    final authResponse =
        await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    print('DEBUG: Auth response received: ${authResponse.user?.id}');

    if (authResponse.user == null) {
      throw Exception('Login failed');
    }

    final user = authResponse.user!;
    print('Auth user signed in: ${user.id}');

    // Get comprehensive user details after successful authentication
    final userDetails = await _getUserDetailsFromAuth(user);

    // ✅ CRITICAL CHECK: Verify user is an Organization User
    if (userDetails['organization_users'].isEmpty) {
      print('❌ Access denied: User is not an organization member');
      
      // Sign the user out immediately
      await Supabase.instance.client.auth.signOut();
      
      return LoginResult.failure(
        'Access denied. This login is for staff members only. Patients should use the patient portal.',
      );
    }

    print('✅ User verified as organization member');

    // Store user session
    await _storeUserSession(userDetails, user);

    print('Login successful');

    // Determine user position
    String userPosition = '';
    if (userDetails['organization_users'].isNotEmpty) {
      userPosition = userDetails['organization_users'][0]['position']
              ?.toString()
              .toLowerCase() ??
          '';
    }

    return LoginResult.success(
      userDetails: userDetails,
      userPosition: userPosition,
      authUser: user,
    );
  } catch (e) {
    print('Login error: $e');

    String errorMessage = _getErrorMessage(e.toString());
    return LoginResult.failure(errorMessage);
  }
}

  /// Get user details from authenticated user
  static Future<Map<String, dynamic>> _getUserDetailsFromAuth(
      User authUser) async {
    try {
      // Get Person details using auth_user_id
      final personResponse = await Supabase.instance.client
          .from('Person')
          .select('*')
          .eq('auth_user_id', authUser.id)
          .single();

      print('DEBUG: Person found: ${personResponse['id']}');

      // Get User details using person_id
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('*')
          .eq('person_id', personResponse['id'])
          .single();

      print('DEBUG: User found: ${userResponse['id']}');

      // Get Organization_User details using user_id
      final orgUserResponse = await Supabase.instance.client
          .from('Organization_User')
          .select('*, Organization(*)')
          .eq('user_id', userResponse['id']);

      print(
          'DEBUG: Organization_User found: ${orgUserResponse.length} records');

      return {
        'person': personResponse,
        'user': userResponse,
        'organization_users': orgUserResponse,
        'auth_user': {
          'id': authUser.id,
          'email': authUser.email,
          'user_metadata': authUser.userMetadata,
        },
      };
    } catch (e) {
      print('Error getting user details: $e');
      throw Exception('Failed to load user details');
    }
  }

  /// Store user session in SharedPreferences
  static Future<void> _storeUserSession(
      Map<String, dynamic> userDetails, User authUser) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Store auth user info
      await prefs.setString('auth_user_id', authUser.id);
      await prefs.setString('auth_user_email', authUser.email ?? '');

      // Store internal user info
      await prefs.setString(
          'user_id', userDetails['user']['id']?.toString() ?? '');
      await prefs.setString(
          'person_id', userDetails['person']['id']?.toString() ?? '');
      await prefs.setString(
          'username', userDetails['user']['username']?.toString() ?? '');
      await prefs.setString('user_name',
          '${userDetails['person']['first_name'] ?? ''} ${userDetails['person']['last_name'] ?? ''}');
      await prefs.setString(
          'user_email', userDetails['person']['email']?.toString() ?? '');

      if (userDetails['organization_users'].isNotEmpty) {
        await prefs.setBool('is_organization_user', true);
        await prefs.setString(
            'organization_id',
            userDetails['organization_users'][0]['organization_id']
                    ?.toString() ??
                '');
        await prefs.setString('user_position',
            userDetails['organization_users'][0]['position']?.toString() ?? '');
        await prefs.setString(
            'user_department',
            userDetails['organization_users'][0]['department']?.toString() ??
                '');

        // Handle organization name from nested query
        String orgName = '';
        if (userDetails['organization_users'][0]['Organization'] != null) {
          orgName = userDetails['organization_users'][0]['Organization']['name']
                  ?.toString() ??
              '';
        }
        await prefs.setString('organization_name', orgName);
      } else {
        await prefs.setBool('is_organization_user', false);
      }
    } catch (e) {
      print('Error storing session data: $e');
    }
  }

  /// Get appropriate error message for display
  static String _getErrorMessage(String errorString) {
    if (errorString.contains('Username not supported')) {
      return 'Please use your email address to login.';
    } else if (errorString.contains('Invalid login credentials')) {
      return 'Invalid email or password. Please check your credentials.';
    } else if (errorString.contains('Email not confirmed')) {
      return 'Please verify your email address before signing in.';
    } else if (errorString.contains('Too many requests')) {
      return 'Too many login attempts. Please wait before trying again.';
    } else {
      return 'Something went wrong. Please try again.';
    }
  }

  /// Password reset function
  static Future<PasswordResetResult> resetPassword({
    required String emailOrUsername,
    String? redirectTo,
  }) async {
    try {
      String email = emailOrUsername.trim();

      // If input doesn't contain @, it's likely a username - find the email
      if (!email.contains('@')) {
        // Get user by username
        final userResponse = await Supabase.instance.client
            .from('User')
            .select('person_id')
            .eq('username', emailOrUsername)
            .maybeSingle();

        if (userResponse == null) {
          return PasswordResetResult.failure('Username not found.');
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
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo ?? 'your-app-scheme://reset-password',
      );

      return PasswordResetResult.success(email);
    } catch (e) {
      print('Password reset error: $e');
      return PasswordResetResult.failure(
          'Failed to send password reset email. Please try again.');
    }
  }

  /// Check rate limiting for login attempts
  static bool canAttemptLogin() {
    if (_lastLoginAttempt == null) return true;

    final timeSinceLastAttempt =
        DateTime.now().difference(_lastLoginAttempt!).inSeconds;
    return timeSinceLastAttempt >= _loginCooldownSeconds;
  }

  /// Get remaining cooldown time
  static int getRemainingCooldownTime() {
    if (_lastLoginAttempt == null) return 0;

    final timeSinceLastAttempt =
        DateTime.now().difference(_lastLoginAttempt!).inSeconds;
    return (_loginCooldownSeconds - timeSinceLastAttempt)
        .clamp(0, _loginCooldownSeconds);
  }
}

class SignupService {
  static const int _signupCooldownSeconds = 45;
  static DateTime? _lastSignupAttempt;

  /// Validate password strength
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
    return null; // Password is valid
  }

  /// Main signup function
  static Future<SignupResult> signup({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? middleName,
    required String address,
    required String contactNumber,
    required String position,
    required String department,
    required String organizationId,
  }) async {
    // Validate password before proceeding
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      return SignupResult.failure(passwordError);
    }

    // Check rate limiting
    if (_lastSignupAttempt != null) {
      final timeSinceLastAttempt =
          DateTime.now().difference(_lastSignupAttempt!).inSeconds;
      if (timeSinceLastAttempt < _signupCooldownSeconds) {
        final remainingTime = _signupCooldownSeconds - timeSinceLastAttempt;
        return SignupResult.failure(
            'Please wait $remainingTime seconds before trying again.');
      }
    }

    _lastSignupAttempt = DateTime.now();

    try {
      final currentTime = DateTime.now().toIso8601String();

      // Generate RSA Key Pair using CryptoUtils (proper ASN.1 format)
      print('🔐 Generating RSA key pair using CryptoUtils...');

      // Use the crypto prefix to specify which CryptoUtils to use
      final keyData =
          crypto.CryptoUtils.generateRSAKeyPairAsPem(bitLength: 2048);

      final publicKeyPem = keyData['publicKey']!;
      final privateKeyPem = keyData['privateKey']!;

      // Generate fingerprint
      final keyFingerprint = _generateKeyFingerprint(publicKeyPem);

      // Test the keys to make sure they work
      final testResult = crypto.CryptoUtils.testRSAEncryption(bitLength: 2048);
      if (!testResult) {
        throw Exception('Generated RSA keys failed validation test');
      }

      print('✅ RSA keys generated and validated successfully');
      print('🔑 Key fingerprint: $keyFingerprint');

      // Step 1: Create Supabase Auth user FIRST
      print('👤 Creating Auth user...');
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'role': 'employee',
          'key_fingerprint': keyFingerprint, // Store fingerprint in metadata
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create authentication account');
      }

      final authUserId = authResponse.user!.id;
      print('✅ Auth user created with ID: $authUserId');

      // Step 2: Create Person record
      print('👥 Creating Person record...');
      final personResponse = await Supabase.instance.client
          .from('Person')
          .insert({
            'first_name': firstName.trim(),
            'middle_name':
                middleName?.trim().isEmpty == true ? null : middleName?.trim(),
            'last_name': lastName.trim(),
            'address': address.trim(),
            'contact_number': contactNumber.trim(),
            'auth_user_id': authUserId,
            'created_at': currentTime,
          })
          .select()
          .single();

      final personUuid = personResponse['id'];
      print('✅ Person created with UUID: $personUuid');

      // Step 3: Create User record with RSA keys
      print('🔐 Creating User record with RSA keys...');
      final userResponse = await Supabase.instance.client
          .from('User')
          .insert({
            'email': email.trim(),
            'person_id': personUuid,
            'created_at': currentTime,
            'rsa_private_key': privateKeyPem, // Store private key securely
            'rsa_public_key': publicKeyPem, // Store public key
            'key_created_at': currentTime,
          })
          .select()
          .single();

      final userUuid = userResponse['id'];
      print('✅ User created with UUID: $userUuid');

      // Step 4: Create Organization_User record
      print('🏢 Creating Organization_User record...');
      await Supabase.instance.client.from('Organization_User').insert({
        'position': position.trim(),
        'department': department.trim(),
        'created_at': currentTime,
        'organization_id': organizationId,
        'user_id': userUuid,
      });

      print('✅ Organization_User created successfully');

      // Step 5: Optionally store key metadata in RSA_Keys table
      print('🔑 Creating RSA key metadata record...');
      try {
        await Supabase.instance.client.from('RSA_Keys').insert({
          'person_id': personUuid,
          'key_fingerprint': keyFingerprint,
          'rsa_public_key': publicKeyPem,
          'rsa_private_key':
              privateKeyPem, // Consider if you need this here too
          'key_size': 2048,
          'algorithm': 'RSA',
          'created_at': currentTime,
          'is_active': true,
        });
        print('✅ RSA key metadata record created successfully');
      } catch (e) {
        print('⚠️ RSA_Keys table might not exist or have different schema: $e');
        // Continue without failing if RSA_Keys table doesn't exist
      }

      return SignupResult.success(
        message:
            '🎉 Employee account created successfully with RSA keys! Please check your email to verify your account before signing in.',
        authUserId: authUserId,
        personId: personUuid,
        userId: userUuid,
        keyFingerprint: keyFingerprint,
      );
    } catch (e) {
      print('❌ Signup error: $e');
      print('Error type: ${e.runtimeType}');

      String errorMessage = _getSignupErrorMessage(e);
      return SignupResult.failure(errorMessage);
    }
  }

  /// Load organizations for dropdown
  static Future<List<Map<String, dynamic>>> loadOrganizations() async {
    try {
      final response = await Supabase.instance.client
          .from('Organization')
          .select('id, name')
          .order('name');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Failed to load organizations: $e');
      throw Exception('Failed to load organizations: $e');
    }
  }

  /// Generate key fingerprint helper
  static String _generateKeyFingerprint(String publicKeyPem) {
    final keyBytes = utf8.encode(publicKeyPem);
    final digest = sha256.convert(keyBytes);
    return digest.toString().substring(0, 16); // First 16 chars of SHA256
  }

  /// Get appropriate error message for signup
  static String _getSignupErrorMessage(dynamic error) {
    String errorString = error.toString().toLowerCase();

    if (errorString.contains('duplicate key')) {
      if (errorString.contains('email') ||
          errorString.contains('users_email_key')) {
        return 'An account with this email already exists.';
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
      return 'Password is too weak. Please use a stronger password with at least 8 characters, one uppercase letter, one number, and one special character.';
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

  /// Check rate limiting for signup attempts
  static bool canAttemptSignup() {
    if (_lastSignupAttempt == null) return true;

    final timeSinceLastAttempt =
        DateTime.now().difference(_lastSignupAttempt!).inSeconds;
    return timeSinceLastAttempt >= _signupCooldownSeconds;
  }

  /// Get remaining cooldown time for signup
  static int getRemainingSignupCooldownTime() {
    if (_lastSignupAttempt == null) return 0;

    final timeSinceLastAttempt =
        DateTime.now().difference(_lastSignupAttempt!).inSeconds;
    return (_signupCooldownSeconds - timeSinceLastAttempt)
        .clamp(0, _signupCooldownSeconds);
  }
}

/// Result classes for better error handling
class LoginResult {
  final bool success;
  final String? errorMessage;
  final Map<String, dynamic>? userDetails;
  final String? userPosition;
  final User? authUser;

  LoginResult._({
    required this.success,
    this.errorMessage,
    this.userDetails,
    this.userPosition,
    this.authUser,
  });

  factory LoginResult.success({
    required Map<String, dynamic> userDetails,
    required String userPosition,
    required User authUser,
  }) {
    return LoginResult._(
      success: true,
      userDetails: userDetails,
      userPosition: userPosition,
      authUser: authUser,
    );
  }

  factory LoginResult.failure(String errorMessage) {
    return LoginResult._(
      success: false,
      errorMessage: errorMessage,
    );
  }
}

class SignupResult {
  final bool success;
  final String? errorMessage;
  final String? message;
  final String? authUserId;
  final String? personId;
  final String? userId;
  final String? keyFingerprint;

  SignupResult._({
    required this.success,
    this.errorMessage,
    this.message,
    this.authUserId,
    this.personId,
    this.userId,
    this.keyFingerprint,
  });

  factory SignupResult.success({
    required String message,
    required String authUserId,
    required String personId,
    required String userId,
    required String keyFingerprint,
  }) {
    return SignupResult._(
      success: true,
      message: message,
      authUserId: authUserId,
      personId: personId,
      userId: userId,
      keyFingerprint: keyFingerprint,
    );
  }

  factory SignupResult.failure(String errorMessage) {
    return SignupResult._(
      success: false,
      errorMessage: errorMessage,
    );
  }
}

class PasswordResetResult {
  final bool success;
  final String? errorMessage;
  final String? email;

  PasswordResetResult._({
    required this.success,
    this.errorMessage,
    this.email,
  });

  factory PasswordResetResult.success(String email) {
    return PasswordResetResult._(
      success: true,
      email: email,
    );
  }

  factory PasswordResetResult.failure(String errorMessage) {
    return PasswordResetResult._(
      success: false,
      errorMessage: errorMessage,
    );
  }
}