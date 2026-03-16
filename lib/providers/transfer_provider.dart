// lib/providers/transfer_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/discovered_device.dart';
import '../models/transfer_file.dart';
import '../models/transfer_record.dart';
import '../services/background_service.dart';
import '../services/history_service.dart';
import '../services/notification_service.dart';
import '../services/transfer_service.dart';

enum TransferPhase { idle, connecting, transferring, done, error }

class TransferProvider extends ChangeNotifier {
  final TransferService _service = TransferService();
  final HistoryService _history = HistoryService();
  final BackgroundService _bg = BackgroundService();

  TransferPhase _phase = TransferPhase.idle;
  String? _currentFileName;
  double _progress = 0;
  double _speedBytesPerSec = 0;
  String? _errorMessage;
  List<String> _completedFiles = [];
  StreamSubscription<TransferEvent>? _sub;

  // Incoming state
  bool _hasIncomingRequest = false;
  String? _incomingFromDevice;
  List<String> _incomingFileNames = [];
  List<int> _incomingFileSizes = [];
  bool _incomingAccepted = false;

  // Callback — home screen listens to this to show the bottom sheet
  VoidCallback? _onIncomingRequest;
  bool _pendingIncomingRequest = false;

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
  String? get currentFileName => _currentFileName;
  double get progress => _progress;
  double get speedMBps => _speedBytesPerSec / (1024 * 1024);
  String? get errorMessage => _errorMessage;
  List<String> get completedFiles => _completedFiles;
  String? get incomingFromDevice => _incomingFromDevice;
  List<String> get incomingFileNames => _incomingFileNames;
  List<int> get incomingFileSizes => _incomingFileSizes;

  String get speedLabel {
    if (_speedBytesPerSec < 1024) return '${_speedBytesPerSec.toStringAsFixed(0)} B/s';
    if (_speedBytesPerSec < 1024 * 1024) return '${(_speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(_speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Future<void> initialize() async {
    await _service.startServer();
    await _bg.initialize();
    await _bg.requestPermissions();

    _service.incomingEvents.listen((event) {
      if (event is TransferStarted) {
        _hasIncomingRequest = true;
        _incomingAccepted = false;
        _incomingFromDevice = event.deviceName;
        _incomingFileNames = event.fileNames;
        _incomingFileSizes = event.fileSizes;
        _completedFiles = []; // ← reset from any previous transfer
        _phase = TransferPhase.connecting;
        notifyListeners();

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
        notifyListeners();

      } else if (event is TransferComplete) {
        _phase = TransferPhase.done;
        _hasIncomingRequest = false;
        _progress = 1.0;
        _bg.stopTransfer();
        // ── Notify user ───────────────────────────────────────────────────
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
          completedAt: DateTime.now(),
          success: true,
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

  /// User tapped Accept on the receive sheet
  void acceptIncoming() {
    _incomingAccepted = true;
    _phase = TransferPhase.transferring;
    _service.acceptTransfer();
    _bg.startTransfer('Receiving files from ${_incomingFromDevice ?? 'device'}…');
    notifyListeners();
  }

  /// User tapped Decline on the receive sheet
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

  Future<void> sendFiles({
    required DiscoveredDevice device,
    required List<TransferFile> files,
  }) async {
    _phase = TransferPhase.connecting;
    _progress = 0;
    _completedFiles = [];
    _errorMessage = null;
    notifyListeners();

    await _bg.startTransfer('Connecting to ${device.name}…');
    await _sub?.cancel();

    _sub = _service
        .sendFiles(host: device.host, port: device.port, files: files)
        .listen((event) {
      if (event is TransferProgress) {
        _phase = TransferPhase.transferring;
        _currentFileName = event.fileName;
        _progress = event.percent;
        _speedBytesPerSec = event.speedBytesPerSec;
        final pct = (event.percent * 100).toStringAsFixed(0);
        _bg.updateProgress('Sending ${event.fileName} · $pct%');
      } else if (event is TransferFileComplete) {
        _completedFiles.add(event.fileName);
      } else if (event is TransferComplete) {
        _phase = TransferPhase.done;
        _progress = 1.0;
        _bg.stopTransfer();
        // ── Notify user ───────────────────────────────────────────────────
        NotificationService.showTransferComplete(
          fileCount: _completedFiles.length,
          deviceName: device.name,
          isSend: true,
        );
        _history.save(TransferRecord(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          direction: TransferDirection.sent,
          deviceName: device.name,
          fileNames: files.map((f) => f.name).toList(),
          fileSizes: files.map((f) => f.sizeBytes).toList(),
          completedAt: DateTime.now(),
          success: true,
        ));
      } else if (event is TransferError) {
        _phase = TransferPhase.error;
        _errorMessage = event.message;
        _bg.stopTransfer();
      }
      notifyListeners();
    });
  }

  void reset() {
    _bg.stopTransfer();
    _phase = TransferPhase.idle;
    _progress = 0;
    _currentFileName = null;
    _speedBytesPerSec = 0;
    _errorMessage = null;
    _completedFiles = [];
    _hasIncomingRequest = false;
    _incomingAccepted = false;
    _incomingFromDevice = null;
    _incomingFileNames = [];
    _incomingFileSizes = [];
    _pendingIncomingRequest = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}