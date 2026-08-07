import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../domain/contracts.dart';
import '../domain/models.dart' as domain;
import '../domain/render_fingerprints.dart';
import '../domain/task_selectors.dart';
import '../services/health_score_calculator.dart';
import '../services/recurrence_engine.dart';
import '../utils/date_utils.dart';
import 'reactive_stream.dart';

const _uuid = Uuid();

Future<void> _deletePlansCascade(AppDatabase db, List<String> planIds) async {
  if (planIds.isEmpty) {
    return;
  }
  await (db.delete(
    db.inboxNotifications,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.appNotifications,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.maintenanceRecords,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.maintenancePlanMetadata,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.maintenancePlans,
  )..where((row) => row.id.isIn(planIds))).go();
}

Future<void> _syncPlantWateringPlansForInterval({
  required AppDatabase db,
  required String assetId,
  required int? previousIntervalDays,
  required int? nextIntervalDays,
  required DateTime updatedAt,
}) async {
  if (nextIntervalDays == null ||
      nextIntervalDays < 1 ||
      previousIntervalDays == nextIntervalDays) {
    return;
  }
  final plans =
      await (db.select(db.maintenancePlans)..where(
            (plan) =>
                plan.assetId.equals(assetId) &
                plan.archivedAt.isNull() &
                plan.healthGroup.equals(domain.HealthGroup.plants.name) &
                plan.recurrenceUnit.equals(domain.RecurrenceUnit.days.name),
          ))
          .get();
  if (plans.isEmpty) return;

  final planIds = plans.map((plan) => plan.id).toList();
  final metadataRows = await (db.select(
    db.maintenancePlanMetadata,
  )..where((row) => row.planId.isIn(planIds))).get();
  final metadataByPlanId = {for (final row in metadataRows) row.planId: row};

  for (final plan in plans) {
    if (plan.recurrenceInterval == nextIntervalDays) continue;
    final metadata = metadataByPlanId[plan.id];
    if (!_isClearPlantWateringPlan(plan, metadata)) continue;
    final latestCompletion =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.equals(plan.id))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)])
              ..limit(1))
            .getSingleOrNull();
    final nextDueDate = latestCompletion == null
        ? const Value<DateTime>.absent()
        : Value<DateTime>(
            _nextDailyDueDate(latestCompletion.completedAt, nextIntervalDays),
          );
    await (db.update(
      db.maintenancePlans,
    )..where((row) => row.id.equals(plan.id))).write(
      MaintenancePlansCompanion(
        recurrenceInterval: Value(nextIntervalDays),
        recurrenceUnit: Value(domain.RecurrenceUnit.days.name),
        nextDueDate: nextDueDate,
        updatedAt: Value(updatedAt),
      ),
    );
  }
}

bool _isClearPlantWateringPlan(
  MaintenancePlanRow plan,
  MaintenancePlanMetadataRow? metadata,
) {
  final primaryText = _normalizedConsistencyText([
    plan.title,
    metadata?.taskType,
  ]);
  if (!_wateringIntentPattern.hasMatch(primaryText)) return false;
  if (_nonWateringPlantIntentPattern.hasMatch(primaryText)) return false;
  return true;
}

DateTime _nextDailyDueDate(DateTime completionDate, int intervalDays) {
  return DateTime(
    completionDate.year,
    completionDate.month,
    completionDate.day + intervalDays,
    completionDate.hour,
    completionDate.minute,
    completionDate.second,
    completionDate.millisecond,
    completionDate.microsecond,
  );
}

