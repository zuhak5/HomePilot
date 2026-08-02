import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_failure.dart';
import 'media_download_cache.dart';
import 'sync_dtos.dart';

class RemoteWriteResult {
  const RemoteWriteResult.applied(
    this.canonical, {
    this.cleanupObjectPaths = const [],
  }) : conflict = false;
  const RemoteWriteResult.conflict(this.canonical)
    : conflict = true,
      cleanupObjectPaths = const [];

  final bool conflict;
  final SyncRecord? canonical;
  final List<String> cleanupObjectPaths;
}

enum MaintenanceCompletionStatus {
  applied,
  alreadyApplied,
  conflict,
  invalid,
  unauthorized,
}

class MaintenanceCompletionResult {
  const MaintenanceCompletionResult({
    required this.status,
    required this.retryable,
    this.plan,
    this.record,
    this.currentPlanRevision,
    this.resultingRecordId,
    this.resultingNextDueDate,
    this.conflictReason,
  });

  final MaintenanceCompletionStatus status;
  final bool retryable;
  final SyncRecord? plan;
  final SyncRecord? record;
  final int? currentPlanRevision;
  final String? resultingRecordId;
  final DateTime? resultingNextDueDate;
  final String? conflictReason;

  bool get acknowledged =>
      status == MaintenanceCompletionStatus.applied ||
      status == MaintenanceCompletionStatus.alreadyApplied;
}

enum SyncRealtimeStatus { subscribed, disconnected, failed }

abstract interface class RealtimeSyncSource {
  Future<void> startRealtime({
    required String userId,
    required String deviceId,
    required void Function(RealtimeSyncEvent event) onChange,
    required void Function(SyncEntitySpec spec, Map<String, dynamic> oldRecord)
    onDelete,
    required void Function(SyncRealtimeStatus status, Object? error) onStatus,
  });

  Future<void> stopRealtime();
}

class SupabaseSyncGateway implements RealtimeSyncSource {
  SupabaseSyncGateway(this._client, {MediaDownloadCache? mediaDownloadCache})
    : _mediaDownloadCache =
          mediaDownloadCache ??
          MediaDownloadCache(
            download: (objectPath) => _client.storage
                .from(_bucket)
                .download(objectPath)
                .timeout(_storageTimeout),
            rootProvider: getApplicationDocumentsDirectory,
          );

  final SupabaseClient _client;
  final MediaDownloadCache _mediaDownloadCache;
  RealtimeChannel? _realtimeChannel;
  static const pageSize = 200;
  static const _bucket = 'user-media';
  static const _maximumMediaBytes = 10 * 1024 * 1024;
  static const _dataTimeout = Duration(seconds: 30);
  static const _storageTimeout = Duration(seconds: 120);

  Future<void> registerDevice({
    required String userId,
    required String deviceId,
    int? lastAckSyncSeq,
  }) async {}

