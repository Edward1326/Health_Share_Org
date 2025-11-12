import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fetch_web.dart';

/// Result class for verification operations
class VerificationResult {
  final bool success;
  final String? error;
  final String? supabaseFileHash;
  final String? blockchainFileHash;
  final String? transactionId;
  final int? blockNumber;

  VerificationResult({
    required this.success,
    this.error,
    this.supabaseFileHash,
    this.blockchainFileHash,
    this.transactionId,
    this.blockNumber,
  });

  @override
  String toString() {
    if (success) {
      return 'VerificationResult(success: true, txId: $transactionId, block: $blockNumber)';
    } else {
      return 'VerificationResult(success: false, error: $error)';
    }
  }

  bool get hashesMatch =>
      success &&
      supabaseFileHash != null &&
      blockchainFileHash != null &&
      supabaseFileHash == blockchainFileHash;
}

/// Business logic for validating file integrity before decryption (Web Version)
/// Compares blockchain data with Supabase Hive_Logs records
class HiveCompareServiceWeb {
  /// Verifies file integrity before decryption by comparing blockchain data
  /// with Supabase records
  ///
  /// Parameters:
  /// - fileId: The file ID from Supabase Files table
  /// - trxId: Optional transaction ID (if known)
  /// - username: Hive username for fallback account history search
  ///
  /// Returns true if blockchain data matches Supabase records, false otherwise
  ///
  /// Verification Flow:
  /// 1. Fetch Hive_Logs record from Supabase by file_id
  /// 2. If trx_id exists → fetch transaction from blockchain
  /// 3. If trx_id missing → fallback to account history search
  /// 4. Extract file_hash from blockchain custom_json
  /// 5. Compare blockchain file_hash with Supabase file_hash
  /// 6. Return true if match, false otherwise
  static Future<bool> verifyBeforeDecryption({
    required String fileId,
    String? trxId,
    required String username,
  }) async {
    try {
      print('=== VERIFY BEFORE DECRYPTION START ===');
      print('File ID: $fileId');
      print('Transaction ID: ${trxId ?? "Not provided"}');
      print('Username: $username');

      // STEP 1: Fetch Hive_Logs record from Supabase
      print('\n--- STEP 1: Fetching Hive_Logs from Supabase ---');
      final supabase = Supabase.instance.client;

      final hiveLogResult = await supabase
          .from('Hive_Logs')
          .select('trx_id, file_hash, user_id, file_name, timestamp')
          .eq('file_id', fileId)
          .maybeSingle();

      if (hiveLogResult == null) {
        print('❌ No Hive_Logs record found for file_id: $fileId');
        print('File may not have been logged to blockchain');
        return false;
      }

      print('✅ Hive_Logs record found:');
      print('  - trx_id: ${hiveLogResult['trx_id']}');
      print('  - file_hash: ${hiveLogResult['file_hash']}');
      print('  - user_id: ${hiveLogResult['user_id']}');
      print('  - file_name: ${hiveLogResult['file_name']}');
      print('  - timestamp: ${hiveLogResult['timestamp']}');

      final supabaseFileHash = hiveLogResult['file_hash'] as String;
      final supabaseTrxId = hiveLogResult['trx_id'] as String?;

      // Use provided trxId or fallback to Supabase trxId
      final effectiveTrxId = trxId ?? supabaseTrxId;

      String? blockchainFileHash;
      String? blockchainFileId;

      // STEP 2: Try to fetch transaction directly if trx_id exists
      if (effectiveTrxId != null && effectiveTrxId.isNotEmpty) {
        print('\n--- STEP 2: Fetching transaction from blockchain ---');
        print('Using transaction ID: $effectiveTrxId');

        try {
          final transaction = await HiveFetchWeb.getTransaction(effectiveTrxId);

          print('✅ Transaction retrieved successfully');
          print('Block number: ${transaction['block_num']}');

          // Extract custom_json operation
          final operations = transaction['operations'] as List<dynamic>;
          print('Operations count: ${operations.length}');

          final customJsonData = _extractCustomJsonData(operations);

          if (customJsonData != null) {
            blockchainFileHash = customJsonData['file_hash'] as String?;
            blockchainFileId = customJsonData['file_id'] as String?;

            print('✅ Extracted from blockchain:');
            print('  - file_hash: $blockchainFileHash');
            print('  - file_id: $blockchainFileId');
            print('  - action: ${customJsonData['action']}');
            print('  - user_id: ${customJsonData['user_id']}');
          } else {
            print('⚠️ No medical_logs custom_json found in transaction');
          }
        } catch (e) {
          print('⚠️ Failed to fetch transaction: $e');
          print('Will try fallback to account history');
        }
      }

      // STEP 3: Fallback to account history search if transaction fetch failed
      if (blockchainFileHash == null) {
        print('\n--- STEP 3: Fallback to account history search ---');
        print('Searching recent operations for file_id: $fileId');

        try {
          final accountHistory = await HiveFetchWeb.getAccountHistory(
            username,
            100, // Search last 100 operations
          );

          print('Retrieved ${accountHistory.length} operations');

          // Search through operations for matching file_id
          for (final entry in accountHistory.reversed) {
            final opData = entry['op'] as Map<String, dynamic>;
            final opType = opData['op'] as List<dynamic>;
            final opName = opType[0] as String;

            if (opName == 'custom_json') {
              final customJsonData = _extractCustomJsonFromOp(opType);

              if (customJsonData != null) {
                final opFileId = customJsonData['file_id'] as String?;

                if (opFileId == fileId) {
                  blockchainFileHash = customJsonData['file_hash'] as String?;
                  blockchainFileId = opFileId;

                  print('✅ Found matching operation in account history:');
                  print('  - file_hash: $blockchainFileHash');
                  print('  - file_id: $blockchainFileId');
                  break;
                }
              }
            }
          }

          if (blockchainFileHash == null) {
            print('❌ No matching operation found in account history');
          }
        } catch (e) {
          print('❌ Failed to search account history: $e');
        }
      }

      // STEP 4: Compare file hashes
      if (blockchainFileHash == null) {
        print('\n--- VERIFICATION FAILED ---');
        print('❌ Could not retrieve file_hash from blockchain');
        print('File cannot be verified');
        return false;
      }

      print('\n--- STEP 4: Comparing file hashes ---');
      print('Supabase file_hash:   $supabaseFileHash');
      print('Blockchain file_hash: $blockchainFileHash');

      final hashesMatch = supabaseFileHash == blockchainFileHash;

      if (hashesMatch) {
        print('✅ VERIFICATION SUCCESSFUL');
        print('File hashes match - file integrity confirmed');
      } else {
        print('❌ VERIFICATION FAILED');
        print('File hashes DO NOT match - file may be corrupted or tampered');
      }

      print('=== VERIFY BEFORE DECRYPTION END ===');
      return hashesMatch;
    } catch (e, stackTrace) {
      print('💥 Error during verification: $e');
      print('Stack trace: $stackTrace');
      print('=== VERIFY BEFORE DECRYPTION END (ERROR) ===');
      return false;
    }
  }

