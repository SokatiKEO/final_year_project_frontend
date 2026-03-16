// lib/models/transfer_record.dart

enum TransferDirection { sent, received }

class TransferRecord {
  final String id;
  final TransferDirection direction;
  final String deviceName;
  final List<String> fileNames;
  final List<int> fileSizes;
  final List<String> filePaths;
  final DateTime completedAt;
  final bool success;
  final String? errorMessage;
  final String? saveFolderPath;

  const TransferRecord({
    required this.id,
    required this.direction,
    required this.deviceName,
    required this.fileNames,
    required this.fileSizes,
    this.filePaths = const [],
    required this.completedAt,
    required this.success,
    this.errorMessage,
    this.saveFolderPath,
  });

  int get totalBytes => fileSizes.fold(0, (a, b) => a + b);

  String get totalSizeLabel {
    final bytes = totalBytes;
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  String get timeLabel {
    final now = DateTime.now();
    final diff = now.difference(completedAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${completedAt.day}/${completedAt.month}/${completedAt.year}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'direction': direction.name,
        'deviceName': deviceName,
        'fileNames': fileNames,
        'fileSizes': fileSizes,
        'filePaths': filePaths,
        'completedAt': completedAt.toIso8601String(),
        'success': success,
        'errorMessage': errorMessage,
        'saveFolderPath': saveFolderPath,
      };

  factory TransferRecord.fromJson(Map<String, dynamic> json) => TransferRecord(
        id: json['id'] as String,
        direction: TransferDirection.values.byName(json['direction'] as String),
        deviceName: json['deviceName'] as String,
        fileNames: List<String>.from(json['fileNames'] as List),
        fileSizes: List<int>.from(json['fileSizes'] as List),
        filePaths: json['filePaths'] != null
            ? List<String>.from(json['filePaths'] as List)
            : [],
        completedAt: DateTime.parse(json['completedAt'] as String),
        success: json['success'] as bool,
        errorMessage: json['errorMessage'] as String?,
        saveFolderPath: json['saveFolderPath'] as String?,
      );
}