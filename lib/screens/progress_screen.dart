// lib/screens/progress_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/transfer_provider.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  TransferPhase? _lastStablePhase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Consumer<TransferProvider>(
          builder: (context, provider, _) {
            final isMulti = provider.totalDeviceCount > 1;

            // Latch onto done/error
            if (provider.multiPhase == TransferPhase.done ||
                provider.multiPhase == TransferPhase.error) {
              _lastStablePhase = provider.multiPhase;
            }

            final displayPhase = _lastStablePhase ?? provider.multiPhase;

            if (displayPhase == TransferPhase.done) {
              return isMulti
                  ? _MultiDoneView(provider: provider)
                  : _DoneView(provider: provider);
            }
            if (displayPhase == TransferPhase.error && !isMulti) {
              return _ErrorView(provider: provider);
            }

            return isMulti
                ? _MultiTransferringView(provider: provider)
                : _SingleTransferringView(provider: provider);
          },
        ),
      ),
    );
  }
}

// ── Single device transferring ────────────────────────────────────────────────

class _SingleTransferringView extends StatefulWidget {
  final TransferProvider provider;
  const _SingleTransferringView({required this.provider});

  @override
  State<_SingleTransferringView> createState() =>
      _SingleTransferringViewState();
}

class _SingleTransferringViewState extends State<_SingleTransferringView>
    with SingleTickerProviderStateMixin {
  late AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final state = p.deviceStates.isNotEmpty ? p.deviceStates.first : null;
    final progress = state?.progress ?? p.progress;
    final fileName = state?.currentFileName ?? p.currentFileName ?? '';
    final speed = state?.speedLabel ?? p.speedLabel;
    final pct = (progress * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: _spin,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Color(0xFF3D7BFF),
                          Color(0xFF00E5C0),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0E1422),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: const Center(
                    child: Text('📦', style: TextStyle(fontSize: 34)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Transferring...',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            fileName,
            style: const TextStyle(color: Color(0xFF5A6580), fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1422),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
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
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.05),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF3D7BFF)),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCard(label: 'Speed', value: speed),
              const SizedBox(width: 10),
              _StatCard(label: 'Mode', value: 'WiFi'),
              const SizedBox(width: 10),
              _StatCard(label: 'Link', value: 'P2P'),
            ],
          ),
          const Spacer(),
          _CancelButton(),
        ],
      ),
    );
  }
}

// ── Multi device transferring ─────────────────────────────────────────────────

class _MultiTransferringView extends StatelessWidget {
  final TransferProvider provider;
  const _MultiTransferringView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final done = p.completedDeviceCount;
    final total = p.totalDeviceCount;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Header
          Row(
            children: [
              const Text('📡', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Broadcasting...',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$done of $total devices done',
                    style:
                        const TextStyle(color: Color(0xFF5A6580), fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Overall progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total > 0 ? done / total : 0,
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF3D7BFF)),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 24),

          // Per-device rows
          Expanded(
            child: ListView(
              children: p.deviceStates
                  .map((s) => _DeviceProgressRow(state: s))
                  .toList(),
            ),
          ),

          _CancelButton(),
        ],
      ),
    );
  }
}

class _DeviceProgressRow extends StatelessWidget {
  final DeviceTransferState state;
  const _DeviceProgressRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final String statusLabel;
    final Widget trailing;

