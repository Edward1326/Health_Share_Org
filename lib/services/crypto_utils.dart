import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'package:asn1lib/asn1lib.dart';

class CryptoUtils {
  /// Parse RSA public key from PEM format
  static pc.RSAPublicKey rsaPublicKeyFromPem(String pem) {
    try {
      // Remove PEM headers and decode base64
      final pemHeader = '-----BEGIN PUBLIC KEY-----';
      final pemFooter = '-----END PUBLIC KEY-----';

      var keyString = pem
          .replaceAll(pemHeader, '')
          .replaceAll(pemFooter, '')
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .replaceAll(' ', '')
          .trim();

      final keyBytes = base64Decode(keyString);

      // Parse DER encoded public key
      final asn1Parser = ASN1Parser(keyBytes);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

      // Skip algorithm identifier
      final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;
      final publicKeyAsn = ASN1Parser(publicKeyBitString.contentBytes());
      final publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;

      final modulus =
          (publicKeySeq.elements![0] as ASN1Integer).valueAsBigInteger;
      final exponent =
          (publicKeySeq.elements![1] as ASN1Integer).valueAsBigInteger;

      return pc.RSAPublicKey(modulus!, exponent!);
    } catch (e) {
      throw Exception('Failed to parse RSA public key from PEM: $e');
    }
  }

  /// Parse RSA private key from PEM format
  static pc.RSAPrivateKey rsaPrivateKeyFromPem(String pem) {
    try {
      // Handle both PKCS#1 and PKCS#8 formats
      String pemHeader = '-----BEGIN PRIVATE KEY-----';
      String pemFooter = '-----END PRIVATE KEY-----';

      if (pem.contains('-----BEGIN RSA PRIVATE KEY-----')) {
        pemHeader = '-----BEGIN RSA PRIVATE KEY-----';
        pemFooter = '-----END RSA PRIVATE KEY-----';
      }

      var keyString = pem
          .replaceAll(pemHeader, '')
          .replaceAll(pemFooter, '')
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .replaceAll(' ', '')
          .trim();

      final keyBytes = base64Decode(keyString);

      if (pem.contains('-----BEGIN RSA PRIVATE KEY-----')) {
        // PKCS#1 format
        return _parseRSAPrivateKeyPKCS1(keyBytes);
      } else {
        // PKCS#8 format
        return _parseRSAPrivateKeyPKCS8(keyBytes);
      }
    } catch (e) {
      throw Exception('Failed to parse RSA private key from PEM: $e');
    }
  }

  /// Parse PKCS#1 RSA private key
  static pc.RSAPrivateKey _parseRSAPrivateKeyPKCS1(Uint8List keyBytes) {
    final asn1Parser = ASN1Parser(keyBytes);
    final privateKeySeq = asn1Parser.nextObject() as ASN1Sequence;

    // PKCS#1 RSAPrivateKey structure:
    // RSAPrivateKey ::= SEQUENCE {
    //   version           Version,
    //   modulus           INTEGER,
    //   publicExponent    INTEGER,
    //   privateExponent   INTEGER,
    //   prime1            INTEGER,
    //   prime2            INTEGER,
    //   exponent1         INTEGER,
    //   exponent2         INTEGER,
    //   coefficient       INTEGER
    // }

    final modulus =
        (privateKeySeq.elements![1] as ASN1Integer).valueAsBigInteger;
    final publicExponent =
        (privateKeySeq.elements![2] as ASN1Integer).valueAsBigInteger;
    final privateExponent =
        (privateKeySeq.elements![3] as ASN1Integer).valueAsBigInteger;
    final p = (privateKeySeq.elements![4] as ASN1Integer).valueAsBigInteger;
    final q = (privateKeySeq.elements![5] as ASN1Integer).valueAsBigInteger;

    return pc.RSAPrivateKey(modulus!, privateExponent!, p, q);
  }

