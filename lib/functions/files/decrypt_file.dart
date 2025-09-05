import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:health_share_org/services/crypto_utils.dart'; // Your CryptoUtils file
import 'package:health_share_org/services/aes_helper.dart';    // Your AESHelper file
import 'dart:async';


class FileDecryptionService {
  // Original debugging method
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

      // Parse keys
      final privateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
      final publicKey = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
      print('Keys parsed successfully');

      // Test encryption/decryption
      const testData = '{"key":"test123","nonce":"abc456"}';
      
      final encrypted = CryptoUtils.rsaEncrypt(testData, publicKey);
      print('Test encryption successful: ${encrypted.length} chars');

      final decrypted = CryptoUtils.rsaDecrypt(encrypted, privateKey);
      print('Test decryption successful');

      if (decrypted == testData) {
        print('SUCCESS: Key pair is working correctly');
      } else {
        print('ERROR: Decrypted data doesn\'t match original');
      }

    } catch (e) {
      print('ERROR: Key pair test failed: $e');
    }
  }

  // Original download and decrypt method with debugging
  static Future<void> downloadAndDecryptFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    try {
      showSnackBar('Downloading and decrypting file...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

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

      if (actualUserId == null || rsaPrivateKeyPem == null) {
        showSnackBar('User authentication error');
        return;
      }

      // ADD THIS DEBUGGING SECTION HERE:
      print('\n=== STARTING ENHANCED DEBUGGING ===');
      
      // Test the user's key pair integrity first
      await debugKeyIntegrity(actualUserId);
      
      // Parse RSA private key
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);

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

      // ENHANCED RSA DECRYPTION WITH DEBUGGING:
      print('\n--- ATTEMPTING RSA DECRYPTION ---');
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

      // Now attempt the actual RSA decryption
      try {
        final decryptedKeyDataJson = CryptoUtils.rsaDecrypt(
          encryptedKeyData, 
          rsaPrivateKey
        );

        print('RSA decryption successful!');
        
        final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
        final aesKeyHex = keyData['key'] as String?;
        final aesNonceHex = keyData['nonce'] as String? ?? usableKey['nonce_hex'] as String?;

        if (aesKeyHex == null || aesNonceHex == null) {
          throw Exception('Missing AES key or nonce in decrypted data');
        }

        print('AES key extracted successfully');

        // Continue with file download and decryption...
        final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
        final response = await http.get(Uri.parse(ipfsUrl));

        if (response.statusCode != 200) {
          throw Exception('Failed to download from IPFS: ${response.statusCode}');
        }

        final encryptedFileBytes = response.bodyBytes;
        print('Downloaded ${encryptedFileBytes.length} bytes from IPFS');

        // Decrypt the file
        final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
        final decryptedBytes = aesHelper.decryptData(encryptedFileBytes);

        print('File decrypted successfully: ${decryptedBytes.length} bytes');

        // Trigger download
        final blob = html.Blob([decryptedBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);

        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', file['filename'] ?? 'decrypted_file')
          ..click();

        html.Url.revokeObjectUrl(url);

        showSnackBar('File decrypted and downloaded successfully!');

      } catch (rsaError) {
        print('RSA decryption failed: $rsaError');
        
        // ADDITIONAL DEBUGGING: Check if wrong key was used
        if (rsaError.toString().contains('decoding error')) {
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

  // Helper method to investigate wrong key usage
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

  // Helper method to test decryption with owner key
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

      final ownerPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(ownerPrivateKeyPem);
      
      try {
        final decryptedJson = CryptoUtils.rsaDecrypt(encryptedKeyData, ownerPrivateKey);
        print('SUCCESS: Owner can decrypt this key!');
        print('DIAGNOSIS: Key was encrypted with owner\'s public key instead of recipient\'s public key');
        print('This means the sharing process used the wrong public key during encryption');
      } catch (e) {
        print('Owner cannot decrypt this key either: $e');
        print('DIAGNOSIS: Key may be corrupted or encrypted with unknown key');
      }

    } catch (e) {
      print('Error testing owner key: $e');
    }
  }

  // NEW: Preview file in modal dialog
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

      if (actualUserId == null || rsaPrivateKeyPem == null) {
        showSnackBar('User authentication error');
        return;
      }

      // Parse RSA private key
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);

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

      // Decrypt the AES key
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      final decryptedKeyDataJson = CryptoUtils.rsaDecrypt(encryptedKeyData, rsaPrivateKey);
      
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
      final aesKeyHex = keyData['key'] as String?;
      final aesNonceHex = keyData['nonce'] as String? ?? usableKey['nonce_hex'] as String?;

      if (aesKeyHex == null || aesNonceHex == null) {
        throw Exception('Missing AES key or nonce in decrypted data');
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

  // Helper method to show the file preview in a modal
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

  // Helper method to build preview content based on file type
  static Widget _buildPreviewContent(String mimeType, Uint8List bytes, String filename) {
    // Determine file type
    final extension = filename.toLowerCase().split('.').last;
    
    // Image files
    if (mimeType.startsWith('image/') || 
        ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      return _buildImagePreview(bytes);
    }
    
    // Text files
    if (mimeType.startsWith('text/') || 
        ['txt', 'md', 'json', 'xml', 'csv', 'log'].contains(extension)) {
      return _buildTextPreview(bytes);
    }
    
    // PDF files
    if (mimeType == 'application/pdf' || extension == 'pdf') {
      return _buildPdfPreview(bytes);
    }
    
    // Code files
    if (['dart', 'js', 'html', 'css', 'py', 'java', 'cpp', 'c', 'h'].contains(extension)) {
      return _buildCodePreview(bytes, extension);
    }
    
    // Default: show file info and hex preview
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
        // Show hex preview for binary files
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

  // NEW: Alternative preview function that opens in new tab
  static Future<void> previewFileInNewTab(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    try {
      showSnackBar('Preparing file preview...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];
      final filename = file['filename'] ?? 'Unknown file';
      final mimeType = file['mime_type'] ?? '';

      if (ipfsCid == null) {
        showSnackBar('IPFS CID not found');
        return;
      }

      // Get current user and decrypt file (same process as above)
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

      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);

      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, file_id, recipient_type, recipient_id, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      Map<String, dynamic>? usableKey;
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

      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      final decryptedKeyDataJson = CryptoUtils.rsaDecrypt(encryptedKeyData, rsaPrivateKey);
      
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
      final aesKeyHex = keyData['key'] as String?;
      final aesNonceHex = keyData['nonce'] as String? ?? usableKey['nonce_hex'] as String?;

      if (aesKeyHex == null || aesNonceHex == null) {
        throw Exception('Missing AES key or nonce in decrypted data');
      }

      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download from IPFS: ${response.statusCode}');
      }

      final encryptedFileBytes = response.bodyBytes;
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(encryptedFileBytes);

      // Create blob and open in new tab
      final blob = html.Blob([decryptedBytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      
      html.window.open(url, '_blank');
      
      // Clean up URL after a delay
      Timer(const Duration(seconds: 30), () {
        html.Url.revokeObjectUrl(url);
      });

      showSnackBar('File opened in new tab for preview');

    } catch (e, stackTrace) {
      print('ERROR in previewFileInNewTab: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error previewing file: $e');
    }
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

  // Helper method to format file size
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // Helper method to convert bytes to hex string
  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 16) {
      // Address
      buffer.write('${i.toRadixString(16).padLeft(8, '0')}: ');
      
      // Hex bytes
      for (int j = 0; j < 16; j++) {
        if (i + j < bytes.length) {
          buffer.write('${bytes[i + j].toRadixString(16).padLeft(2, '0')} ');
        } else {
          buffer.write('   ');
        }
      }
      
      // ASCII representation
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