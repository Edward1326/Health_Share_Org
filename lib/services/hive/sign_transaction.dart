import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HiveTransactionSignerWeb {
  // Base58 alphabet for WIF decoding
  static const String _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  // Hive chain ID (mainnet)
  static const String _hiveChainId =
      'beeab0de00000000000000000000000000000000000000000000000000000000';

  /// Signs a Hive transaction using the posting private key from environment
  static Future<Map<String, dynamic>> signTransaction(
    Map<String, dynamic> transaction,
  ) async {
    try {
      // Get posting WIF from environment
      final postingWif = dotenv.env['HIVE_POSTING_WIF'] ?? '';
      if (postingWif.isEmpty) {
        throw Exception('HIVE_POSTING_WIF not found in environment variables');
      }

      print('🔐 Starting Hive transaction signing...');

      // 1. Convert WIF to private key
      final privateKey = _wifToPrivateKey(postingWif);
      print('✓ Private key decoded from WIF');

      // 2. Serialize the transaction
      final serializedTransaction = _serializeTransaction(transaction);
      print('✓ Transaction serialized (${serializedTransaction.length} bytes)');

      // 3. Create signing buffer (chain ID + serialized transaction)
      final chainIdBytes = _hexToBytes(_hiveChainId);
      final signingBuffer = Uint8List.fromList([
        ...chainIdBytes,
        ...serializedTransaction,
      ]);
      print('✓ Signing buffer created (${signingBuffer.length} bytes)');

      // 4. Hash the signing buffer
      final hash = sha256.convert(signingBuffer).bytes;
      print('✓ SHA-256 hash computed');

      // 5. Sign the hash
      final signature = _signHash(Uint8List.fromList(hash), privateKey);
      print('✓ Signature generated: ${signature.substring(0, 20)}...');

      // 6. Add signature to transaction
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

  /// --- Private helpers ---

  static Uint8List _wifToPrivateKey(String wif) {
    try {
      final decoded = _base58Decode(wif);
      if (decoded.length != 37) {
        throw Exception('Invalid WIF length: ${decoded.length} (expected 37)');
      }
      final privateKey = decoded.sublist(1, 33);

      // Verify checksum
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

    // Handle leading '1's (which represent leading zeros)
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

    buffer.addAll(_serializeVarint(0)); // extensions (always empty)

    return Uint8List.fromList(buffer);
  }

  static List<int> _serializeOperations(List operations) {
    final buffer = <int>[];
    buffer.addAll(_serializeVarint(operations.length));

    for (final operation in operations) {
      final opList = operation as List;
      final opName = opList[0] as String;
      final opData = opList[1] as Map<String, dynamic>;

      // Operation type ID for custom_json is 18
      buffer.addAll(_serializeVarint(18));
      buffer.addAll(_serializeCustomJsonOperation(opData));
    }
    return buffer;
  }

  static List<int> _serializeCustomJsonOperation(Map<String, dynamic> opData) {
    final buffer = <int>[];

    // required_auths (array of account names)
    final requiredAuths = opData['required_auths'] as List<dynamic>;
    buffer.addAll(_serializeVarint(requiredAuths.length));
    for (final auth in requiredAuths) {
      buffer.addAll(_serializeString(auth as String));
    }

    // required_posting_auths (array of account names)
    final requiredPostingAuths =
        opData['required_posting_auths'] as List<dynamic>;
    buffer.addAll(_serializeVarint(requiredPostingAuths.length));
    for (final auth in requiredPostingAuths) {
      buffer.addAll(_serializeString(auth as String));
    }

    // id (string)
    final id = opData['id'] as String;
    buffer.addAll(_serializeString(id));

    // json (string)
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

  /// Sign a hash using secp256k1 ECDSA with deterministic nonce (RFC 6979)
  static String _signHash(Uint8List hash, Uint8List privateKey) {
    try {
      final secp256k1 = ECDomainParameters('secp256k1');
      final privKey = ECPrivateKey(_bytesToBigInt(privateKey), secp256k1);

      // Use deterministic ECDSA with SHA-256 (RFC 6979)
      // This eliminates need for SecureRandom which can be problematic on web
      final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
      final params = PrivateKeyParameter(privKey);
      signer.init(true, params);

      final ECSignature ecSig = signer.generateSignature(hash) as ECSignature;

      // Normalize signature to low-S form (required by Hive)
      var r = ecSig.r;
      var s = ecSig.s;
      final halfCurveOrder = secp256k1.n >> 1;
      if (s.compareTo(halfCurveOrder) > 0) {
        s = secp256k1.n - s;
      }

      // Calculate recovery ID (determines which public key to recover)
      final recoveryId = _calculateRecoveryId(hash, r, s, privKey, secp256k1);

      // Build compact signature (65 bytes: 1 byte recovery + 32 bytes r + 32 bytes s)
      final rBytes = _bigIntToBytes(r, 32);
      final sBytes = _bigIntToBytes(s, 32);
      
      final compactSig = Uint8List(65);
      compactSig[0] = recoveryId + 31; // Recovery flag (31-34 for compressed keys)
      compactSig.setRange(1, 33, rBytes);
      compactSig.setRange(33, 65, sBytes);

      // Return as hex string
      return compactSig.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } catch (e) {
      throw Exception('Failed to sign hash: $e');
    }
  }

  /// Calculate the correct recovery ID by testing all possibilities
  static int _calculateRecoveryId(
    Uint8List hash,
    BigInt r,
    BigInt s,
    ECPrivateKey privateKey,
    ECDomainParameters curve,
  ) {
    // Derive the public key from private key
    final publicKey = _derivePublicKey(privateKey, curve);
    
    // Test recovery IDs 0-3 to find which one recovers the correct public key
    for (int recoveryId = 0; recoveryId < 4; recoveryId++) {
      try {
        final recovered = _recoverPublicKey(hash, r, s, recoveryId, curve);
        if (recovered != null && 
            recovered.x == publicKey.x && 
            recovered.y == publicKey.y) {
          return recoveryId;
        }
      } catch (e) {
        // Try next recovery ID
        continue;
      }
    }
    
    // Default to 0 if recovery fails (shouldn't happen with valid signature)
    return 0;
  }

  /// Derive public key from private key
  static ECPoint _derivePublicKey(ECPrivateKey privateKey, ECDomainParameters curve) {
    final q = curve.G * privateKey.d;
    return q!;
  }

  /// Recover public key from signature (simplified version for recovery ID calculation)
  static ECPoint? _recoverPublicKey(
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
      
      // Convert fieldSize to BigInt for comparison
      final fieldSize = BigInt.from(curve.curve.fieldSize);
      if (x.compareTo(fieldSize) >= 0) {
        return null;
      }
      
      // Get point on curve with x coordinate
      final R = _decompressPoint(x, (recoveryId & 1) == 1, curve);
      if (R == null || !(R * n)!.isInfinity) {
        return null;
      }
      
      final e = _bytesToBigInt(hash);
      final rInv = r.modInverse(n);
      
      // Q = r^-1 * (s*R - e*G)
      final srInv = (s * rInv) % n;
      final eInv = (n - e) % n;
      final eInvRInv = (eInv * rInv) % n;
      
      final q = (R * srInv)! + (curve.G * eInvRInv)!;
      return q;
    } catch (e) {
      return null;
    }
  }

  /// Decompress an EC point from x coordinate and sign
  static ECPoint? _decompressPoint(BigInt x, bool yBit, ECDomainParameters curve) {
    try {
      final curveEquation = curve.curve as ECCurve;
      // Convert fieldSize to BigInt for all operations
      final fieldSize = BigInt.from(curveEquation.fieldSize);
      
      // Calculate y² = x³ + b (mod p) for secp256k1
      final x3 = x.modPow(BigInt.from(3), fieldSize);
      final bValue = curveEquation.b!.toBigInteger()!;
      final y2 = (x3 + bValue) % fieldSize;
      
      // Calculate y = y²^((p+1)/4) (mod p) - works for p ≡ 3 (mod 4)
      final exponent = (fieldSize + BigInt.one) ~/ BigInt.from(4);
      var y = y2.modPow(exponent, fieldSize);
      
      // Ensure y has correct parity
      if (y.isEven != !yBit) {
        y = fieldSize - y;
      }
      
      return curve.curve.createPoint(x, y);
    } catch (e) {
      return null;
    }
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

  /// Validate a WIF private key
  static bool isValidWif(String wif) {
    try {
      _wifToPrivateKey(wif);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get posting WIF from environment
  static String getPostingWif() {
    return dotenv.env['HIVE_POSTING_WIF'] ?? '';
  }
}