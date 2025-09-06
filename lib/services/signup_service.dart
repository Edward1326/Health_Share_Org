import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';

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

class SignupService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  
  // Rate limiting
  static DateTime? _lastSignupAttempt;
  static const int _signupCooldownSeconds = 30;

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

  // RSA key generation using PointyCastle (works on all platforms)
  static Future<Map<String, String>> _generateRSAKeyPair() async {
    try {
      print('Generating RSA-2048 keys using PointyCastle...');
      // Use compute for heavy cryptographic operations
      return await compute(_generateRSAKeyPairSync, null);
    } catch (e) {
      print('Error generating RSA keys: $e');
      rethrow;
    }
  }

  /// RSA generation using PointyCastle (cross-platform)
  static Map<String, String> _generateRSAKeyPairSync(void _) {
    final keyGen = RSAKeyGenerator();
    final secureRandom = FortunaRandom();

    // Enhanced random seeding
    _seedSecureRandom(secureRandom);

    // Generate 2048-bit RSA keys
    keyGen.init(ParametersWithRandom(
      RSAKeyGeneratorParameters(
          BigInt.parse('65537'), // Standard F4 exponent
          2048, // 2048-bit keys - SAME AS AuthService
          12 // Standard certainty for production
          ),
      secureRandom,
    ));

    final keyPair = keyGen.generateKeyPair();
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;

    final publicKeyPem = _rsaPublicKeyToPem(publicKey);
    final privateKeyPem = _rsaPrivateKeyToPem(privateKey);

    return {
      'publicKey': publicKeyPem,
      'privateKey': privateKeyPem,
      'fingerprint': _generateKeyFingerprint(publicKeyPem),
    };
  }

  /// Secure random seeding
  static void _seedSecureRandom(FortunaRandom secureRandom) {
    final seedSource = Random.secure();
    final seed = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      seed[i] = seedSource.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));
    
    // Initialize internal state
    for (int i = 0; i < 100; i++) {
      secureRandom.nextUint8();
    }
  }

  /// Convert RSA public key to PEM format
  static String _rsaPublicKeyToPem(RSAPublicKey publicKey) {
    try {
      final publicKeySeq = ASN1Sequence();
      publicKeySeq.add(ASN1Integer(publicKey.modulus!));
      publicKeySeq.add(ASN1Integer(publicKey.exponent!));

      final algorithmSeq = ASN1Sequence();
      final rsaOid = ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]);
      algorithmSeq.add(rsaOid);
      algorithmSeq.add(ASN1Null());

      final publicKeyBitString = ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

      final topLevelSeq = ASN1Sequence();
      topLevelSeq.add(algorithmSeq);
      topLevelSeq.add(publicKeyBitString);

      final dataBase64 = base64Encode(topLevelSeq.encodedBytes);
      return _formatPem(dataBase64, 'PUBLIC KEY');
    } catch (e) {
      throw Exception('Failed to convert RSA public key to PEM: $e');
    }
  }

  /// Convert RSA private key to PEM format (PKCS#8)
  static String _rsaPrivateKeyToPem(RSAPrivateKey privateKey) {
    try {
      final privateKeySeq = ASN1Sequence()
        ..add(ASN1Integer(BigInt.from(0))) // version
        ..add(ASN1Integer(privateKey.modulus!))
        ..add(ASN1Integer(privateKey.exponent!))
        ..add(ASN1Integer(privateKey.privateExponent!))
        ..add(ASN1Integer(privateKey.p!))
        ..add(ASN1Integer(privateKey.q!))
        ..add(ASN1Integer(privateKey.privateExponent! % (privateKey.p! - BigInt.one)))
        ..add(ASN1Integer(privateKey.privateExponent! % (privateKey.q! - BigInt.one)))
        ..add(ASN1Integer(privateKey.q!.modInverse(privateKey.p!)));

      final algorithmSeq = ASN1Sequence();
      final rsaOid = ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]);
      algorithmSeq.add(rsaOid);
      algorithmSeq.add(ASN1Null());

      final privateKeyOctetString = ASN1OctetString(
        Uint8List.fromList(privateKeySeq.encodedBytes),
      );

      final topLevelSeq = ASN1Sequence()
        ..add(ASN1Integer(BigInt.from(0))) // version
        ..add(algorithmSeq)
        ..add(privateKeyOctetString);

      final dataBase64 = base64Encode(topLevelSeq.encodedBytes);
      return _formatPem(dataBase64, 'PRIVATE KEY');
    } catch (e) {
      throw Exception('Failed to convert RSA private key to PEM: $e');
    }
  }

  /// Format PEM with proper line breaks
  static String _formatPem(String base64Data, String keyType) {
    final chunks = <String>[];
    for (int i = 0; i < base64Data.length; i += 64) {
      chunks.add(base64Data.substring(
          i, i + 64 > base64Data.length ? base64Data.length : i + 64));
    }
    return '-----BEGIN $keyType-----\n${chunks.join('\n')}\n-----END $keyType-----';
  }

  // Generate key fingerprint
  static String _generateKeyFingerprint(String publicKeyPem) {
    final keyBytes = utf8.encode(publicKeyPem);
    final digest = sha256.convert(keyBytes);
    return digest.toString().substring(0, 16);
  }

  // Load organizations from database with caching
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

  // Main signup method
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
    final stopwatch = Stopwatch()..start();
    
    try {
      print('Starting doctor registration...');
      _lastSignupAttempt = DateTime.now();

      // Validate organization exists first
      print('Validating organization...');
      final orgCheck = await _supabase
          .from('Organization')
          .select('id')
          .eq('id', organizationId)
          .maybeSingle();
      
      if (orgCheck == null) {
        throw Exception('Invalid organization selected');
      }

      // Generate RSA keys using PointyCastle
      final keyPair = await _generateRSAKeyPair();
      final publicPem = keyPair['publicKey']!;
      final privatePem = keyPair['privateKey']!;
      final fingerprint = keyPair['fingerprint']!;
      
      print('RSA-2048 keys generated successfully (${stopwatch.elapsedMilliseconds}ms)');
      print('Key fingerprint: $fingerprint');

      // Create auth user
      print('Creating auth user...');
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      final authUser = authResponse.user;
      if (authUser == null) {
        throw Exception('Authentication failed - no user returned');
      }

      final authUserId = authUser.id;
      print('Auth user created: $authUserId (${stopwatch.elapsedMilliseconds}ms)');

      // Create database records with better error handling
      print('Creating database records...');
      
      String? personId;
      bool userCreated = false;
      bool doctorCreated = false;
      
      try {
        // Insert Person record
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

        // Insert User record - CONSISTENT WITH AuthService FORMAT
        print('Inserting User record...');
        await _supabase.from('User').insert({
          'id': authUserId,
          'email': email,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'rsa_public_key': publicPem,
          'rsa_private_key': privatePem,
          'key_created_at': DateTime.now().toUtc().toIso8601String(),
          'person_id': personId,
        });
        userCreated = true;
        print('User record created successfully');
          
        // Insert Doctor record
        print('Inserting Doctor record...');
        await _supabase.from('Organization_User').insert({
          'user_id': authUserId,
          'organization_id': organizationId,
          'position': position,
          'department': department,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        doctorCreated = true;
        print('Doctor record created successfully');

        print('All database records created successfully');

      } catch (dbError) {
        print('Database error: $dbError');
        
        // Clean up in reverse order
        if (doctorCreated) {
          try {
            await _supabase.from('Organization_User').delete().eq('user_id', authUserId);
            print('Cleaned up Doctor record');
          } catch (e) {
            print('Failed to clean up Doctor record: $e');
          }
        }
        
        if (userCreated) {
          try {
            await _supabase.from('User').delete().eq('id', authUserId);
            print('Cleaned up User record');
          } catch (e) {
            print('Failed to clean up User record: $e');
          }
        }
        
        if (personId != null) {
          try {
            await _supabase.from('Person').delete().eq('id', personId);
            print('Cleaned up Person record');
          } catch (e) {
            print('Failed to clean up Person record: $e');
          }
        }
        
        // Clean up auth user with proper admin access
        try {
          print('Cleaning up auth user...');
          await _supabase.auth.signOut();
          print('Auth user cleanup attempted');
        } catch (cleanupError) {
          print('Note: Auth user may need manual cleanup: $cleanupError');
        }
        
        rethrow;
      }

      stopwatch.stop();
      print('Staff registration completed in ${stopwatch.elapsedMilliseconds}ms!');

      return SignupResult(
        success: true,
        message: 'Account created successfully with 2048-bit RSA encryption! Please check your email to verify your account.',
        userId: authUserId,
      );

    } on AuthException catch (e) {
      stopwatch.stop();
      print('Auth error after ${stopwatch.elapsedMilliseconds}ms: ${e.message}');
      return SignupResult(
        success: false,
        errorMessage: _getAuthErrorMessage(e.message),
      );
    } on PostgrestException catch (e) {
      stopwatch.stop();
      print('Database error after ${stopwatch.elapsedMilliseconds}ms: ${e.message}');
      print('Error details: ${e.details}');
      print('Error hint: ${e.hint}');
      print('Error code: ${e.code}');
      return SignupResult(
        success: false,
        errorMessage: _getDatabaseErrorMessage(e.message, e.details, e.hint),
      );
    } catch (e) {
      stopwatch.stop();
      print('Registration error after ${stopwatch.elapsedMilliseconds}ms: $e');
      return SignupResult(
        success: false,
        errorMessage: 'Failed to register user: $e',
      );
    }
  }

  // Enhanced error message helpers
  static String _getAuthErrorMessage(String message) {
    if (message.contains('already registered') || 
        message.contains('already exists')) {
      return 'An account with this email already exists';
    } else if (message.contains('password')) {
      return 'Password does not meet requirements';
    } else if (message.contains('email')) {
      return 'Invalid email address';
    }
    return 'Authentication failed: $message';
  }

  static String _getDatabaseErrorMessage(String? message, String? details, String? hint) {
    final fullMessage = message ?? '';
    final fullDetails = details ?? '';
    final fullHint = hint ?? '';
    
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
    
    if (fullDetails.isNotEmpty && fullDetails != '{}') {
      return 'Database error: $fullDetails';
    } else if (fullMessage.isNotEmpty && fullMessage != '{}') {
      return 'Database error: $fullMessage';
    } else if (fullHint.isNotEmpty) {
      return 'Database error: $fullHint';
    }
    
    return 'Database error occurred - please try again';
  }

  // User RSA keys caching
  static Map<String, String>? _cachedUserKeys;
  static String? _cachedUserId;

  static Future<Map<String, String>?> getUserRSAKeys() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      if (_cachedUserKeys != null && _cachedUserId == user.id) {
        return _cachedUserKeys;
      }

      final response = await _supabase
          .from('User')
          .select('rsa_public_key, rsa_private_key')
          .eq('id', user.id)
          .single();

      final keys = <String, String>{
        'publicKey': response['rsa_public_key'] as String,
        'privateKey': response['rsa_private_key'] as String,
      };

      _cachedUserKeys = keys;
      _cachedUserId = user.id;

      return keys;
    } catch (e) {
      print('Error fetching RSA keys: $e');
      return null;
    }
  }

  // Clear caches
  static void clearCaches() {
    _cachedOrganizations = null;
    _organizationsCacheTime = null;
    _cachedUserKeys = null;
    _cachedUserId = null;
  }

  // RSA-OAEP Encryption using PointyCastle - CONSISTENT WITH AuthService
  static Future<String?> encryptData(String data) async {
    try {
      final keys = await getUserRSAKeys();
      if (keys == null) {
        print('No RSA keys available for encryption');
        return null;
      }
      
      return await compute(_encryptWithPointyCastle, {
        'data': data,
        'publicKeyPem': keys['publicKey']!,
      });
    } catch (e) {
      print('Encryption error: $e');
      return null;
    }
  }

  // RSA-OAEP Decryption using PointyCastle - CONSISTENT WITH AuthService  
  static Future<String?> decryptData(String encryptedData) async {
    try {
      final keys = await getUserRSAKeys();
      if (keys == null) {
        print('No RSA keys available for decryption');
        return null;
      }

      return await compute(_decryptWithPointyCastle, {
        'encryptedData': encryptedData,
        'privateKeyPem': keys['privateKey']!,
      });
    } catch (e) {
      print('Decryption error: $e');
      return null;
    }
  }

  // PointyCastle OAEP encryption (same as AuthService format)
  static String? _encryptWithPointyCastle(Map<String, String> params) {
    try {
      final data = params['data']!;
      final publicKeyPem = params['publicKeyPem']!;
      
      final publicKey = _parsePublicKeyFromPem(publicKeyPem);
      final encryptor = OAEPEncoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
      
      final dataBytes = utf8.encode(data);
      final encryptedBytes = encryptor.process(Uint8List.fromList(dataBytes));
      return base64Encode(encryptedBytes);
    } catch (e) {
      print('PointyCastle encryption error: $e');
      return null;
    }
  }

  // PointyCastle OAEP decryption (same as AuthService format)
  static String? _decryptWithPointyCastle(Map<String, String> params) {
    try {
      final encryptedData = params['encryptedData']!;
      final privateKeyPem = params['privateKeyPem']!;
      
      final privateKey = _parsePrivateKeyFromPem(privateKeyPem);
      final decryptor = OAEPEncoding(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      
      final encryptedBytes = base64Decode(encryptedData);
      final decryptedBytes = decryptor.process(encryptedBytes);
      return utf8.decode(decryptedBytes);
    } catch (e) {
      print('PointyCastle decryption error: $e');
      return null;
    }
  }

  // Parse public key from PEM
  static RSAPublicKey _parsePublicKeyFromPem(String pem) {
    final lines = pem.split('\n').where((line) => !line.startsWith('-----')).join('');
    final keyBytes = base64Decode(lines);
    final asn1Parser = ASN1Parser(keyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;
    final publicKeyAsn = ASN1Parser(publicKeyBitString.contentBytes());
    final publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;
    final modulus = (publicKeySeq.elements[0] as ASN1Integer).valueAsBigInteger;
    final exponent = (publicKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
    return RSAPublicKey(modulus, exponent);
  }

  // Parse private key from PEM
  static RSAPrivateKey _parsePrivateKeyFromPem(String pem) {
    final lines = pem.split('\n').where((line) => !line.startsWith('-----')).join('');
    final keyBytes = base64Decode(lines);
    final asn1Parser = ASN1Parser(keyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final privateKeyOctetString = topLevelSeq.elements[2] as ASN1OctetString;
    final privateKeyAsn = ASN1Parser(privateKeyOctetString.contentBytes());
    final privateKeySeq = privateKeyAsn.nextObject() as ASN1Sequence;
    final modulus = (privateKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
    final privateExponent = (privateKeySeq.elements[3] as ASN1Integer).valueAsBigInteger;
    final p = (privateKeySeq.elements[4] as ASN1Integer).valueAsBigInteger;
    final q = (privateKeySeq.elements[5] as ASN1Integer).valueAsBigInteger;
    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  // Validation helpers
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