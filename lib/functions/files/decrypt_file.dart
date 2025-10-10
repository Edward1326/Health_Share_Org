import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:fast_rsa/fast_rsa.dart';
import 'package:health_share_org/services/hive/compare.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pointycastle/export.dart' hide Mac;
import 'package:asn1lib/asn1lib.dart';
import 'package:cryptography/cryptography.dart';
import 'file_preview.dart';

class FileDecryptionService {
  // PERFORMANCE FIX: Use cryptography package for fast AES-GCM decryption
  static final _aesGcm = AesGcm.with256bits();

  static Future<void> previewFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    try {
      showSnackBar('Loading file preview...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];
      final filename = file['filename'] ?? 'Unknown file';
      final mimeType = file['mime_type'] ?? '';

      print('DEBUG: Starting preview for file: $filename');

      if (ipfsCid == null) {
        showSnackBar('IPFS CID not found');
        return;
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        showSnackBar('Authentication error');
        return;
      }

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key, email')
          .eq('email', currentUser.email!)
          .single();

      final actualUserId = userResponse['id'] as String?;
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      if (actualUserId == null || rsaPrivateKeyPem == null) {
        showSnackBar('User authentication error');
        return;
      }

      // 🔐 MANDATORY BLOCKCHAIN VERIFICATION
      print('\n🔐 === MANDATORY BLOCKCHAIN VERIFICATION START ===');
      showSnackBar('Verifying file integrity on blockchain...');

      final String hiveUsername = await _getHiveUsername(actualUserId);

      final verificationResult = await HiveCompareServiceWeb.verifyWithDetails(
        fileId: fileId.toString(),
        username: hiveUsername,
      );

      if (!verificationResult.success) {
        print('❌ BLOCKCHAIN VERIFICATION FAILED');
        await _showVerificationFailedDialogEnhanced(
          context, 
          fileId.toString(),
          verificationResult,
        );
        showSnackBar('❌ File cannot be decrypted - verification failed');
        return;
      }

      if (!verificationResult.hashesMatch) {
        print('❌ HASH MISMATCH DETECTED');
        await _showHashMismatchDialog(
          context,
          verificationResult.supabaseFileHash ?? 'N/A',
          verificationResult.blockchainFileHash ?? 'N/A',
        );
        showSnackBar('❌ File corrupted - hash mismatch detected');
        return;
      }

      print('✅ BLOCKCHAIN VERIFICATION PASSED');
      print('Transaction ID: ${verificationResult.transactionId}');
      print('Block Number: ${verificationResult.blockNumber}');
      print('=== BLOCKCHAIN VERIFICATION END ===\n');
      
      showSnackBar('✓ Blockchain verification passed');

      await _performDecryption(
        context: context,
        fileId: fileId,
        ipfsCid: ipfsCid,
        filename: filename,
        mimeType: mimeType,
        actualUserId: actualUserId,
        rsaPrivateKeyPem: rsaPrivateKeyPem,
        showSnackBar: showSnackBar,
      );

    } catch (e, stackTrace) {
      print('ERROR in previewFile: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error previewing file: $e');
    }
  }