    if (state.isDone) {
      statusColor = const Color(0xFF00E5C0);
      statusLabel = 'Done';
      trailing = const Icon(Icons.check_circle_rounded,
          color: Color(0xFF00E5C0), size: 20);
    } else if (state.isError) {
      statusColor = const Color(0xFFFF5C87);
      statusLabel = 'Failed';
      trailing =
          const Icon(Icons.error_rounded, color: Color(0xFFFF5C87), size: 20);
    } else if (state.phase == TransferPhase.transferring) {
      statusColor = const Color(0xFF3D7BFF);
      statusLabel = '${(state.progress * 100).toStringAsFixed(0)}%';
      trailing = SizedBox(
        width: 60,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: state.progress,
            backgroundColor: Colors.white.withOpacity(0.05),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF3D7BFF)),
            minHeight: 5,
          ),
        ),
      );
    } else {
      statusColor = const Color(0xFF5A6580);
      statusLabel = 'Connecting';
      trailing = const SizedBox(
        width: 16,
        height: 16,
        child:
            CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5A6580)),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1422),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: state.isDone
              ? const Color(0xFF00E5C0).withOpacity(0.25)
              : state.isError
                  ? const Color(0xFFFF5C87).withOpacity(0.25)
                  : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Icon(state.device.platformIcon, size: 20, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.device.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                if (state.phase == TransferPhase.transferring &&
                    state.currentFileName != null)
                  Text(
                    state.currentFileName!,
                    style:
                        const TextStyle(color: Color(0xFF5A6580), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (state.isError && state.errorMessage != null)
                  Text(
                    state.errorMessage!,
                    style:
                        const TextStyle(color: Color(0xFFFF5C87), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

// ── Single done ───────────────────────────────────────────────────────────────

class _DoneView extends StatelessWidget {
  final TransferProvider provider;
  const _DoneView({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E5C0).withOpacity(0.1),
              border:
                  Border.all(color: const Color(0xFF00E5C0).withOpacity(0.4)),
            ),
            child:
                const Center(child: Text('✅', style: TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 20),
          const Text('Transfer Complete!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            () {
              final count = provider.deviceStates.isNotEmpty
                  ? provider.deviceStates.first.completedFiles.length
                  : provider.completedFiles.length;
              return '$count file${count == 1 ? '' : 's'} sent successfully';
            }(),
            style: const TextStyle(color: Color(0xFF5A6580), fontSize: 14),
          ),
          const SizedBox(height: 32),
          _DoneButton(provider: provider),
        ],
      ),
    );
  }
}

// ── Multi done ────────────────────────────────────────────────────────────────

class _MultiDoneView extends StatelessWidget {
  final TransferProvider provider;
  const _MultiDoneView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final ok = provider.completedDeviceCount;
    final failed = provider.failedDeviceCount;
    final total = provider.totalDeviceCount;
    final allOk = failed == 0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            allOk ? '✅' : '⚠️',
            style: const TextStyle(fontSize: 56),
          ),
          const SizedBox(height: 20),
          Text(
            allOk ? 'All Transfers Complete!' : 'Partially Complete',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            allOk
                ? '$total device${total == 1 ? '' : 's'} received the files'
                : '$ok of $total succeeded · $failed failed',
            style: const TextStyle(color: Color(0xFF5A6580), fontSize: 14),
          ),
          const SizedBox(height: 32),
          // Summary list
          ...provider.deviceStates.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      s.isDone
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: s.isDone
                          ? const Color(0xFF00E5C0)
                          : const Color(0xFFFF5C87),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.device.name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    if (s.isError && s.errorMessage != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '· ${s.errorMessage}',
                          style: const TextStyle(
                              color: Color(0xFFFF5C87), fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              )),
          const SizedBox(height: 24),
          _DoneButton(provider: provider),
        ],
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final TransferProvider provider;
  const _ErrorView({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('❌', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 20),
          const Text('Transfer Failed',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            provider.errorMessage ?? 'Unknown error',
            style: const TextStyle(color: Color(0xFF5A6580), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () {
              provider.reset();
              Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1422),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Center(
                child: Text('Go Back',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _DoneButton extends StatelessWidget {
  final TransferProvider provider;
  const _DoneButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        provider.reset();
        // Navigator.popUntil(context, (r) => r.isFirst);
        Navigator.pop(context);
        Navigator.pop(context);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00E5C0), Color(0xFF00B8A3)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Done',
            style: TextStyle(
                color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.read<TransferProvider>().reset();
        Navigator.popUntil(context, (r) => r.isFirst);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.07)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text(
            'Cancel Transfer',
            style: TextStyle(
                color: Color(0xFF5A6580), fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1422),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Color(0xFF3D7BFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Color(0xFF5A6580), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
