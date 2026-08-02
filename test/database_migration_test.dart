import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/core/data/repositories.dart';
import 'package:homepilot/src/core/database/app_database.dart';
import 'package:homepilot/src/core/domain/models.dart';

void main() {
  test('v22 creates the device-local reminder schedule snapshot', () async {
    final file = File(
      '${Directory.systemTemp.path}/homepilot_reminder_schedule_migration_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    final original = AppDatabase(executor: NativeDatabase(file));
    AppDatabase? migrated;
    try {
      await original.customSelect('SELECT 1').get();
      await original.customStatement('DROP TABLE reminder_schedule_snapshot');
      await original.customStatement('PRAGMA user_version = 21');
      await original.close();

      migrated = AppDatabase(executor: NativeDatabase(file));
      final columns = await migrated
          .customSelect('PRAGMA table_info(reminder_schedule_snapshot)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        containsAll([
          'identity',
          'notification_id',
          'scheduled_at',
          'timezone',
          'schedule_mode',
          'content_version',
        ]),
      );
    } finally {
      await migrated?.close();
      if (await file.exists()) await file.delete();
    }
  });

  test(
    'v19 migration preserves notifications and marks legacy Arabic explicit',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/homepilot_locale_notification_migration_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      var originalClosed = false;
      final original = AppDatabase(executor: NativeDatabase(file));
      AppDatabase? migrated;
      try {
        await original
            .into(original.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                key: 'app_language',
                value: 'ar',
                updatedAt: Value(DateTime.utc(2026, 7, 22)),
              ),
            );
        await original
            .into(original.inboxNotifications)
            .insert(
              InboxNotificationsCompanion.insert(
                id: 'legacy-notification',
                title: 'Legacy title',
                body: 'Legacy body',
                kind: 'system',
              ),
            );
        await original.customStatement(
          "DELETE FROM settings WHERE key = 'app_language_explicit'",
        );
        await original.customStatement(
          'ALTER TABLE notification_inbox DROP COLUMN message_code',
        );
        await original.customStatement(
          'ALTER TABLE notification_inbox DROP COLUMN message_args',
        );
        await original.customStatement('PRAGMA user_version = 18');
        await original.close();
        originalClosed = true;

        migrated = AppDatabase(executor: NativeDatabase(file));
        await migrated.customSelect('SELECT 1').get();

        final preference = await DriftSettingsRepository(
          migrated,
        ).appLocalePreference();
        final notification = await migrated
            .select(migrated.inboxNotifications)
            .getSingle();
        expect(preference.language, AppLanguage.ar);
        expect(preference.isExplicit, isTrue);
        expect(notification.title, 'Legacy title');
        expect(notification.messageCode, isNull);
        expect(notification.messageArgs, '{}');
      } finally {
        if (!originalClosed) await original.close();
        await migrated?.close();
        if (await file.exists()) await file.delete();
      }
    },
  );

  test(
    'v18 migration defaults existing maintenance plans to enabled',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/homepilot_enabled_migration_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      var originalClosed = false;
      final original = AppDatabase(executor: NativeDatabase(file));
      AppDatabase? migrated;
      try {
        final assets = DriftAssetRepository(original);
        final maintenance = DriftMaintenanceRepository(original);
        await assets.saveArea(
          id: 'area_first_floor',
          name: 'First Floor',
          kind: AreaKind.indoor,
          sortOrder: 0,
        );
        final roomId = await assets.saveRoom(
          areaId: 'area_first_floor',
          name: 'Migration laundry',
        );
        final assetId = await assets.saveAsset(
          name: 'Migration washer',
          categoryId: 'category_general',
          roomId: roomId,
        );
        final planId = await maintenance.savePlan(
          assetId: assetId,
          title: 'Existing plan',
          recurrence: const RecurrenceRule(
            interval: 1,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 1, 1),
          healthGroup: HealthGroup.other,
        );

        await original.customStatement(
          'DROP INDEX IF EXISTS idx_plans_enabled_due',
        );
        await original.customStatement(
          'ALTER TABLE maintenance_plans DROP COLUMN is_enabled',
        );
        await original.customStatement('PRAGMA user_version = 17');
        await original.close();
        originalClosed = true;

        migrated = AppDatabase(executor: NativeDatabase(file));
        await migrated.customSelect('SELECT 1').get();

        final task = await DriftMaintenanceRepository(migrated).getTask(planId);
        final columns = await migrated
            .customSelect('PRAGMA table_info(maintenance_plans)')
            .get();

        expect(
          columns.map((row) => row.read<String>('name')),
          contains('is_enabled'),
        );
        expect(task?.plan.isEnabled, isTrue);
        expect(
          (await DriftMaintenanceRepository(
            migrated,
          ).listTasks()).map((task) => task.plan.id),
          contains(planId),
        );
      } finally {
        if (!originalClosed) await original.close();
        await migrated?.close();
        if (await file.exists()) await file.delete();
      }
    },
  );

  test('v7 and v8 migrations preserve data and queue expanded sync', () async {
    final file = File(
      '${Directory.systemTemp.path}/homepilot_tag_migration_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    var originalClosed = false;
    final original = AppDatabase(executor: NativeDatabase(file));
    AppDatabase? migrated;
    try {
      final repository = DriftAssetRepository(original);
      await repository.saveArea(
        id: 'area_first_floor',
        name: 'First Floor',
        kind: AreaKind.indoor,
        sortOrder: 0,
      );
      final roomId = await repository.saveRoom(
        areaId: 'area_first_floor',
        name: 'Migration room',
      );
      final firstAssetId = await repository.saveAsset(
        name: 'First migration asset',
        categoryId: 'category_general',
        roomId: roomId,
      );
      final secondAssetId = await repository.saveAsset(
        name: 'Second migration asset',
        categoryId: 'category_general',
        roomId: roomId,
      );
      await original.customStatement('DROP INDEX idx_tags_name_nocase');
      final createdAt = DateTime.utc(2026, 6, 28);
      await original
          .into(original.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-a',
              name: 'Home',
              createdAt: Value(createdAt),
            ),
          );
      await original
          .into(original.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-b',
              name: 'home',
              createdAt: Value(createdAt),
            ),
          );
      await original
          .into(original.assetTags)
          .insert(
            AssetTagsCompanion.insert(assetId: firstAssetId, tagId: 'tag-a'),
          );
      await original
          .into(original.assetTags)
          .insert(
            AssetTagsCompanion.insert(assetId: secondAssetId, tagId: 'tag-b'),
          );
      await original
          .into(original.syncAccount)
          .insert(
            const SyncAccountCompanion(
              id: Value(1),
              deviceId: Value('migration-test-device'),
              lastError: Value(
                'A cloud record kept changing during synchronization.',
              ),
            ),
          );
      await original
          .into(original.inboxNotifications)
          .insert(
            InboxNotificationsCompanion.insert(
              id: 'legacy-inbox',
              title: 'Existing notification',
              body: 'Preserve me',
              kind: 'system',
              createdAt: Value(createdAt),
            ),
          );
      await original.customStatement('DROP INDEX idx_inbox_dedupe');
      await original.customStatement(
        'ALTER TABLE notification_inbox DROP COLUMN dedupe_key',
      );
      await original.customStatement(
        'ALTER TABLE notification_inbox DROP COLUMN updated_at',
      );
      await original.delete(original.syncOutbox).go();
      await original.customStatement('PRAGMA user_version = 6');
      await original.close();
      originalClosed = true;

      migrated = AppDatabase(executor: NativeDatabase(file));
      await migrated.customSelect('SELECT 1').get();

      final tags = await migrated.select(migrated.tags).get();
      final relations = await migrated.select(migrated.assetTags).get();
      final syncAccount = await migrated
          .select(migrated.syncAccount)
          .getSingle();
      final inbox = await migrated
          .select(migrated.inboxNotifications)
          .getSingle();
      final pendingEntities = (await migrated.select(migrated.syncOutbox).get())
          .map((row) => row.entity)
          .toSet();
      final syncTriggers = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'trigger' AND name LIKE 'sync_%'",
          )
          .get();
      expect(
        tags.where((tag) => tag.name.toLowerCase() == 'home'),
        hasLength(1),
      );
      expect(
        relations.where((relation) => relation.tagId == 'tag-a'),
        hasLength(2),
      );
      expect(relations.where((relation) => relation.tagId == 'tag-b'), isEmpty);
      expect(syncAccount.lastError, isNull);
      expect(inbox.dedupeKey, 'legacy:legacy-inbox');
      expect(inbox.updatedAt.toUtc(), createdAt);
      expect(
        pendingEntities,
        containsAll({'notification_inbox', 'user_setting', 'streak'}),
      );
      expect(
        syncTriggers.map((row) => row.read<String>('name')),
        isNot(contains('sync_settings_insert')),
      );
    } finally {
      if (!originalClosed) await original.close();
      await migrated?.close();
      if (await file.exists()) await file.delete();
    }
  });
}
