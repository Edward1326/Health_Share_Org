import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

class EnhancedFilePreviewService {
  /// Enhanced file preview with better error handling and file type detection
  static Future<void> previewFile(
    BuildContext context,
    String fileName,
    Uint8List decryptedBytes,
  ) async {
    try {
      // Get file extension
      final extension = fileName.toLowerCase().split('.').last;
      
      // For images, show in-app preview
      if (_isImageFile(extension)) {
        _showImagePreview(context, fileName, decryptedBytes);
        return;
      }
      
      // For text files, show in-app preview
      if (_isTextFile(extension)) {
        _showTextPreview(context, fileName, decryptedBytes);
        return;
      }
      
      // For other files, save to external storage and open with system app
      await _openWithSystemApp(context, fileName, decryptedBytes);
      
    } catch (e) {
      print('Error in previewFile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file: $e')),
      );
    }
  }
  
  /// Check if file is an image
  static bool _isImageFile(String extension) {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return imageExtensions.contains(extension);
  }
  
  /// Check if file is a text file
  static bool _isTextFile(String extension) {
    const textExtensions = ['txt', 'json', 'xml', 'csv', 'log'];
    return textExtensions.contains(extension);
  }
  
  /// Show image preview in app
  static void _showImagePreview(
    BuildContext context,
    String fileName,
    Uint8List imageBytes,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(fileName),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () => _saveToDownloads(context, fileName, imageBytes),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    print('Image loading error: $error');
                    return Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          const Text('Failed to load image'),
                          const SizedBox(height: 8),
                          Text('Error: $error'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _saveToDownloads(context, fileName, imageBytes),
                            child: const Text('Save to Downloads'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Show text preview in app
  static void _showTextPreview(
    BuildContext context,
    String fileName,
    Uint8List textBytes,
  ) {
    try {
      final textContent = String.fromCharCodes(textBytes);
      
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            children: [
              AppBar(
                title: Text(fileName),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () => _saveToDownloads(context, fileName, textBytes),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    textContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Error showing text preview: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error displaying text: $e')),
      );
    }
  }
  
  /// Save file and open with system app
  static Future<void> _openWithSystemApp(
    BuildContext context,
    String fileName,
    Uint8List fileBytes,
  ) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Save to temporary directory with proper filename
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      
      // Ensure the file is written completely
      await tempFile.writeAsBytes(fileBytes, flush: true);
      
      // Verify file was written correctly
      if (!await tempFile.exists()) {
        throw Exception('Failed to save temporary file');
      }
      
      final fileSize = await tempFile.length();
      print('Temp file created: ${tempFile.path}');
      print('File size: $fileSize bytes (original: ${fileBytes.length})');
      
      Navigator.of(context).pop(); // Close loading dialog
      
      // Try to open with system app
      final result = await OpenFile.open(tempFile.path);
      
      if (result.type == ResultType.done) {
        print('File opened successfully');
      } else {
        print('OpenFile result: ${result.type} - ${result.message}');
        
        // Show options dialog if system app failed
        _showFileOptionsDialog(context, fileName, fileBytes, tempFile.path);
      }
      
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog if still open
      print('Error opening file with system app: $e');
      
      // Show fallback options
      _showFileOptionsDialog(context, fileName, fileBytes, null);
    }
  }
  
  /// Show options dialog when system app fails
  static void _showFileOptionsDialog(
    BuildContext context,
    String fileName,
    Uint8List fileBytes,
    String? tempFilePath,
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open: ${result.message}')),
                  );
                }
              },
              child: const Text('Try Again'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _saveToDownloads(context, fileName, fileBytes);
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
  ) async {
    try {
      // Request storage permission
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission required')),
          );
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
        // Fallback to app documents directory
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved: ${file.path}'),
          duration: const Duration(seconds: 3),
        ),
      );
      
    } catch (e) {
      print('Error saving file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving file: $e')),
      );
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