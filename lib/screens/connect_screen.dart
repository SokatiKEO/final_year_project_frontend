// lib/screens/connect_screen.dart
//
// Fallback connection screen with two options:
//  1. Show MY QR code (other device scans it to connect)
//  2. Scan another device's QR code
//  3. Manual IP input
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/discovered_device.dart';
import '../providers/discovery_provider.dart';
import 'send_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String? _myIp;
  bool _loadingIp = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _fetchMyIp();
  }

  Future<void> _fetchMyIp() async {
    final ip = await NetworkInfo().getWifiIP();
    setState(() {
      _myIp = ip ?? 'Not connected';
      _loadingIp = false;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceName =
        context.read<DiscoveryProvider>().localDeviceName ?? 'My Device';

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1422),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Connect Manually',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab bar ──────────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1422),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: const Color(0xFF3D7BFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF5A6580),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'My QR'),
                  Tab(text: 'Scan QR'),
                  Tab(text: 'Manual IP'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Tab views ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // Tab 1 — Show my QR
                  _MyQrTab(
                    ip: _myIp,
                    loading: _loadingIp,
                    deviceName: deviceName,
                  ),

                  // Tab 2 — Scan QR
                  _ScanQrTab(onDeviceFound: _navigateToSend),

                  // Tab 3 — Manual IP
                  _ManualIpTab(onConnect: _navigateToSend),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSend(DiscoveredDevice device) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SendScreen(device: device)),
    );
  }
}

// ── Tab 1: Show MY QR code ────────────────────────────────────────────────────

class _MyQrTab extends StatelessWidget {
  final String? ip;
  final bool loading;
  final String deviceName;

  const _MyQrTab({
    required this.ip,
    required this.loading,
    required this.deviceName,
  });

  String get _qrData => jsonEncode({
        'name': deviceName,
        'ip': ip ?? '',
        'port': 49152,
        'platform': 'android',
      });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Text(
            'Let another device scan this\nto connect to you',
            style: TextStyle(color: Color(0xFF5A6580), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // QR Code
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: loading
                ? const SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF3D7BFF),
                      ),
                    ),
                  )
                : QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF080C14),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF080C14),
                    ),
                  ),
          ),

          const SizedBox(height: 24),

          // IP info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1422),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              children: [
                const Text(
                  'Your IP Address',
                  style: TextStyle(color: Color(0xFF5A6580), fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  loading ? 'Loading...' : (ip ?? 'Not connected to WiFi'),
                  style: const TextStyle(
                    color: Color(0xFF3D7BFF),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Port: 49152',
                  style: TextStyle(color: Color(0xFF5A6580), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Scan QR code ───────────────────────────────────────────────────────

class _ScanQrTab extends StatefulWidget {
  final void Function(DiscoveredDevice) onDeviceFound;
  const _ScanQrTab({required this.onDeviceFound});

  @override
  State<_ScanQrTab> createState() => _ScanQrTabState();
}

class _ScanQrTabState extends State<_ScanQrTab> {
  bool _scanned = false;
  final MobileScannerController _scanner = MobileScannerController();

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;

    try {
      final data = jsonDecode(code) as Map<String, dynamic>;
      final device = DiscoveredDevice(
        id: 'manual-${data['ip']}',
        name: data['name'] ?? 'Unknown Device',
        platform: data['platform'] ?? 'unknown',
        host: data['ip'] as String,
        port: (data['port'] as num?)?.toInt() ?? 49152,
        discoveredAt: DateTime.now(),
      );
      _scanned = true;
      _scanner.stop();
      widget.onDeviceFound(device);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid QR code — not a Dropix device'),
          backgroundColor: Color(0xFFFF5C87),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Text(
            'Scan the QR code shown\non the other device',
            style: TextStyle(color: Color(0xFF5A6580), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Scanner view
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                  ),
                  // Scan overlay
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF3D7BFF),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Tab 3: Manual IP input ────────────────────────────────────────────────────

class _ManualIpTab extends StatefulWidget {
  final void Function(DiscoveredDevice) onConnect;
  const _ManualIpTab({required this.onConnect});

  @override
  State<_ManualIpTab> createState() => _ManualIpTabState();
}

class _ManualIpTabState extends State<_ManualIpTab> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '49152');
  final _nameController = TextEditingController(text: 'Remote Device');
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 49152;
    final name = _nameController.text.trim();

    if (ip.isEmpty) {
      setState(() => _error = 'Please enter an IP address');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    // Quick reachability check
    try {
      final socket =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      await socket.close();
    } catch (_) {
      setState(() {
        _connecting = false;
        _error =
            'Could not reach $ip:$port — check IP and make sure Dropix is open on the other device';
      });
      return;
    }

    final device = DiscoveredDevice(
      id: 'manual-$ip',
      name: name.isEmpty ? ip : name,
      platform: 'unknown',
      host: ip,
      port: port,
      discoveredAt: DateTime.now(),
    );

    setState(() => _connecting = false);
    widget.onConnect(device);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the IP address shown\non the other device\'s QR tab',
            style: TextStyle(color: Color(0xFF5A6580), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          _InputField(
            label: 'Device Name (optional)',
            controller: _nameController,
            hint: 'e.g. John\'s Phone',
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          _InputField(
            label: 'IP Address',
            controller: _ipController,
            hint: 'e.g. 192.168.1.5',
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          _InputField(
            label: 'Port',
            controller: _portController,
            hint: '49152',
            keyboardType: TextInputType.number,
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5C87).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF5C87).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF5C87),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          GestureDetector(
            onTap: _connecting ? null : _connect,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3D7BFF), Color(0xFF5B9BFF)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3D7BFF).withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: _connecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        '⚡ Connect',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Hint box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1422),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💡', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'On the other device, go to Connect → My QR tab to see their IP address.',
                    style: TextStyle(
                      color: Color(0xFF5A6580),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;

  const _InputField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF5A6580),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            filled: true,
            fillColor: const Color(0xFF0E1422),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.07)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.07)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3D7BFF)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}
