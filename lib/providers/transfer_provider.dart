// lib/providers/transfer_provider.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/discovered_device.dart';
import '../models/transfer_file.dart';
import '../models/transfer_record.dart';
import '../services/background_service.dart';
import '../services/discovery_service.dart';
import '../services/history_service.dart';
import '../services/notification_service.dart';
import '../services/transfer_service.dart';

enum TransferPhase { idle, connecting, transferring, done, error }

// Progress state for a single device session
class DeviceTransferState {
  final DiscoveredDevice device;
  TransferPhase phase;
  String? currentFileName;
  double progress;
  double speedBytesPerSec;
  String? errorMessage;
  List<String> completedFiles;
  List<String> completedPaths;

  DeviceTransferState({
    required this.device,
    this.phase = TransferPhase.connecting,
    this.currentFileName,
    this.progress = 0,
    this.speedBytesPerSec = 0,
    this.errorMessage,
    List<String>? completedFiles,
    List<String>? completedPaths,
  })  : completedFiles = completedFiles ?? [],
        completedPaths = completedPaths ?? [];

  bool get isDone => phase == TransferPhase.done;
  bool get isError => phase == TransferPhase.error;
  bool get isActive =>
      phase == TransferPhase.connecting ||
      phase == TransferPhase.transferring;

