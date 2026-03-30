// lib/screens/home_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../providers/discovery_provider.dart';
import '../providers/transfer_provider.dart';
import '../models/transfer_file.dart';
import 'receive_screen.dart';
import 'connect_screen.dart';
import 'send_screen.dart';
import 'history_screen.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _radarController;

  // Multi-select state
  final Set<String> _selectedDeviceIds = {};
  bool get _isSelecting => _selectedDeviceIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TransferProvider>();
      provider.onIncomingRequest = () {
        if (mounted) ReceiveSheet.show(context);
      };
      if (provider.hasIncomingRequest && mounted) {
        ReceiveSheet.show(context);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) context.read<DiscoveryProvider>().startScanning();
      });
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  void _toggleDevice(DiscoveredDevice device) {
    setState(() {
      if (_selectedDeviceIds.contains(device.id)) {
        _selectedDeviceIds.remove(device.id);
      } else {
        _selectedDeviceIds.add(device.id);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedDeviceIds.clear());
  }

  void _sendToSelected(List<DiscoveredDevice> allDevices) {
    final selected = allDevices
        .where((d) => _selectedDeviceIds.contains(d.id))
        .toList();
    if (selected.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendScreen(devices: selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Consumer<DiscoveryProvider>(
          builder: (context, provider, _) {
            return Stack(
              children: [
                RefreshIndicator(
                  onRefresh: provider.refresh,
                  color: const Color(0xFF3D7BFF),
                  backgroundColor: const Color(0xFF0E1422),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _AppBar(
                          deviceName: provider.localDeviceName ?? 'My Device',
                          isSelecting: _isSelecting,
                          selectedCount: _selectedDeviceIds.length,
                          onCancelSelection: _clearSelection,
                        ),
                      ),

                      SliverToBoxAdapter(
                        child: _RadarWidget(
                          controller: _radarController,
                          deviceCount: provider.devices.length,
                          isScanning: provider.isScanning,
                        ),
                      ),

                      if (provider.state == DiscoveryState.error)
                        SliverToBoxAdapter(
                          child: _ErrorBanner(message: provider.errorMessage),
                        ),

                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: 'Nearby Devices',
                          count: provider.devices.length,
                        ),
                      ),

                      provider.devices.isEmpty
                          ? SliverToBoxAdapter(
                              child:
                                  _EmptyState(isScanning: provider.isScanning),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final device = provider.devices[index];
                                  return _DeviceCard(
                                    device: device,
                                    isSelected: _selectedDeviceIds
                                        .contains(device.id),
                                    isSelecting: _isSelecting,
                                    onTap: () => _toggleDevice(device),
                                  );
                                },
                                childCount: provider.devices.length,
                              ),
                            ),

                      SliverToBoxAdapter(
                        child: SizedBox(
                            height: _isSelecting ? 100 : 24),
                      ),
                    ],
                  ),
                ),

                // ── Send to Selected FAB ──────────────────────────────────
                if (_isSelecting)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 24,
                    child: _SendSelectedBar(
                      selectedCount: _selectedDeviceIds.length,
                      onCancel: _clearSelection,
                      onSend: () => _sendToSelected(provider.devices),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final String deviceName;
  final bool isSelecting;
  final int selectedCount;
  final VoidCallback onCancelSelection;

  const _AppBar({
    required this.deviceName,
    required this.isSelecting,
    required this.selectedCount,
    required this.onCancelSelection,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF3D7BFF), Color(0xFF00E5C0)],
            ).createShader(bounds),
            child: const Text(
              'Dropix',
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          if (isSelecting)
            GestureDetector(
              onTap: onCancelSelection,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1422),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.close_rounded,
                        color: Color(0xFFFF5C87), size: 15),
                    SizedBox(width: 5),
                    Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFFFF5C87),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const HistoryScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1422),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.07)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.history_rounded,
                            color: Color(0xFF00E5C0), size: 15),
                        SizedBox(width: 5),
                        Text(
                          'History',
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
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ConnectScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1422),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isDesktop
                              ? Icons.lan_rounded
                              : Icons.qr_code_rounded,
                          color: const Color(0xFF3D7BFF),
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Connect',
                          style: TextStyle(
                            color: Color(0xFF3D7BFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3D7BFF), Color(0xFF00E5C0)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      deviceName.isNotEmpty
                          ? deviceName[0].toUpperCase()
                          : 'D',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Radar ─────────────────────────────────────────────────────────────────────

class _RadarWidget extends StatelessWidget {
  final AnimationController controller;
  final int deviceCount;
  final bool isScanning;

  const _RadarWidget({
    required this.controller,
    required this.deviceCount,
    required this.isScanning,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isScanning) ...[
                  for (int i = 0; i < 3; i++)
                    AnimatedBuilder(
                      animation: controller,
                      builder: (_, __) {
                        final progress = (controller.value + i * 0.33) % 1.0;
                        return Opacity(
                          opacity: (1.0 - progress).clamp(0, 1),
                          child: Container(
                            width: 80 + progress * 160,
                            height: 80 + progress * 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF3D7BFF),
                                width: 1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0E1422),
                    border: Border.all(
                      color: const Color(0xFF3D7BFF).withOpacity(0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3D7BFF).withOpacity(0.2),
                        blurRadius: 24,
                        spreadRadius: 4,
                      )
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.wifi_tethering_rounded,
                      size: 32,
                      color: Color(0xFF3D7BFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isScanning
                ? (deviceCount == 0
                    ? 'Scanning...'
                    : '$deviceCount device${deviceCount == 1 ? '' : 's'} nearby')
                : 'Tap to scan',
            style: const TextStyle(
              color: Color(0xFF5A6580),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF5A6580),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF3D7BFF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFF3D7BFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

// ── Device card ───────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.device,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF3D7BFF).withOpacity(0.12)
                : const Color(0xFF0E1422),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF3D7BFF).withOpacity(0.5)
                  : Colors.white.withOpacity(0.07),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Animated selection checkbox
              if (isSelecting)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFF3D7BFF)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF3D7BFF)
                            : const Color(0xFF5A6580),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white)
                        : null,
                  ),
                ),

              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF3D7BFF).withOpacity(0.15),
                      const Color(0xFF00E5C0).withOpacity(0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    device.platformIcon,
                    size: 22,
                    color: const Color(0xFF3D7BFF),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${device.platform} · ${device.host}:${device.port}',
                      style: const TextStyle(
                        color: Color(0xFF5A6580),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isSelecting)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5C0),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5C0).withOpacity(0.6),
                        blurRadius: 6,
                      )
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Send Selected Bar ─────────────────────────────────────────────────────────

class _SendSelectedBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _SendSelectedBar({
    required this.selectedCount,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1422),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF3D7BFF).withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3D7BFF).withOpacity(0.15),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF3D7BFF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '$selectedCount',
                style: const TextStyle(
                  color: Color(0xFF3D7BFF),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$selectedCount device${selectedCount == 1 ? '' : 's'} selected',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3D7BFF), Color(0xFF00C4FF)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3D7BFF).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.send_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Send',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  const _EmptyState({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.devices_rounded,
              size: 40, color: Color(0xFF3A4460)),
          const SizedBox(height: 14),
          Text(
            isScanning ? 'Looking for nearby devices...' : 'No devices found',
            style: const TextStyle(color: Color(0xFF5A6580), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Make sure both devices are on the\nsame WiFi network.',
            style: TextStyle(color: Color(0xFF3A4460), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String? message;
  const _ErrorBanner({this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C87).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFFF5C87).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF5C87), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? 'Discovery error. Pull to refresh.',
              style:
                  const TextStyle(color: Color(0xFFFF5C87), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}