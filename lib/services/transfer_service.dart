// lib/services/transfer_service.dart
//
// Handles file transfer between two Dropix devices over a direct TCP socket.
//
// PROTOCOL (binary, sequential):
//
//  ┌─────────────────────────────────────────────────┐
//  │  HANDSHAKE  (sender → receiver)                  │
//  │  4 bytes  : magic number  0x44524F50 ("DROP")    │
//  │  1 byte   : protocol version (0x01)              │
//  │  4 bytes  : number of files (uint32 big-endian)  │
//  └─────────────────────────────────────────────────┘
//
//  For each file:
//  ┌─────────────────────────────────────────────────┐
//  │  FILE HEADER  (sender → receiver)               │
//  │  2 bytes  : filename length (uint16)            │
//  │  N bytes  : filename (UTF-8)                    │
//  │  8 bytes  : file size in bytes (uint64)         │
//  └─────────────────────────────────────────────────┘
//  ┌─────────────────────────────────────────────────┐
//  │  FILE DATA                                      │
//  │  Raw bytes, chunked at 64KB                     │
//  └─────────────────────────────────────────────────┘
//  ┌─────────────────────────────────────────────────┐
//  │  ACK  (receiver → sender after each file)       │
//  │  1 byte : 0x01 = OK, 0x00 = error              │
//  └─────────────────────────────────────────────────┘

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/transfer_file.dart';

// ── Constants ────────────────────────────────────────────────────────────────
const int kTransferPort = 49152;
const int _kChunkSize = 64 * 1024;       // 64 KB chunks
const List<int> _kMagic = [0x44, 0x52, 0x4F, 0x50]; // "DROP"
const int _kVersion = 0x01;

// ── Transfer event types ─────────────────────────────────────────────────────

abstract class TransferEvent {}

class TransferStarted extends TransferEvent {
  final String deviceName;
  final List<String> fileNames;
  TransferStarted({required this.deviceName, required this.fileNames});
}

class TransferProgress extends TransferEvent {
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSec;
  double get percent => totalBytes == 0 ? 0 : bytesTransferred / totalBytes;
  TransferProgress({
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.speedBytesPerSec,
  });
}

class TransferFileComplete extends TransferEvent {
  final String fileName;
  final String savedPath;
  TransferFileComplete({required this.fileName, required this.savedPath});
}

class TransferComplete extends TransferEvent {}

class TransferError extends TransferEvent {
  final String message;
  TransferError(this.message);
}

// ── Transfer Service ─────────────────────────────────────────────────────────

class TransferService {
  // Singleton
  static final TransferService _instance = TransferService._internal();
  factory TransferService() => _instance;
  TransferService._internal();

  ServerSocket? _server;
  bool _isListening = false;

  // Stream for incoming transfer events (receiver side)
  final _incomingController =
      StreamController<TransferEvent>.broadcast();
  Stream<TransferEvent> get incomingEvents => _incomingController.stream;

  bool get isListening => _isListening;

  // ── SERVER (Receiver) ─────────────────────────────────────────────────────

