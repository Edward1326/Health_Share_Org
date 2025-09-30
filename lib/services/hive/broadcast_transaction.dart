import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HiveTransactionBroadcasterWeb {
  // Get Hive node URL from environment
  static String get _hiveNodeUrl =>
      dotenv.env['HIVE_NODE_URL'] ?? 'https://api.hive.blog';

  /// Broadcasts a signed transaction (synchronous only)
  static Future<HiveBroadcastResult> broadcastTransaction(
    Map<String, dynamic> signedTransaction,
  ) async {
    try {
      print('=== BROADCAST TRANSACTION (WEB) DEBUG START ===');

      // Validate transaction before broadcasting
      if (!_isValidSignedTransaction(signedTransaction)) {
        print('Transaction validation failed');
        return HiveBroadcastResult.error('Invalid transaction format');
      }
      print('Transaction validation passed');

      // Always use synchronous broadcast
      final requestBody = {
        "jsonrpc": "2.0",
        "method": "condenser_api.broadcast_transaction_synchronous",
        "params": [signedTransaction],
        "id": 1,
      };

      print('Broadcasting transaction to: $_hiveNodeUrl');
      print('Request method: condenser_api.broadcast_transaction_synchronous');
      print('Request ID: ${requestBody['id']}');
      print('Full request body structure:');
      print('  - jsonrpc: ${requestBody['jsonrpc']}');
      print('  - method: ${requestBody['method']}');
      print('  - params type: ${requestBody['params'].runtimeType}');
      print('  - params length: ${(requestBody['params'] as List).length}');
      print('  - id: ${requestBody['id']}');

      print('Transaction details:');
      print('  - ref_block_num: ${signedTransaction['ref_block_num']}');
      print('  - ref_block_prefix: ${signedTransaction['ref_block_prefix']}');
      print('  - expiration: ${signedTransaction['expiration']}');
      print(
        '  - operations count: ${(signedTransaction['operations'] as List).length}',
      );
      print(
        '  - signatures count: ${(signedTransaction['signatures'] as List).length}',
      );
      print('  - extensions: ${signedTransaction['extensions']}');

      print('Full transaction JSON:');
      final transactionJson = jsonEncode(signedTransaction);
      print(transactionJson);

      print('Full request JSON:');
      final requestJson = jsonEncode(requestBody);
      print(requestJson);

      print('Request size: ${utf8.encode(requestJson).length} bytes');

      print('Sending HTTP POST request...');
      final response = await http
          .post(
            Uri.parse(_hiveNodeUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Flutter-Web-Hive-Client/1.0',
            },
            body: requestJson,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('Request timed out after 30 seconds');
              throw Exception('Request timeout');
            },
          );

      print('Response received:');
      print('  - Status Code: ${response.statusCode}');
      print('  - Content-Type: ${response.headers['content-type']}');
      print('  - Content-Length: ${response.headers['content-length']}');
      print('  - Server: ${response.headers['server']}');
      print('Full response body:');
      print(response.body);

      if (response.statusCode != 200) {
        print('HTTP Error: ${response.statusCode}');
        print('Response headers: ${response.headers}');
        return HiveBroadcastResult.error(
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(response.body);
        print('Response JSON parsed successfully');
        print('Response structure:');
        responseData.forEach((key, value) {
          print('  - $key: ${value.runtimeType} = $value');
        });
      } catch (e) {
        print('Failed to parse response JSON: $e');
        return HiveBroadcastResult.error('Invalid JSON response: $e');
      }

      if (responseData['error'] != null) {
        final error = responseData['error'];
        print('RPC Error detected:');
        print('  - Error object: $error');
        print('  - Error type: ${error.runtimeType}');

        final errorMessage = error['message'] ?? error.toString();
        final errorCode = error['code'] ?? -1;
        print('  - Error code: $errorCode');
        print('  - Error message: $errorMessage');

        if (error['data'] != null) {
          print('  - Error data: ${error['data']}');
        }

        return HiveBroadcastResult.error('RPC Error $errorCode: $errorMessage');
      }

      final result = responseData['result'];
      print('Broadcast successful!');
      print('Result: $result');
      print('=== BROADCAST TRANSACTION (WEB) DEBUG END ===');

      return HiveBroadcastResult.success(result);
    } catch (e, stackTrace) {
      print('Exception caught during broadcast:');
      print('Error: $e');
      print('Error type: ${e.runtimeType}');
      print('Stack trace:');
      print(stackTrace.toString());
      print('=== BROADCAST TRANSACTION (WEB) DEBUG END (ERROR) ===');
      return HiveBroadcastResult.error('Broadcast failed: $e');
    }
  }

  /// Alternative method using condenser_api (synchronous only)
  static Future<HiveBroadcastResult> broadcastTransactionCondenser(
    Map<String, dynamic> signedTransaction,
  ) async {
    try {
      print('=== CONDENSER BROADCAST (WEB) DEBUG START ===');

      if (!_isValidSignedTransaction(signedTransaction)) {
        print('Condenser transaction validation failed');
        return HiveBroadcastResult.error('Invalid transaction format');
      }
      print('Condenser transaction validation passed');

      final requestBody = {
        'jsonrpc': '2.0',
        'method': 'condenser_api.broadcast_transaction_synchronous',
        'params': [signedTransaction],
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      print('Broadcasting via condenser_api to: $_hiveNodeUrl');
      print('Request method: condenser_api.broadcast_transaction_synchronous');
      print('Request ID: ${requestBody['id']}');

      print('Full condenser request JSON:');
      final requestJson = jsonEncode(requestBody);
      print(requestJson);

      print('Sending condenser HTTP POST request...');
      final response = await http
          .post(
            Uri.parse(_hiveNodeUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Flutter-Web-Hive-Client/1.0',
            },
            body: requestJson,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('Condenser request timed out after 30 seconds');
              throw Exception('Condenser request timeout');
            },
          );

      print('Condenser response received:');
      print('  - Status Code: ${response.statusCode}');
      print('  - Content-Type: ${response.headers['content-type']}');
      print('Condenser response body:');
      print(response.body);

      if (response.statusCode != 200) {
        print('Condenser HTTP Error: ${response.statusCode}');
        return HiveBroadcastResult.error(
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(response.body);
        print('Condenser response JSON parsed successfully');
      } catch (e) {
        print('Failed to parse condenser response JSON: $e');
        return HiveBroadcastResult.error('Invalid JSON response: $e');
      }

      if (responseData['error'] != null) {
        final error = responseData['error'];
        print('Condenser RPC Error: $error');
        final errorMessage = error['message'] ?? error.toString();
        final errorCode = error['code'] ?? -1;
        return HiveBroadcastResult.error('RPC Error $errorCode: $errorMessage');
      }

      final result = responseData['result'];
      print('Condenser broadcast successful!');
      print('Condenser result: $result');
      print('=== CONDENSER BROADCAST (WEB) DEBUG END ===');

      return HiveBroadcastResult.success(result);
    } catch (e, stackTrace) {
      print('Condenser exception caught:');
      print('Error: $e');
      print('Stack trace:');
      print(stackTrace.toString());
      print('=== CONDENSER BROADCAST (WEB) DEBUG END (ERROR) ===');
      return HiveBroadcastResult.error('Condenser broadcast failed: $e');
    }
  }

  /// Smart broadcast (tries both APIs if one fails)
  static Future<HiveBroadcastResult> smartBroadcast(
    Map<String, dynamic> signedTransaction,
  ) async {
    print('Starting smart broadcast (web)...');
    print('Attempt 1: condenser_api');
    var result = await broadcastTransactionCondenser(signedTransaction);

    if (result.success) {
      print('Smart broadcast succeeded with condenser_api');
      return result;
    }

    print('condenser_api failed: ${result.getError()}');
    print('Attempt 2: network_broadcast_api');
    result = await broadcastTransaction(signedTransaction);

    if (result.success) {
      print('Smart broadcast succeeded with network_broadcast_api');
      return result;
    }

    print('Both APIs failed');
    return HiveBroadcastResult.error(
      'Both condenser_api and network_broadcast_api failed. Last error: ${result.getError()}',
    );
  }

  /// Validates that a transaction is properly signed
  static bool _isValidSignedTransaction(Map<String, dynamic> transaction) {
    print('Validating transaction structure...');

    final requiredFields = [
      'ref_block_num',
      'ref_block_prefix',
      'expiration',
      'operations',
      'extensions',
      'signatures',
    ];

    for (final field in requiredFields) {
      if (!transaction.containsKey(field)) {
        print('Missing required field: $field');
        return false;
      }
      print('Found field: $field (${transaction[field].runtimeType})');
    }

    final signatures = transaction['signatures'] as List?;
    if (signatures == null || signatures.isEmpty) {
      print('Transaction has no signatures');
      return false;
    }
    print('Found ${signatures.length} signature(s)');

    final operations = transaction['operations'] as List?;
    if (operations == null || operations.isEmpty) {
      print('Transaction has no operations');
      return false;
    }
    print('Found ${operations.length} operation(s)');

    // Validate each operation structure
    for (int i = 0; i < operations.length; i++) {
      final op = operations[i];
      print('Operation $i: ${op.runtimeType}');
      if (op is List && op.length >= 2) {
        print('  - Operation type: ${op[0]}');
        print('  - Operation data type: ${op[1].runtimeType}');
      } else {
        print('Invalid operation structure at index $i');
        return false;
      }
    }

    print('Transaction validation complete');
    return true;
  }

  static String getHiveNodeUrl() => _hiveNodeUrl;

  static Future<bool> testConnection() async {
    print('Testing connection to $_hiveNodeUrl...');
    try {
      final response = await http
          .post(
            Uri.parse(_hiveNodeUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'Flutter-Web-Hive-Client/1.0',
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
      if (!success) {
        print('Status: ${response.statusCode}, Body: ${response.body}');
      }
      return success;
    } catch (e) {
      print('Connection test failed with exception: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getNodeInfo() async {
    print('Getting node info from $_hiveNodeUrl...');
    try {
      final response = await http.post(
        Uri.parse(_hiveNodeUrl),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Flutter-Web-Hive-Client/1.0',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'condenser_api.get_version',
          'params': [],
          'id': 1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Node info retrieved: ${data['result']}');
        return data['result'] as Map<String, dynamic>?;
      }
      print('Failed to get node info: HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      print('Failed to get node info with exception: $e');
      return null;
    }
  }

  static int estimateTransactionSize(Map<String, dynamic> transaction) {
    final jsonString = jsonEncode(transaction);
    final size = utf8.encode(jsonString).length;
    print('Estimated transaction size: $size bytes');
    return size;
  }
}

/// Result class for broadcast operations
class HiveBroadcastResult {
  final bool success;
  final String? error;
  final Map<String, dynamic>? data;
  final String? transactionId;
  final int? blockNum;

  HiveBroadcastResult._({
    required this.success,
    this.error,
    this.data,
    this.transactionId,
    this.blockNum,
  });

  factory HiveBroadcastResult.success(Map<String, dynamic> result) {
    return HiveBroadcastResult._(
      success: true,
      data: result,
      transactionId: result['id'] as String?,
      blockNum: result['block_num'] as int?,
    );
  }

  factory HiveBroadcastResult.error(String errorMessage) {
    return HiveBroadcastResult._(success: false, error: errorMessage);
  }

  @override
  String toString() {
    if (success) {
      return 'HiveBroadcastResult(success: true, transactionId: $transactionId, blockNum: $blockNum)';
    } else {
      return 'HiveBroadcastResult(success: false, error: $error)';
    }
  }

  String? getTxId() => transactionId;
  int? getBlockNum() => blockNum;
  Map<String, dynamic>? getData() => data;
  String? getError() => error;
}