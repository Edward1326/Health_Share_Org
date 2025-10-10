import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HiveTransactionSignerWeb {
  static const String _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static const String _hiveChainId =
      'beeab0de00000000000000000000000000000000000000000000000000000000';

  static Future<Map<String, dynamic>> signTransaction(
    Map<String, dynamic> transaction,
  ) async {
    try {
      final postingWif = dotenv.env['HIVE_POSTING_WIF'] ?? '';
      if (postingWif.isEmpty) {
        throw Exception('HIVE_POSTING_WIF not found in environment variables');
      }

      print('🔐 Starting Hive transaction signing...');

      final privateKey = _wifToPrivateKey(postingWif);
      print('✓ Private key decoded from WIF');

      final serializedTransaction = _serializeTransaction(transaction);
      print('✓ Transaction serialized (${serializedTransaction.length} bytes)');

      final chainIdBytes = _hexToBytes(_hiveChainId);
      final signingBuffer = Uint8List.fromList([
        ...chainIdBytes,
        ...serializedTransaction,
      ]);
      print('✓ Signing buffer created (${signingBuffer.length} bytes)');

      final hash = sha256.convert(signingBuffer).bytes;
      print('✓ SHA-256 hash computed');

      final signature = _signHash(Uint8List.fromList(hash), privateKey);
      print('✓ Signature generated: ${signature.substring(0, 20)}...');

      final signedTransaction = Map<String, dynamic>.from(transaction);
      signedTransaction['signatures'] = [signature];

      print('✅ Transaction signed successfully!');
      return signedTransaction;
    } catch (e, stackTrace) {
      print('❌ Failed to sign transaction: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to sign transaction: $e');
    }
  }

  static Uint8List _wifToPrivateKey(String wif) {
    try {
      final decoded = _base58Decode(wif);
      if (decoded.length != 37) {
        throw Exception('Invalid WIF length: ${decoded.length} (expected 37)');
      }
      final privateKey = decoded.sublist(1, 33);

      final payload = decoded.sublist(0, 33);
      final checksum = decoded.sublist(33);
      final hash = sha256.convert(sha256.convert(payload).bytes).bytes;
      if (!_listEquals(checksum, hash.sublist(0, 4))) {
        throw Exception('Invalid WIF checksum');
      }

      return Uint8List.fromList(privateKey);
    } catch (e) {
      throw Exception('Failed to decode WIF: $e');
    }
  }

  static Uint8List _base58Decode(String input) {
    final alphabet = _base58Alphabet;
    final base = BigInt.from(58);
    BigInt decoded = BigInt.zero;
    BigInt multi = BigInt.one;

    for (int i = input.length - 1; i >= 0; i--) {
      final char = input[i];
      final index = alphabet.indexOf(char);
      if (index == -1) {
        throw Exception('Invalid base58 character: $char');
      }
      decoded += BigInt.from(index) * multi;
      multi *= base;
    }

    final bytes = <int>[];
    while (decoded > BigInt.zero) {
      bytes.insert(0, (decoded % BigInt.from(256)).toInt());
      decoded ~/= BigInt.from(256);
    }

    for (int i = 0; i < input.length && input[i] == '1'; i++) {
      bytes.insert(0, 0);
    }
    return Uint8List.fromList(bytes);
  }

  static Uint8List _serializeTransaction(Map<String, dynamic> transaction) {
    final buffer = <int>[];

    final refBlockNum = transaction['ref_block_num'] as int;
    buffer.addAll(_serializeUint16(refBlockNum));

    final refBlockPrefix = transaction['ref_block_prefix'] as int;
    buffer.addAll(_serializeUint32(refBlockPrefix));

    final expiration = transaction['expiration'] as String;
    final expirationTimestamp =
        DateTime.parse(expiration + 'Z').millisecondsSinceEpoch ~/ 1000;
    buffer.addAll(_serializeUint32(expirationTimestamp));

    final operations = transaction['operations'] as List;
    buffer.addAll(_serializeOperations(operations));

    buffer.addAll(_serializeVarint(0));

    return Uint8List.fromList(buffer);
  }

  static List<int> _serializeOperations(List operations) {
    final buffer = <int>[];
    buffer.addAll(_serializeVarint(operations.length));

    for (final operation in operations) {
      final opList = operation as List;
      final opData = opList[1] as Map<String, dynamic>;

      buffer.addAll(_serializeVarint(18));
      buffer.addAll(_serializeCustomJsonOperation(opData));
    }
    return buffer;
  }

  static List<int> _serializeCustomJsonOperation(Map<String, dynamic> opData) {
    final buffer = <int>[];

    final requiredAuths = opData['required_auths'] as List<dynamic>;
    buffer.addAll(_serializeVarint(requiredAuths.length));
    for (final auth in requiredAuths) {
      buffer.addAll(_serializeString(auth as String));
    }

    final requiredPostingAuths =
        opData['required_posting_auths'] as List<dynamic>;
    buffer.addAll(_serializeVarint(requiredPostingAuths.length));
    for (final auth in requiredPostingAuths) {
      buffer.addAll(_serializeString(auth as String));
    }

    final id = opData['id'] as String;
    buffer.addAll(_serializeString(id));

    final json = opData['json'] as String;
    buffer.addAll(_serializeString(json));

    return buffer;
  }

  static List<int> _serializeString(String str) {
    final bytes = utf8.encode(str);
    final buffer = <int>[];
    buffer.addAll(_serializeVarint(bytes.length));
    buffer.addAll(bytes);
    return buffer;
  }

  static List<int> _serializeVarint(int value) {
    final buffer = <int>[];
    while (value >= 0x80) {
      buffer.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    buffer.add(value & 0x7F);
    return buffer;
  }

  static List<int> _serializeUint16(int value) => [
        value & 0xFF,
        (value >> 8) & 0xFF,
      ];

  static List<int> _serializeUint32(int value) => [
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ];

  /// Sign using deterministic ECDSA (RFC 6979) - Hive compatible
  static String _signHash(Uint8List hash, Uint8List privateKey) {
    try {
      final secp256k1 = ECDomainParameters('secp256k1');
      final privKey = ECPrivateKey(_bytesToBigInt(privateKey), secp256k1);

      // Use deterministic ECDSA with SHA-256 (RFC 6979)
      final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
      final params = PrivateKeyParameter(privKey);
      signer.init(true, params);

      final ECSignature ecSig = signer.generateSignature(hash) as ECSignature;

      var r = ecSig.r;
      var s = ecSig.s;
      
      // Normalize to low-S form (required by Hive)
      final halfCurveOrder = secp256k1.n >> 1;
      if (s.compareTo(halfCurveOrder) > 0) {
        s = secp256k1.n - s;
      }

      // Calculate recovery ID by trying all 4 possibilities and checking which recovers our public key
      final publicKeyPoint = secp256k1.G * privKey.d;
      final publicKeyBytes = _encodePublicKeyUncompressed(publicKeyPoint!);
      
      int recoveryId = 0;
      bool foundRecoveryId = false;
      
      for (int i = 0; i < 4; i++) {
        try {
          final recovered = _recoverPublicKeyFromSignature(hash, r, s, i, secp256k1);
          if (recovered != null) {
            final recoveredBytes = _encodePublicKeyUncompressed(recovered);
            if (_listEquals(publicKeyBytes, recoveredBytes)) {
              recoveryId = i;
              foundRecoveryId = true;
              print('✓ Recovery ID found: $recoveryId');
              break;
            }
          }
        } catch (e) {
          print('Recovery attempt $i failed: $e');
          continue;
        }
      }
      
      if (!foundRecoveryId) {
        print('⚠️  Warning: Could not find recovery ID, defaulting to 0');
      }

      // Build compact signature (65 bytes)
      final rBytes = _bigIntToBytes(r, 32);
      final sBytes = _bigIntToBytes(s, 32);
      
      final compactSig = Uint8List(65);
      compactSig[0] = recoveryId + 31; // Recovery flag for compressed key
      compactSig.setRange(1, 33, rBytes);
      compactSig.setRange(33, 65, sBytes);

      return compactSig.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } catch (e) {
      throw Exception('Failed to sign hash: $e');
    }
  }

  /// Recover public key from signature components
  static ECPoint? _recoverPublicKeyFromSignature(
    Uint8List hash,
    BigInt r,
    BigInt s,
    int recoveryId,
    ECDomainParameters curve,
  ) {
    try {
      final n = curve.n;
      final i = BigInt.from(recoveryId ~/ 2);
      final x = r + (i * n);
      
      final p = curve.curve as ECCurve;
      final fieldSize = BigInt.from(p.fieldSize);
      
      if (x.compareTo(fieldSize) >= 0) {
        return null;
      }
      
      // Decompress point from x coordinate
      final R = _decompressPoint(x, (recoveryId & 1) == 1, curve);
      if (R == null) {
        return null;
      }
      
      // Verify R*n = infinity (point is on curve)
      final Rn = R * n;
      if (Rn == null || !Rn.isInfinity) {
        return null;
      }
      
      // Recover: Q = r^-1 * (s*R - e*G)
      final e = _bytesToBigInt(hash);
      final rInv = r.modInverse(n);
      
      // Calculate s*R
      final sR = R * s;
      if (sR == null) {
        return null;
      }
      
      // Calculate -e*G = (n-e)*G
      final minusE = (n - (e % n)) % n;
      final negEG = curve.G * minusE;
      if (negEG == null) {
        return null;
      }
      
      // Calculate (s*R - e*G) = (s*R) + (-e*G)
      final sRMinusEG = sR + negEG;
      if (sRMinusEG == null) {
        return null;
      }
      
      // Multiply by r^-1
      final Q = sRMinusEG * rInv;
      
      return Q;
    } catch (e) {
      return null;
    }
  }

  /// Decompress EC point from x coordinate
  static ECPoint? _decompressPoint(
    BigInt x,
    bool yBit,
    ECDomainParameters curve,
  ) {
    try {
      final p = curve.curve as ECCurve;
      final fieldSize = BigInt.from(p.fieldSize);
      
      // For secp256k1: y² = x³ + 7
      final x3 = x.modPow(BigInt.from(3), fieldSize);
      final seven = BigInt.from(7);
      final y2 = (x3 + seven) % fieldSize;
      
      // y = y²^((p+1)/4) mod p (since p ≡ 3 mod 4)
      final exponent = (fieldSize + BigInt.one) ~/ BigInt.from(4);
      var y = y2.modPow(exponent, fieldSize);
      
      // Ensure correct parity
      if (y.isEven != !yBit) {
        y = fieldSize - y;
      }
      
      return curve.curve.createPoint(x, y);
    } catch (e) {
      return null;
    }
  }

  /// Encode public key in uncompressed format for comparison
  static Uint8List _encodePublicKeyUncompressed(ECPoint point) {
    final x = point.x!.toBigInteger()!;
    final y = point.y!.toBigInteger()!;
    
    final xBytes = _bigIntToBytes(x, 32);
    final yBytes = _bigIntToBytes(y, 32);
    
    final result = Uint8List(65);
    result[0] = 0x04; // Uncompressed format marker
    result.setRange(1, 33, xBytes);
    result.setRange(33, 65, yBytes);
    
    return result;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) + BigInt.from(bytes[i]);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final bytes = Uint8List(length);
    for (int i = length - 1; i >= 0; i--) {
      bytes[i] = (value & BigInt.from(0xFF)).toInt();
      value >>= 8;
    }
    return bytes;
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool isValidWif(String wif) {
    try {
      _wifToPrivateKey(wif);
      return true;
    } catch (e) {
      return false;
    }
  }

  static String getPostingWif() {
    return dotenv.env['HIVE_POSTING_WIF'] ?? '';
  }

  /// DEBUG: Derive and print public key from WIF
  static String debugGetPublicKeyFromWif(String wif) {
    try {
      print('\n=== DEBUG: Deriving public key from WIF ===');
      
      final privateKey = _wifToPrivateKey(wif);
      print('✓ Private key extracted from WIF');
      print('  Private key (hex): ${privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      
      final secp256k1 = ECDomainParameters('secp256k1');
      final privKeyObj = ECPrivateKey(_bytesToBigInt(privateKey), secp256k1);
      final publicKeyPoint = secp256k1.G * privKeyObj.d;
      
      if (publicKeyPoint == null) {
        throw Exception('Failed to derive public key point');
      }
      
      print('✓ Public key point derived');
      
      // Uncompressed format (for internal use)
      final uncompressedBytes = _encodePublicKeyUncompressed(publicKeyPoint);
      final uncompressedHex = uncompressedBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      print('  Uncompressed (hex): $uncompressedHex');
      
      // Compressed format (what Hive typically uses)
      final x = publicKeyPoint.x!.toBigInteger()!;
      final y = publicKeyPoint.y!.toBigInteger()!;
      final isYEven = y.isEven;
      
      final xBytes = _bigIntToBytes(x, 32);
      final compressedPrefix = isYEven ? '02' : '03';
      final compressedHex = compressedPrefix + xBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      print('  Compressed (hex): $compressedHex');
      
      // Convert to Hive public key format (STM prefix)
      // This is a simplified version - actual implementation may vary
      final publicKeyForHive = 'STM' + compressedHex;
      print('  Hive format (approx): $publicKeyForHive');
      print('  Note: Actual format may differ - compare with Hive posting key\n');
      
      return compressedHex;
    } catch (e, stackTrace) {
      print('Error deriving public key: $e');
      print('Stack trace: $stackTrace');
      return '';
    }
  }

  /// DEBUG: Run all diagnostic checks
  static Future<void> runDiagnostics() async {
    print('\n╔════════════════════════════════════════════════════════╗');
    print('║        HIVE SIGNING DIAGNOSTICS                        ║');
    print('╚════════════════════════════════════════════════════════╝\n');
    
    await dotenv.load();
    
    final wif = dotenv.env['HIVE_POSTING_WIF'] ?? '';
    final accountName = dotenv.env['HIVE_ACCOUNT_NAME'] ?? '';
    
    print('Environment variables:');
    print('  HIVE_ACCOUNT_NAME: ${accountName.isNotEmpty ? '✓ Set' : '✗ Missing'}');
    print('  HIVE_POSTING_WIF: ${wif.isNotEmpty ? '✓ Set' : '✗ Missing'}\n');
    
    if (wif.isEmpty) {
      print('✗ HIVE_POSTING_WIF is not set. Cannot proceed.\n');
      return;
    }
    
    print('WIF Validation:');
    final isValid = isValidWif(wif);
    if (isValid) {
      print('  ✓ WIF format is valid');
      debugGetPublicKeyFromWif(wif);
    } else {
      print('  ✗ WIF format is invalid\n');
    }
    
    print('Expected Hive account posting key:');
    print('  STM5VqN4yjdZGCeLTkkXyfTWnYzgQN5VjwvW3HF5hHhWXDhtZnKpc');
    print('\n  ^ Compare the key above with the one derived from your WIF\n');
    
    print('╔════════════════════════════════════════════════════════╗');
    print('║        If the keys do not match, your WIF is           ║');
    print('║        for a different account. Update .env file.      ║');
    print('╚════════════════════════════════════════════════════════╝\n');
  }
}