String _normalizedConsistencyText(Iterable<Object?> values) {
  return values
      .whereType<Object>()
      .map((value) => value.toString().toLowerCase())
      .join(' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

final RegExp _wateringIntentPattern = RegExp(
  r'\b(water|watering|moisture|irrigat|hydrate|hydro|watercheck|waterchange)\b',
);

final RegExp _nonWateringPlantIntentPattern = RegExp(
  r'\b(fertiliz|feed|prun|trim|repot|sunlight|light|pest|leaf|leaves|temperature|aquarium|fish|gravel)\b',
);

class DriftAssetRepository implements AssetRepository {
  DriftAssetRepository(this.db);

  final AppDatabase db;

  @override
  Stream<List<domain.Area>> watchAreas() {
    final query = db.select(db.areas)
      ..where((area) => area.archivedAt.isNull())
      ..orderBy([
        (area) => OrderingTerm.asc(area.sortOrder),
        (area) => OrderingTerm.asc(area.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_areaFromRow).toList())
        .distinctByFingerprint(areaListFingerprint);
  }

  @override
  Future<List<domain.Area>> listAreas() async {
    final rows =
        await (db.select(db.areas)
              ..where((area) => area.archivedAt.isNull())
              ..orderBy([
                (area) => OrderingTerm.asc(area.sortOrder),
                (area) => OrderingTerm.asc(area.name),
              ]))
            .get();
    return rows.map(_areaFromRow).toList();
  }

  @override
  Future<String> saveArea({
    String? id,
    required String name,
    required domain.AreaKind kind,
    int? sortOrder,
  }) async {
    final areaId = id ?? _uuid.v7();
    final now = DateTime.now();
    final existing = id == null
        ? null
        : await (db.select(
            db.areas,
          )..where((area) => area.id.equals(areaId))).getSingleOrNull();
    final resolvedSortOrder =
        sortOrder ?? existing?.sortOrder ?? await _nextAreaSortOrder();
    if (existing == null) {
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: areaId,
              name: name.trim(),
              kind: kind.name,
              sortOrder: Value(resolvedSortOrder),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (db.update(
        db.areas,
      )..where((area) => area.id.equals(areaId))).write(
        AreasCompanion(
          name: Value(name.trim()),
          kind: Value(kind.name),
          sortOrder: Value(resolvedSortOrder),
          updatedAt: Value(now),
        ),
      );
    }
    return areaId;
  }

  @override
  Future<void> archiveArea(String id) async {
    final roomCount =
        await (db.select(db.rooms)..where(
              (room) => room.areaId.equals(id) & room.archivedAt.isNull(),
            ))
            .get();
    if (roomCount.isNotEmpty) {
      throw StateError('Move or archive rooms before archiving this area.');
    }
    await (db.update(db.areas)..where((area) => area.id.equals(id))).write(
      AreasCompanion(archivedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> deleteArea(String id) async {
    final roomRows = await (db.select(
      db.rooms,
    )..where((room) => room.areaId.equals(id))).get();
    final roomIds = roomRows.map((row) => row.id).toList();
    final assetRows = roomIds.isEmpty
        ? <AssetRow>[]
        : await (db.select(
            db.assets,
          )..where((asset) => asset.roomId.isIn(roomIds))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    final photoRows = await _photoRowsForAssets(assetIds);
    await db.transaction(() async {
      await _deleteAssetsCascadeInTransaction(assetIds);
      if (roomIds.isNotEmpty) {
        await (db.delete(
          db.rooms,
        )..where((room) => room.id.isIn(roomIds))).go();
      }
      await (db.delete(db.areas)..where((area) => area.id.equals(id))).go();
    });
    await _deletePhotoFiles(photoRows);
  }

  @override
  Stream<List<domain.Area>> watchArchivedAreas() {
    final query = db.select(db.areas)
      ..where((area) => area.archivedAt.isNotNull())
      ..orderBy([
        (area) => OrderingTerm.desc(area.archivedAt),
        (area) => OrderingTerm.asc(area.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_areaFromRow).toList())
        .distinctByFingerprint(areaListFingerprint);
  }

  @override
  Future<List<domain.Area>> listArchivedAreas() async {
    final rows =
        await (db.select(db.areas)
              ..where((area) => area.archivedAt.isNotNull())
              ..orderBy([
                (area) => OrderingTerm.desc(area.archivedAt),
                (area) => OrderingTerm.asc(area.name),
              ]))
            .get();
    return rows.map(_areaFromRow).toList();
  }

  @override
  Future<void> trashArea(String id) async {
    final now = DateTime.now();
    final roomRows = await (db.select(
      db.rooms,
    )..where((room) => room.areaId.equals(id))).get();
    final roomIds = roomRows.map((row) => row.id).toList();
    final assetRows = roomIds.isEmpty
        ? <AssetRow>[]
        : await (db.select(
            db.assets,
          )..where((asset) => asset.roomId.isIn(roomIds))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(db.areas)..where((area) => area.id.equals(id))).write(
        AreasCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      if (roomIds.isNotEmpty) {
        await (db.update(
          db.rooms,
        )..where((room) => room.id.isIn(roomIds))).write(
          RoomsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
      }
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  @override
  Future<void> restoreArea(String id) async {
    final now = DateTime.now();
    final roomRows = await (db.select(
      db.rooms,
    )..where((room) => room.areaId.equals(id))).get();
    final roomIds = roomRows.map((row) => row.id).toList();
    final assetRows = roomIds.isEmpty
        ? <AssetRow>[]
        : await (db.select(
            db.assets,
          )..where((asset) => asset.roomId.isIn(roomIds))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(db.areas)..where((area) => area.id.equals(id))).write(
        AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      if (roomIds.isNotEmpty) {
        await (db.update(
          db.rooms,
        )..where((room) => room.id.isIn(roomIds))).write(
          RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  @override
  Stream<List<domain.Room>> watchRooms({String? areaId}) {
    final query = db.select(db.rooms)
      ..where(
        (room) =>
            room.archivedAt.isNull() &
            (areaId == null
                ? const Constant(true)
                : room.areaId.equals(areaId)),
      )
      ..orderBy([
        (room) => OrderingTerm.asc(room.sortOrder),
        (room) => OrderingTerm.asc(room.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_roomFromRow).toList())
        .distinctByFingerprint(roomListFingerprint);
  }

  @override
  Future<List<domain.Room>> listRooms({String? areaId}) async {
    final query = db.select(db.rooms)
      ..where(
        (room) =>
            room.archivedAt.isNull() &
            (areaId == null
                ? const Constant(true)
                : room.areaId.equals(areaId)),
      )
      ..orderBy([
        (room) => OrderingTerm.asc(room.sortOrder),
        (room) => OrderingTerm.asc(room.name),
      ]);
    return (await query.get()).map(_roomFromRow).toList();
  }

  @override
  Future<String> saveRoom({
    String? id,
    required String areaId,
    required String name,
    domain.RoomType roomType = domain.RoomType.other,
    String? notes,
    int? sortOrder,
  }) async {
    final roomId = id ?? _uuid.v7();
    final now = DateTime.now();
    final existing = id == null
        ? null
        : await (db.select(
            db.rooms,
          )..where((room) => room.id.equals(roomId))).getSingleOrNull();
    final resolvedSortOrder =
        sortOrder ??
        (existing?.areaId == areaId ? existing?.sortOrder : null) ??
        await _nextRoomSortOrder(areaId);
    if (id == null) {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: roomId,
              areaId: areaId,
              name: name.trim(),
              roomType: Value(roomType.name),
              notes: Value(_blankToNull(notes)),
              sortOrder: Value(resolvedSortOrder),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (db.update(
        db.rooms,
      )..where((room) => room.id.equals(roomId))).write(
        RoomsCompanion(
          areaId: Value(areaId),
          name: Value(name.trim()),
          roomType: Value(roomType.name),
          notes: Value(_blankToNull(notes)),
          sortOrder: Value(resolvedSortOrder),
          updatedAt: Value(now),
        ),
      );
    }
    return roomId;
  }

  @override
  Future<void> archiveRoom(String id) async {
    final assetRows =
        await (db.select(db.assets)..where(
              (asset) => asset.roomId.equals(id) & asset.archivedAt.isNull(),
            ))
            .get();
    if (assetRows.isNotEmpty) {
      throw StateError('Move or archive items before archiving this room.');
    }
    await (db.update(db.rooms)..where((room) => room.id.equals(id))).write(
      RoomsCompanion(
        archivedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteRoom(String id) async {
    final assetRows = await (db.select(
      db.assets,
    )..where((asset) => asset.roomId.equals(id))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    final photoRows = await _photoRowsForAssets(assetIds);
    await db.transaction(() async {
      await _deleteAssetsCascadeInTransaction(assetIds);
      await (db.delete(db.rooms)..where((room) => room.id.equals(id))).go();
    });
    await _deletePhotoFiles(photoRows);
  }

  @override
  Stream<List<domain.Room>> watchArchivedRooms() {
    final query = db.select(db.rooms)
      ..where((room) => room.archivedAt.isNotNull())
      ..orderBy([
        (room) => OrderingTerm.desc(room.archivedAt),
        (room) => OrderingTerm.asc(room.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_roomFromRow).toList())
        .distinctByFingerprint(roomListFingerprint);
  }

  @override
  Future<List<domain.Room>> listArchivedRooms() async {
    final rows =
        await (db.select(db.rooms)
              ..where((room) => room.archivedAt.isNotNull())
              ..orderBy([
                (room) => OrderingTerm.desc(room.archivedAt),
                (room) => OrderingTerm.asc(room.name),
              ]))
            .get();
    return rows.map(_roomFromRow).toList();
  }

  @override
  Future<void> trashRoom(String id) async {
    final now = DateTime.now();
    final assetRows = await (db.select(
      db.assets,
    )..where((asset) => asset.roomId.equals(id))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(db.rooms)..where((room) => room.id.equals(id))).write(
        RoomsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  @override
  Future<void> restoreRoom(String id) async {
    final now = DateTime.now();
    final room = await (db.select(
      db.rooms,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (room == null) return;
    final assetRows = await (db.select(
      db.assets,
    )..where((asset) => asset.roomId.equals(id))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(
        db.areas,
      )..where((area) => area.id.equals(room.areaId))).write(
        AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      await (db.update(db.rooms)..where((row) => row.id.equals(id))).write(
        RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  @override
  Stream<List<domain.Asset>> watchAssets({String? roomId}) {
    return watchReloaded(
      triggers: [
        db.select(db.assets).watch(),
        db.select(db.deviceDetailsTable).watch(),
        db.select(db.petDetailsTable).watch(),
        db.select(db.plantDetailsTable).watch(),
        db.select(db.safetyDetailsTable).watch(),
      ],
      load: () => listAssets(roomId: roomId),
      fingerprint: assetListFingerprint,
    );
  }

  @override
  Future<List<domain.Asset>> listAssets({String? roomId}) async {
    final query = db.select(db.assets)
      ..where(
        (asset) =>
            asset.archivedAt.isNull() &
            (roomId == null
                ? const Constant(true)
                : asset.roomId.equals(roomId)),
      )
      ..orderBy([(asset) => OrderingTerm.asc(asset.name)]);
    return _hydrateAssetRows(await query.get());
  }

  @override
  Stream<domain.Asset?> watchAsset(String id) {
    return watchReloaded(
      triggers: [
        db.select(db.assets).watch(),
        db.select(db.deviceDetailsTable).watch(),
        db.select(db.petDetailsTable).watch(),
        db.select(db.plantDetailsTable).watch(),
        db.select(db.safetyDetailsTable).watch(),
      ],
      load: () => getAsset(id),
      fingerprint: (asset) => asset == null ? 0 : assetFingerprint(asset),
    );
  }

  @override
  Future<domain.Asset?> getAsset(String id) async {
    final row = await (db.select(
      db.assets,
    )..where((asset) => asset.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return (await _hydrateAssetRows([row])).first;
  }

  @override
  Future<String> saveAsset({
    String? id,
    required String name,
    domain.AssetType assetType = domain.AssetType.general,
    required String categoryId,
    required String roomId,
    String? placement,
    String? notes,
    DateTime? purchaseDate,
    List<String> tagNames = const [],
    domain.DeviceDetails? deviceDetails,
    domain.PetDetails? petDetails,
    domain.PlantDetails? plantDetails,
    domain.SafetyDetails? safetyDetails,
  }) async {
    final assetId = id ?? _uuid.v7();
    final now = DateTime.now();
    await db.transaction(() async {
      final existingAsset = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(assetId))).getSingleOrNull();
      final previousPlantDetails = existingAsset == null
          ? null
          : await (db.select(
              db.plantDetailsTable,
            )..where((row) => row.assetId.equals(assetId))).getSingleOrNull();
      if (existingAsset == null) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: assetId,
                name: name.trim(),
                assetType: Value(assetType.name),
                categoryId: categoryId,
                roomId: roomId,
                placement: Value(_blankToNull(placement)),
                notes: Value(_blankToNull(notes)),
                purchaseDate: Value(purchaseDate),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.equals(assetId))).write(
          AssetsCompanion(
            name: Value(name.trim()),
            assetType: Value(assetType.name),
            categoryId: Value(categoryId),
            roomId: Value(roomId),
            placement: Value(_blankToNull(placement)),
            notes: Value(_blankToNull(notes)),
            purchaseDate: Value(purchaseDate),
            updatedAt: Value(now),
          ),
        );
      }

      await _replaceAssetDetails(
        assetId: assetId,
        assetType: assetType,
        deviceDetails: deviceDetails,
        petDetails: petDetails,
        plantDetails: plantDetails,
        safetyDetails: safetyDetails,
      );
      await _syncPlantWateringPlansForInterval(
        db: db,
        assetId: assetId,
        previousIntervalDays: previousPlantDetails?.wateringIntervalDays,
        nextIntervalDays: assetType == domain.AssetType.plant
            ? plantDetails?.wateringIntervalDays
            : null,
        updatedAt: now,
      );

      await (db.delete(
        db.assetTags,
      )..where((tag) => tag.assetId.equals(assetId))).go();
      for (final rawTag in tagNames) {
        final tagName = rawTag.trim();
        if (tagName.isEmpty) {
          continue;
        }
        final tagId = await _ensureTag(tagName);
        await db
            .into(db.assetTags)
            .insert(
              AssetTagsCompanion.insert(assetId: assetId, tagId: tagId),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
    return assetId;
  }

  @override
  Future<void> moveAsset({
    required String assetId,
    required String roomId,
  }) async {
    await _ensureActiveRoom(roomId);
    final asset = await getAsset(assetId);
    if (asset == null || asset.archivedAt != null) {
      throw StateError('Item is no longer available.');
    }
    final tags = await listTagsForAsset(assetId);
    await saveAsset(
      id: asset.id,
      name: asset.name,
      assetType: asset.assetType,
      categoryId: asset.categoryId,
      roomId: roomId,
      placement: asset.placement,
      notes: asset.notes,
      purchaseDate: asset.purchaseDate,
      tagNames: [for (final tag in tags) tag.name],
      deviceDetails: asset.deviceDetails,
      petDetails: asset.petDetails,
      plantDetails: asset.plantDetails,
      safetyDetails: asset.safetyDetails,
    );
  }

  @override
  Future<String> copyAsset({
    required String assetId,
    required String roomId,
    bool includeTasks = true,
    bool includePhotos = false,
    String? newAssetId,
    Map<String, String> taskIdBySource = const {},
  }) async {
    await _ensureActiveRoom(roomId);
    final source = await getAsset(assetId);
    if (source == null || source.archivedAt != null) {
      throw StateError('Item is no longer available.');
    }
    final tags = await listTagsForAsset(assetId);
    final copiedAssetId = await saveAsset(
      id: newAssetId,
      name: source.name,
      assetType: source.assetType,
      categoryId: source.categoryId,
      roomId: roomId,
      placement: source.placement,
      notes: source.notes,
      purchaseDate: source.purchaseDate,
      tagNames: [for (final tag in tags) tag.name],
      deviceDetails: source.deviceDetails,
      petDetails: source.petDetails,
      plantDetails: source.plantDetails,
      safetyDetails: source.safetyDetails,
    );
    if (includeTasks) {
      final maintenance = DriftMaintenanceRepository(db);
      final tasks = await maintenance.listTasksForAsset(assetId);
      for (final task in tasks) {
        await maintenance.savePlan(
          id: taskIdBySource[task.plan.id],
          assetId: copiedAssetId,
          title: task.plan.title,
          instructions: task.plan.instructions,
          recurrence: task.plan.recurrence,
          priority: task.plan.priority,
          nextDueDate: task.plan.nextDueDate,
          healthGroup: task.plan.healthGroup,
          reminderDaysBefore: task.plan.reminderDaysBefore,
          metadata: task.plan.metadata,
        );
      }
    }
    if (includePhotos) {
      final docDir = await getApplicationDocumentsDirectory();
      final photos = await listPhotosForAsset(assetId);
      for (final photo in photos) {
        final file = File(
          p.joinAll([docDir.path, ...photo.relativePath.split('/')]),
        );
        if (!await file.exists()) {
          continue;
        }
        await addPhoto(
          copiedAssetId,
          file.path,
          caption: photo.caption,
          makePrimary: photo.isPrimary,
        );
      }
    }
    return copiedAssetId;
  }

  @override
  Future<void> archiveAsset(String id) async {
    await (db.update(db.assets)..where((asset) => asset.id.equals(id))).write(
      AssetsCompanion(
        archivedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteAsset(String id) async {
    final photoRows = await _photoRowsForAssets([id]);
    await db.transaction(() async {
      await _deleteAssetsCascadeInTransaction([id]);
    });
    await _deletePhotoFiles(photoRows);
  }

  @override
  Stream<List<domain.Asset>> watchArchivedAssets() {
    return watchReloaded(
      triggers: [
        db.select(db.assets).watch(),
        db.select(db.deviceDetailsTable).watch(),
        db.select(db.petDetailsTable).watch(),
        db.select(db.plantDetailsTable).watch(),
        db.select(db.safetyDetailsTable).watch(),
      ],
      load: listArchivedAssets,
      fingerprint: assetListFingerprint,
    );
  }

  @override
  Future<List<domain.Asset>> listArchivedAssets() async {
    final rows =
        await (db.select(db.assets)
              ..where((asset) => asset.archivedAt.isNotNull())
              ..orderBy([
                (asset) => OrderingTerm.desc(asset.archivedAt),
                (asset) => OrderingTerm.asc(asset.name),
              ]))
            .get();
    return _hydrateAssetRows(rows);
  }

  @override
  Future<void> trashAsset(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.assets)..where((asset) => asset.id.equals(id))).write(
        AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      await (db.update(
        db.maintenancePlans,
      )..where((plan) => plan.assetId.equals(id))).write(
        MaintenancePlansCompanion(
          archivedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> restoreAsset(String id) async {
    final now = DateTime.now();
    final asset = await (db.select(
      db.assets,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (asset == null) return;
    final room = await (db.select(
      db.rooms,
    )..where((row) => row.id.equals(asset.roomId))).getSingleOrNull();
    await db.transaction(() async {
      if (room != null) {
        await (db.update(
          db.areas,
        )..where((area) => area.id.equals(room.areaId))).write(
          AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.rooms,
        )..where((row) => row.id.equals(asset.roomId))).write(
          RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      await (db.update(db.assets)..where((row) => row.id.equals(id))).write(
        AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      await (db.update(
        db.maintenancePlans,
      )..where((plan) => plan.assetId.equals(id))).write(
        MaintenancePlansCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<domain.AssetPhoto> addPhoto(
    String assetId,
    String sourcePath, {
    String? caption,
    bool makePrimary = false,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'Photo file does not exist.',
      );
    }
    final docDir = await getApplicationDocumentsDirectory();
    final photoId = _uuid.v7();
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final relativePath = p.posix.join('photos', assetId, '$photoId$extension');
    final destination = File(
      p.joinAll([docDir.path, ...relativePath.split('/')]),
    );
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    final existingPhotos = await listPhotosForAsset(assetId);
    final isPrimary = makePrimary || existingPhotos.isEmpty;
    final createdAt = DateTime.now();
    try {
      await db.transaction(() async {
        if (isPrimary) {
          await (db.update(db.assetPhotos)
                ..where((photo) => photo.assetId.equals(assetId)))
              .write(const AssetPhotosCompanion(isPrimary: Value(false)));
        }
        await db
            .into(db.assetPhotos)
            .insert(
              AssetPhotosCompanion.insert(
                id: photoId,
                assetId: assetId,
                relativePath: relativePath,
                caption: Value(_blankToNull(caption)),
                isPrimary: Value(isPrimary),
                createdAt: Value(createdAt),
              ),
            );
      });
    } catch (_) {
      try {
        if (await destination.exists()) {
          await destination.delete();
        }
      } catch (_) {
        // The database insert failed, so the app should not rely on this file.
      }
      rethrow;
    }
    return domain.AssetPhoto(
      id: photoId,
      assetId: assetId,
      relativePath: relativePath,
      caption: _blankToNull(caption),
      isPrimary: isPrimary,
      createdAt: createdAt,
    );
  }

  @override
  Future<void> setPrimaryPhoto(String assetId, String photoId) async {
    await db.transaction(() async {
      final target =
          await (db.select(db.assetPhotos)..where(
                (photo) =>
                    photo.id.equals(photoId) & photo.assetId.equals(assetId),
              ))
              .getSingleOrNull();
      if (target == null) {
        return;
      }
      await (db.update(db.assetPhotos)
            ..where((photo) => photo.assetId.equals(assetId)))
          .write(const AssetPhotosCompanion(isPrimary: Value(false)));
      await (db.update(db.assetPhotos)..where(
            (photo) => photo.id.equals(photoId) & photo.assetId.equals(assetId),
          ))
          .write(const AssetPhotosCompanion(isPrimary: Value(true)));
    });
  }

  @override
  Future<void> deletePhoto(String photoId) async {
    final row = await (db.select(
      db.assetPhotos,
    )..where((photo) => photo.id.equals(photoId))).getSingleOrNull();
    if (row == null) {
      return;
    }
    await (db.delete(
      db.assetPhotos,
    )..where((photo) => photo.id.equals(photoId))).go();
    if (row.isPrimary) {
      final next =
          await (db.select(db.assetPhotos)
                ..where((photo) => photo.assetId.equals(row.assetId))
                ..orderBy([(photo) => OrderingTerm.desc(photo.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (next != null) {
        await setPrimaryPhoto(row.assetId, next.id);
      }
    }
    await _deletePhotoFile(row);
  }

  @override
  Stream<List<domain.AssetPhoto>> watchPhotosForAsset(String assetId) {
    return (db.select(db.assetPhotos)
          ..where((photo) => photo.assetId.equals(assetId))
          ..orderBy([
            (photo) => OrderingTerm.desc(photo.isPrimary),
            (photo) => OrderingTerm.desc(photo.createdAt),
          ]))
        .watch()
        .map((rows) => rows.map(_photoFromRow).toList())
        .distinctByFingerprint(assetPhotoListFingerprint);
  }

  @override
  Future<List<domain.AssetPhoto>> listPhotosForAsset(String assetId) async {
    final rows =
        await (db.select(db.assetPhotos)
              ..where((photo) => photo.assetId.equals(assetId))
              ..orderBy([
                (photo) => OrderingTerm.desc(photo.isPrimary),
                (photo) => OrderingTerm.desc(photo.createdAt),
              ]))
            .get();
    return rows.map(_photoFromRow).toList();
  }

  @override
  Stream<List<domain.Category>> watchCategories() {
    return (db.select(db.categories)
          ..orderBy([(category) => OrderingTerm.asc(category.name)]))
        .watch()
        .map((rows) => rows.map(_categoryFromRow).toList())
        .distinctByFingerprint(categoryListFingerprint);
  }

  @override
  Future<List<domain.Category>> listCategories() async {
    final rows = await (db.select(
      db.categories,
    )..orderBy([(category) => OrderingTerm.asc(category.name)])).get();
    return rows.map(_categoryFromRow).toList();
  }

  @override
  Stream<List<domain.Tag>> watchTagsForAsset(String assetId) {
    return watchReloaded(
      triggers: [db.select(db.assetTags).watch(), db.select(db.tags).watch()],
      load: () => listTagsForAsset(assetId),
      fingerprint: tagListFingerprint,
    );
  }

  @override
  Future<List<domain.Tag>> listTagsForAsset(String assetId) async {
    final rows = await (db.select(
      db.assetTags,
    )..where((tag) => tag.assetId.equals(assetId))).get();
    final ids = rows.map((row) => row.tagId).toList();
    if (ids.isEmpty) {
      return [];
    }
    final tags = await (db.select(
      db.tags,
    )..where((tag) => tag.id.isIn(ids))).get();
    return tags.map(_tagFromRow).toList();
  }

  Future<List<AssetPhotoRow>> _photoRowsForAssets(List<String> assetIds) async {
    if (assetIds.isEmpty) {
      return [];
    }
    return (db.select(
      db.assetPhotos,
    )..where((photo) => photo.assetId.isIn(assetIds))).get();
  }

  Future<void> _deleteAssetsCascadeInTransaction(List<String> assetIds) async {
    if (assetIds.isEmpty) {
      return;
    }
    final planRows = await (db.select(
      db.maintenancePlans,
    )..where((plan) => plan.assetId.isIn(assetIds))).get();
    await _deletePlansCascade(db, planRows.map((row) => row.id).toList());
    await (db.delete(
      db.assetTags,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.assetPhotos,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.deviceDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.petDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.plantDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.safetyDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(db.assets)..where((row) => row.id.isIn(assetIds))).go();
  }

  Future<void> _deletePhotoFiles(List<AssetPhotoRow> photoRows) async {
    if (photoRows.isEmpty) {
      return;
    }
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final assetIds = <String>{};
      for (final row in photoRows) {
        assetIds.add(row.assetId);
        final file = File(
          p.joinAll([docDir.path, ...row.relativePath.split('/')]),
        );
        if (await file.exists()) {
          await file.delete();
        }
      }
      for (final assetId in assetIds) {
        final dir = Directory(p.join(docDir.path, 'photos', assetId));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {
      // Database cleanup is authoritative; stale photo files should not block it.
    }
  }

  Future<void> _deletePhotoFile(AssetPhotoRow row) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File(
        p.joinAll([docDir.path, ...row.relativePath.split('/')]),
      );
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Database cleanup is authoritative; stale photo files should not block it.
    }
  }

  Future<int> _nextAreaSortOrder() async {
    final rows = await db.select(db.areas).get();
    if (rows.isEmpty) {
      return 0;
    }
    return rows.map((row) => row.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<int> _nextRoomSortOrder(String areaId) async {
    final rows = await (db.select(
      db.rooms,
    )..where((room) => room.areaId.equals(areaId))).get();
    if (rows.isEmpty) {
      return 0;
    }
    return rows.map((row) => row.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _replaceAssetDetails({
    required String assetId,
    required domain.AssetType assetType,
    domain.DeviceDetails? deviceDetails,
    domain.PetDetails? petDetails,
    domain.PlantDetails? plantDetails,
    domain.SafetyDetails? safetyDetails,
  }) async {
    await (db.delete(
      db.deviceDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();
    await (db.delete(
      db.petDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();
    await (db.delete(
      db.plantDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();
    await (db.delete(
      db.safetyDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();

    switch (assetType) {
      case domain.AssetType.device:
        final details = deviceDetails ?? const domain.DeviceDetails();
        await db
            .into(db.deviceDetailsTable)
            .insert(
              DeviceDetailsTableCompanion.insert(
                assetId: assetId,
                brand: Value(_blankToNull(details.brand)),
                model: Value(_blankToNull(details.model)),
                serialNumber: Value(_blankToNull(details.serialNumber)),
                powerSource: Value(details.powerSource?.name),
                warrantyUntil: Value(details.warrantyUntil),
                manualUrl: Value(_blankToNull(details.manualUrl)),
                consumable: Value(_blankToNull(details.consumable)),
              ),
            );
      case domain.AssetType.pet:
        final details = petDetails ?? const domain.PetDetails();
        await db
            .into(db.petDetailsTable)
            .insert(
              PetDetailsTableCompanion.insert(
                assetId: assetId,
                species: Value(_blankToNull(details.species)),
                breed: Value(_blankToNull(details.breed)),
                birthDate: Value(details.birthDate),
                microchipId: Value(_blankToNull(details.microchipId)),
                vetName: Value(_blankToNull(details.vetName)),
                vetPhone: Value(_blankToNull(details.vetPhone)),
                feedingNotes: Value(_blankToNull(details.feedingNotes)),
                medicalNotes: Value(_blankToNull(details.medicalNotes)),
              ),
            );
      case domain.AssetType.plant:
        final details = plantDetails ?? const domain.PlantDetails();
        await db
            .into(db.plantDetailsTable)
            .insert(
              PlantDetailsTableCompanion.insert(
                assetId: assetId,
                species: Value(_blankToNull(details.species)),
                sunlight: Value(details.sunlight?.name),
                wateringIntervalDays: Value(details.wateringIntervalDays),
                potSize: Value(_blankToNull(details.potSize)),
                lastRepottedAt: Value(details.lastRepottedAt),
                toxicityNotes: Value(_blankToNull(details.toxicityNotes)),
              ),
            );
      case domain.AssetType.safety:
        final details = safetyDetails ?? const domain.SafetyDetails();
        await db
            .into(db.safetyDetailsTable)
            .insert(
              SafetyDetailsTableCompanion.insert(
                assetId: assetId,
                safetyType: Value(_blankToNull(details.safetyType)),
                installedAt: Value(details.installedAt),
                expiresAt: Value(details.expiresAt),
                batteryType: Value(_blankToNull(details.batteryType)),
                testIntervalDays: Value(details.testIntervalDays),
              ),
            );
      case domain.AssetType.general:
        break;
    }
  }

  Future<List<domain.Asset>> _hydrateAssetRows(List<AssetRow> rows) async {
    if (rows.isEmpty) {
      return [];
    }
    final ids = rows.map((row) => row.id).toSet().toList();
    final deviceRows = await (db.select(
      db.deviceDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final petRows = await (db.select(
      db.petDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final plantRows = await (db.select(
      db.plantDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final safetyRows = await (db.select(
      db.safetyDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final devices = {
      for (final row in deviceRows) row.assetId: _deviceDetailsFromRow(row),
    };
    final pets = {
      for (final row in petRows) row.assetId: _petDetailsFromRow(row),
    };
    final plants = {
      for (final row in plantRows) row.assetId: _plantDetailsFromRow(row),
    };
    final safetyItems = {
      for (final row in safetyRows) row.assetId: _safetyDetailsFromRow(row),
    };
    return [
      for (final row in rows)
        _assetFromRow(
          row,
          deviceDetails: devices[row.id],
          petDetails: pets[row.id],
          plantDetails: plants[row.id],
          safetyDetails: safetyItems[row.id],
        ),
    ];
  }

  Future<String> _ensureTag(String tagName) async {
    final existing = await db
        .customSelect(
          'SELECT id FROM tags WHERE name = ? COLLATE NOCASE LIMIT 1',
          variables: [Variable.withString(tagName)],
          readsFrom: {db.tags},
        )
        .getSingleOrNull();
    if (existing != null) {
      return existing.read<String>('id');
    }
    final id = _uuid.v7();
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            name: tagName,
            createdAt: Value(DateTime.now()),
          ),
        );
    return id;
  }

  Future<void> _ensureActiveRoom(String roomId) async {
    final room =
        await (db.select(db.rooms)
              ..where((row) => row.id.equals(roomId) & row.archivedAt.isNull()))
            .getSingleOrNull();
    if (room == null) {
      throw StateError('Choose an active room.');
    }
  }
}

class DriftMaintenanceRepository
    implements MaintenanceRepository, CalendarRepository {
  DriftMaintenanceRepository(
    this.db, {
    this._recurrenceEngine = const HomePilotRecurrenceEngine(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase db;
  final RecurrenceEngine _recurrenceEngine;
  final DateTime Function() _now;

  @override
  Stream<List<domain.TaskItem>> watchTasks() {
    return _watchTaskDependencies(listTasks);
  }

  @override
  Stream<List<domain.TaskItem>> watchSavedTasks() {
    return _watchTaskDependencies(
      listSavedTasks,
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Stream<List<domain.TaskItem>> watchArchivedTasks() {
    return _watchTaskDependencies(
      listArchivedTasks,
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Future<List<domain.TaskItem>> listTasks() async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.archivedAt.isNull() & plan.isEnabled.equals(true),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> listSavedTasks() async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where((plan) => plan.archivedAt.isNull())
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> listArchivedTasks() async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where((plan) => plan.archivedAt.isNotNull())
              ..orderBy([(plan) => OrderingTerm.desc(plan.archivedAt)]))
            .get();
    return _hydrateTasks(planRows, includeArchivedAssets: true);
  }

  @override
  Stream<domain.TaskItem?> watchTask(String planId) {
    return _watchTaskDependencies(
      () => getTask(planId),
      fingerprint: (task) => task == null ? 0 : taskFingerprint(task),
    );
  }

  @override
  Future<domain.TaskItem?> getTask(String planId) async {
    final planRow = await (db.select(
      db.maintenancePlans,
    )..where((plan) => plan.id.equals(planId))).getSingleOrNull();
    if (planRow == null) {
      return null;
    }
    return (await _hydrateTasks([planRow])).firstOrNull;
  }

  @override
  Stream<List<domain.TaskItem>> watchTasksForAsset(String assetId) {
    return _watchTaskDependencies(
      () => listTasksForAsset(assetId),
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Stream<List<domain.TaskItem>> watchSavedTasksForAsset(String assetId) {
    return _watchTaskDependencies(
      () => listSavedTasksForAsset(assetId),
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Future<List<domain.TaskItem>> listTasksForAsset(String assetId) async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.assetId.equals(assetId) &
                    plan.archivedAt.isNull() &
                    plan.isEnabled.equals(true),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> listSavedTasksForAsset(String assetId) async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.assetId.equals(assetId) & plan.archivedAt.isNull(),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> tasksBetween(
    DateTime startInclusive,
    DateTime endInclusive,
  ) async {
    final start = dateOnly(startInclusive);
    final end = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
      23,
      59,
      59,
    );
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.archivedAt.isNull() &
                    plan.isEnabled.equals(true) &
                    plan.nextDueDate.isBiggerOrEqualValue(start) &
                    plan.nextDueDate.isSmallerOrEqualValue(end),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<String> savePlan({
    String? id,
    required String assetId,
    required String title,
    String? instructions,
    required domain.RecurrenceRule recurrence,
    required domain.PriorityLevel priority,
    required DateTime nextDueDate,
    required domain.HealthGroup healthGroup,
    int reminderDaysBefore = 0,
    domain.TaskMetadata? metadata,
  }) async {
    final cleanAssetId = assetId.trim();
    final cleanTitle = title.trim();
    await _validatePlanTargetAsset(cleanAssetId);
    if (recurrence.interval < 1) {
      throw const MaintenancePlanValidationException(
        'Task recurrence must be greater than zero.',
        code: 'invalid_recurrence',
      );
    }
    if (cleanTitle.isEmpty) {
      throw const MaintenancePlanValidationException(
        'Task title is required.',
        code: 'missing_title',
      );
    }
    if (reminderDaysBefore < 0) {
      throw const MaintenancePlanValidationException(
        'Reminder lead time cannot be negative.',
        code: 'invalid_reminder',
      );
    }
    final planId = id ?? _uuid.v7();
    final now = _now();
    await db.transaction(() async {
      final existingPlan = await (db.select(
        db.maintenancePlans,
      )..where((plan) => plan.id.equals(planId))).getSingleOrNull();
      if (existingPlan == null) {
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: planId,
                assetId: cleanAssetId,
                title: cleanTitle,
                instructions: Value(_blankToNull(instructions)),
                recurrenceInterval: recurrence.interval,
                recurrenceUnit: recurrence.unit.name,
                priority: priority.name,
                nextDueDate: nextDueDate,
                reminderDaysBefore: Value(reminderDaysBefore),
                healthGroup: healthGroup.name,
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, now);
        }
      } else {
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.id.equals(planId))).write(
          MaintenancePlansCompanion(
            assetId: Value(cleanAssetId),
            title: Value(cleanTitle),
            instructions: Value(_blankToNull(instructions)),
            recurrenceInterval: Value(recurrence.interval),
            recurrenceUnit: Value(recurrence.unit.name),
            priority: Value(priority.name),
            nextDueDate: Value(nextDueDate),
            reminderDaysBefore: Value(reminderDaysBefore),
            healthGroup: Value(healthGroup.name),
            updatedAt: Value(now),
          ),
        );
        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, now);
        }
        await _markPlanInboxRead(planId);
      }
    });
    return planId;
  }

  Future<void> _savePlanMetadata(
    String planId,
    domain.TaskMetadata metadata,
    DateTime now,
  ) async {
    await db
        .into(db.maintenancePlanMetadata)
        .insertOnConflictUpdate(
          MaintenancePlanMetadataCompanion.insert(
            planId: planId,
            taskType: Value(_blankToNull(metadata.taskType)),
            locationLabel: Value(_blankToNull(metadata.locationLabel)),
            estimatedDurationMinutes: Value(metadata.estimatedDurationMinutes),
            requiredMaterialsJson: Value(
              jsonEncode(metadata.requiredMaterials),
            ),
            dependencyPlanIdsJson: Value(
              jsonEncode(metadata.dependencyPlanIds),
            ),
            reminderRecommendation: Value(
              _blankToNull(metadata.reminderRecommendation),
            ),
            sortOrder: Value(metadata.sortOrder),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> _validatePlanTargetAsset(String assetId) async {
    if (assetId.isEmpty) {
      throw const MaintenancePlanValidationException(
        'Suggestion not applied. The related item could not be found.',
        code: 'missing_asset',
      );
    }
    final asset =
        await (db.select(
              db.assets,
            )..where((row) => row.id.equals(assetId) & row.archivedAt.isNull()))
            .getSingleOrNull();
    if (asset == null) {
      throw const MaintenancePlanValidationException(
        'Suggestion not applied. The related item could not be found.',
        code: 'invalid_asset',
      );
    }
  }

  @override
  Future<bool> completePlan(
    String planId, {
    DateTime? completedAt,
    String? notes,
    DateTime? expectedNextDueDate,
  }) async {
    final result = await completePlanResult(
      planId,
      completedAt: completedAt,
      notes: notes,
      expectedNextDueDate: expectedNextDueDate,
    );
    return result.isApplied;
  }

  @override
  Future<LocalMaintenanceCompletionResult> completePlanResult(
    String planId, {
    DateTime? completedAt,
    String? notes,
    DateTime? expectedNextDueDate,
  }) {
    return db.transaction(() async {
      final plan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();
      if (plan == null) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.planUnavailable,
        );
      }
      if (plan.archivedAt != null || !plan.isEnabled) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.planInactive,
        );
      }
      if (expectedNextDueDate != null &&
          !plan.nextDueDate.isAtSameMomentAs(expectedNextDueDate)) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.occurrenceChanged,
        );
      }

      final completed = completedAt ?? _now();
      final previousDueDate = plan.nextDueDate;
      final nextDue = _recurrenceEngine.nextDueDate(
        completed,
        domain.RecurrenceRule(
          interval: plan.recurrenceInterval,
          unit: _recurrenceUnit(plan.recurrenceUnit),
        ),
      );
      final completionId = _uuid.v7();
      final completionNotes = _blankToNull(notes);
      final planUpdatedAt = _now();

      // Identify unresolved predecessor for same plan for CT-003 causal ordering
      final pendingCompletions =
          await (db.select(db.syncOutbox)
                ..where((row) => row.entity.equals('maintenance_completion'))
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
              .get();
      String? predecessorId;
      for (final comp in pendingCompletions) {
        final payloadJson = comp.payloadJson;
        if (payloadJson == null) continue;
        try {
          final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
          final compPlanId =
              decoded['plan_id'] as String? ??
              (decoded['plan'] as Map<String, dynamic>?)?['id'] as String?;
          if (compPlanId == planId) {
            predecessorId = comp.recordKey;
            break;
          }
        } catch (_) {}
      }

      final planShadow =
          await (db.select(db.syncShadows)..where(
                (row) =>
                    row.entity.equals('maintenance_plan') &
                    row.recordKey.equals(planId),
              ))
              .getSingleOrNull();
      final syncAccount = await (db.select(
        db.syncAccount,
      )..where((row) => row.id.equals(1))).getSingleOrNull();

      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
        const SyncRuntimeCompanion(suppressOutbox: Value(true)),
      );
      try {
        await db
            .into(db.maintenanceRecords)
            .insert(
              MaintenanceRecordsCompanion.insert(
                id: completionId,
                planId: planId,
                dueDate: previousDueDate,
                completedAt: Value(completed),
                notes: Value(completionNotes),
              ),
            );

        await (db.update(
          db.maintenancePlans,
        )..where((row) => row.id.equals(planId))).write(
          MaintenancePlansCompanion(
            nextDueDate: Value(nextDue),
            updatedAt: Value(planUpdatedAt),
          ),
        );
      } finally {
        await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
            .write(const SyncRuntimeCompanion(suppressOutbox: Value(false)));
      }

      await _markPlanInboxRead(planId);

      // CT-004 & CT-005: Upsert durable notification reconciliation request
      await db
          .into(db.notificationReconciliationRequests)
          .insertOnConflictUpdate(
            NotificationReconciliationRequestsCompanion.insert(
              scopeKey: 'plan:$planId',
              planId: Value(planId),
              reason: 'local_completion',
              createdAt: Value(planUpdatedAt),
              updatedAt: Value(planUpdatedAt),
            ),
          );

      // Payload v2 with depends_on_operation_id for CT-003 causal ordering
      final payload = jsonEncode({
        'version': 2,
        'operation_id': completionId,
        'idempotency_key': completionId,
        'plan_id': planId,
        'depends_on_operation_id': predecessorId,
        'expected_plan_revision': planShadow?.remoteRevision,
        'expected_next_due_date': previousDueDate.toUtc().toIso8601String(),
        'preimage': {
          'plan': {
            'id': plan.id,
            'asset_id': plan.assetId,
            'title': plan.title,
            'instructions': plan.instructions,
            'recurrence_interval': plan.recurrenceInterval,
            'recurrence_unit': plan.recurrenceUnit,
            'priority': plan.priority,
            'next_due_date': previousDueDate.toUtc().toIso8601String(),
            'reminder_days_before': plan.reminderDaysBefore,
            'is_enabled': plan.isEnabled,
            'health_group': plan.healthGroup,
            'created_at': plan.createdAt.toUtc().toIso8601String(),
            'updated_at': plan.updatedAt.toUtc().toIso8601String(),
            'archived_at': plan.archivedAt?.toUtc().toIso8601String(),
          },
        },
        'plan': {
          'id': plan.id,
          'asset_id': plan.assetId,
          'title': plan.title,
          'instructions': plan.instructions,
          'recurrence_interval': plan.recurrenceInterval,
          'recurrence_unit': plan.recurrenceUnit,
          'priority': plan.priority,
          'next_due_date': nextDue.toUtc().toIso8601String(),
          'reminder_days_before': plan.reminderDaysBefore,
          'is_enabled': plan.isEnabled,
          'health_group': plan.healthGroup,
          'created_at': plan.createdAt.toUtc().toIso8601String(),
          'updated_at': planUpdatedAt.toUtc().toIso8601String(),
          'archived_at': plan.archivedAt?.toUtc().toIso8601String(),
        },
        'record': {
          'id': completionId,
          'plan_id': planId,
          'due_date': previousDueDate.toUtc().toIso8601String(),
          'completed_at': completed.toUtc().toIso8601String(),
          'notes': completionNotes,
        },
      });

      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('maintenance_plan') &
                row.recordKey.equals(planId),
          ))
          .go();

      await db
          .into(db.syncOutbox)
          .insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_completion',
              recordKey: completionId,
              operation: 'execute',
              payloadJson: Value(payload),
              userId: Value(syncAccount?.boundUserId),
              changedAt: Value(planUpdatedAt),
              createdAt: Value(planUpdatedAt),
              state: const Value('pending'),
              attempts: const Value(0),
            ),
          );

      return LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.applied,
        operationId: completionId,
        previousDueDate: previousDueDate,
        nextDueDate: nextDue,
      );
    });
  }

  @override
  Future<void> undoLastCompletion(
    String planId,
    DateTime previousDueDate,
  ) async {
    final latestRecord =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.equals(planId))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (latestRecord == null) {
      return;
    }
    await db.transaction(() async {
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('maintenance_completion') &
                row.recordKey.equals(latestRecord.id),
          ))
          .go();
      await (db.delete(
        db.maintenanceRecords,
      )..where((record) => record.id.equals(latestRecord.id))).go();
      await (db.update(
        db.maintenancePlans,
      )..where((plan) => plan.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(previousDueDate),
          updatedAt: Value(_now()),
        ),
      );
      await _markPlanInboxRead(planId);
    });
  }

  @override
  Future<void> archivePlan(String planId) async {
    await (db.update(
      db.maintenancePlans,
    )..where((plan) => plan.id.equals(planId))).write(
      MaintenancePlansCompanion(
        archivedAt: Value(_now()),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<void> restorePlan(String planId) async {
    final now = _now();
    final plan = await (db.select(
      db.maintenancePlans,
    )..where((row) => row.id.equals(planId))).getSingleOrNull();
    if (plan == null) return;
    final asset = await (db.select(
      db.assets,
    )..where((row) => row.id.equals(plan.assetId))).getSingleOrNull();
    final room = asset == null
        ? null
        : await (db.select(
            db.rooms,
          )..where((row) => row.id.equals(asset.roomId))).getSingleOrNull();
    await db.transaction(() async {
      if (asset != null) {
        await (db.update(
          db.assets,
        )..where((row) => row.id.equals(asset.id))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      if (room != null) {
        await (db.update(
          db.rooms,
        )..where((row) => row.id.equals(room.id))).write(
          RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.areas,
        )..where((row) => row.id.equals(room.areaId))).write(
          AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> setTaskEnabled(String planId, bool enabled) async {
    await db.transaction(() async {
      final plan =
          await (db.select(db.maintenancePlans)..where(
                (row) => row.id.equals(planId) & row.archivedAt.isNull(),
              ))
              .getSingleOrNull();
      if (plan == null || plan.isEnabled == enabled) {
        return;
      }
      final now = _now();
      final recurrence = domain.RecurrenceRule(
        interval: plan.recurrenceInterval,
        unit: _recurrenceUnit(plan.recurrenceUnit),
      );
      final nextDueDate = enabled && !plan.nextDueDate.isAfter(now)
          ? _recurrenceEngine.nextDueDate(now, recurrence)
          : plan.nextDueDate;
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          isEnabled: Value(enabled),
          nextDueDate: Value(nextDueDate),
          updatedAt: Value(now),
        ),
      );
      if (!enabled) {
        await _markPlanInboxRead(planId);
      }
    });
  }

  @override
  Future<void> skipPlanOccurrence(
    String planId, {
    DateTime? skippedAt,
    String? reason,
  }) async {
    await db.transaction(() async {
      final plan =
          await (db.select(db.maintenancePlans)..where(
                (row) =>
                    row.id.equals(planId) &
                    row.archivedAt.isNull() &
                    row.isEnabled.equals(true),
              ))
              .getSingleOrNull();
      if (plan == null) return;
      final nextDue = _recurrenceEngine.nextDueDate(
        plan.nextDueDate,
        domain.RecurrenceRule(
          interval: plan.recurrenceInterval,
          unit: _recurrenceUnit(plan.recurrenceUnit),
        ),
      );
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(nextDue),
          updatedAt: Value(_now()),
        ),
      );
      await _markPlanInboxRead(planId);
      final normalizedReason = _blankToNull(reason);
      await _recordTaskSystemNote(
        planId: planId,
        title: 'Task skipped',
        body: normalizedReason == null
            ? '${plan.title} was skipped for this occurrence.'
            : '${plan.title} was skipped: $normalizedReason',
        dedupeKey:
            'skip:$planId:${(skippedAt ?? _now()).millisecondsSinceEpoch}',
        messageCode: domain.NotificationMessageCode.taskSkipped,
        messageArgs: {'task': plan.title, 'reason': ?normalizedReason},
      );
    });
  }

  @override
  Future<void> postponePlan(
    String planId,
    DateTime nextDueDate, {
    String? reason,
  }) async {
    await db.transaction(() async {
      final plan =
          await (db.select(db.maintenancePlans)..where(
                (row) =>
                    row.id.equals(planId) &
                    row.archivedAt.isNull() &
                    row.isEnabled.equals(true),
              ))
              .getSingleOrNull();
      if (plan == null) return;
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(nextDueDate),
          updatedAt: Value(_now()),
        ),
      );
      await _markPlanInboxRead(planId);
      final normalizedReason = _blankToNull(reason);
      await _recordTaskSystemNote(
        planId: planId,
        title: 'Task postponed',
        body: normalizedReason == null
            ? '${plan.title} was postponed to ${nextDueDate.toLocal()}.'
            : '${plan.title} was postponed: $normalizedReason',
        dedupeKey:
            'postpone:$planId:${nextDueDate.toUtc().millisecondsSinceEpoch}',
        messageCode: domain.NotificationMessageCode.taskPostponed,
        messageArgs: {
          'task': plan.title,
          'date': nextDueDate.toUtc().toIso8601String(),
          'reason': ?normalizedReason,
        },
      );
    });
  }

  @override
  Future<void> deletePlan(String planId) async {
    await db.transaction(() async {
      await _deletePlansCascade(db, [planId]);
    });
  }

  @override
  Stream<List<domain.MaintenanceRecord>> watchRecordsForPlan(String planId) {
    return (db.select(db.maintenanceRecords)
          ..where((record) => record.planId.equals(planId))
          ..orderBy([(record) => OrderingTerm.desc(record.completedAt)]))
        .watch()
        .map((rows) => rows.map(_recordFromRow).toList())
        .distinctByFingerprint(maintenanceRecordListFingerprint);
  }

  @override
  Future<List<domain.MaintenanceRecord>> listRecordsForPlan(
    String planId,
  ) async {
    final rows =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.equals(planId))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)]))
            .get();
    return rows.map(_recordFromRow).toList();
  }

  @override
  Stream<List<domain.MaintenanceRecord>> watchRecordsForAsset(String assetId) {
    return watchReloaded(
      triggers: [
        db.select(db.maintenancePlans).watch(),
        db.select(db.maintenanceRecords).watch(),
      ],
      load: () => listRecordsForAsset(assetId),
      fingerprint: maintenanceRecordListFingerprint,
    );
  }

  @override
  Future<List<domain.MaintenanceRecord>> listRecordsForAsset(
    String assetId,
  ) async {
    final plans = await (db.select(
      db.maintenancePlans,
    )..where((plan) => plan.assetId.equals(assetId))).get();
    final planIds = plans.map((plan) => plan.id).toList();
    if (planIds.isEmpty) {
      return const [];
    }
    final rows =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.isIn(planIds))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)]))
            .get();
    return rows.map(_recordFromRow).toList();
  }

  Future<void> _markPlanInboxRead(String planId) async {
    await (db.update(db.inboxNotifications)
          ..where((row) => row.planId.equals(planId) & row.readAt.isNull()))
        .write(InboxNotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Future<void> _recordTaskSystemNote({
    required String planId,
    required String title,
    required String body,
    required String dedupeKey,
    required domain.NotificationMessageCode messageCode,
    required Map<String, dynamic> messageArgs,
  }) async {
    final now = _now();
    await db
        .into(db.inboxNotifications)
        .insert(
          InboxNotificationsCompanion.insert(
            id: _uuid.v7(),
            title: title,
            body: body,
            kind: 'task',
            route: Value('/maintenance/$planId'),
            planId: Value(planId),
            dedupeKey: Value(dedupeKey),
            messageCode: Value(messageCode.wireValue),
            messageArgs: Value(jsonEncode(messageArgs)),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<List<domain.TaskItem>> _hydrateTasks(
    List<MaintenancePlanRow> planRows, {
    bool includeArchivedAssets = false,
  }) async {
    if (planRows.isEmpty) {
      return [];
    }
    final assetIds = planRows.map((plan) => plan.assetId).toSet().toList();
    final planIds = planRows.map((plan) => plan.id).toList();
    final assetRows =
        await (db.select(db.assets)..where(
              (asset) =>
                  asset.id.isIn(assetIds) &
                  (includeArchivedAssets
                      ? const Constant(true)
                      : asset.archivedAt.isNull()),
            ))
            .get();
    final metadataRows = await (db.select(
      db.maintenancePlanMetadata,
    )..where((metadata) => metadata.planId.isIn(planIds))).get();
    final metadataMap = {for (final row in metadataRows) row.planId: row};
    final assetMap = {for (final row in assetRows) row.id: row};
    final categoryRows = await db.select(db.categories).get();
    final categoryMap = {for (final row in categoryRows) row.id: row};
    final roomRows = await db.select(db.rooms).get();
    final roomMap = {for (final row in roomRows) row.id: row};
    final now = DateTime.now();
    final items = <domain.TaskItem>[];
    for (final plan in planRows) {
      final asset = assetMap[plan.assetId];
      if (asset == null) {
        continue;
      }
      final category = categoryMap[asset.categoryId];
      final room = roomMap[asset.roomId];
      if (category == null || room == null) {
        continue;
      }
      items.add(
        domain.TaskItem(
          plan: _planFromRow(plan, metadataMap[plan.id]),
          asset: _assetFromRow(asset),
          category: _categoryFromRow(category),
          room: _roomFromRow(room),
          status: _statusFor(plan.nextDueDate, now),
        ),
      );
    }
    items.sort((a, b) => a.plan.nextDueDate.compareTo(b.plan.nextDueDate));
    return items;
  }

  Stream<T> _watchTaskDependencies<T>(
    Future<T> Function() loader, {
    int Function(T value)? fingerprint,
  }) {
    return watchReloaded(
      triggers: [
        db.select(db.maintenancePlans).watch(),
        db.select(db.maintenancePlanMetadata).watch(),
        db.select(db.assets).watch(),
        db.select(db.categories).watch(),
        db.select(db.rooms).watch(),
      ],
      load: loader,
      fingerprint:
          fingerprint ??
          (value) => taskListFingerprint(value as List<domain.TaskItem>),
    );
  }
}

class DriftStatisticsRepository implements StatisticsRepository {
  DriftStatisticsRepository(
    this.db,
    this.maintenanceRepository,
    this.streakService, {
    this._healthScoreCalculator = const WeightedHealthScoreCalculator(),
  });

  final AppDatabase db;
  final MaintenanceRepository maintenanceRepository;
  final StreakService streakService;
  final HealthScoreCalculator _healthScoreCalculator;

  @override
  Future<domain.DashboardSummary> dashboardSummary(DateTime now) async {
    final tasks = await maintenanceRepository.listTasks();
    final buckets = getTaskBuckets(tasks, now);
    final startMonth = startOfMonth(now);
    final endMonth = endOfMonth(now);
    final recordsThisMonth =
        await (db.select(db.maintenanceRecords)..where(
              (record) =>
                  record.completedAt.isBiggerOrEqualValue(startMonth) &
                  record.completedAt.isSmallerOrEqualValue(endMonth),
            ))
            .get();
    final completionRate = _completionRate(
      recordsThisMonth.length,
      buckets.overdueCount,
    );
    return domain.DashboardSummary(
      todayTasks: buckets.todayCount,
      upcomingTasks: buckets.upcomingCount,
      overdueTasks: buckets.overdueCount,
      health: _healthScoreCalculator.calculate(tasks, now),
      streak: await streakService.current(),
      completionRate: completionRate,
      completedThisMonth: recordsThisMonth.length,
    );
  }

  @override
  Stream<domain.DashboardSummary> watchDashboardSummary() {
    return watchReloaded(
      triggers: [
        maintenanceRepository.watchTasks(),
        db.select(db.maintenanceRecords).watch(),
        db.select(db.streaks).watch(),
      ],
      load: () => dashboardSummary(DateTime.now()),
      fingerprint: dashboardSummaryFingerprint,
    );
  }

  @override
  Stream<domain.StatisticsSummary> watchStatisticsSummary() {
    return watchReloaded(
      triggers: [
        maintenanceRepository.watchTasks(),
        db.select(db.maintenanceRecords).watch(),
      ],
      load: () => statisticsSummary(DateTime.now()),
      fingerprint: statisticsSummaryFingerprint,
    );
  }

  @override
  Future<domain.StatisticsSummary> statisticsSummary(DateTime now) async {
    final tasks = await maintenanceRepository.listTasks();
    final buckets = getTaskBuckets(tasks, now);
    final records = await db.select(db.maintenanceRecords).get();
    final completedByMonth = <String, int>{};
    for (final record in records) {
      completedByMonth.update(
        monthKey(record.completedAt),
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final distribution = <domain.HealthGroup, int>{};
    for (final task in tasks) {
      distribution.update(
        task.plan.healthGroup,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return domain.StatisticsSummary(
      completionRate: _completionRate(records.length, buckets.overdueCount),
      overdueRate: tasks.isEmpty ? 0 : buckets.overdueCount / tasks.length,
      completedByMonth: completedByMonth,
      taskDistribution: distribution,
    );
  }

  double _completionRate(int completed, int overdue) {
    final denominator = completed + overdue;
    if (denominator == 0) {
      return 1;
    }
    return completed / denominator;
  }
}

class DriftNotificationInboxRepository implements NotificationInboxRepository {
  DriftNotificationInboxRepository(this.db);

  final AppDatabase db;

  @override
  Stream<List<domain.InboxNotification>> watchNotifications() {
    final query = db.select(db.inboxNotifications)
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch().map((rows) => rows.map(_inboxFromRow).toList());
  }

  @override
  Stream<int> watchUnreadCount() {
    final query = db.select(db.inboxNotifications)
      ..where((row) => row.readAt.isNull());
    return query.watch().map((rows) => rows.length).distinct();
  }

  @override
  Future<List<domain.InboxNotification>> listNotifications() async {
    final rows = await (db.select(
      db.inboxNotifications,
    )..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).get();
    return rows.map(_inboxFromRow).toList();
  }

  @override
  Future<int> unreadCount() async {
    final rows = await (db.select(
      db.inboxNotifications,
    )..where((row) => row.readAt.isNull())).get();
    return rows.length;
  }

  @override
  Future<void> clear() async {
    await db.delete(db.inboxNotifications).go();
  }

  @override
  Future<void> createNotification({
    required String title,
    required String body,
    required String kind,
    String? route,
    String? planId,
    domain.NotificationMessageCode? messageCode,
    Map<String, dynamic> messageArgs = const {},
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty && cleanBody.isEmpty) {
      return;
    }
    final normalizedKind = _blankToNull(kind)?.toLowerCase() ?? 'general';
    final routeValue = _blankToNull(route);
    final planValue = _blankToNull(planId);
    final now = DateTime.now();
    final dedupeKey = _notificationDedupeKey(
      kind: normalizedKind,
      title: cleanTitle,
      body: cleanBody,
      route: routeValue,
      planId: planValue,
      createdAt: now,
    );
    final cutoff = now.subtract(_notificationDedupeWindow(normalizedKind));
    final duplicateQuery = db.select(db.inboxNotifications)
      ..where((row) {
        var predicate =
            row.kind.equals(normalizedKind) &
            row.title.equals(cleanTitle) &
            row.createdAt.isBiggerOrEqualValue(cutoff);
        if (_notificationDedupeIncludesBody(normalizedKind)) {
          predicate = predicate & row.body.equals(cleanBody);
        }
        predicate =
            predicate &
            (routeValue == null
                ? row.route.isNull()
                : row.route.equals(routeValue));
        predicate =
            predicate &
            (planValue == null
                ? row.planId.isNull()
                : row.planId.equals(planValue));
        return predicate;
      })
      ..limit(1);
    if (await duplicateQuery.getSingleOrNull() != null) {
      return;
    }
    await db
        .into(db.inboxNotifications)
        .insert(
          InboxNotificationsCompanion.insert(
            id: dedupeKey,
            title: cleanTitle.isEmpty ? 'HomePilot update' : cleanTitle,
            body: cleanBody,
            kind: normalizedKind,
            route: Value(routeValue),
            planId: Value(planValue),
            messageCode: Value(messageCode?.wireValue),
            messageArgs: Value(jsonEncode(messageArgs)),
            dedupeKey: Value(dedupeKey),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db.customStatement('''
DELETE FROM notification_inbox
WHERE id NOT IN (
  SELECT id
  FROM notification_inbox
  ORDER BY created_at DESC
  LIMIT 250
)
''');
  }

  @override
  Future<void> markRead(String id) async {
    await (db.update(
      db.inboxNotifications,
    )..where((row) => row.id.equals(id))).write(
      InboxNotificationsCompanion(
        readAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> markAllRead() async {
    await (db.update(
      db.inboxNotifications,
    )..where((row) => row.readAt.isNull())).write(
      InboxNotificationsCompanion(
        readAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this.db);

  final AppDatabase db;

  @override
  Future<domain.AppLanguage> appLanguage() async {
    final row = await _setting('app_language');
    return _appLanguage(row?.value);
  }

  @override
  Future<void> setAppLanguage(domain.AppLanguage language) async {
    await setAppLocalePreference(language);
  }

  @override
  Stream<domain.AppLanguage> watchAppLanguage() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('app_language'));
    return query
        .watchSingleOrNull()
        .map((row) => _appLanguage(row?.value))
        .distinct();
  }

  @override
  Future<domain.AppLocalePreference> appLocalePreference() async {
    final rows =
        await (db.select(db.settings)..where(
              (setting) =>
                  setting.key.isIn(['app_language', 'app_language_explicit']),
            ))
            .get();
    return _appLocalePreference(rows);
  }

  @override
  Future<void> setAppLocalePreference(domain.AppLanguage language) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await _setSettingAt('app_language', language.name, now);
      await _setSettingAt('app_language_explicit', 'true', now);
    });
  }

  @override
  Stream<domain.AppLocalePreference> watchAppLocalePreference() {
    final query = db.select(db.settings)
      ..where(
        (setting) =>
            setting.key.isIn(['app_language', 'app_language_explicit']),
      );
    return query.watch().map(_appLocalePreference).distinct();
  }

  @override
  Future<domain.ThemePreference> themePreference() async {
    final row = await _setting('theme');
    return _themePreference(row?.value);
  }

  @override
  Future<void> setThemePreference(domain.ThemePreference preference) async {
    await _setSetting('theme', preference.name);
  }

  @override
  Stream<domain.ThemePreference> watchThemePreference() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('theme'));
    return query
        .watchSingleOrNull()
        .map((row) => _themePreference(row?.value))
        .distinct();
  }

  @override
  Future<bool> timeOfDayThemeEnabled() async {
    final row = await _setting('theme_time_of_day_enabled');
    return _boolSetting(row?.value);
  }

  @override
  Future<void> setTimeOfDayThemeEnabled(bool enabled) {
    return _setSetting('theme_time_of_day_enabled', enabled.toString());
  }

  @override
  Stream<bool> watchTimeOfDayThemeEnabled() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('theme_time_of_day_enabled'));
    return query
        .watchSingleOrNull()
        .map((row) => _boolSetting(row?.value))
        .distinct();
  }

  @override
  Future<bool> onboardingCompleted() async {
    final row = await _setting('onboarding_completed');
    return _boolSetting(row?.value);
  }

  @override
  Future<void> setOnboardingCompleted(bool completed) {
    return _setSetting('onboarding_completed', completed.toString());
  }

  @override
  Stream<bool> watchOnboardingCompleted() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('onboarding_completed'));
    return query.watchSingleOrNull().map((row) => _boolSetting(row?.value));
  }

  @override
  Future<bool> permissionEducationSeen() async {
    final row = await _setting('permission_education_seen_v2');
    return _boolSetting(row?.value);
  }

  @override
  Future<void> setPermissionEducationSeen(bool seen) {
    return _setSetting('permission_education_seen_v2', seen.toString());
  }

  @override
  Stream<bool> watchPermissionEducationSeen() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('permission_education_seen_v2'));
    return query.watchSingleOrNull().map((row) => _boolSetting(row?.value));
  }

  @override
  Future<domain.AppProfile> profile() async {
    return _profileFromValue((await _setting('profile'))?.value);
  }

  @override
  Stream<domain.AppProfile> watchProfile() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('profile'));
    return query
        .watchSingleOrNull()
        .map((row) => _profileFromValue(row?.value))
        .distinct(
          (previous, next) =>
              previous.nickname == next.nickname &&
              previous.displayName == next.displayName &&
              previous.avatarPath == next.avatarPath,
        );
  }

  @override
  Future<void> setProfile({String? nickname}) async {
    final current = _profileFromValue((await _setting('profile'))?.value);
    final resolvedNickname = _blankToNull(nickname);
    final value = <String, Object?>{'nickname': resolvedNickname};
    if (current.displayName.trim().isNotEmpty &&
        current.displayName != 'Home Pilot') {
      value['displayName'] = current.displayName;
    }
    if (current.avatarPath != null) {
      value['avatarPath'] = current.avatarPath;
    }
    await _setSetting('profile', jsonEncode(value));
  }

  @override
  Future<domain.HomeLocation?> homeLocation() async {
    return _locationFromValue((await _setting('home_location'))?.value);
  }

  @override
  Stream<domain.HomeLocation?> watchHomeLocation() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('home_location'));
    return query
        .watchSingleOrNull()
        .map((row) => _locationFromValue(row?.value))
        .distinct(
          (previous, next) =>
              previous?.label == next?.label &&
              previous?.latitude == next?.latitude &&
              previous?.longitude == next?.longitude &&
              previous?.timezone == next?.timezone &&
              previous?.source == next?.source,
        );
  }

  @override
  Future<void> setHomeLocation(domain.HomeLocation? location) async {
    if (location == null) {
      await (db.delete(
        db.settings,
      )..where((setting) => setting.key.equals('home_location'))).go();
      await (db.delete(
        db.settings,
      )..where((setting) => setting.key.equals('weather_cache'))).go();
      return;
    }
    await _setSetting(
      'home_location',
      jsonEncode({
        'label': location.label,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timezone': location.timezone,
        'source': location.source,
      }),
    );
  }

  @override
  Future<domain.NotificationPreferences> notificationPreferences() async {
    final row = await _setting('notification_preferences');
    final legacyRow = await _setting('notifications_enabled');
    return _notificationPreferencesFromValue(
      row?.value,
      legacyEnabled: legacyRow == null ? null : _boolSetting(legacyRow.value),
    );
  }

  @override
  Stream<domain.NotificationPreferences> watchNotificationPreferences() {
    final query = db.select(db.settings)
      ..where(
        (setting) => setting.key.isIn([
          'notification_preferences',
          'notifications_enabled',
        ]),
      );
    return query.watch().map((rows) {
      final byKey = {for (final row in rows) row.key: row.value};
      final legacyValue = byKey['notifications_enabled'];
      return _notificationPreferencesFromValue(
        byKey['notification_preferences'],
        legacyEnabled: legacyValue == null ? null : _boolSetting(legacyValue),
      );
    });
  }

  @override
  Future<void> setNotificationPreferences(
    domain.NotificationPreferences preferences,
  ) async {
    final normalized = _normalizeNotificationPreferences(preferences);
    await _setSetting(
      'notification_preferences',
      jsonEncode(_notificationPreferencesToJson(normalized)),
    );
    await _setSetting('notifications_enabled', normalized.enabled.toString());
  }

  Future<SettingRow?> _setting(String key) {
    return (db.select(
      db.settings,
    )..where((setting) => setting.key.equals(key))).getSingleOrNull();
  }

  Future<void> _setSetting(String key, String value) async {
    await _setSettingAt(key, value, DateTime.now());
  }

  Future<void> _setSettingAt(
    String key,
    String value,
    DateTime updatedAt,
  ) async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(updatedAt),
          ),
        );
  }

  domain.AppProfile _profileFromValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const domain.AppProfile();
    }
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      return domain.AppProfile(
        nickname: _blankToNull(decoded['nickname'] as String?),
        displayName:
            _blankToNull(decoded['displayName'] as String?) ?? 'Home Pilot',
        avatarPath: _blankToNull(decoded['avatarPath'] as String?),
      );
    } catch (_) {
      return const domain.AppProfile();
    }
  }

  domain.HomeLocation? _locationFromValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      final latitude = (decoded['latitude'] as num?)?.toDouble();
      final longitude = (decoded['longitude'] as num?)?.toDouble();
      final label = _blankToNull(decoded['label'] as String?);
      if (latitude == null || longitude == null || label == null) {
        return null;
      }
      return domain.HomeLocation(
        label: label,
        latitude: latitude,
        longitude: longitude,
        timezone: _blankToNull(decoded['timezone'] as String?),
        source: _blankToNull(decoded['source'] as String?) ?? 'manual',
      );
    } catch (_) {
      return null;
    }
  }
}

class DriftSearchRepository implements SearchRepository {
  DriftSearchRepository(this.db);

  final AppDatabase db;

  @override
  Future<void> rebuildIndex() async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM search_index');
      final areaRows = await (db.select(
        db.areas,
      )..where((area) => area.archivedAt.isNull())).get();
      final areaById = {for (final area in areaRows) area.id: area};
      for (final area in areaRows) {
        await _insert('area', area.id, area.name, area.kind);
      }
      for (final room in await (db.select(
        db.rooms,
      )..where((room) => room.archivedAt.isNull())).get()) {
        final areaName = areaById[room.areaId]?.name ?? '';
        await _insert(
          'room',
          room.id,
          room.name,
          '$areaName ${room.roomType} ${room.notes ?? ''}',
        );
      }
      for (final category in await db.select(db.categories).get()) {
        await _insert(
          'category',
          category.id,
          category.name,
          category.healthGroup,
        );
      }
      for (final asset in await (db.select(
        db.assets,
      )..where((asset) => asset.archivedAt.isNull())).get()) {
        await _insert(
          'asset',
          asset.id,
          asset.name,
          '${asset.assetType} ${asset.placement ?? ''} ${asset.notes ?? ''} '
              '${await _assetDetailSearchBody(asset)} '
              '${await _assetTagSearchBody(asset.id)} '
              '${await _assetPhotoSearchBody(asset.id)}',
        );
      }
      for (final tag in await db.select(db.tags).get()) {
        await _insert('tag', tag.id, tag.name, '');
      }
      for (final plan in await (db.select(
        db.maintenancePlans,
      )..where((plan) => plan.archivedAt.isNull())).get()) {
        await _insert('plan', plan.id, plan.title, plan.instructions ?? '');
      }
    });
  }

  @override
  Future<List<domain.SearchResult>> search(String query) async {
    final match = _searchMatch(query);
    if (match == null) {
      return [];
    }
    final rows = await db
        .customSelect(
          "SELECT entity_type, entity_id, title, snippet(search_index, 3, '', '', '...', 12) AS snippet "
          "FROM search_index WHERE search_index MATCH ? ORDER BY rank LIMIT 25",
          variables: [Variable.withString(match)],
          readsFrom: {},
        )
        .get();
    return rows
        .map(
          (row) => domain.SearchResult(
            entityType: row.read<String>('entity_type'),
            entityId: row.read<String>('entity_id'),
            title: row.read<String>('title'),
            snippet: row.read<String>('snippet'),
          ),
        )
        .toList();
  }

  Future<void> _insert(
    String type,
    String id,
    String title,
    String body,
  ) async {
    await db.customStatement(
      'INSERT INTO search_index(entity_type, entity_id, title, body) VALUES (?, ?, ?, ?)',
      [type, id, title, body],
    );
  }

  Future<String> _assetDetailSearchBody(AssetRow asset) async {
    switch (_assetType(asset.assetType)) {
      case domain.AssetType.device:
        final row =
            await (db.select(db.deviceDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [
          row.brand,
          row.model,
          row.serialNumber,
          row.powerSource,
          row.manualUrl,
          row.consumable,
        ].whereType<String>().join(' ');
      case domain.AssetType.pet:
        final row =
            await (db.select(db.petDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [
          row.species,
          row.breed,
          row.microchipId,
          row.vetName,
          row.vetPhone,
          row.feedingNotes,
          row.medicalNotes,
        ].whereType<String>().join(' ');
      case domain.AssetType.plant:
        final row =
            await (db.select(db.plantDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [
          row.species,
          row.sunlight,
          row.potSize,
          row.toxicityNotes,
        ].whereType<String>().join(' ');
      case domain.AssetType.safety:
        final row =
            await (db.select(db.safetyDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [row.safetyType, row.batteryType].whereType<String>().join(' ');
      case domain.AssetType.general:
        return '';
    }
  }

  Future<String> _assetTagSearchBody(String assetId) async {
    final links = await (db.select(
      db.assetTags,
    )..where((tag) => tag.assetId.equals(assetId))).get();
    final tagIds = links.map((link) => link.tagId).toList();
    if (tagIds.isEmpty) {
      return '';
    }
    final tags = await (db.select(
      db.tags,
    )..where((tag) => tag.id.isIn(tagIds))).get();
    return tags.map((tag) => tag.name).join(' ');
  }

  Future<String> _assetPhotoSearchBody(String assetId) async {
    final photos = await (db.select(
      db.assetPhotos,
    )..where((photo) => photo.assetId.equals(assetId))).get();
    return photos.map((photo) => photo.caption).whereType<String>().join(' ');
  }

  String? _searchMatch(String query) {
    final tokens = RegExp(
      r'[A-Za-z0-9]+',
    ).allMatches(query).map((match) => '${match.group(0)}*').toList();
    if (tokens.isEmpty) {
      return null;
    }
    return tokens.join(' ');
  }
}

class DatabaseStreakService implements StreakService {
  DatabaseStreakService(this.db);

  final AppDatabase db;

  @override
  Future<domain.StreakState> current() async {
    final row = await (db.select(
      db.streaks,
    )..where((streak) => streak.id.equals('default'))).getSingleOrNull();
    if (row == null) {
      return domain.StreakState(
        currentStreak: 0,
        bestStreak: 0,
        updatedAt: DateTime.now(),
      );
    }
    return _streakFromRow(row);
  }

  @override
  Future<domain.StreakState> refresh(DateTime now) async {
    final today = dateOnly(now);
    final plans =
        await (db.select(db.maintenancePlans)..where(
              (plan) => plan.archivedAt.isNull() & plan.isEnabled.equals(true),
            ))
            .get();
    final existing = await current();
    final missedObligation = plans.any(
      (plan) => compareDateOnly(plan.nextDueDate, today) < 0,
    );
    if (missedObligation) {
      return _write(
        currentStreak: 0,
        bestStreak: existing.bestStreak,
        lastCompletedDate: existing.lastCompletedDate,
        now: now,
      );
    }

    final tomorrow = today.add(const Duration(days: 1));
    final recordsDueToday =
        await (db.select(db.maintenanceRecords)..where(
              (record) =>
                  record.dueDate.isBiggerOrEqualValue(today) &
                  record.dueDate.isSmallerThanValue(tomorrow),
            ))
            .get();
    final hasOpenDueToday = plans.any(
      (plan) => isSameDate(plan.nextDueDate, today),
    );
    if (recordsDueToday.isEmpty ||
        hasOpenDueToday ||
        isSameDate(existing.lastCompletedDate ?? DateTime(1900), today)) {
      return existing;
    }

    final yesterday = today.subtract(const Duration(days: 1));
    final nextCurrent =
        existing.lastCompletedDate != null &&
            isSameDate(existing.lastCompletedDate!, yesterday)
        ? existing.currentStreak + 1
        : 1;
    return _write(
      currentStreak: nextCurrent,
      bestStreak: nextCurrent > existing.bestStreak
          ? nextCurrent
          : existing.bestStreak,
      lastCompletedDate: today,
      now: now,
    );
  }

  Future<domain.StreakState> _write({
    required int currentStreak,
    required int bestStreak,
    required DateTime? lastCompletedDate,
    required DateTime now,
  }) async {
    await db
        .into(db.streaks)
        .insertOnConflictUpdate(
          StreaksCompanion.insert(
            id: 'default',
            currentStreak: Value(currentStreak),
            bestStreak: Value(bestStreak),
            lastCompletedDate: Value(lastCompletedDate),
            updatedAt: Value(now),
          ),
        );
    return domain.StreakState(
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      lastCompletedDate: lastCompletedDate,
      updatedAt: now,
    );
  }
}

domain.Area _areaFromRow(AreaRow row) => domain.Area(
  id: row.id,
  name: row.name,
  kind: _areaKind(row.kind),
  sortOrder: row.sortOrder,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
);

domain.Room _roomFromRow(RoomRow row) => domain.Room(
  id: row.id,
  areaId: row.areaId,
  name: row.name,
  roomType: _roomType(row.roomType),
  notes: row.notes,
  sortOrder: row.sortOrder,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
);

domain.Category _categoryFromRow(CategoryRow row) => domain.Category(
  id: row.id,
  name: row.name,
  healthGroup: _healthGroup(row.healthGroup),
  iconName: row.iconName,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

domain.Asset _assetFromRow(
  AssetRow row, {
  domain.DeviceDetails? deviceDetails,
  domain.PetDetails? petDetails,
  domain.PlantDetails? plantDetails,
  domain.SafetyDetails? safetyDetails,
}) => domain.Asset(
  id: row.id,
  name: row.name,
  assetType: _assetType(row.assetType),
  categoryId: row.categoryId,
  roomId: row.roomId,
  placement: row.placement,
  notes: row.notes,
  purchaseDate: row.purchaseDate,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
  deviceDetails: deviceDetails,
  petDetails: petDetails,
  plantDetails: plantDetails,
  safetyDetails: safetyDetails,
);

domain.DeviceDetails _deviceDetailsFromRow(DeviceDetailRow row) =>
    domain.DeviceDetails(
      brand: row.brand,
      model: row.model,
      serialNumber: row.serialNumber,
      powerSource: row.powerSource == null
          ? null
          : _powerSource(row.powerSource!),
      warrantyUntil: row.warrantyUntil,
      manualUrl: row.manualUrl,
      consumable: row.consumable,
    );

domain.PetDetails _petDetailsFromRow(PetDetailRow row) => domain.PetDetails(
  species: row.species,
  breed: row.breed,
  birthDate: row.birthDate,
  microchipId: row.microchipId,
  vetName: row.vetName,
  vetPhone: row.vetPhone,
  feedingNotes: row.feedingNotes,
  medicalNotes: row.medicalNotes,
);

domain.PlantDetails _plantDetailsFromRow(PlantDetailRow row) =>
    domain.PlantDetails(
      species: row.species,
      sunlight: row.sunlight == null ? null : _sunlight(row.sunlight!),
      wateringIntervalDays: row.wateringIntervalDays,
      potSize: row.potSize,
      lastRepottedAt: row.lastRepottedAt,
      toxicityNotes: row.toxicityNotes,
    );

domain.SafetyDetails _safetyDetailsFromRow(SafetyDetailRow row) =>
    domain.SafetyDetails(
      safetyType: row.safetyType,
      installedAt: row.installedAt,
      expiresAt: row.expiresAt,
      batteryType: row.batteryType,
      testIntervalDays: row.testIntervalDays,
    );

domain.Tag _tagFromRow(TagRow row) =>
    domain.Tag(id: row.id, name: row.name, createdAt: row.createdAt);

domain.AssetPhoto _photoFromRow(AssetPhotoRow row) => domain.AssetPhoto(
  id: row.id,
  assetId: row.assetId,
  relativePath: row.relativePath,
  isPrimary: row.isPrimary,
  caption: row.caption,
  createdAt: row.createdAt,
);

domain.InboxNotification _inboxFromRow(InboxNotificationRow row) =>
    domain.InboxNotification(
      id: row.id,
      title: row.title,
      body: row.body,
      kind: row.kind,
      route: row.route,
      planId: row.planId,
      messageCode: row.messageCode,
      messageArgs: _notificationMessageArgs(row.messageArgs),
      readAt: row.readAt,
      createdAt: row.createdAt,
    );

Map<String, dynamic> _notificationMessageArgs(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, item) => MapEntry(key.toString(), item));
    }
  } on FormatException {
    // Older or damaged local records degrade to an empty argument object.
  }
  return const {};
}

domain.MaintenancePlan _planFromRow(
  MaintenancePlanRow row, [
  MaintenancePlanMetadataRow? metadata,
]) => domain.MaintenancePlan(
  id: row.id,
  assetId: row.assetId,
  title: row.title,
  instructions: row.instructions,
  recurrence: domain.RecurrenceRule(
    interval: row.recurrenceInterval,
    unit: _recurrenceUnit(row.recurrenceUnit),
  ),
  priority: _priority(row.priority),
  nextDueDate: row.nextDueDate,
  reminderDaysBefore: row.reminderDaysBefore,
  isEnabled: row.isEnabled,
  metadata: metadata == null
      ? null
      : domain.TaskMetadata(
          taskType: metadata.taskType,
          locationLabel: metadata.locationLabel,
          estimatedDurationMinutes: metadata.estimatedDurationMinutes,
          requiredMaterials: _stringListFromJson(
            metadata.requiredMaterialsJson,
          ),
          dependencyPlanIds: _stringListFromJson(
            metadata.dependencyPlanIdsJson,
          ),
          reminderRecommendation: metadata.reminderRecommendation,
          sortOrder: metadata.sortOrder,
        ),
  healthGroup: _healthGroup(row.healthGroup),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
);

List<String> _stringListFromJson(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded
          .map((item) => item.toString())
          .where((item) {
            return item.trim().isNotEmpty;
          })
          .toList(growable: false);
    }
  } on Object {
    return const [];
  }
  return const [];
}

domain.MaintenanceRecord _recordFromRow(MaintenanceRecordRow row) =>
    domain.MaintenanceRecord(
      id: row.id,
      planId: row.planId,
      dueDate: row.dueDate,
      completedAt: row.completedAt,
      notes: row.notes,
    );

domain.StreakState _streakFromRow(StreakRow row) => domain.StreakState(
  currentStreak: row.currentStreak,
  bestStreak: row.bestStreak,
  lastCompletedDate: row.lastCompletedDate,
  updatedAt: row.updatedAt,
);

domain.TaskStatus _statusFor(DateTime dueDate, DateTime now) =>
    activeTaskStatusForDueDate(dueDate, now);

domain.HealthGroup _healthGroup(String value) {
  return domain.HealthGroup.values
          .where((group) => group.name == value)
          .firstOrNull ??
      domain.HealthGroup.other;
}

domain.AreaKind _areaKind(String value) {
  return domain.AreaKind.values
          .where((kind) => kind.name == value)
          .firstOrNull ??
      domain.AreaKind.indoor;
}

domain.RoomType _roomType(String value) {
  return domain.RoomType.values
          .where((type) => type.name == value)
          .firstOrNull ??
      domain.RoomType.other;
}

domain.AssetType _assetType(String value) {
  return domain.AssetType.values
          .where((type) => type.name == value)
          .firstOrNull ??
      domain.AssetType.general;
}

domain.PowerSource _powerSource(String value) {
  return domain.PowerSource.values
          .where((source) => source.name == value)
          .firstOrNull ??
      domain.PowerSource.other;
}

domain.Sunlight _sunlight(String value) {
  return domain.Sunlight.values
          .where((sunlight) => sunlight.name == value)
          .firstOrNull ??
      domain.Sunlight.medium;
}

domain.RecurrenceUnit _recurrenceUnit(String value) {
  return domain.RecurrenceUnit.values
          .where((unit) => unit.name == value)
          .firstOrNull ??
      domain.RecurrenceUnit.months;
}

domain.PriorityLevel _priority(String value) {
  return domain.PriorityLevel.values
          .where((priority) => priority.name == value)
          .firstOrNull ??
      domain.PriorityLevel.medium;
}

domain.ThemePreference _themePreference(String? value) {
  return domain.ThemePreference.values
          .where((preference) => preference.name == value)
          .firstOrNull ??
      domain.ThemePreference.system;
}

domain.AppLanguage _appLanguage(String? value) {
  return domain.AppLanguage.values
          .where((language) => language.name == value)
          .firstOrNull ??
      domain.AppLanguage.en;
}

domain.AppLocalePreference _appLocalePreference(List<SettingRow> rows) {
  final languageRow = rows
      .where((row) => row.key == 'app_language')
      .firstOrNull;
  final explicitRow = rows
      .where((row) => row.key == 'app_language_explicit')
      .firstOrNull;
  final updatedAt =
      [
        if (languageRow != null) languageRow.updatedAt,
        if (explicitRow != null) explicitRow.updatedAt,
      ].fold<DateTime>(
        DateTime.fromMillisecondsSinceEpoch(0),
        (latest, value) => value.isAfter(latest) ? value : latest,
      );
  return domain.AppLocalePreference(
    language: _appLanguage(languageRow?.value),
    isExplicit: _boolSetting(explicitRow?.value),
    updatedAt: updatedAt,
  );
}

bool _boolSetting(String? value) => value == 'true';

domain.NotificationPreferences _notificationPreferencesFromValue(
  String? value, {
  bool? legacyEnabled,
}) {
  final defaults = domain.NotificationPreferences(
    enabled: legacyEnabled ?? true,
  );
  if (value == null || value.trim().isEmpty) {
    return defaults;
  }
  try {
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return _normalizeNotificationPreferences(
      defaults.copyWith(
        enabled: _jsonBool(decoded, 'enabled'),
        localReminders: _jsonBool(decoded, 'localReminders'),
        inAppInbox: _jsonBool(decoded, 'inAppInbox'),
        weatherAlerts: _jsonBool(decoded, 'weatherAlerts'),
        quietHoursEnabled: _jsonBool(decoded, 'quietHoursEnabled'),
        quietHoursStartMinutes: _jsonInt(decoded, 'quietHoursStartMinutes'),
        quietHoursEndMinutes: _jsonInt(decoded, 'quietHoursEndMinutes'),
        criticalBypassQuietHours: _jsonBool(
          decoded,
          'criticalBypassQuietHours',
        ),
        privacyMode: _jsonBool(decoded, 'privacyMode'),
        dailyDigest: _jsonBool(decoded, 'dailyDigest'),
        digestHour: _jsonInt(decoded, 'digestHour'),
        reminderHour: _jsonInt(decoded, 'reminderHour'),
        maxRemindersPerDay: _jsonInt(decoded, 'maxRemindersPerDay'),
        defaultSnoozeMinutes: _jsonInt(decoded, 'defaultSnoozeMinutes'),
        preferExactReminders: _jsonBool(decoded, 'preferExactReminders'),
      ),
    );
  } catch (_) {
    return defaults;
  }
}

domain.NotificationPreferences _normalizeNotificationPreferences(
  domain.NotificationPreferences preferences,
) {
  return preferences.copyWith(
    quietHoursStartMinutes: _clampInt(
      preferences.quietHoursStartMinutes,
      0,
      1439,
    ),
    quietHoursEndMinutes: _clampInt(preferences.quietHoursEndMinutes, 0, 1439),
    digestHour: _clampInt(preferences.digestHour, 0, 23),
    reminderHour: _clampInt(preferences.reminderHour, 0, 23),
    maxRemindersPerDay: _clampInt(preferences.maxRemindersPerDay, 1, 24),
    defaultSnoozeMinutes: _clampInt(
      preferences.defaultSnoozeMinutes,
      5,
      60 * 24 * 7,
    ),
  );
}

Map<String, Object> _notificationPreferencesToJson(
  domain.NotificationPreferences preferences,
) {
  final normalized = _normalizeNotificationPreferences(preferences);
  return {
    'enabled': normalized.enabled,
    'localReminders': normalized.localReminders,
    'inAppInbox': normalized.inAppInbox,
    'weatherAlerts': normalized.weatherAlerts,
    'quietHoursEnabled': normalized.quietHoursEnabled,
    'quietHoursStartMinutes': normalized.quietHoursStartMinutes,
    'quietHoursEndMinutes': normalized.quietHoursEndMinutes,
    'criticalBypassQuietHours': normalized.criticalBypassQuietHours,
    'privacyMode': normalized.privacyMode,
    'dailyDigest': normalized.dailyDigest,
    'digestHour': normalized.digestHour,
    'reminderHour': normalized.reminderHour,
    'maxRemindersPerDay': normalized.maxRemindersPerDay,
    'defaultSnoozeMinutes': normalized.defaultSnoozeMinutes,
    'preferExactReminders': normalized.preferExactReminders,
  };
}

bool? _jsonBool(Map<String, dynamic> decoded, String key) {
  final value = decoded[key];
  return value is bool ? value : null;
}

int? _jsonInt(Map<String, dynamic> decoded, String key) {
  final value = decoded[key];
  return value is num ? value.round() : null;
}

int _clampInt(int value, int min, int max) => value.clamp(min, max).toInt();

Duration _notificationDedupeWindow(String kind) {
  return switch (kind) {
    'weather' => const Duration(hours: 12),
    'task' => const Duration(hours: 20),
    'digest' => const Duration(hours: 20),
    _ => const Duration(hours: 2),
  };
}

bool _notificationDedupeIncludesBody(String kind) {
  return switch (kind) {
    'weather' || 'task' || 'digest' => false,
    _ => true,
  };
}

String _notificationDedupeKey({
  required String kind,
  required String title,
  required String body,
  required String? route,
  required String? planId,
  required DateTime createdAt,
}) {
  final window = _notificationDedupeWindow(kind);
  final bucket =
      createdAt.toUtc().millisecondsSinceEpoch ~/ window.inMilliseconds;
  final canonical = jsonEncode([
    kind,
    title.trim(),
    _notificationDedupeIncludesBody(kind) ? body.trim() : '',
    route ?? '',
    planId ?? '',
    bucket,
  ]);
  return sha256.convert(utf8.encode(canonical)).toString();
}

String? _blankToNull(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => DriftMaintenanceRepository(ref.watch(databaseProvider)),
);
