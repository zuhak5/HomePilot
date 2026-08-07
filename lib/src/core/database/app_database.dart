import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';

part 'app_database.g.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

@DataClassName('AreaRow')
class Areas extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get kind => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RoomRow')
class Rooms extends Table {
  TextColumn get id => text()();
  TextColumn get areaId => text().references(Areas, #id)();
  TextColumn get name => text()();
  TextColumn get roomType => text().withDefault(const Constant('other'))();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {areaId, name},
  ];
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get healthGroup => text()();
  TextColumn get iconName => text().withDefault(const Constant('home'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get assetType => text().withDefault(const Constant('general'))();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get roomId => text().references(Rooms, #id)();
  TextColumn get placement => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DeviceDetailRow')
class DeviceDetailsTable extends Table {
  @override
  String get tableName => 'device_details';

  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get brand => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get powerSource => text().nullable()();
  DateTimeColumn get warrantyUntil => dateTime().nullable()();
  TextColumn get manualUrl => text().nullable()();
  TextColumn get consumable => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('PetDetailRow')
class PetDetailsTable extends Table {
  @override
  String get tableName => 'pet_details';

  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get species => text().nullable()();
  TextColumn get breed => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get microchipId => text().nullable()();
  TextColumn get vetName => text().nullable()();
  TextColumn get vetPhone => text().nullable()();
  TextColumn get feedingNotes => text().nullable()();
  TextColumn get medicalNotes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('PlantDetailRow')
class PlantDetailsTable extends Table {
  @override
  String get tableName => 'plant_details';

  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get species => text().nullable()();
  TextColumn get sunlight => text().nullable()();
  IntColumn get wateringIntervalDays => integer().nullable()();
  TextColumn get potSize => text().nullable()();
  DateTimeColumn get lastRepottedAt => dateTime().nullable()();
  TextColumn get toxicityNotes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('SafetyDetailRow')
class SafetyDetailsTable extends Table {
  @override
  String get tableName => 'safety_details';

  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get safetyType => text().nullable()();
  DateTimeColumn get installedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get batteryType => text().nullable()();
  IntColumn get testIntervalDays => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssetTagRow')
class AssetTags extends Table {
  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column<Object>> get primaryKey => {assetId, tagId};
}

@DataClassName('AssetPhotoRow')
class AssetPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get relativePath => text()();
  TextColumn get caption => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenancePlanRow')
class MaintenancePlans extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get title => text()();
  TextColumn get instructions => text().nullable()();
  IntColumn get recurrenceInterval => integer()();
  TextColumn get recurrenceUnit => text()();
  TextColumn get priority => text()();
  DateTimeColumn get nextDueDate => dateTime()();
  IntColumn get reminderDaysBefore =>
      integer().withDefault(const Constant(0))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get healthGroup => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenancePlanMetadataRow')
class MaintenancePlanMetadata extends Table {
  TextColumn get planId => text().references(MaintenancePlans, #id)();
  TextColumn get taskType => text().nullable()();
  TextColumn get locationLabel => text().nullable()();
  IntColumn get estimatedDurationMinutes => integer().nullable()();
  TextColumn get requiredMaterialsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get dependencyPlanIdsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get reminderRecommendation => text().nullable()();
  IntColumn get sortOrder => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {planId};
}

@DataClassName('MaintenanceRecordRow')
class MaintenanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get planId => text().references(MaintenancePlans, #id)();
  DateTimeColumn get dueDate => dateTime()();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('NotificationRow')
class AppNotifications extends Table {
  @override
  String get tableName => 'notifications';

  TextColumn get id => text()();
  TextColumn get planId => text().references(MaintenancePlans, #id)();
  TextColumn get channel => text()();
  DateTimeColumn get scheduledFor => dateTime()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('InboxNotificationRow')
class InboxNotifications extends Table {
  @override
  String get tableName => 'notification_inbox';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get kind => text()();
  TextColumn get route => text().nullable()();
  TextColumn get planId =>
      text().nullable().references(MaintenancePlans, #id)();
  TextColumn get messageCode => text().nullable()();
  TextColumn get messageArgs => text().withDefault(const Constant('{}'))();
  TextColumn get dedupeKey => text().withDefault(const Constant(''))();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('StreakRow')
class Streaks extends Table {
  TextColumn get id => text()();
  IntColumn get currentStreak => integer().withDefault(const Constant(0))();
  IntColumn get bestStreak => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastCompletedDate => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncOutbox extends Table {
  @override
  String get tableName => 'offline_mutation_queue';

  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().nullable()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entity, recordKey};
}

class ReminderScheduleSnapshots extends Table {
  @override
  String get tableName => 'reminder_schedule_snapshot';

  TextColumn get identity => text()();
  IntColumn get notificationId => integer().unique()();
  TextColumn get planRevision => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get timezone => text()();
  TextColumn get localComponents => text()();
  TextColumn get scheduleMode => text()();
  TextColumn get contentVersion => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {identity};
}

@DataClassName('NotificationReconciliationRequestRow')
class NotificationReconciliationRequests extends Table {
  @override
  String get tableName => 'notification_reconciliation_requests';

  TextColumn get scopeKey => text()();
  TextColumn get planId => text().nullable()();
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorMessage => text().nullable()();
  BoolColumn get requiresFullRebuild =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {scopeKey};
}

class SyncCursors extends Table {
  @override
  String get tableName => 'sync_cursors';

  TextColumn get entity => text()();
  IntColumn get lastSyncSeq => integer().withDefault(const Constant(0))();
  TextColumn get lastRecordKey => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entity};
}

class SyncShadows extends Table {
  @override
  String get tableName => 'sync_shadows';

  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  IntColumn get remoteRevision => integer()();
  DateTimeColumn get remoteModifiedAt => dateTime().nullable()();
  TextColumn get payloadHash => text().nullable()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {entity, recordKey};
}

class SyncRuntime extends Table {
  @override
  String get tableName => 'sync_runtime';

  IntColumn get id => integer()();
  BoolColumn get suppressOutbox =>
      boolean().withDefault(const Constant(false))();
  TextColumn get leaseOwner => text().nullable()();
  DateTimeColumn get leaseExpiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncMediaCleanup extends Table {
  @override
  String get tableName => 'sync_media_cleanup';

  TextColumn get objectPath => text()();
  TextColumn get userId => text()();
  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {objectPath};
}

class SyncAccount extends Table {
  @override
  String get tableName => 'sync_account';

  IntColumn get id => integer()();
  TextColumn get deviceId => text()();
  TextColumn get boundUserId => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get migrationState =>
      text().withDefault(const Constant('localOnly'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastSyncFailureAt => dateTime().nullable()();
  DateTimeColumn get lastIntegrityCheckAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get blockedReason => text().nullable()();
  BoolColumn get restorePending =>
      boolean().withDefault(const Constant(false))();
  TextColumn get backgroundResult => text().nullable()();
  TextColumn get hydrationRunId => text().nullable()();
  TextColumn get hydrationState => text().nullable()();
  TextColumn get hydrationStage => text().nullable()();
  IntColumn get hydrationCompletedUnits =>
      integer().withDefault(const Constant(0))();
  IntColumn get hydrationTotalUnits =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get hydrationStartedAt => dateTime().nullable()();
  DateTimeColumn get hydrationUpdatedAt => dateTime().nullable()();
  TextColumn get hydrationError => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Areas,
    Rooms,
    Categories,
    Assets,
    DeviceDetailsTable,
    PetDetailsTable,
    PlantDetailsTable,
    SafetyDetailsTable,
    Tags,
    AssetTags,
    AssetPhotos,
    MaintenancePlans,
    MaintenancePlanMetadata,
    MaintenanceRecords,
    AppNotifications,
    InboxNotifications,
    Settings,
    Streaks,
    SyncOutbox,
    ReminderScheduleSnapshots,
    SyncCursors,
    SyncShadows,
    SyncRuntime,
    SyncMediaCleanup,
    SyncAccount,
    NotificationReconciliationRequests,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor})
    : super(executor ?? _openDatabaseConnection());

  static const databaseName = 'homepilot';
  static const databaseFileName = '$databaseName.sqlite';
  static const currentSchemaVersion = 24;
  static const _sqliteBusyTimeoutMs = 8000;
  static const _startupRecoveryAttempts = 5;

  static QueryExecutor _openDatabaseConnection() {
    return driftDatabase(
      name: databaseName,
      native: const DriftNativeOptions(
        shareAcrossIsolates: true,
        setup: _configureNativeSqlite,
      ),
    );
  }

  static void _configureNativeSqlite(CommonDatabase db) {
    db.execute('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
    db.execute('PRAGMA foreign_keys = ON');
  }

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  StreamQueryUpdateRules get streamUpdateRules => StreamQueryUpdateRules([
    for (final table in [
      'areas',
      'rooms',
      'assets',
      'device_details',
      'pet_details',
      'plant_details',
      'safety_details',
      'tags',
      'asset_tags',
      'asset_photos',
      'maintenance_plans',
      'maintenance_plan_metadata',
      'maintenance_records',
      'notifications',
      'notification_inbox',
      'settings',
      'streaks',
    ])
      WritePropagation(
        on: TableUpdateQuery.onTableName(table),
        result: const [TableUpdate('offline_mutation_queue')],
      ),
  ]);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _upgradeToV2(m);
      }
      if (from < 3) {
        await _upgradeToV3(m);
      }
      if (from < 4) {
        await _upgradeToV4(m);
      }
      if (from < 5) {
        await _upgradeToV5(m);
      }
      if (from < 6) {
        await _upgradeToV6(m);
      }
      if (from < 7) {
        await _upgradeToV7();
      }
      if (from < 8) {
        await _upgradeToV8(m);
      }
      if (from < 9) {
        await _upgradeToV9(m);
      }
      if (from < 10) {
        await _upgradeToV10(m);
      }
      if (from < 11) {
        await _upgradeToV11(m);
      }
      if (from < 12) {
        await _upgradeToV12(m);
      }
      if (from < 13) {
        await _upgradeToV13();
      }
      if (from < 15) {
        await _upgradeToV15();
      }
      if (from < 16) {
        await _upgradeToV16();
      }
      if (from < 17) {
        await _upgradeToV17(m);
      }
      if (from < 18) {
        await _upgradeToV18(m);
      }
      if (from < 19) {
        await _upgradeToV19(m);
      }
      if (from < 20) {
        await _upgradeToV20(m);
      }
      if (from < 21) {
        await _upgradeToV21(m);
      }
      if (from < 22) {
        await _upgradeToV22(m);
      }
      if (from < 23) {
        await _upgradeToV23(m);
      }
      if (from < 24) {
        await _upgradeToV24(m);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs');
      await customStatement('PRAGMA foreign_keys = ON');
      await _createIndexes();
      await _createSearchIndex();
      await _seedSyncRuntime();
      await _recoverExpiredSyncRuntimeLease();
      await _createSyncTriggers();
      await _seedDefaults();
    },
  );

  Future<void> _upgradeToV2(Migrator m) async {
    await m.createTable(areas);
    await m.createTable(deviceDetailsTable);
    await m.createTable(petDetailsTable);
    await m.createTable(plantDetailsTable);
    await m.createTable(safetyDetailsTable);
    await m.addColumn(assets, assets.assetType);
    await m.addColumn(assets, assets.placement);

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'INSERT OR IGNORE INTO areas(id, name, kind, sort_order, created_at, updated_at) '
      'VALUES '
      "('area_first_floor', 'First Floor', 'indoor', 0, $now, $now), "
      "('area_second_floor', 'Second Floor', 'indoor', 1, $now, $now), "
      "('area_outdoor_garden', 'Outdoor', 'outdoor', 2, $now, $now)",
    );

    await customStatement('PRAGMA foreign_keys = OFF');
    await customStatement('''
CREATE TABLE rooms_new (
  id TEXT NOT NULL PRIMARY KEY,
  area_id TEXT NOT NULL REFERENCES areas(id),
  name TEXT NOT NULL,
  room_type TEXT NOT NULL DEFAULT 'other',
  notes TEXT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER)),
  updated_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER)),
  archived_at INTEGER NULL,
  UNIQUE(area_id, name)
)
''');
    await customStatement('''
INSERT INTO rooms_new(
  id,
  area_id,
  name,
  room_type,
  notes,
  sort_order,
  created_at,
  updated_at,
  archived_at
)
SELECT
  id,
  CASE WHEN lower(name) = 'garden' THEN 'area_outdoor_garden' ELSE 'area_first_floor' END,
  name,
  CASE
    WHEN lower(name) = 'kitchen' THEN 'kitchen'
    WHEN lower(name) = 'garden' THEN 'garden'
    ELSE 'other'
  END,
  NULL,
  CASE
    WHEN lower(name) = 'general' THEN 0
    WHEN lower(name) = 'kitchen' THEN 1
    WHEN lower(name) = 'garden' THEN 0
    ELSE 10
  END,
  created_at,
  updated_at,
  NULL
FROM rooms
''');
    await customStatement('DROP TABLE rooms');
    await customStatement('ALTER TABLE rooms_new RENAME TO rooms');
    await customStatement('PRAGMA foreign_keys = ON');

    await customStatement('''
UPDATE assets
SET asset_type = COALESCE(
  (
    SELECT CASE categories.health_group
      WHEN 'appliances' THEN 'device'
      WHEN 'pets' THEN 'pet'
      WHEN 'plants' THEN 'plant'
      WHEN 'safety' THEN 'safety'
      ELSE 'general'
    END
    FROM categories
    WHERE categories.id = assets.category_id
  ),
  'general'
)
''');
  }

  Future<void> _upgradeToV3(Migrator m) async {
    await m.addColumn(assetPhotos, assetPhotos.isPrimary);
    await m.createTable(inboxNotifications);
    await customStatement(
      "UPDATE areas SET name = 'Outdoor', updated_at = CAST(strftime('%s', 'now') AS INTEGER) "
      "WHERE id = 'area_outdoor_garden' OR name = 'Outdoor Garden'",
    );
    await customStatement('''
UPDATE asset_photos
SET is_primary = 1
WHERE id IN (
  SELECT first_photo.id
  FROM asset_photos first_photo
  WHERE first_photo.created_at = (
    SELECT MIN(other_photo.created_at)
    FROM asset_photos other_photo
    WHERE other_photo.asset_id = first_photo.asset_id
  )
)
''');
  }

  Future<void> _upgradeToV4(Migrator _) async {}

  Future<void> _upgradeToV18(Migrator m) async {
    if (!await _columnExists('maintenance_plans', 'is_enabled')) {
      await m.addColumn(maintenancePlans, maintenancePlans.isEnabled);
    }
  }

  Future<void> _upgradeToV19(Migrator m) async {
    if (!await _columnExists('notification_inbox', 'message_code')) {
      await m.addColumn(inboxNotifications, inboxNotifications.messageCode);
    }
    if (!await _columnExists('notification_inbox', 'message_args')) {
      await m.addColumn(inboxNotifications, inboxNotifications.messageArgs);
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement('''
INSERT OR IGNORE INTO settings(key, value, updated_at)
SELECT
  'app_language_explicit',
  CASE WHEN value = 'ar' THEN 'true' ELSE 'false' END,
  COALESCE(updated_at, $now)
FROM settings
WHERE key = 'app_language'
''');
    await customStatement(
      "INSERT OR IGNORE INTO settings(key, value, updated_at) "
      "VALUES ('app_language_explicit', 'false', $now)",
    );
  }

  Future<void> _upgradeToV20(Migrator m) async {
    if (!await _columnExists('offline_mutation_queue', 'payload_json')) {
      await m.addColumn(syncOutbox, syncOutbox.payloadJson);
    }
  }

  Future<void> _upgradeToV21(Migrator m) async {
    if (!await _columnExists('offline_mutation_queue', 'user_id')) {
      await m.addColumn(syncOutbox, syncOutbox.userId);
    }
    if (!await _columnExists('offline_mutation_queue', 'created_at')) {
      await m.addColumn(syncOutbox, syncOutbox.createdAt);
      await customStatement('''
UPDATE offline_mutation_queue
SET created_at = changed_at
WHERE created_at IS NULL
''');
    }
    if (!await _columnExists('offline_mutation_queue', 'state')) {
      await m.addColumn(syncOutbox, syncOutbox.state);
    }
    if (!await _columnExists('offline_mutation_queue', 'last_error_code')) {
      await m.addColumn(syncOutbox, syncOutbox.lastErrorCode);
    }
    await customStatement('''
UPDATE offline_mutation_queue
SET state = CASE
  WHEN attempts < 0 THEN 'failedVisible'
  ELSE 'pending'
END
WHERE state NOT IN (
  'pending',
  'inFlight',
  'conflictRecovery',
  'failedVisible'
)
''');
  }

  Future<void> _upgradeToV22(Migrator m) async {
    if (!await _hasTable(reminderScheduleSnapshots.actualTableName)) {
      await m.createTable(reminderScheduleSnapshots);
    }
  }

  Future<void> _upgradeToV23(Migrator m) async {
    if (!await _columnExists('sync_account', 'last_integrity_check_at')) {
      await m.addColumn(syncAccount, syncAccount.lastIntegrityCheckAt);
    }
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  Future<void> _upgradeToV5(Migrator _) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      "INSERT OR IGNORE INTO settings(key, value, updated_at) "
      "VALUES ('app_language', 'en', $now)",
    );
  }

  Future<void> _upgradeToV6(Migrator m) async {
    await m.createTable(syncOutbox);
    await m.createTable(syncCursors);
    await m.createTable(syncShadows);
    await m.createTable(syncRuntime);
    await m.createTable(syncAccount);
  }

  Future<void> _upgradeToV7() async {
    // Cloud tag names are unique case-insensitively. Older local databases
    // allowed "Home" and "home" to have different IDs, so merge those IDs
    // before enforcing the same rule locally. Existing sync triggers preserve
    // the required relationship upserts and tombstones in the outbox.
    await transaction(() async {
      await customStatement('''
INSERT OR IGNORE INTO asset_tags(asset_id, tag_id)
SELECT
  asset_tags.asset_id,
  (
    SELECT MIN(canonical.id)
    FROM tags AS canonical
    WHERE lower(canonical.name) = lower(duplicate.name)
  )
FROM asset_tags
JOIN tags AS duplicate ON duplicate.id = asset_tags.tag_id
WHERE duplicate.id <> (
  SELECT MIN(canonical.id)
  FROM tags AS canonical
  WHERE lower(canonical.name) = lower(duplicate.name)
)
''');
      await customStatement('''
DELETE FROM asset_tags
WHERE tag_id IN (
  SELECT duplicate.id
  FROM tags AS duplicate
  WHERE duplicate.id <> (
    SELECT MIN(canonical.id)
    FROM tags AS canonical
    WHERE lower(canonical.name) = lower(duplicate.name)
  )
)
''');
      await customStatement('''
DELETE FROM tags
WHERE id <> (
  SELECT MIN(canonical.id)
  FROM tags AS canonical
  WHERE lower(canonical.name) = lower(tags.name)
)
''');
      await customStatement('UPDATE sync_account SET last_error = NULL');
    });
  }

  Future<void> _upgradeToV8(Migrator _) async {
    await customStatement('''
CREATE TABLE notification_inbox_v8 (
  id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  kind TEXT NOT NULL,
  route TEXT NULL,
  plan_id TEXT NULL REFERENCES maintenance_plans(id),
  dedupe_key TEXT NOT NULL DEFAULT '',
  read_at INTEGER NULL,
  created_at INTEGER NOT NULL
    DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  updated_at INTEGER NOT NULL
    DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
)
''');
    await customStatement('''
INSERT INTO notification_inbox_v8(
  id,
  title,
  body,
  kind,
  route,
  plan_id,
  dedupe_key,
  read_at,
  created_at,
  updated_at
)
SELECT
  id,
  title,
  body,
  kind,
  route,
  plan_id,
  'legacy:' || id,
  read_at,
  created_at,
  COALESCE(read_at, created_at)
FROM notification_inbox
''');
    await customStatement('DROP TABLE notification_inbox');
    await customStatement(
      'ALTER TABLE notification_inbox_v8 RENAME TO notification_inbox',
    );
    await customStatement('''
UPDATE notification_inbox
SET
  dedupe_key = 'legacy:' || id,
  updated_at = COALESCE(read_at, created_at)
''');

    final oldTriggers = await customSelect(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'trigger' AND name LIKE 'sync_%'",
    ).get();
    for (final row in oldTriggers) {
      final name = row.read<String>('name').replaceAll('"', '""');
      await customStatement('DROP TRIGGER IF EXISTS "$name"');
    }

    await transaction(() async {
      await _enqueueV8Snapshot(
        entity: 'device_notification',
        table: 'notifications',
        keyExpression: 'id',
        modifiedExpression: 'COALESCE(delivered_at, created_at)',
      );
      await _enqueueV8Snapshot(
        entity: 'notification_inbox',
        table: 'notification_inbox',
        keyExpression: 'id',
        modifiedExpression: 'updated_at',
      );
      await _enqueueV8Snapshot(
        entity: 'user_setting',
        table: 'settings',
        keyExpression: 'key',
        modifiedExpression: 'updated_at',
        where:
            "key IN ('theme', 'app_language', 'app_language_explicit', "
            "'theme_time_of_day_enabled', "
            "'notifications_enabled', 'notification_preferences', "
            "'onboarding_completed', 'permission_education_seen', "
            "'permission_education_seen_v2', "
            "'home_location')",
      );
      await _enqueueV8Snapshot(
        entity: 'device_setting',
        table: 'settings',
        keyExpression: 'key',
        modifiedExpression: 'updated_at',
        where: "key IN ('weather_cache')",
      );
      await _enqueueV8Snapshot(
        entity: 'streak',
        table: 'streaks',
        keyExpression: 'id',
        modifiedExpression: 'updated_at',
      );
    });
  }

  Future<void> _upgradeToV9(Migrator m) async {
    if (!await _hasColumn('sync_runtime', 'lease_owner')) {
      await m.addColumn(syncRuntime, syncRuntime.leaseOwner);
    }
    if (!await _hasColumn('sync_runtime', 'lease_expires_at')) {
      await m.addColumn(syncRuntime, syncRuntime.leaseExpiresAt);
    }
    if (!await _hasTable('sync_media_cleanup')) {
      await m.createTable(syncMediaCleanup);
    }
    if (!await _hasColumn('sync_account', 'migration_state')) {
      await m.addColumn(syncAccount, syncAccount.migrationState);
    }
    if (!await _hasColumn('sync_account', 'last_sync_attempt_at')) {
      await m.addColumn(syncAccount, syncAccount.lastSyncAttemptAt);
    }
    if (!await _hasColumn('sync_account', 'last_sync_failure_at')) {
      await m.addColumn(syncAccount, syncAccount.lastSyncFailureAt);
    }
    if (!await _hasColumn('sync_account', 'blocked_reason')) {
      await m.addColumn(syncAccount, syncAccount.blockedReason);
    }
    if (!await _hasColumn('sync_account', 'restore_pending')) {
      await m.addColumn(syncAccount, syncAccount.restorePending);
    }
    if (!await _hasColumn('sync_account', 'background_result')) {
      await m.addColumn(syncAccount, syncAccount.backgroundResult);
    }
  }

  Future<void> _upgradeToV10(Migrator _) async {}

  Future<void> _upgradeToV11(Migrator m) async {
    await m.createTable(maintenancePlanMetadata);
  }

  Future<void> _upgradeToV12(Migrator _) async {}

  Future<void> _upgradeToV13() async {
    await transaction(() async {
      await _dropLegacyAiSyncTriggers();
      await _stripLegacyAiNotificationPreferences();
      await customStatement('''
DELETE FROM offline_mutation_queue
WHERE entity IN (
  'ai_provider_setting',
  'device_ai_provider_status',
  'ai_usage_log'
)
''');
      await customStatement('''
DELETE FROM sync_shadows
WHERE entity IN (
  'ai_provider_setting',
  'device_ai_provider_status',
  'ai_usage_log'
)
''');
      await customStatement('''
DELETE FROM sync_cursors
WHERE entity IN (
  'ai_provider_setting',
  'device_ai_provider_status',
  'ai_usage_log'
)
''');
      await customStatement('DROP TABLE IF EXISTS ai_chat_messages');
      await customStatement('DROP TABLE IF EXISTS ai_conversations');
      await customStatement('DROP TABLE IF EXISTS ai_usage_logs');
      await customStatement('DROP TABLE IF EXISTS ai_providers');
      await customStatement(
        'DROP TABLE IF EXISTS dynamic_content_translations',
      );
    });
  }

  Future<void> _upgradeToV15() async {
    const legacyOutboxTable =
        'sync'
        '_outbox';
    if (await _hasTable(legacyOutboxTable) &&
        !await _hasTable('offline_mutation_queue')) {
      await customStatement(
        'ALTER TABLE $legacyOutboxTable RENAME TO offline_mutation_queue',
      );
    }
  }

  Future<void> _upgradeToV16() async {
    await customStatement('''
DELETE FROM offline_mutation_queue
WHERE entity IN ('maintenance_session', 'maintenance_session_task')
''');
    await customStatement('''
DELETE FROM sync_shadows
WHERE entity IN ('maintenance_session', 'maintenance_session_task')
''');
    await customStatement('''
DELETE FROM sync_cursors
WHERE entity IN ('maintenance_session', 'maintenance_session_task')
''');
    await customStatement('DROP TABLE IF EXISTS maintenance_session_tasks');
    await customStatement('DROP TABLE IF EXISTS maintenance_sessions');
  }

  Future<void> _upgradeToV17(Migrator m) async {
    if (!await _hasColumn('sync_cursors', 'last_record_key')) {
      await m.addColumn(syncCursors, syncCursors.lastRecordKey);
    }
    for (final column in <GeneratedColumn<Object>>[
      syncAccount.hydrationRunId,
      syncAccount.hydrationState,
      syncAccount.hydrationStage,
      syncAccount.hydrationCompletedUnits,
      syncAccount.hydrationTotalUnits,
      syncAccount.hydrationStartedAt,
      syncAccount.hydrationUpdatedAt,
      syncAccount.hydrationError,
    ]) {
      if (!await _hasColumn('sync_account', column.$name)) {
        await m.addColumn(syncAccount, column);
      }
    }
  }

  Future<void> _upgradeToV24(Migrator m) async {
    await m.createTable(notificationReconciliationRequests);
  }

  Future<void> _dropLegacyAiSyncTriggers() async {
    const triggers = [
      'sync_ai_usage_logs_ai_usage_log_insert',
      'sync_ai_usage_logs_ai_usage_log_update',
      'sync_ai_usage_logs_ai_usage_log_delete',
      'sync_ai_providers_ai_provider_setting_insert',
      'sync_ai_providers_ai_provider_setting_update',
      'sync_ai_providers_ai_provider_setting_delete',
      'sync_ai_providers_device_ai_provider_status_insert',
      'sync_ai_providers_device_ai_provider_status_update',
      'sync_ai_providers_device_ai_provider_status_delete',
    ];
    for (final trigger in triggers) {
      await customStatement('DROP TRIGGER IF EXISTS "$trigger"');
    }
  }

  Future<void> _stripLegacyAiNotificationPreferences() async {
    final row = await customSelect(
      "SELECT value FROM settings WHERE key = 'notification_preferences' LIMIT 1",
    ).getSingleOrNull();
    final value = row?.read<String>('value');
    if (value == null || value.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final removedText = decoded.remove('aiNotificationTextEnabled') != null;
      final removedStyle = decoded.remove('aiNotificationStyle') != null;
      if (!removedText && !removedStyle) {
        return;
      }
      await customUpdate(
        'UPDATE settings SET value = ?, updated_at = ? WHERE key = ?',
        variables: [
          Variable.withString(jsonEncode(decoded)),
          Variable<DateTime>(DateTime.now()),
          Variable.withString('notification_preferences'),
        ],
        updates: {settings},
      );
    } catch (_) {
      return;
    }
  }

  Future<bool> _hasTable(String table) async {
    final rows = await customSelect(
      'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
      variables: [Variable.withString('table'), Variable.withString(table)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  Future<void> _enqueueV8Snapshot({
    required String entity,
    required String table,
    required String keyExpression,
    required String modifiedExpression,
    String? where,
  }) {
    return customStatement('''
INSERT INTO offline_mutation_queue(
  entity,
  record_key,
  operation,
  changed_at,
  attempts,
  next_attempt_at,
  last_error
)
SELECT
  '$entity',
  CAST($keyExpression AS TEXT),
  'upsert',
  COALESCE($modifiedExpression, CAST(strftime('%s', 'now') AS INTEGER)),
  0,
  NULL,
  NULL
FROM $table
WHERE ${where ?? '1 = 1'}
ON CONFLICT(entity, record_key) DO UPDATE SET
  operation = excluded.operation,
  changed_at = excluded.changed_at,
  attempts = 0,
  next_attempt_at = NULL,
  last_error = NULL
''');
  }

  Future<void> _seedSyncRuntime() async {
    await into(syncRuntime).insert(
      SyncRuntimeCompanion.insert(id: const Value(1)),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> _recoverExpiredSyncRuntimeLease() {
    return _withStartupDatabaseRetry(() async {
      final now = DateTime.now();
      await customUpdate(
        '''
UPDATE sync_runtime
SET suppress_outbox = 0,
    lease_owner = NULL,
    lease_expires_at = NULL
WHERE id = 1
  AND (
    lease_owner IS NULL
    OR lease_expires_at IS NULL
    OR lease_expires_at <= ?
  )
''',
        variables: [Variable<DateTime>(now)],
        updates: {syncRuntime},
        updateKind: UpdateKind.update,
      );
    });
  }

  Future<T> _withStartupDatabaseRetry<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 0; attempt < _startupRecoveryAttempts; attempt++) {
      try {
        return await action();
      } on Object catch (error) {
        lastError = error;
        if (!_isSqliteBusy(error) || attempt == _startupRecoveryAttempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 80 * (attempt + 1) * (attempt + 1)),
        );
      }
    }
    throw StateError('Startup database recovery failed: $lastError');
  }

  bool _isSqliteBusy(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('database is locked') ||
        message.contains('database table is locked') ||
        message.contains('sqlite_busy') ||
        message.contains('sqlite_locked');
  }

  Future<void> _createSyncTriggers() async {
    const specs = <(String, String, String)>[
      ('areas', 'area', 'id'),
      ('rooms', 'room', 'id'),
      ('assets', 'asset', 'id'),
      ('device_details', 'device_detail', 'asset_id'),
      ('pet_details', 'pet_detail', 'asset_id'),
      ('plant_details', 'plant_detail', 'asset_id'),
      ('safety_details', 'safety_detail', 'asset_id'),
      ('tags', 'tag', 'id'),
      ('asset_tags', 'asset_tag', "asset_id || '|' || tag_id"),
      ('asset_photos', 'asset_photo', 'id'),
      ('maintenance_plans', 'maintenance_plan', 'id'),
      ('maintenance_plan_metadata', 'maintenance_plan_metadata', 'plan_id'),
      ('maintenance_records', 'maintenance_record', 'id'),
      ('notifications', 'device_notification', 'id'),
      ('notification_inbox', 'notification_inbox', 'id'),
      ('streaks', 'streak', 'id'),
    ];
    for (final (table, entity, keyExpression) in specs) {
      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'INSERT',
        rowPrefix: 'NEW',
        operation: 'upsert',
      );
      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'UPDATE',
        rowPrefix: 'NEW',
        operation: 'upsert',
      );
      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'DELETE',
        rowPrefix: 'OLD',
        operation: 'delete',
      );
    }

    await _createSyncTrigger(
      table: 'settings',
      entity: 'profile',
      keyExpression: "'profile'",
      event: 'INSERT',
      rowPrefix: 'NEW',
      operation: 'upsert',
      extraWhen: "NEW.key = 'profile'",
    );
    await _createSyncTrigger(
      table: 'settings',
      entity: 'profile',
      keyExpression: "'profile'",
      event: 'UPDATE',
      rowPrefix: 'NEW',
      operation: 'upsert',
      extraWhen: "NEW.key = 'profile'",
    );
    await _createSyncTrigger(
      table: 'settings',
      entity: 'profile',
      keyExpression: "'profile'",
      event: 'DELETE',
      rowPrefix: 'OLD',
      operation: 'delete',
      extraWhen: "OLD.key = 'profile'",
    );

    const userSettingKeys =
        "'theme', 'app_language', 'app_language_explicit', 'theme_time_of_day_enabled', "
        "'notifications_enabled', "
        "'notification_preferences', 'onboarding_completed', "
        "'permission_education_seen', 'permission_education_seen_v2', "
        "'home_location'";
    const deviceSettingKeys = "'weather_cache'";
    for (final (entity, keys) in [
      ('user_setting', userSettingKeys),
      ('device_setting', deviceSettingKeys),
    ]) {
      for (final (event, rowPrefix, operation) in [
        ('INSERT', 'NEW', 'upsert'),
        ('UPDATE', 'NEW', 'upsert'),
        ('DELETE', 'OLD', 'delete'),
      ]) {
        await _createSyncTrigger(
          table: 'settings',
          entity: entity,
          keyExpression: 'key',
          event: event,
          rowPrefix: rowPrefix,
          operation: operation,
          extraWhen: "$rowPrefix.key IN ($keys)",
        );
      }
    }
  }

  Future<void> _createSyncTrigger({
    required String table,
    required String entity,
    required String keyExpression,
    required String event,
    required String rowPrefix,
    required String operation,
    String? extraWhen,
  }) async {
    final normalizedEvent = event.toLowerCase();
    final triggerName = 'sync_${table}_${entity}_$normalizedEvent';
    final key = keyExpression.contains('||') || keyExpression.startsWith("'")
        ? keyExpression
        : '$rowPrefix.$keyExpression';
    final compositeKey = keyExpression.contains('||')
        ? keyExpression
              .split(RegExp(r'\s+'))
              .map((part) {
                if (part == 'asset_id' ||
                    part == 'tag_id' ||
                    part == 'session_id' ||
                    part == 'plan_id') {
                  return '$rowPrefix.$part';
                }
                return part;
              })
              .join(' ')
        : key;
    final conditions = [
      'COALESCE((SELECT suppress_outbox FROM sync_runtime WHERE id = 1), 0) = 0',
      ?extraWhen,
    ].join(' AND ');
    await customStatement('DROP TRIGGER IF EXISTS $triggerName');
    await customStatement('''
CREATE TRIGGER $triggerName
AFTER $event ON $table
WHEN $conditions
BEGIN
  INSERT INTO offline_mutation_queue(
    entity,
    record_key,
    operation,
    changed_at,
    attempts,
    next_attempt_at,
    last_error
  )
  VALUES (
    '$entity',
    $compositeKey,
    '$operation',
    CAST(strftime('%s', 'now') AS INTEGER),
    0,
    NULL,
    NULL
  )
  ON CONFLICT(entity, record_key) DO UPDATE SET
    operation = excluded.operation,
    changed_at = excluded.changed_at,
    attempts = 0,
    next_attempt_at = NULL,
    last_error = NULL;
END
''');
  }

  Future<void> _createIndexes() async {
    final statements = [
      'CREATE INDEX IF NOT EXISTS idx_areas_sort ON areas(sort_order, name)',
      'CREATE INDEX IF NOT EXISTS idx_areas_archived ON areas(archived_at)',
      'CREATE INDEX IF NOT EXISTS idx_rooms_area ON rooms(area_id)',
      'CREATE INDEX IF NOT EXISTS idx_rooms_name ON rooms(name)',
      'CREATE INDEX IF NOT EXISTS idx_rooms_archived ON rooms(archived_at)',
      'CREATE INDEX IF NOT EXISTS idx_categories_group ON categories(health_group)',
      'CREATE INDEX IF NOT EXISTS idx_assets_category ON assets(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_assets_room ON assets(room_id)',
      'CREATE INDEX IF NOT EXISTS idx_assets_type ON assets(asset_type)',
      'CREATE INDEX IF NOT EXISTS idx_assets_archived ON assets(archived_at)',
      'CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_nocase '
          'ON tags(name COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_asset_tags_asset ON asset_tags(asset_id)',
      'CREATE INDEX IF NOT EXISTS idx_asset_tags_tag ON asset_tags(tag_id)',
      'CREATE INDEX IF NOT EXISTS idx_asset_photos_asset ON asset_photos(asset_id)',
      'CREATE INDEX IF NOT EXISTS idx_asset_photos_primary ON asset_photos(asset_id, is_primary)',
      'CREATE INDEX IF NOT EXISTS idx_plans_asset ON maintenance_plans(asset_id)',
      'CREATE INDEX IF NOT EXISTS idx_plans_enabled_due '
          'ON maintenance_plans(is_enabled, next_due_date)',
      'CREATE INDEX IF NOT EXISTS idx_plans_due ON maintenance_plans(next_due_date)',
      'CREATE INDEX IF NOT EXISTS idx_plans_group ON maintenance_plans(health_group)',
      'CREATE INDEX IF NOT EXISTS idx_plan_metadata_sort '
          'ON maintenance_plan_metadata(sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_records_plan ON maintenance_records(plan_id)',
      'CREATE INDEX IF NOT EXISTS idx_records_completed ON maintenance_records(completed_at)',
      'CREATE INDEX IF NOT EXISTS idx_notifications_plan ON notifications(plan_id)',
      'CREATE INDEX IF NOT EXISTS idx_notifications_scheduled ON notifications(scheduled_for)',
      'CREATE INDEX IF NOT EXISTS idx_inbox_unread ON notification_inbox(read_at, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_inbox_plan ON notification_inbox(plan_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_inbox_dedupe '
          "ON notification_inbox(dedupe_key) WHERE dedupe_key <> ''",
      'CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key)',
      'CREATE INDEX IF NOT EXISTS idx_streaks_updated ON streaks(updated_at)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  Future<void> _createSearchIndex() async {
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
      'entity_type UNINDEXED, entity_id UNINDEXED, title, body)',
    );
  }

  Future<void> _seedDefaults() async {
    final now = DateTime.now();
    await batch((batch) {
      batch.insertAll(categories, [
        _categorySeed(
          'category_safety',
          'Safety',
          HealthGroup.safety,
          'shield',
          now,
        ),
        _categorySeed('category_pets', 'Pets', HealthGroup.pets, 'pets', now),
        _categorySeed(
          'category_appliances',
          'Appliances',
          HealthGroup.appliances,
          'kitchen',
          now,
        ),
        _categorySeed(
          'category_plants',
          'Plants',
          HealthGroup.plants,
          'yard',
          now,
        ),
        _categorySeed(
          'category_cleaning',
          'Cleaning',
          HealthGroup.cleaning,
          'cleaning_services',
          now,
        ),
        _categorySeed(
          'category_general',
          'General',
          HealthGroup.other,
          'home',
          now,
        ),
      ], mode: InsertMode.insertOrIgnore);
      batch.insertAll(settings, [
        SettingsCompanion.insert(
          key: 'theme',
          value: ThemePreference.system.name,
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'app_language',
          value: AppLanguage.en.name,
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'app_language_explicit',
          value: 'false',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'theme_time_of_day_enabled',
          value: 'false',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'notifications_enabled',
          value: 'true',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'onboarding_completed',
          value: 'false',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'permission_education_seen',
          value: 'false',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'permission_education_seen_v2',
          value: 'false',
          updatedAt: Value(now),
        ),
      ], mode: InsertMode.insertOrIgnore);
      batch.insertAll(streaks, [
        StreaksCompanion.insert(id: 'default', updatedAt: Value(now)),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  CategoriesCompanion _categorySeed(
    String id,
    String name,
    HealthGroup group,
    String iconName,
    DateTime now,
  ) {
    return CategoriesCompanion.insert(
      id: id,
      name: name,
      healthGroup: group.name,
      iconName: Value(iconName),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }
}
