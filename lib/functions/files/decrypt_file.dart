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

class FileDecryptionService {
  // CRITICAL: Remove skipVerification parameter - verification should NEVER be optional
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

      // Get current user from auth
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        showSnackBar('Authentication error');
        return;
      }

      // Get the User record by email
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key, email')
          .eq('email', currentUser.email!)
          .single();

      final actualUserId = userResponse['id'] as String?;
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;
      final userEmail = userResponse['email'] as String;

      if (actualUserId == null || rsaPrivateKeyPem == null) {
        showSnackBar('User authentication error');
        return;
      }

      // 🔐 MANDATORY BLOCKCHAIN VERIFICATION - NO BYPASS ALLOWED
      print('\n🔐 === MANDATORY BLOCKCHAIN VERIFICATION START ===');
      showSnackBar('Verifying file integrity on blockchain...');

      final String hiveUsername = await _getHiveUsername(actualUserId);

      // Use enhanced verification to get detailed results
      final verificationResult = await HiveCompareServiceWeb.verifyWithDetails(
        fileId: fileId.toString(),
        username: hiveUsername,
      );

      if (!verificationResult.success) {
        print('❌ BLOCKCHAIN VERIFICATION FAILED');
        print('Supabase hash: ${verificationResult.supabaseFileHash}');
        print('Blockchain hash: ${verificationResult.blockchainFileHash}');
        print('Error: ${verificationResult.error}');
        print('DECRYPTION BLOCKED FOR SECURITY');
        print('=== BLOCKCHAIN VERIFICATION END ===\n');
        
        // Show detailed error to user
        await _showVerificationFailedDialogEnhanced(
          context, 
          fileId.toString(),
          verificationResult,
        );
        
        // CRITICAL: Stop execution here - no decryption allowed
        showSnackBar('❌ File cannot be decrypted - verification failed');
        return;
      }

      // Additional check: Ensure hashes actually match
      if (!verificationResult.hashesMatch) {
        print('❌ HASH MISMATCH DETECTED');
        print('Supabase hash: ${verificationResult.supabaseFileHash}');
        print('Blockchain hash: ${verificationResult.blockchainFileHash}');
        
        await _showHashMismatchDialog(
          context,
          verificationResult.supabaseFileHash ?? 'N/A',
          verificationResult.blockchainFileHash ?? 'N/A',
        );
        
        showSnackBar('❌ File corrupted - hash mismatch detected');
        return;
      }

      print('✅ BLOCKCHAIN VERIFICATION PASSED');
      print('File integrity confirmed - proceeding with decryption');
      print('Transaction ID: ${verificationResult.transactionId}');
      print('Block Number: ${verificationResult.blockNumber}');
      print('=== BLOCKCHAIN VERIFICATION END ===\n');
      
      showSnackBar('✓ Blockchain verification passed');

      // Continue with decryption only after successful verification
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

  // Separate method for actual decryption logic
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
      // Get all File_Keys for analysis
      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, file_id, recipient_type, recipient_id, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      print('Found ${allFileKeys.length} File_Keys records for file $fileId');

      // Find usable key
      Map<String, dynamic>? usableKey;
      
      // Try direct user key first
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

      // RSA Decryption
      print('\n--- ATTEMPTING RSA DECRYPTION WITH FAST_RSA ---');
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      
      try {
        String decryptedKeyDataJson;
        
        // Try RSA-OAEP first
        try {
          print('Attempting RSA-OAEP decryption...');
          decryptedKeyDataJson = await RSA.decryptOAEP(
            encryptedKeyData, 
            "",
            Hash.SHA256,
            rsaPrivateKeyPem
          );
          print('RSA-OAEP decryption successful!');
        } catch (oaepError) {
          print('RSA-OAEP decryption failed, trying PKCS1v15: $oaepError');
          // Fallback to PKCS1v15 for older encryptions
          decryptedKeyDataJson = await RSA.decryptPKCS1v15(
            encryptedKeyData,
            rsaPrivateKeyPem
          );
          print('RSA-PKCS1v15 decryption successful!');
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
          // Use nonce_hex from database if available
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

      } catch (rsaError) {
        print('RSA decryption failed: $rsaError');
        showSnackBar('RSA decryption failed: ${rsaError.toString()}');
        return;
      }
    } catch (e, stackTrace) {
      print('Error in _performDecryption: $e');
      print('Stack trace: $stackTrace');
      throw e;
    }
  }

  // Enhanced error dialog with verification details
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

  // Show hash mismatch dialog
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
              'The file hash stored in the database does not match the blockchain record. This indicates the file or its metadata has been modified.',
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

  // Rest of the helper methods remain the same...
  static Future<String> _getHiveUsername(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('User')
          .select('hive_username')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['hive_username'] != null) {
        return response['hive_username'] as String;
      }

      return 'your-hive-username'; // Replace with actual logic
    } catch (e) {
      print('Error getting Hive username: $e');
      return 'your-hive-username';
    }
  }

  // [Previous helper methods like _showFilePreview, _buildPreviewContent, etc. remain unchanged]
  
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

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 16) {
      buffer.write('${i.toRadixString(16).padLeft(8, '0')}: ');
      
      for (int j = 0; j < 16; j++) {
        if (i + j < bytes.length) {
          buffer.write('${bytes[i + j].toRadixString(16).padLeft(2, '0')} ');
        } else {
          buffer.write('   ');
        }
      }
      
      buffer.write(' |');
      for (int j = 0; j < 16 && i + j < bytes.length; j++) {
        final byte = bytes[i + j];
        if (byte >= 32 && byte <= 126) {
          buffer.write(String.fromCharCode(byte));
        } else {
          buffer.write('.');
        }
      }
      buffer.write('|\n');
    }
    return buffer.toString();
  }
}