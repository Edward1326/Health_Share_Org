import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:asn1lib/asn1lib.dart';

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

  /// CORRECTED: Converts RSA public key to PEM format using proper ASN.1 encoding
  static String _rsaPublicKeyToPem(RSAPublicKey publicKey) {
    try {
      // Create the RSA public key sequence (modulus, exponent)
      final publicKeySeq = ASN1Sequence();
      publicKeySeq.add(ASN1Integer(publicKey.modulus!));
      publicKeySeq.add(ASN1Integer(publicKey.exponent!));

      // Create the algorithm identifier for RSA
      final algorithmSeq = ASN1Sequence();
      final rsaOid =
          ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]); // RSA OID
      algorithmSeq.add(rsaOid);
      algorithmSeq.add(ASN1Null()); // NULL parameters for RSA

      // Create the bit string containing the public key
      final publicKeyBitString =
          ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

      // Create the top-level SubjectPublicKeyInfo structure
      final topLevelSeq = ASN1Sequence();
      topLevelSeq.add(algorithmSeq);
      topLevelSeq.add(publicKeyBitString);

      final dataBase64 = base64Encode(topLevelSeq.encodedBytes);
      return _formatPem(dataBase64, 'PUBLIC KEY');
    } catch (e) {
      throw Exception('Failed to convert RSA public key to PEM: $e');
    }
  }

  /// CORRECTED: Converts RSA private key to PEM format using proper ASN.1 encoding (PKCS#8)
  static String _rsaPrivateKeyToPem(RSAPrivateKey privateKey) {
    try {
      // Create PKCS#1 RSAPrivateKey structure
      final privateKeySeq = ASN1Sequence()
        ..add(ASN1Integer(BigInt.from(0))) // version
        ..add(ASN1Integer(privateKey.modulus!))
        ..add(ASN1Integer(privateKey.exponent!))
        ..add(ASN1Integer(privateKey.privateExponent!))
        ..add(ASN1Integer(privateKey.p!))
        ..add(ASN1Integer(privateKey.q!))
        ..add(ASN1Integer(
            privateKey.privateExponent! % (privateKey.p! - BigInt.one)))
        ..add(ASN1Integer(
            privateKey.privateExponent! % (privateKey.q! - BigInt.one)))
        ..add(ASN1Integer(privateKey.q!.modInverse(privateKey.p!)));

      // Create algorithm identifier for RSA
      final algorithmSeq = ASN1Sequence();
      final rsaOid =
          ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]); // RSA OID
      algorithmSeq.add(rsaOid);
      algorithmSeq.add(ASN1Null()); // NULL parameters

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

  /// Formats base64 string with line breaks every 64 characters
  static String _formatPem(String base64Data, String keyType) {
    final chunks = <String>[];
    for (int i = 0; i < base64Data.length; i += 64) {
      chunks.add(base64Data.substring(
          i, i + 64 > base64Data.length ? base64Data.length : i + 64));
    }

    return '-----BEGIN $keyType-----\n${chunks.join('\n')}\n-----END $keyType-----';
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
