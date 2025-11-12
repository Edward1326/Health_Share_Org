import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:health_share_org/services/hive/create_custom_json.dart';
import 'package:health_share_org/services/hive/create_transaction.dart';
import 'package:health_share_org/services/hive/sign_transaction.dart';
import 'package:health_share_org/services/hive/broadcast_transaction.dart';

/// Service for handling complete file deletion including:
/// - Deleting encryption keys from File_Keys
/// - Revoking file shares in File_Shares (setting revoked_at)
/// - Marking file as deleted in Files (setting deleted_at)
/// - Logging deletion to Hive blockchain
class FileDeleteService {
  /// Deletes a file completely by:
  /// 1. Deleting all encryption keys from File_Keys table
  /// 2. Updating revoked_at in File_Shares table
  /// 3. Updating deleted_at in Files table
  /// 4. Logging deletion to Hive blockchain
  /// Deletes a file completely by:
  /// 1. Deleting all encryption keys from File_Keys table
  /// 2. Updating revoked_at in File_Shares table
  /// 3. Updating deleted_at in Files table
  /// 4. Logging deletion to Hive blockchain
  static Future<void> deleteFile({
    required BuildContext context,
    required Map<String, dynamic> file,
    required Function(String) showSnackBar,
    required Function() onDeleteSuccess,
  }) async {
    try {
      final fileId = file['id']?.toString();
      final fileName = file['filename']?.toString() ?? 'Unknown File';
      final fileHash = file['sha256_hash']?.toString() ?? '';

      if (fileId == null || fileId == 'null') {
        showSnackBar('Error: Invalid file ID');
        return;
      }

      // Get current user ID
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        showSnackBar('Authentication error: Not logged in');
        return;
      }

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id')
          .eq('email', currentUser.email!);

      if (userResponse.isEmpty) {
        showSnackBar('User not found');
        return;
      }

      final userId = userResponse.first['id']?.toString();
      if (userId == null) {
        showSnackBar('Error: Invalid user ID');
        return;
      }

      // Check if context is still valid before showing dialog
      if (!context.mounted) return;

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final now = DateTime.now();
      final timestamp = now.toIso8601String();

      // Step 1: Delete all encryption keys for this file
      await _deleteFileKeys(fileId);

      // Step 2: Update File_Shares to mark as revoked
      await _revokeFileShares(fileId, timestamp);

      // Step 3: Update Files table to mark as deleted
      await _markFileAsDeleted(fileId, timestamp);

      // Step 4: Log deletion to Hive blockchain
      print('🔗 Logging file deletion to Hive blockchain...');
      final hiveResult = await _logDeletionToHiveBlockchain(
        fileName: fileName,
        fileHash: fileHash,
        fileId: fileId,
        userId: userId,
        timestamp: now,
        context: context,
      );

      // Check if context is still valid before closing dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      // Show success message based on Hive result
      if (hiveResult.success) {
        showSnackBar(
            'File deleted and logged to Hive blockchain successfully!');
        print('✅ HIVE BLOCKCHAIN DELETION LOGGING SUCCESSFUL');
        print('   Transaction ID: ${hiveResult.transactionId}');
        print('   Block Number: ${hiveResult.blockNum}');
      } else {
        showSnackBar(
            'File deleted successfully! (Hive logging failed - check logs)');
        print(
            '⚠️ HIVE BLOCKCHAIN DELETION LOGGING FAILED: ${hiveResult.error}');
      }

      // Trigger refresh callback
      onDeleteSuccess();
    } catch (e) {
      // Check if context is still valid before closing dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      print('Error deleting file: $e');
      showSnackBar('Error deleting file: $e');
    }
  }

  /// Deletes all encryption keys associated with a file from File_Keys table
  static Future<void> _deleteFileKeys(String fileId) async {
    try {
      print('DEBUG: Deleting keys for file_id: $fileId');

      await Supabase.instance.client
          .from('File_Keys')
          .delete()
          .eq('file_id', fileId);

      print('DEBUG: Successfully deleted keys for file_id: $fileId');
    } catch (e) {
      print('ERROR: Failed to delete file keys: $e');
      throw Exception('Failed to delete encryption keys: $e');
    }
  }

  /// Updates all File_Shares records for a file to mark them as revoked
  static Future<void> _revokeFileShares(String fileId, String timestamp) async {
    try {
      print('DEBUG: Revoking file shares for file_id: $fileId');

      await Supabase.instance.client
          .from('File_Shares')
          .update({'revoked_at': timestamp}).eq('file_id', fileId);

      print('DEBUG: Successfully revoked file shares for file_id: $fileId');
    } catch (e) {
      print('ERROR: Failed to revoke file shares: $e');
      throw Exception('Failed to revoke file shares: $e');
    }
  }

  /// Marks a file as deleted in the Files table
  static Future<void> _markFileAsDeleted(
      String fileId, String timestamp) async {
    try {
      print('DEBUG: Marking file as deleted for file_id: $fileId');

      await Supabase.instance.client
          .from('Files')
          .update({'deleted_at': timestamp}).eq('id', fileId);

      print('DEBUG: Successfully marked file as deleted for file_id: $fileId');
    } catch (e) {
      print('ERROR: Failed to mark file as deleted: $e');
      throw Exception('Failed to mark file as deleted: $e');
    }
  }

  /// 🔗 LOG FILE DELETION TO HIVE BLOCKCHAIN
  /// This orchestrates: HiveCustomJsonService → HiveTransactionService →
  /// HiveTransactionSigner → HiveTransactionBroadcaster → Hive_Logs table
  static Future<HiveLogResult> _logDeletionToHiveBlockchain({
    required String fileName,
    required String fileHash,
    required String fileId,
    required String userId,
    required DateTime timestamp,
    required BuildContext context,
  }) async {
    try {
      // Check if Hive is configured
      if (!HiveCustomJsonService.isHiveConfigured()) {
        print('Warning: Hive not configured (HIVE_ACCOUNT_NAME missing)');
        return HiveLogResult(success: false, error: 'Hive not configured');
      }

      print('🔗 Starting Hive blockchain deletion logging...');

      // 🔗 STEP 1: Create custom JSON for deletion using HiveCustomJsonService
      final customJsonResult = HiveCustomJsonService.createMedicalLogCustomJson(
        fileName: fileName,
        fileHash: fileHash,
        timestamp: timestamp,
        action: 'delete', // Specify deletion action
      );
      final customJsonOperation =
          customJsonResult['operation'] as List<dynamic>;
      print('✓ Deletion custom JSON created');

      // 🔗 STEP 2: Create unsigned transaction using HiveTransactionService
      final unsignedTransaction =
          await HiveTransactionService.createCustomJsonTransaction(
        customJsonOperation: customJsonOperation,
        expirationMinutes: 30,
      );
      print('✓ Unsigned transaction created');

      // 🔗 STEP 3: Sign transaction using HiveTransactionSigner
      final signedTransaction = await HiveTransactionSignerWeb.signTransaction(
        unsignedTransaction,
      );
      print('✓ Transaction signed');

      // 🔗 STEP 4: Broadcast transaction using HiveTransactionBroadcaster
      final broadcastResult =
          await HiveTransactionBroadcasterWeb.broadcastTransaction(
        signedTransaction,
      );

      if (broadcastResult.success) {
        print('✓ Deletion transaction broadcasted successfully!');
        print('  Transaction ID: ${broadcastResult.getTxId()}');
        print('  Block Number: ${broadcastResult.getBlockNum()}');

        // 🔗 STEP 5: Insert into Hive_Logs table
        final logSuccess = await _insertHiveDeletionLog(
          transactionId: broadcastResult.getTxId() ?? '',
          action: 'delete',
          userId: userId,
          fileId: fileId,
          fileName: fileName,
          fileHash: fileHash,
          timestamp: timestamp,
        );

        if (logSuccess) {
          print('✓ Hive deletion log inserted into database');
          return HiveLogResult(
            success: true,
            transactionId: broadcastResult.getTxId(),
            blockNum: broadcastResult.getBlockNum(),
          );
        } else {
          print('✗ Failed to insert Hive deletion log into database');
          return HiveLogResult(
            success: false,
            error:
                'Transaction broadcast succeeded but database logging failed',
          );
        }
      } else {
        print(
            '✗ Failed to broadcast deletion transaction: ${broadcastResult.getError()}');
        return HiveLogResult(success: false, error: broadcastResult.getError());
      }
    } catch (e, stackTrace) {
      print('Error logging file deletion to Hive blockchain: $e');
      print('Stack trace: $stackTrace');
      return HiveLogResult(success: false, error: e.toString());
    }
  }

  /// Insert a deletion record into the Hive_Logs table
  static Future<bool> _insertHiveDeletionLog({
    required String transactionId,
    required String action,
    required String userId,
    required String fileId,
    required String fileName,
    required String fileHash,
    required DateTime timestamp,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      final insertData = {
        'trx_id': transactionId,
        'action': action, // 'delete'
        'user_id': userId,
        'file_id': fileId,
        'timestamp': timestamp.toIso8601String(),
        'file_name': fileName,
        'file_hash': fileHash,
        'created_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('Hive_Logs').insert(insertData);
      print('Hive deletion log inserted successfully');
      return true;
    } catch (e, stackTrace) {
      print('Error inserting Hive deletion log: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Shows a confirmation dialog before deleting
  static void confirmDeleteFile({
    required BuildContext context,
    required Map<String, dynamic> file,
    required Function(String) showSnackBar,
    required Function() onDeleteSuccess,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'Delete File',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this file?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file['filename'] ?? 'Unknown File',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This action will:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Delete all encryption keys',
                    style: TextStyle(fontSize: 11),
                  ),
                  const Text(
                    '• Revoke all file shares',
                    style: TextStyle(fontSize: 11),
                  ),
                  const Text(
                    '• Mark the file as deleted',
                    style: TextStyle(fontSize: 11),
                  ),
                  const Text(
                    '• Log deletion to Hive blockchain',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              deleteFile(
                context: context,
                file: file,
                showSnackBar: showSnackBar,
                onDeleteSuccess: onDeleteSuccess,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Result class for Hive logging operations
class HiveLogResult {
  final bool success;
  final String? error;
  final String? transactionId;
  final int? blockNum;

  HiveLogResult({
    required this.success,
    this.error,
    this.transactionId,
    this.blockNum,
  });

  @override
  String toString() {
    if (success) {
      return 'HiveLogResult(success: true, txId: $transactionId, block: $blockNum)';
    } else {
      return 'HiveLogResult(success: false, error: $error)';
    }
  }
}
