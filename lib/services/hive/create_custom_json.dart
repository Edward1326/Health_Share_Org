import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Hive Blockchain Custom JSON Service for Web
/// 
/// This service creates custom JSON operations for logging medical file
/// uploads to the Hive blockchain. Works in web environment.
/// 
/// Required Environment Variables:
/// - HIVE_ACCOUNT_NAME: Your Hive blockchain account name
class HiveCustomJsonService {
  // Get Hive account name from environment
  static final String _hiveAccountName = dotenv.env['HIVE_ACCOUNT_NAME'] ?? '';

  /// Creates a custom JSON for Hive blockchain medical logs
  ///
  /// This method generates a properly formatted custom_json operation
  /// that can be submitted to the Hive blockchain to create an immutable
  /// record of a medical file upload.
  ///
  /// Parameters:
  /// - fileName: The name of the uploaded file
  /// - fileHash: The SHA-256 hash of the file (before encryption)
  /// - timestamp: Optional timestamp (defaults to current time)
  ///
  /// Returns a Map containing:
  /// - "operation": The custom_json operation array for Hive
  /// - "payload_data": The structured data (for debugging/logging)
  ///
  /// Throws:
  /// - Exception if HIVE_ACCOUNT_NAME is not configured
  static Map<String, dynamic> createMedicalLogCustomJson({
  required String fileName,
  required String fileHash,
  DateTime? timestamp,
  String action = 'upload', // Add this parameter with default value
}) {
  if (_hiveAccountName.isEmpty) {
    throw Exception('HIVE_ACCOUNT_NAME not found in environment variables');
  }

  // Use provided timestamp or current time
  final logTimestamp = timestamp ?? DateTime.now();

  // Create the medical log payload
  final medicalLogData = {
    "action": action, // Use the parameter instead of hardcoded "upload"
    "user_id": _hiveAccountName,
    "file_name": fileName,
    "file_hash": fileHash,
    "timestamp": logTimestamp.toUtc().toIso8601String(),
  };

  // Convert payload to JSON string
  final jsonPayload = jsonEncode(medicalLogData);

  // Create the custom_json operation following Hive blockchain format
  final customJsonOperation = [
    "custom_json",
    {
      "id": "medical_logs",
      "json": jsonPayload,
      "required_auths": <String>[],
      "required_posting_auths": [_hiveAccountName],
    },
  ];

  return {
    "operation": customJsonOperation,
    "payload_data": medicalLogData, // For debugging/logging purposes
  };
}

  /// Creates a custom JSON string ready for Hive blockchain submission
  ///
  /// This is a convenience method that returns the operation as a JSON string
  /// instead of a Map structure.
  ///
  /// Parameters:
  /// - fileName: The name of the uploaded file
  /// - fileHash: The SHA-256 hash of the file
  /// - timestamp: Optional timestamp (defaults to current time)
  ///
  /// Returns a JSON string of the custom_json operation
  static String createMedicalLogCustomJsonString({
    required String fileName,
    required String fileHash,
    DateTime? timestamp,
  }) {
    final customJson = createMedicalLogCustomJson(
      fileName: fileName,
      fileHash: fileHash,
      timestamp: timestamp,
    );
    return jsonEncode(customJson["operation"]);
  }

  /// Validates environment setup for Hive integration
  ///
  /// Call this before attempting to create Hive operations to ensure
  /// proper configuration.
  ///
  /// Returns true if HIVE_ACCOUNT_NAME is configured, false otherwise
  static bool isHiveConfigured() {
    return _hiveAccountName.isNotEmpty;
  }

  /// Gets the configured Hive account name
  ///
  /// Returns the Hive account name from environment variables,
  /// or an empty string if not configured
  static String getHiveAccountName() {
    return _hiveAccountName;
  }

  /// Validates that a custom JSON operation has the correct structure
  ///
  /// Useful for debugging and testing
  ///
  /// Returns true if the operation appears valid, false otherwise
  static bool validateCustomJsonStructure(Map<String, dynamic> operation) {
    try {
      final op = operation["operation"] as List<dynamic>;
      if (op.length != 2) return false;
      if (op[0] != "custom_json") return false;

      final params = op[1] as Map<String, dynamic>;
      return params.containsKey("id") &&
          params.containsKey("json") &&
          params.containsKey("required_posting_auths");
    } catch (e) {
      return false;
    }
  }
}