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

      // Get user info with correct schema - removed created_at since it doesn't exist
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key, rsa_public_key')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      print('DEBUG: Current user ID: $userId');

      if (rsaPrivateKeyPem == null) {
        showSnackBar('RSA private key not found');
        return;
      }

      // Check if user has Organization_User records (doctor/organization roles)
      final orgUserResponse = await Supabase.instance.client
          .from('Organization_User')
          .select('id, organization_id')
          .eq('user_id', userId);

      print('DEBUG: Organization_User records: $orgUserResponse');

      // Collect all possible recipient IDs
      final List<String> possibleRecipientIds = [
        userId
      ]; // Always include user ID

      for (var orgUser in orgUserResponse) {
        possibleRecipientIds.add(orgUser['id']); // Add Organization_User ID
      }

      print('DEBUG: Possible recipient IDs: $possibleRecipientIds');

      // Get file info and check ownership - removed created_at since it doesn't exist
      final fileInfo = await Supabase.instance.client
          .from('Files')
          .select('uploaded_by, filename, category')
          .eq('id', fileId)
          .single();

      print('DEBUG: File info: $fileInfo');
      print(
          'DEBUG: File uploaded_by: ${fileInfo['uploaded_by']}, Current user: $userId');

      bool isOwner = fileInfo['uploaded_by'] == userId;
      print('DEBUG: User is file owner: $isOwner');

      // First, check if file sharing is still active
      print('DEBUG: Checking file sharing permissions...');
      final fileShares = await Supabase.instance.client
          .from('File_Shares')
          .select('shared_with_user_id, shared_with_doctor, revoked_at')
          .eq('file_id', fileId);

      bool hasActiveShare = false;

      if (isOwner) {
        hasActiveShare = true;
        print('DEBUG: User is file owner - access granted');
      } else {
        // Check for active (non-revoked) shares
        for (var share in fileShares) {
          if (share['revoked_at'] == null) {
            // Check if share is for current user or doctor
            if (share['shared_with_user_id'] == userId) {
              hasActiveShare = true;
              print('DEBUG: Found active user share');
              break;
            }

            // Check doctor shares against Organization_User IDs
            for (var orgUser in orgUserResponse) {
              if (share['shared_with_doctor'] == orgUser['id']) {
                hasActiveShare = true;
                print(
                    'DEBUG: Found active doctor share for Organization_User: ${orgUser['id']}');
                break;
              }
            }

            if (hasActiveShare) break;
          } else {
            print(
                'DEBUG: Found revoked share - revoked at: ${share['revoked_at']}');
          }
        }
      }

      if (!hasActiveShare) {
        showSnackBar(
            'Access denied: File sharing has been revoked or you do not have permission');
        print('DEBUG: No active file sharing permissions found');
        return;
      }

      // Find the correct File_Keys record
      Map<String, dynamic>? keyResponse;

      try {
        // Get all File_Keys for this file to understand the sharing structure
        // Removed created_at since it doesn't exist in File_Keys table
        final allFileKeys = await Supabase.instance.client
            .from('File_Keys')
            .select('id, recipient_id, recipient_type, aes_key_encrypted')
            .eq('file_id', fileId);

        print('DEBUG: All File_Keys for this file:');
        for (var key in allFileKeys) {
          print(
              'DEBUG:   - ID: ${key['id']}, Recipient: ${key['recipient_type']} ${key['recipient_id']}');
        }

        // Find a File_Keys record we can use
        for (var key in allFileKeys) {
          String recipientId = key['recipient_id'];
          String recipientType = key['recipient_type'];

          // Check different recipient types
          bool canUseKey = false;

          if (recipientType == 'user' && recipientId == userId) {
            canUseKey = true;
            print('DEBUG: Found direct user key match');
          } else if (recipientType == 'doctor') {
            // For doctor keys, check if the recipient_id matches our Organization_User ID
            if (possibleRecipientIds.contains(recipientId)) {
              canUseKey = true;
              print('DEBUG: Found doctor key match via Organization_User ID');
            } else if (recipientId == userId) {
              // Some systems might store User ID as doctor recipient - this seems to be your case
              canUseKey = true;
              print(
                  'DEBUG: Found doctor key match via User ID (legacy format)');
            }
          } else if (recipientType == 'group') {
            // Handle group sharing if needed
            print('DEBUG: Found group key, checking group membership...');
            // You might need additional logic here to check group membership
          }

          if (canUseKey) {
            keyResponse = key;
            print(
                'DEBUG: Using File_Keys record for recipient: ${key['recipient_id']} (${key['recipient_type']})');
            break;
          }
        }

        // If no direct match and user is owner, try any key (they should be able to decrypt their own files)
        if (keyResponse == null && isOwner && allFileKeys.isNotEmpty) {
          keyResponse = allFileKeys.first;
          print('DEBUG: User is owner, using first available key as fallback');
        }
      } catch (e) {
        print('DEBUG: Error querying File_Keys: $e');
      }

      if (keyResponse == null) {
        showSnackBar('No decryption key found for this file');
        print('DEBUG: No accessible File_Keys record found');

        // Enhanced debugging for key issues
        await _analyzeKeyAccessIssues(fileId, userId, possibleRecipientIds);
        return;
      }

      final encryptedAesKey = keyResponse['aes_key_encrypted'] as String?;
      if (encryptedAesKey == null || encryptedAesKey.isEmpty) {
        showSnackBar('Encrypted AES key is missing');
        return;
      }

      print(
          'DEBUG: Found encrypted AES key (length: ${encryptedAesKey.length})');
      print(
          'DEBUG: Key recipient: ${keyResponse['recipient_type']} ${keyResponse['recipient_id']}');

      // Attempt RSA decryption
      try {
        print('DEBUG: Parsing RSA private key...');
        final rsaPrivateKey =
            CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
        print('DEBUG: RSA private key parsed successfully');

        // Get the public key from private key for comparison
        print('DEBUG: Extracting public key info...');
        // You might need to implement getPublicKeyInfo() in CryptoUtils
        // This would help identify which public key was used for encryption

        print('DEBUG: Checking if we need to try different keys...');

        // If the key is stored with recipient_type 'doctor' but recipient_id is User ID,
        // we might need to get the correct doctor's RSA key
        if (keyResponse['recipient_type'] == 'doctor' &&
            keyResponse['recipient_id'] == userId &&
            orgUserResponse.isNotEmpty) {
          print(
              'DEBUG: Key shows doctor recipient but uses User ID. Checking if we should use doctor keys...');

          // Try to get the organization user's RSA key if it exists
          try {
            final doctorId = orgUserResponse.first['id'];
            print('DEBUG: Trying to get RSA key for doctor ID: $doctorId');

            // Check if there's a separate RSA key for the doctor role
            final doctorKeyResponse = await Supabase.instance.client
                .from('Organization_User')
                .select('rsa_private_key, rsa_public_key')
                .eq('id', doctorId)
                .maybeSingle();

            if (doctorKeyResponse != null &&
                doctorKeyResponse['rsa_private_key'] != null) {
              print(
                  'DEBUG: Found separate doctor RSA key, trying that instead...');
              final doctorPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(
                  doctorKeyResponse['rsa_private_key']);

              final decryptedKeyDataJson = CryptoUtils.rsaDecryptWithDebug(
                  encryptedAesKey, doctorPrivateKey);
              print('DEBUG: RSA decryption successful with doctor key!');

              final keyData =
                  jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
              final aesKeyHex = keyData['key'] as String;
              final aesNonceHex = keyData['nonce'] as String;

              print('DEBUG: AES key extracted successfully');
              // Continue with file download and decryption...
            } else {
              print(
                  'DEBUG: No separate doctor RSA key found, using user key...');
              throw Exception('No doctor RSA key available');
            }
          } catch (doctorKeyError) {
            print('DEBUG: Doctor key approach failed: $doctorKeyError');
            print('DEBUG: Falling back to user RSA key...');
          }
        }

        // Try decryption with the user's private key
        print('DEBUG: Attempting RSA decryption with user private key...');
        final decryptedKeyDataJson =
            CryptoUtils.rsaDecryptWithDebug(encryptedAesKey, rsaPrivateKey);

        print('DEBUG: RSA decryption successful!');

        final keyData =
            jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
        final aesKeyHex = keyData['key'] as String;
        final aesNonceHex = keyData['nonce'] as String;

        print('DEBUG: AES key extracted successfully');

        // Download file from IPFS
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
        print('DEBUG: Decrypting file content...');
        final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
        final decryptedBytes = aesHelper.decryptData(encryptedBytes);

        print(
            'DEBUG: File decrypted successfully: ${decryptedBytes.length} bytes');

        // Create blob and trigger download
        final blob = html.Blob([decryptedBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);

        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileInfo['filename'] ?? 'decrypted_file')
          ..click();

        html.Url.revokeObjectUrl(url);

        showSnackBar('File decrypted and downloaded successfully!');
      } catch (rsaError) {
        print('ERROR: RSA decryption failed: $rsaError');

        // Try to debug the key mismatch issue
        await _debugRSAKeyMismatch(fileId, userId, keyResponse, userResponse);

        showSnackBar('Decryption failed: Key mismatch or corrupted data');
        return;
      }
    } catch (e, stackTrace) {
      print('ERROR in downloadAndDecryptFile: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error downloading file: $e');
    }
  }

