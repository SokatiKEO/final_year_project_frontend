// lib/services/transfer_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const int kTransferPort = 49152;
const int _kChunkSize = 64 * 1024;
const List<int> _kMagic = [0x44, 0x52, 0x4F, 0x50];
const int _kVersion = 0x01;

// ── Events ────────────────────────────────────────────────────────────────────

abstract class TransferEvent {}

class TransferStarted extends TransferEvent {
  final String deviceName;
  final List<String> fileNames;
  final List<int> fileSizes;
  TransferStarted({
    required this.deviceName,
    required this.fileNames,
    required this.fileSizes,
  });
}

class TransferProgress extends TransferEvent {
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSec;
  double get percent =>
      totalBytes == 0 ? 0 : bytesTransferred / totalBytes;
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

// ── Service ───────────────────────────────────────────────────────────────────

class TransferService {
  static final TransferService _instance = TransferService._internal();
  factory TransferService() => _instance;
  TransferService._internal();

  ServerSocket? _server;
  bool _isListening = false;

  final _incomingController =
      StreamController<TransferEvent>.broadcast();
  Stream<TransferEvent> get incomingEvents => _incomingController.stream;
  bool get isListening => _isListening;

  Completer<bool>? _acceptCompleter;

  // ── SERVER ────────────────────────────────────────────────────────────────

  Future<void> startServer() async {
    if (_isListening) return;
    try {
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        kTransferPort,
        shared: true,
      );
      _isListening = true;
      print('[Dropix] 🖥️ Server listening on port $kTransferPort');
      _server!.listen(_handleIncomingConnection);
    } catch (e) {
      print('[Dropix] ❌ Failed to start server: $e');
    }
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    _isListening = false;
  }

  void acceptTransfer() => _acceptCompleter?.complete(true);
  void declineTransfer() => _acceptCompleter?.complete(false);

