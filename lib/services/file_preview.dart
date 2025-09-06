import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' hide Mac;
import 'package:asn1lib/asn1lib.dart';

class SimpleFilePreviewService {
  // Cryptography instances - same as upload service
  static final _aesGcm = AesGcm.with256bits();

  /// Simple file preview - just show the content, no save/download
  static Future<void> previewFile(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Loading file...'),
            ],
          ),
        ),
      );

      // Decrypt the file
      final decryptedBytes = await _decryptFile(file);
      
      // Close loading dialog
      Navigator.of(context).pop();

      if (decryptedBytes == null) {
        showSnackBar('Failed to decrypt file');
        return;
      }

      final fileName = file['filename'] ?? 'Unknown File';
      final extension = fileName.toLowerCase().split('.').last;
      
      // Show appropriate preview based on file type
      if (_isImageFile(extension)) {
        _showImagePreview(context, fileName, decryptedBytes);
      } else if (_isTextFile(extension)) {
        _showTextPreview(context, fileName, decryptedBytes);
      } else if (extension == 'pdf') {
        _showPDFPreview(context, fileName, decryptedBytes);
      } else {
        _showGenericPreview(context, fileName, decryptedBytes, extension);
      }
      
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      print('Error in previewFile: $e');
      showSnackBar('Error opening file: $e');
    }
  }

  /// Parse RSA private key from PEM format - FIXED VERSION
  static RSAPrivateKey _parseRSAPrivateKeyFromPem(String pem) {
    try {
      print('Parsing RSA private key from PEM...');
      
      final cleanPem = pem.trim();
      
      bool isPkcs1 = cleanPem.contains('-----BEGIN RSA PRIVATE KEY-----');
      bool isPkcs8 = cleanPem.contains('-----BEGIN PRIVATE KEY-----');
      
      if (!isPkcs1 && !isPkcs8) {
        throw FormatException('Invalid PEM format - missing proper headers');
      }
      
      String lines;
      if (isPkcs1) {
        print('Detected PKCS#1 format');
        lines = cleanPem
            .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
            .replaceAll('-----END RSA PRIVATE KEY-----', '')
            .replaceAll(RegExp(r'\s+'), '') // Remove all whitespace including newlines
            .trim();
      } else {
        print('Detected PKCS#8 format');
        lines = cleanPem
            .replaceAll('-----BEGIN PRIVATE KEY-----', '')
            .replaceAll('-----END PRIVATE KEY-----', '')
            .replaceAll(RegExp(r'\s+'), '') // Remove all whitespace including newlines
            .trim();
      }
      
      final keyBytes = base64Decode(lines);
      
      if (isPkcs1) {
        return _parsePKCS1PrivateKey(keyBytes);
      } else {
        return _parsePKCS8PrivateKey(keyBytes);
      }
    } catch (e) {
      print('Error parsing RSA private key from PEM: $e');
      rethrow;
    }
  }

  /// Parse PKCS#1 RSA private key
  static RSAPrivateKey _parsePKCS1PrivateKey(Uint8List keyBytes) {
    final privateKeyParser = ASN1Parser(keyBytes);
    final privateKeySeq = privateKeyParser.nextObject() as ASN1Sequence;
    
    // PKCS#1 RSAPrivateKey structure:
    // version, n, e, d, p, q, dP, dQ, qInv
    if (privateKeySeq.elements.length < 6) {
      throw FormatException('Invalid PKCS#1 private key structure');
    }
    
    final modulus = (privateKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
    final privateExponent = (privateKeySeq.elements[3] as ASN1Integer).valueAsBigInteger;
    final p = (privateKeySeq.elements[4] as ASN1Integer).valueAsBigInteger;
    final q = (privateKeySeq.elements[5] as ASN1Integer).valueAsBigInteger;
    
    if (modulus == null || privateExponent == null || p == null || q == null) {
      throw FormatException('Failed to extract RSA key components');
    }
    
    print('PKCS#1 RSA private key parsed - Modulus bits: ${modulus.bitLength}');
    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  /// Parse PKCS#8 RSA private key
  static RSAPrivateKey _parsePKCS8PrivateKey(Uint8List keyBytes) {
    final asn1Parser = ASN1Parser(keyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    
    if (topLevelSeq.elements.length < 3) {
      throw FormatException('Invalid PKCS#8 structure');
    }
    
    final privateKeyBitString = topLevelSeq.elements[2] as ASN1OctetString;
    final privateKeyBytes = privateKeyBitString.contentBytes();
    
    return _parsePKCS1PrivateKey(privateKeyBytes);
  }

  // Replace the _decryptWithRSAOAEP method in SimpleFilePreviewService

/// RSA-OAEP decryption with SHA-1 first (fast_rsa default), then SHA-256 fallback
static String _decryptWithRSAOAEP(String encryptedData, String privateKeyPem) {
  try {
    print('Starting RSA-OAEP decryption...');
    print('Encrypted data length: ${encryptedData.length}');
    
    final privateKey = _parseRSAPrivateKeyFromPem(privateKeyPem);
    print('Private key modulus bits: ${privateKey.n!.bitLength}');
    
    // Try SHA-1 first (fast_rsa default)
    try {
      print('Attempting RSA-OAEP with SHA-1 (fast_rsa default)...');
      
      final cipher = OAEPEncoding.withCustomDigest(
        () => SHA1Digest(), // SHA-1 to match fast_rsa default
        RSAEngine(),
      );
      
      cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      
      final encryptedBytes = base64Decode(encryptedData);
      print('Encrypted bytes length: ${encryptedBytes.length}');
      
      final maxInputSize = cipher.inputBlockSize;
      print('Max input size for cipher: $maxInputSize');
      
      if (encryptedBytes.length > maxInputSize) {
        throw Exception('Encrypted data too large for RSA key size');
      }
      
      final decryptedBytes = cipher.process(encryptedBytes);
      final decryptedString = utf8.decode(decryptedBytes);
      
      print('RSA-OAEP SHA-1 decryption completed successfully');
      print('Decrypted data length: ${decryptedString.length}');
      return decryptedString;
      
    } catch (sha1Error) {
      print('SHA-1 OAEP failed: $sha1Error');
      
      // Fallback to SHA-256 (for doctor-uploaded files)
      try {
        print('Trying SHA-256 OAEP fallback...');
        
        final cipher = OAEPEncoding.withCustomDigest(
          () => SHA256Digest(), // SHA-256 for doctor uploads
          RSAEngine(),
        );
        
        cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
        
        final encryptedBytes = base64Decode(encryptedData);
        final decryptedBytes = cipher.process(encryptedBytes);
        final decryptedString = utf8.decode(decryptedBytes);
        
        print('RSA-OAEP SHA-256 fallback successful');
        return decryptedString;
        
      } catch (sha256Error) {
        print('SHA-256 OAEP also failed: $sha256Error');
        
        // Final fallback to PKCS#1 v1.5
        print('Trying PKCS#1 v1.5 as final fallback...');
        return _decryptWithRSAPKCS1v15(encryptedData, privateKeyPem);
      }
    }
  } catch (e) {
    print('All RSA decryption methods failed: $e');
    rethrow;
  }
}

/// Fallback RSA-PKCS1v15 decryption - IMPROVED ERROR HANDLING
static String _decryptWithRSAPKCS1v15(String encryptedData, String privateKeyPem) {
  try {
    final privateKey = _parseRSAPrivateKeyFromPem(privateKeyPem);
    final cipher = PKCS1Encoding(RSAEngine());
    cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    
    final encryptedBytes = base64Decode(encryptedData);
    
    // Additional validation
    if (encryptedBytes.length != (privateKey.n!.bitLength / 8).round()) {
      throw Exception('Encrypted data length (${encryptedBytes.length}) does not match key size (${privateKey.n!.bitLength / 8})');
    }
    
    final decryptedBytes = cipher.process(encryptedBytes);
    final decryptedString = utf8.decode(decryptedBytes);
    
    print('PKCS1v15 fallback decryption successful');
    return decryptedString;
  } catch (e) {
    print('PKCS1v15 fallback decryption error: $e');
    rethrow;
  }
}

  /// AES-256-GCM decryption - IMPROVED ERROR HANDLING
  static Future<Uint8List> _decryptWithAES256GCM(
      Uint8List encryptedData, Uint8List key, Uint8List nonce) async {
    try {
      print('Starting AES-256-GCM decryption...');
      print('Encrypted data length: ${encryptedData.length}');
      print('Key length: ${key.length}');
      print('Nonce length: ${nonce.length}');
      
      if (encryptedData.length < 16) {
        throw Exception('Encrypted data too short - missing MAC (${encryptedData.length} bytes)');
      }
      
      if (key.length != 32) {
        throw Exception('Invalid AES-256 key length: ${key.length} (expected 32)');
      }
      
      if (nonce.length != 12) {
        throw Exception('Invalid GCM nonce length: ${nonce.length} (expected 12)');
      }
      
      final cipherTextLength = encryptedData.length - 16;
      final cipherText = encryptedData.sublist(0, cipherTextLength);
      final macBytes = encryptedData.sublist(cipherTextLength);
      
      print('Cipher text length: ${cipherText.length}');
      print('MAC length: ${macBytes.length}');
      
      final secretKey = SecretKey(key);
      final mac = Mac(macBytes);
      
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      
      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      
      print('AES-256-GCM decryption completed successfully: ${decryptedBytes.length} bytes');
      return Uint8List.fromList(decryptedBytes);
    } catch (e) {
      print('AES-256-GCM decryption error: $e');
      rethrow;
    }
  }

  /// Decrypt file using the cryptography package - IMPROVED VERSION
  static Future<Uint8List?> _decryptFile(Map<String, dynamic> file) async {
    try {
      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

      if (ipfsCid == null) {
        print('IPFS CID not found');
        return null;
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        print('Authentication error');
        return null;
      }

      print('Current user: ${currentUser.email}');
      print('File ID: $fileId');
      print('IPFS CID: $ipfsCid');

      // Get current user's data
      final userResponse = await Supabase.instance.client
          .from('User')
          .select('id, rsa_private_key, email')
          .eq('email', currentUser.email!)
          .single();

      final actualUserId = userResponse['id'] as String?;
      final rsaPrivateKeyPem = userResponse['rsa_private_key'] as String?;

      if (actualUserId == null || rsaPrivateKeyPem == null) {
        print('User authentication error');
        return null;
      }

      print('User ID: $actualUserId');
      print('RSA private key length: ${rsaPrivateKeyPem.length}');

      // Get all file keys for this file
      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, file_id, recipient_type, recipient_id, aes_key_encrypted')
          .eq('file_id', fileId);

      print('Found ${allFileKeys.length} file keys');

      Map<String, dynamic>? usableKey;
      
      // Look for a key we can use
      for (var key in allFileKeys) {
        print('Checking key: ${key['recipient_type']} - ${key['recipient_id']}');
        if (key['recipient_type'] == 'user' && key['recipient_id'] == actualUserId) {
          usableKey = key;
          print('Found usable key for current user');
          break;
        }
      }

      if (usableKey == null) {
        print('No usable key found for user $actualUserId');
        return null;
      }

      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      print('Encrypted key data length: ${encryptedKeyData.length}');

      // Decrypt the AES key package
      final decryptedKeyDataJson = _decryptWithRSAOAEP(encryptedKeyData, rsaPrivateKeyPem);
      print('Successfully decrypted RSA key package');
      
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
      final aesKeyBase64 = keyData['key'] as String?;
      final aesNonceBase64 = keyData['nonce'] as String?;

      if (aesKeyBase64 == null || aesNonceBase64 == null) {
        throw Exception('Missing AES key or nonce in decrypted data');
      }

      final aesKey = base64Decode(aesKeyBase64);
      final aesNonce = base64Decode(aesNonceBase64);

      print('AES key length: ${aesKey.length}');
      print('AES nonce length: ${aesNonce.length}');

      // Download file from IPFS
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      print('Downloading from: $ipfsUrl');
      
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download from IPFS: ${response.statusCode}');
      }

      final encryptedFileBytes = response.bodyBytes;
      print('Downloaded encrypted file: ${encryptedFileBytes.length} bytes');

      // Decrypt the file
      final decryptedBytes = await _decryptWithAES256GCM(encryptedFileBytes, aesKey, aesNonce);

      print('File decrypted successfully: ${decryptedBytes.length} bytes');
      return decryptedBytes;
      
    } catch (e, stackTrace) {
      print('Error decrypting file: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// Simple image preview
  static void _showImagePreview(BuildContext context, String fileName, Uint8List imageBytes) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(fileName),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.memory(
                imageBytes,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Failed to load image', style: TextStyle(color: Colors.white)),
                        const SizedBox(height: 8),
                        Text('Error: $error', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// Simple text preview
  static void _showTextPreview(BuildContext context, String fileName, Uint8List textBytes) {
    try {
      final textContent = String.fromCharCodes(textBytes);
      final extension = fileName.toLowerCase().split('.').last;
      
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(fileName),
            ),
            body: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Icon(_getFileIcon(extension), size: 20),
                      const SizedBox(width: 8),
                      Text('${_formatFileSize(textBytes.length)} • ${extension.toUpperCase()}'),
                      const Spacer(),
                      Text('${textContent.split('\n').length} lines'),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      textContent,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      print('Error showing text preview: $e');
    }
  }

  /// Simple PDF preview placeholder
  static void _showPDFPreview(BuildContext context, String fileName, Uint8List pdfBytes) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 400,
          height: 300,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('PDF Preview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(fileName, textAlign: TextAlign.center),
              Text('${_formatFileSize(pdfBytes.length)}'),
              const SizedBox(height: 16),
              const Text('PDF viewer not implemented in preview mode', 
                style: TextStyle(color: Colors.grey), 
                textAlign: TextAlign.center
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Generic preview for unsupported file types
  static void _showGenericPreview(
    BuildContext context, 
    String fileName, 
    Uint8List fileBytes, 
    String extension
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 400,
          height: 400,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(_getFileIcon(extension), size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                extension.toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                fileName,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('Size: ${_formatFileSize(fileBytes.length)}'),
              const SizedBox(height: 16),
              const Text(
                'Preview not available for this file type.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              if (fileBytes.length < 2000) ...[
                const Text(
                  'Hex Preview (first 500 bytes):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _bytesToHex(fileBytes.take(500).toList()),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper methods
  static bool _isImageFile(String extension) {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'];
    return imageExtensions.contains(extension);
  }
  
  static bool _isTextFile(String extension) {
    const textExtensions = ['txt', 'json', 'xml', 'csv', 'log', 'md', 'html', 'css', 'js'];
    return textExtensions.contains(extension);
  }

  static IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
      case 'md':
        return Icons.text_snippet;
      case 'json':
      case 'xml':
        return Icons.code;
      case 'csv':
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
        return Icons.archive;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
        return Icons.audio_file;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 16) {
      buffer.write('${i.toRadixString(16).padLeft(8, '0')}: ');
      
      for (int j = 0; j < 16; j++) {
        if (i + j < bytes.length) {
          buffer.write('${bytes[i + j].toRadixString(16).padLeft(2, '0')} ');
        } else {
          buffer.write('   ');
        }
      }
      
      buffer.write(' |');
      for (int j = 0; j < 16 && i + j < bytes.length; j++) {
        final byte = bytes[i + j];
        if (byte >= 32 && byte <= 126) {
          buffer.write(String.fromCharCode(byte));
        } else {
          buffer.write('.');
        }
      }
      buffer.write('|\n');
    }
    return buffer.toString();
  }
}