// Enhanced debugging for key access issues
  static Future<void> _analyzeKeyAccessIssues(
    String fileId,
    String userId,
    List<String> possibleRecipientIds,
  ) async {
    try {
      print('DEBUG: === KEY ACCESS ANALYSIS ===');

      // Check File_Shares table
      final fileShares = await Supabase.instance.client
          .from('File_Shares')
          .select('shared_with_user_id, shared_with_doctor, revoked_at')
          .eq('file_id', fileId);

      print('DEBUG: File_Shares records:');
      for (var share in fileShares) {
        print(
            'DEBUG:   - User: ${share['shared_with_user_id']}, Doctor: ${share['shared_with_doctor']}');
        print('DEBUG:   - Revoked: ${share['revoked_at']}');
      }

      // Check if there are any File_Keys at all
      final allKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('recipient_id, recipient_type')
          .eq('file_id', fileId);

      if (allKeys.isEmpty) {
        print('DEBUG: ⚠️  NO File_Keys records exist for this file!');
        print(
            'DEBUG: This suggests the file was never properly encrypted or shared.');
      } else {
        print('DEBUG: Available keys but none match user access:');
        for (var key in allKeys) {
          final hasAccess = possibleRecipientIds.contains(key['recipient_id']);
          print(
              'DEBUG:   - ${key['recipient_type']} ${key['recipient_id']} - Access: $hasAccess');
        }
      }

      print('DEBUG: === END ANALYSIS ===');
    } catch (e) {
      print('DEBUG: Analysis failed: $e');
    }
  }

