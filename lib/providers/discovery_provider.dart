// lib/providers/discovery_provider.dart

import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/discovered_device.dart';
import '../services/discovery_service.dart';

enum DiscoveryState { idle, scanning, error }

class DiscoveryProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DiscoveryService _service = DiscoveryService();

  List<DiscoveredDevice> _devices = [];
  DiscoveryState _state = DiscoveryState.idle;
  String? _errorMessage;
  StreamSubscription<List<DiscoveredDevice>>? _subscription;

  List<DiscoveredDevice> get devices => _devices;
  DiscoveryState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isScanning => _state == DiscoveryState.scanning;
  String? get localDeviceName => _service.localDeviceName;

  DiscoveryProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        print('[Dropix] 📲 App resumed — restarting discovery');
        _restartAfterResume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        print('[Dropix] 💤 App paused — stopping discovery');
        _service.stop();
        break;
      default:
        break;
    }
  }

  Future<void> _restartAfterResume() async {
    _state = DiscoveryState.scanning;
    _errorMessage = null;
    notifyListeners();
    try {
      await _service.restart();
    } catch (e) {
      _state = DiscoveryState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> startScanning() async {
    if (_state == DiscoveryState.scanning) return;

    _state = DiscoveryState.scanning;
    _errorMessage = null;
    notifyListeners();

    // Subscribe to device stream first
    _subscription ??= _service.devicesStream.listen(
      (devices) {
        _devices = devices;
        notifyListeners();
      },
      onError: (e) {
        _errorMessage = e.toString();
        _state = DiscoveryState.error;
        notifyListeners();
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 800));
      await _service.start();
    } catch (e) {
      _state = DiscoveryState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopScanning() async {
    await _subscription?.cancel();
    _subscription = null;
    await _service.stop();
    _devices = [];
    _state = DiscoveryState.idle;
    notifyListeners();
  }

  Future<void> refresh() async {
    _state = DiscoveryState.scanning;
    _devices = [];
    notifyListeners();
    await _service.restart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _service.dispose();
    super.dispose();
  }
}