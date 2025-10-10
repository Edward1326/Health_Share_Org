import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'package:mime/mime.dart';

class FullscreenFilePreviewWeb extends StatefulWidget {
  final String fileName;
  final Uint8List bytes;

  const FullscreenFilePreviewWeb({
    super.key,
    required this.fileName,
    required this.bytes,
  });

  @override
  State<FullscreenFilePreviewWeb> createState() => _FullscreenFilePreviewWebState();
}

class _FullscreenFilePreviewWebState extends State<FullscreenFilePreviewWeb> {
  String? _mimeType;
  late String _extension;
  String? _iframeViewId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _extension = widget.fileName.split('.').last.toLowerCase();
    _mimeType = lookupMimeType(widget.fileName) ?? _getMimeTypeFromExtension(_extension);
    
    // For PDF and other embeddable content, create iframe
    if (_shouldUseIframe()) {
      _createIframeView();
    }
  }

  /// Get MIME type from file extension as fallback
  String _getMimeTypeFromExtension(String ext) {
    const mimeTypes = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'json': 'application/json',
      'xml': 'application/xml',
      'csv': 'text/csv',
      'html': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'mp4': 'video/mp4',
      'webm': 'video/webm',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  /// Check if file should use iframe for preview
  bool _shouldUseIframe() {
    return _extension == 'pdf' || 
           _mimeType?.startsWith('video/') == true ||
           _mimeType?.startsWith('audio/') == true;
  }

  /// Create iframe view for PDF, video, or audio
  void _createIframeView() {
    final blob = html.Blob([widget.bytes], _mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    _iframeViewId = 'iframe-${DateTime.now().millisecondsSinceEpoch}';
    
    // Register iframe view factory
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      _iframeViewId!,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        
        return iframe;
      },
    );
  }

  @override
  void dispose() {
    // Cleanup is automatic for web
    super.dispose();
  }

  /// Download file to user's computer
  void _downloadFile() {
    setState(() => _isLoading = true);

    try {
      final blob = html.Blob([widget.bytes], _mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', widget.fileName)
        ..click();
      
      // Cleanup
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading ${widget.fileName}...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Open file in new tab
  void _openInNewTab() {
    try {
      final blob = html.Blob([widget.bytes], _mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
      
      // Cleanup after a delay
      Future.delayed(const Duration(seconds: 2), () {
        html.Url.revokeObjectUrl(url);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    // PDF Preview (embedded iframe)
    if (_extension == 'pdf' && _iframeViewId != null) {
      content = Column(
        children: [
          Expanded(
            child: HtmlElementView(viewType: _iframeViewId!),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _downloadFile,
                  icon: const Icon(Icons.download),
                  label: const Text('Download PDF'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _openInNewTab,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in New Tab'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    // Video Preview (embedded iframe)
    else if (_mimeType?.startsWith('video/') == true && _iframeViewId != null) {
      content = Column(
        children: [
          Expanded(
            child: HtmlElementView(viewType: _iframeViewId!),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black87,
            child: Text(
              widget.fileName,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    // Audio Preview (embedded iframe)
    else if (_mimeType?.startsWith('audio/') == true && _iframeViewId != null) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.audiotrack, size: 100, color: Colors.white70),
          const SizedBox(height: 24),
          Text(
            widget.fileName,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 60,
            child: HtmlElementView(viewType: _iframeViewId!),
          ),
        ],
      );
    }
    // Image Preview
    else if (_mimeType?.startsWith('image/') == true) {
      content = InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Failed to load image',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
    // Text File Preview
    else if (_isTextFile(_extension)) {
      content = _buildTextPreview();
    }
    // Document files that should be downloaded
    else if (_isDocumentFile(_extension)) {
      content = _buildDocumentDownloadView();
    }
    // Unsupported preview
    else {
      content = _buildUnsupportedView();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.fileName,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadFile,
            tooltip: 'Download',
          ),
          if (_extension == 'pdf' || 
              _mimeType?.startsWith('video/') == true ||
              _mimeType?.startsWith('audio/') == true)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: _openInNewTab,
              tooltip: 'Open in New Tab',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : content,
    );
  }

  /// Check if file is a text file
  bool _isTextFile(String extension) {
    const textExtensions = [
      'txt', 'json', 'xml', 'csv', 'log', 'md', 
      'html', 'css', 'js', 'dart', 'py', 'java',
      'cpp', 'c', 'h', 'ts', 'jsx', 'tsx',
    ];
    return textExtensions.contains(extension);
  }

  /// Check if file is a document that should be downloaded
  bool _isDocumentFile(String extension) {
    const docExtensions = [
      'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
      'zip', 'rar', '7z', 'tar', 'gz',
      'epub', 'mobi',
    ];
    return docExtensions.contains(extension);
  }

  /// Build text file preview
  Widget _buildTextPreview() {
    try {
      final textContent = String.fromCharCodes(widget.bytes);
      return Container(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            textContent,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: Colors.black,
            ),
          ),
        ),
      );
    } catch (e) {
      return Center(
        child: Text(
          'Error displaying text: $e',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
  }

  /// Build document download view
  Widget _buildDocumentDownloadView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getFileIcon(), size: 80, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            widget.fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _formatFileSize(widget.bytes.length),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
            onPressed: _downloadFile,
            icon: const Icon(Icons.download),
            label: Text('Download ${_getAppTypeName()}'),
          ),
          const SizedBox(height: 16),
          Text(
            'Preview not available in browser',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Download and open with appropriate app',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Build unsupported file view
  Widget _buildUnsupportedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insert_drive_file, size: 80, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            widget.fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Type: ${_mimeType ?? 'Unknown'}',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            'Size: ${_formatFileSize(widget.bytes.length)}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          Text(
            'Preview not supported for .$_extension files',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: _downloadFile,
            icon: const Icon(Icons.download),
            label: const Text('Download File'),
          ),
        ],
      ),
    );
  }

  /// Get icon based on file type
  IconData _getFileIcon() {
    if (_extension == 'pdf') return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(_extension)) return Icons.description;
    if (['xls', 'xlsx'].contains(_extension)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(_extension)) return Icons.slideshow;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(_extension)) {
      return Icons.folder_zip;
    }
    if (['epub', 'mobi'].contains(_extension)) return Icons.menu_book;
    return Icons.insert_drive_file;
  }

  /// Get app type name based on file extension
  String _getAppTypeName() {
    if (_extension == 'pdf') return 'PDF';
    if (['doc', 'docx'].contains(_extension)) return 'Document';
    if (['xls', 'xlsx'].contains(_extension)) return 'Spreadsheet';
    if (['ppt', 'pptx'].contains(_extension)) return 'Presentation';
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(_extension)) {
      return 'Archive';
    }
    if (['epub', 'mobi'].contains(_extension)) return 'Ebook';
    return 'File';
  }

  /// Format file size
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}