  /// Parse PKCS#8 RSA private key
  static pc.RSAPrivateKey _parseRSAPrivateKeyPKCS8(Uint8List keyBytes) {
    final asn1Parser = ASN1Parser(keyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    // Skip version and algorithm identifier
    final privateKeyOctetString = topLevelSeq.elements![2] as ASN1OctetString;
    return _parseRSAPrivateKeyPKCS1(privateKeyOctetString.contentBytes());
  }

  /// Encrypt string with RSA public key using OAEP padding
  static String rsaEncrypt(String plainText, pc.RSAPublicKey publicKey) {
    try {
      final cipher = pc.OAEPEncoding(pc.RSAEngine())
        ..init(true, pc.PublicKeyParameter<pc.RSAPublicKey>(publicKey));

      final plainBytes = utf8.encode(plainText);

      // Check if data is too large for RSA encryption
      final maxInputSize =
          (publicKey.modulus!.bitLength + 7) ~/ 8 - 2 * 20 - 2; // OAEP overhead
      if (plainBytes.length > maxInputSize) {
        throw Exception(
            'Data too large for RSA encryption. Maximum size: $maxInputSize bytes');
      }

      final encryptedBytes = cipher.process(Uint8List.fromList(plainBytes));
      return base64Encode(encryptedBytes);
    } catch (e) {
      throw Exception('RSA encryption failed: $e');
    }
  }

  /// Decrypt string with RSA private key using OAEP padding
  static String rsaDecrypt(String encryptedText, pc.RSAPrivateKey privateKey) {
    try {
      final cipher = pc.OAEPEncoding(pc.RSAEngine())
        ..init(false, pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey));

      final encryptedBytes = base64Decode(encryptedText);
      final decryptedBytes = cipher.process(encryptedBytes);

      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw Exception('RSA decryption failed: $e');
    }
  }

