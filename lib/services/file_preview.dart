import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:health_share_org/services/crypto_utilstest.dart';
import 'package:health_share_org/services/aes_helper.dart';

class EnhancedFilePreviewService {
  /// Enhanced file preview with better error handling and file type detection
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

      // Use the working decryption logic from FileDecryptionService
      final decryptedBytes = await _decryptFileUsingWorkingMethod(file);
      
      // Close loading dialog
      Navigator.of(context).pop();

      if (decryptedBytes == null) {
        showSnackBar('Failed to decrypt file');
        return;
      }

      final fileName = file['filename'] ?? 'Unknown File';
      final extension = fileName.toLowerCase().split('.').last;
      
      // For images, show in-app preview
      if (_isImageFile(extension)) {
        _showImagePreview(context, fileName, decryptedBytes, showSnackBar);
        return;
      }
      
      // For text files, show in-app preview
      if (_isTextFile(extension)) {
        _showTextPreview(context, fileName, decryptedBytes, showSnackBar);
        return;
      }

      // For PDF files, show enhanced PDF preview
      if (extension == 'pdf') {
        _showPDFPreview(context, fileName, decryptedBytes, showSnackBar);
        return;
      }
      
      // For other files, save to external storage and open with system app
      await _openWithSystemApp(context, fileName, decryptedBytes, showSnackBar);
      
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      print('Error in previewFile: $e');
      showSnackBar('Error opening file: $e');
    }
  }

  /// Preview file in new tab/window (web-like experience)
  static Future<void> previewFileInNewTab(
    BuildContext context,
    Map<String, dynamic> file,
    Function(String) showSnackBar,
  ) async {
    // For mobile, this opens in full screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenFilePreview(
          file: file,
          showSnackBar: showSnackBar,
        ),
      ),
    );
  }

  /// Use the working decryption method from FileDecryptionService
  static Future<Uint8List?> _decryptFileUsingWorkingMethod(Map<String, dynamic> file) async {
    try {
      final fileId = file['id'];
      final ipfsCid = file['ipfs_cid'];

      if (ipfsCid == null) {
        print('IPFS CID not found');
        return null;
      }

      // Get current user from auth
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        print('Authentication error');
        return null;
      }

      // Get the User record by email
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

      // Parse RSA private key
      final rsaPrivateKey = MyCryptoUtils.rsaPrivateKeyFromPem(rsaPrivateKeyPem);

      // Get File_Keys for this file
      final allFileKeys = await Supabase.instance.client
          .from('File_Keys')
          .select('id, file_id, recipient_type, recipient_id, aes_key_encrypted, nonce_hex')
          .eq('file_id', fileId);

      // Find usable key
      Map<String, dynamic>? usableKey;
      
      // Try direct user key first
      for (var key in allFileKeys) {
        if (key['recipient_type'] == 'user' && key['recipient_id'] == actualUserId) {
          usableKey = key;
          break;
        }
      }

      if (usableKey == null) {
        print('No usable key found');
        return null;
      }

      // Decrypt the AES key
      final encryptedKeyData = usableKey['aes_key_encrypted'] as String;
      final decryptedKeyDataJson = MyCryptoUtils.rsaDecrypt(encryptedKeyData, rsaPrivateKey);
      
      final keyData = jsonDecode(decryptedKeyDataJson) as Map<String, dynamic>;
      final aesKeyHex = keyData['key'] as String?;
      final aesNonceHex = keyData['nonce'] as String? ?? usableKey['nonce_hex'] as String?;

      if (aesKeyHex == null || aesNonceHex == null) {
        throw Exception('Missing AES key or nonce in decrypted data');
      }

      // Download file from IPFS
      final ipfsUrl = 'https://gateway.pinata.cloud/ipfs/$ipfsCid';
      final response = await http.get(Uri.parse(ipfsUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download from IPFS: ${response.statusCode}');
      }

      final encryptedFileBytes = response.bodyBytes;

      // Decrypt the file
      final aesHelper = AESHelper(aesKeyHex, aesNonceHex);
      final decryptedBytes = aesHelper.decryptData(encryptedFileBytes);

      print('File decrypted successfully: ${decryptedBytes.length} bytes');
      return decryptedBytes;
      
    } catch (e) {
      print('Error decrypting file: $e');
      return null;
    }
  }
  
  /// Check if file is an image
  static bool _isImageFile(String extension) {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'];
    return imageExtensions.contains(extension);
  }
  
  /// Check if file is a text file
  static bool _isTextFile(String extension) {
    const textExtensions = ['txt', 'json', 'xml', 'csv', 'log', 'md', 'html', 'css', 'js'];
    return textExtensions.contains(extension);
  }
  
  /// Show enhanced image preview with zoom and pan
  static void _showImagePreview(
    BuildContext context,
    String fileName,
    Uint8List imageBytes,
    Function(String) showSnackBar,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(fileName),
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => _saveToDownloads(context, fileName, imageBytes, showSnackBar),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _shareFile(context, fileName, imageBytes, showSnackBar),
              ),
            ],
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
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _saveToDownloads(context, fileName, imageBytes, showSnackBar),
                          child: const Text('Save to Downloads'),
                        ),
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
  
  /// Show enhanced text preview with syntax highlighting for code
  static void _showTextPreview(
    BuildContext context,
    String fileName,
    Uint8List textBytes,
    Function(String) showSnackBar,
  ) {
    try {
      final textContent = String.fromCharCodes(textBytes);
      final extension = fileName.toLowerCase().split('.').last;
      
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(fileName),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    // Copy to clipboard functionality
                    showSnackBar('Copy to clipboard feature coming soon!');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () => _saveToDownloads(context, fileName, textBytes, showSnackBar),
                ),
              ],
            ),
            body: Column(
              children: [
                // File info bar
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
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        height: 1.4,
                        color: _isCodeFile(extension) ? Colors.blue[900] : Colors.black87,
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
      showSnackBar('Error displaying text: $e');
    }
  }

  /// Show PDF preview with page navigation
  static void _showPDFPreview(
    BuildContext context,
    String fileName,
    Uint8List pdfBytes,
    Function(String) showSnackBar,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(fileName),
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => _saveToDownloads(context, fileName, pdfBytes, showSnackBar),
              ),
            ],
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('PDF Preview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(fileName),
                Text('${_formatFileSize(pdfBytes.length)}'),
                const SizedBox(height: 24),
                const Text('PDF viewer integration needed', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _openWithSystemApp(context, fileName, pdfBytes, showSnackBar),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Externally'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _saveToDownloads(context, fileName, pdfBytes, showSnackBar),
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// Save file and open with system app
  static Future<void> _openWithSystemApp(
    BuildContext context,
    String fileName,
    Uint8List fileBytes,
    Function(String) showSnackBar,
  ) async {
    try {
      // Save to temporary directory with proper filename
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      
      // Ensure the file is written completely
      await tempFile.writeAsBytes(fileBytes, flush: true);
      
      // Verify file was written correctly
      if (!await tempFile.exists()) {
        throw Exception('Failed to save temporary file');
      }
      
      // Try to open with system app
      final result = await OpenFile.open(tempFile.path);
      
      if (result.type == ResultType.done) {
        print('File opened successfully');
        showSnackBar('File opened successfully');
      } else {
        print('OpenFile result: ${result.type} - ${result.message}');
        _showFileOptionsDialog(context, fileName, fileBytes, tempFile.path, showSnackBar);
      }
      
    } catch (e) {
      print('Error opening file with system app: $e');
      _showFileOptionsDialog(context, fileName, fileBytes, null, showSnackBar);
    }
  }
  
  /// Show options dialog when system app fails
  static void _showFileOptionsDialog(
    BuildContext context,
    String fileName,
    Uint8List fileBytes,
    String? tempFilePath,
    Function(String) showSnackBar,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Preview'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: $fileName'),
            Text('Size: ${_formatFileSize(fileBytes.length)}'),
            const SizedBox(height: 16),
            const Text('Unable to preview this file type in the app.'),
          ],
        ),
        actions: [
          if (tempFilePath != null)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final result = await OpenFile.open(tempFilePath);
                if (result.type != ResultType.done) {
                  showSnackBar('Could not open: ${result.message}');
                }
              },
              child: const Text('Try Again'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _saveToDownloads(context, fileName, fileBytes, showSnackBar);
            },
            child: const Text('Save to Downloads'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  /// Save file to Downloads folder
  static Future<void> _saveToDownloads(
    BuildContext context,
    String fileName,
    Uint8List fileBytes,
    Function(String) showSnackBar,
  ) async {
    try {
      // Request storage permission
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          showSnackBar('Storage permission required');
          return;
        }
      }
      
      // Get Downloads directory
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else if (Platform.isIOS) {
        downloadsDir = await getApplicationDocumentsDirectory();
      }
      
      if (downloadsDir == null || !await downloadsDir.exists()) {
        downloadsDir = await getApplicationDocumentsDirectory();
      }
      
      // Ensure unique filename
      String uniqueFileName = fileName;
      int counter = 1;
      while (await File('${downloadsDir.path}/$uniqueFileName').exists()) {
        final nameParts = fileName.split('.');
        if (nameParts.length > 1) {
          final name = nameParts.sublist(0, nameParts.length - 1).join('.');
          final extension = nameParts.last;
          uniqueFileName = '${name}_$counter.$extension';
        } else {
          uniqueFileName = '${fileName}_$counter';
        }
        counter++;
      }
      
      final file = File('${downloadsDir.path}/$uniqueFileName');
      await file.writeAsBytes(fileBytes);
      
      showSnackBar('File saved: ${file.path}');
      
    } catch (e) {
      print('Error saving file: $e');
      showSnackBar('Error saving file: $e');
    }
  }

  /// Share file (placeholder for future implementation)
  static Future<void> _shareFile(
    BuildContext context,
    String fileName,
    Uint8List fileBytes,
    Function(String) showSnackBar,
  ) async {
    // Placeholder for sharing functionality
    showSnackBar('Share functionality coming soon!');
  }

  /// Helper methods
  static bool _isCodeFile(String extension) {
    const codeExtensions = ['js', 'ts', 'dart', 'java', 'python', 'cpp', 'c', 'css', 'html', 'xml'];
    return codeExtensions.contains(extension);
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
  
  /// Format file size in human readable format
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Full screen file preview widget for "new tab" experience
class FullScreenFilePreview extends StatefulWidget {
  final Map<String, dynamic> file;
  final Function(String) showSnackBar;

  const FullScreenFilePreview({
    Key? key,
    required this.file,
    required this.showSnackBar,
  }) : super(key: key);

  @override
  State<FullScreenFilePreview> createState() => _FullScreenFilePreviewState();
}

class _FullScreenFilePreviewState extends State<FullScreenFilePreview> {
  bool _isLoading = true;
  Uint8List? _fileBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final bytes = await EnhancedFilePreviewService._decryptFileUsingWorkingMethod(widget.file);
      setState(() {
        _fileBytes = bytes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file['filename'] ?? 'Unknown File';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          if (_fileBytes != null) ...[
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => EnhancedFilePreviewService._saveToDownloads(
                context, 
                fileName, 
                _fileBytes!, 
                widget.showSnackBar
              ),
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => EnhancedFilePreviewService._shareFile(
                context, 
                fileName, 
                _fileBytes!, 
                widget.showSnackBar
              ),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error loading file: $_error'),
                    ],
                  ),
                )
              : _buildFileContent(),
    );
  }

  Widget _buildFileContent() {
    if (_fileBytes == null) return const Center(child: Text('No file data'));

    final fileName = widget.file['filename'] ?? 'Unknown File';
    final extension = fileName.toLowerCase().split('.').last;

    if (EnhancedFilePreviewService._isImageFile(extension)) {
      return Center(
        child: InteractiveViewer(
          child: Image.memory(_fileBytes!, fit: BoxFit.contain),
        ),
      );
    }

    if (EnhancedFilePreviewService._isTextFile(extension)) {
      final textContent = String.fromCharCodes(_fileBytes!);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          textContent,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            height: 1.4,
          ),
        ),
      );
    }

    // For other file types, show info and options
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            EnhancedFilePreviewService._getFileIcon(extension),
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            fileName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            EnhancedFilePreviewService._formatFileSize(_fileBytes!.length),
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          const Text('This file type cannot be previewed in the app'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => EnhancedFilePreviewService._openWithSystemApp(
              context, 
              fileName, 
              _fileBytes!, 
              widget.showSnackBar
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open with System App'),
          ),
        ],
      ),
    );
  }
}