  /// Start TCP server to accept incoming files.
  /// Should be called once when the app starts.
  Future<void> startServer() async {
    if (_isListening) return;

    try {
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        kTransferPort,
        shared: true,
      );
      _isListening = true;
      print('[Dropix] 🖥️ Transfer server listening on port $kTransferPort');

      _server!.listen(
        _handleIncomingConnection,
        onError: (e) {
          print('[Dropix] ⚠️ Server error: $e');
          _incomingController.add(TransferError(e.toString()));
        },
      );
    } catch (e) {
      print('[Dropix] ❌ Failed to start server: $e');
    }
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    _isListening = false;
    print('[Dropix] 🔴 Transfer server stopped');
  }

  /// Handles a new TCP connection from a sender.
  Future<void> _handleIncomingConnection(Socket socket) async {
    print('[Dropix] 📥 Incoming connection from ${socket.remoteAddress.address}');

    try {
      final reader = _SocketReader(socket);

      // ── Read handshake ────────────────────────────────────────────────────
      final magic = await reader.readBytes(4);
      if (!_listEquals(magic, _kMagic)) {
        throw Exception('Invalid magic number — not a Dropix client');
      }

      final version = (await reader.readBytes(1))[0];
      if (version != _kVersion) {
        throw Exception('Unsupported protocol version: $version');
      }

      final fileCountBytes = await reader.readBytes(4);
      final fileCount = ByteData.sublistView(
        Uint8List.fromList(fileCountBytes),
      ).getUint32(0, Endian.big);

      print('[Dropix] 📦 Expecting $fileCount file(s)');
      _incomingController.add(TransferStarted(
        deviceName: socket.remoteAddress.address,
        fileNames: [],
      ));

      // ── Receive each file ─────────────────────────────────────────────────
      final saveDir = await _getSaveDirectory();

      for (int i = 0; i < fileCount; i++) {
        await _receiveFile(reader, socket, saveDir, i + 1, fileCount);
      }

      _incomingController.add(TransferComplete());
      print('[Dropix] ✅ All files received');
    } catch (e) {
      print('[Dropix] ❌ Receive error: $e');
      _incomingController.add(TransferError(e.toString()));
    } finally {
      await socket.close();
    }
  }

  Future<void> _receiveFile(
    _SocketReader reader,
    Socket socket,
    Directory saveDir,
    int fileIndex,
    int totalFiles,
  ) async {
    // Read filename length + filename
    final nameLenBytes = await reader.readBytes(2);
    final nameLen = ByteData.sublistView(Uint8List.fromList(nameLenBytes))
        .getUint16(0, Endian.big);
    final nameBytes = await reader.readBytes(nameLen);
    final fileName = utf8.decode(nameBytes);

    // Read file size (8 bytes uint64)
    final sizeBytes = await reader.readBytes(8);
    final fileSize = ByteData.sublistView(Uint8List.fromList(sizeBytes))
        .getUint64(0, Endian.big);

    print('[Dropix] 📄 Receiving "$fileName" ($fileSize bytes)');

    // Create output file (handle name conflicts)
    final outFile = _uniqueFile(saveDir, fileName);
    final sink = outFile.openWrite();

    int received = 0;
    final stopwatch = Stopwatch()..start();
    int lastSpeedBytes = 0;
    int lastSpeedTime = 0;

    while (received < fileSize) {
      final remaining = fileSize - received;
      final toRead = remaining < _kChunkSize ? remaining : _kChunkSize;
      final chunk = await reader.readBytes(toRead);
      sink.add(chunk);
      received += chunk.length;

      // Calculate speed every 500ms
      final now = stopwatch.elapsedMilliseconds;
      double speed = 0;
      if (now - lastSpeedTime >= 500) {
        speed = (received - lastSpeedBytes) / ((now - lastSpeedTime) / 1000);
        lastSpeedBytes = received;
        lastSpeedTime = now;
      }

      _incomingController.add(TransferProgress(
        fileName: fileName,
        bytesTransferred: received,
        totalBytes: fileSize,
        speedBytesPerSec: speed,
      ));
    }

    await sink.flush();
    await sink.close();

    // Send ACK back to sender
    socket.add([0x01]);
    await socket.flush();

    _incomingController.add(TransferFileComplete(
      fileName: fileName,
      savedPath: outFile.path,
    ));

    print('[Dropix] ✅ Saved "$fileName" to ${outFile.path}');
  }

  // ── CLIENT (Sender) ───────────────────────────────────────────────────────

  /// Send files to a remote device.
  ///
  /// Returns a stream of [TransferEvent]s for progress tracking.
  Stream<TransferEvent> sendFiles({
    required String host,
    required int port,
    required List<TransferFile> files,
  }) async* {
    Socket? socket;

    try {
      print('[Dropix] 📤 Connecting to $host:$port');
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
      print('[Dropix] 🔗 Connected to $host:$port');

      yield TransferStarted(
        deviceName: host,
        fileNames: files.map((f) => f.name).toList(),
      );

      // ── Send handshake ────────────────────────────────────────────────────
      final handshake = BytesBuilder();
      handshake.add(_kMagic);
      handshake.addByte(_kVersion);
      final countBytes = Uint8List(4);
      ByteData.sublistView(countBytes).setUint32(0, files.length, Endian.big);
      handshake.add(countBytes);
      socket.add(handshake.toBytes());
      await socket.flush();

      // ── Send each file ────────────────────────────────────────────────────
      for (final file in files) {
        yield* _sendFile(socket, file);
      }

      yield TransferComplete();
      print('[Dropix] ✅ All files sent');
    } catch (e) {
      print('[Dropix] ❌ Send error: $e');
      yield TransferError(e.toString());
    } finally {
      await socket?.close();
    }
  }

  Stream<TransferEvent> _sendFile(Socket socket, TransferFile file) async* {
    final ioFile = File(file.path);
    final fileSize = await ioFile.length();

    // ── File header ────────────────────────────────────────────────────────
    final nameBytes = utf8.encode(file.name);
    final header = BytesBuilder();

    // Filename length (2 bytes)
    final nameLenBuf = Uint8List(2);
    ByteData.sublistView(nameLenBuf).setUint16(0, nameBytes.length, Endian.big);
    header.add(nameLenBuf);

    // Filename
    header.add(nameBytes);

    // File size (8 bytes)
    final sizeBuf = Uint8List(8);
    ByteData.sublistView(sizeBuf).setUint64(0, fileSize, Endian.big);
    header.add(sizeBuf);

    socket.add(header.toBytes());
    await socket.flush();

    // ── File data ──────────────────────────────────────────────────────────
    final stream = ioFile.openRead();
    int sent = 0;
    final stopwatch = Stopwatch()..start();
    int lastSpeedBytes = 0;
    int lastSpeedTime = 0;

    await for (final chunk in stream) {
      socket.add(chunk);
      sent += chunk.length;

      final now = stopwatch.elapsedMilliseconds;
      double speed = 0;
      if (now - lastSpeedTime >= 500) {
        speed = (sent - lastSpeedBytes) / ((now - lastSpeedTime) / 1000);
        lastSpeedBytes = sent;
        lastSpeedTime = now;
      }

      yield TransferProgress(
        fileName: file.name,
        bytesTransferred: sent,
        totalBytes: fileSize,
        speedBytesPerSec: speed,
      );
    }

    await socket.flush();

    // Wait for ACK from receiver
    final ack = await socket.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('No ACK received'),
    );

    if (ack.isEmpty || ack[0] != 0x01) {
      throw Exception('Receiver rejected the file');
    }

    yield TransferFileComplete(
      fileName: file.name,
      savedPath: file.path,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Directory> _getSaveDirectory() async {
    Directory base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/Download/Dropix');
    } else if (Platform.isIOS) {
      base = await getApplicationDocumentsDirectory();
      base = Directory('${base.path}/Dropix');
    } else {
      base = await getDownloadsDirectory() ?? Directory('/tmp/Dropix');
    }
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

  /// Returns a File that doesn't already exist by appending (1), (2) etc.
  File _uniqueFile(Directory dir, String name) {
    final dot = name.lastIndexOf('.');
    final base = dot >= 0 ? name.substring(0, dot) : name;
    final ext = dot >= 0 ? name.substring(dot) : '';
    var file = File('${dir.path}/$name');
    int i = 1;
    while (file.existsSync()) {
      file = File('${dir.path}/$base ($i)$ext');
      i++;
    }
    return file;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void dispose() {
    stopServer();
    _incomingController.close();
  }
}

// ── Socket Reader helper ──────────────────────────────────────────────────────
// Buffers socket data and lets us read exact byte counts reliably.

class _SocketReader {
  final Socket _socket;
  final _buffer = <int>[];
  late StreamSubscription _sub;
  final _completer = Completer<void>();
  bool _done = false;

  _SocketReader(this._socket) {
    _sub = _socket.listen(
      (data) {
        _buffer.addAll(data);
        if (!_completer.isCompleted) _completer.complete();
      },
      onDone: () {
        _done = true;
        if (!_completer.isCompleted) _completer.complete();
      },
      onError: (e) {
        if (!_completer.isCompleted) _completer.completeError(e);
      },
    );
  }

  Future<List<int>> readBytes(int count) async {
    while (_buffer.length < count) {
      if (_done) throw Exception('Socket closed before $count bytes available');
      final c = Completer<void>();
      _sub.pause();
      _socket.listen(
        (data) {
          _buffer.addAll(data);
          if (!c.isCompleted) c.complete();
        },
        onDone: () {
          _done = true;
          if (!c.isCompleted) c.complete();
        },
        cancelOnError: false,
      );
      _sub.resume();
      await c.future;
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }
}