  /// Extracts custom_json data from transaction operations
  static Map<String, dynamic>? _extractCustomJsonData(
    List<dynamic> operations,
  ) {
    try {
      for (final operation in operations) {
        if (operation is List && operation.length >= 2) {
          final opName = operation[0] as String;

          if (opName == 'custom_json') {
            return _extractCustomJsonFromOp(operation);
          }
        }
      }
      return null;
    } catch (e) {
      print('Error extracting custom_json data: $e');
      return null;
    }
  }

  /// Extracts custom_json data from a single operation
  static Map<String, dynamic>? _extractCustomJsonFromOp(List<dynamic> op) {
    try {
      if (op.length < 2) return null;

      final opData = op[1] as Map<String, dynamic>;
      final customJsonId = opData['id'] as String?;

      if (customJsonId != 'medical_logs') {
        return null; // Not a medical log operation
      }

      final jsonString = opData['json'] as String;
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      print('Custom JSON payload: $jsonData');
      return jsonData;
    } catch (e) {
      print('Error parsing custom_json: $e');
      return null;
    }
  }

  /// Verifies multiple files in batch
  /// Returns a map of fileId -> verification result
  static Future<Map<String, bool>> verifyMultipleFiles({
    required List<String> fileIds,
    required String username,
  }) async {
    print('=== BATCH VERIFICATION START ===');
    print('Files to verify: ${fileIds.length}');

    final results = <String, bool>{};

    for (final fileId in fileIds) {
      print('\nVerifying file: $fileId');
      final result = await verifyBeforeDecryption(
        fileId: fileId,
        username: username,
      );
      results[fileId] = result;
    }

    final successCount = results.values.where((v) => v).length;
    final failCount = fileIds.length - successCount;

    print('\n=== BATCH VERIFICATION END ===');
    print('Success: $successCount / ${fileIds.length}');
    print('Failed: $failCount / ${fileIds.length}');

    return results;
  }

