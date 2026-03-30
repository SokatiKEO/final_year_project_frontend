// lib/screens/relay_screen.dart
//
// Online Transfer — share files across different networks via relay.
//
// Flow:
//   1. Create a room (generates a code) OR join one (enter a code)
//   2. Both devices appear in the room
//   3. Either device can tap the other to send files

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../providers/discovery_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/transfer_service.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

// ── Config ─────────────────────────────────────────────────────────────────────
const _kBackendBase = 'https://web-production-04f9.up.railway.app';

// ══════════════════════════════════════════════════════════════════════════════
// Screen
// ══════════════════════════════════════════════════════════════════════════════

class RelayScreen extends StatefulWidget {
  const RelayScreen({super.key});

  @override
  State<RelayScreen> createState() => _RelayScreenState();
}

enum _Phase { idle, registering, inRoom }

class _RelayScreenState extends State<RelayScreen> {
  _Phase _phase = _Phase.idle;
  String? _roomCode;
  String? _error;
  List<_RelayDevice> _peers = [];
  bool _polling = false;
  bool _connecting = false;
  final _seenSessionIds = <String>{};
  final _selectedPeerIds = <String>{};

  final _codeController = TextEditingController();

  String get _deviceId => _localDeviceId();
  String get _deviceName =>
      context.read<DiscoveryProvider>().localDeviceName ?? 'My Device';

  // ── Room entry ────────────────────────────────────────────────────────────

  Future<void> _createRoom() async {
    await _joinRoomWithCode(_generateCode(), isNew: true);
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Room code must be 6 characters');
      return;
    }

    // Check the room has at least one active member before joining
    setState(() {
      _phase = _Phase.registering;
      _error = null;
    });
    try {
      final checkRes = await http.get(
        Uri.parse('$_kBackendBase/discovery/devices/$code'),
      );
      if (checkRes.statusCode == 200) {
        final members = jsonDecode(checkRes.body) as List;
        if (members.isEmpty) {
          setState(() {
            _phase = _Phase.idle;
            _error = 'Room doesn\'t exist. Check the code and try again.';
          });
          return;
        }
      }
    } catch (_) {
      setState(() {
        _phase = _Phase.idle;
        _error = 'Could not reach the relay server. Check your connection.';
      });
      return;
    }

