// lib/services/history_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/transfer_record.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static const _fileName = 'transfer_history.json';
  static const _maxRecords = 100;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<TransferRecord>> loadAll() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TransferRecord.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> save(TransferRecord record) async {
    final records = await loadAll();
    records.insert(0, record);
    // Keep only the most recent records
    final trimmed = records.take(_maxRecords).toList();
    final file = await _getFile();
    await file.writeAsString(jsonEncode(trimmed.map((r) => r.toJson()).toList()));
  }

  Future<void> deleteRecord(String id) async {
    final records = await loadAll();
    records.removeWhere((r) => r.id == id);
    final file = await _getFile();
    await file.writeAsString(jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  Future<void> clearAll() async {
    final file = await _getFile();
    if (await file.exists()) await file.delete();
  }
}