// Debug RSA key mismatch issues
  static Future<void> _debugRSAKeyMismatch(
    String fileId,
    String userId,
    Map<String, dynamic> keyResponse,
    Map<String, dynamic> userResponse,
  ) async {
    try {
      print('DEBUG: === RSA KEY MISMATCH ANALYSIS ===');

      // Check if the key was created for a different recipient type
      final keyRecipientType = keyResponse['recipient_type'];
      final keyRecipientId = keyResponse['recipient_id'];

      print(
          'DEBUG: Key was encrypted for: $keyRecipientType ID $keyRecipientId');
      print('DEBUG: Current user ID: $userId');

      if (keyRecipientType == 'doctor' && keyRecipientId != userId) {
        print(
            'DEBUG: ⚠️  Key was encrypted for a doctor role, not direct user');

        // Check if this doctor ID belongs to current user
        final doctorCheck = await Supabase.instance.client
            .from('Organization_User')
            .select('user_id, organization_id')
            .eq('id', keyRecipientId)
            .maybeSingle();

        if (doctorCheck != null) {
          print(
              'DEBUG: Doctor record belongs to user: ${doctorCheck['user_id']}');
          if (doctorCheck['user_id'] == userId) {
            print('DEBUG: ✅ Doctor ID matches current user');
          } else {
            print(
                'DEBUG: ❌ Doctor ID belongs to different user: ${doctorCheck['user_id']}');
          }
        } else {
          print('DEBUG: ❌ Doctor ID not found in Organization_User table');
        }
      }

      print('DEBUG: === END RSA ANALYSIS ===');
    } catch (e) {
      print('DEBUG: RSA analysis failed: $e');
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
