import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:health_share_org/services/aes_helper.dart';
import 'package:health_share_org/services/crypto_utils.dart';
import 'dart:html' as html;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:async';

class FileUploadService {
  // Define app theme colors
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color darkGray = Color(0xFF757575);

  // Helper method to generate secure random bytes
  static Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (i) => random.nextInt(256)));
  }

  // Helper method to convert bytes to hex string
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  }

  // Helper method to calculate SHA256 hash
  static String _calculateSHA256(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  // Add this helper method to validate JWT token format
  static bool _isValidJWT(String token) {
    if (token.isEmpty) return false;

    final parts = token.split('.');
    if (parts.length != 3) return false;

    // Check if each part is valid base64
    for (final part in parts) {
      try {
        base64Url.decode(part + '=' * (4 - part.length % 4));
      } catch (e) {
        return false;
      }
    }

    return true;
  }

  static Future<void> uploadFileForPatient(
    BuildContext context,
    Map<String, dynamic> selectedPatient,
    Function(String) showSnackBar,
    Function() onUploadComplete,
  ) async {
    if (selectedPatient == null) return;

    try {
      // Step 1: Create HTML file input for web compatibility
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

      // Step 2: Read file as bytes
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final Uint8List fileBytes = reader.result as Uint8List;

      // Step 3: Show file details dialog and get description
      final fileDetails =
          await _showFileDetailsDialog(context, fileName, fileSize);
      if (fileDetails == null) return;

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Row(
            children: [
              CircularProgressIndicator(color: primaryBlue),
              SizedBox(width: 16),
              Text('Encrypting and uploading file...'),
            ],
          ),
        ),
      );

      // Step 4: Get current user info for uploaded_by field
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        Navigator.pop(context);
        showSnackBar('Authentication error');
        return;
      }

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id')
          .eq('email', currentUser.email!)
          .single();

      final uploaderId = userResponse['id'];

      // Step 5: Generate AES key and nonce for GCM mode, then encrypt file
      final aesKeyBytes = _generateRandomBytes(32); // 32 bytes for AES-256
      final aesNonceBytes = _generateRandomBytes(12); // 12 bytes for GCM nonce

      // Convert to hex strings for AESHelper
      final aesKeyHex = _bytesToHex(aesKeyBytes);
      final aesNonceHex = _bytesToHex(aesNonceBytes);

      print('DEBUG: Generated AES Key (hex): $aesKeyHex');
      print('DEBUG: Generated AES Nonce (hex): $aesNonceHex');

      // Create AESHelper and encrypt the file
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final encryptedBytes = aesHelper.encryptData(fileBytes);

      print('DEBUG: Original file size: ${fileBytes.length} bytes');
      print('DEBUG: Encrypted file size: ${encryptedBytes.length} bytes');

      // Step 6: Get patient's RSA public key
      final patientResponse = await Supabase.instance.client
          .from('User')
          .select('rsa_public_key')
          .eq('id', selectedPatient['patient_id'])
          .single();

      final patientRsaPublicKeyPem =
          patientResponse['rsa_public_key'] as String;
      print(
          'DEBUG: Patient RSA Public Key: ${patientRsaPublicKeyPem.substring(0, 100)}...');

      final patientRsaPublicKey =
          CryptoUtils.rsaPublicKeyFromPem(patientRsaPublicKeyPem);

      // Step 7: Also get doctor's (your) RSA public key
      final doctorResponse = await Supabase.instance.client
          .from('User')
          .select('rsa_public_key')
          .eq('id', uploaderId)
          .single();

      final doctorRsaPublicKeyPem = doctorResponse['rsa_public_key'] as String;
      final doctorRsaPublicKey =
          CryptoUtils.rsaPublicKeyFromPem(doctorRsaPublicKeyPem);

      // Step 8: Encrypt AES key with both patient's and doctor's RSA public keys
      final keyData = {
        'key': aesKeyHex,
        'nonce': aesNonceHex,
      };
      final keyDataJson = jsonEncode(keyData);

      print('DEBUG: Key data to encrypt: $keyDataJson');

      final patientRsaEncryptedString =
          CryptoUtils.rsaEncrypt(keyDataJson, patientRsaPublicKey);
      final doctorRsaEncryptedString =
          CryptoUtils.rsaEncrypt(keyDataJson, doctorRsaPublicKey);

      print(
          'DEBUG: Patient RSA encrypted key data length: ${patientRsaEncryptedString.length}');
      print(
          'DEBUG: Doctor RSA encrypted key data length: ${doctorRsaEncryptedString.length}');

      // Step 9: Calculate SHA256 hash of original file
      final sha256Hash = _calculateSHA256(fileBytes);
      print('DEBUG: File SHA256 hash: $sha256Hash');

      // Step 10: Upload encrypted file to IPFS with enhanced error handling
      print('DEBUG: Starting IPFS upload...');
      print(
          'DEBUG: Encrypted file size for upload: ${encryptedBytes.length} bytes');

      final url = Uri.parse('https://api.pinata.cloud/pinning/pinFileToIPFS');

      // Your actual Pinata credentials
      const String jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySW5mb3JtYXRpb24iOnsiaWQiOiI1MjNmNzlmZC0xZjVmLTQ4NzUtOTQwMS01MDcyMDE3NmMyYjYiLCJlbWFpbCI6ImVkd2FyZC5xdWlhbnpvbi5yQGdtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJwaW5fcG9saWN5Ijp7InJlZ2lvbnMiOlt7ImRlc2lyZWRSZXBsaWNhdGlvbkNvdW50IjoxLCJpZCI6IkZSQTEifSx7ImRlc2lyZWRSZXBsaWNhdGlvbkNvdW50IjoxLCJpZCI6Ik5ZQzEifV0sInZlcnNpb24iOjF9LCJtZmFfZW5hYmxlZCI6ZmFsc2UsInN0YXR1cyI6IkFDVElWRSJ9LCJhdXRoZW50aWNhdGlvblR5cGUiOiJzY29wZWRLZXkiLCJzY29wZWRLZXlLZXkiOiI5NmM3NGQxNTY4YzBlNDE4MGQ5MiIsInNjb3BlZEtleVNlY3JldCI6IjQ2MDIxYzNkYThmZDIzZDJmY2E4ZmYzNThjMGI3NmE2ODYxMzRhOWMzNDNiOTFmODY3MmIyMzhlYjE2N2FkODkiLCJleHAiOjE3ODU2ODIyMzl9.1VpMdmG4CaQ-eNxNVesfiy-P6J7p9IGLtjD9q1r5mkg';

      print('DEBUG: Creating multipart request...');

      final request = http.MultipartRequest('POST', url);

      // Using JWT
      request.headers['Authorization'] = 'Bearer $jwt';

      // Add the encrypted file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encryptedBytes,
          filename: 'encrypted_${DateTime.now().millisecondsSinceEpoch}.bin',
        ),
      );

      // Optional: Add metadata
      final metadata = {
        'name': 'Medical File - ${fileDetails['fileName']}',
        'keyvalues': {
          'originalFileName': fileDetails['fileName'],
          'category': fileDetails['category'],
          'uploadedBy': uploaderId,
          'patientId': selectedPatient['patient_id'],
          'encrypted': 'true',
          'uploadDate': DateTime.now().toIso8601String(),
        }
      };

      request.fields['pinataMetadata'] = jsonEncode(metadata);

      // Optional: Add pinning options
      final options = {
        'cidVersion': 1,
        'wrapWithDirectory': false,
      };

      request.fields['pinataOptions'] = jsonEncode(options);

      print('DEBUG: Sending request to Pinata...');
      print('DEBUG: Request URL: ${request.url}');
      print('DEBUG: Request headers: ${request.headers}');

      final streamedResponse = await request.send().timeout(
            const Duration(minutes: 5), // 5 minute timeout
          );

      print(
          'DEBUG: Received response with status: ${streamedResponse.statusCode}');

      final response = await http.Response.fromStream(streamedResponse);

      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final ipfsJson = jsonDecode(response.body);
        final ipfsCid = ipfsJson['IpfsHash'] as String;
        print('DEBUG: Upload successful. CID: $ipfsCid');

        // Step 11: Create file record in Files table
        final fileResponse = await Supabase.instance.client
            .from('Files')
            .insert({
              'filename': fileDetails['fileName'],
              'category': fileDetails['category'],
              'file_type': fileExtension.toUpperCase(),
              'uploaded_at': DateTime.now().toIso8601String(),
              'file_size': fileBytes.length, // Store original file size
              'ipfs_cid': ipfsCid,
              'sha256_hash': sha256Hash,
              'uploaded_by': uploaderId,
            })
            .select()
            .single();

        final fileId = fileResponse['id'];
        print('DEBUG: File inserted with ID: $fileId');

        // Step 12: Insert encrypted AES keys for BOTH patient and doctor
        try {
          // Insert key for patient
          await Supabase.instance.client.from('File_Keys').insert({
            'file_id': fileId,
            'recipient_type': 'user',
            'recipient_id': selectedPatient['patient_id'],
            'aes_key_encrypted': patientRsaEncryptedString,
            'nonce_hex': aesNonceHex,
          });

          // Insert key for doctor (yourself)
          await Supabase.instance.client.from('File_Keys').insert({
            'file_id': fileId,
            'recipient_type': 'user',
            'recipient_id': uploaderId, // Your user ID
            'aes_key_encrypted': doctorRsaEncryptedString,
            'nonce_hex': aesNonceHex,
          });

          print(
              'DEBUG: File keys inserted successfully for both patient and doctor');
        } catch (fileKeyError) {
          print('ERROR: inserting file key: $fileKeyError');
          Navigator.pop(context);
          showSnackBar('File uploaded but key storage failed: $fileKeyError');
          return;
        }

        // Step 13: Create File_Shares record to share with patient
        final patientId = selectedPatient['patient_id'].toString();

        await Supabase.instance.client.from('File_Shares').insert({
          'file_id': fileId,
          'shared_with_user_id': patientId,
          'shared_by_user_id': uploaderId,
          'shared_at': DateTime.now().toIso8601String(),
        });

        // Close loading dialog
        Navigator.pop(context);

        // Step 14: Call the completion callback
        onUploadComplete();
        showSnackBar(
            'File encrypted, uploaded to IPFS and shared successfully!');

        print('DEBUG: File upload process completed successfully');
      } else {
        // Handle different error codes
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
            'ERROR: IPFS upload failed - Status: ${response.statusCode}, Body: ${response.body}');
      }
    } on TimeoutException {
      Navigator.pop(context);
      showSnackBar(
          'Upload timeout - Please check your connection and try again');
      print('ERROR: IPFS upload timeout');
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
                            style:
                                const TextStyle(color: darkGray, fontSize: 13),
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
                        .map(
                            (word) => word[0].toUpperCase() + word.substring(1))
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
                      content:
                          Text('Please enter a display name for the file')),
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