    await _joinRoomWithCode(code, isNew: false);
  }

  Future<void> _joinRoomWithCode(String code, {required bool isNew}) async {
    setState(() {
      _phase = _Phase.registering;
      _error = null;
      _roomCode = code;
    });

    try {
      final res = await http.post(
        Uri.parse('$_kBackendBase/discovery/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room_code': code,
          'device_id': _deviceId,
          'device_name': _deviceName,
          'platform': _platformString(),
        }),
      );
      if (res.statusCode != 200)
        throw Exception('Server error ${res.statusCode}');

      setState(() => _phase = _Phase.inRoom);
      _startPolling();
    } catch (e) {
      setState(() {
        _phase = _Phase.idle;
        _roomCode = null;
        _error = isNew
            ? 'Could not reach the relay server. Check your connection.'
            : 'Could not join room. Check the code and your connection.';
      });
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    if (_polling) return;
    _polling = true;
    _poll();
  }

  Future<void> _poll() async {
    while (_polling && mounted && _phase == _Phase.inRoom) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _phase != _Phase.inRoom) break;
      try {
        final res = await http.get(Uri.parse(
          '$_kBackendBase/discovery/devices/$_roomCode'
          '?exclude_id=${Uri.encodeComponent(_deviceId)}',
        ));
        if (res.statusCode == 200 && mounted) {
          final list = (jsonDecode(res.body) as List)
              .map((e) => _RelayDevice.fromJson(e))
              .toList();
          setState(() => _peers = list);
          // Auto-receive: connect immediately when sender publishes a session
          for (final peer in list) {
            final sid = peer.relaySessionForMe;
            if (sid != null && !_seenSessionIds.contains(sid)) {
              _receiveFromPeer(peer);
              break;
            }
          }
        }
      } catch (_) {}
    }
  }

  void _stopPolling() => _polling = false;

  Future<void> _refresh() async {
    if (_phase != _Phase.inRoom) return;
    try {
      final res = await http.get(Uri.parse(
        '$_kBackendBase/discovery/devices/$_roomCode'
        '?exclude_id=${Uri.encodeComponent(_deviceId)}',
      ));
      if (res.statusCode == 200 && mounted) {
        final list = (jsonDecode(res.body) as List)
            .map((e) => _RelayDevice.fromJson(e))
            .toList();
        setState(() => _peers = list);
        for (final peer in list) {
          final sid = peer.relaySessionForMe;
          if (sid != null && !_seenSessionIds.contains(sid)) {
            _receiveFromPeer(peer);
            break;
          }
        }
      }
    } catch (_) {}
  }

  // ── Send to peer ──────────────────────────────────────────────────────────

  void _togglePeerSelection(_RelayDevice peer) {
    setState(() {
      if (_selectedPeerIds.contains(peer.deviceId)) {
        _selectedPeerIds.remove(peer.deviceId);
      } else {
        _selectedPeerIds.add(peer.deviceId);
      }
    });
  }

  Future<void> _sendToSelected() async {
    if (_connecting || _selectedPeerIds.isEmpty) return;
    final targets = _peers
        .where((p) =>
            _selectedPeerIds.contains(p.deviceId) &&
            p.relaySessionForMe == null)
        .toList();
    if (targets.isEmpty) return;

    setState(() => _connecting = true);

    // Create one relay session per target in parallel
    final devices = <DiscoveredDevice>[];
    await Future.wait(targets.map((peer) async {
      try {
        final res = await http.post(
          Uri.parse('$_kBackendBase/relay/session'),
          headers: {'Content-Type': 'application/json'},
        );
        if (res.statusCode != 200) throw Exception('Server error');
        final sessionId = (jsonDecode(res.body)
            as Map<String, dynamic>)['session_id'] as String;
        print('[Dropix] 🔗 Relay session for ${peer.deviceName}: $sessionId');
        devices.add(DiscoveredDevice(
          id: peer.deviceId,
          name: peer.deviceName,
          platform: peer.platform,
          host: _kBackendBase,
          port: 0,
          discoveredAt: DateTime.now(),
          relaySessionId: sessionId,
        ));
      } catch (_) {}
    }));

    if (devices.isEmpty) {
      if (mounted)
        setState(() {
          _connecting = false;
          _error = 'Could not create relay sessions. Try again.';
        });
      return;
    }

    // Publish relay_sessions map: each target device_id -> their session_id
    final sessionsMap = {
      for (final d in devices) d.id: d.relaySessionId!,
    };
    try {
      await http.post(
        Uri.parse('$_kBackendBase/discovery/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room_code': _roomCode,
          'device_id': _deviceId,
          'device_name': _deviceName,
          'platform': _platformString(),
          'relay_sessions': sessionsMap,
        }),
      );
    } catch (_) {}

    if (!mounted) return;
    _stopPolling();
    setState(() {
      _connecting = false;
      _selectedPeerIds.clear();
    });

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SendScreen(devices: devices)),
    );

    // Resumed — clear published session and restart polling
    if (mounted && _phase == _Phase.inRoom) {
      try {
        await http.post(
          Uri.parse('$_kBackendBase/discovery/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'room_code': _roomCode,
            'device_id': _deviceId,
            'device_name': _deviceName,
            'platform': _platformString(),
            'relay_sessions': null,
          }),
        );
      } catch (_) {}
      _startPolling();
    }
  }

  // ── Receive from peer ─────────────────────────────────────────────────────

  Future<void> _receiveFromPeer(_RelayDevice peer) async {
    final sessionId = peer.relaySessionForMe!;
    // Guard: if already handling this session (e.g. manual tap after auto-trigger), bail
    if (!_seenSessionIds.add(sessionId)) return;
    _stopPolling();
    // Reset provider so a stale 'done' or 'error' phase doesn't swallow TransferStarted
    if (mounted) context.read<TransferProvider>().reset();
    // Show sheet immediately so user knows something is happening
    if (mounted) {
      context.read<TransferProvider>().setWaitingForRelay(true);
      ReceiveSheet.show(context);
    }

    final wsBase = _kBackendBase
        .replaceFirst(RegExp(r'^https://'), 'wss://')
        .replaceFirst(RegExp(r'^http://'), 'ws://');

    try {
      final ws = await WebSocket.connect(
        '$wsBase/relay/ws/$sessionId/receiver',
        // Keep the connection alive while waiting for the sender to start
      );
      ws.pingInterval = const Duration(seconds: 20);
      print('[Dropix] 📥 Relay WS connected as receiver');

      final toService = StreamController<Uint8List>();
      final fromService = StreamController<Uint8List>();

      // Forward ACKs from the service back to the sender via the WebSocket.
      // Without this, the sender never receives accept/file-ACK bytes and stalls.
      fromService.stream.listen(
        (ack) {
          print('[RECEIVER] sending ACK (${ack.length} bytes) to relay');
          ws.add(ack);
        },
        onDone: () => print('[RECEIVER] ACK stream done'),
        onError: (e) => print('[RECEIVER] ACK stream error: $e'),
      );

      // Track close code so we can show a meaningful error
      int? wsCloseCode;
      ws.listen(
        (data) {
          if (data is Uint8List) {
            print('[RECEIVER] got ${data.length} bytes');
            toService.add(data);
          } else if (data is List<int>) {
            print('[RECEIVER] got ${data.length} bytes (List<int>)');
            toService.add(Uint8List.fromList(data));
          }
        },
        onDone: () {
          print('[RECEIVER] WS closed by sender');
          // DO NOT close toService immediately here; let receiveViaRelay finish
          toService.close();
        },
        onError: (e) {
          print('[RECEIVER] WS error: $e');
          toService.addError(e);
        },
        cancelOnError: false,
      );

      await TransferService().receiveViaRelay(
        incoming: toService.stream,
        outgoing: fromService,
      );

      if (mounted) {
        context.read<TransferProvider>().setWaitingForRelay(false);
        _startPolling();
      }
    } catch (e) {
      print('[Dropix] ❌ Relay receiver error: $e');
      if (mounted) {
        // Clear the waiting state
        context.read<TransferProvider>().setWaitingForRelay(false);
        setState(() {
          _error =
              'Sender did not connect in time. Ask them to tap Send again.';
        });
        _seenSessionIds.clear(); // Allow retrying with a new session
        _startPolling();
      }
    }
  }

  // ── Leave room ────────────────────────────────────────────────────────────

  Future<void> _leaveRoom() async {
    _stopPolling();
    final code = _roomCode;
    final id = _deviceId;
    setState(() {
      _phase = _Phase.idle;
      _roomCode = null;
      _peers = [];
      _error = null;
    });
    _codeController.clear();
    if (code == null) return;
    try {
      await http
          .delete(Uri.parse('$_kBackendBase/discovery/leave/$code/$id'))
          .timeout(const Duration(seconds: 4));
      print('[Dropix] 👋 Left room $code');
    } catch (_) {}
  }

  Future<bool> _confirmLeave() async {
    if (_phase != _Phase.inRoom) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1422),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Leave room?',
          style: TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'You\'re currently in a room. Leaving will remove you and the other device won\'t be able to find you.',
          style: TextStyle(color: Color(0xFF5A6580), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay',
                style: TextStyle(
                    color: Color(0xFF3D7BFF), fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(
                    color: Color(0xFFFF5C87), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TransferProvider>();
      provider.onIncomingRequest = () {
        if (mounted) ReceiveSheet.show(context);
      };
    });
  }

  @override
  void dispose() {
    _stopPolling();
    _codeController.dispose();
    final code = _roomCode;
    final id = _deviceId;
    if (code != null) {
      http
          .delete(Uri.parse('$_kBackendBase/discovery/leave/$code/$id'))
          .timeout(const Duration(seconds: 4))
          .ignore();
    }
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final should = await _confirmLeave();
        if (!should || !context.mounted) return;
        await _leaveRoom();
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF080C14),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: switch (_phase) {
                  _Phase.idle => _buildIdle(),
                  _Phase.registering => _buildSpinner(),
                  _Phase.inRoom => _buildInRoom(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final should = await _confirmLeave();
              if (!should || !context.mounted) return;
              await _leaveRoom();
              if (context.mounted) Navigator.pop(context);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0E1422),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 15),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Online Relay Connect',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          // Room code badge (tap to copy)
          if (_phase == _Phase.inRoom && _roomCode != null)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _roomCode!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Room code copied!'),
                    backgroundColor: Color(0xFF3D7BFF),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D7BFF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF3D7BFF).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _roomCode!,
                      style: const TextStyle(
                        color: Color(0xFF3D7BFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.copy_rounded,
                        color: Color(0xFF3D7BFF), size: 12),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Idle ──────────────────────────────────────────────────────────────────

  Widget _buildIdle() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 20),
          ],

          // Create room card
          // Create room card (same style as Join)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1422),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF3D7BFF).withOpacity(0.1),
                        border: Border.all(
                            color: const Color(0xFF3D7BFF).withOpacity(0.2)),
                      ),
                      child: const Center(
                        child: Text('🌐', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create a room',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text('Generate a 6-letter code and share it',
                            style: TextStyle(
                                color: Color(0xFF5A6580), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _createRoom,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3D7BFF), Color(0xFF5B9BFF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3D7BFF).withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('Generate Code',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Divider
          Row(
            children: [
              Expanded(
                  child: Divider(
                      color: Colors.white.withOpacity(0.07), thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('or',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.2), fontSize: 16)),
              ),
              Expanded(
                  child: Divider(
                      color: Colors.white.withOpacity(0.07), thickness: 1)),
            ],
          ),

          const SizedBox(height: 16),

          // Join room card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1422),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00E5C0).withOpacity(0.1),
                        border: Border.all(
                            color: const Color(0xFF00E5C0).withOpacity(0.2)),
                      ),
                      child: const Center(
                          child: Text('🔑', style: TextStyle(fontSize: 20))),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Join a room',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text('Enter the code from the other device',
                            style: TextStyle(
                                color: Color(0xFF5A6580), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '······',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.15),
                      fontSize: 28,
                      letterSpacing: 8,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF080C14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.07)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.07)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: Color(0xFF00E5C0), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _joinRoom,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5C0), Color(0xFF00B8A3)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5C0).withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('✓  Join Room',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
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

  // ── Spinner ───────────────────────────────────────────────────────────────

  Widget _buildSpinner() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF3D7BFF), strokeWidth: 2),
          SizedBox(height: 16),
          Text('Joining room...',
              style: TextStyle(color: Color(0xFF5A6580), fontSize: 13)),
        ],
      ),
    );
  }

  // ── In room ───────────────────────────────────────────────────────────────

  Widget _buildInRoom() {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF3D7BFF),
      backgroundColor: const Color(0xFF0E1422),
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],

          // Status banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF3D7BFF).withOpacity(0.07),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: const Color(0xFF3D7BFF).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('You\'re in the room',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(
                        _peers.isEmpty
                            ? 'Waiting for others to join...'
                            : _selectedPeerIds.isEmpty
                                ? 'Tap devices to select, then tap Send'
                                : '${_selectedPeerIds.length} of ${_peers.length} selected',
                        style: const TextStyle(
                            color: Color(0xFF5A6580), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Color(0xFF3D7BFF), strokeWidth: 2),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_peers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0E1422),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.07)),
                      ),
                      child: const Center(
                          child: Text('🔍', style: TextStyle(fontSize: 28))),
                    ),
                    const SizedBox(height: 16),
                    const Text('No devices yet',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      'Share your room code with the other\ndevice so they can join.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF5A6580), fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            const Text(
              'DEVICES IN ROOM',
              style: TextStyle(
                color: Color(0xFF5A6580),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ..._peers.map((peer) => _buildPeerCard(peer)),
          ],

          const SizedBox(height: 24),

          // Send button — shown when devices are selected
          if (_selectedPeerIds.isNotEmpty) ...[
            GestureDetector(
              onTap: _connecting ? null : _sendToSelected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3D7BFF), Color(0xFF5B9BFF)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3D7BFF).withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          '⚡  Send to ${_selectedPeerIds.length} device${_selectedPeerIds.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          GestureDetector(
            onTap: () async {
              final should = await _confirmLeave();
              if (should) await _leaveRoom();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.07)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text('Leave Room',
                    style: TextStyle(
                        color: Color(0xFF5A6580), fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildPeerCard(_RelayDevice peer) {
    final hasPendingSession = peer.relaySessionForMe != null;
    final isSelected = _selectedPeerIds.contains(peer.deviceId);

    return GestureDetector(
      onTap: hasPendingSession
          ? () => _receiveFromPeer(peer)
          : () => _togglePeerSelection(peer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3D7BFF).withOpacity(0.08)
              : const Color(0xFF0E1422),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasPendingSession
                ? const Color(0xFF00E5C0).withOpacity(0.3)
                : isSelected
                    ? const Color(0xFF3D7BFF).withOpacity(0.5)
                    : Colors.white.withOpacity(0.07),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Checkbox (only for sendable peers, only while in selection mode)
            if (!hasPendingSession && _selectedPeerIds.isNotEmpty) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isSelected ? const Color(0xFF3D7BFF) : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3D7BFF)
                        : Colors.white.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 13)
                    : null,
              ),
              const SizedBox(width: 10),
            ],
            // Device icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: hasPendingSession
                      ? [
                          const Color(0xFF00E5C0).withOpacity(0.2),
                          const Color(0xFF00E5C0).withOpacity(0.05),
                        ]
                      : isSelected
                          ? [
                              const Color(0xFF3D7BFF).withOpacity(0.25),
                              const Color(0xFF3D7BFF).withOpacity(0.08),
                            ]
                          : [
                              const Color(0xFF3D7BFF).withOpacity(0.15),
                              const Color(0xFF3D7BFF).withOpacity(0.04),
                            ],
                ),
              ),
              child: Center(
                child: Icon(
                  peer.platform == 'android' || peer.platform == 'ios'
                      ? Icons.smartphone
                      : Icons.laptop,
                  color: hasPendingSession
                      ? const Color(0xFF00E5C0)
                      : const Color(0xFF3D7BFF),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer.deviceName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(peer.platform,
                      style: const TextStyle(
                          color: Color(0xFF5A6580), fontSize: 11)),
                ],
              ),
            ),
            if (hasPendingSession)
              _ActionChip(
                label: '📥 Receive',
                color: const Color(0xFF00E5C0),
                loading: false,
                onTap: () => _receiveFromPeer(peer),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ══════════════════════════════════════════════════════════════════════════════

class _ActionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final List<Color> buttonColors;
  final Color buttonGlow;
  final VoidCallback onTap;

  const _ActionCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.buttonColors,
    required this.buttonGlow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1422),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: buttonColors.first.withOpacity(0.1),
                  border:
                      Border.all(color: buttonColors.first.withOpacity(0.2)),
                ),
              ),
              Text(emoji, style: const TextStyle(fontSize: 30)),
            ],
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  color: Color(0xFF5A6580), fontSize: 12, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: buttonColors),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: buttonGlow.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Text(buttonLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(color: color, strokeWidth: 2))
            : Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C87).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF5C87).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Color(0xFFFF5C87), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Models + helpers
// ══════════════════════════════════════════════════════════════════════════════

class _RelayDevice {
  final String deviceId;
  final String deviceName;
  final String platform;
  // Session ID that this device's sender has allocated specifically for us
  final String? relaySessionForMe;

  const _RelayDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    this.relaySessionForMe,
  });

  factory _RelayDevice.fromJson(Map<String, dynamic> j) => _RelayDevice(
        deviceId: j['device_id'] as String,
        deviceName: j['device_name'] as String,
        platform: j['platform'] as String,
        relaySessionForMe: j['relay_session_for_me'] as String?,
      );
}

String _localDeviceId() => 'device-${Platform.localHostname.hashCode.abs()}';

String _platformString() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  return 'linux';
}

String _generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
}