  String get speedLabel {
    if (speedBytesPerSec < 1024)
      return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
    if (speedBytesPerSec < 1024 * 1024)
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

class TransferProvider extends ChangeNotifier {
  final TransferService _service = TransferService();
  final HistoryService _history = HistoryService();
  final BackgroundService _bg = BackgroundService();

  // ── Single-device legacy state (used by receive flow) ─────────────────────
  TransferPhase _phase = TransferPhase.idle;
  String? _currentFileName;
  double _progress = 0;
  double _speedBytesPerSec = 0;
  String? _errorMessage;
  List<String> _completedFiles = [];
  List<String> _completedPaths = [];

  // ── Multi-device send state ───────────────────────────────────────────────
  List<DeviceTransferState> _deviceStates = [];
  final List<StreamSubscription<TransferEvent>> _subs = [];

  List<DeviceTransferState> get deviceStates => _deviceStates;

  // Overall phase for multi-send: transferring if any active, done if all done/error
  TransferPhase get multiPhase {
    if (_deviceStates.isEmpty) return _phase;
    if (_deviceStates.any((s) => s.isActive)) return TransferPhase.transferring;
    if (_deviceStates.every((s) => s.isDone)) return TransferPhase.done;
    if (_deviceStates.every((s) => s.isDone || s.isError)) {
      // All settled: error if every device failed, done if at least one succeeded
      return _deviceStates.any((s) => s.isDone)
          ? TransferPhase.done
          : TransferPhase.error;
    }
    return TransferPhase.transferring;
  }

  int get completedDeviceCount => _deviceStates.where((s) => s.isDone).length;
  int get failedDeviceCount => _deviceStates.where((s) => s.isError).length;
  int get totalDeviceCount => _deviceStates.length;

  // ── Incoming state ────────────────────────────────────────────────────────
  bool _hasIncomingRequest = false;
  String? _incomingFromDevice;
  List<String> _incomingFileNames = [];
  List<int> _incomingFileSizes = [];
  bool _incomingAccepted = false;

  VoidCallback? _onIncomingRequest;
  bool _pendingIncomingRequest = false;
  bool _isWaitingForRelay = false;

  VoidCallback? get onIncomingRequest => _onIncomingRequest;
  set onIncomingRequest(VoidCallback? cb) {
    _onIncomingRequest = cb;
    if (cb != null && _pendingIncomingRequest) {
      _pendingIncomingRequest = false;
      Future.microtask(() => cb());
    }
  }

  TransferPhase get phase => _phase;
  bool get isTransferring => _phase == TransferPhase.transferring;
  bool get hasIncomingRequest => _hasIncomingRequest;
  bool get isWaitingForRelay => _isWaitingForRelay;
  String? get currentFileName => _currentFileName;
  double get progress => _progress;
  double get speedMBps => _speedBytesPerSec / (1024 * 1024);
  String? get errorMessage => _errorMessage;
  List<String> get completedFiles => _completedFiles;
  String? get incomingFromDevice => _incomingFromDevice;
  List<String> get incomingFileNames => _incomingFileNames;
  List<int> get incomingFileSizes => _incomingFileSizes;

  String get speedLabel {
    if (_speedBytesPerSec < 1024)
      return '${_speedBytesPerSec.toStringAsFixed(0)} B/s';
    if (_speedBytesPerSec < 1024 * 1024)
      return '${(_speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(_speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Future<void> initialize() async {
    await _service.startServer();
    await _bg.initialize();
    await _bg.requestPermissions();

    _service.incomingEvents.listen((event) {
      if (event is TransferStarted) {
        if (_phase == TransferPhase.transferring) return;
        _hasIncomingRequest = true;
        _isWaitingForRelay = false;
        _incomingAccepted = false;
        _incomingFromDevice = event.deviceName;
        _incomingFileNames = event.fileNames;
        _incomingFileSizes = event.fileSizes;
        _completedFiles = [];
        _completedPaths = [];
        _phase = TransferPhase.connecting;
        notifyListeners();

        // Notify the user that a device wants to send files
        final fileCount = event.fileNames.length;
        // fileWord unused
        NotificationService.showIncomingRequest(
          deviceName: event.deviceName,
          fileCount: fileCount,
        );

        if (_onIncomingRequest != null) {
          Future.microtask(() => _onIncomingRequest?.call());
        } else {
          _pendingIncomingRequest = true;
        }
      } else if (event is TransferProgress) {
        if (!_incomingAccepted) return;
        _phase = TransferPhase.transferring;
        _currentFileName = event.fileName;
        _progress = event.percent;
        _speedBytesPerSec = event.speedBytesPerSec;
        final pct = (event.percent * 100).toStringAsFixed(0);
        _bg.updateProgress('Receiving ${event.fileName} · $pct%');
        notifyListeners();
      } else if (event is TransferFileComplete) {
        _completedFiles.add(event.fileName);
        _completedPaths.add(event.savedPath);
        notifyListeners();
      } else if (event is TransferComplete) {
        _phase = TransferPhase.done;
        _hasIncomingRequest = false;
        _progress = 1.0;
        _bg.stopTransfer();
        NotificationService.showTransferComplete(
          fileCount: _completedFiles.length,
          deviceName: _incomingFromDevice ?? 'device',
          isSend: false,
        );
        _history.save(TransferRecord(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          direction: TransferDirection.received,
          deviceName: _incomingFromDevice ?? 'Unknown',
          fileNames: List.from(_completedFiles),
          fileSizes: List.from(_incomingFileSizes),
          filePaths: List.from(_completedPaths),
          completedAt: DateTime.now(),
          success: true,
          saveFolderPath: _service.saveDirectoryPath,
        ));
        notifyListeners();
      } else if (event is TransferError) {
        _phase = TransferPhase.error;
        _errorMessage = event.message;
        _hasIncomingRequest = false;
        _bg.stopTransfer();
        notifyListeners();
      }
    });
  }

  void setWaitingForRelay(bool value) {
    _isWaitingForRelay = value;
    if (value) _phase = TransferPhase.connecting;
    notifyListeners();
  }

  void acceptIncoming() {
    _incomingAccepted = true;
    _phase = TransferPhase.transferring;
    _service.acceptTransfer();
    _bg.startTransfer(
        'Receiving files from ${_incomingFromDevice ?? 'device'}…');
    notifyListeners();
  }

  void declineIncoming() {
    _hasIncomingRequest = false;
    _incomingAccepted = false;
    _incomingFromDevice = null;
    _incomingFileNames = [];
    _incomingFileSizes = [];
    _pendingIncomingRequest = false;
    _phase = TransferPhase.idle;
    _service.declineTransfer();
    notifyListeners();
  }

  /// Send files to one or more devices in parallel.
  Future<void> sendFiles({
    required List<DiscoveredDevice> devices,
    required List<TransferFile> files,
  }) async {
    // Cancel any previous send subscriptions
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();

    // Build per-device state objects
    _deviceStates = devices
        .map((d) => DeviceTransferState(device: d))
        .toList();

    _phase = TransferPhase.connecting;
    _progress = 0;
    _completedFiles = [];
    _completedPaths = [];
    _errorMessage = null;
    notifyListeners();

    final localName =
        DiscoveryService().localDeviceName ?? Platform.localHostname;

    await _bg.startTransfer(
      devices.length == 1
          ? 'Connecting to ${devices.first.name}…'
          : 'Sending to ${devices.length} devices…',
    );

    // Fan out — one stream subscription per device
    for (final state in _deviceStates) {
      final Stream<TransferEvent> stream;
      if (state.device.isRelay) {
        // Use WebSocket relay path
        stream = _service.sendFilesViaRelay(
          backendBase: state.device.host,
          sessionId: state.device.relaySessionId!,
          files: files,
          deviceName: localName,
          deviceId: DiscoveryService().localDeviceId,
        );
      } else {
        // Use direct LAN path
        stream = _service.sendFiles(
          host: state.device.host,
          port: state.device.port,
          files: files,
          deviceName: localName,
        );
      }

      final sub = stream.listen(
        (event) {
          _handleSendEvent(event, state, files);
        },
        onError: (e) {
          state.phase = TransferPhase.error;
          state.errorMessage = e.toString();
          notifyListeners();
          _checkAllDone(files);
        },
      );
      _subs.add(sub);
    }
  }

  void _handleSendEvent(
    TransferEvent event,
    DeviceTransferState state,
    List<TransferFile> files,
  ) {
    if (event is TransferProgress) {
      state.phase = TransferPhase.transferring;
      state.currentFileName = event.fileName;
      state.progress = event.percent;
      state.speedBytesPerSec = event.speedBytesPerSec;
      final pct = (event.percent * 100).toStringAsFixed(0);
      _bg.updateProgress('Sending to ${state.device.name} · $pct%');
    } else if (event is TransferFileComplete) {
      state.completedFiles.add(event.fileName);
      state.completedPaths.add(event.savedPath);
    } else if (event is TransferComplete) {
      state.phase = TransferPhase.done;
      state.progress = 1.0;
      NotificationService.showTransferComplete(
        fileCount: state.completedFiles.length,
        deviceName: state.device.name,
        isSend: true,
      );
      _history.save(TransferRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        direction: TransferDirection.sent,
        deviceName: state.device.name,
        fileNames: files.map((f) => f.name).toList(),
        fileSizes: files.map((f) => f.sizeBytes).toList(),
        filePaths: files.map((f) => f.path).toList(),
        completedAt: DateTime.now(),
        success: true,
      ));
      _checkAllDone(files);
    } else if (event is TransferError) {
      state.phase = TransferPhase.error;
      state.errorMessage = event.message;
      _checkAllDone(files);
    }
    notifyListeners();
  }

  void _checkAllDone(List<TransferFile> files) {
    final allSettled =
        _deviceStates.every((s) => s.isDone || s.isError);
    if (allSettled) {
      final anySuccess = _deviceStates.any((s) => s.isDone);
      _phase = anySuccess ? TransferPhase.done : TransferPhase.error;
      _bg.stopTransfer();
    }
    notifyListeners();
  }

  void reset() {
    _bg.stopTransfer();
    _phase = TransferPhase.idle;
    _progress = 0;
    _currentFileName = null;
    _speedBytesPerSec = 0;
    _errorMessage = null;
    _completedFiles = [];
    _completedPaths = [];
    _hasIncomingRequest = false;
    _incomingAccepted = false;
    _incomingFromDevice = null;
    _incomingFileNames = [];
    _incomingFileSizes = [];
    _pendingIncomingRequest = false;
    _isWaitingForRelay = false;
    _deviceStates = [];
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _service.dispose();
    super.dispose();
  }
}