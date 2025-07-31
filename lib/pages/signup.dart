import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart'
    hide State; // Hide State from pointycastle
import 'package:asn1lib/asn1lib.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

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

  Future<Map<String, String>> generateRSAKeyPairIsolate() async {
    return await compute(_generateRSAKeyPairSync, null);
  }

// Enhanced synchronous key generation for compute function (static for top-level requirement)
  static Map<String, String> _generateRSAKeyPairSync(void _) {
    final keyGen = RSAKeyGenerator();
    final secureRandom = FortunaRandom();

    // Enhanced random seeding with proper 256-bit seed
    _seedSecureRandom(secureRandom);

    // Optimized parameters for faster generation
    keyGen.init(ParametersWithRandom(
      RSAKeyGeneratorParameters(
          BigInt.parse('65537'), // Standard public exponent
          2048, // Key size
          8 // Reduced certainty for faster generation (was 12, now 8)
          ),
      secureRandom,
    ));

    final keyPair = keyGen.generateKeyPair();
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;

    return {
      'publicKey': _rsaPublicKeyToPem(publicKey),
      'privateKey': _rsaPrivateKeyToPem(privateKey),
      'fingerprint': _generateKeyFingerprint(_rsaPublicKeyToPem(publicKey)),
    };
  }

// Fixed random seeding function - FortunaRandom requires exactly 32 bytes (256 bits)
  static void _seedSecureRandom(FortunaRandom secureRandom) {
    final seedSource = Random.secure();

    // Generate exactly 32 bytes (256 bits) for Fortuna PRNG
    final seed = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      seed[i] = seedSource.nextInt(256);
    }

    // Seed the FortunaRandom with exactly 256 bits
    secureRandom.seed(KeyParameter(seed));

    // Add additional entropy by generating some random bytes
    // This helps initialize the internal state
    for (int i = 0; i < 100; i++) {
      secureRandom.nextUint8();
    }
  }

// Alternative seeding method using system entropy sources
  static void _seedSecureRandomAlternative(FortunaRandom secureRandom) {
    final seedSource = Random.secure();
    final timeMillis = DateTime.now().millisecondsSinceEpoch;

    // Create exactly 32 bytes combining different entropy sources
    final seed = Uint8List(32);

    // Fill first 8 bytes with time-based entropy
    final timeBytes = ByteData(8);
    timeBytes.setUint64(0, timeMillis);
    seed.setRange(0, 8, timeBytes.buffer.asUint8List());

    // Fill remaining 24 bytes with secure random
    for (int i = 8; i < 32; i++) {
      seed[i] = seedSource.nextInt(256);
    }

    secureRandom.seed(KeyParameter(seed));

    // Prime the generator
    for (int i = 0; i < 100; i++) {
      secureRandom.nextUint8();
    }
  }

// Static helper functions for compute (need to be static/top-level)
  static String _rsaPublicKeyToPem(RSAPublicKey publicKey) {
    final asn1 = ASN1Sequence();
    asn1.add(ASN1Integer(publicKey.modulus!));
    asn1.add(ASN1Integer(publicKey.exponent!));

    // Use encodedBytes instead of encode()
    final publicKeyDer = asn1.encodedBytes;
    final publicKeyBase64 = base64Encode(publicKeyDer);

    return '-----BEGIN PUBLIC KEY-----\n${_formatBase64(publicKeyBase64)}\n-----END PUBLIC KEY-----';
  }

  static String _rsaPrivateKeyToPem(RSAPrivateKey privateKey) {
    final asn1 = ASN1Sequence();
    asn1.add(ASN1Integer(BigInt.from(0))); // version
    asn1.add(ASN1Integer(privateKey.modulus!));
    asn1.add(ASN1Integer(privateKey.exponent!));
    asn1.add(ASN1Integer(privateKey.privateExponent!));
    asn1.add(ASN1Integer(privateKey.p!));
    asn1.add(ASN1Integer(privateKey.q!));
    asn1.add(ASN1Integer(
        privateKey.privateExponent! % (privateKey.p! - BigInt.one)));
    asn1.add(ASN1Integer(
        privateKey.privateExponent! % (privateKey.q! - BigInt.one)));
    asn1.add(ASN1Integer(privateKey.q!.modInverse(privateKey.p!)));

    // Use encodedBytes instead of encode()
    final privateKeyDer = asn1.encodedBytes;
    final privateKeyBase64 = base64Encode(privateKeyDer);

    return '-----BEGIN PRIVATE KEY-----\n${_formatBase64(privateKeyBase64)}\n-----END PRIVATE KEY-----';
  }

  static String _formatBase64(String base64String) {
    final regex = RegExp(r'.{1,64}');
    return regex
        .allMatches(base64String)
        .map((match) => match.group(0))
        .join('\n');
  }

