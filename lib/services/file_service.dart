import 'dart:typed_data'; // For Uint8List
import 'package:encrypt/encrypt.dart'; // For Encrypted class
import 'package:crypto/crypto.dart'; // For hashing functions
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'file_encryption_service.dart';

class FileService {
  static final _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>> uploadEncryptedFile({
    required File file,
    required String userPassword,
    required String? groupID,
    required String? category,
    required String? description,
  }) async {
    try {
      // Getting logged in User
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User not Authenticated");

      // Read file
      final fileBytes = await file.readAsBytes();
      final fileName = file.path.split('/').last;

      // Encryption time!
      final fileData = await FileEncryptionService.encryptAndPrepareFile(
        fileBytes: fileBytes,
        fileName: fileName,
        userPassword: userPassword,
        uploadedBy: user.id,
        groupId: groupID,
        category: category,
        description: description,
      );

      final response =
          await _supabase.from('Files').insert(fileData).select().single();

      return response;
    } catch (e) {
      print('Error uploading file: $e');
      throw Exception('Failed to upload file: $e');
    }
  }

  // MONTH 3 na i add pag naay block chain

  static Future<void> _logFileAction({
    required String fileId,
    required String userId,
    required String action,
    required String fileHash,
  }) async {
    try {
      await _supabase.from('file_logs').insert({
        'file_id': fileId,
        'user_id': userId,
        'action': action,
        'file_hash': fileHash,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error logging file action: $e');
    }
  }
}
