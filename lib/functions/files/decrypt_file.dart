import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:health_share_org/services/crypto_utils.dart'; // Your CryptoUtils file
import 'package:health_share_org/services/aes_helper.dart';    // Your AESHelper file

class FileDecryptionService {
  /// Shows file action options (download, share, etc.)
  static void showFileActions(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar, {
    VoidCallback? onRemoveShare,
    VoidCallback? onShare,
    bool showRemoveShare = false,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              file['filename'] ?? 'Unknown File',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download & Decrypt'),
              onTap: () {
                Navigator.pop(context);
                downloadAndDecryptFile(context, file, showSnackBar);
              },
            ),
            if (onShare != null)
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share File'),
                onTap: () {
                  Navigator.pop(context);
                  onShare();
                },
              ),
            if (showRemoveShare && onRemoveShare != null)
              ListTile(
                leading: const Icon(Icons.remove_circle, color: Colors.red),
                title: const Text('Remove Share', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  onRemoveShare();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('File Details'),
              onTap: () {
                Navigator.pop(context);
                _showFileDetailsDialog(context, file);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Shows detailed file information
  static void _showFileDetailsDialog(BuildContext context, Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Filename', file['filename'] ?? 'Unknown'),
            _buildDetailRow('Category', file['category'] ?? 'Unknown'),
            _buildDetailRow('File ID', file['id'] ?? 'Unknown'),
            _buildDetailRow('IPFS CID', file['ipfs_cid'] ?? 'Not available'),
            if (file['created_at'] != null)
              _buildDetailRow('Created', file['created_at']),
            if (file['file_size'] != null)
              _buildDetailRow('Size', '${file['file_size']} bytes'),
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

  /// Helper to build detail rows
  static Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  /// Fixed version of downloadAndDecryptFile that handles Organization_User IDs
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

      // Get user info with correct schema
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key, rsa_public_key')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;
      final rsaPublicKeyPem = userResponse['rsa_public_key'] as String?;

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

      // Get file info and check ownership
      final fileInfo = await Supabase.instance.client
          .from('Files')
          .select('uploaded_by, filename, category')
          .eq('id', fileId)
          .single();

      print('DEBUG: File info: $fileInfo');
      print('DEBUG: File uploaded_by: ${fileInfo['uploaded_by']}, Current user: $userId');

      bool isOwner = fileInfo['uploaded_by'] == userId;
      print('DEBUG: User is file owner: $isOwner');

      // Check file sharing permissions
      print('DEBUG: Checking file sharing permissions...');
      final fileShares = await Supabase.instance.client
          .from('File_Shares')
          .select('shared_with_user_id, shared_with_doctor, shared_with_group_id, revoked_at')
          .eq('file_id', fileId);

      print('DEBUG: File_Shares query returned: $fileShares');

      bool hasActiveShare = false;

      if (isOwner) {
        hasActiveShare = true;
        print('DEBUG: User is file owner - access granted');
      } else {
        // Check for active (non-revoked) shares
        for (var share in fileShares) {
          if (share['revoked_at'] == null) {
            // Check if share is for current user
            if (share['shared_with_user_id'] == userId) {
              hasActiveShare = true;
              print('DEBUG: Found active user share');
              break;
            }

            // Check if shared with doctor using User.id
            if (share['shared_with_doctor'] == userId) {
              hasActiveShare = true;
              print('DEBUG: Found active doctor share for user ID');
              break;
            }

            // Also check Organization_User IDs as fallback
            for (var orgUser in orgUserResponse) {
              if (share['shared_with_doctor'] == orgUser['id']) {
                hasActiveShare = true;
                print('DEBUG: Found active doctor share for Organization_User: ${orgUser['id']}');
                break;
              }
            }

            if (hasActiveShare) break;
          }
        }
      }

      if (!hasActiveShare) {
        showSnackBar('Access denied: File sharing has been revoked or you do not have permission');
        print('DEBUG: No active file sharing permissions found');
        return;
      }

      // Get all File_Keys for this file
      print('DEBUG: Fetching File_Keys records...');
      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, recipient_id, recipient_type, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      print('DEBUG: Found ${allFileKeys.length} File_Keys records');

      if (allFileKeys.isEmpty) {
        showSnackBar('No encryption keys found for this file');
        return;
      }

      // Parse RSA private key once
      print('DEBUG: Parsing RSA private key...');
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
      print('DEBUG: RSA private key parsed successfully');

      // KEY VALIDATION: Test if our keys are correctly paired
      if (rsaPublicKeyPem != null) {
        print('DEBUG: === TESTING KEY PAIR VALIDITY ===');
        try {
          final rsaPublicKey = CryptoUtils.rsaPublicKeyFromPem(rsaPublicKeyPem);
          final testMessage = "test encryption validation";
          final encrypted = CryptoUtils.rsaEncrypt(testMessage, rsaPublicKey);
          final decrypted = CryptoUtils.rsaDecrypt(encrypted, rsaPrivateKey);
          
          if (decrypted == testMessage) {
            print('DEBUG: ✅ RSA key pair is valid and correctly paired');
          } else {
            print('DEBUG: ❌ RSA key pair validation failed - decrypted text doesn\'t match');
          }
        } catch (e) {
          print('DEBUG: ❌ RSA key pair validation failed with error: $e');
        }
        print('DEBUG: === END KEY PAIR TEST ===');
      }

      // **CRITICAL FIX**: Build list of all possible recipient IDs we should try
      List<String> possibleRecipientIds = [userId]; // Direct user ID
      
      // **ADD ORGANIZATION_USER IDs**: Include Organization_User IDs for doctor shares
      for (var orgUser in orgUserResponse) {
        possibleRecipientIds.add(orgUser['id']);
      }

      print('DEBUG: Will try User.id: $userId');
      if (orgUserResponse.isNotEmpty) {
        print('DEBUG: Will also try Organization_User IDs: ${orgUserResponse.map((o) => o['id']).join(', ')}');
      }

      // Enhanced key analysis - validate each key before attempting decryption
      print('DEBUG: === ENHANCED KEY ANALYSIS ===');
      for (var key in allFileKeys) {
        String recipientId = key['recipient_id'];
        String recipientType = key['recipient_type'];
        String encryptedAesKey = key['aes_key_encrypted'];

        print('DEBUG: Analyzing key ${key['id']}:');
        print('DEBUG:   - Recipient: ${recipientType} ${recipientId}');
        print('DEBUG:   - Encrypted key length: ${encryptedAesKey.length}');
        
        // Validate the encrypted key format
        try {
          final decoded = base64.decode(encryptedAesKey);
          print('DEBUG:   - Base64 decode successful: ${decoded.length} bytes');
          
          // Check if this matches expected RSA block size
          if (decoded.length == 256) {
            print('DEBUG:   - ✅ Encrypted block size matches 2048-bit RSA expectation');
          } else {
            print('DEBUG:   - ⚠️ Unexpected block size: ${decoded.length} bytes');
          }
        } catch (e) {
          print('DEBUG:   - ❌ Base64 decode failed: $e');
        }

        // If this key is for one of our recipient IDs, note it
        if (possibleRecipientIds.contains(recipientId)) {
          print('DEBUG:   - ✅ This key is intended for us (${recipientType} ${recipientId})');
        } else {
          print('DEBUG:   - ❌ This key is NOT for us (${recipientType} ${recipientId})');
        }
      }
      print('DEBUG: === END ENHANCED KEY ANALYSIS ===');

      Map<String, dynamic>? usableKey;
      String? decryptedKeyDataJson;
      String? aesKeyHex;
      String? aesNonceHex;

      // Sort keys by creation date (most recent first) to try newer keys first
      allFileKeys.sort((a, b) {
        final aId = a['id'] as String;
        final bId = b['id'] as String;
        return bId.compareTo(aId);
      });

      for (var key in allFileKeys) {
        String recipientId = key['recipient_id'];
        String recipientType = key['recipient_type'];
        String encryptedAesKey = key['aes_key_encrypted'];

        print('DEBUG: Trying key ${key['id']} for ${recipientType} ${recipientId}...');

        // **FIXED**: Check if this key could be for us (including Organization_User IDs)
        bool shouldTryKey = possibleRecipientIds.contains(recipientId);
        
        if (shouldTryKey) {
          try {
            print('DEBUG: Attempting RSA decryption...');
            decryptedKeyDataJson = CryptoUtils.rsaDecryptWithDebug(encryptedAesKey, rsaPrivateKey);
            
            // Parse the decrypted JSON to check for key and nonce
            final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
            aesKeyHex = keyData['key'] as String?;
            
            // Check for nonce in JSON first, then fallback to database
            aesNonceHex = keyData['nonce'] as String? ?? key['nonce_hex'] as String?;
            
            if (aesKeyHex != null && aesNonceHex != null) {
              usableKey = key;
              print('DEBUG: ✅ Successfully decrypted AES key with nonce from key ID ${key['id']}!');
              print('DEBUG: AES key length: ${aesKeyHex.length}, nonce length: ${aesNonceHex.length}');
              break;
            } else {
              print('DEBUG: ❌ Key ${key['id']} missing key or nonce: key=${aesKeyHex != null}, nonce=${aesNonceHex != null}');
            }
          } catch (e) {
            print('DEBUG: ❌ RSA decryption failed for key ${key['id']}: $e');
            
            // Additional debugging for this specific key
            try {
              final decoded = base64.decode(encryptedAesKey);
              print('DEBUG: Key ${key['id']} - Encrypted data first 16 bytes (hex): ${decoded.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
              print('DEBUG: Key ${key['id']} - Total encrypted bytes: ${decoded.length}');
            } catch (e2) {
              print('DEBUG: Key ${key['id']} - Could not decode base64: $e2');
            }
            
            continue;
          }
        } else {
          print('DEBUG: Skipping key ${key['id']} - not for current user');
        }
      }

      // Check if we found a usable key
      if (usableKey == null || aesKeyHex == null || aesNonceHex == null) {
        print('DEBUG: === FAILURE ANALYSIS ===');
        print('DEBUG: Could not find any usable File_Keys record');
        print('DEBUG: Available keys were for recipients: ${allFileKeys.map((k) => '${k['recipient_type']} ${k['recipient_id']}').join(', ')}');
        print('DEBUG: We tried recipient IDs: ${possibleRecipientIds.join(', ')}');
        print('DEBUG: This suggests one of the following issues:');
        print('DEBUG: 1. The wrong RSA public key was used during file sharing');
        print('DEBUG: 2. The current user\'s RSA private key is corrupted or incorrect');
        print('DEBUG: 3. There\'s a mismatch in the key generation/storage process');
        print('DEBUG: 4. The encrypted AES keys are malformed');
        print('DEBUG: 5. The nonce is missing from both JSON payload and database');
        
        showSnackBar('Decryption failed: No usable encryption keys found');
        _showDecryptionErrorDialog(context, allFileKeys, possibleRecipientIds);
        return;
      }

      print('DEBUG: Using AES key: ${aesKeyHex.substring(0, 8)}... with nonce: ${aesNonceHex.substring(0, 8)}...');

      // Download file from IPFS
      print('DEBUG: Downloading file from IPFS...');
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        showSnackBar('Failed to download file from IPFS (Status: ${response.statusCode})');
        return;
      }

      final encryptedBytes = response.bodyBytes;
      print('DEBUG: Downloaded encrypted file: ${encryptedBytes.length} bytes');

      // Decrypt the file using your AESHelper
      print('DEBUG: Decrypting file content...');
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(encryptedBytes);

      print('DEBUG: File decrypted successfully: ${decryptedBytes.length} bytes');

      // Create blob and trigger download
      final blob = html.Blob([decryptedBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileInfo['filename'] ?? 'decrypted_file')
        ..click();

      html.Url.revokeObjectUrl(url);

      showSnackBar('File decrypted and downloaded successfully!');

    } catch (e, stackTrace) {
      print('ERROR in downloadAndDecryptFile: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error downloading file: $e');
    }
  }

  /// Shows a detailed error dialog for decryption failures
  static void _showDecryptionErrorDialog(
    BuildContext context, 
    List<dynamic> allFileKeys, 
    List<String> possibleRecipientIds
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decryption Failed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Unable to decrypt this file. This usually indicates a key synchronization issue.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Debug Information:'),
              const SizedBox(height: 8),
              Text('Your User ID: ${possibleRecipientIds.first}'),
              if (possibleRecipientIds.length > 1)
                Text('Your Organization IDs: ${possibleRecipientIds.skip(1).join(', ')}'),
              const SizedBox(height: 8),
              const Text('Available encryption keys:'),
              ...allFileKeys.map((key) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text('• ${key['recipient_type']} ${key['recipient_id']}'),
              )),
              const SizedBox(height: 16),
              const Text(
                'Possible solutions:\n'
                '1. Ask the file owner to re-share the file\n'
                '2. Regenerate your encryption keys\n'
                '3. Contact support if the issue persists',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showKeyRegenerationDialog(context);
            },
            child: const Text('Regenerate Keys'),
          ),
        ],
      ),
    );
  }

  /// Shows dialog to regenerate RSA keys
  static void _showKeyRegenerationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate Encryption Keys'),
        content: const Text(
          'Regenerating your encryption keys will fix decryption issues but will '
          'require all previously shared files to be re-shared with you.\n\n'
          'Are you sure you want to proceed?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // TODO: Implement key regeneration logic
              // This should:
              // 1. Generate new RSA key pair
              // 2. Update User table with new keys
              // 3. Invalidate old File_Keys records for this user
              // 4. Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Key regeneration feature coming soon. Please contact support.'),
                ),
              );
            },
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
  }

  /// Validates that a specific File_Keys record can be decrypted by the current user
  static Future<bool> validateFileKeyDecryption(
    int fileId,
    String recipientId,
    String recipientType,
  ) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return false;

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key')
          .eq('email', currentUser.email!)
          .single();

      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;
      if (rsaPrivateKeyPem == null) return false;

      final keyResponse = await Supabase.instance.client
          .from('File_Keys')
          .select('aes_key_encrypted')
          .eq('file_id', fileId)
          .eq('recipient_id', recipientId)
          .eq('recipient_type', recipientType)
          .single();

      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
      final decryptedKeyDataJson = CryptoUtils.rsaDecrypt(
        keyResponse['aes_key_encrypted'], 
        rsaPrivateKey
      );

      // If we get here without exception, decryption worked
      final keyData = jsonDecode(decryptedKeyDataJson);
      return keyData['key'] != null && keyData['nonce'] != null;
      
    } catch (e) {
      print('Key validation failed for $recipientType $recipientId: $e');
      return false;
    }
  }

  /// Attempts to repair file sharing by re-encrypting with correct public keys
  static Future<bool> repairFileSharing(
    int fileId,
    Function(String) showProgress,
  ) async {
    try {
      showProgress('Analyzing file sharing configuration...');

      // Get the file owner's information
      final fileInfo = await Supabase.instance.client
          .from('Files')
          .select('uploaded_by, filename')
          .eq('id', fileId)
          .single();

      final ownerId = fileInfo['uploaded_by'];

      // Get owner's RSA keys
      final ownerData = await Supabase.instance.client
          .from('User')
          .select('rsa_private_key, rsa_public_key')
          .eq('id', ownerId)
          .single();

      if (ownerData['rsa_private_key'] == null) {
        showProgress('Cannot repair: File owner has no RSA private key');
        return false;
      }

      // Get the owner's original AES key by decrypting their File_Keys record
      final ownerKeyResponse = await Supabase.instance.client
          .from('File_Keys')
          .select('aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId)
          .eq('recipient_id', ownerId)
          .eq('recipient_type', 'user')
          .single();

      final ownerPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(ownerData['rsa_private_key']);
      final decryptedOwnerKeyJson = CryptoUtils.rsaDecrypt(
        ownerKeyResponse['aes_key_encrypted'], 
        ownerPrivateKey
      );
      final ownerKeyData = jsonDecode(decryptedOwnerKeyJson) as Map<String, dynamic>;

      showProgress('Retrieved original AES key from file owner...');

      // Get all current shares for this file
      final fileShares = await Supabase.instance.client
          .from('File_Shares')
          .select('shared_with_user_id, shared_with_doctor, shared_with_group_id')
          .eq('file_id', fileId)
          .is_('revoked_at', null);

      showProgress('Re-encrypting AES key for all recipients...');

      // For each active share, recreate the File_Keys record with correct encryption
      for (var share in fileShares) {
        if (share['shared_with_user_id'] != null) {
          await _reencryptKeyForUser(fileId, share['shared_with_user_id'], ownerKeyData);
        }
        if (share['shared_with_doctor'] != null) {
          await _reencryptKeyForDoctor(fileId, share['shared_with_doctor'], ownerKeyData);
        }
        // Group sharing would need additional logic
      }

      showProgress('File sharing repair completed!');
      return true;

    } catch (e) {
      showProgress('Repair failed: $e');
      return false;
    }
  }

  /// Re-encrypts the AES key for a specific user
  static Future<void> _reencryptKeyForUser(
    int fileId,
    String userId,
    Map<String, dynamic> keyData,
  ) async {
    // Get user's public key
    final userData = await Supabase.instance.client
        .from('User')
        .select('rsa_public_key')
        .eq('id', userId)
        .single();

    if (userData['rsa_public_key'] == null) {
      print('WARNING: User $userId has no RSA public key');
      return;
    }

    final userPublicKey = CryptoUtils.rsaPublicKeyFromPem(userData['rsa_public_key']);
    final keyDataJson = jsonEncode(keyData);
    final encryptedKey = CryptoUtils.rsaEncrypt(keyDataJson, userPublicKey);

    // Update or insert the File_Keys record
    await Supabase.instance.client
        .from('File_Keys')
        .upsert({
          'file_id': fileId,
          'recipient_id': userId,
          'recipient_type': 'user',
          'aes_key_encrypted': encryptedKey,
          'nonce_hex': keyData['nonce'],
        });

    print('DEBUG: Re-encrypted key for user $userId');
  }

  /// Re-encrypts the AES key for a specific doctor (Organization_User)
  static Future<void> _reencryptKeyForDoctor(
    int fileId,
    String doctorOrgUserId,
    Map<String, dynamic> keyData,
  ) async {
    // Get the actual User ID for this Organization_User
    final orgUserData = await Supabase.instance.client
        .from('Organization_User')
        .select('user_id')
        .eq('id', doctorOrgUserId)
        .single();

    // Get doctor's public key from their User record
    final doctorUserData = await Supabase.instance.client
        .from('User')
        .select('rsa_public_key')
        .eq('id', orgUserData['user_id'])
        .single();

    if (doctorUserData['rsa_public_key'] == null) {
      print('WARNING: Doctor user ${orgUserData['user_id']} has no RSA public key');
      return;
    }

    final doctorPublicKey = CryptoUtils.rsaPublicKeyFromPem(doctorUserData['rsa_public_key']);
    final keyDataJson = jsonEncode(keyData);
    final encryptedKey = CryptoUtils.rsaEncrypt(keyDataJson, doctorPublicKey);

    // Update or insert the File_Keys record
    await Supabase.instance.client
        .from('File_Keys')
        .upsert({
          'file_id': fileId,
          'recipient_id': doctorOrgUserId,
          'recipient_type': 'doctor',
          'aes_key_encrypted': encryptedKey,
          'nonce_hex': keyData['nonce'],
        });

    print('DEBUG: Re-encrypted key for doctor Organization_User $doctorOrgUserId');
  }
}