  static Future<void> _performDecryption({
    required BuildContext context,
    required dynamic fileId,
    required String ipfsCid,
    required String filename,
    required String mimeType,
    required String actualUserId,
    required String rsaPrivateKeyPem,
    required Function(String) showSnackBar,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, file_id, recipient_type, recipient_id, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      print('Found ${allFileKeys.length} File_Keys records for file $fileId');

      Map<String, dynamic>? usableKey;
      
      for (var key in allFileKeys) {
        if (key['recipient_type'] == 'user' && key['recipient_id'] == actualUserId) {
          usableKey = key;
          print('Found direct user key: ${usableKey!['id']}');
          break;
        }
      }

      if (usableKey == null) {
        print('No usable key found');
        showSnackBar('No decryption key found for this file');
        return;
      }

      // RSA Decryption with PointyCastle (fast on web)
      print('\n--- ATTEMPTING RSA DECRYPTION ---');
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      
      showSnackBar('Decrypting encryption key...');
      
      final decryptedKeyDataJson = _decryptWithRSAOAEP(encryptedKeyData, rsaPrivateKeyPem);
      print('✓ PointyCastle RSA decryption successful!');

      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
      final aesKeyBase64 = keyData['key'] as String?;
      final aesNonceBase64 = keyData['nonce'] as String?;

      if (aesKeyBase64 == null) {
        throw Exception('Missing AES key in decrypted data');
      }

      // PERFORMANCE FIX: Convert to bytes directly (no hex conversion needed)
      final aesKeyBytes = base64Decode(aesKeyBase64);
      
      Uint8List nonceBytes;
      if (aesNonceBase64 != null) {
        nonceBytes = base64Decode(aesNonceBase64);
      } else {
        // Fallback to nonce_hex if nonce not in JSON
        final nonceHex = usableKey['nonce_hex'] as String?;
        if (nonceHex == null || nonceHex.isEmpty) {
          throw Exception('Missing AES nonce');
        }
        nonceBytes = _hexToBytes(nonceHex);
      }

      print('✓ AES key (${aesKeyBytes.length} bytes) and nonce (${nonceBytes.length} bytes) extracted');
      print('  RSA decryption took: ${stopwatch.elapsedMilliseconds}ms');

      // Download file from IPFS
      showSnackBar('Downloading encrypted file from IPFS...');
      final downloadStart = stopwatch.elapsedMilliseconds;
      
      final ipfsUrl = 'https://apricot-delicate-vole-342.mypinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download from IPFS: ${response.statusCode}');
      }

      final encryptedFileBytes = response.bodyBytes;
      final downloadTime = stopwatch.elapsedMilliseconds - downloadStart;
      print('✓ Downloaded ${encryptedFileBytes.length} bytes from IPFS in ${downloadTime}ms');

      // PERFORMANCE FIX: Use native cryptography package for AES-GCM (SUPER FAST!)
      showSnackBar('Decrypting file...');
      final decryptStart = stopwatch.elapsedMilliseconds;
      
      final decryptedBytes = await _fastDecryptFile(
        encryptedFileBytes,
        aesKeyBytes,
        nonceBytes,
      );

      final decryptTime = stopwatch.elapsedMilliseconds - decryptStart;
      stopwatch.stop();
      
      print('✅ File decrypted successfully!');
      print('  Decrypted size: ${decryptedBytes.length} bytes');
      print('  Decryption took: ${decryptTime}ms');
      print('  Total time: ${stopwatch.elapsedMilliseconds}ms');

