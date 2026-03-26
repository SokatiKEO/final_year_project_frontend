// lib/screens/receive_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/transfer_provider.dart';

class ReceiveSheet extends StatelessWidget {
  const ReceiveSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<TransferProvider>(),
        child: const ReceiveSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransferProvider>(
      builder: (context, provider, _) {
        // if (provider.phase == TransferPhase.done ||
        //     provider.phase == TransferPhase.error) {
        //   WidgetsBinding.instance.addPostFrameCallback((_) {
        //     if (Navigator.canPop(context)) Navigator.pop(context);
        //   });
        // }

        // Lock drag during active transfer so it can't be accidentally dismissed
        final isTransferring = provider.phase == TransferPhase.transferring;

        return GestureDetector(
          onVerticalDragUpdate: isTransferring ? (_) {} : null,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0E1422),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(color: Color(0xFF1E2940), width: 1),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
            child: switch (provider.phase) {
              TransferPhase.connecting => _IncomingRequest(provider: provider),
              TransferPhase.transferring =>
                _ReceivingProgress(provider: provider),
              TransferPhase.done => _ReceiveDone(provider: provider),
              TransferPhase.error => _ReceiveError(provider: provider),
              _ => const SizedBox.shrink(),
            },
          ),
        );
      },
    );
  }
}

// ── Drag handle ───────────────────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

// ── 1. Incoming request — Accept / Decline ────────────────────────────────────

class _IncomingRequest extends StatelessWidget {
  final TransferProvider provider;
  const _IncomingRequest({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),

        // Pulsing badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5C0).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00E5C0).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(),
              const SizedBox(width: 6),
              const Text(
                'Incoming Drop',
                style: TextStyle(
                  color: Color(0xFF00E5C0),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Sender avatar
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF5C87), Color(0xFFFF8C42)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5C87).withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              (provider.incomingFromDevice ?? '?')[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        Text(
          provider.incomingFromDevice ?? 'Unknown Device',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'wants to send you files',
          style: TextStyle(color: Color(0xFF5A6580), fontSize: 13),
        ),

        const SizedBox(height: 20),

        // ── Rich file preview ─────────────────────────────────────────────
        if (provider.incomingFileNames.isNotEmpty)
          _FilePreviewCard(
            fileNames: provider.incomingFileNames,
            fileSizes: provider.incomingFileSizes,
          ),

        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            // Decline
            Expanded(
              child: GestureDetector(
                onTap: () {
                  provider.declineIncoming();
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141929),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
                  ),
                  child: const Center(
                    child: Text(
                      'Decline',
                      style: TextStyle(
                        color: Color(0xFF5A6580),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Accept
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => provider.acceptIncoming(),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5C0), Color(0xFF00B8A3)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5C0).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '✓  Accept',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── File preview card ─────────────────────────────────────────────────────────

class _FilePreviewCard extends StatelessWidget {
  final List<String> fileNames;
  final List<int> fileSizes;
  const _FilePreviewCard({required this.fileNames, required this.fileSizes});

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  int get _totalBytes => fileSizes.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final previewFiles = fileNames.take(4).toList();
    final overflow = fileNames.length - previewFiles.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Header: file count + total size pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${fileNames.length} file${fileNames.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Color(0xFF5A6580),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              if (fileSizes.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D7BFF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _sizeLabel(_totalBytes),
                    style: const TextStyle(
                      color: Color(0xFF3D7BFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // File rows
          ...List.generate(previewFiles.length, (i) {
            final name = previewFiles[i];
            final size = i < fileSizes.length ? fileSizes[i] : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Type badge
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1422),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Center(
                      child: Text(
                        _emojiForFile(name),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // File name
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
                  // File size
                  Text(
                    _sizeLabel(size),
                    style: const TextStyle(
                      color: Color(0xFF5A6580),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          }),

          // Overflow label
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+$overflow more file${overflow == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Color(0xFF5A6580),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 2. Receiving — live progress ──────────────────────────────────────────────

class _ReceivingProgress extends StatelessWidget {
  final TransferProvider provider;
  const _ReceivingProgress({required this.provider});

  @override
  Widget build(BuildContext context) {
    final pct = (provider.progress * 100).toStringAsFixed(0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        const Text(
          '📥  Receiving...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          provider.currentFileName ?? '',
          style: const TextStyle(color: Color(0xFF5A6580), fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF141929),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      provider.currentFileName ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [Color(0xFF3D7BFF), Color(0xFF00E5C0)],
                    ).createShader(b),
                    child: Text(
                      '$pct%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: provider.progress,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF3D7BFF)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    provider.speedLabel,
                    style:
                        const TextStyle(color: Color(0xFF5A6580), fontSize: 11),
                  ),
                  Text(
                    '${provider.completedFiles.length} done',
                    style:
                        const TextStyle(color: Color(0xFF5A6580), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () {
            provider.reset();
            Navigator.pop(context);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.07)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'Cancel',
                style: TextStyle(
                    color: Color(0xFF5A6580), fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 3. Done ───────────────────────────────────────────────────────────────────

class _ReceiveDone extends StatelessWidget {
  final TransferProvider provider;
  const _ReceiveDone({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00E5C0).withOpacity(0.1),
            border: Border.all(color: const Color(0xFF00E5C0).withOpacity(0.4)),
          ),
          child: const Center(
            child: Text('✅', style: TextStyle(fontSize: 32)),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Files Received!',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${provider.completedFiles.length} file${provider.completedFiles.length == 1 ? '' : 's'} saved to Downloads/Dropix',
          style: const TextStyle(color: Color(0xFF5A6580), fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () {
            provider.reset();
            Navigator.pop(context);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5C0), Color(0xFF00B8A3)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'Done',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 4. Error ──────────────────────────────────────────────────────────────────

class _ReceiveError extends StatelessWidget {
  final TransferProvider provider;
  const _ReceiveError({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        const Text('❌', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 14),
        const Text(
          'Transfer Failed',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          provider.errorMessage ?? 'Unknown error',
          style: const TextStyle(color: Color(0xFF5A6580), fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () {
            provider.reset();
            Navigator.pop(context);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF141929),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: const Center(
              child: Text(
                'Dismiss',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: 0.3 + _ctrl.value * 0.7,
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF00E5C0),
          ),
        ),
      ),
    );
  }
}

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
