import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:fast_rsa/fast_rsa.dart';
import 'package:health_share_org/services/aes_helper.dart';
import 'package:health_share_org/services/hive/compare.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pointycastle/export.dart' hide Mac;
import 'package:asn1lib/asn1lib.dart';
import 'package:cryptography/cryptography.dart';

class FileDecryptionService {
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

      // RSA Decryption with PointyCastle fallback
      print('\n--- ATTEMPTING RSA DECRYPTION ---');
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      
      String decryptedKeyDataJson;
      
      // FOR WEB: Use PointyCastle directly (fast_rsa has timeout issues on web)
      print('WEB PLATFORM: Using PointyCastle for RSA decryption...');
      showSnackBar('Decrypting encryption key...');
      
      try {
        decryptedKeyDataJson = _decryptWithRSAOAEP(encryptedKeyData, rsaPrivateKeyPem);
        print('✓ PointyCastle RSA decryption successful!');
      } catch (pointyCastleError) {
        print('PointyCastle decryption failed: $pointyCastleError');
        showSnackBar('RSA decryption failed: ${pointyCastleError.toString()}');
        return;
      }

      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
      final aesKeyBase64 = keyData['key'] as String?;
      final aesNonceBase64 = keyData['nonce'] as String?;

      if (aesKeyBase64 == null) {
        throw Exception('Missing AES key in decrypted data');
      }

      // Convert base64 to hex for AESHelper
      final aesKeyBytes = base64Decode(aesKeyBase64);
      final aesKeyHex = aesKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      String aesNonceHex;
      if (aesNonceBase64 != null) {
        final aesNonceBytes = base64Decode(aesNonceBase64);
        aesNonceHex = aesNonceBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } else {
        aesNonceHex = usableKey['nonce_hex'] as String? ?? '';
      }

      if (aesNonceHex.isEmpty) {
        throw Exception('Missing AES nonce');
      }

      print('AES key and nonce extracted successfully');

      // Download file from IPFS
      showSnackBar('Downloading encrypted file from IPFS...');
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download from IPFS: ${response.statusCode}');
      }

      final encryptedFileBytes = response.bodyBytes;
      print('Downloaded ${encryptedFileBytes.length} bytes from IPFS');

      // Decrypt the file
      showSnackBar('Decrypting file...');
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(encryptedFileBytes);

      print('File decrypted successfully: ${decryptedBytes.length} bytes');

      // Show preview
      showSnackBar('✓ File decrypted successfully!');
      await _showFilePreview(context, filename, mimeType, decryptedBytes);

    } catch (e, stackTrace) {
      print('Error in _performDecryption: $e');
      print('Stack trace: $stackTrace');
      throw e;
    }
  }

  // =====================================================
  // PointyCastle RSA Decryption Methods (Fallback)
  // =====================================================
  
  static RSAPrivateKey _parseRSAPrivateKeyFromPem(String pem) {
    try {
      print('Parsing RSA private key from PEM...');
      
      final cleanPem = pem.trim();
      
      bool isPkcs1 = cleanPem.contains('-----BEGIN RSA PRIVATE KEY-----');
      bool isPkcs8 = cleanPem.contains('-----BEGIN PRIVATE KEY-----');
      
      if (!isPkcs1 && !isPkcs8) {
        throw FormatException('Invalid PEM format - missing proper headers');
      }
      
      String lines;
      if (isPkcs1) {
        print('Detected PKCS#1 format');
        lines = cleanPem
            .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
            .replaceAll('-----END RSA PRIVATE KEY-----', '')
            .replaceAll(RegExp(r'\s+'), '')
            .trim();
      } else {
        print('Detected PKCS#8 format');
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
      print('Error parsing RSA private key from PEM: $e');
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
    
    print('PKCS#1 RSA private key parsed - Modulus bits: ${modulus.bitLength}');
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
      print('Starting RSA-OAEP decryption with PointyCastle...');
      
      final privateKey = _parseRSAPrivateKeyFromPem(privateKeyPem);
      
      // Try SHA-256 first (modern standard)
      try {
        print('Attempting RSA-OAEP with SHA-256...');
        
        final cipher = OAEPEncoding.withCustomDigest(
          () => SHA256Digest(),
          RSAEngine(),
        );
        
        cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
        
        final encryptedBytes = base64Decode(encryptedData);
        final decryptedBytes = cipher.process(encryptedBytes);
        final decryptedString = utf8.decode(decryptedBytes);
        
        print('✓ RSA-OAEP SHA-256 decryption successful!');
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
        
        print('✓ RSA-OAEP SHA-1 decryption successful!');
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
      
      print('✓ PKCS1v15 decryption successful!');
      return decryptedString;
    } catch (e) {
      print('PKCS1v15 decryption error: $e');
      rethrow;
    }
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

  // =====================================================
  // Helper Methods
  // =====================================================

  static Future<String> _getHiveUsername(String userId) async {
    final envUsername = dotenv.env['HIVE_ACCOUNT_NAME'];
    
    if (envUsername == null || envUsername.isEmpty) {
      throw Exception('HIVE_ACCOUNT_NAME not found in .env file');
    }
    
    print('Using Hive username: $envUsername');
    return envUsername;
  }
  
  static Future<void> _showFilePreview(
    BuildContext context,
    String filename,
    String mimeType,
    Uint8List decryptedBytes,
  ) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.9,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        filename,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: _buildPreviewContent(mimeType, decryptedBytes, filename),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildPreviewContent(String mimeType, Uint8List bytes, String filename) {
    final extension = filename.toLowerCase().split('.').last;
    
    if (mimeType.startsWith('image/') || 
        ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      return _buildImagePreview(bytes);
    }
    
    if (mimeType.startsWith('text/') || 
        ['txt', 'md', 'json', 'xml', 'csv', 'log'].contains(extension)) {
      return _buildTextPreview(bytes);
    }
    
    if (mimeType == 'application/pdf' || extension == 'pdf') {
      return _buildPdfPreview(bytes);
    }
    
    if (['dart', 'js', 'html', 'css', 'py', 'java', 'cpp', 'c', 'h'].contains(extension)) {
      return _buildCodePreview(bytes, extension);
    }
    
    return _buildDefaultPreview(bytes, mimeType, filename);
  }

  static Widget _buildImagePreview(Uint8List bytes) {
    return Center(
      child: SingleChildScrollView(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text('Failed to load image'),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _buildTextPreview(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      return SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
      );
    } catch (e) {
      return _buildErrorPreview('Failed to decode text: $e');
    }
  }

  static Widget _buildCodePreview(Uint8List bytes, String extension) {
    try {
      final code = utf8.decode(bytes);
      return SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: Colors.green,
            ),
          ),
        ),
      );
    } catch (e) {
      return _buildErrorPreview('Failed to decode code: $e');
    }
  }

  static Widget _buildPdfPreview(Uint8List bytes) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text(
          'PDF Preview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('Size: ${_formatFileSize(bytes.length)}'),
        const SizedBox(height: 16),
        const Text(
          'PDF preview is not available in this interface.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  static Widget _buildDefaultPreview(Uint8List bytes, String mimeType, String filename) {
    final extension = filename.split('.').last.toUpperCase();
    
    return SingleChildScrollView(
      child: Column(
        children: [
          Icon(Icons.insert_drive_file, size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            extension,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            filename,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text('Type: $mimeType'),
          Text('Size: ${_formatFileSize(bytes.length)}'),
          const SizedBox(height: 16),
          const Text(
            'Preview not available for this file type.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  static Widget _buildErrorPreview(String error) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text(
          'Preview Error',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ],
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}