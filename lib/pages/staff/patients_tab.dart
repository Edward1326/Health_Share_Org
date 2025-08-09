import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:health_share_org/services/aes_helper.dart';
import 'package:health_share_org/services/crypto_utils.dart';
import 'dart:html' as html;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:math';
import 'package:pointycastle/export.dart' as pc;
import 'package:crypto/crypto.dart';
import 'dart:async';

class PatientsTab extends StatefulWidget {
  const PatientsTab({Key? key}) : super(key: key);

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _selectedPatientFiles = [];
  Map<String, dynamic>? _selectedPatient;
  bool _loadingPatients = false;
  bool _loadingFiles = false;

  // Define app theme colors
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color orange = Color(0xFFFF9500);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color darkGray = Color(0xFF757575);
  static const Color cardBackground = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loadingPatients = true;
    });

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null || currentUser.email == null) {
        throw Exception('No authenticated user found');
      }

      final userEmail = currentUser.email!;
      print('DEBUG: Looking up user with email: $userEmail');

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, person_id')
          .eq('email', userEmail)
          .single();

      print('DEBUG: User lookup response: $userResponse');
      final userId = userResponse['id'];

      final doctorLookupResponse = await Supabase.instance.client
          .from('Organization_User')
          .select('id, position, department')
          .eq('user_id', userId)
          .eq('position', 'Doctor');

      print('DEBUG: Doctor lookup response: $doctorLookupResponse');

      if (doctorLookupResponse.isEmpty) {
        throw Exception(
            'No doctor records found for this user. Make sure you have a Doctor position in Organization_User table.');
      }

      final doctorIds =
          doctorLookupResponse.map((doctor) => doctor['id']).toList();
      print('DEBUG: Doctor IDs for assignment lookup: $doctorIds');

      final response = await Supabase.instance.client
          .from('Doctor_User_Assignment')
          .select('''
      id,
      doctor_id,
      patient_id,
      status,
      assigned_at,
      patient_user:User!patient_id(
        id,
        person_id,
        email,
        Person!person_id(
          id,
          first_name,
          middle_name,
          last_name,
          address,
          contact_number
        )
      )
    ''')
          .in_('doctor_id', doctorIds)
          .eq('status', 'active');

      print('DEBUG: Patients query response: $response');

      final transformedPatients =
          response.map<Map<String, dynamic>>((assignment) {
        final assignmentMap = assignment as Map<String, dynamic>;
        return {
          'patient_id': assignmentMap['patient_id'],
          'doctor_id': assignmentMap['doctor_id'],
          'status': assignmentMap['status'],
          'assigned_at': assignmentMap['assigned_at'],
          'User': assignmentMap['patient_user'],
        };
      }).toList();

      setState(() {
        _patients = List<Map<String, dynamic>>.from(transformedPatients);
        _loadingPatients = false;
      });
    } catch (e) {
      print('Error loading patients: $e');
      setState(() {
        _loadingPatients = false;
      });
      _showSnackBar('Error loading patients: $e');
    }
  }

  Future<void> _loadPatientFiles(String patientId) async {
    setState(() {
      _loadingFiles = true;
    });

    try {
      final response = await Supabase.instance.client
          .from('File_Shares')
          .select('''
          id,
          shared_at,
          Files!inner(
            id,
            filename,
            category,
            file_type,
            uploaded_at,
            file_size,
            ipfs_cid,
            sha256_hash,
            uploaded_by,
            uploader:User!uploaded_by(
              Person!person_id(
                first_name,
                last_name
              )
            )
          )
        ''')
          .eq('shared_with_user_id', patientId)
          .order('shared_at', ascending: false);

      setState(() {
        _selectedPatientFiles = List<Map<String, dynamic>>.from(response);
        _loadingFiles = false;
      });

      print(
          'Loaded ${_selectedPatientFiles.length} files for patient $patientId');
    } catch (e) {
      print('Error loading patient files: $e');
      setState(() {
        _loadingFiles = false;
      });
      _showSnackBar('Error loading files: $e');
    }
  }

  // Helper method to generate secure random bytes
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (i) => random.nextInt(256)));
  }

  // Helper method to convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  }

  // Helper method to calculate SHA256 hash
  String _calculateSHA256(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  Future<void> _uploadFileForPatient() async {
    if (_selectedPatient == null) return;

    try {
      // Step 1: Create HTML file input for web compatibility
      final html.InputElement uploadInput = html.InputElement(type: 'file');
      uploadInput.accept = '.pdf,.jpg,.jpeg,.png,.doc,.docx,.txt';
      uploadInput.click();

      // Wait for file selection
      await uploadInput.onChange.first;

      if (uploadInput.files == null || uploadInput.files!.isEmpty) {
        _showSnackBar('No file selected');
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
      final fileDetails = await _showFileDetailsDialog(fileName, fileSize);
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
        _showSnackBar('Authentication error');
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
          .eq('id', _selectedPatient!['patient_id'])
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
          'patientId': _selectedPatient!['patient_id'],
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
            'recipient_id': _selectedPatient!['patient_id'],
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
          _showSnackBar('File uploaded but key storage failed: $fileKeyError');
          return;
        }

        // Step 13: Create File_Shares record to share with patient
        final patientId = _selectedPatient!['patient_id'].toString();

        await Supabase.instance.client.from('File_Shares').insert({
          'file_id': fileId,
          'shared_with_user_id': patientId,
          'shared_by_user_id': uploaderId,
          'shared_at': DateTime.now().toIso8601String(),
        });

        // Close loading dialog
        Navigator.pop(context);

        // Step 14: Refresh patient files and show success
        await _loadPatientFiles(patientId);
        _showSnackBar(
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
        _showSnackBar('$errorMessage: ${response.body}');
        print(
            'ERROR: IPFS upload failed - Status: ${response.statusCode}, Body: ${response.body}');
      }
    } on TimeoutException {
      Navigator.pop(context);
      _showSnackBar(
          'Upload timeout - Please check your connection and try again');
      print('ERROR: IPFS upload timeout');
    } catch (e, stackTrace) {
      Navigator.pop(context);
      print('ERROR uploading file: $e');
      print('Stack trace: $stackTrace');
      _showSnackBar('Error uploading file: $e');
    }
  }

// Add this helper method to validate JWT token format
  bool _isValidJWT(String token) {
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

  Future<Map<String, String>?> _showFileDetailsDialog(
      String fileName, int fileSize) async {
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header with Add Patient button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Patients',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      _showSnackBar('Add patient feature coming soon!'),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _loadingPatients
                ? const Center(
                    child: CircularProgressIndicator(color: primaryBlue))
                : _patients.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Patients Assigned',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Patients will appear here once assigned to you',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : _selectedPatient == null
                        ? _buildPatientsList()
                        : _buildPatientDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _patients.length,
      itemBuilder: (context, index) {
        final patient = _patients[index];
        final person = patient['User']['Person'];
        final fullName = _buildFullName(person);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _getPatientAvatarColor(index),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _getPatientInitials(fullName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            title: Text(
              fullName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  patient['User']['email'] ?? '',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Patient ID: ${patient['patient_id']}',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                patient['status'] ?? 'active',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            onTap: () {
              setState(() {
                _selectedPatient = patient;
              });
              final patientId = patient['patient_id'].toString();
              _loadPatientFiles(patientId);
            },
          ),
        );
      },
    );
  }

  Widget _buildPatientDetails() {
    final patient = _selectedPatient!;
    final person = patient['User']['Person'];
    final fullName =
        '${person['first_name']} ${person['middle_name'] ?? ''} ${person['last_name']}'
            .trim();

    return Column(
      children: [
        // Patient Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedPatient = null;
                    _selectedPatientFiles = [];
                  });
                },
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 12),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _getPatientInitials(fullName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      person['email'] ?? '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _uploadFileForPatient,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // Files Section
        Expanded(
          child: _loadingFiles
              ? const Center(
                  child: CircularProgressIndicator(color: primaryBlue))
              : _selectedPatientFiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Files Shared',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Upload files to share with this patient',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _selectedPatientFiles.length,
                      itemBuilder: (context, index) {
                        final fileShare = _selectedPatientFiles[index];
                        final file = fileShare['Files'];
                        return _buildFileCard(file);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildFileCard(Map<String, dynamic> file) {
    final fileType = file['file_type'] ?? 'unknown';
    final category = file['category'] ?? 'other';
    final fileName = file['filename'] ?? 'Unknown File';
    final description = file['description'] ?? '';
    final createdAt =
        DateTime.tryParse(file['created_at'] ?? '') ?? DateTime.now();
    final uploader = file['uploader'];
    final uploaderName = uploader != null
        ? '${uploader['Person']['first_name']} ${uploader['Person']['last_name']}'
        : 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getFileTypeColor(fileType),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileTypeIcon(fileType),
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(category).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          category.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            color: _getCategoryColor(category),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatDate(createdAt)} • $uploaderName',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _showFileActions(file),
              icon: const Icon(Icons.more_vert, color: darkGray),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods
  Color _getPatientAvatarColor(int index) {
    final colors = [primaryBlue, coral, orange, Colors.purple, Colors.teal];
    return colors[index % colors.length];
  }

  // Fixed method to safely get patient initials
  String _getPatientInitials(String fullName) {
    if (fullName.trim().isEmpty) {
      return 'P';
    }

    final names =
        fullName.trim().split(' ').where((name) => name.isNotEmpty).toList();

    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    } else if (names.isNotEmpty && names[0].isNotEmpty) {
      return names[0][0].toUpperCase();
    }
    return 'P';
  }

// Also fix the fullName construction in your build methods
  String _buildFullName(Map<String, dynamic> person) {
    final parts = <String>[];

    if (person['first_name'] != null &&
        person['first_name'].toString().trim().isNotEmpty) {
      parts.add(person['first_name'].toString().trim());
    }

    if (person['middle_name'] != null &&
        person['middle_name'].toString().trim().isNotEmpty) {
      parts.add(person['middle_name'].toString().trim());
    }

    if (person['last_name'] != null &&
        person['last_name'].toString().trim().isNotEmpty) {
      parts.add(person['last_name'].toString().trim());
    }

    return parts.join(' ');
  }

  Color _getFileTypeColor(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.blue;
      case 'doc':
      case 'docx':
        return Colors.blue[700]!;
      case 'txt':
        return Colors.grey[600]!;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  IconData _getFileTypeIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'medical_report':
        return Colors.blue;
      case 'lab_result':
        return Colors.green;
      case 'prescription':
        return Colors.purple;
      case 'x_ray':
        return Colors.orange;
      case 'mri_scan':
        return Colors.red;
      case 'ct_scan':
        return Colors.indigo;
      case 'ultrasound':
        return Colors.teal;
      case 'blood_test':
        return Colors.pink;
      case 'discharge_summary':
        return Colors.brown;
      case 'consultation_notes':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1 year ago' : '$years years ago';
    }
  }

  void _showFileActions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.download, color: primaryBlue),
              title: const Text('Download File'),
              onTap: () {
                Navigator.pop(context);
                _downloadAndDecryptFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: primaryBlue),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                _shareFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: primaryBlue),
              title: const Text('File Details'),
              onTap: () {
                Navigator.pop(context);
                _showFileDetails(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: coral),
              title: const Text('Remove Share'),
              onTap: () {
                Navigator.pop(context);
                _removeFileShare(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewFile(Map<String, dynamic> file) async {
    try {
      final fileType = file['file_type']?.toLowerCase();

      // Only allow preview for images and PDFs
      if (!['jpg', 'jpeg', 'png', 'pdf'].contains(fileType)) {
        _showSnackBar('Preview not available for this file type');
        return;
      }

      _showSnackBar('Loading file preview...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

      if (ipfsCid == null) {
        _showSnackBar('IPFS CID not found');
        return;
      }

      // Get current user and decrypt file (same as download)
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        _showSnackBar('Authentication error');
        return;
      }

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      if (rsaPrivateKeyPem == null) {
        _showSnackBar('RSA private key not found');
        return;
      }

      final keyResponse = await Supabase.instance.client
          .from('File_Keys')
          .select('aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId)
          .eq('recipient_id', userId)
          .single();

      final encryptedAesKey = keyResponse['aes_key_encrypted'] as String;
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
      final decryptedKeyDataJson =
          CryptoUtils.rsaDecrypt(encryptedAesKey, rsaPrivateKey);
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;

      final aesKeyHex = keyData['key'] as String;
      final aesNonceHex = keyData['nonce'] as String;

      // Download and decrypt
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        _showSnackBar('Failed to download file from IPFS');
        return;
      }

      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(response.bodyBytes);

      // Create blob URL and open in new tab for preview
      final blob = html.Blob([decryptedBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');

      // Clean up the URL after a delay
      Timer(const Duration(seconds: 30), () {
        html.Url.revokeObjectUrl(url);
      });

      _showSnackBar('File preview opened in new tab');
    } catch (e) {
      print('ERROR previewing file: $e');
      _showSnackBar('Error previewing file: $e');
    }
  }

  Future<void> _downloadAndDecryptFile(Map<String, dynamic> file) async {
    try {
      _showSnackBar('Downloading and decrypting file...');

      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

      if (ipfsCid == null) {
        _showSnackBar('IPFS CID not found');
        return;
      }

      // Get current user
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        _showSnackBar('Authentication error');
        return;
      }

      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key')
          .eq('email', currentUser.email!)
          .single();

      final userId = userResponse['id'];
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      if (rsaPrivateKeyPem == null) {
        _showSnackBar('RSA private key not found');
        return;
      }

      // Get the encrypted AES key for this user
      final keyResponse = await Supabase.instance.client
          .from('File_Keys')
          .select('aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId)
          .eq('recipient_id', userId)
          .single();

      final encryptedAesKey = keyResponse['aes_key_encrypted'] as String;
      final nonceHex = keyResponse['nonce_hex'] as String;

      // Decrypt the AES key using RSA private key
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);
      final decryptedKeyDataJson =
          CryptoUtils.rsaDecrypt(encryptedAesKey, rsaPrivateKey);
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;

      final aesKeyHex = keyData['key'] as String;
      final aesNonceHex = keyData['nonce'] as String;

      print('DEBUG: Decrypted AES key: $aesKeyHex');
      print('DEBUG: Decrypted nonce: $aesNonceHex');

      // Download encrypted file from IPFS
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        _showSnackBar('Failed to download file from IPFS');
        return;
      }

      final encryptedBytes = response.bodyBytes;
      print('DEBUG: Downloaded encrypted file: ${encryptedBytes.length} bytes');

      // Decrypt the file
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(encryptedBytes);

      print('DEBUG: Decrypted file: ${decryptedBytes.length} bytes');

      // Create a blob and download it
      final blob = html.Blob([decryptedBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', file['filename'] ?? 'decrypted_file')
        ..click();

      html.Url.revokeObjectUrl(url);

      _showSnackBar('File decrypted and downloaded successfully!');
    } catch (e, stackTrace) {
      print('ERROR downloading/decrypting file: $e');
      print('Stack trace: $stackTrace');
      _showSnackBar('Error downloading file: $e');
    }
  }

  void _shareFile(Map<String, dynamic> file) {
    _showSnackBar('Share functionality coming soon!');
  }

  void _showFileDetails(Map<String, dynamic> file) {
    final fileName = file['filename'] ?? 'Unknown File';
    final description = file['description'] ?? 'No description';
    final fileType = file['file_type'] ?? 'unknown';
    final category = file['category'] ?? 'other';
    final createdAt =
        DateTime.tryParse(file['created_at'] ?? '') ?? DateTime.now();
    final uploader = file['uploader'];
    final uploaderName = uploader != null
        ? '${uploader['Person']['first_name']} ${uploader['Person']['last_name']}'
        : 'Unknown';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('File Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Name', fileName),
            _buildDetailRow('Description', description),
            _buildDetailRow('Type', fileType.toUpperCase()),
            _buildDetailRow(
                'Category', category.replaceAll('_', ' ').toUpperCase()),
            _buildDetailRow('Uploaded by', uploaderName),
            _buildDetailRow('Date', _formatDate(createdAt)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: darkGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  void _removeFileShare(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove File Share'),
        content: const Text(
            'Are you sure you want to remove this file share? The patient will no longer have access to this file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performRemoveFileShare(file);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: coral,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _performRemoveFileShare(Map<String, dynamic> file) async {
    try {
      // Find and delete the file share record
      await Supabase.instance.client
          .from('File_Shares')
          .delete()
          .eq('file_id', file['id'])
          .eq('shared_with_user_id', _selectedPatient!['patient_id']);

      // Refresh the patient files
      final patientId = _selectedPatient!['patient_id'].toString();
      await _loadPatientFiles(patientId);

      _showSnackBar('File share removed successfully');
    } catch (e) {
      print('Error removing file share: $e');
      _showSnackBar('Error removing file share: $e');
    }
  }
}