// Generate key fingerprint for easier identification (static version)
  static String _generateKeyFingerprint(String publicKeyPem) {
    final keyBytes = utf8.encode(publicKeyPem);
    final digest = sha256.convert(keyBytes);
    return digest.toString().substring(0, 16); // First 16 chars of SHA256
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

      // Generate RSA Key Pair using optimized compute approach (works on web)
      print('Generating RSA key pair using compute...');
      final keyData = await generateRSAKeyPairIsolate();

      final publicKeyPem = keyData['publicKey']!;
      final privateKeyPem = keyData['privateKey']!;
      final keyFingerprint = keyData['fingerprint']!;

      print('RSA keys generated successfully using compute');
      print('Key fingerprint: $keyFingerprint');

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
          'key_fingerprint': keyFingerprint, // Store fingerprint in metadata
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create authentication account');
      }

      final authUserId = authResponse.user!.id;
      print('Auth user created with ID: $authUserId');

      // Step 2: Create Person record (without keys)
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
            'auth_user_id': authUserId,
            'created_at': currentTime,
          })
          .select()
          .single();

      final personUuid = personResponse['id']; // This is now a UUID string
      print('Person created with UUID: $personUuid');

      // Step 3: Create User record (with both keys)
      print('Creating User record...');
      final userResponse = await Supabase.instance.client
          .from('User')
          .insert({
            'username': _usernameController.text.trim(),
            'person_id': personUuid, // UUID string, no parsing needed
            'created_at': currentTime,
            'rsa_private_key': privateKeyPem, // Store private key in User table
            'rsa_public_key': publicKeyPem, // Store public key in User table
            'key_created_at': currentTime,
          })
          .select()
          .single();

      final userUuid = userResponse['id']; // This is now a UUID string
      print('User created with UUID: $userUuid');

      // Step 4: Create Organization_User record
      print('Creating Organization_User record...');
      await Supabase.instance.client.from('Organization_User').insert({
        'position': _positionController.text.trim(),
        'department': _departmentController.text.trim(),
        'created_at': currentTime,
        'organization_id':
            _selectedOrganizationId, // UUID string, no parsing needed
        'user_id': userUuid, // UUID string, no parsing needed
      });

      print('Organization_User created successfully');

      // Step 5: Optionally store key metadata in RSA_Keys table if it exists
      print('Creating RSA key record...');
      try {
        await Supabase.instance.client.from('RSA_Keys').insert({
          'person_id': personUuid, // UUID string, no parsing needed
          'user_id': userUuid, // UUID string, no parsing needed
          'key_fingerprint': keyFingerprint,
          'rsa_public_key': publicKeyPem,
          'rsa_private_key': privateKeyPem,
          'key_size': 2048,
          'algorithm': 'RSA',
          'created_at': currentTime,
          'is_active': true,
        });
        print('RSA key record created successfully');
      } catch (e) {
        print('RSA_Keys table might not exist or have different schema: $e');
        // Continue without failing if RSA_Keys table doesn't exist
      }

      _showSuccessSnackBar(
          'Employee account created successfully with RSA keys! Please check your email to verify your account before signing in.');

      // Navigate back to login page
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Signup error: $e');
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
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoadingOrgs
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0891B2)))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 20.0),
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
                                  color:
                                      const Color(0xFF0891B2).withOpacity(0.1),
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
                                  color:
                                      const Color(0xFF0891B2).withOpacity(0.05),
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
                                      color: const Color(0xFF0891B2)
                                          .withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.enhanced_encryption,
                                      size: 40,
                                      color: Color(0xFF0891B2),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Secure Sign up',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Join your organization with end-to-end encryption',
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

                      // Organization Selection
                      _buildInputField(
                        child: DropdownButtonFormField<String>(
                          value: _selectedOrganizationId,
                          decoration: InputDecoration(
                            hintText: 'Select your organization',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
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
                              value: org[
                                  'id'], // Remove .toString() - UUIDs are already strings
                              child: Text(org['name']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedOrganizationId = value;
                            });
                          },
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Color(0xFF64748B)),
                        ),
                        icon: Icons.business,
                      ),

                      // Full Name
                      _buildInputField(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: InputDecoration(
                            hintText: 'First Name',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
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
                          decoration: InputDecoration(
                            hintText: 'Middle Name (Optional)',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                        icon: Icons.person_outline,
                      ),

                      _buildInputField(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: InputDecoration(
                            hintText: 'Last Name',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your last name'
                              : null,
                        ),
                        icon: Icons.person,
                      ),

                      // Phone Number
                      _buildInputField(
                        child: TextFormField(
                          controller: _contactNumberController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Phone Number',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
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
                        icon: Icons.phone,
                      ),

                      // Address
                      _buildInputField(
                        child: TextFormField(
                          controller: _addressController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Address',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your address'
                              : null,
                        ),
                        icon: Icons.location_on,
                      ),

                      // Position
                      _buildInputField(
                        child: TextFormField(
                          controller: _positionController,
                          decoration: InputDecoration(
                            hintText: 'Position/Job Title',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your position'
                              : null,
                        ),
                        icon: Icons.work,
                      ),

                      // Department
                      _buildInputField(
                        child: TextFormField(
                          controller: _departmentController,
                          decoration: InputDecoration(
                            hintText: 'Department',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          validator: (value) => value?.trim().isEmpty ?? true
                              ? 'Please enter your department'
                              : null,
                        ),
                        icon: Icons.group_work,
                      ),

                      // Username
                      _buildInputField(
                        child: TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            hintText: 'Username',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
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
                        icon: Icons.account_circle,
                      ),

                      // Email
                      _buildInputField(
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'Email ID',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
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
                        icon: Icons.alternate_email,
                      ),

                      // Password
                      _buildInputField(
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
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
                        icon: Icons.lock,
                      ),

                      // Confirm Password
                      _buildInputField(
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Confirm Password',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
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

                      const SizedBox(height: 32),

                      // Sign Up Button
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
                          onPressed: _isLoading ? null : _signup,
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
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Create Secure Account',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Security Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0891B2).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.security,
                              color: Color(0xFF0891B2),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your account will be secured with RSA-2048 encryption keys generated during signup.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF0891B2).withOpacity(0.8),
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
                            'Already Signed up? ',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 16,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              'Login',
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
              color: const Color(0xFF64748B),
              size: 20,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