  Future<void> _handleIncomingConnection(Socket socket) async {
    print('[Dropix] 📥 Connection from ${socket.remoteAddress.address}');
    final reader = _SocketReader(socket);
    try {
      // Magic + version
      final magic = await reader.readBytes(4);
      if (!_listEquals(magic, _kMagic)) throw Exception('Not a Dropix client');
      final version = (await reader.readBytes(1))[0];
      if (version != _kVersion) throw Exception('Unsupported version');

      // File count
      final fileCount = _readUint32(await reader.readBytes(4));
      print('[Dropix] 📦 Expecting $fileCount file(s)');

      // Read all file names and sizes
      final fileNames = <String>[];
      final fileSizes = <int>[];
      for (int i = 0; i < fileCount; i++) {
        final nameLen = _readUint16(await reader.readBytes(2));
        final name = utf8.decode(await reader.readBytes(nameLen));
        final size = _readUint64(await reader.readBytes(8));
        fileNames.add(name);
        fileSizes.add(size);
        print('[Dropix] 📄 File $i: $name ($size bytes)');
      }

      // Notify UI and wait for user decision
      _acceptCompleter = Completer<bool>();
      _incomingController.add(TransferStarted(
        deviceName: socket.remoteAddress.address,
        fileNames: fileNames,
        fileSizes: fileSizes,
      ));

      final accepted = await _acceptCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );

      // Send decision to sender
      socket.add([accepted ? 0x01 : 0x00]);
      await socket.flush();
      print('[Dropix] ${accepted ? "✅ Accepted" : "❌ Declined"}');

      if (!accepted) {
        await socket.close();
        return;
      }

      // Receive file data
      final saveDir = await _getSaveDirectory();
      for (final fileName in fileNames) {
        await _receiveFileData(reader, socket, fileName, saveDir);
      }

      _incomingController.add(TransferComplete());
      print('[Dropix] ✅ All files received');
    } catch (e) {
      print('[Dropix] ❌ Receive error: $e');
      _incomingController.add(TransferError(e.toString()));
    } finally {
      reader.dispose();
      await socket.close();
      _acceptCompleter = null;
    }
  }

  Future<void> _receiveFileData(
    _SocketReader reader,
    Socket socket,
    String fileName,
    Directory saveDir,
  ) async {
    // Read file size
    final fileSize = _readUint64(await reader.readBytes(8));
    print('[Dropix] 📥 Receiving "$fileName" ($fileSize bytes)');

    final outFile = _uniqueFile(saveDir, fileName);
    final sink = outFile.openWrite();

    int received = 0;
    final sw = Stopwatch()..start();
    int lastBytes = 0;
    int lastTime = 0;

    while (received < fileSize) {
      final toRead =
          (fileSize - received) < _kChunkSize ? (fileSize - received) : _kChunkSize;
      final chunk = await reader.readBytes(toRead);
      sink.add(chunk);
      received += chunk.length;

      final now = sw.elapsedMilliseconds;
      double speed = 0;
      if (now - lastTime >= 500) {
        speed = (received - lastBytes) / ((now - lastTime) / 1000);
        lastBytes = received;
        lastTime = now;
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

    // ACK this file
    socket.add([0x01]);
    await socket.flush();

    _incomingController.add(TransferFileComplete(
      fileName: fileName,
      savedPath: outFile.path,
    ));
    print('[Dropix] ✅ Saved: ${outFile.path}');
  }

  // ── CLIENT ────────────────────────────────────────────────────────────────

  Stream<TransferEvent> sendFiles({
    required String host,
    required int port,
    required List<dynamic> files,
  }) async* {
    Socket? socket;
    _SocketReader? reader;

    try {
      print('[Dropix] 📤 Connecting to $host:$port');
      socket = await Socket.connect(
        host, port,
        timeout: const Duration(seconds: 10),
      );
      // Use a shared reader so ACK bytes aren't lost
      reader = _SocketReader(socket);

      print('[Dropix] 🔗 Connected');
      yield TransferStarted(
        deviceName: host,
        fileNames: files.map((f) => f.name as String).toList(),
        fileSizes: files.map((f) => (f as dynamic).sizeBytes as int).toList(),
      );

      // ── Send magic + version + file count ─────────────────────────────────
      final header = BytesBuilder();
      header.add(_kMagic);
      header.addByte(_kVersion);
      header.add(_uint32Bytes(files.length));
      socket.add(header.toBytes());

      // ── Send all file names + sizes ───────────────────────────────────────
      for (final file in files) {
        final nameBytes = utf8.encode(file.name as String);
        final fileSize = await File(file.path as String).length();
        final nameHeader = BytesBuilder();
        nameHeader.add(_uint16Bytes(nameBytes.length));
        nameHeader.add(nameBytes);
        nameHeader.add(_uint64Bytes(fileSize));
        socket.add(nameHeader.toBytes());
      }
      await socket.flush();
      print('[Dropix] 📋 Sent ${files.length} filename(s), waiting for accept...');

      // ── Wait for accept/decline via shared reader ─────────────────────────
      final ackBytes = await reader.readBytes(1).timeout(
        const Duration(seconds: 35),
        onTimeout: () => throw TimeoutException('No response from receiver'),
      );

      if (ackBytes[0] != 0x01) {
        yield TransferError('Receiver declined the transfer');
        return;
      }
      print('[Dropix] ✅ Accepted — streaming files');

      // ── Send each file ────────────────────────────────────────────────────
      for (final file in files) {
        yield* _sendFileData(socket, reader, file);
      }

      yield TransferComplete();
      print('[Dropix] ✅ All done');
    } catch (e) {
      print('[Dropix] ❌ Send error: $e');
      yield TransferError(e.toString());
    } finally {
      reader?.dispose();
      await socket?.close();
    }
  }

  Stream<TransferEvent> _sendFileData(
    Socket socket,
    _SocketReader reader,
    dynamic file,
  ) async* {
    final ioFile = File(file.path as String);
    final fileSize = await ioFile.length();
    final fileName = file.name as String;

    print('[Dropix] 📤 Sending "$fileName" ($fileSize bytes)');

    // Send file size
    socket.add(_uint64Bytes(fileSize));
    await socket.flush();

    // Stream file data
    int sent = 0;
    final sw = Stopwatch()..start();
    int lastBytes = 0;
    int lastTime = 0;

    await for (final chunk in ioFile.openRead()) {
      socket.add(chunk);
      sent += chunk.length;

      final now = sw.elapsedMilliseconds;
      double speed = 0;
      if (now - lastTime >= 500) {
        speed = (sent - lastBytes) / ((now - lastTime) / 1000);
        lastBytes = sent;
        lastTime = now;
      }

      yield TransferProgress(
        fileName: fileName,
        bytesTransferred: sent,
        totalBytes: fileSize,
        speedBytesPerSec: speed,
      );
    }
    await socket.flush();
    print('[Dropix] ✅ Sent "$fileName", waiting for ACK');

    // Wait for per-file ACK via shared reader (not socket.first!)
    final ack = await reader.readBytes(1).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('ACK timeout'),
    );

    if (ack[0] != 0x01) throw Exception('File rejected');

    yield TransferFileComplete(
      fileName: fileName,
      savedPath: file.path as String,
    );
    print('[Dropix] ✅ ACK received for "$fileName"');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _readUint16(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint16(0, Endian.big);
  int _readUint32(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.big);
  int _readUint64(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint64(0, Endian.big);

  Uint8List _uint16Bytes(int v) {
    final b = Uint8List(2);
    ByteData.sublistView(b).setUint16(0, v, Endian.big);
    return b;
  }

  Uint8List _uint32Bytes(int v) {
    final b = Uint8List(4);
    ByteData.sublistView(b).setUint32(0, v, Endian.big);
    return b;
  }

  Uint8List _uint64Bytes(int v) {
    final b = Uint8List(8);
    ByteData.sublistView(b).setUint64(0, v, Endian.big);
    return b;
  }

  Future<Directory> _getSaveDirectory() async {
    Directory base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/Download/Dropix');
    } else if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      base = Directory('${docs.path}/Dropix');
    } else {
      base = Directory('/tmp/Dropix');
    }
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

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

// ── Socket Reader ─────────────────────────────────────────────────────────────
// Buffers ALL incoming bytes from the socket into a single queue.
// This prevents bytes being lost when switching between reads.

class _SocketReader {
  final _buffer = <int>[];
  final _waiters = <Completer<void>>[];
  bool _done = false;
  late StreamSubscription _sub;

  _SocketReader(Socket socket) {
    _sub = socket.listen(
      (data) {
        _buffer.addAll(data);
        // Wake up anyone waiting for data
        for (final w in _waiters) {
          if (!w.isCompleted) w.complete();
        }
        _waiters.clear();
      },
      onDone: () {
        _done = true;
        for (final w in _waiters) {
          if (!w.isCompleted) w.complete();
        }
        _waiters.clear();
      },
      onError: (e) {
        _done = true;
        for (final w in _waiters) {
          if (!w.isCompleted) w.completeError(e);
        }
        _waiters.clear();
      },
    );
  }

  Future<List<int>> readBytes(int count) async {
    while (_buffer.length < count) {
      if (_done) throw Exception('Socket closed (need $count, have ${_buffer.length})');
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }

  void dispose() {
    _sub.cancel();
  }
}