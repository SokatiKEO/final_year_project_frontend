// lib/screens/progress_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/transfer_provider.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Consumer<TransferProvider>(
          builder: (context, provider, _) {
            return switch (provider.phase) {
              TransferPhase.done    => _DoneView(provider: provider),
              TransferPhase.error   => _ErrorView(provider: provider),
              _                     => _TransferringView(provider: provider),
            };
          },
        ),
      ),
    );
  }
}

// ── Transferring ──────────────────────────────────────────────────────────────

class _TransferringView extends StatefulWidget {
  final TransferProvider provider;
  const _TransferringView({required this.provider});

  @override
  State<_TransferringView> createState() => _TransferringViewState();
}

class _TransferringViewState extends State<_TransferringView>
    with SingleTickerProviderStateMixin {
  late AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 2))
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
    final pct = (p.progress * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // ── Spinning animation ─────────────────────────────────────────────
          SizedBox(
            width: 130, height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: _spin,
                  child: Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.transparent,
                        width: 2,
                      ),
                      gradient: const SweepGradient(
                        colors: [Color(0xFF3D7BFF), Color(0xFF00E5C0), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 90, height: 90,
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
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            p.currentFileName ?? '',
            style: const TextStyle(color: Color(0xFF5A6580), fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 32),

          // ── Progress bar ───────────────────────────────────────────────────
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
                    Text(
                      p.currentFileName ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
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
                    value: p.progress,
                    backgroundColor: Colors.white.withOpacity(0.05),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF3D7BFF)),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Stats row ──────────────────────────────────────────────────────
          Row(
            children: [
              _StatCard(label: 'Speed', value: p.speedLabel),
              const SizedBox(width: 10),
              _StatCard(label: 'Mode', value: 'WiFi'),
              const SizedBox(width: 10),
              _StatCard(label: 'Link', value: 'P2P'),
            ],
          ),

          const Spacer(),

          // ── Cancel ─────────────────────────────────────────────────────────
          GestureDetector(
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
                  style: TextStyle(color: Color(0xFF5A6580), fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Done ──────────────────────────────────────────────────────────────────────

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
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E5C0).withOpacity(0.1),
              border: Border.all(color: const Color(0xFF00E5C0).withOpacity(0.4)),
            ),
            child: const Center(child: Text('✅', style: TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 20),
          const Text('Transfer Complete!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            '${provider.completedFiles.length} file${provider.completedFiles.length == 1 ? '' : 's'} sent successfully',
            style: const TextStyle(color: Color(0xFF5A6580), fontSize: 14),
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5C0), Color(0xFF00B8A3)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text(
                  'Done',
                  style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
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
          const Text('Transfer Failed', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
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
                child: Text('Go Back', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

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
            Text(value, style: const TextStyle(color: Color(0xFF3D7BFF), fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Color(0xFF5A6580), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