  /// Gets verification status for debugging
  static Future<Map<String, dynamic>> getVerificationStatus({
    required String fileId,
    required String username,
  }) async {
    final status = <String, dynamic>{};

    try {
      // Check Supabase record
      final supabase = Supabase.instance.client;
      final hiveLog = await supabase
          .from('Hive_Logs')
          .select()
          .eq('file_id', fileId)
          .maybeSingle();

      status['supabase_record_exists'] = hiveLog != null;
      if (hiveLog != null) {
        status['supabase_trx_id'] = hiveLog['trx_id'];
        status['supabase_file_hash'] = hiveLog['file_hash'];
      }

      // Check blockchain connectivity
      status['blockchain_connected'] = await HiveFetchWeb.testConnection();

      // Try verification
      status['verification_passed'] = await verifyBeforeDecryption(
        fileId: fileId,
        username: username,
      );
    } catch (e) {
      status['error'] = e.toString();
    }

    return status;
  }

  /// Enhanced verification with detailed result
  /// Enhanced verification with detailed result - STRICT MODE
  /// Enhanced verification with detailed result - STRICT MODE
  static Future<VerificationResult> verifyWithDetails({
    required String fileId,
    String? trxId,
    required String username,
  }) async {
    try {
      print('=== STRICT VERIFICATION START ===');

      // Fetch Supabase record
      final supabase = Supabase.instance.client;
      final hiveLogResult = await supabase
          .from('Hive_Logs')
          .select('trx_id, file_hash, user_id, file_name, timestamp')
          .eq('file_id', fileId)
          .maybeSingle();

      if (hiveLogResult == null) {
        return VerificationResult(
          success: false,
          error: 'No Hive_Logs record found for file',
        );
      }

      final supabaseFileHash = hiveLogResult['file_hash'] as String;
      final supabaseTrxId = hiveLogResult['trx_id'] as String?;

      // CRITICAL: We MUST have a transaction ID
      if (supabaseTrxId == null || supabaseTrxId.isEmpty) {
        return VerificationResult(
          success: false,
          error: 'No transaction ID found in Hive_Logs',
          supabaseFileHash: supabaseFileHash,
        );
      }

      print('Supabase file_hash: $supabaseFileHash');
      print('Supabase trx_id: $supabaseTrxId');

      // STRICT MODE: Only use the exact transaction ID from database
      // NO FALLBACK to account history search
      String? blockchainFileHash;
      int? blockNumber;

      try {
        print('Fetching transaction: $supabaseTrxId');
        final transaction = await HiveFetchWeb.getTransaction(supabaseTrxId);
        blockNumber = transaction['block_num'] as int?;

        final operations = transaction['operations'] as List<dynamic>;
        final customJsonData = _extractCustomJsonData(operations);

        if (customJsonData == null) {
          return VerificationResult(
            success: false,
            error: 'No medical_logs custom_json found in transaction',
            supabaseFileHash: supabaseFileHash,
            transactionId: supabaseTrxId,
          );
        }

        // Extract file_hash from blockchain (file_id is not stored in blockchain)
        blockchainFileHash = customJsonData['file_hash'] as String?;

        if (blockchainFileHash == null) {
          return VerificationResult(
            success: false,
            error: 'No file_hash found in blockchain transaction',
            supabaseFileHash: supabaseFileHash,
            transactionId: supabaseTrxId,
          );
        }

        print('Blockchain file_hash: $blockchainFileHash');
      } catch (e) {
        // CRITICAL: If we can't fetch the exact transaction, verification FAILS
        // DO NOT fall back to account history
        print('Failed to fetch transaction: $e');
        return VerificationResult(
          success: false,
          error: 'Failed to fetch transaction from blockchain: $e',
          supabaseFileHash: supabaseFileHash,
          transactionId: supabaseTrxId,
        );
      }

      // Final comparison
      final hashesMatch = supabaseFileHash == blockchainFileHash;

      if (!hashesMatch) {
        print('❌ HASH MISMATCH DETECTED');
        print('Supabase:   $supabaseFileHash');
        print('Blockchain: $blockchainFileHash');
      } else {
        print('✅ HASHES MATCH - Verification passed');
      }

      return VerificationResult(
        success: hashesMatch,
        supabaseFileHash: supabaseFileHash,
        blockchainFileHash: blockchainFileHash,
        transactionId: supabaseTrxId,
        blockNumber: blockNumber,
        error: hashesMatch
            ? null
            : 'File hash mismatch - file may be corrupted or tampered',
      );
    } catch (e, stackTrace) {
      print('Error in verifyWithDetails: $e');
      print('Stack trace: $stackTrace');
      return VerificationResult(
        success: false,
        error: 'Verification error: $e',
      );
    }
  }
}
