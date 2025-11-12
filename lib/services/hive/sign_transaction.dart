import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' show hex;
import 'package:bs58/bs58.dart' as bs58;
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HiveTransactionSignerWeb {
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

      print('🔐 Starting transaction signing...');

      // 1. Convert WIF to private key (32 bytes)
      final privateKeyBytes = _wifToPrivateKey(postingWif);
      print('✓ WIF decoded successfully');

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
      final hashBytes = sha256.convert(signingBuffer).bytes;
      final hash = Uint8List.fromList(hashBytes);
      print('✓ Hash computed: ${hex.encode(hash)}');

      // 5. Sign the hash (returns Hive compact hex string)
      final signature = _signHash(hash, privateKeyBytes);
      print('✓ Signature created: ${signature.substring(0, 20)}...');

      // 6. Attach signature and return
      final signedTransaction = Map<String, dynamic>.from(transaction);
      signedTransaction['signatures'] = [signature];

      print('✅ Transaction signed successfully!');
      return signedTransaction;
    } catch (e, stackTrace) {
      print('❌ Signing failed: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to sign transaction: $e');
    }
  }

  // ---------------- WIF decoding ----------------
  static Uint8List _wifToPrivateKey(String wif) {
    try {
      // Use the top-level decode function which handles Base58
      final decoded = bs58.base58.decode(wif);

      if (decoded.length != 37 && decoded.length != 38) {
        throw Exception('Invalid WIF length: ${decoded.length}');
      }

      final payloadLen = decoded.length - 4;
      final payload = decoded.sublist(0, payloadLen);
      final checksum = decoded.sublist(payloadLen);

      final hash1 = sha256.convert(payload).bytes;
      final hash2 = sha256.convert(hash1).bytes;
      final expected = hash2.sublist(0, 4);
      if (!_listEquals(checksum, expected)) {
        throw Exception('Invalid WIF checksum');
      }

      if (payload[0] != 0x80) {
        throw Exception('Invalid WIF version byte: ${payload[0]}');
      }

      final priv = payload.sublist(1, 33);

      if (payloadLen == 34 && payload[33] != 0x01) {
        throw Exception('Invalid compressed flag in WIF');
      }

      return Uint8List.fromList(priv);
    } catch (e) {
      throw Exception('Failed to decode WIF: $e');
    }
  }

  // ---------------- Signing (secp256k1 + recovery ID 0..3) ----------------
  static String _signHash(Uint8List hash, Uint8List privateKeyBytes) {
    try {
      final params = ECDomainParameters('secp256k1');
      final d = _bytesToBigInt(privateKeyBytes);
      final privKey = ECPrivateKey(d, params);
      final Q = (params.G * d)!;
      final pubKeyBytes = _encodePublicKey(Q, true);
      print('🔑 Public key: ${hex.encode(pubKeyBytes)}');

      // Use a deterministic signer (RFC 6979) with HMAC-SHA256
      final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
      signer.init(true, PrivateKeyParameter(privKey));

      // Loop to find a canonical signature that produces a valid recovery ID
      int recoveryId = -1;
      ECSignature signature;

      for (int i = 0; i < 4; i++) {
        // Note: In a real deterministic signer, k is fixed. Here we regenerate
        // to find a suitable signature, which is a common practice for recovery.
        signature = signer.generateSignature(hash) as ECSignature;

        // Normalize s to low-S form
        if (signature.s.compareTo(params.n >> 1) > 0) {
          signature = ECSignature(signature.r, params.n - signature.s);
          print('📝 Normalized s to low-S form');
        }

        // Try to recover the public key with the current signature
        for (int j = 0; j < 4; j++) {
          final recoveredPubKey = _recoverPublicKey(
            hash,
            signature.r,
            signature.s,
            j,
            params,
          );
          if (recoveredPubKey != null) {
            print(
              '🔍 Recovery attempt (sig $i, recId $j): ${hex.encode(recoveredPubKey).substring(0, 20)}...',
            );
            if (_listEquals(recoveredPubKey, pubKeyBytes)) {
              recoveryId = j;
              print('✅ Found matching recovery ID: $j');
              break;
            }
          }
        }
        if (recoveryId != -1) {
          // We found the right signature and recovery ID, break the outer loop
          final rBytes = _bigIntToBytes(signature.r, 32);
          final sBytes = _bigIntToBytes(signature.s, 32);

          print(
            '📊 Final Signature r: ${hex.encode(rBytes).substring(0, 16)}...',
          );
          print(
            '📊 Final Signature s: ${hex.encode(sBytes).substring(0, 16)}...',
          );

          final compactSig = Uint8List(65);
          compactSig[0] = (31 + recoveryId);
          compactSig.setRange(1, 33, rBytes);
          compactSig.setRange(33, 65, sBytes);

          return hex.encode(compactSig);
        }
      }

      throw Exception('Failed to compute a valid signature and recovery ID');
    } catch (e, stackTrace) {
      print('💥 Sign hash error: $e');
      print('Stack: $stackTrace');
      throw Exception('Failed to sign hash: $e');
    }
  }

  // Recover public key from signature - SIMPLIFIED & CORRECTED
  static Uint8List? _recoverPublicKey(
    Uint8List hash,
    BigInt r,
    BigInt s,
    int recoveryId,
    ECDomainParameters params,
  ) {
    try {
      final n = params.n;
      final G = params.G;
      final curve = params.curve;

      // 1. Calculate x coordinate from r
      final i = BigInt.from(recoveryId >> 1);
      final x = r + (i * n);

      // 2. Decompress point R from x
      final R = curve.decompressPoint(recoveryId & 1, x);

      // 3. Calculate message hash 'e'
      final e = _bytesToBigInt(hash);

      // 4. Calculate Q = r^-1 * (s*R - e*G)
      final rInv = r.modInverse(n);
      final Q = ((R * s)! - (G * e)!)! * rInv;

      if (Q == null || Q.isInfinity) return null;

      return _encodePublicKey(Q, true);
    } catch (e) {
      return null;
    }
  }

  // Encode public key to compressed format
  static Uint8List _encodePublicKey(ECPoint point, bool compressed) {
    return point.getEncoded(compressed);
  }

  // ---------------- Serialization helpers (Unchanged) ----------------
  static Uint8List _serializeTransaction(Map<String, dynamic> transaction) {
    final buffer = <int>[];
    buffer.addAll(_serializeUint16(transaction['ref_block_num'] as int));
    buffer.addAll(_serializeUint32(transaction['ref_block_prefix'] as int));
    final expirationTimestamp = DateTime.parse(
          (transaction['expiration'] as String) + 'Z',
        ).millisecondsSinceEpoch ~/
        1000;
    buffer.addAll(_serializeUint32(expirationTimestamp));
    buffer.addAll(_serializeOperations(transaction['operations'] as List));
    buffer.addAll(_serializeVarint(0));
    return Uint8List.fromList(buffer);
  }

  static List<int> _serializeOperations(List operations) {
    final buffer = <int>[];
    buffer.addAll(_serializeVarint(operations.length));
    for (final operation in operations) {
      final opList = operation as List;
      buffer.addAll(_serializeVarint(18)); // custom_json op id
      buffer.addAll(
        _serializeCustomJsonOperation(opList[1] as Map<String, dynamic>),
      );
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
    buffer.addAll(_serializeString(opData['id'] as String));
    buffer.addAll(_serializeString(opData['json'] as String));
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

  static List<int> _serializeUint16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

  static List<int> _serializeUint32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

  // ---------------- Utility helpers ----------------
  static Uint8List _hexToBytes(String hexStr) =>
      Uint8List.fromList(hex.decode(hexStr));

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    String hexStr = value.toRadixString(16);
    if (hexStr.length > length * 2) {
      throw Exception('BigInt is too large for the specified length');
    }
    hexStr = hexStr.padLeft(length * 2, '0');
    return _hexToBytes(hexStr);
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    return BigInt.parse(hex.encode(bytes), radix: 16);
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
}
