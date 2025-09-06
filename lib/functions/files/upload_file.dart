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

class FileUploadService {
  // Define app theme colors
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color darkGray = Color(0xFF757575);

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
      final result = Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
      result.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
      result.setRange(secretBox.cipherText.length, result.length, secretBox.mac.bytes);
      
      print('Combined encrypted data: ${result.length} bytes (${secretBox.cipherText.length} ciphertext + ${secretBox.mac.bytes.length} MAC)');
      
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
        
        final modulus = (publicKeySeq.elements[0] as ASN1Integer).valueAsBigInteger;
        final exponent = (publicKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
        
        print('PKCS#1 RSA key parsed - Modulus bits: ${modulus!.bitLength}, Exponent: $exponent');
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
        
        final modulus = (publicKeySeq.elements[0] as ASN1Integer).valueAsBigInteger;
        final exponent = (publicKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
        
        print('PKCS#8 RSA key parsed - Modulus bits: ${modulus!.bitLength}, Exponent: $exponent');
        return RSAPublicKey(modulus, exponent!);
      }
    } catch (e) {
      print('Error parsing RSA public key from PEM: $e');
      print('PEM content (first 100 chars): ${pem.substring(0, pem.length > 100 ? 100 : pem.length)}');
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

  static Future<void> uploadFileForPatient(
    BuildContext context,
    Map<String, dynamic> selectedPatient,
    Function(String) showSnackBar,
    Function() onUploadComplete,
  ) async {
    if (selectedPatient == null) return;

    try {
      print('=== STARTING FILE UPLOAD PROCESS ===');
      print('Using PointyCastle RSA-OAEP + cryptography AES-256-GCM (consistent format)');
      
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

      print('File selected: $fileName (${fileSize} bytes)');

      // Step 2: Read file as bytes
      print('Step 2: Reading file as bytes...');
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final Uint8List fileBytes = reader.result as Uint8List;
      print('File read successfully: ${fileBytes.length} bytes');

      // Step 3: Show file details dialog and get description
      print('Step 3: Getting file details from user...');
      final fileDetails = await _showFileDetailsDialog(context, fileName, fileSize);
      if (fileDetails == null) {
        print('User cancelled file upload');
        return;
      }

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Row(
            children: [
              CircularProgressIndicator(color: primaryBlue),
              SizedBox(width: 16),
              Text('Encrypting and uploading file...'),
            ],
          ),
        ),
      );

      // Step 4: Get current user info
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

      // Step 5: Generate AES key and nonce for GCM mode
      print('Step 5: Generating AES-256 key and nonce...');
      final aesKey = _generateRandomBytes(32); // 32 bytes for AES-256
      final aesNonce = _generateRandomBytes(12); // 12 bytes for GCM nonce

      print('Generated AES-256 key (base64): ${base64Encode(aesKey)}');
      print('Generated GCM nonce (base64): ${base64Encode(aesNonce)}');

      // Step 6: Encrypt file with AES-256-GCM (using consistent format)
      print('Step 6: Encrypting file with AES-256-GCM...');
      final encryptedBytes = await _encryptWithAES256GCM(fileBytes, aesKey, aesNonce);

      print('Original file size: ${fileBytes.length} bytes');
      print('Encrypted file size: ${encryptedBytes.length} bytes');

      // Step 7: Get patient's RSA public key
      print('Step 7: Getting patient RSA public key...');
      final patientId = selectedPatient['patient_id'];
      
      final patientResponse = await Supabase.instance.client
          .from('Patient')
          .select('id, user_id')
          .eq('id', patientId);

      if (patientResponse.isEmpty) {
        Navigator.pop(context);
        showSnackBar('Patient not found in Patient table. Patient ID: $patientId');
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
      final patientRsaPublicKeyPem = patientUserData['rsa_public_key'] as String?;

      if (patientRsaPublicKeyPem == null || patientRsaPublicKeyPem.isEmpty) {
        Navigator.pop(context);
        showSnackBar('Patient does not have an RSA public key');
        return;
      }

      print('Patient RSA public key retrieved');

      // Step 8: Get doctor's RSA public key
      print('Step 8: Getting doctor RSA public key...');
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
        showSnackBar('Doctor does not have an RSA public key. Please generate keys first.');
        return;
      }

      print('Doctor RSA public key retrieved');

      // Step 9: Encrypt AES key and nonce with RSA-OAEP using PointyCastle (consistent format)
      print('Step 9: Encrypting AES key with RSA-OAEP...');
      final keyData = {
        'key': base64Encode(aesKey),      // BASE64 format (consistent with mobile)
        'nonce': base64Encode(aesNonce),  // BASE64 format (consistent with mobile)
      };
      final keyDataJson = jsonEncode(keyData);

      print('Key data JSON: $keyDataJson');

      final patientRsaEncryptedString = _encryptWithRSAOAEP(keyDataJson, patientRsaPublicKeyPem);
      final doctorRsaEncryptedString = _encryptWithRSAOAEP(keyDataJson, doctorRsaPublicKeyPem);

      print('RSA-OAEP encryption completed for both patient and doctor');

      // Step 10: Calculate SHA256 hash of original file
      final sha256Hash = _calculateSHA256(fileBytes);
      print('File SHA256 hash: $sha256Hash');

      // Step 11: Upload encrypted file to IPFS
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

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final ipfsJson = jsonDecode(response.body);
        final ipfsCid = ipfsJson['IpfsHash'] as String;
        print('IPFS upload successful. CID: $ipfsCid');

        // Step 12: Create file record in Files table
        print('Step 12: Creating file record in database...');
        final fileResponse = await Supabase.instance.client
            .from('Files')
            .insert({
              'filename': fileDetails['fileName'],
              'category': fileDetails['category'],
              'file_type': fileExtension.toUpperCase(),
              'uploaded_at': DateTime.now().toIso8601String(),
              'file_size': fileBytes.length,
              'ipfs_cid': ipfsCid,
              'sha256_hash': sha256Hash,
              'uploaded_by': uploaderId,
            })
            .select()
            .single();

        final fileId = fileResponse['id'];
        print('File record created with ID: $fileId');

        // Step 13: Insert encrypted AES keys for both patient and doctor
        print('Step 13: Storing encrypted keys in database...');
        await Supabase.instance.client.from('File_Keys').insert({
          'file_id': fileId,
          'recipient_type': 'user',
          'recipient_id': patientUserId.toString(),
          'aes_key_encrypted': patientRsaEncryptedString,
          // Note: nonce_hex not used in consistent format - nonce is stored in key JSON
        });

        await Supabase.instance.client.from('File_Keys').insert({
          'file_id': fileId,
          'recipient_type': 'user',
          'recipient_id': uploaderId.toString(),
          'aes_key_encrypted': doctorRsaEncryptedString,
          // Note: nonce_hex not used in consistent format - nonce is stored in key JSON
        });

        print('Encrypted keys stored successfully');

        // Step 14: Create File_Shares record
        print('Step 14: Creating file sharing record...');
        await Supabase.instance.client.from('File_Shares').insert({
          'file_id': fileId,
          'shared_with_user_id': patientUserId.toString(),
          'shared_by_user_id': uploaderId.toString(),
          'shared_at': DateTime.now().toIso8601String(),
        });

        print('File sharing record created successfully');

        Navigator.pop(context);
        onUploadComplete();
        showSnackBar('File encrypted with consistent format and uploaded successfully!');

        print('=== FILE UPLOAD PROCESS COMPLETED SUCCESSFULLY ===');

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
            errorMessage = 'Payment required - Check your Pinata account limits';
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
        print('IPFS upload failed - Status: ${response.statusCode}, Body: ${response.body}');
      }
    } on TimeoutException {
      Navigator.pop(context);
      showSnackBar('Upload timeout - Please check your connection and try again');
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('File Upload Details',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: primaryBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'File: $fileName',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                            style: const TextStyle(color: darkGray, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Display Name *',
                  hintText: 'Enter a descriptive name for the file',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryBlue, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.edit, color: primaryBlue),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add notes about this file (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryBlue, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.notes, color: primaryBlue),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Medical Category *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryBlue, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.category, color: primaryBlue),
                ),
                items: categories.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category
                        .replaceAll('_', ' ')
                        .split(' ')
                        .map((word) => word[0].toUpperCase() + word.substring(1))
                        .join(' ')),
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
            child: const Text('Cancel', style: TextStyle(color: darkGray)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please enter a display name for the file')),
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
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Upload File'),
          ),
        ],
      ),
    );
  }
}