  /// Generate RSA key pair
  static pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey>
      generateRSAKeyPair({
    int bitLength = 2048,
  }) {
    final secureRandom = pc.SecureRandom('Fortuna');
    final seed = _generateRandomBytes(32);
    secureRandom.seed(pc.KeyParameter(seed));

    final keyGen = pc.RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), bitLength, 64),
        secureRandom,
      ));

    final keyPair = keyGen.generateKeyPair();
    return pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey>(
      keyPair.publicKey as pc.RSAPublicKey,
      keyPair.privateKey as pc.RSAPrivateKey,
    );
  }

  /// Convert RSA public key to PEM format
  static String rsaPublicKeyToPem(pc.RSAPublicKey publicKey) {
    try {
      // Create algorithm identifier sequence
      final algorithmSeq = ASN1Sequence();
      final algorithmAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList(
          [0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
      final paramsAsn1Obj =
          ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
      algorithmSeq.add(algorithmAsn1Obj);
      algorithmSeq.add(paramsAsn1Obj);

      // Create public key sequence
      final publicKeySeq = ASN1Sequence();
      publicKeySeq.add(ASN1Integer(publicKey.modulus!));
      publicKeySeq.add(ASN1Integer(publicKey.exponent!));
      final publicKeySeqBitString =
          ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

      // Create top level sequence
      final topLevelSeq = ASN1Sequence();
      topLevelSeq.add(algorithmSeq);
      topLevelSeq.add(publicKeySeqBitString);

      final dataBase64 = base64Encode(topLevelSeq.encodedBytes);
      return _formatPem(dataBase64, 'PUBLIC KEY');
    } catch (e) {
      throw Exception('Failed to convert RSA public key to PEM: $e');
    }
  }

  /// Convert RSA private key to PEM format (PKCS#8)
  static String rsaPrivateKeyToPem(pc.RSAPrivateKey privateKey) {
    try {
      // Create PKCS#1 RSAPrivateKey structure
      final privateKeySeq = ASN1Sequence()
        ..add(ASN1Integer(BigInt.from(0))) // version
        ..add(ASN1Integer(privateKey.modulus!))
        ..add(ASN1Integer(privateKey.publicExponent!))
        ..add(ASN1Integer(privateKey.privateExponent!))
        ..add(ASN1Integer(privateKey.p!))
        ..add(ASN1Integer(privateKey.q!))
        ..add(ASN1Integer(
            privateKey.privateExponent! % (privateKey.p! - BigInt.one)))
        ..add(ASN1Integer(
            privateKey.privateExponent! % (privateKey.q! - BigInt.one)))
        ..add(ASN1Integer(_modInverse(privateKey.q!, privateKey.p!)));

      // Create algorithm identifier
      final algorithmSeq = ASN1Sequence();
      final algorithmAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList(
          [0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
      final paramsAsn1Obj =
          ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
      algorithmSeq.add(algorithmAsn1Obj);
      algorithmSeq.add(paramsAsn1Obj);

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

  /// Format base64 data as PEM
  static String _formatPem(String base64Data, String keyType) {
    final chunks = <String>[];
    for (int i = 0; i < base64Data.length; i += 64) {
      chunks.add(base64Data.substring(
          i, i + 64 > base64Data.length ? base64Data.length : i + 64));
    }

    return '-----BEGIN $keyType-----\n${chunks.join('\n')}\n-----END $keyType-----';
  }

  /// Generate secure random bytes
  static Uint8List _generateRandomBytes(int length) {
    final random = pc.SecureRandom('Fortuna');

    // Create a more secure seed
    final now = DateTime.now();
    final seed = <int>[];

    // Add timestamp components
    seed.addAll(_intToBytes(now.millisecondsSinceEpoch));
    seed.addAll(_intToBytes(now.microsecond));

    // Add some entropy from object hash codes
    seed.addAll(_intToBytes(Object().hashCode));
    seed.addAll(_intToBytes(DateTime.now().hashCode));

    // Pad to at least 32 bytes
    while (seed.length < 32) {
      seed.add((now.millisecondsSinceEpoch + seed.length) & 0xFF);
    }

    random.seed(pc.KeyParameter(Uint8List.fromList(seed.take(32).toList())));
    return random.nextBytes(length);
  }

  /// Convert integer to bytes
  static List<int> _intToBytes(int value) {
    final bytes = <int>[];
    while (value > 0) {
      bytes.insert(0, value & 0xFF);
      value >>= 8;
    }
    return bytes.isEmpty ? [0] : bytes;
  }

  /// Calculate modular inverse using Extended Euclidean Algorithm
  static BigInt _modInverse(BigInt a, BigInt m) {
    if (a < BigInt.one || m < BigInt.one) {
      throw ArgumentError('Arguments must be positive');
    }

    // Extended Euclidean Algorithm
    BigInt m0 = m;
    BigInt x0 = BigInt.zero;
    BigInt x1 = BigInt.one;

    if (m == BigInt.one) return BigInt.zero;

    while (a > BigInt.one) {
      BigInt q = a ~/ m;
      BigInt t = m;

      m = a % m;
      a = t;
      t = x0;

      x0 = x1 - q * x0;
      x1 = t;
    }

    if (x1 < BigInt.zero) x1 += m0;

    return x1;
  }

  /// Utility method to create RSA key pair and return as PEM strings
  static Map<String, String> generateRSAKeyPairAsPem({int bitLength = 2048}) {
    final keyPair = generateRSAKeyPair(bitLength: bitLength);

    return {
      'publicKey': rsaPublicKeyToPem(keyPair.publicKey),
      'privateKey': rsaPrivateKeyToPem(keyPair.privateKey),
    };
  }

  /// Test method to verify encryption/decryption works
  static bool testRSAEncryption({int bitLength = 2048}) {
    try {
      final keyPair = generateRSAKeyPair(bitLength: bitLength);
      final testMessage = 'Hello, RSA encryption test!';

      final encrypted = rsaEncrypt(testMessage, keyPair.publicKey);
      final decrypted = rsaDecrypt(encrypted, keyPair.privateKey);

      return testMessage == decrypted;
    } catch (e) {
      print('RSA test failed: $e');
      return false;
    }
  }
}
