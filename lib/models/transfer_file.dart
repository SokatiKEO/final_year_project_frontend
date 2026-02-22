// lib/models/transfer_file.dart
//
// Represents a file queued for or received from a transfer.

import 'dart:io';

enum TransferStatus { pending, transferring, done, failed }

class TransferFile {
  final String id;
  final String name;
  final String path;       // Local file path
  final int sizeBytes;
  TransferStatus status;
  int bytesTransferred;
  String? error;

  TransferFile({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.status = TransferStatus.pending,
    this.bytesTransferred = 0,
    this.error,
  });

  double get progress =>
      sizeBytes == 0 ? 0 : bytesTransferred / sizeBytes;

  String get sizeLabel {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  String get emoji {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': return '🖼️';
      case 'mp4': case 'mov': case 'avi': case 'mkv': return '🎬';
      case 'mp3': case 'aac': case 'wav': case 'flac': return '🎵';
      case 'pdf': return '📄';
      case 'zip': case 'rar': case '7z': return '📦';
      case 'doc': case 'docx': return '📝';
      default: return '📁';
    }
  }

  /// Build from a File on disk
  static Future<TransferFile> fromFile(File file) async {
    final stat = await file.stat();
    return TransferFile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: file.path.split(Platform.pathSeparator).last,
      path: file.path,
      sizeBytes: stat.size,
    );
  }
}
