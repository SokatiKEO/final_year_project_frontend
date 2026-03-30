// lib/screens/history_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/transfer_record.dart';
import '../services/history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _service = HistoryService();
  late Future<List<TransferRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.loadAll();
  }

  void _reload() => setState(() => _future = _service.loadAll());

  Future<void> _openFolder() async {
    String path;
    if (Platform.isAndroid) {
      path = '/storage/emulated/0/Download/Dropix';
    } else if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      path = '${docs.path}/Dropix';
    } else if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
      path = '$home\\Downloads\\Dropix';
    } else {
      final home = Platform.environment['HOME'] ?? '/tmp';
      path = '$home/Downloads/Dropix';
    }
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    await OpenFilex.open(path);
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1422),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear History',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'All transfer history will be permanently deleted.',
          style: TextStyle(color: Color(0xFF5A6580)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF5A6580))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear',
                style: TextStyle(color: Color(0xFFFF5C87))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.clearAll();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(
          children: [
            // ── App bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const Expanded(
                    child: Text(
                      'Transfer History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openFolder,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5C0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF00E5C0).withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.folder_open_rounded,
                              color: Color(0xFF00E5C0), size: 13),
                          SizedBox(width: 5),
                          Text(
                            'Open Folder',
                            style: TextStyle(
                              color: Color(0xFF00E5C0),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FutureBuilder<List<TransferRecord>>(
                    future: _future,
                    builder: (_, snap) {
                      if ((snap.data ?? []).isEmpty) return const SizedBox();
                      return GestureDetector(
                        onTap: _confirmClearAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5C87).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFF5C87).withOpacity(0.3),
                            ),
                          ),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: Color(0xFFFF5C87),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── List ───────────────────────────────────────────────────────
            Expanded(
              child: FutureBuilder<List<TransferRecord>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF3D7BFF),
                        strokeWidth: 2,
                      ),
                    );
                  }

                  final records = snap.data ?? [];

                  if (records.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async => _reload(),
                      color: const Color(0xFF3D7BFF),
                      backgroundColor: const Color(0xFF0E1422),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 180),
                          _EmptyState(),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    color: const Color(0xFF3D7BFF),
                    backgroundColor: const Color(0xFF0E1422),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      itemCount: records.length,
                      itemBuilder: (context, index) => _RecordCard(
                        record: records[index],
                        onDelete: () async {
                          await _service.deleteRecord(records[index].id);
                          _reload();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Record card ───────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final TransferRecord record;
  final VoidCallback onDelete;
  const _RecordCard({required this.record, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isSent = record.direction == TransferDirection.sent;
    final accentColor =
        isSent ? const Color(0xFF3D7BFF) : const Color(0xFF00E5C0);

    return Dismissible(
      key: Key(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5C87).withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFFF5C87), size: 22),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1422),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Direction icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: accentColor.withOpacity(0.25)),
                  ),
                  child: Center(
                    child: Icon(
                      isSent
                          ? Icons.upload_rounded
                          : Icons.download_rounded,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              record.deviceName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!record.success)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFFF5C87).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Failed',
                                style: TextStyle(
                                  color: Color(0xFFFF5C87),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _filesSummary(),
                        style: const TextStyle(
                            color: Color(0xFF5A6580), fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Right side: size + time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      record.totalSizeLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.timeLabel,
                      style: const TextStyle(
                          color: Color(0xFF3A4460), fontSize: 11),
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

  String _filesSummary() {
    if (record.fileNames.isEmpty) return 'No files';
    if (record.fileNames.length == 1) return record.fileNames.first;
    return '${record.fileNames.first} +${record.fileNames.length - 1} more';
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RecordDetailSheet(record: record),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _RecordDetailSheet extends StatelessWidget {
  final TransferRecord record;
  const _RecordDetailSheet({required this.record});

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  /// Opens the save folder in the OS file manager / Files app.
  Future<void> _openFile(BuildContext context, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _showSnack(context, 'File no longer exists.');
      return;
    }
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      _showSnack(context, 'No app found to open this file.');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: const Color(0xFF1E2940),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSent = record.direction == TransferDirection.sent;
    final accentColor =
        isSent ? const Color(0xFF3D7BFF) : const Color(0xFF00E5C0);
    final dirLabel = isSent ? 'Sent to' : 'Received from';

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1422),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Color(0xFF1E2940))),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: accentColor.withOpacity(0.25)),
                    ),
                    child: Center(
                      child: Icon(
                        isSent
                            ? Icons.upload_rounded
                            : Icons.download_rounded,
                        color: accentColor,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dirLabel,
                          style: const TextStyle(
                              color: Color(0xFF5A6580), fontSize: 11),
                        ),
                        Text(
                          record.deviceName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        record.totalSizeLabel,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        record.timeLabel,
                        style: const TextStyle(
                            color: Color(0xFF3A4460), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Divider
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.white.withOpacity(0.05),
            ),
            const SizedBox(height: 4),

            // File list
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: record.fileNames.length,
                itemBuilder: (_, i) {
                  final name = record.fileNames[i];
                  final size =
                      i < record.fileSizes.length ? record.fileSizes[i] : 0;
                  final path =
                      i < record.filePaths.length ? record.filePaths[i] : null;
                  final canOpen = path != null && File(path).existsSync();
                  return GestureDetector(
                    onTap: canOpen ? () => _openFile(context, path!) : null,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141929),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: canOpen
                                ? Colors.white.withOpacity(0.1)
                                : Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        children: [
                          Text(_emojiForFile(name),
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _sizeLabel(size),
                            style: const TextStyle(
                                color: Color(0xFF5A6580), fontSize: 11),
                          ),
                          if (canOpen) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.open_in_new_rounded,
                                size: 13, color: Color(0xFF5A6580)),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('📭', style: TextStyle(fontSize: 48)),
          SizedBox(height: 16),
          Text(
            'No transfers yet',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Completed transfers will appear here.',
            style: TextStyle(color: Color(0xFF5A6580), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _emojiForFile(String name) {
  final ext = name.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return '🖼️';
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
      return '🎬';
    case 'mp3':
    case 'aac':
    case 'wav':
    case 'flac':
      return '🎵';
    case 'pdf':
      return '📄';
    case 'zip':
    case 'rar':
    case '7z':
      return '📦';
    case 'doc':
    case 'docx':
      return '📝';
    default:
      return '📁';
  }
}