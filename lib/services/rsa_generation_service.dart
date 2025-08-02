import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

class RSAKeyGenerationService {
  /// Generates RSA key pair using isolate for better performance
  /// Returns a map containing publicKey, privateKey, and fingerprint
  static Future<Map<String, String>> generateRSAKeyPairIsolate() async {
    return await compute(_generateRSAKeyPairSync, null);
  }

  /// Enhanced synchronous key generation for compute function (static for top-level requirement)
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

    final publicKeyPem = _rsaPublicKeyToPem(publicKey);
    final privateKeyPem = _rsaPrivateKeyToPem(privateKey);

    return {
      'publicKey': publicKeyPem,
      'privateKey': privateKeyPem,
      'fingerprint': _generateKeyFingerprint(publicKeyPem),
    };
  }

  /// Fixed random seeding function - FortunaRandom requires exactly 32 bytes (256 bits)
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

  /// Alternative seeding method using system entropy sources
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

  /// Converts RSA public key to PEM format using manual ASN.1 encoding
  static String _rsaPublicKeyToPem(RSAPublicKey publicKey) {
    // Manual ASN.1 DER encoding for RSA public key
    final modulusBytes = _bigIntToBytes(publicKey.modulus!);
    final exponentBytes = _bigIntToBytes(publicKey.exponent!);

    // Create ASN.1 INTEGER for modulus
    final modulusAsn1 = _createAsn1Integer(modulusBytes);

    // Create ASN.1 INTEGER for exponent
    final exponentAsn1 = _createAsn1Integer(exponentBytes);

    // Create ASN.1 SEQUENCE containing both integers
    final sequenceContent = <int>[];
    sequenceContent.addAll(modulusAsn1);
    sequenceContent.addAll(exponentAsn1);

    final sequence = _createAsn1Sequence(sequenceContent);

    // Convert to base64 and format as PEM
    final publicKeyBase64 = base64Encode(sequence);
    return '-----BEGIN PUBLIC KEY-----\n${_formatBase64(publicKeyBase64)}\n-----END PUBLIC KEY-----';
  }

  /// Converts RSA private key to PEM format using manual ASN.1 encoding
  static String _rsaPrivateKeyToPem(RSAPrivateKey privateKey) {
    // Manual ASN.1 DER encoding for RSA private key (PKCS#1 format)
    final version = _createAsn1Integer([0]); // version 0
    final modulus = _createAsn1Integer(_bigIntToBytes(privateKey.modulus!));
    final publicExponent =
        _createAsn1Integer(_bigIntToBytes(privateKey.exponent!));
    final privateExponent =
        _createAsn1Integer(_bigIntToBytes(privateKey.privateExponent!));
    final prime1 = _createAsn1Integer(_bigIntToBytes(privateKey.p!));
    final prime2 = _createAsn1Integer(_bigIntToBytes(privateKey.q!));
    final exponent1 = _createAsn1Integer(_bigIntToBytes(
        privateKey.privateExponent! % (privateKey.p! - BigInt.one)));
    final exponent2 = _createAsn1Integer(_bigIntToBytes(
        privateKey.privateExponent! % (privateKey.q! - BigInt.one)));
    final coefficient = _createAsn1Integer(
        _bigIntToBytes(privateKey.q!.modInverse(privateKey.p!)));

    // Create sequence with all components
    final sequenceContent = <int>[];
    sequenceContent.addAll(version);
    sequenceContent.addAll(modulus);
    sequenceContent.addAll(publicExponent);
    sequenceContent.addAll(privateExponent);
    sequenceContent.addAll(prime1);
    sequenceContent.addAll(prime2);
    sequenceContent.addAll(exponent1);
    sequenceContent.addAll(exponent2);
    sequenceContent.addAll(coefficient);

    final sequence = _createAsn1Sequence(sequenceContent);

    // Convert to base64 and format as PEM
    final privateKeyBase64 = base64Encode(sequence);
    return '-----BEGIN PRIVATE KEY-----\n${_formatBase64(privateKeyBase64)}\n-----END PRIVATE KEY-----';
  }

  /// Convert BigInt to bytes
  static List<int> _bigIntToBytes(BigInt bigInt) {
    final bytes = <int>[];
    var value = bigInt;

    if (value == BigInt.zero) {
      return [0];
    }

    while (value > BigInt.zero) {
      bytes.insert(0, (value & BigInt.from(0xff)).toInt());
      value = value >> 8;
    }

    // Add leading zero if the first bit is set (to ensure positive interpretation)
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes.insert(0, 0);
    }

    return bytes;
  }

  /// Create ASN.1 INTEGER
  static List<int> _createAsn1Integer(List<int> value) {
    final result = <int>[0x02]; // INTEGER tag
    result.addAll(_encodeLength(value.length));
    result.addAll(value);
    return result;
  }

  /// Create ASN.1 SEQUENCE
  static List<int> _createAsn1Sequence(List<int> content) {
    final result = <int>[0x30]; // SEQUENCE tag
    result.addAll(_encodeLength(content.length));
    result.addAll(content);
    return result;
  }

  /// Encode ASN.1 length
  static List<int> _encodeLength(int length) {
    if (length < 0x80) {
      return [length];
    }

    final lengthBytes = <int>[];
    var temp = length;
    while (temp > 0) {
      lengthBytes.insert(0, temp & 0xff);
      temp >>= 8;
    }

    return [0x80 | lengthBytes.length, ...lengthBytes];
  }

  /// Formats base64 string with line breaks every 64 characters
  static String _formatBase64(String base64String) {
    final regex = RegExp(r'.{1,64}');
    return regex
        .allMatches(base64String)
        .map((match) => match.group(0))
        .join('\n');
  }

  /// Generate key fingerprint for easier identification (static version)
  static String _generateKeyFingerprint(String publicKeyPem) {
    final keyBytes = utf8.encode(publicKeyPem);
    final digest = sha256.convert(keyBytes);
    return digest.toString().substring(0, 16); // First 16 chars of SHA256
  }

  /// Utility method to validate generated keys
  static bool validateKeyPair(String publicKeyPem, String privateKeyPem) {
    try {
      // Basic validation - check if keys are properly formatted
      return publicKeyPem.contains('-----BEGIN PUBLIC KEY-----') &&
          publicKeyPem.contains('-----END PUBLIC KEY-----') &&
          privateKeyPem.contains('-----BEGIN PRIVATE KEY-----') &&
          privateKeyPem.contains('-----END PRIVATE KEY-----');
    } catch (e) {
      return false;
    }
  }
}
