// lib/services/discovery_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:nsd/nsd.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/discovered_device.dart';

const String _kServiceType = '_dropix._tcp';
const int _kListenPort = 49152;
const String _kDeviceIdKey = 'dropix_device_id';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  final Map<String, DiscoveredDevice> _devices = {};
  final _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  Discovery? _discovery;
  Registration? _registration;

  bool _isRunning = false;
  String? _localDeviceId;
  String? _localDeviceName;

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesController.stream;
  List<DiscoveredDevice> get devices => List.unmodifiable(_devices.values);
  bool get isRunning => _isRunning;
  String? get localDeviceId => _localDeviceId;
  String? get localDeviceName => _localDeviceName;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    await _resolveLocalIdentity();
    await _registerOurService();
    await _startDiscovery();
  }

  Future<void> stop() async {
    _isRunning = false;
    await _stopDiscovery();
    await _unregisterOurService();
    _clearDevices();
  }

  Future<void> restart() async {
    print('[Dropix] 🔄 Restarting discovery...');
    _isRunning = false;
    await _stopDiscovery();
    await _unregisterOurService();
    _clearDevices();
    await Future.delayed(const Duration(milliseconds: 800));
    await start();
  }

  void _clearDevices() {
    _devices.clear();
    _pushUpdate();
  }

  // ── Identity ───────────────────────────────────────────────────────────────

  Future<void> _resolveLocalIdentity() async {
    // Load persisted device ID, or generate and save a new one.
    // This ensures the same device ID is used across app restarts,
    // preventing duplicate rows in the devices table on the backend.
    if (_localDeviceId == null) {
      final prefs = await SharedPreferences.getInstance();
      String? storedId = prefs.getString(_kDeviceIdKey);
      if (storedId == null) {
        storedId = const Uuid().v4();
        await prefs.setString(_kDeviceIdKey, storedId);
        print('[Dropix] 🆔 Generated and saved new device ID: $storedId');
      } else {
        print('[Dropix] 🆔 Loaded persisted device ID: $storedId');
      }
      _localDeviceId = storedId;
    }

    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      _localDeviceName = android.model;
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      _localDeviceName = ios.name;
    } else if (Platform.isWindows) {
      final windows = await info.windowsInfo;
      _localDeviceName = windows.computerName;
    } else if (Platform.isMacOS) {
      final macos = await info.macOsInfo;
      _localDeviceName = macos.computerName;
    } else if (Platform.isLinux) {
      final linux = await info.linuxInfo;
      _localDeviceName = linux.prettyName;
    } else {
      _localDeviceName = 'Unknown Device';
    }
  }

  // ── mDNS ──────────────────────────────────────────────────────────────────

  Future<void> _registerOurService() async {
    final serviceName = '$_localDeviceId|$_localDeviceName';
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : Platform.isWindows
                ? 'windows'
                : Platform.isMacOS
                    ? 'macos'
                    : Platform.isLinux
                        ? 'linux'
                        : 'other';
    try {
      _registration = await register(
        Service(
          name: serviceName,
          type: _kServiceType,
          port: _kListenPort,
          txt: {
            'platform': Uint8List.fromList(utf8.encode(platform)),
            'v': Uint8List.fromList(utf8.encode('1')),
            'ip': Uint8List.fromList(utf8.encode(await _getLocalIp() ?? '')),
          },
        ),
      );
      print('[Dropix] Registered as "$_localDeviceName" on mDNS — advertising ip=${await _getLocalIp()}');
    } catch (e) {
      print('[Dropix] ⚠️ Failed to register mDNS service: $e');
    }
  }

  Future<void> _unregisterOurService() async {
    if (_registration != null) {
      try {
        await unregister(_registration!);
        print('[Dropix] 🔴 Unregistered from mDNS');
      } catch (e) {
        print('[Dropix] ⚠️ Failed to unregister: $e');
      }
      _registration = null;
    }
  }

  Future<void> _startDiscovery() async {
    try {
      _discovery = await startDiscovery(_kServiceType);
      _discovery!.addServiceListener((service, status) async {
        if (status == ServiceStatus.found) {
          await _onServiceFound(service);
        } else if (status == ServiceStatus.lost) {
          _onServiceLost(service);
        }
      });
      print('[Dropix] 🔍 Discovery started for $_kServiceType');
    } catch (e) {
      print('[Dropix] ⚠️ Failed to start discovery: $e');
    }
  }

  Future<void> _stopDiscovery() async {
    if (_discovery != null) {
      try {
        await stopDiscovery(_discovery!);
        print('[Dropix] 🔴 Discovery stopped');
      } catch (e) {
        print('[Dropix] ⚠️ Failed to stop discovery: $e');
      }
      _discovery = null;
    }
  }

  Future<void> _onServiceFound(Service service) async {
    final name = service.name ?? '';
    if (_localDeviceId != null && name.startsWith(_localDeviceId!)) return;

    final parts = name.split('|');
    final deviceId = parts.isNotEmpty ? parts[0] : name;
    final deviceName = parts.length > 1 ? parts[1] : name;

    final platformRaw = service.txt?['platform'];
    final platform = platformRaw != null ? utf8.decode(platformRaw) : 'unknown';

    // Prefer IP advertised in txt record — avoids broken .local DNS lookups
    final ipRaw = service.txt?['ip'];
    final txtIp = ipRaw != null ? utf8.decode(ipRaw) : null;
    final rawHost = service.host;
    print('[Dropix] 🔎 Resolving $deviceName — txt.ip=$txtIp, service.host=$rawHost, txt=${service.txt?.keys.toList()}');
    final host = (txtIp != null && txtIp.isNotEmpty)
        ? txtIp
        : (rawHost != null && rawHost.endsWith('.local'))
            ? await _resolveHost(service)
            : rawHost ?? await _resolveHost(service);
    final port = service.port ?? _kListenPort;

    if (host == null) {
      print('[Dropix] ⚠️ Could not resolve host for $deviceName');
      return;
    }

    if (_devices.containsKey(deviceId)) return;
    if (_devices.values.any((d) => d.host == host && d.port == port)) return;

    final device = DiscoveredDevice(
      id: deviceId,
      name: deviceName,
      platform: platform,
      host: host,
      port: port,
      discoveredAt: DateTime.now(),
    );

    _devices[deviceId] = device;
    _pushUpdate();
    print(
        '[Dropix] 📱 Found via mDNS: ${device.name} @ ${device.host}:${device.port}');
  }

  void _onServiceLost(Service service) {
    final name = service.name ?? '';
    final parts = name.split('|');
    final deviceId = parts.isNotEmpty ? parts[0] : name;
    if (_devices.remove(deviceId) != null) {
      _pushUpdate();
      print('[Dropix] 👋 Device lost: $deviceId');
    }
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        // Prefer Wi-Fi interfaces
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('wi-fi') || name.contains('en0') || name.contains('wlp')) {
          final addr = iface.addresses.firstOrNull;
          if (addr != null) return addr.address;
        }
      }
      // Fallback: first non-loopback IPv4
      for (final iface in interfaces) {
        final addr = iface.addresses
            .where((a) => !a.isLoopback)
            .firstOrNull;
        if (addr != null) return addr.address;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveHost(Service service) async {
    try {
      final hostname = service.host;
      if (hostname == null) return null;

      // If it's already an IP address, return it directly
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(hostname)) return hostname;

      // Resolve mDNS hostname to IP
      final addresses = await InternetAddress.lookup(hostname);
      final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4);
      if (ipv4.isNotEmpty) return ipv4.first.address;
      if (addresses.isNotEmpty) return addresses.first.address;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _pushUpdate() {
    if (!_devicesController.isClosed) {
      _devicesController.add(devices);
    }
  }

  void dispose() {
    stop();
    _devicesController.close();
  }
}