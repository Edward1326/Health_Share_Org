import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Low-level utility for Hive blockchain JSON-RPC calls (Web Version)
/// Provides direct access to Hive condenser_api methods
class HiveFetchWeb {
  // Get Hive node URL from environment, fallback to default
  static String get _hiveNodeUrl =>
      dotenv.env['HIVE_NODE_URL'] ?? 'https://api.hive.blog';

  /// Fetches account history for a given username
  ///
  /// Parameters:
  /// - username: Hive account name
  /// - limit: Maximum number of operations to fetch (default: 100, max: 1000)
  ///
  /// Returns list of operations in chronological order (oldest first)
  static Future<List<Map<String, dynamic>>> getAccountHistory(
    String username,
    int limit,
  ) async {
    try {
      print('=== GET ACCOUNT HISTORY START ===');
      print('Username: $username');
      print('Limit: $limit');
      print('Node URL: $_hiveNodeUrl');

      if (limit <= 0 || limit > 1000) {
        throw ArgumentError('Limit must be between 1 and 1000');
      }

      // Hive account history params: [account, start, limit]
      // start=-1 means get most recent operations
      final requestBody = {
        'jsonrpc': '2.0',
        'method': 'condenser_api.get_account_history',
        'params': [username, -1, limit],
        'id': 1,
      };

      print('Request body:');
      print(jsonEncode(requestBody));

      final response = await http
          .post(
        Uri.parse(_hiveNodeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Flutter-Hive-Client-Web/1.0',
        },
        body: jsonEncode(requestBody),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout after 30 seconds');
        },
      );

      print('Response status: ${response.statusCode}');
      print('Response body length: ${response.body.length} bytes');

      if (response.statusCode != 200) {
        print('HTTP Error: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final responseData = jsonDecode(response.body);

      if (responseData['error'] != null) {
        final error = responseData['error'];
        final errorMessage = error['message'] ?? error.toString();
        print('RPC Error: $errorMessage');
        throw Exception('Hive RPC Error: $errorMessage');
      }

      final result = responseData['result'] as List<dynamic>;
      print('Retrieved ${result.length} operations');

      // Convert to List<Map<String, dynamic>>
      final operations = result.map((op) {
        return {
          'trx_id': op[0] as int, // Operation index
          'op': op[1] as Map<String, dynamic>, // Operation data
        };
      }).toList();

      print('=== GET ACCOUNT HISTORY END ===');
      return operations;
    } catch (e, stackTrace) {
      print('Error in getAccountHistory: $e');
      print('Stack trace: $stackTrace');
      print('=== GET ACCOUNT HISTORY END (ERROR) ===');
      rethrow;
    }
  }

  /// Fetches a specific transaction by ID
  ///
  /// Parameters:
  /// - txId: Transaction ID (hash)
  ///
  /// Returns transaction details including operations
  static Future<Map<String, dynamic>> getTransaction(String txId) async {
    try {
      print('=== GET TRANSACTION START ===');
      print('Transaction ID: $txId');
      print('Node URL: $_hiveNodeUrl');

      final requestBody = {
        'jsonrpc': '2.0',
        'method': 'condenser_api.get_transaction',
        'params': [txId],
        'id': 1,
      };

      print('Request body:');
      print(jsonEncode(requestBody));

      final response = await http
          .post(
        Uri.parse(_hiveNodeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Flutter-Hive-Client-Web/1.0',
        },
        body: jsonEncode(requestBody),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout after 30 seconds');
        },
      );

      print('Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('HTTP Error: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final responseData = jsonDecode(response.body);

      if (responseData['error'] != null) {
        final error = responseData['error'];
        final errorMessage = error['message'] ?? error.toString();
        print('RPC Error: $errorMessage');
        throw Exception('Hive RPC Error: $errorMessage');
      }

      final result = responseData['result'];

      if (result == null) {
        print('Transaction not found: $txId');
        throw Exception('Transaction not found');
      }

      print('Transaction retrieved successfully');
      print('Block number: ${result['block_num']}');
      print('Operations: ${(result['operations'] as List).length}');
      print('=== GET TRANSACTION END ===');

      return result as Map<String, dynamic>;
    } catch (e, stackTrace) {
      print('Error in getTransaction: $e');
      print('Stack trace: $stackTrace');
      print('=== GET TRANSACTION END (ERROR) ===');
      rethrow;
    }
  }

  /// Fetches a specific block by number
  ///
  /// Parameters:
  /// - blockNum: Block number
  ///
  /// Returns block details including all transactions
  static Future<Map<String, dynamic>> getBlock(int blockNum) async {
    try {
      print('=== GET BLOCK START ===');
      print('Block number: $blockNum');
      print('Node URL: $_hiveNodeUrl');

      final requestBody = {
        'jsonrpc': '2.0',
        'method': 'condenser_api.get_block',
        'params': [blockNum],
        'id': 1,
      };

      print('Request body:');
      print(jsonEncode(requestBody));

      final response = await http
          .post(
        Uri.parse(_hiveNodeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Flutter-Hive-Client-Web/1.0',
        },
        body: jsonEncode(requestBody),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout after 30 seconds');
        },
      );

      print('Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('HTTP Error: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final responseData = jsonDecode(response.body);

      if (responseData['error'] != null) {
        final error = responseData['error'];
        final errorMessage = error['message'] ?? error.toString();
        print('RPC Error: $errorMessage');
        throw Exception('Hive RPC Error: $errorMessage');
      }

      final result = responseData['result'];

      if (result == null) {
        print('Block not found: $blockNum');
        throw Exception('Block not found');
      }

      print('Block retrieved successfully');
      print('Timestamp: ${result['timestamp']}');
      print('Transactions: ${(result['transactions'] as List).length}');
      print('=== GET BLOCK END ===');

      return result as Map<String, dynamic>;
    } catch (e, stackTrace) {
      print('Error in getBlock: $e');
      print('Stack trace: $stackTrace');
      print('=== GET BLOCK END (ERROR) ===');
      rethrow;
    }
  }

  /// Tests connection to Hive node
  static Future<bool> testConnection() async {
    try {
      print('Testing connection to $_hiveNodeUrl...');
      final response = await http
          .post(
            Uri.parse(_hiveNodeUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'Flutter-Hive-Client-Web/1.0',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'condenser_api.get_dynamic_global_properties',
              'params': [],
              'id': 1,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final success = response.statusCode == 200;
      print(success ? 'Connection test passed' : 'Connection test failed');
      return success;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }

  /// Gets the configured node URL
  static String getNodeUrl() => _hiveNodeUrl;
}