  @override
  Future<void> startRealtime({
    required String userId,
    required String deviceId,
    required void Function(RealtimeSyncEvent event) onChange,
    required void Function(SyncEntitySpec spec, Map<String, dynamic> oldRecord)
    onDelete,
    required void Function(SyncRealtimeStatus status, Object? error) onStatus,
  }) async {
    await stopRealtime();
    var channel = _client.channel(
      'homepilot-sync-$userId-$deviceId-${DateTime.now().microsecondsSinceEpoch}',
    );
    final specsByTable = {
      profileSyncSpec.remoteTable: profileSyncSpec,
      for (final spec in syncEntitySpecs) spec.remoteTable: spec,
    };
    for (final entry in specsByTable.entries) {
      final table = entry.key;
      final spec = entry.value;
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final record = payload.eventType == PostgresChangeEvent.delete
              ? payload.oldRecord
              : payload.newRecord;
          if (record['user_id'] != userId) return;
          if (spec.scope == SyncScope.deviceScoped &&
              record['device_id'] != deviceId) {
            return;
          }
          if (payload.eventType == PostgresChangeEvent.delete) {
            onDelete(spec, record);
            return;
          }
          onChange(_realtimeEvent(spec, table, payload));
        },
      );
    }
    _realtimeChannel = channel;
    channel.subscribe((status, error) {
      onStatus(switch (status) {
        RealtimeSubscribeStatus.subscribed => SyncRealtimeStatus.subscribed,
        RealtimeSubscribeStatus.closed ||
        RealtimeSubscribeStatus.timedOut => SyncRealtimeStatus.disconnected,
        RealtimeSubscribeStatus.channelError => SyncRealtimeStatus.failed,
      }, error);
    });
  }

  Future<int> syncHead(String userId) async {
    try {
      final heads = await Future.wait([
        for (final spec in [...syncEntitySpecs, profileSyncSpec])
          _tableUpdatedHead(spec, userId),
      ]);
      return heads.fold<int>(0, math.max);
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  @override
  Future<void> stopRealtime() async {
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }

  Future<int> _tableUpdatedHead(SyncEntitySpec spec, String userId) async {
    var query = _client
        .from(spec.remoteTable)
        .select('updated_at')
        .eq('user_id', userId);
    final response = await _withDataTimeout(
      () async => query.order('updated_at', ascending: false).limit(1),
    );
    if (response.isEmpty) return 0;
    final updatedAt = _parseUtc(response.first['updated_at']);
    return updatedAt?.microsecondsSinceEpoch ?? 0;
  }

  Future<List<SyncRecord>> pullChanges({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    required int afterSyncSeq,
    String? afterRecordKey,
    void Function(int exactCount)? onExactCount,
    bool materializeMedia = true,
  }) async {
    try {
      var query = _client
          .from(spec.remoteTable)
          .select(spec.selectClause)
          .eq('user_id', userId);
      if (spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      final updatedAfter = DateTime.fromMicrosecondsSinceEpoch(
        afterSyncSeq,
        isUtc: true,
      ).toIso8601String();
      if (afterRecordKey == null || afterRecordKey.isEmpty) {
        query = query.gt('updated_at', updatedAfter);
      } else {
        query = query.or(
          _stableKeysetFilter(spec, updatedAfter, afterRecordKey),
        );
      }
      final ordered = query.order('updated_at');
      final transformed = spec.keyColumns
          .fold(ordered, (builder, column) {
            return builder.order(column);
          })
          .limit(pageSize);
      late final List<dynamic> response;
      if (onExactCount != null) {
        final counted = await _withDataTimeout(
          () async => transformed.count(CountOption.exact),
        );
        onExactCount(counted.count);
        response = counted.data;
      } else {
        response = await _withDataTimeout(() async => transformed);
      }
      final parsed = [
        for (final item in response)
          SyncRecord.fromRemote(spec, item as Map<String, dynamic>),
      ];
      final records = <SyncRecord>[];
      const mediaParallelism = 4;
      for (var index = 0; index < parsed.length; index += mediaParallelism) {
        final end = index + mediaParallelism < parsed.length
            ? index + mediaParallelism
            : parsed.length;
        records.addAll(
          await Future.wait([
            for (final record in parsed.sublist(index, end))
              if (record.isDeleted)
                Future<SyncRecord>.value(record)
              else if (materializeMedia)
                _materializeRemoteMedia(record, userId)
              else
                Future<SyncRecord>.value(record),
          ]),
        );
      }
      records.sort((a, b) {
        final timestamp = a.syncSeq!.compareTo(b.syncSeq!);
        return timestamp != 0 ? timestamp : a.recordKey.compareTo(b.recordKey);
      });
      return records.take(pageSize).toList(growable: false);
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<SyncRecord> materializeRemoteMedia(SyncRecord record, String userId) =>
      _materializeRemoteMedia(record, userId);

  Future<Set<String>> fetchAuthoritativeRecordKeys({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
  }) async {
    if (spec.keyColumns.isEmpty) {
      final record = await fetch(
        spec: spec,
        userId: userId,
        deviceId: deviceId,
        recordKey: spec.entity,
        materializeMedia: false,
      );
      return record == null ? const {} : {spec.entity};
    }
    final keys = <String>{};
    String? afterRecordKey;
    while (true) {
      var query = _client
          .from(spec.remoteTable)
          .select(spec.keyColumns.join(','))
          .eq('user_id', userId);
      if (spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      if (afterRecordKey != null) {
        query = query.or(_keyOnlyFilter(spec, afterRecordKey));
      }
      var ordered = query.order(spec.keyColumns.first);
      for (final column in spec.keyColumns.skip(1)) {
        ordered = ordered.order(column);
      }
      final rows = await _withDataTimeout(() => ordered.limit(pageSize));
      if (rows.isEmpty) break;
      for (final row in rows) {
        keys.add(
          spec.keyColumns.map((column) => row[column].toString()).join('|'),
        );
      }
      afterRecordKey = keys.last;
      if (rows.length < pageSize) break;
    }
    return keys;
  }

  String _keyOnlyFilter(SyncEntitySpec spec, String afterRecordKey) {
    final values = afterRecordKey.split('|');
    final branches = <String>[];
    for (
      var keyIndex = 0;
      keyIndex < spec.keyColumns.length && keyIndex < values.length;
      keyIndex++
    ) {
      final terms = <String>[];
      for (var previous = 0; previous < keyIndex; previous++) {
        terms.add('${spec.keyColumns[previous]}.eq.${values[previous]}');
      }
      terms.add('${spec.keyColumns[keyIndex]}.gt.${values[keyIndex]}');
      branches.add(
        terms.length == 1 ? terms.single : 'and(${terms.join(',')})',
      );
    }
    return branches.join(',');
  }

  String _stableKeysetFilter(
    SyncEntitySpec spec,
    String updatedAfter,
    String afterRecordKey,
  ) {
    final values = afterRecordKey.split('|');
    final branches = <String>['updated_at.gt.$updatedAfter'];
    for (
      var keyIndex = 0;
      keyIndex < spec.keyColumns.length && keyIndex < values.length;
      keyIndex++
    ) {
      final terms = <String>['updated_at.eq.$updatedAfter'];
      for (var previous = 0; previous < keyIndex; previous++) {
        terms.add('${spec.keyColumns[previous]}.eq.${values[previous]}');
      }
      terms.add('${spec.keyColumns[keyIndex]}.gt.${values[keyIndex]}');
      branches.add('and(${terms.join(',')})');
    }
    return branches.join(',');
  }

  Future<RemoteWriteResult> write({
    required SyncRecord record,
    required String userId,
    required String deviceId,
    required int? expectedRevision,
  }) async {
    try {
      final payload = await _preparePayload(record, userId, deviceId);
      if (record.isDeleted) {
        if (expectedRevision == null) {
          final existing = await fetch(
            spec: record.spec,
            userId: userId,
            deviceId: deviceId,
            recordKey: record.recordKey,
          );
          if (existing == null) {
            return const RemoteWriteResult.applied(null);
          }
          return write(
            record: record,
            userId: userId,
            deviceId: deviceId,
            expectedRevision: existing.revision,
          );
        }
        var deleteQuery = _client
            .from(record.spec.remoteTable)
            .delete()
            .eq('user_id', userId);
        if (record.spec.scope == SyncScope.deviceScoped) {
          deleteQuery = deleteQuery.eq('device_id', deviceId);
        }
        final keyValues = _keyValues(record.spec, record.recordKey);
        for (final entry in keyValues.entries) {
          deleteQuery = deleteQuery.eq(entry.key, entry.value);
        }
        final deleted = await _withDataTimeout(
          () async => deleteQuery
              .eq('revision', expectedRevision)
              .select(record.spec.selectClause)
              .maybeSingle(),
        );
        if (deleted != null) {
          final cleanupPath = _remoteMediaPath(
            record.spec,
            Map<String, dynamic>.from(deleted),
          );
          return RemoteWriteResult.applied(
            null,
            cleanupObjectPaths: cleanupPath == null ? const [] : [cleanupPath],
          );
        }
        final current = await fetch(
          spec: record.spec,
          userId: userId,
          deviceId: deviceId,
          recordKey: record.recordKey,
        );
        return RemoteWriteResult.conflict(current);
      }
      if (expectedRevision == null) {
        try {
          final response = await _withDataTimeout(
            () async => _client
                .from(record.spec.remoteTable)
                .insert(payload)
                .select(record.spec.selectClause)
                .single(),
          );
          final canonical = SyncRecord.fromRemote(
            record.spec,
            Map<String, dynamic>.from(response),
          );
          return RemoteWriteResult.applied(
            canonical,
            cleanupObjectPaths: const [],
          );
        } on PostgrestException catch (error) {
          if (error.code != '23505') rethrow;
          final canonical = await fetch(
            spec: record.spec,
            userId: userId,
            deviceId: deviceId,
            recordKey: record.recordKey,
          );
          if (canonical == null) {
            throw const SupabaseFailure(
              kind: SupabaseFailureKind.conflict,
              message:
                  'A cloud uniqueness rule rejected this local record. '
                  'Check for duplicate names or multiple primary photos.',
            );
          }
          return RemoteWriteResult.conflict(canonical);
        }
      }

      var query = _client
          .from(record.spec.remoteTable)
          .update(payload)
          .eq('user_id', userId);
      if (record.spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      final keyValues = _keyValues(record.spec, record.recordKey);
      for (final entry in keyValues.entries) {
        query = query.eq(entry.key, entry.value);
      }
      final response = await _withDataTimeout(
        () async => query
            .eq('revision', expectedRevision)
            .select(record.spec.selectClause)
            .maybeSingle(),
      );
      if (response == null) {
        return RemoteWriteResult.conflict(
          await fetch(
            spec: record.spec,
            userId: userId,
            deviceId: deviceId,
            recordKey: record.recordKey,
          ),
        );
      }
      final canonical = SyncRecord.fromRemote(
        record.spec,
        Map<String, dynamic>.from(response),
      );
      return RemoteWriteResult.applied(canonical, cleanupObjectPaths: const []);
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<List<SyncRecord>?> writeNewBatch({
    required List<SyncRecord> records,
    required String userId,
    required String deviceId,
  }) async {
    if (records.isEmpty) return const [];
    final spec = records.first.spec;
    if (records.any(
      (record) =>
          record.spec.entity != spec.entity ||
          record.isDeleted ||
          record.spec.entity == 'asset_photo' ||
          record.spec.entity == 'profile',
    )) {
      return null;
    }
    try {
      final payloads = <Map<String, dynamic>>[];
      for (final record in records) {
        payloads.add(await _preparePayload(record, userId, deviceId));
      }
      final response = await _withDataTimeout(
        () async => _client
            .from(spec.remoteTable)
            .insert(payloads)
            .select(spec.selectClause),
      );
      return [
        for (final item in response)
          SyncRecord.fromRemote(spec, Map<String, dynamic>.from(item)),
      ];
    } on PostgrestException catch (error) {
      if (error.code == '23505') return null;
      throw SupabaseFailure.from(error);
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<MaintenanceCompletionResult> completeMaintenance({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        throw const FormatException(
          'The queued maintenance completion payload is invalid.',
        );
      }
      final operation = Map<String, dynamic>.from(decoded);
      final Object? response = await _withDataTimeout<Object?>(
        () async => _client.rpc<Map<String, dynamic>>(
          'complete_maintenance_task',
          params: {'p_operation': operation, 'p_device_id': deviceId},
        ),
      );
      if (response is! Map) {
        throw const FormatException(
          'The maintenance completion RPC returned an invalid result.',
        );
      }

      final body = Map<String, dynamic>.from(response);
      final status = _maintenanceCompletionStatus(body['status']);
      final rawPlan = body['plan'];
      final rawRecord = body['record'];
      final planData = rawPlan is Map
          ? Map<String, dynamic>.from(rawPlan)
          : null;
      final recordData = rawRecord is Map
          ? Map<String, dynamic>.from(rawRecord)
          : null;
      if ((planData != null && planData['user_id'] != userId) ||
          (recordData != null && recordData['user_id'] != userId)) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'The cloud returned maintenance data for another account.',
        );
      }
      if ((status == MaintenanceCompletionStatus.applied ||
              status == MaintenanceCompletionStatus.alreadyApplied) &&
          (planData == null || recordData == null)) {
        throw const FormatException(
          'The maintenance completion RPC omitted canonical records.',
        );
      }

      return MaintenanceCompletionResult(
        status: status,
        retryable: body['retryable'] == true,
        plan: planData == null
            ? null
            : SyncRecord.fromRemote(
                syncSpecByEntity['maintenance_plan']!,
                planData,
              ),
        record: recordData == null
            ? null
            : SyncRecord.fromRemote(
                syncSpecByEntity['maintenance_record']!,
                recordData,
              ),
        currentPlanRevision: (body['current_plan_revision'] as num?)?.toInt(),
        resultingRecordId: body['resulting_record_id'] as String?,
        resultingNextDueDate: _parseUtc(body['resulting_next_due_date']),
        conflictReason: body['conflict_reason'] as String?,
      );
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<SyncRecord?> fetch({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    required String recordKey,
    bool materializeMedia = true,
  }) async {
    try {
      var query = _client
          .from(spec.remoteTable)
          .select(spec.selectClause)
          .eq('user_id', userId);
      if (spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      final keyValues = _keyValues(spec, recordKey);
      for (final entry in keyValues.entries) {
        query = query.eq(entry.key, entry.value);
      }
      final response = await _withDataTimeout(() async => query.maybeSingle());
      if (response == null) return null;
      var record = SyncRecord.fromRemote(
        spec,
        Map<String, dynamic>.from(response),
      );
      if (materializeMedia && !record.isDeleted) {
        record = await _materializeRemoteMedia(record, userId);
      }
      return record;
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<Map<String, dynamic>> _preparePayload(
    SyncRecord record,
    String userId,
    String deviceId,
  ) async {
    final payload = record.toRemotePayload(userId, deviceId: deviceId);
    if (record.isDeleted) {
      return payload;
    }
    if (record.spec.entity == 'asset_photo') {
      final localPath = record.values['relative_path'] as String;
      final assetId = record.values['asset_id'] as String;
      final photoId = record.values['id'] as String;
      final upload = await _uploadMedia(
        userId: userId,
        localRelativePath: localPath,
        remoteDirectory: '$userId/assets/$assetId',
        remoteBaseName: photoId,
      );
      payload['object_path'] = upload.objectPath;
    }
    return payload;
  }

  Future<List<Map<String, dynamic>>> pullCatalogCategories({
    required String userId,
  }) async {
    try {
      final categorySpec = syncSpecByEntity['category']!;
      final response = await _withDataTimeout(
        () async => _client
            .from(categorySpec.remoteTable)
            .select(categorySpec.selectClause)
            .eq('user_id', userId)
            .order('id'),
      );
      return [for (final item in response) Map<String, dynamic>.from(item)];
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<SyncRecord> _materializeRemoteMedia(
    SyncRecord record,
    String userId,
  ) async {
    if (record.spec.entity != 'asset_photo') {
      return record;
    }
    const key = 'relative_path';
    final objectPath = record.values[key] as String?;
    if (objectPath == null || objectPath.isEmpty) {
      return record;
    }
    if (!objectPath.startsWith('$userId/')) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud media path does not belong to this account.',
      );
    }
    final version =
        record.serverUpdatedAt?.toUtc().toIso8601String() ??
        record.revision?.toString() ??
        record.syncSeq.toString();
    final cached = await _mediaDownloadCache.materialize(
      objectPath: objectPath,
      version: version,
      assetId: record.values['asset_id'] as String,
    );
    return SyncRecord(
      spec: record.spec,
      recordKey: record.recordKey,
      values: {...record.values, key: cached.relativePath},
      clientModifiedAt: record.clientModifiedAt,
      originDeviceId: record.originDeviceId,
      revision: record.revision,
      syncSeq: record.syncSeq,
      serverUpdatedAt: record.serverUpdatedAt,
      deletedAt: record.deletedAt,
    );
  }

  Future<void> removeMediaObject(String objectPath, String userId) async {
    if (objectPath.isEmpty) return;
    if (!objectPath.startsWith('$userId/')) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud media path does not belong to this account.',
      );
    }
    await _client.storage
        .from(_bucket)
        .remove([objectPath])
        .timeout(_storageTimeout);
  }

  Future<_MediaUpload> _uploadMedia({
    required String userId,
    required String localRelativePath,
    required String remoteDirectory,
    required String remoteBaseName,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final file = File(
      p.normalize(p.joinAll([documents.path, ...localRelativePath.split('/')])),
    );
    if (!p.isWithin(documents.path, file.path) || !await file.exists()) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'A local media file is missing.',
      );
    }
    final byteSize = await file.length();
    if (byteSize > _maximumMediaBytes) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud images must be 10 MiB or smaller.',
      );
    }
    final extension = p.extension(file.path).toLowerCase();
    final mimeType = switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Only JPEG, PNG, and WebP images can be uploaded.',
      ),
    };
    final objectPath =
        '$remoteDirectory/$remoteBaseName'
        '${extension == '.jpeg' ? '.jpg' : extension}';
    await _client.storage
        .from(_bucket)
        .upload(
          objectPath,
          file,
          fileOptions: FileOptions(upsert: true, contentType: mimeType),
        )
        .timeout(_storageTimeout);
    return _MediaUpload(objectPath: objectPath);
  }
}

Future<T> _withDataTimeout<T>(Future<T> Function() action) {
  return action().timeout(SupabaseSyncGateway._dataTimeout);
}

String? _remoteMediaPath(SyncEntitySpec spec, Map<String, dynamic> values) {
  return switch (spec.entity) {
    'asset_photo' => values['object_path'] as String?,
    _ => null,
  };
}

Map<String, String> _keyValues(SyncEntitySpec spec, String recordKey) {
  if (spec.entity == 'profile') return const {};
  final parts = recordKey.split('|');
  return {
    for (var index = 0; index < spec.keyColumns.length; index++)
      spec.keyColumns[index]: parts[index],
  };
}

RealtimeSyncEvent _realtimeEvent(
  SyncEntitySpec spec,
  String table,
  dynamic payload,
) {
  final row = Map<String, dynamic>.from(payload.newRecord as Map);
  return RealtimeSyncEvent(
    table: table,
    spec: spec,
    type: _realtimeType(payload.eventType as PostgresChangeEvent),
    recordKey: _recordKeyFromRemote(spec, row),
    revision: row['revision'] is num ? (row['revision'] as num).toInt() : null,
    updatedAt: _parseUtc(row['updated_at']),
    originDeviceId: row['origin_device_id'] as String?,
  );
}

SyncRealtimeEventType _realtimeType(PostgresChangeEvent event) {
  return switch (event) {
    PostgresChangeEvent.insert => SyncRealtimeEventType.insert,
    PostgresChangeEvent.update => SyncRealtimeEventType.update,
    PostgresChangeEvent.delete => SyncRealtimeEventType.delete,
    PostgresChangeEvent.all => SyncRealtimeEventType.update,
  };
}

String? _recordKeyFromRemote(SyncEntitySpec spec, Map<String, dynamic> row) {
  if (spec.keyColumns.isEmpty) return spec.entity;
  final values = <String>[];
  for (final column in spec.keyColumns) {
    final value = row[spec.remoteColumnFor(column)];
    if (value == null) return null;
    values.add(value.toString());
  }
  return values.join('|');
}

DateTime? _parseUtc(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

MaintenanceCompletionStatus _maintenanceCompletionStatus(Object? value) {
  return switch (value) {
    'applied' => MaintenanceCompletionStatus.applied,
    'already_applied' => MaintenanceCompletionStatus.alreadyApplied,
    'conflict' => MaintenanceCompletionStatus.conflict,
    'invalid' => MaintenanceCompletionStatus.invalid,
    'unauthorized' => MaintenanceCompletionStatus.unauthorized,
    _ => throw const FormatException(
      'The maintenance completion RPC returned an unknown status.',
    ),
  };
}

class _MediaUpload {
  const _MediaUpload({required this.objectPath});

  final String objectPath;
}
