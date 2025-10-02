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
  // Original debugging method - updated to use fast_rsa
  static Future<void> debugKeyIntegrity(String userId) async {
    try {
      print('\n=== TESTING KEY PAIR INTEGRITY ===');

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('rsa_private_key, rsa_public_key, email')
          .eq('id', userId)
          .single();

      final privateKeyPem = userResponse['rsa_private_key'] as String?;
      final publicKeyPem = userResponse['rsa_public_key'] as String?;
      final email = userResponse['email'] as String?;

      print('User: $email');
      print('Has Private Key: ${privateKeyPem != null && privateKeyPem.isNotEmpty}');
      print('Has Public Key: ${publicKeyPem != null && publicKeyPem.isNotEmpty}');

      if (privateKeyPem == null || publicKeyPem == null) {
        print('ERROR: Missing RSA keys');
        return;
      }

      print('Keys found successfully');

      // Test encryption/decryption with fast_rsa
      const testData = '{"key":"test123","nonce":"abc456"}';
      
      try {
        final encrypted = await RSA.encryptOAEP(testData, "", Hash.SHA256, publicKeyPem);
        print('Test encryption successful: ${encrypted.length} chars');

        final decrypted = await RSA.decryptOAEP(encrypted, "", Hash.SHA256, privateKeyPem);
        print('Test decryption successful');

        if (decrypted == testData) {
          print('SUCCESS: Key pair is working correctly');
        } else {
          print('ERROR: Decrypted data doesn\'t match original');
        }
      } catch (e) {
        print('ERROR: RSA test failed: $e');
      }

    } catch (e) {
      print('ERROR: Key pair test failed: $e');
    }
  }

  // 🔒 UPDATED: Download and decrypt method with BLOCKCHAIN VERIFICATION
  static Future<void> downloadAndDecryptFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar, {
    bool skipVerification = false,
  }) async {
    try {
      showSnackBar('Downloading and decrypting file...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];
      final fileName = file['filename'] ?? 'decrypted_file';

      print('DEBUG: Starting decryption for file ID: $fileId');

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

      // 🔐 STEP 1: BLOCKCHAIN VERIFICATION (CRITICAL SECURITY STEP)
      if (!skipVerification) {
        print('\n🔐 === BLOCKCHAIN VERIFICATION START ===');
        showSnackBar('Verifying file integrity on blockchain...');

        // Get Hive username from environment or user profile
        final String hiveUsername = await _getHiveUsername(actualUserId);

        final isVerified = await HiveCompareServiceWeb.verifyBeforeDecryption(
          fileId: fileId.toString(),
          username: hiveUsername,
        );

        if (!isVerified) {
          print('❌ BLOCKCHAIN VERIFICATION FAILED');
          print('File hash does not match blockchain record');
          print('DECRYPTION ABORTED FOR SECURITY');
          print('=== BLOCKCHAIN VERIFICATION END ===\n');
          
          showSnackBar('⚠️ Blockchain verification failed - file may be tampered');
          
          // Show detailed warning dialog
          await _showVerificationFailedDialog(context, fileId.toString());
          return;
        }

        print('✅ BLOCKCHAIN VERIFICATION PASSED');
        print('File integrity confirmed - proceeding with decryption');
        print('=== BLOCKCHAIN VERIFICATION END ===\n');
        
        showSnackBar('✓ Blockchain verification passed');
      } else {
        print('⚠️ WARNING: Blockchain verification skipped');
      }

      // Test the user's key pair integrity first
      print('\n=== STARTING ENHANCED DEBUGGING ===');
      await debugKeyIntegrity(actualUserId);

      // Get all File_Keys for analysis
      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, file_id, recipient_type, recipient_id, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      print('Found ${allFileKeys.length} File_Keys records for file $fileId:');
      for (var key in allFileKeys) {
        print('  - ${key['id']}: ${key['recipient_type']} ${key['recipient_id']}');
      }

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

      // ENHANCED RSA DECRYPTION WITH DEBUGGING USING FAST_RSA:
      print('\n--- ATTEMPTING RSA DECRYPTION WITH FAST_RSA ---');
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      
      // Debug the encrypted data
      print('Encrypted key length: ${encryptedKeyData.length}');
      print('First 50 chars: ${encryptedKeyData.substring(0, 50)}...');
      
      // Test base64 decoding
      try {
        final decodedBytes = base64Decode(encryptedKeyData);
        print('Base64 decode successful: ${decodedBytes.length} bytes');
        
        // Check expected size for RSA-2048 (256 bytes) or RSA-1024 (128 bytes)
        if (decodedBytes.length == 256) {
          print('Encrypted with RSA-2048 (normal)');
        } else if (decodedBytes.length == 128) {
          print('Encrypted with RSA-1024');
        } else {
          print('WARNING: Unexpected encrypted data size: ${decodedBytes.length} bytes');
        }
        
      } catch (e) {
        print('ERROR: Base64 decode failed: $e');
        showSnackBar('Corrupted encrypted key data');
        return;
      }

      // Now attempt the actual RSA decryption using fast_rsa
      try {
        String decryptedKeyDataJson;
        
        // Try RSA-OAEP first (matches your upload encryption)
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

        // Continue with file download and decryption...
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

        // Trigger download
        final blob = html.Blob([decryptedBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);

        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();

        html.Url.revokeObjectUrl(url);

        showSnackBar('✓ File decrypted and downloaded successfully!');

      } catch (rsaError) {
        print('RSA decryption failed: $rsaError');
        
        // ADDITIONAL DEBUGGING: Check if wrong key was used
        if (rsaError.toString().contains('decoding error') || 
            rsaError.toString().contains('decrypt')) {
          print('\n--- INVESTIGATING WRONG KEY USAGE ---');
          await _investigateWrongKeyUsage(fileId, actualUserId, encryptedKeyData);
        }
        
        showSnackBar('RSA decryption failed: ${rsaError.toString()}');
        return;
      }

    } catch (e, stackTrace) {
      print('ERROR in downloadAndDecryptFile: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error downloading file: $e');
    }
  }

  // 🔒 UPDATED: Preview file with BLOCKCHAIN VERIFICATION
  static Future<void> previewFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar, {
    bool skipVerification = false,
  }) async {
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

      if (actualUserId == null || rsaPrivateKeyPem == null) {
        showSnackBar('User authentication error');
        return;
      }

      // 🔐 BLOCKCHAIN VERIFICATION BEFORE PREVIEW
      if (!skipVerification) {
        print('\n🔐 === BLOCKCHAIN VERIFICATION FOR PREVIEW ===');
        
        final String hiveUsername = await _getHiveUsername(actualUserId);

        final isVerified = await HiveCompareServiceWeb.verifyBeforeDecryption(
          fileId: fileId.toString(),
          username: hiveUsername,
        );

        if (!isVerified) {
          print('❌ BLOCKCHAIN VERIFICATION FAILED - Preview aborted');
          showSnackBar('⚠️ Cannot preview - blockchain verification failed');
          return;
        }

        print('✅ BLOCKCHAIN VERIFICATION PASSED - Proceeding with preview');
      }

      // Get File_Keys for this file
      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, file_id, recipient_type, recipient_id, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      // Find usable key
      Map<String, dynamic>? usableKey;
      
      // Try direct user key first
      for (var key in allFileKeys) {
        if (key['recipient_type'] == 'user' && key['recipient_id'] == actualUserId) {
          usableKey = key;
          break;
        }
      }

      if (usableKey == null) {
        showSnackBar('No decryption key found for this file');
        return;
      }

      // Decrypt the AES key using fast_rsa
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      
      String decryptedKeyDataJson;
      try {
        // Try RSA-OAEP first
        decryptedKeyDataJson = await RSA.decryptOAEP(
          encryptedKeyData, 
          "",
          Hash.SHA256,
          rsaPrivateKeyPem
        );
      } catch (oaepError) {
        // Fallback to PKCS1v15
        decryptedKeyDataJson = await RSA.decryptPKCS1v15(
          encryptedKeyData,
          rsaPrivateKeyPem
        );
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

      // Download file from IPFS
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download from IPFS: ${response.statusCode}');
      }

      final encryptedFileBytes = response.bodyBytes;

      // Decrypt the file
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(encryptedFileBytes);

      print('File decrypted successfully for preview: ${decryptedBytes.length} bytes');

      // Show preview based on file type
      await _showFilePreview(context, filename, mimeType, decryptedBytes);

    } catch (e, stackTrace) {
      print('ERROR in previewFile: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error previewing file: $e');
    }
  }

  // 🆕 NEW: Get Hive username for blockchain verification
  static Future<String> _getHiveUsername(String userId) async {
    try {
      // Try to get from User table first
      final response = await Supabase.instance.client
          .from('User')
          .select('hive_username')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['hive_username'] != null) {
        return response['hive_username'] as String;
      }

      // Fallback to environment variable
      // You should configure this in your .env file
      return 'your-hive-username'; // Replace with actual logic
    } catch (e) {
      print('Error getting Hive username: $e');
      return 'your-hive-username'; // Fallback
    }
  }

  // 🆕 NEW: Show verification failed dialog
  static Future<void> _showVerificationFailedDialog(
    BuildContext context,
    String fileId,
  ) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 32),
            SizedBox(width: 12),
            Text('Verification Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This file failed blockchain verification. This could mean:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('• File has been tampered with'),
            const Text('• File was not properly logged to blockchain'),
            const Text('• Blockchain data is corrupted'),
            const SizedBox(height: 16),
            Text(
              'File ID: $fileId',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Helper method to investigate wrong key usage - updated to use fast_rsa
  static Future<void> _investigateWrongKeyUsage(String fileId, String userId, String encryptedKeyData) async {
    try {
      // Get file owner to check if they can decrypt their own key
      final fileResponse = await Supabase.instance.client
          .from('Files')
          .select('uploaded_by')
          .eq('id', fileId)
          .single();

      final ownerId = fileResponse['uploaded_by'] as String;
      print('File owner ID: $ownerId');

      if (ownerId == userId) {
        print('User is file owner - this should definitely work');
      } else {
        print('File was shared with user - checking sharing process');
        
        // Check how this file was shared
        final shareResponse = await Supabase.instance.client
            .from('File_Shares')
            .select('shared_with_doctor, shared_by_user_id')
            .eq('file_id', fileId)
            .eq('shared_with_doctor', userId)
            .maybeSingle();

        if (shareResponse != null) {
          print('File was shared as doctor share by: ${shareResponse['shared_by_user_id']}');
          
          // This means the sharing process should have used the user's public key
          // Let's check if the owner's private key can decrypt this (wrong key scenario)
          await _testDecryptionWithOwnerKey(ownerId, encryptedKeyData);
        }
      }

    } catch (e) {
      print('Error investigating wrong key usage: $e');
    }
  }

  // Helper method to test decryption with owner key - updated to use fast_rsa
  static Future<void> _testDecryptionWithOwnerKey(String ownerId, String encryptedKeyData) async {
    try {
      print('Testing if owner\'s key can decrypt this data...');
      
      final ownerResponse = await Supabase.instance.client
          .from('User')
          .select('rsa_private_key, email')
          .eq('id', ownerId)
          .single();

      final ownerPrivateKeyPem = ownerResponse['rsa_private_key'] as String?;
      if (ownerPrivateKeyPem == null) {
        print('Owner has no private key');
        return;
      }

      try {
        // Try RSA-OAEP first
        final decryptedJson = await RSA.decryptOAEP(
          encryptedKeyData, 
          "",
          Hash.SHA256,
          ownerPrivateKeyPem
        );
        print('SUCCESS: Owner can decrypt this key with RSA-OAEP!');
        print('DIAGNOSIS: Key was encrypted with owner\'s public key instead of recipient\'s public key');
        print('This means the sharing process used the wrong public key during encryption');
      } catch (oaepError) {
        try {
          // Try PKCS1v15 fallback
          final decryptedJson = await RSA.decryptPKCS1v15(
            encryptedKeyData,
            ownerPrivateKeyPem
          );
          print('SUCCESS: Owner can decrypt this key with RSA-PKCS1v15!');
          print('DIAGNOSIS: Key was encrypted with owner\'s public key instead of recipient\'s public key');
        } catch (pkcsError) {
          print('Owner cannot decrypt this key either: $pkcsError');
          print('DIAGNOSIS: Key may be corrupted or encrypted with unknown key');
        }
      }

    } catch (e) {
      print('Error testing owner key: $e');
    }
  }

  // Rest of the helper methods remain the same...
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
                // Header
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
                    Row(
                      children: [
                        // Download button
                        IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () {
                            _downloadDecryptedFile(filename, decryptedBytes);
                          },
                          tooltip: 'Download',
                        ),
                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(),
                // Content
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

  // All the remaining helper methods stay the same...
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
          'PDF preview is not available in this interface.\nUse the download button to save and view the file.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  static Widget _buildDefaultPreview(Uint8List bytes, String mimeType, String filename) {
    final extension = filename.split('.').last.toUpperCase();
    
    return Column(
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
          'Preview not available for this file type.\nUse the download button to save the file.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (bytes.length < 1000) ...[
          const Text(
            'Hex Preview (first 512 bytes):',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _bytesToHex(bytes.take(512).toList()),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
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

  // Helper method to download the already decrypted file
  static void _downloadDecryptedFile(String filename, Uint8List bytes) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();

    html.Url.revokeObjectUrl(url);
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

  // Add this diagnostic method to test your current RSA setup
  static Future<void> testCurrentRSASetup(String userId) async {
    try {
      print('\n=== TESTING CURRENT RSA SETUP ===');
      
      // Get user keys
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('rsa_private_key, rsa_public_key, email')
          .eq('id', userId)
          .single();

      final privateKeyPem = userResponse['rsa_private_key'] as String;
      final publicKeyPem = userResponse['rsa_public_key'] as String;
      final email = userResponse['email'] as String;

      print('Testing user: $email');

      // Test data that matches your upload service format
      final testKeyData = {
        'key': base64Encode(List.generate(32, (i) => i)), // 32 byte AES key
        'nonce': base64Encode(List.generate(12, (i) => i + 32)), // 12 byte nonce
      };
      final testJson = jsonEncode(testKeyData);
      
      print('Test data: $testJson');

      // Test RSA-OAEP (matches your upload)
      try {
        final encrypted = await RSA.encryptOAEP(testJson, "", Hash.SHA256, publicKeyPem);
        print('RSA-OAEP encryption successful: ${encrypted.length} chars');
        
        final decrypted = await RSA.decryptOAEP(encrypted, "", Hash.SHA256, privateKeyPem);
        print('RSA-OAEP decryption successful');
        
        if (decrypted == testJson) {
          print('✅ RSA-OAEP round-trip successful - your setup should work!');
          
          // Now test if you can decrypt existing problematic data
          await _testProblematicFileKey(userId);
          
        } else {
          print('❌ RSA-OAEP data mismatch');
        }
        
      } catch (e) {
        print('❌ RSA-OAEP failed: $e');
        
        // Your current setup is broken - check key format
        print('\n--- Checking Key Formats ---');
        print('Private key starts with: ${privateKeyPem.substring(0, 50)}...');
        print('Public key starts with: ${publicKeyPem.substring(0, 50)}...');
      }
      
    } catch (e) {
      print('❌ Setup test failed: $e');
    }
  }

  static Future<void> _testProblematicFileKey(String userId) async {
    try {
      print('\n--- Testing Problematic File Key ---');
      
      // Get a problematic file key
      final problemKey = await Supabase.instance.client
          .from('File_Keys')
          .select('aes_key_encrypted, file_id')
          .eq('recipient_type', 'user')
          .eq('recipient_id', userId)
          .limit(1)
          .single();
          
      final encryptedData = problemKey['aes_key_encrypted'] as String;
      final fileId = problemKey['file_id'] as String;
      
      print('Testing file key for file: $fileId');
      print('Encrypted data length: ${encryptedData.length}');
      
      // Get user's private key
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('rsa_private_key')
          .eq('id', userId)
          .single();
          
      final privateKeyPem = userResponse['rsa_private_key'] as String;
      
      // Try decrypting with current method
      try {
        final decrypted = await RSA.decryptOAEP(encryptedData, "", Hash.SHA256, privateKeyPem);
        print('✅ Existing key DOES work with RSA-OAEP!');
        print('Decrypted: ${decrypted.substring(0, 100)}...');
      } catch (e) {
        print('❌ Existing key does NOT work with RSA-OAEP: $e');
        
        // Try PKCS1v15
        try {
          final decrypted = await RSA.decryptPKCS1v15(encryptedData, privateKeyPem);
          print('✅ Existing key works with RSA-PKCS1v15!');
          print('🔧 SOLUTION: Your old files use PKCS1v15, new files use OAEP');
        } catch (e2) {
          print('❌ Existing key does NOT work with PKCS1v15 either: $e2');
          print('🔍 This key was encrypted with a different library/method');
        }
      }
      
    } catch (e) {
      print('Error testing problematic key: $e');
    }
  }

  // 🆕 NEW: Check if file can be decrypted (with blockchain verification)
  static Future<bool> canDecryptFile({
    required String fileId,
    required String username,
  }) async {
    try {
      print('Checking if file can be decrypted: $fileId');

      final isVerified = await HiveCompareServiceWeb.verifyBeforeDecryption(
        fileId: fileId,
        username: username,
      );

      if (isVerified) {
        print('✅ File can be decrypted - blockchain verification passed');
      } else {
        print('❌ File cannot be decrypted - blockchain verification failed');
      }

      return isVerified;
    } catch (e) {
      print('Error checking decryption eligibility: $e');
      return false;
    }
  }

  // 🆕 NEW: Get verification status for a file
  static Future<Map<String, dynamic>> getFileVerificationStatus({
    required String fileId,
    required String username,
  }) async {
    return await HiveCompareServiceWeb.getVerificationStatus(
      fileId: fileId,
      username: username,
    );
  }

  // 🆕 NEW: Batch verify multiple files before decryption
  static Future<Map<String, bool>> batchVerifyFiles({
    required List<String> fileIds,
    required String username,
  }) async {
    return await HiveCompareServiceWeb.verifyMultipleFiles(
      fileIds: fileIds,
      username: username,
    );
  }
}