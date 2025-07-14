import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart'; // For Encrypted class
import 'package:crypto/crypto.dart'; // For hashing functions
import 'dart:convert';

class FileEncryptionService {
  static Future<Map<String, dynamic>> encryptAndPrepareFile({
    required Uint8List fileBytes,
    required String fileName,
    required String userPassword,
    required String uploadedBy,
    required String? groupId,
    required String? category,
    required String? description,
  }) async {
    try {
      //Generate AES key and IV
      final key = Key.fromSecureRandom(32);
      final iv = IV.fromSecureRandom(16);
      final encrypter = Encrypter(AES(key));

      // Encrypt the file content
      final encryptedBytes = encrypter.encryptBytes(fileBytes, iv: iv);

      // Generate file has for integrity checking
      final fileHash = sha256.convert(fileBytes).toString();

      // For Month 1: Store AES key directly (will change in Month 2)
      final encryptedData = {
        'file_name': fileName,
        'encrypted_filename': _encryptFileName(fileName, userPassword),
        'file_type': _getFileExtension(fileName),
        'file_size': fileBytes.length,
        'encrypted_content': encryptedBytes.base64, // Store in Supabase for now
        'encryption_key':
            key.base64, // TODO: Month 2 - Replace with RSA encrypted keys
        'encryption_iv': iv.base64,
        'ipfs_cid': null, // TODO: Month 2 - Will store IPFS CID here
        'uploaded_by': uploadedBy,
        'group_id': groupId,
        'category': category,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
      };
      return encryptedData;
    } catch (e) {
      print('Error encrypting file: $e');
      throw Exception('Failed to encrypt file: $e');
    }
  }

  static String _encryptFileName(String fileName, String userPassword) {
    final key =
        Key.fromBase64(base64.encode(utf8.encode(userPassword.padRight(32))));
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key));

    final encrypted = encrypter.encrypt(fileName, iv: iv);
    return '${encrypted.base64}:${iv.base64}';
  }

  static String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'unknown';
  }
}