      // Show preview
      showSnackBar('✓ File decrypted in ${stopwatch.elapsedMilliseconds}ms!');
      await _showFilePreview(context, filename, mimeType, decryptedBytes);

    } catch (e, stackTrace) {
      stopwatch.stop();
      print('Error in _performDecryption after ${stopwatch.elapsedMilliseconds}ms: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Decryption failed: ${e.toString()}');
      rethrow;
    }
  }

  // =====================================================
  // PERFORMANCE FIX: Fast AES-GCM Decryption
  // =====================================================
  
  /// Fast decryption using native cryptography package (same as mobile app)
  /// This is MUCH faster than custom AESHelper implementation
  static Future<Uint8List> _fastDecryptFile(
    Uint8List combinedData,
    List<int> aesKeyBytes,
    List<int> nonceBytes,
  ) async {
    try {
      print('Fast AES-GCM decryption starting...');
      print('  Combined data: ${combinedData.length} bytes');
      print('  AES key: ${aesKeyBytes.length} bytes');
      print('  Nonce: ${nonceBytes.length} bytes');

      // Check minimum size (at least 16 bytes for MAC)
      if (combinedData.length < 16) {
        throw Exception('Combined data too short (${combinedData.length} bytes)');
      }

      // Separate ciphertext and MAC
      // Format: [ciphertext][16-byte MAC]
      final cipherText = combinedData.sublist(0, combinedData.length - 16);
      final macBytes = combinedData.sublist(combinedData.length - 16);

      print('  Separated: ciphertext=${cipherText.length}B, MAC=${macBytes.length}B');

      // Create SecretKey and SecretBox
      final secretKey = SecretKey(aesKeyBytes);
      final secretBox = SecretBox(
        cipherText,
        nonce: nonceBytes,
        mac: Mac(macBytes),
      );

      // Decrypt using native AES-GCM (FAST!)
      final decryptedData = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      print('✓ Fast decryption successful!');
      return Uint8List.fromList(decryptedData);
      
    } catch (e) {
      print('❌ Fast decryption failed: $e');
      
      // Try fallback methods for backward compatibility
      print('Attempting fallback decryption methods...');
      return await _fallbackDecryption(combinedData, aesKeyBytes, nonceBytes);
    }
  }

  /// Fallback decryption for backward compatibility
  static Future<Uint8List> _fallbackDecryption(
    Uint8List encryptedData,
    List<int> aesKeyBytes,
    List<int> nonceBytes,
  ) async {
    final secretKey = SecretKey(aesKeyBytes);

    // Method 1: Try with Mac.empty (for old data without proper MAC)
    try {
      print('Trying Mac.empty fallback...');
      final secretBox = SecretBox(encryptedData, nonce: nonceBytes, mac: Mac.empty);
      final decryptedData = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
      print('✓ Mac.empty fallback successful!');
      return Uint8List.fromList(decryptedData);
    } catch (e) {
      print('Mac.empty failed: $e');
    }

    // Method 2: Try assuming MAC is at the beginning
    try {
      if (encryptedData.length > 16) {
        print('Trying MAC-at-beginning fallback...');
        final macBytes = encryptedData.sublist(0, 16);
        final cipherText = encryptedData.sublist(16);
        
        final secretBox = SecretBox(cipherText, nonce: nonceBytes, mac: Mac(macBytes));
        final decryptedData = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
        print('✓ MAC-at-beginning fallback successful!');
        return Uint8List.fromList(decryptedData);
      }
    } catch (e) {
      print('MAC-at-beginning failed: $e');
    }

    throw Exception('All decryption methods failed');
  }

  // =====================================================
  // PointyCastle RSA Decryption Methods
  // =====================================================
  
  static RSAPrivateKey _parseRSAPrivateKeyFromPem(String pem) {
    try {
      final cleanPem = pem.trim();
      
      bool isPkcs1 = cleanPem.contains('-----BEGIN RSA PRIVATE KEY-----');
      bool isPkcs8 = cleanPem.contains('-----BEGIN PRIVATE KEY-----');
      
      if (!isPkcs1 && !isPkcs8) {
        throw FormatException('Invalid PEM format');
      }
      
      String lines;
      if (isPkcs1) {
        lines = cleanPem
            .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
            .replaceAll('-----END RSA PRIVATE KEY-----', '')
            .replaceAll(RegExp(r'\s+'), '')
            .trim();
      } else {
        lines = cleanPem
            .replaceAll('-----BEGIN PRIVATE KEY-----', '')
            .replaceAll('-----END PRIVATE KEY-----', '')
            .replaceAll(RegExp(r'\s+'), '')
            .trim();
      }
      
      final keyBytes = base64Decode(lines);
      
      if (isPkcs1) {
        return _parsePKCS1PrivateKey(keyBytes);
      } else {
        return _parsePKCS8PrivateKey(keyBytes);
      }
    } catch (e) {
      print('Error parsing RSA private key: $e');
      rethrow;
    }
  }

  static RSAPrivateKey _parsePKCS1PrivateKey(Uint8List keyBytes) {
    final privateKeyParser = ASN1Parser(keyBytes);
    final privateKeySeq = privateKeyParser.nextObject() as ASN1Sequence;
    
    if (privateKeySeq.elements.length < 6) {
      throw FormatException('Invalid PKCS#1 private key structure');
    }
    
    final modulus = (privateKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
    final privateExponent = (privateKeySeq.elements[3] as ASN1Integer).valueAsBigInteger;
    final p = (privateKeySeq.elements[4] as ASN1Integer).valueAsBigInteger;
    final q = (privateKeySeq.elements[5] as ASN1Integer).valueAsBigInteger;
    
    if (modulus == null || privateExponent == null || p == null || q == null) {
      throw FormatException('Failed to extract RSA key components');
    }
    
    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  static RSAPrivateKey _parsePKCS8PrivateKey(Uint8List keyBytes) {
    final asn1Parser = ASN1Parser(keyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    
    if (topLevelSeq.elements.length < 3) {
      throw FormatException('Invalid PKCS#8 structure');
    }
    
    final privateKeyBitString = topLevelSeq.elements[2] as ASN1OctetString;
    final privateKeyBytes = privateKeyBitString.contentBytes();
    
    return _parsePKCS1PrivateKey(privateKeyBytes);
  }

  static String _decryptWithRSAOAEP(String encryptedData, String privateKeyPem) {
    try {
      final privateKey = _parseRSAPrivateKeyFromPem(privateKeyPem);
      
      // Try SHA-256 first (modern standard)
      try {
        final cipher = OAEPEncoding.withCustomDigest(
          () => SHA256Digest(),
          RSAEngine(),
        );
        cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
        
        final encryptedBytes = base64Decode(encryptedData);
        final decryptedBytes = cipher.process(encryptedBytes);
        final decryptedString = utf8.decode(decryptedBytes);
        
        return decryptedString;
        
      } catch (sha256Error) {
        print('SHA-256 OAEP failed, trying SHA-1: $sha256Error');
        
        final cipher = OAEPEncoding.withCustomDigest(
          () => SHA1Digest(),
          RSAEngine(),
        );
        cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
        
        final encryptedBytes = base64Decode(encryptedData);
        final decryptedBytes = cipher.process(encryptedBytes);
        final decryptedString = utf8.decode(decryptedBytes);
        
        return decryptedString;
      }
    } catch (e) {
      print('RSA-OAEP failed, trying PKCS1v15 fallback: $e');
      return _decryptWithRSAPKCS1v15(encryptedData, privateKeyPem);
    }
  }

  static String _decryptWithRSAPKCS1v15(String encryptedData, String privateKeyPem) {
    try {
      final privateKey = _parseRSAPrivateKeyFromPem(privateKeyPem);
      final cipher = PKCS1Encoding(RSAEngine());
      cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      
      final encryptedBytes = base64Decode(encryptedData);
      final decryptedBytes = cipher.process(encryptedBytes);
      final decryptedString = utf8.decode(decryptedBytes);
      
      return decryptedString;
    } catch (e) {
      print('PKCS1v15 decryption error: $e');
      rethrow;
    }
  }

  // =====================================================
  // Helper Methods
  // =====================================================

  static Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  static Future<String> _getHiveUsername(String userId) async {
    final envUsername = dotenv.env['HIVE_ACCOUNT_NAME'];
    
    if (envUsername == null || envUsername.isEmpty) {
      throw Exception('HIVE_ACCOUNT_NAME not found in .env file');
    }
    
    return envUsername;
  }

  // =====================================================
  // File Preview Method
  // =====================================================

  static Future<void> _showFilePreview(
    BuildContext context,
    String filename,
    String mimeType,
    Uint8List decryptedBytes,
  ) async {
    // Use fullscreen preview for better viewing experience
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullscreenFilePreviewWeb(
          fileName: filename,
          bytes: decryptedBytes,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  // =====================================================
  // Dialog Methods
  // =====================================================

  static Future<void> _showVerificationFailedDialogEnhanced(
    BuildContext context,
    String fileId,
    VerificationResult result,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Text('Security Verification Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This file cannot be decrypted due to security verification failure.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Possible reasons:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('• File data has been tampered with in database'),
            const Text('• File was not properly logged to blockchain'),
            const Text('• Blockchain record is missing or corrupted'),
            const Text('• Network connectivity issues with blockchain'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('File ID: $fileId', style: const TextStyle(fontSize: 12)),
                  if (result.error != null)
                    Text('Error: ${result.error}', style: const TextStyle(fontSize: 12)),
                  if (result.transactionId != null)
                    Text('Tx ID: ${result.transactionId}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  static Future<void> _showHashMismatchDialog(
    BuildContext context,
    String supabaseHash,
    String blockchainHash,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Text('File Integrity Compromised'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CRITICAL: File hash mismatch detected!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'The file hash stored in the database does not match the blockchain record.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Database Hash:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(supabaseHash, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  const SizedBox(height: 8),
                  const Text('Blockchain Hash:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(blockchainHash, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}