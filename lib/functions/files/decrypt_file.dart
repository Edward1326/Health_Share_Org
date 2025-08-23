import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'package:health_share_org/services/aes_helper.dart';
import 'package:health_share_org/services/crypto_utils.dart';

class FileDecryptionService {
  static const Color primaryBlue = Color(0xFF4A90E2);

  /// Downloads and decrypts a file from IPFS with proper doctor sharing logic
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

      // Get current user
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        showSnackBar('Authentication error');
        return;
      }

      print('DEBUG: Current user email: ${currentUser.email}');

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      print('DEBUG: Current user ID: $userId');

      if (rsaPrivateKeyPem == null) {
        showSnackBar('RSA private key not found');
        return;
      }

      // Check if user has an Organization_User record (doctor profile)
      final orgUserResponse = await Supabase.instance.client
          .from('Organization_User')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final doctorId = orgUserResponse?['id'];

      print('DEBUG: Doctor Organization_User ID: $doctorId');

      // Use both user ID and doctor ID for lookups
      final List<String> possibleRecipientIds = [userId];
      if (doctorId != null) {
        possibleRecipientIds.add(doctorId);
      }

      print('DEBUG: Possible recipient IDs: $possibleRecipientIds');

      // Check access permissions - prioritize File_Keys over File_Shares
      print('DEBUG: Checking access permissions...');

      bool hasAccess = false;
      String accessReason = '';

      // First, check if user is the file owner
      final fileOwnerCheck = await Supabase.instance.client
          .from('Files')
          .select('uploaded_by')
          .eq('id', fileId)
          .single();

      print(
          'DEBUG: File uploaded_by: ${fileOwnerCheck['uploaded_by']}, Current user: $userId');

      if (fileOwnerCheck['uploaded_by'] == userId) {
        hasAccess = true;
        accessReason = 'User is file owner';
        print('DEBUG: $accessReason');
      }

      // If not owner, check if there's a valid File_Keys record (this indicates sharing)
      if (!hasAccess) {
        final keyResponse = await Supabase.instance.client
            .from('File_Keys')
            .select('recipient_id, recipient_type')
            .eq('file_id', fileId)
            .in_('recipient_id', possibleRecipientIds)
            .maybeSingle();

        if (keyResponse != null) {
          hasAccess = true;
          accessReason =
              'User has decryption key (${keyResponse['recipient_type']}: ${keyResponse['recipient_id']})';
          print('DEBUG: $accessReason');

          // Optional: Check if the share has been explicitly revoked (but allow if key exists)
          final shareCheck = await Supabase.instance.client
              .from('File_Shares')
              .select('revoked_at')
              .eq('file_id', fileId)
              .or('shared_with_doctor.eq.${keyResponse['recipient_id']},shared_with_user_id.eq.${keyResponse['recipient_id']}')
              .maybeSingle();

          if (shareCheck != null && shareCheck['revoked_at'] != null) {
            print(
                'DEBUG: Warning - Share was revoked at ${shareCheck['revoked_at']}, but decryption key still exists');
            // You can choose to block access here or allow it since the key exists
            // For now, we'll allow it but log the warning
          }
        }
      }

      if (!hasAccess) {
        showSnackBar('Access denied: No valid decryption key found');
        print('DEBUG: User has no access to this file');
        return;
      }

      // Now get the encryption key from File_Keys using both possible IDs
      Map<String, dynamic>? keyResponse;

      try {
        // Try to find File_Keys record using any of the possible recipient IDs
        keyResponse = await Supabase.instance.client
            .from('File_Keys')
            .select(
                'aes_key_encrypted, nonce_hex, recipient_type, recipient_id')
            .eq('file_id', fileId)
            .in_('recipient_id', possibleRecipientIds)
            .maybeSingle();

        print('DEBUG: File_Keys lookup result: $keyResponse');
      } catch (e) {
        print('DEBUG: File_Keys lookup failed: $e');
      }

      if (keyResponse == null) {
        // Second try: Get all keys for this file and find the right one
        final allKeys = await Supabase.instance.client
            .from('File_Keys')
            .select('*')
            .eq('file_id', fileId);

        print('DEBUG: All File_Keys for this file: $allKeys');

        // Find a key that matches our sharing scenario
        for (var key in allKeys) {
          if (possibleRecipientIds.contains(key['recipient_id'])) {
            keyResponse = key;
            print(
                'DEBUG: Found matching key for recipient: ${key['recipient_id']}');
            break;
          }
        }

        if (keyResponse == null && allKeys.isNotEmpty) {
          // Last resort: if there's only one key and user has access, try it
          if (allKeys.length == 1) {
            keyResponse = allKeys.first;
            print('DEBUG: Using single available key as fallback');
          }
        }
      }

      if (keyResponse == null) {
        showSnackBar('Decryption key not found');
        print(
            'ERROR: No valid decryption key found for user $userId and file $fileId');
        return;
      }

      final encryptedAesKey = keyResponse['aes_key_encrypted'] as String?;
      final nonceHex = keyResponse['nonce_hex'] as String?;

      if (encryptedAesKey == null || encryptedAesKey.isEmpty) {
        showSnackBar('Encrypted AES key is missing from File_Keys record');
        print('ERROR: aes_key_encrypted is null or empty in File_Keys record');
        return;
      }

      print(
          'DEBUG: Found encrypted AES key (length: ${encryptedAesKey.length})');
      print(
          'DEBUG: Encrypted AES key preview: ${encryptedAesKey.substring(0, 50)}...');

      // Always use the user's RSA private key for decryption
      print('DEBUG: Using user RSA private key for decryption');

      // Decrypt the AES key using the correct RSA private key
      try {
        print('DEBUG: Parsing RSA private key...');
        final rsaPrivateKey =
            CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
        print('DEBUG: RSA private key parsed successfully');

        // Derive the public key from the current private key for comparison
        try {
          final derivedPublicKey =
              CryptoUtils.getPublicKeyFromPrivateKey(rsaPrivateKeyPem);
          print('DEBUG: Public key derived from current private key:');
          print('DEBUG: ${derivedPublicKey.substring(0, 100)}...');

          // Check the stored public key for comparison
          final userKeyInfo = await Supabase.instance.client
              .from('User')
              .select('rsa_public_key, created_at, updated_at')
              .eq('id', userId)
              .single();

          final storedPublicKey = userKeyInfo['rsa_public_key'] as String?;
          print('DEBUG: User key created: ${userKeyInfo['created_at']}');
          print('DEBUG: User key updated: ${userKeyInfo['updated_at']}');

          if (storedPublicKey != null) {
            print(
                'DEBUG: Stored public key preview: ${storedPublicKey.substring(0, 100)}...');

            // Compare stored public key with derived public key
            if (storedPublicKey.trim() == derivedPublicKey.trim()) {
              print('DEBUG: ✓ Stored public key matches derived public key');
            } else {
              print(
                  'DEBUG: ✗ Stored public key does NOT match derived public key');
              print(
                  'DEBUG: This suggests the private key was updated but public key wasn\'t, or vice versa');
            }
          } else {
            print('DEBUG: No stored public key found');
          }

          // Check when the File_Keys record was created vs when keys were created/updated
          final fileKeyDetails = await Supabase.instance.client
              .from('File_Keys')
              .select('created_at, updated_at')
              .eq('file_id', fileId)
              .single();

          print(
              'DEBUG: File_Keys record created: ${fileKeyDetails['created_at']}');
          print(
              'DEBUG: File_Keys record updated: ${fileKeyDetails['updated_at']}');
        } catch (e) {
          print('DEBUG: Failed to derive/compare public keys: $e');
        }

        print('DEBUG: Attempting RSA decryption...');
        final decryptedKeyDataJson =
            CryptoUtils.rsaDecryptWithDebug(encryptedAesKey, rsaPrivateKey);
        print(
            'DEBUG: RSA decryption successful, result length: ${decryptedKeyDataJson.length}');
        print(
            'DEBUG: Decrypted data preview: ${decryptedKeyDataJson.substring(0, decryptedKeyDataJson.length > 100 ? 100 : decryptedKeyDataJson.length)}');

        print('DEBUG: Parsing JSON...');
        final keyData =
            jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
        print('DEBUG: JSON parsed successfully: ${keyData.keys}');

        final aesKeyHex = keyData['key'] as String;
        final aesNonceHex = keyData['nonce'] as String;

        print(
            'DEBUG: AES key length: ${aesKeyHex.length}, nonce length: ${aesNonceHex.length}');

        // Download encrypted file from IPFS
        print('DEBUG: Downloading file from IPFS...');
        final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
        final response = await http.get(Uri.parse(ipfsUrl));

        if (response.statusCode != 200) {
          showSnackBar(
              'Failed to download file from IPFS (Status: ${response.statusCode})');
          return;
        }

        final encryptedBytes = response.bodyBytes;
        print(
            'DEBUG: Downloaded encrypted file: ${encryptedBytes.length} bytes');

        // Decrypt the file
        print('DEBUG: Creating AES helper...');
        final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
        print('DEBUG: Decrypting file data...');
        final decryptedBytes = aesHelper.decryptData(encryptedBytes);

        print('DEBUG: Decrypted file: ${decryptedBytes.length} bytes');

        // Create a blob and download it
        final blob = html.Blob([decryptedBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);

        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', file['filename'] ?? 'decrypted_file')
          ..click();

        html.Url.revokeObjectUrl(url);

        showSnackBar('File decrypted and downloaded successfully!');
      } catch (rsaError) {
        print('ERROR: RSA decryption failed: $rsaError');

        // Additional debugging for RSA issues
        print(
            'DEBUG: RSA Private key preview: ${rsaPrivateKeyPem.substring(0, 100)}...');

        // Try to validate the private key format
        try {
          final testKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
          print('DEBUG: Private key parsing works independently');
        } catch (e) {
          print('DEBUG: Private key parsing also fails: $e');
        }

        showSnackBar('RSA decryption failed - key mismatch or corrupted data');

        print('DEBUG: TROUBLESHOOTING TIPS:');
        print(
            'DEBUG: 1. Check if the file was encrypted using the user\'s public key');
        print(
            'DEBUG: 2. Verify that File_Keys were created with the user ID as recipient');
        print(
            'DEBUG: 3. Ensure RSA key pairs are properly generated and stored');
        print(
            'DEBUG: 4. Check if keys were regenerated after the file was shared');

        return;
      }
    } catch (e, stackTrace) {
      print('ERROR downloading/decrypting file: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error downloading file: $e');
    }
  }

  /// Previews a file by decrypting and opening it in a new browser tab
  /// Only supports images (jpg, jpeg, png) and PDFs
  static Future<void> previewFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    try {
      final fileType = file['file_type']?.toLowerCase();

      // Only allow preview for images and PDFs
      if (!['jpg', 'jpeg', 'png', 'pdf'].contains(fileType)) {
        showSnackBar('Preview not available for this file type');
        return;
      }

      showSnackBar('Loading file preview...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

      if (ipfsCid == null) {
        showSnackBar('IPFS CID not found');
        return;
      }

      // Get current user and decrypt file (same as download)
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        showSnackBar('Authentication error');
        return;
      }

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      if (rsaPrivateKeyPem == null) {
        showSnackBar('RSA private key not found');
        return;
      }

      final keyResponse = await Supabase.instance.client
          .from('File_Keys')
          .select('aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId)
          .eq('recipient_id', userId)
          .single();

      final encryptedAesKey = keyResponse['aes_key_encrypted'] as String;
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
      final decryptedKeyDataJson =
          CryptoUtils.rsaDecrypt(encryptedAesKey, rsaPrivateKey);
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;

      final aesKeyHex = keyData['key'] as String;
      final aesNonceHex = keyData['nonce'] as String;

      // Download and decrypt
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        showSnackBar('Failed to download file from IPFS');
        return;
      }

      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(response.bodyBytes);

      // Create blob URL and open in new tab for preview
      final blob = html.Blob([decryptedBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');

      // Clean up the URL after a delay
      Timer(const Duration(seconds: 30), () {
        html.Url.revokeObjectUrl(url);
      });

      showSnackBar('File preview opened in new tab');
    } catch (e) {
      print('ERROR previewing file: $e');
      showSnackBar('Error previewing file: $e');
    }
  }

  /// Gets decrypted file bytes without triggering download or preview
  /// Useful for when you need the file data for other operations
  static Future<List<int>?> getDecryptedFileBytes(
    Map<String, dynamic> file,
  ) async {
    try {
      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

      if (ipfsCid == null) {
        print('IPFS CID not found');
        return null;
      }

      // Get current user
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        print('Authentication error - no current user');
        return null;
      }

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      if (rsaPrivateKeyPem == null) {
        print('RSA private key not found');
        return null;
      }

      // Get the encrypted AES key for this user
      final keyResponse = await Supabase.instance.client
          .from('File_Keys')
          .select('aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId)
          .eq('recipient_id', userId)
          .single();

      final encryptedAesKey = keyResponse['aes_key_encrypted'] as String;
      final nonceHex = keyResponse['nonce_hex'] as String;

      // Decrypt the AES key using RSA private key
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
      final decryptedKeyDataJson =
          CryptoUtils.rsaDecrypt(encryptedAesKey, rsaPrivateKey);
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;

      final aesKeyHex = keyData['key'] as String;
      final aesNonceHex = keyData['nonce'] as String;

      // Download encrypted file from IPFS
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        print('Failed to download file from IPFS: ${response.statusCode}');
        return null;
      }

      final encryptedBytes = response.bodyBytes;

      // Decrypt the file
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(encryptedBytes);

      return decryptedBytes;
    } catch (e, stackTrace) {
      print('ERROR getting decrypted file bytes: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Shows a modal bottom sheet with file action options
  static void showFileActions(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar, {
    VoidCallback? onRemoveShare,
    VoidCallback? onShare,
    bool showRemoveShare = true,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.visibility, color: primaryBlue),
              title: const Text('Preview File'),
              onTap: () {
                Navigator.pop(context);
                previewFile(context, file, showSnackBar);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: primaryBlue),
              title: const Text('Download File'),
              onTap: () {
                Navigator.pop(context);
                downloadAndDecryptFile(context, file, showSnackBar);
              },
            ),
            if (onShare != null)
              ListTile(
                leading: const Icon(Icons.share, color: primaryBlue),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(context);
                  onShare();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: primaryBlue),
              title: const Text('File Details'),
              onTap: () {
                Navigator.pop(context);
                showFileDetails(context, file);
              },
            ),
            if (showRemoveShare && onRemoveShare != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
                title: const Text('Remove Share'),
                onTap: () {
                  Navigator.pop(context);
                  onRemoveShare();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Shows a dialog with detailed file information
  static void showFileDetails(BuildContext context, Map<String, dynamic> file) {
    final fileName = file['filename'] ?? 'Unknown File';
    final description = file['description'] ?? 'No description';
    final fileType = file['file_type'] ?? 'unknown';
    final category = file['category'] ?? 'other';
    final createdAt =
        DateTime.tryParse(file['created_at'] ?? '') ?? DateTime.now();
    final uploader = file['uploader'];
    final uploaderName = uploader != null
        ? '${uploader['Person']['first_name']} ${uploader['Person']['last_name']}'
        : 'Unknown';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('File Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Name', fileName),
            _buildDetailRow('Description', description),
            _buildDetailRow('Type', fileType.toUpperCase()),
            _buildDetailRow(
                'Category', category.replaceAll('_', ' ').toUpperCase()),
            _buildDetailRow('Uploaded by', uploaderName),
            _buildDetailRow('Date', _formatDate(createdAt)),
            if (file['file_size'] != null)
              _buildDetailRow('Size', _formatFileSize(file['file_size'])),
            if (file['ipfs_cid'] != null)
              _buildDetailRow('IPFS CID', file['ipfs_cid']),
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

  /// Helper method to build detail rows in file details dialog
  static Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF757575),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// Formats file size in human readable format
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Formats date in a user-friendly way
  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1 year ago' : '$years years ago';
    }
  }

  /// Checks if the current user has access to decrypt a specific file
  static Future<bool> canUserAccessFile(int fileId) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return false;

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];

      final keyResponse = await Supabase.instance.client
          .from('File_Keys')
          .select('id')
          .eq('file_id', fileId)
          .eq('recipient_id', userId)
          .maybeSingle();

      return keyResponse != null;
    } catch (e) {
      print('Error checking file access: $e');
      return false;
    }
  }
}
