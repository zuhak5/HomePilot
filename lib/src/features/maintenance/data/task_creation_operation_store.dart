// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/task_creation.dart';

class TaskCreationOperationStore {
  TaskCreationOperationStore({FlutterSecureStorage? storage})
      : _storage = storage;

  final FlutterSecureStorage? _storage;
  final Map<String, String> _inMemoryFallback = {};
  static const _keyPrefix = 'task_creation_op_v1_';

  String _storageKey(String operationId) => '$_keyPrefix$operationId';

  Future<void> saveOperation(TaskCreationOperation operation) async {
    final key = _storageKey(operation.operationId);
    final value = jsonEncode(operation.toJson());
    _inMemoryFallback[key] = value;
    final storage = _storage;
    if (storage != null) {
      try {
        await storage.write(key: key, value: value);
      } catch (_) {}
    }
  }

  Future<TaskCreationOperation?> getOperation(String operationId) async {
    final key = _storageKey(operationId);
    final storage = _storage;
    if (storage != null) {
      try {
        final raw = await storage.read(key: key);
        if (raw != null && raw.trim().isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          return TaskCreationOperation.fromJson(json);
        }
      } catch (_) {}
    }
    final raw = _inMemoryFallback[key];
    if (raw == null || raw.trim().isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return TaskCreationOperation.fromJson(json);
  }

  Future<List<TaskCreationOperation>> listOperationsForAccount(
    String accountScope,
  ) async {
    Map<String, String> all = {};
    final storage = _storage;
    if (storage != null) {
      try {
        all = await storage.readAll();
      } catch (_) {
        all = Map<String, String>.from(_inMemoryFallback);
      }
    } else {
      all = Map<String, String>.from(_inMemoryFallback);
    }
    final ops = <TaskCreationOperation>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_keyPrefix)) continue;
      try {
        final json = jsonDecode(entry.value) as Map<String, dynamic>;
        final op = TaskCreationOperation.fromJson(json);
        if (op.accountScope == accountScope) {
          ops.add(op);
        }
      } catch (_) {}
    }
    ops.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ops;
  }

  Future<void> deleteOperation(String operationId) async {
    final key = _storageKey(operationId);
    _inMemoryFallback.remove(key);
    final storage = _storage;
    if (storage != null) {
      try {
        await storage.delete(key: key);
      } catch (_) {}
    }
  }
}
