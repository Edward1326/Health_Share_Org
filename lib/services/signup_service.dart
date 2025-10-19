// Add to pubspec.yaml:
// dependencies:
//   webcrypto: ^0.5.3

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:webcrypto/webcrypto.dart';
// Import crypto ONLY for sha256, with prefix to avoid conflicts
import 'package:crypto/crypto.dart' as crypto;

class SignupResult {
  final bool success;
  final String? message;
  final String? errorMessage;
  final String? userId;

  SignupResult({
    required this.success,
    this.message,
    this.errorMessage,
    this.userId,
  });
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

class SignupService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  
  // Rate limiting
  static DateTime? _lastSignupAttempt;
  static const int _signupCooldownSeconds = 30;
  
  // OTP tracking
  static String? _pendingEmail;
  static DateTime? _otpSentTime;
  static const int _otpResendCooldownSeconds = 60;

  static bool canAttemptSignup() {
    if (_lastSignupAttempt == null) return true;
    final now = DateTime.now();
    final timeSinceLastAttempt = now.difference(_lastSignupAttempt!);
    return timeSinceLastAttempt.inSeconds >= _signupCooldownSeconds;
  }

  static int getRemainingSignupCooldownTime() {
    if (_lastSignupAttempt == null) return 0;
    final now = DateTime.now();
    final timeSinceLastAttempt = now.difference(_lastSignupAttempt!);
    final remaining = _signupCooldownSeconds - timeSinceLastAttempt.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  static bool canResendOTP() {
    if (_otpSentTime == null) return true;
    final now = DateTime.now();
    final timeSinceLastOTP = now.difference(_otpSentTime!);
    return timeSinceLastOTP.inSeconds >= _otpResendCooldownSeconds;
  }

  static int getRemainingOTPCooldownTime() {
    if (_otpSentTime == null) return 0;
    final now = DateTime.now();
    final timeSinceLastOTP = now.difference(_otpSentTime!);
    final remaining = _otpResendCooldownSeconds - timeSinceLastOTP.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  static Future<bool> checkEmailExists(String email) async {
    try {
      final userCheck = await _supabase
          .from('User')
          .select('id')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();
      
      if (userCheck != null) {
        return true;
      }
      
      return false;
    } catch (e) {
      print('Error checking email: $e');
      return false;
    }
  }

  // RSA key generation using Web Crypto API (FAST! ~50-200ms)
  static Future<Map<String, String>> _generateRSAKeyPair() async {
    try {
      print('Generating RSA-2048 keys using Web Crypto API...');
      final stopwatch = Stopwatch()..start();
      
      // Generate RSA-OAEP key pair using native browser crypto
      final keyPair = await RsaOaepPrivateKey.generateKey(
        2048, // modulus length
        BigInt.from(65537), // public exponent
        Hash.sha256,
      );
      
      // Export keys to PKCS#8/SPKI format
      final privateKeyBytes = await keyPair.privateKey.exportPkcs8Key();
      final publicKeyBytes = await keyPair.publicKey.exportSpkiKey();
      
      // Convert to PEM format
      final publicPem = _bytesToPem(publicKeyBytes, 'PUBLIC KEY');
      final privatePem = _bytesToPem(privateKeyBytes, 'PRIVATE KEY');
      
      // Generate fingerprint
      final fingerprint = _generateKeyFingerprint(publicPem);
      
      stopwatch.stop();
      print('RSA-2048 keys generated in ${stopwatch.elapsedMilliseconds}ms!');
      print('Key fingerprint: $fingerprint');
      
      return {
        'publicKey': publicPem,
        'privateKey': privatePem,
        'fingerprint': fingerprint,
      };
    } catch (e) {
      print('Error generating RSA keys: $e');
      rethrow;
    }
  }

  static String _bytesToPem(List<int> bytes, String type) {
    final base64Data = base64Encode(bytes);
    final chunks = <String>[];
    for (int i = 0; i < base64Data.length; i += 64) {
      chunks.add(base64Data.substring(
          i, i + 64 > base64Data.length ? base64Data.length : i + 64));
    }
    return '-----BEGIN $type-----\n${chunks.join('\n')}\n-----END $type-----';
  }

  static String _generateKeyFingerprint(String publicKeyPem) {
    final keyBytes = utf8.encode(publicKeyPem);
    final digest = crypto.sha256.convert(keyBytes);
    return digest.toString().substring(0, 16);
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

      if (!isValidEmail(email)) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Please enter a valid email address',
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
      
      if (e.message.contains('Signups not allowed')) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Email signup is not enabled. Please contact your administrator.',
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

  static Future<OTPVerificationResult> verifyOTP(
    String email, 
    String otp, 
    String password,
  ) async {
    try {
      if (_pendingEmail == null || _pendingEmail != email.toLowerCase().trim()) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Please request a new verification code',
        );
      }

      if (!isValidPassword(password)) {
        return OTPVerificationResult(
          success: false,
          errorMessage: 'Password must be 8+ chars with uppercase, lowercase, and numbers',
        );
      }

      print('Verifying OTP for email: $email');
      
      final response = await _supabase.auth.verifyOTP(
        email: email.toLowerCase().trim(),
        token: otp.trim(),
        type: OtpType.email,
      );

      if (response.session != null && response.user != null) {
        print('OTP verified, auth user created: ${response.user!.id}');
        
        print('Setting password...');
        try {
          final updateResponse = await _supabase.auth.updateUser(
            UserAttributes(password: password),
          );
          
          if (updateResponse.user != null) {
            print('Password set successfully');
            
            return OTPVerificationResult(
              success: true,
              message: 'Email verified and password set successfully',
            );
          } else {
            await _supabase.auth.signOut();
            return OTPVerificationResult(
              success: false,
              errorMessage: 'Failed to set password. Please try again.',
            );
          }
        } catch (e) {
          print('Error setting password: $e');
          try {
            await _supabase.auth.signOut();
          } catch (signOutError) {
            print('Error signing out after password failure: $signOutError');
          }
          return OTPVerificationResult(
            success: false,
            errorMessage: 'Failed to set password: ${e.toString()}',
          );
        }
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
    required bool emailVerified,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    String? authUserId;
    bool shouldCleanupAuth = false;
    
    try {
      if (!emailVerified) {
        return SignupResult(
          success: false,
          errorMessage: 'Please verify your email before signing up',
        );
      }

      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null || currentUser.email?.toLowerCase() != email.toLowerCase().trim()) {
        return SignupResult(
          success: false,
          errorMessage: 'Session expired. Please verify your email again.',
        );
      }

      print('Starting user registration for existing auth user...');
      _lastSignupAttempt = DateTime.now();

      authUserId = currentUser.id;
      shouldCleanupAuth = true; // Mark for cleanup if anything fails
      print('Using authenticated user: $authUserId');

      final orgCheck = await _supabase
          .from('Organization')
          .select('id')
          .eq('id', organizationId)
          .maybeSingle();
      
      if (orgCheck == null) {
        throw Exception('Invalid organization selected');
      }

      // Generate RSA keys using Web Crypto API (SUPER FAST!)
      final keyPair = await _generateRSAKeyPair();
      final publicPem = keyPair['publicKey']!;
      final privatePem = keyPair['privateKey']!;
      final fingerprint = keyPair['fingerprint']!;
      
      print('Keys generated successfully (${stopwatch.elapsedMilliseconds}ms)');

      print('Creating database records...');
      
      String? personId;
      bool userCreated = false;
      bool orgUserCreated = false;
      
      try {
        print('Inserting Person record...');
        final personInsertResponse = await _supabase
            .from('Person')
            .insert({
              'first_name': firstName,
              'middle_name': middleName?.isNotEmpty == true ? middleName : null,
              'last_name': lastName,
              'address': address,
              'contact_number': contactNumber,
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'auth_user_id': authUserId,
            })
            .select('id')
            .single();

        personId = personInsertResponse['id'];
        print('Person record created: $personId');

        print('Inserting User record...');
        await _supabase.from('User').insert({
          'id': authUserId,
          'email': email.toLowerCase().trim(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'rsa_public_key': publicPem,
          'rsa_private_key': privatePem,
          'key_created_at': DateTime.now().toUtc().toIso8601String(),
          'person_id': personId,
        });
        userCreated = true;
        print('User record created successfully');
          
        print('Inserting Organization_User record...');
        await _supabase.from('Organization_User').insert({
          'user_id': authUserId,
          'organization_id': organizationId,
          'position': position,
          'department': department,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        orgUserCreated = true;
        print('Organization_User record created successfully');

      } catch (dbError) {
        print('Database error: $dbError');
        
        // Cleanup database records
        if (orgUserCreated) {
          try {
            await _supabase.from('Organization_User').delete().eq('user_id', authUserId!);
            print('Cleaned up Organization_User');
          } catch (e) {
            print('Failed to clean up Organization_User: $e');
          }
        }
        
        if (userCreated) {
          try {
            await _supabase.from('User').delete().eq('id', authUserId!);
            print('Cleaned up User');
          } catch (e) {
            print('Failed to clean up User: $e');
          }
        }
        
        if (personId != null) {
          try {
            await _supabase.from('Person').delete().eq('id', personId);
            print('Cleaned up Person');
          } catch (e) {
            print('Failed to clean up Person: $e');
          }
        }
        
        rethrow;
      }

      // If we got here, everything succeeded - don't cleanup auth
      shouldCleanupAuth = false;
      _pendingEmail = null;
      _otpSentTime = null;

      stopwatch.stop();
      print('User registration completed in ${stopwatch.elapsedMilliseconds}ms!');

      return SignupResult(
        success: true,
        message: 'Account created successfully with 2048-bit RSA encryption!',
        userId: authUserId,
      );

    } on PostgrestException catch (e) {
      stopwatch.stop();
      print('Database error after ${stopwatch.elapsedMilliseconds}ms: ${e.message}');
      
      // Cleanup auth user if registration failed
      if (shouldCleanupAuth && authUserId != null) {
        await _cleanupAuthUser(authUserId, email);
      }
      
      return SignupResult(
        success: false,
        errorMessage: _getDatabaseErrorMessage(e.message, e.details, e.hint),
      );
    } catch (e) {
      stopwatch.stop();
      print('Registration error after ${stopwatch.elapsedMilliseconds}ms: $e');
      
      // Cleanup auth user if registration failed
      if (shouldCleanupAuth && authUserId != null) {
        await _cleanupAuthUser(authUserId, email);
      }
      
      return SignupResult(
        success: false,
        errorMessage: 'Failed to register user: $e',
      );
    }
  }

  /// Cleanup auth user if registration fails
  static Future<void> _cleanupAuthUser(String authUserId, String email) async {
    print('Registration failed - cleaning up auth user...');
    try {
      // Try to delete using admin API (requires service role or proper permissions)
      // If this fails, we'll fall back to signOut
      try {
        await _supabase.auth.admin.deleteUser(authUserId);
        print('Auth user deleted successfully');
      } catch (adminError) {
        print('Admin delete not available, signing out instead: $adminError');
        // Fallback: Sign out the user (leaves auth record but prevents login without proper data)
        await _supabase.auth.signOut();
        print('User signed out - auth record remains but cannot login without completing registration');
      }
    } catch (cleanupError) {
      print('Failed to cleanup auth user: $cleanupError');
      print('⚠️ WARNING: Orphaned auth user may exist for email: $email');
    }
  }

  static String _getDatabaseErrorMessage(String? message, String? details, String? hint) {
    final fullMessage = message ?? '';
    final fullDetails = details ?? '';
    
    if (fullMessage.contains('unique constraint') || 
        fullMessage.contains('duplicate key') ||
        fullDetails.contains('unique constraint') ||
        fullDetails.contains('duplicate key')) {
      return 'An account with this information already exists';
    } else if (fullMessage.contains('foreign key') ||
               fullDetails.contains('foreign key')) {
      return 'Invalid organization selected';
    } else if (fullMessage.contains('not-null') ||
               fullDetails.contains('not-null') ||
               fullMessage.contains('null value')) {
      return 'Required information is missing';
    } else if (fullMessage.contains('check constraint')) {
      return 'Invalid data format provided';
    } else if (fullMessage.contains('permission denied')) {
      return 'Permission denied - please contact support';
    }
    
    return 'Database error occurred - please try again';
  }

  static List<Map<String, dynamic>>? _cachedOrganizations;
  static DateTime? _organizationsCacheTime;
  static const Duration _cacheTimeout = Duration(minutes: 10);

  static Future<List<Map<String, dynamic>>> loadOrganizations() async {
    if (_cachedOrganizations != null && _organizationsCacheTime != null) {
      final now = DateTime.now();
      if (now.difference(_organizationsCacheTime!) < _cacheTimeout) {
        return _cachedOrganizations!;
      }
    }

    try {
      final response = await _supabase
          .from('Organization')
          .select('id, name')
          .order('name');
      
      final organizations = List<Map<String, dynamic>>.from(response);
      _cachedOrganizations = organizations;
      _organizationsCacheTime = DateTime.now();
      
      return organizations;
    } catch (e) {
      print('Error loading organizations: $e');
      throw Exception('Failed to load organizations: $e');
    }
  }

  static void clearCaches() {
    _cachedOrganizations = null;
    _organizationsCacheTime = null;
    _pendingEmail = null;
    _otpSentTime = null;
  }

  static bool isValidEmail(String email) {
    return RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(email);
  }

  static bool isValidPassword(String password) {
    return password.length >= 8 &&
           RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(password);
  }

  static bool isValidPhoneNumber(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    return RegExp(r'^[\+]?[0-9]{10,15}$').hasMatch(cleanPhone);
  }
}