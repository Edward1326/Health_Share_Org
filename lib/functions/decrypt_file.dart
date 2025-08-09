import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'package:health_share_org/services/aes_helper.dart';
import 'package:health_share_org/services/crypto_utils.dart';

class FileDecryptionService {
  // Define theme colors for consistency
  static const Color primaryBlue = Color(0xFF4A90E2);

  /// Downloads and decrypts a file from IPFS, then triggers browser download
  static Future<void> downloadAndDecryptFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    try {
      showSnackBar('Downloading and decrypting file...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

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

      print('DEBUG: Decrypted AES key: $aesKeyHex');
      print('DEBUG: Decrypted nonce: $aesNonceHex');

      // Download encrypted file from IPFS
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        showSnackBar('Failed to download file from IPFS');
        return;
      }

      final encryptedBytes = response.bodyBytes;
      print('DEBUG: Downloaded encrypted file: ${encryptedBytes.length} bytes');

      // Decrypt the file
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
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
