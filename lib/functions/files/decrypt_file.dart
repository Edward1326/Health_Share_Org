import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:health_share_org/services/hive/compare.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pointycastle/export.dart' hide Mac;
import 'package:asn1lib/asn1lib.dart';
import 'package:cryptography/cryptography.dart';
import 'preview_file.dart';

class FileDecryptionService {
  // PERFORMANCE FIX: Use cryptography package for fast AES-GCM decryption
  static final _aesGcm = AesGcm.with256bits();

  static Future<void> previewFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    // 🔥 SHOW LOADING DIALOG IMMEDIATELY - BEFORE ANY PROCESSING
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildLoadingDialog('Preparing file preview...'),
    );

    // Small delay to ensure dialog renders
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];
      final filename = file['filename'] ?? 'Unknown file';
      final mimeType = file['mime_type'] ?? '';

      print('DEBUG: Starting preview for file: $filename');

      if (ipfsCid == null) {
        if (context.mounted) Navigator.pop(context);
        return;
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        if (context.mounted) Navigator.pop(context);
        showSnackBar('Authentication error');
        return;
      }

      _updateLoadingDialog(context, 'Loading user credentials...');

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key, email')
          .eq('email', currentUser.email!)
          .single();

      final actualUserId = userResponse['id'] as String?;
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      if (actualUserId == null || rsaPrivateKeyPem == null) {
        if (context.mounted) Navigator.pop(context);
        return;
      }

      // 🔐 MANDATORY BLOCKCHAIN VERIFICATION
      _updateLoadingDialog(context, 'Verifying blockchain integrity...');

      print('\n🔐 === MANDATORY BLOCKCHAIN VERIFICATION START ===');

      final String hiveUsername = await _getHiveUsername(actualUserId);

      final verificationResult = await HiveCompareServiceWeb.verifyWithDetails(
        fileId: fileId.toString(),
        username: hiveUsername,
      );

      if (!verificationResult.success) {
        print('❌ BLOCKCHAIN VERIFICATION FAILED');
        if (context.mounted) Navigator.pop(context);
        if (context.mounted) {
          await _showVerificationFailedDialogEnhanced(
            context,
            fileId.toString(),
            verificationResult,
          );
        }
        showSnackBar('❌ File cannot be decrypted - verification failed');
        return;
      }

      if (!verificationResult.hashesMatch) {
        print('❌ HASH MISMATCH DETECTED');
        if (context.mounted) Navigator.pop(context);
        if (context.mounted) {
          await _showHashMismatchDialog(
            context,
            verificationResult.supabaseFileHash ?? 'N/A',
            verificationResult.blockchainFileHash ?? 'N/A',
          );
        }
        return;
      }

      print('✅ BLOCKCHAIN VERIFICATION PASSED');
      print('Transaction ID: ${verificationResult.transactionId}');
      print('Block Number: ${verificationResult.blockNumber}');
      print('=== BLOCKCHAIN VERIFICATION END ===\n');

      await _performDecryption(
        context: context,
        fileId: fileId,
        ipfsCid: ipfsCid,
        filename: filename,
        mimeType: mimeType,
        actualUserId: actualUserId,
        rsaPrivateKeyPem: rsaPrivateKeyPem,
        showSnackBar: showSnackBar,
        verificationResult: verificationResult,
      );
    } catch (e, stackTrace) {
      print('ERROR in previewFile: $e');
      print('Stack trace: $stackTrace');
      if (context.mounted) {
        Navigator.pop(context);
        showSnackBar('Error: ${e.toString()}');
      }
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
    required VerificationResult verificationResult,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      _updateLoadingDialog(context, 'Loading encryption keys...');

      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select(
              'id, file_id, recipient_type, recipient_id, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      print('Found ${allFileKeys.length} File_Keys records for file $fileId');

      Map<String, dynamic>? usableKey;

      for (var key in allFileKeys) {
        if (key['recipient_type'] == 'user' &&
            key['recipient_id'] == actualUserId) {
          usableKey = key;
          print('Found direct user key: ${usableKey!['id']}');
          break;
        }
      }

      if (usableKey == null) {
        print('No usable key found');
        if (context.mounted) Navigator.pop(context);
        showSnackBar('No decryption key found for this file');
        return;
      }

      // RSA Decryption with PointyCastle (fast on web)
      _updateLoadingDialog(context, 'Decrypting file keys...');

      print('\n--- ATTEMPTING RSA DECRYPTION ---');
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;

      final decryptedKeyDataJson =
          _decryptWithRSAOAEP(encryptedKeyData, rsaPrivateKeyPem);
      print('✓ PointyCastle RSA decryption successful!');

      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
      final aesKeyBase64 = keyData['key'] as String?;
      final aesNonceBase64 = keyData['nonce'] as String?;

      if (aesKeyBase64 == null) {
        throw Exception('Missing AES key in decrypted data');
      }

      final aesKeyBytes = base64Decode(aesKeyBase64);

      Uint8List nonceBytes;
      if (aesNonceBase64 != null) {
        nonceBytes = base64Decode(aesNonceBase64);
      } else {
        final nonceHex = usableKey['nonce_hex'] as String?;
        if (nonceHex == null || nonceHex.isEmpty) {
          throw Exception('Missing AES nonce');
        }
        nonceBytes = _hexToBytes(nonceHex);
      }

      print(
          '✓ AES key (${aesKeyBytes.length} bytes) and nonce (${nonceBytes.length} bytes) extracted');
      print('  RSA decryption took: ${stopwatch.elapsedMilliseconds}ms');

      // Download file from IPFS
      _updateLoadingDialog(context, 'Downloading file from IPFS...');

      final downloadStart = stopwatch.elapsedMilliseconds;

      final ipfsUrl =
          'https://apricot-delicate-vole-342.mypinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download from IPFS: ${response.statusCode}');
      }

      final encryptedFileBytes = response.bodyBytes;
      final downloadTime = stopwatch.elapsedMilliseconds - downloadStart;
      print(
          '✓ Downloaded ${encryptedFileBytes.length} bytes from IPFS in ${downloadTime}ms');

      // 🔐 VERIFY IPFS FILE INTEGRITY
      _updateLoadingDialog(context, 'Verifying file integrity...');

      print('\n🔐 === VERIFYING IPFS FILE INTEGRITY ===');
      final downloadedFileHash = await _computeSHA256(encryptedFileBytes);
      print('Downloaded file hash: $downloadedFileHash');

      final hiveLogRecord = await Supabase.instance.client
          .from('Hive_Logs')
          .select('file_hash')
          .eq('file_id', fileId)
          .maybeSingle();

      if (hiveLogRecord == null) {
        print('❌ No Hive_Logs record found');
        if (context.mounted) Navigator.pop(context);
        showSnackBar('❌ No blockchain record found for this file');
        return;
      }

      final blockchainConfirmedHash = hiveLogRecord['file_hash'] as String;

      if (downloadedFileHash != blockchainConfirmedHash) {
        print('❌ IPFS FILE INTEGRITY FAILED - Hash mismatch!');
        if (context.mounted) Navigator.pop(context);
        if (context.mounted) {
          await _showIPFSIntegrityFailedDialog(
            context,
            downloadedFileHash,
            blockchainConfirmedHash,
          );
        }
        showSnackBar('❌ Downloaded file is corrupted or tampered');
        return;
      }

      print('✅ IPFS FILE INTEGRITY VERIFIED');

      // DECRYPT FILE
      _updateLoadingDialog(context, 'Decrypting file content...');

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

      // Close loading dialog before showing preview
      if (context.mounted) Navigator.pop(context);

      // Show preview
      if (context.mounted) {
        await _showFilePreview(context, filename, mimeType, decryptedBytes);
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      print(
          'Error in _performDecryption after ${stopwatch.elapsedMilliseconds}ms: $e');
      print('Stack trace: $stackTrace');

      if (context.mounted) {
        Navigator.pop(context);
        showSnackBar('Decryption error: ${e.toString()}');
      }

      rethrow;
    }
  }

  // Helper: Build loading dialog
  static Widget _buildLoadingDialog(String message) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B8E5A)),
                strokeWidth: 4,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2C3E50),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Helper: Update loading dialog message
  static void _updateLoadingDialog(BuildContext context, String message) {
    if (context.mounted) {
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _buildLoadingDialog(message),
      );
    }
  }

  /// Compute SHA-256 hash of file bytes
  static Future<String> _computeSHA256(Uint8List bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');
  }

  static Future<void> _showIPFSIntegrityFailedDialog(
    BuildContext context,
    String downloadedHash,
    String expectedHash,
  ) async {
    const Color errorRed = Color(0xFFDC2626);
    const Color lightRed = Color(0xFFFEF2F2);
    const Color darkText = Color(0xFF2C3E50);
    const Color textGray = Color(0xFF6C757D);
    const Color primaryGreen = Color(0xFF6B8E5A);
    const Color lightGreen = Color(0xFFF5F8F3);
    const Color borderColor = Color(0xFFD5E1CF);

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: errorRed.withOpacity(0.3), width: 2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: lightRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: errorRed,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'IPFS File Corrupted',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: darkText,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: lightRed,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: errorRed.withOpacity(0.3), width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_rounded, color: errorRed, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Downloaded file does not match blockchain record!',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: errorRed,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'The file downloaded from IPFS has been modified or corrupted. The hash does not match the immutable blockchain record.',
                style: TextStyle(fontSize: 14, color: textGray, height: 1.5),
              ),
              const SizedBox(height: 20),
              Text(
                'Hash Comparison:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: darkText,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_download_rounded,
                            color: primaryGreen, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Downloaded from IPFS:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: SelectableText(
                        downloadedHash,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: textGray,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.link_rounded, color: primaryGreen, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Expected (Blockchain):',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: SelectableText(
                        expectedHash,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: textGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange[300]!, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Colors.orange[700], size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The IPFS storage may have been compromised. Contact your system administrator.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: errorRed,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Close',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
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
        throw Exception(
            'Combined data too short (${combinedData.length} bytes)');
      }

      // Separate ciphertext and MAC
      // Format: [ciphertext][16-byte MAC]
      final cipherText = combinedData.sublist(0, combinedData.length - 16);
      final macBytes = combinedData.sublist(combinedData.length - 16);

      print(
          '  Separated: ciphertext=${cipherText.length}B, MAC=${macBytes.length}B');

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
      final secretBox =
          SecretBox(encryptedData, nonce: nonceBytes, mac: Mac.empty);
      final decryptedData =
          await _aesGcm.decrypt(secretBox, secretKey: secretKey);
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

        final secretBox =
            SecretBox(cipherText, nonce: nonceBytes, mac: Mac(macBytes));
        final decryptedData =
            await _aesGcm.decrypt(secretBox, secretKey: secretKey);
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

    final modulus =
        (privateKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
    final privateExponent =
        (privateKeySeq.elements[3] as ASN1Integer).valueAsBigInteger;
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

  static String _decryptWithRSAOAEP(
      String encryptedData, String privateKeyPem) {
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

  static String _decryptWithRSAPKCS1v15(
      String encryptedData, String privateKeyPem) {
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
    // Theme colors - Green medical theme
    const Color primaryGreen = Color(0xFF6B8E5A);
    const Color lightGreen = Color(0xFFF5F8F3);
    const Color darkText = Color(0xFF2C3E50);
    const Color textGray = Color(0xFF6C757D);
    const Color borderColor = Color(0xFFD5E1CF);
    const Color errorRed = Color(0xFFDC2626);
    const Color lightRed = Color(0xFFFEF2F2);

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: errorRed.withOpacity(0.3), width: 2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: lightRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.security,
                color: errorRed,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Security Verification Failed',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: darkText,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: lightRed,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: errorRed.withOpacity(0.3), width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.block_rounded,
                      color: errorRed,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'This file cannot be decrypted',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: errorRed,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Security verification has failed. The file cannot be accessed due to integrity concerns.',
                style: TextStyle(
                  fontSize: 14,
                  color: textGray,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Possible reasons:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: darkText,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReasonRow(
                        Icons.storage_rounded,
                        'File data has been tampered with in database',
                        textGray),
                    const SizedBox(height: 10),
                    _buildReasonRow(Icons.link_off_rounded,
                        'File was not properly logged to blockchain', textGray),
                    const SizedBox(height: 10),
                    _buildReasonRow(Icons.broken_image_rounded,
                        'Blockchain record is missing or corrupted', textGray),
                    const SizedBox(height: 10),
                    _buildReasonRow(
                        Icons.wifi_off_rounded,
                        'Network connectivity issues with blockchain',
                        textGray),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange[300]!, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.orange[700],
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Contact your system administrator for assistance.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: errorRed,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Understood',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildReasonRow(IconData icon, String text, Color textColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: textColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  static Widget _buildDetailRow(String label, String value, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: textColor,
          ),
        ),
      ],
    );
  }

  static Future<void> _showHashMismatchDialog(
    BuildContext context,
    String supabaseHash,
    String blockchainHash,
  ) async {
    // Theme colors - Green medical theme
    const Color primaryGreen = Color(0xFF6B8E5A);
    const Color lightGreen = Color(0xFFF5F8F3);
    const Color darkText = Color(0xFF2C3E50);
    const Color textGray = Color(0xFF6C757D);
    const Color borderColor = Color(0xFFD5E1CF);
    const Color errorRed = Color(0xFFDC2626);
    const Color lightRed = Color(0xFFFEF2F2);

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: errorRed.withOpacity(0.3), width: 2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: lightRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: errorRed,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'File Integrity Compromised',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: darkText,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: lightRed,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: errorRed.withOpacity(0.3), width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      color: errorRed,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'CRITICAL: Hash mismatch detected!',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: errorRed,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'The file hash stored in the database does not match the blockchain record. This indicates potential tampering or corruption.',
                style: TextStyle(
                  fontSize: 14,
                  color: textGray,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Hash Comparison:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: darkText,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storage_rounded,
                            color: primaryGreen, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Database Hash:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: SelectableText(
                        supabaseHash,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: textGray,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.link_rounded, color: primaryGreen, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Blockchain Hash:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: SelectableText(
                        blockchainHash,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: textGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange[300]!, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.orange[700],
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Do not use this file. Contact your system administrator immediately.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: errorRed,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Close',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
