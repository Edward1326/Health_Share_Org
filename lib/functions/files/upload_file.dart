import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:health_share_org/services/hive/create_custom_json.dart';
import 'package:health_share_org/services/hive/create_transaction.dart';
import 'package:health_share_org/services/hive/sign_transaction.dart';
import 'package:health_share_org/services/hive/broadcast_transaction.dart';

class FileUploadService {
  // Define app theme colors
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color darkGray = Color(0xFF757575);

  // File size limits
  static const int MAX_FILE_SIZE_MB = 200;
  static const int MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;
  static const int LARGE_FILE_WARNING_MB = 5;
  static const int LARGE_FILE_WARNING_BYTES =
      LARGE_FILE_WARNING_MB * 1024 * 1024;

  // Cryptography instances
  static final _aesGcm = AesGcm.with256bits();

  // Helper method to generate secure random bytes
  static Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (i) => random.nextInt(256)));
  }

  // Helper method to calculate SHA256 hash
  static String _calculateSHA256(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  // Format file size for display
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // Check if file size is acceptable
  static bool isFileSizeAcceptable(int fileSize) {
    return fileSize <= MAX_FILE_SIZE_BYTES;
  }

  // Show file size warning dialog
  static Future<bool?> showFileSizeWarning(
    BuildContext context,
    String fileName,
    int fileSize,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
            const SizedBox(width: 12),
            const Text('Large File Detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: $fileName'),
            Text('Size: ${formatFileSize(fileSize)}'),
            const SizedBox(height: 16),
            Text(
              'This file may take several minutes to encrypt and upload.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            if (fileSize > MAX_FILE_SIZE_BYTES)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'File exceeds ${MAX_FILE_SIZE_MB}MB limit!',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          if (fileSize <= MAX_FILE_SIZE_BYTES)
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue Anyway'),
            ),
        ],
      ),
    );
  }

  // AES-256-GCM encryption using cryptography package - consistent format with mobile
  static Future<Uint8List> _encryptWithAES256GCM(
      Uint8List data, Uint8List key, Uint8List nonce) async {
    try {
      print('Starting AES-256-GCM encryption...');
      print('Data size: ${data.length} bytes');
      print('Key size: ${key.length} bytes');
      print('Nonce size: ${nonce.length} bytes');

      final secretKey = SecretKey(key);

      final secretBox = await _aesGcm.encrypt(
        data,
        secretKey: secretKey,
        nonce: nonce,
      );

      print('AES encryption completed successfully');

      // Format: [ciphertext][16-byte MAC] (consistent with mobile services)
      final result =
          Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
      result.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
      result.setRange(
          secretBox.cipherText.length, result.length, secretBox.mac.bytes);

      print(
          'Combined encrypted data: ${result.length} bytes (${secretBox.cipherText.length} ciphertext + ${secretBox.mac.bytes.length} MAC)');

      return result;
    } catch (e) {
      print('AES-256-GCM encryption error: $e');
      rethrow;
    }
  }

  // Parse RSA public key from PEM format using PointyCastle - handles both PKCS#1 and PKCS#8
  static RSAPublicKey _parseRSAPublicKeyFromPem(String pem) {
    try {
      print('Parsing RSA public key from PEM...');

      // Clean the PEM string
      final cleanPem = pem.trim();

      // Determine the format
      bool isPkcs1 = cleanPem.contains('-----BEGIN RSA PUBLIC KEY-----');
      bool isPkcs8 = cleanPem.contains('-----BEGIN PUBLIC KEY-----');

      if (!isPkcs1 && !isPkcs8) {
        throw FormatException('Invalid PEM format - missing proper headers');
      }

      String lines;
      if (isPkcs1) {
        print('Detected PKCS#1 format');
        lines = cleanPem
            .replaceAll('-----BEGIN RSA PUBLIC KEY-----', '')
            .replaceAll('-----END RSA PUBLIC KEY-----', '')
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .replaceAll(' ', '')
            .trim();
      } else {
        print('Detected PKCS#8 format');
        lines = cleanPem
            .replaceAll('-----BEGIN PUBLIC KEY-----', '')
            .replaceAll('-----END PUBLIC KEY-----', '')
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .replaceAll(' ', '')
            .trim();
      }

      if (lines.isEmpty) {
        throw FormatException('Empty key data after cleaning');
      }

      final keyBytes = base64Decode(lines);

      if (isPkcs1) {
        // PKCS#1 format - direct RSA key structure
        final publicKeyParser = ASN1Parser(keyBytes);
        final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;

        final modulus =
            (publicKeySeq.elements[0] as ASN1Integer).valueAsBigInteger;
        final exponent =
            (publicKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;

        print(
            'PKCS#1 RSA key parsed - Modulus bits: ${modulus!.bitLength}, Exponent: $exponent');
        return RSAPublicKey(modulus, exponent!);
      } else {
        // PKCS#8 format - wrapped in algorithm identifier
        final asn1Parser = ASN1Parser(keyBytes);
        final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

        // Extract the public key bit string
        final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;
        final publicKeyBytes = publicKeyBitString.contentBytes();

        // Parse the RSA public key structure
        final publicKeyParser = ASN1Parser(publicKeyBytes);
        final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;

        final modulus =
            (publicKeySeq.elements[0] as ASN1Integer).valueAsBigInteger;
        final exponent =
            (publicKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;

        print(
            'PKCS#8 RSA key parsed - Modulus bits: ${modulus!.bitLength}, Exponent: $exponent');
        return RSAPublicKey(modulus, exponent!);
      }
    } catch (e) {
      print('Error parsing RSA public key from PEM: $e');
      print(
          'PEM content (first 100 chars): ${pem.substring(0, pem.length > 100 ? 100 : pem.length)}');
      rethrow;
    }
  }

  // RSA-OAEP encryption using PointyCastle
  static String _encryptWithRSAOAEP(String data, String publicKeyPem) {
    try {
      print('Starting RSA-OAEP encryption...');
      print('Data to encrypt length: ${data.length} characters');

      final publicKey = _parseRSAPublicKeyFromPem(publicKeyPem);

      // Create OAEP encryptor with SHA-256
      final encryptor = OAEPEncoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

      final dataBytes = utf8.encode(data);
      final encryptedBytes = encryptor.process(Uint8List.fromList(dataBytes));
      final encryptedBase64 = base64Encode(encryptedBytes);

      print('RSA-OAEP encryption completed successfully');
      print('Encrypted data length: ${encryptedBase64.length} characters');

      return encryptedBase64;
    } catch (e) {
      print('RSA-OAEP encryption error: $e');
      rethrow;
    }
  }

  /// 🔗 MAIN INTEGRATION METHOD - Connects all Hive services and logs to database
  /// This orchestrates: HiveCustomJsonService → HiveTransactionService →
  /// HiveTransactionSigner → HiveTransactionBroadcaster → Hive_Logs table
  static Future<HiveLogResult> _logToHiveBlockchain({
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

      print('🔗 Starting Hive blockchain logging...');

      // 🔗 STEP 1: Create custom JSON using HiveCustomJsonService
      final customJsonResult = HiveCustomJsonService.createMedicalLogCustomJson(
        fileName: fileName,
        fileHash: fileHash,
        timestamp: timestamp,
      );
      final customJsonOperation =
          customJsonResult['operation'] as List<dynamic>;
      print('✓ Custom JSON created');

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
        print('✓ Transaction broadcasted successfully!');
        print('  Transaction ID: ${broadcastResult.getTxId()}');
        print('  Block Number: ${broadcastResult.getBlockNum()}');

        // 🔗 STEP 5: Insert into Hive_Logs table
        final logSuccess = await _insertHiveLog(
          transactionId: broadcastResult.getTxId() ?? '',
          action: 'upload',
          userId: userId,
          fileId: fileId,
          fileName: fileName,
          fileHash: fileHash,
          timestamp: timestamp,
        );

        if (logSuccess) {
          print('✓ Hive log inserted into database');
          return HiveLogResult(
            success: true,
            transactionId: broadcastResult.getTxId(),
            blockNum: broadcastResult.getBlockNum(),
          );
        } else {
          print('✗ Failed to insert Hive log into database');
          return HiveLogResult(
            success: false,
            error:
                'Transaction broadcast succeeded but database logging failed',
          );
        }
      } else {
        print(
            '✗ Failed to broadcast transaction: ${broadcastResult.getError()}');
        return HiveLogResult(success: false, error: broadcastResult.getError());
      }
    } catch (e, stackTrace) {
      print('Error logging to Hive blockchain: $e');
      print('Stack trace: $stackTrace');
      return HiveLogResult(success: false, error: e.toString());
    }
  }

  /// Insert a record into the Hive_Logs table
  static Future<bool> _insertHiveLog({
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
        'action': action,
        'user_id': userId,
        'file_id': fileId,
        'timestamp': timestamp.toIso8601String(),
        'file_name': fileName,
        'file_hash': fileHash,
        'created_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('Hive_Logs').insert(insertData);
      print('Hive log inserted successfully');
      return true;
    } catch (e, stackTrace) {
      print('Error inserting Hive log: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  static Future<void> uploadFileForPatient(
    BuildContext context,
    Map<String, dynamic> selectedPatient,
    Function(String) showSnackBar,
    Function() onUploadComplete,
  ) async {
    if (selectedPatient == null) return;

    try {
      print('=== STARTING FILE UPLOAD PROCESS WITH HIVE INTEGRATION ===');
      print(
          'Using PointyCastle RSA-OAEP + cryptography AES-256-GCM (consistent format)');

      // Step 1: Create HTML file input for web compatibility
      print('Step 1: Creating file input dialog...');
      final html.InputElement uploadInput = html.InputElement(type: 'file');
      uploadInput.accept = '.pdf,.jpg,.jpeg,.png,.doc,.docx,.txt';
      uploadInput.click();

      // Wait for file selection
      await uploadInput.onChange.first;

      if (uploadInput.files == null || uploadInput.files!.isEmpty) {
        showSnackBar('No file selected');
        return;
      }

      final file = uploadInput.files!.first;
      final fileName = file.name;
      final fileSize = file.size;
      final fileExtension = fileName.split('.').last.toLowerCase();

      print(
          'File selected: $fileName (${fileSize} bytes - ${formatFileSize(fileSize)})');

      // Step 2: Check file size
      if (!isFileSizeAcceptable(fileSize)) {
        showSnackBar(
            'File too large! Maximum size is ${MAX_FILE_SIZE_MB}MB. Your file is ${formatFileSize(fileSize)}');
        print('File rejected: exceeds ${MAX_FILE_SIZE_MB}MB limit');
        return;
      }

      // Warn about large files
      if (fileSize > LARGE_FILE_WARNING_BYTES) {
        print(
            'Large file detected (>${LARGE_FILE_WARNING_MB}MB), showing warning...');
        final shouldContinue =
            await showFileSizeWarning(context, fileName, fileSize);
        if (shouldContinue != true) {
          print('User cancelled large file upload');
          return;
        }
        print('User confirmed large file upload');
      }

      // Step 3: Read file as bytes
      print('Step 2: Reading file as bytes...');
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final Uint8List fileBytes = reader.result as Uint8List;
      print('File read successfully: ${fileBytes.length} bytes');

      // Step 4: Show file details dialog and get description
      print('Step 3: Getting file details from user...');
      final fileDetails =
          await _showFileDetailsDialog(context, fileName, fileSize);
      if (fileDetails == null) {
        print('User cancelled file upload');
        return;
      }

      // Show loading dialog with file info
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: primaryBlue),
              const SizedBox(height: 16),
              Text('Encrypting and uploading $fileName...'),
              const SizedBox(height: 8),
              Text(
                'Size: ${formatFileSize(fileSize)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (fileSize > LARGE_FILE_WARNING_BYTES) ...[
                const SizedBox(height: 8),
                const Text(
                  'This may take several minutes',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      );

      // Step 5: Get current user info
      print('Step 4: Getting current user info...');
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        Navigator.pop(context);
        showSnackBar('Authentication error: Not logged in');
        return;
      }

      // Get or create user in database
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id')
          .eq('email', currentUser.email!);

      String? uploaderId;

      if (userResponse.isEmpty) {
        // Create new user record
        try {
          final newUserResponse = await Supabase.instance.client
              .from('User')
              .insert({
                'id': currentUser.id,
                'email': currentUser.email!,
                'created_at': DateTime.now().toIso8601String(),
              })
              .select('id')
              .single();

          uploaderId = newUserResponse['id'];
          print('Created new user with ID: $uploaderId');
        } catch (createError) {
          Navigator.pop(context);
          showSnackBar('Error creating user record: $createError');
          return;
        }
      } else {
        uploaderId = userResponse.first['id'];
        print('Found existing user with ID: $uploaderId');
      }

      if (uploaderId == null) {
        Navigator.pop(context);
        showSnackBar('Failed to get user ID');
        return;
      }

      // Step 6: Generate AES key and nonce for GCM mode
      print('Step 5: Generating AES-256 key and nonce...');
      final aesKey = _generateRandomBytes(32); // 32 bytes for AES-256
      final aesNonce = _generateRandomBytes(12); // 12 bytes for GCM nonce

      print('Generated AES-256 key (base64): ${base64Encode(aesKey)}');
      print('Generated GCM nonce (base64): ${base64Encode(aesNonce)}');

      // Step 7: Encrypt file with AES-256-GCM (using consistent format)
      print('Step 6: Encrypting file with AES-256-GCM...');
      final encryptedBytes =
          await _encryptWithAES256GCM(fileBytes, aesKey, aesNonce);

      print('Original file size: ${fileBytes.length} bytes');
      print('Encrypted file size: ${encryptedBytes.length} bytes');

      // 🔐 Step 8: Calculate SHA256 hash of ENCRYPTED file (for Hive logging and IPFS verification)
      print('Step 7: Calculating SHA256 hash of ENCRYPTED file...');
      final sha256Hash =
          _calculateSHA256(encryptedBytes); // ✅ HASH THE ENCRYPTED FILE!
      print('Encrypted file SHA256 hash: $sha256Hash');

      // Step 9: Get patient's RSA public key
      print('Step 8: Getting patient RSA public key...');
      final patientId = selectedPatient['patient_id'];

      final patientResponse = await Supabase.instance.client
          .from('Patient')
          .select('id, user_id')
          .eq('id', patientId);

      if (patientResponse.isEmpty) {
        Navigator.pop(context);
        showSnackBar(
            'Patient not found in Patient table. Patient ID: $patientId');
        return;
      }

      final patientData = patientResponse.first;
      final patientUserId = patientData['user_id'];

      final patientUserResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_public_key, email')
          .eq('id', patientUserId);

      if (patientUserResponse.isEmpty) {
        Navigator.pop(context);
        showSnackBar('Patient user record not found. User ID: $patientUserId');
        return;
      }

      final patientUserData = patientUserResponse.first;
      final patientRsaPublicKeyPem =
          patientUserData['rsa_public_key'] as String?;

      if (patientRsaPublicKeyPem == null || patientRsaPublicKeyPem.isEmpty) {
        Navigator.pop(context);
        showSnackBar('Patient does not have an RSA public key');
        return;
      }

      print('Patient RSA public key retrieved');

      // Step 10: Get doctor's RSA public key
      print('Step 9: Getting doctor RSA public key...');
      final doctorResponse = await Supabase.instance.client
          .from('User')
          .select('rsa_public_key')
          .eq('id', uploaderId);

      if (doctorResponse.isEmpty) {
        Navigator.pop(context);
        showSnackBar('Doctor user record not found');
        return;
      }

      final doctorData = doctorResponse.first;
      final doctorRsaPublicKeyPem = doctorData['rsa_public_key'] as String?;

      if (doctorRsaPublicKeyPem == null || doctorRsaPublicKeyPem.isEmpty) {
        Navigator.pop(context);
        showSnackBar(
            'Doctor does not have an RSA public key. Please generate keys first.');
        return;
      }

      print('Doctor RSA public key retrieved');

      // Step 11: Encrypt AES key and nonce with RSA-OAEP using PointyCastle (consistent format)
      print('Step 10: Encrypting AES key with RSA-OAEP...');
      final keyData = {
        'key': base64Encode(aesKey), // BASE64 format (consistent with mobile)
        'nonce':
            base64Encode(aesNonce), // BASE64 format (consistent with mobile)
      };
      final keyDataJson = jsonEncode(keyData);

      print('Key data JSON: $keyDataJson');

      final patientRsaEncryptedString =
          _encryptWithRSAOAEP(keyDataJson, patientRsaPublicKeyPem);
      final doctorRsaEncryptedString =
          _encryptWithRSAOAEP(keyDataJson, doctorRsaPublicKeyPem);

      print('RSA-OAEP encryption completed for both patient and doctor');

      // Step 12: Upload encrypted file to IPFS
      print('Step 11: Uploading encrypted file to IPFS...');

      final url = Uri.parse('https://api.pinata.cloud/pinning/pinFileToIPFS');
      final String jwt = dotenv.env['PINATA_JWT'] ?? '';

      if (jwt.isEmpty) {
        Navigator.pop(context);
        showSnackBar('Pinata JWT not configured');
        return;
      }

      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer $jwt';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encryptedBytes,
          filename: 'encrypted_${DateTime.now().millisecondsSinceEpoch}.bin',
        ),
      );

      final metadata = {
        'name': 'Medical File - ${fileDetails['fileName']}',
        'keyvalues': {
          'originalFileName': fileDetails['fileName'],
          'category': fileDetails['category'],
          'uploadedBy': uploaderId,
          'patientId': selectedPatient['patient_id'],
          'encrypted': 'true',
          'algorithm': 'AES-256-GCM (cryptography) + RSA-OAEP (pointycastle)',
          'uploadDate': DateTime.now().toIso8601String(),
        }
      };

      request.fields['pinataMetadata'] = jsonEncode(metadata);

      final options = {
        'cidVersion': 1,
        'wrapWithDirectory': false,
      };

      request.fields['pinataOptions'] = jsonEncode(options);

      print('Sending IPFS upload request (timeout: 10 minutes)...');
      final streamedResponse = await request.send().timeout(
            const Duration(minutes: 10), // Increased timeout for large files
          );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final ipfsJson = jsonDecode(response.body);
        final ipfsCid = ipfsJson['IpfsHash'] as String;
        print('IPFS upload successful. CID: $ipfsCid');

        // Step 13: Create file record in Files table
        print('Step 12: Creating file record in database...');
        final uploadTimestamp = DateTime.now();
        final fileResponse = await Supabase.instance.client
            .from('Files')
            .insert({
              'filename': fileDetails['fileName'],
              'category': fileDetails['category'],
              'file_type': fileExtension.toUpperCase(),
              'uploaded_at': uploadTimestamp.toIso8601String(),
              'file_size': fileBytes.length,
              'ipfs_cid': ipfsCid,
              'uploaded_by': uploaderId,
            })
            .select()
            .single();

        final fileId = fileResponse['id'];
        print('File record created with ID: $fileId');

        // Step 14: Insert encrypted AES keys for both patient and doctor
        print('Step 13: Storing encrypted keys in database...');
        await Supabase.instance.client.from('File_Keys').insert({
          'file_id': fileId,
          'recipient_type': 'user',
          'recipient_id': patientUserId.toString(),
          'aes_key_encrypted': patientRsaEncryptedString,
        });

        await Supabase.instance.client.from('File_Keys').insert({
          'file_id': fileId,
          'recipient_type': 'user',
          'recipient_id': uploaderId.toString(),
          'aes_key_encrypted': doctorRsaEncryptedString,
        });

        print('Encrypted keys stored successfully');

        // Step 15: Create File_Shares record
        print('Step 14: Creating file sharing record...');
        await Supabase.instance.client.from('File_Shares').insert({
          'file_id': fileId,
          'shared_with_user_id': patientUserId.toString(),
          'shared_by_user_id': uploaderId.toString(),
          'shared_at': uploadTimestamp.toIso8601String(),
        });

        print('File sharing record created successfully');

        // 🔗 Step 16: LOG TO HIVE BLOCKCHAIN
        print('🔗 Step 15: Logging to Hive blockchain...');
        final hiveResult = await _logToHiveBlockchain(
          fileName: fileDetails['fileName']!,
          fileHash: sha256Hash, // ✅ Now using the ENCRYPTED file hash
          fileId: fileId.toString(),
          userId: uploaderId,
          timestamp: uploadTimestamp,
          context: context,
        );

        Navigator.pop(context);
        onUploadComplete();

        // Show success message based on Hive result
        if (hiveResult.success) {
          showSnackBar(
              'File encrypted, uploaded, and logged to Hive blockchain successfully!');
          print('✅ HIVE BLOCKCHAIN LOGGING SUCCESSFUL');
          print('   Transaction ID: ${hiveResult.transactionId}');
          print('   Block Number: ${hiveResult.blockNum}');
        } else {
          showSnackBar(
              'File uploaded successfully! (Hive logging failed - check logs)');
          print('⚠️ HIVE BLOCKCHAIN LOGGING FAILED: ${hiveResult.error}');
        }

        print('=== FILE UPLOAD PROCESS COMPLETED ===');
      } else {
        String errorMessage;
        switch (response.statusCode) {
          case 400:
            errorMessage = 'Bad request - Check file format and size';
            break;
          case 401:
            errorMessage = 'Unauthorized - Check your Pinata API credentials';
            break;
          case 402:
            errorMessage =
                'Payment required - Check your Pinata account limits';
            break;
          case 403:
            errorMessage = 'Forbidden - Check your Pinata API permissions';
            break;
          case 413:
            errorMessage = 'File too large - Maximum file size exceeded';
            break;
          case 429:
            errorMessage = 'Rate limit exceeded - Try again later';
            break;
          case 500:
            errorMessage = 'Pinata server error - Try again later';
            break;
          default:
            errorMessage = 'Upload failed with status ${response.statusCode}';
        }

        Navigator.pop(context);
        showSnackBar('$errorMessage: ${response.body}');
        print(
            'IPFS upload failed - Status: ${response.statusCode}, Body: ${response.body}');
      }
    } on TimeoutException {
      Navigator.pop(context);
      showSnackBar(
          'Upload timeout - Please check your connection and try again');
      print('IPFS upload timeout');
    } catch (e, stackTrace) {
      Navigator.pop(context);
      print('ERROR uploading file: $e');
      print('Stack trace: $stackTrace');
      showSnackBar('Error uploading file: $e');
    }
  }

  static Future<Map<String, String>?> _showFileDetailsDialog(
      BuildContext context, String fileName, int fileSize) async {
    final nameController = TextEditingController(text: fileName);
    final descriptionController = TextEditingController();
    String selectedCategory = 'medical_report';

    // Theme colors to match your app
    const Color primaryGreen = Color(0xFF6B8E5A);
    const Color lightGreen = Color(0xFFF5F8F3);
    const Color textGray = Color(0xFF6C757D);
    const Color darkText = Color(0xFF2C3E50);
    const Color borderColor = Color(0xFFD5E1CF);

    final categories = [
      'medical_report',
      'lab_result',
      'prescription',
      'x_ray',
      'mri_scan',
      'ct_scan',
      'ultrasound',
      'blood_test',
      'discharge_summary',
      'consultation_notes',
      'other'
    ];

    return showDialog<Map<String, String>>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: lightGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.cloud_upload, color: primaryGreen, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'File Upload Details',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: darkText,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.insert_drive_file,
                          color: primaryGreen, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: darkText,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Size: ${formatFileSize(fileSize)}',
                            style: TextStyle(
                              color: textGray,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                style: const TextStyle(color: darkText, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Medical Category *',
                  labelStyle: TextStyle(
                      color: textGray,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryGreen, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor, width: 1.5),
                  ),
                  prefixIcon: const Icon(Icons.category_outlined,
                      color: primaryGreen, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                dropdownColor: Colors.white,
                items: categories.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(
                      category
                          .replaceAll('_', ' ')
                          .split(' ')
                          .map((word) =>
                              word[0].toUpperCase() + word.substring(1))
                          .join(' '),
                      style: const TextStyle(color: darkText, fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    selectedCategory = value;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: textGray,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        const Text('Please enter a display name for the file'),
                    backgroundColor: Colors.red[600],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'fileName': nameController.text.trim(),
                'description': descriptionController.text.trim(),
                'category': selectedCategory,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Upload File',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Test the complete Hive workflow without uploading a file
  /// Useful for debugging and testing the integration
  static Future<bool> testHiveWorkflow({
    required BuildContext context,
    String testFileName = 'test_file.pdf',
    String testFileHash = 'abc123def456...',
  }) async {
    try {
      final result = await _logToHiveBlockchain(
        fileName: testFileName,
        fileHash: testFileHash,
        fileId: 'test-file-id',
        userId: 'test-user-id',
        timestamp: DateTime.now(),
        context: context,
      );
      return result.success;
    } catch (e) {
      print('Hive workflow test failed: $e');
      return false;
    }
  }

  /// Get status of all services for debugging
  static Future<Map<String, dynamic>> getServicesStatus() async {
    final status = <String, dynamic>{};

    try {
      // Check HiveCustomJsonService
      status['hive_configured'] = HiveCustomJsonService.isHiveConfigured();
      status['hive_account'] = HiveCustomJsonService.getHiveAccountName();

      // Check HiveTransactionService connectivity
      try {
        final blockchainTime =
            await HiveTransactionService.getCurrentBlockchainTime();
        status['blockchain_connectivity'] = blockchainTime != null;
        status['blockchain_time'] = blockchainTime;
      } catch (e) {
        status['blockchain_connectivity'] = false;
        status['blockchain_error'] = e.toString();
      }

      // Check HiveTransactionSigner WIF
      final wif = HiveTransactionSignerWeb.getPostingWif();
      status['wif_configured'] = wif.isNotEmpty;
      status['wif_valid'] =
          wif.isNotEmpty ? HiveTransactionSignerWeb.isValidWif(wif) : false;

      // Check HiveTransactionBroadcaster connectivity
      try {
        final nodeConnectivity =
            await HiveTransactionBroadcasterWeb.testConnection();
        status['node_connectivity'] = nodeConnectivity;
        status['node_url'] = HiveTransactionBroadcasterWeb.getHiveNodeUrl();

        if (nodeConnectivity) {
          final nodeInfo = await HiveTransactionBroadcasterWeb.getNodeInfo();
          status['node_info'] = nodeInfo;
        }
      } catch (e) {
        status['node_connectivity'] = false;
        status['node_error'] = e.toString();
      }

      // Check Pinata
      final pinataJwt = dotenv.env['PINATA_JWT'] ?? '';
      status['pinata_configured'] = pinataJwt.isNotEmpty;
    } catch (e) {
      status['error'] = e.toString();
    }

    return status;
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
