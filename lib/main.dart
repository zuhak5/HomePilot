import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'src/core/config/app_config.dart';
import 'src/core/data/repositories.dart';
import 'src/core/data/reactive_stream.dart';
import 'src/core/database/app_database.dart';
import 'src/core/domain/contracts.dart';
import 'src/core/domain/feature_models.dart' as features;
import 'src/core/domain/models.dart';
import 'src/core/domain/render_fingerprints.dart';
import 'src/core/domain/task_selectors.dart';
import 'src/core/observability/observability_config.dart';
import 'src/core/observability/sentry_bootstrap.dart';
import 'src/core/observability/sentry_navigation.dart';
import 'src/core/services/action_feedback_service.dart';
import 'src/core/services/feedback_messenger.dart';
export 'src/core/data/repositories.dart';
import 'src/core/services/app_permission_coordinator.dart';
import 'src/core/services/backup_service.dart';
import 'src/core/services/diagnostic_export_service.dart';
import 'src/core/services/feature_selectors.dart' as feature_selectors;
import 'src/core/services/health_score_calculator.dart';
import 'src/core/services/notification_service.dart';
import 'src/core/services/reminder_schedule_reconciler.dart';
import 'src/core/services/notification_localization.dart';
import 'src/core/services/weather_service.dart';
import 'src/core/supabase/supabase_bootstrap.dart';
import 'src/core/sync/local_sync_store.dart';
import 'src/core/sync/background_sync_scheduler.dart';
import 'src/core/sync/restore_foreground_service.dart';
import 'src/core/sync/sync_bootstrap.dart';
import 'src/core/sync/sync_coordinator.dart';
import 'src/core/sync/sync_contracts.dart';
import 'src/core/sync/sync_providers.dart';
import 'src/core/utils/app_failure.dart';
import 'src/core/utils/redacting_logger.dart';
import 'src/features/auth/domain/auth_repository.dart';
import 'src/features/auth/data/local_account_data_cleaner.dart';
import 'src/features/auth/presentation/account_screen.dart';
import 'src/features/auth/presentation/authentication_gate.dart';
import 'src/features/auth/presentation/auth_providers.dart';
import 'src/features/monetization/monetization.dart';
import 'src/features/maintenance/application/task_creation_controller.dart';
import 'src/features/maintenance/data/task_creation_operation_store.dart';
import 'src/features/maintenance/domain/task_creation.dart';
import 'src/features/maintenance/presentation/task_completion_controller.dart';
import 'src/i18n/dynamic_text.dart';
import 'src/core/utils/date_utils.dart' as hk_dates;
import 'src/ui/app_theme.dart';
import 'src/ui/components.dart' as hk_ui;
import 'src/ui/full_bleed_illustration_background.dart';
import 'src/ui/full_canvas_system_ui.dart';
import 'src/features/permissions/application/permission_education_controller.dart';
import 'src/features/permissions/domain/capability_snapshots.dart';
import 'src/features/permissions/domain/permission_capability.dart';
import 'src/features/permissions/presentation/permission_education_overlay.dart';
import 'src/features/permissions/presentation/permission_setup_screen.dart';
import 'homepilot_animated_splash_screen.dart';
import 'package:homepilot/l10n/app_localizations.dart';
import 'package:homepilot/l10n/app_localizations_ext.dart';

const _petTypeOptions = [
  'Dog',
  'Cat',
  'Fish',
  'Bird',
  'Rabbit',
  'Reptile',
  'Small mammal',
  'Other',
];

const _fishTypeOptions = [
  'Goldfish',
  'Betta',
  'Guppy',
  'Tetra',
  'Molly',
  'Platy',
  'Koi',
  'Other',
];

String _petTypeLabel(BuildContext context, String value) => switch (value) {
  'Dog' => context.l10n.petTypeDog,
  'Cat' => context.l10n.petTypeCat,
  'Fish' => context.l10n.petTypeFish,
  'Bird' => context.l10n.petTypeBird,
  'Rabbit' => context.l10n.petTypeRabbit,
  'Reptile' => context.l10n.petTypeReptile,
  'Small mammal' => context.l10n.petTypeSmallMammal,
  'Other' => context.l10n.petTypeOther,
  _ => value,
};

String _fishTypeLabel(BuildContext context, String value) => switch (value) {
  'Goldfish' => context.l10n.fishTypeGoldfish,
  'Betta' => context.l10n.fishTypeBetta,
  'Guppy' => context.l10n.fishTypeGuppy,
  'Tetra' => context.l10n.fishTypeTetra,
  'Molly' => context.l10n.fishTypeMolly,
  'Platy' => context.l10n.fishTypePlaty,
  'Koi' => context.l10n.fishTypeKoi,
  'Other' => context.l10n.petTypeOther,
  _ => value,
};

final _rootNavigatorKey = GlobalKey<NavigatorState>();
const _themeTransitionDuration = Duration(milliseconds: 620);
const _themeTransitionCurve = Curves.easeInOutCubic;
const _routeTransitionDuration = Duration(milliseconds: 260);
const _routeTransitionReverseDuration = Duration(milliseconds: 180);
const _preferredOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
];

@visibleForTesting
List<DeviceOrientation> preferredAppOrientations() => _preferredOrientations;

Future<void> configurePreferredOrientations() {
  return SystemChrome.setPreferredOrientations(_preferredOrientations);
}

typedef StartupThemeLoader = Future<ThemeStartupSettings> Function();
typedef BootstrappedAppBuilder =
    Widget Function(ThemeStartupSettings startupTheme);

Future<ThemeStartupSettings> _loadStartupTheme(AppDatabase database) async {
  final settings = DriftSettingsRepository(database);
  return ThemeStartupSettings(
    preference: await settings.themePreference(),
    timeOfDayEnabled: await settings.timeOfDayThemeEnabled(),
  );
}

class HomePilotBootstrap extends StatefulWidget {
  const HomePilotBootstrap({
    this.database,
    this.appConfig,
    this.supabaseClient,
    this.startupThemeLoader,
    this.appBuilder,
    super.key,
  }) : assert(
         database != null || (startupThemeLoader != null && appBuilder != null),
       );

  final AppDatabase? database;
  final AppConfig? appConfig;
  final SupabaseClient? supabaseClient;
  final StartupThemeLoader? startupThemeLoader;
  final BootstrappedAppBuilder? appBuilder;

  @override
  State<HomePilotBootstrap> createState() => _HomePilotBootstrapState();
}

class _HomePilotBootstrapState extends State<HomePilotBootstrap> {
  @override
  Widget build(BuildContext context) {
    final database = widget.database;
    final appBuilder = widget.appBuilder;
    final startupThemeLoader =
        widget.startupThemeLoader ??
        (database == null ? null : () => _loadStartupTheme(database));
    return ProviderScope(
      overrides: database == null
          ? const []
          : [
              databaseProvider.overrideWithValue(database),
              appConfigProvider.overrideWithValue(
                widget.appConfig ?? AppConfig.test(),
              ),
              supabaseClientProvider.overrideWithValue(widget.supabaseClient),
              localSyncStoreProvider.overrideWithValue(
                LocalSyncStore(database),
              ),
              maintenanceCompletionReminderReconcilerProvider.overrideWith(
                (ref) => () async {
                  await ref
                      .read(notificationSchedulerProvider)
                      .refreshSchedules();
                },
              ),
              accountDeletionPrepareProvider.overrideWith(
                (ref) => (userId) async {
                  await ref
                      .read(syncCoordinatorProvider)
                      ?.prepareForAccountDeletion(userId);
                },
              ),
              accountDeletionCancelProvider.overrideWith(
                (ref) => (userId) async {
                  await ref
                      .read(syncCoordinatorProvider)
                      ?.cancelAccountDeletion(userId);
                  await ref
                      .read(notificationSchedulerProvider)
                      .refreshSchedules();
                },
              ),
              accountDeletionLocalCleanupProvider.overrideWith(
                (ref) => (userId) async {
                  await LocalAccountDataCleaner(
                    LocalSyncStore(database),
                  ).clearAfterCloudDeletion(
                    userId,
                    additionalCleanup: (accountId) async {
                      await ref
                          .read(offlineCreationDraftStoreProvider)
                          .clearForAccount(accountId);
                      await ref
                          .read(taskCreationOperationStoreProvider)
                          .clearOperationsForAccount(accountId);
                    },
                  );
                  await ref
                      .read(notificationSchedulerProvider)
                      .clearAllScheduledReminders();
                  await cancelAccountScopedBackgroundWork();
                  ref.read(initialHomeSnapshotProvider).value = null;
                },
              ),
            ],
      child: _HomeStartupGate(
        startupThemeLoader: startupThemeLoader!,
        appBuilder:
            appBuilder ??
            (startupTheme) => HomePilotApp(startupTheme: startupTheme),
      ),
    );
  }
}

class _HomeStartupGate extends ConsumerStatefulWidget {
  const _HomeStartupGate({
    required this.startupThemeLoader,
    required this.appBuilder,
  });

  final StartupThemeLoader startupThemeLoader;
  final BootstrappedAppBuilder appBuilder;

  @override
  ConsumerState<_HomeStartupGate> createState() => _HomeStartupGateState();
}

class _HomeStartupGateState extends ConsumerState<_HomeStartupGate> {
  static const _preferenceTimeout = Duration(seconds: 4);

  ThemeStartupSettings? _startupTheme;
  late final Future<void> _startup = _initialize();

  @override
  void initState() {
    super.initState();
    unawaited(_startup);
  }

  Future<void> _initialize() async {
    final startupTheme =
        await _guard(
          'startup preferences',
          widget.startupThemeLoader,
          timeout: _preferenceTimeout,
        ) ??
        const ThemeStartupSettings(
          preference: ThemePreference.light,
          timeOfDayEnabled: false,
        );
    if (!mounted) return;
    setState(() => _startupTheme = startupTheme);
  }

  Future<T?> _guard<T>(
    String label,
    Future<T> Function() operation, {
    required Duration timeout,
  }) async {
    try {
      return await operation().timeout(timeout);
    } on Object catch (error) {
      AppLogger.warning('startup_${label.replaceAll(' ', '_')}', error: error);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startupTheme = _startupTheme;
    if (startupTheme == null) {
      return const HomePilotStartupSurface(
        key: ValueKey('startup-theme-loading'),
      );
    }
    return widget.appBuilder(startupTheme);
  }
}

void _openNotificationPayload(String payload) {
  final route = _validatedNotificationRoute(payload);
  if (route == null) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    context.push(route);
  });
}

String? _validatedNotificationRoute(String payload) {
  final route = payload.trim();
  if (route.isEmpty || !route.startsWith('/')) {
    return null;
  }
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasFragment) {
    return null;
  }
  const allowedPrefixes = [
    '/maintenance',
    '/notifications',
    '/assets',
    '/calendar',
    '/search',
    '/settings',
    '/account',
  ];
  if (!allowedPrefixes.any((prefix) => uri.path.startsWith(prefix))) {
    return null;
  }
  return uri.toString();
}

Future<void> _removeUnsupportedCloudSession(
  SupabaseClient? client,
  AppDatabase database,
) async {
  final session = client?.auth.currentSession;
  if (session == null) return;
  final providers = {
    for (final identity in session.user.identities ?? const <UserIdentity>[])
      identity.provider,
    if (session.user.appMetadata['provider'] case final String provider)
      provider,
  };
  if (providers.contains('google')) return;

  final store = LocalSyncStore(database);
  if (!await store.isDomainDataPristine()) {
    await ZipBackupService(
      database,
    ).exportBackup(trigger: BackupTrigger.preRestore);
  }
  await client!.auth.signOut(scope: SignOutScope.local);
  await store.clearBinding();
}

Future<void> main() async {
  final startupClock = Stopwatch()..start();
  SentryWidgetsFlutterBinding.ensureInitialized();
  await configurePreferredOrientations();
  late final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
  } on AppConfigException catch (error, stackTrace) {
    AppLogger.warning(
      'startup_configuration',
      error: error,
      stackTrace: stackTrace,
    );
    _runHomePilotProcess(const HomePilotStartupFailure());
    return;
  }

  Future<void> runHomePilot() async {
    final database = AppDatabase();
    _runHomePilotProcess(
      _DeferredHomePilotBootstrap(
        database: database,
        config: config,
        elapsedBeforeFirstFrame: startupClock.elapsed,
      ),
    );
  }

  try {
    final observability = await ObservabilityConfig.fromAppConfig(config);
    if (!observability.enabled) {
      await runHomePilot();
      return;
    }
    await initializeHomePilotSentry(
      config: observability,
      appRunner: runHomePilot,
    );
  } on Object catch (error, stackTrace) {
    AppLogger.warning(
      'sentry_configuration_failed',
      error: error,
      stackTrace: stackTrace,
    );
    await runHomePilot();
  }
}

void _runHomePilotProcess(Widget child) {
  runApp(HomePilotProcessSplash(child: child));
}

class _DeferredHomePilotBootstrap extends StatefulWidget {
  const _DeferredHomePilotBootstrap({
    required this.database,
    required this.config,
    required this.elapsedBeforeFirstFrame,
  });

  final AppDatabase database;
  final AppConfig config;
  final Duration elapsedBeforeFirstFrame;

  @override
  State<_DeferredHomePilotBootstrap> createState() =>
      _DeferredHomePilotBootstrapState();
}

class _DeferredHomePilotBootstrapState
    extends State<_DeferredHomePilotBootstrap> {
  SupabaseClient? _supabaseClient;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.info(
        'startup_first_frame',
        fields: {'elapsed_ms': widget.elapsedBeforeFirstFrame.inMilliseconds},
      );
      unawaited(_initializeAfterFirstFrame());
    });
  }

  Future<void> _initializeAfterFirstFrame() async {
    final deviceLanguage = _supportedDeviceLanguage(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    initializeRestoreForegroundService(localeCode: deviceLanguage.name);
    try {
      final resumed =
          await LocalAccountDataCleaner(
            LocalSyncStore(widget.database),
          ).resumePendingCleanup(
            additionalCleanup: (accountId) async {
              await const OfflineCreationDraftStore().clearForAccount(
                accountId,
              );
              await TaskCreationOperationStore(
                storage: const FlutterSecureStorage(),
              ).clearOperationsForAccount(accountId);
            },
          );
      if (resumed) AppLogger.info('account_deletion_local_cleanup_resumed');
    } on Object catch (error) {
      AppLogger.warning(
        'account_deletion_local_cleanup_resume_failed',
        error: error,
      );
    }
    try {
      final support = await getApplicationSupportDirectory();
      final diagnosticStore = AppDiagnosticFileStore(
        Directory(p.join(support.path, 'diagnostics')),
      );
      await diagnosticStore.initialize();
      AppDiagnosticRuntime.fileStore = diagnosticStore;
      unawaited(
        DiagnosticExportService(fileStore: diagnosticStore).cleanupExpired(),
      );
    } on Object catch (error) {
      AppLogger.warning('startup_diagnostics', error: error);
    }

    final cloud = SupabaseBootstrap.initialize(widget.config);
    final locale = DriftSettingsRepository(
      widget.database,
    ).appLocalePreference();

    SupabaseClient? client;
    try {
      client = await cloud;
    } on Object catch (error) {
      AppLogger.warning('startup_cloud_initialization', error: error);
    }

    var restoreLanguage = deviceLanguage;
    try {
      final restorePreference = await locale;
      restoreLanguage = restorePreference.isExplicit
          ? restorePreference.language
          : deviceLanguage;
    } on Object catch (error) {
      AppLogger.warning('startup_locale_preference', error: error);
    }
    if (restoreLanguage != deviceLanguage) {
      initializeRestoreForegroundService(localeCode: restoreLanguage.name);
    }

    if (client != null) {
      try {
        await _removeUnsupportedCloudSession(client, widget.database);
      } on Object catch (error) {
        AppLogger.warning('unsupported_cloud_session_cleanup', error: error);
      }
    }
    if (!mounted) return;
    setState(() {
      _supabaseClient = client;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const HomePilotStartupSurface(
        key: ValueKey('deferred-startup-loading'),
      );
    }
    return HomePilotBootstrap(
      database: widget.database,
      appConfig: widget.config,
      supabaseClient: _supabaseClient,
    );
  }
}

class HomePilotStartupFailure extends StatelessWidget {
  const HomePilotStartupFailure({this.cloudUnavailable = false, super.key});

  final bool cloudUnavailable;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomePilot',
      debugShowCheckedModeBanner: false,
      locale: Locale(
        _supportedDeviceLanguage(
          WidgetsBinding.instance.platformDispatcher.locale,
        ).name,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: HomePilotTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        cloudUnavailable
                            ? context
                                  .l10n
                                  .cloudServicesAreUnavailablePleaseTryAgainLater
                            : context.l10n.thisBuildIsNotConfiguredCorrectly,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final assetRepositoryProvider = Provider<AssetRepository>(
  (ref) => DriftAssetRepository(ref.watch(databaseProvider)),
);

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => ref.watch(maintenanceRepositoryProvider) as CalendarRepository,
);

final streakServiceProvider = Provider<StreakService>(
  (ref) => DatabaseStreakService(ref.watch(databaseProvider)),
);

final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => DriftStatisticsRepository(
    ref.watch(databaseProvider),
    ref.watch(maintenanceRepositoryProvider),
    ref.watch(streakServiceProvider),
    healthScoreCalculator: const WeightedHealthScoreCalculator(),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(databaseProvider)),
);

final permissionCoordinatorProvider = Provider<AppPermissionGateway>(
  (ref) => AppPermissionCoordinator(ref.watch(databaseProvider)),
);

final permissionEducationSeenProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchPermissionEducationSeen();
});

class ThemeStartupSettings {
  const ThemeStartupSettings({
    required this.preference,
    required this.timeOfDayEnabled,
  });

  final ThemePreference preference;
  final bool timeOfDayEnabled;
}

final startupThemeSettingsProvider = Provider<ThemeStartupSettings>(
  (ref) => const ThemeStartupSettings(
    preference: ThemePreference.light,
    timeOfDayEnabled: false,
  ),
);

final themePreferenceProvider = StreamProvider<ThemePreference>((ref) {
  return ref.watch(settingsRepositoryProvider).watchThemePreference();
});

final timeOfDayThemeEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchTimeOfDayThemeEnabled();
});

final localThemeClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now().toLocal();
  yield* Stream.periodic(
    const Duration(minutes: 1),
    (_) => DateTime.now().toLocal(),
  );
});

final appLocalePreferenceProvider = StreamProvider<AppLocalePreference>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAppLocalePreference();
});

final notificationInboxRepositoryProvider =
    Provider<NotificationInboxRepository>(
      (ref) => DriftNotificationInboxRepository(ref.watch(databaseProvider)),
    );

final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => OpenMeteoWeatherRepository(
    db: ref.watch(databaseProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => ZipBackupService(ref.watch(databaseProvider)),
);

final backupStateProvider = FutureProvider<BackupState>(
  (ref) => ref.watch(backupRepositoryProvider).backupState(),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => DriftSearchRepository(ref.watch(databaseProvider)),
);

final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => HomePilotNotificationScheduler(
    ref.watch(maintenanceRepositoryProvider),
    scheduleStore: DriftReminderScheduleStore(ref.watch(databaseProvider)),
    notificationInboxRepository: ref.watch(notificationInboxRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    weatherRepository: ref.watch(weatherRepositoryProvider),
    permissionGateway: ref.watch(permissionCoordinatorProvider),
    onNotificationPayload: _openNotificationPayload,
  ),
);

final notificationAutoStartProvider = Provider<bool>((ref) => true);

final backupAutoStartProvider = Provider<bool>((ref) => true);

final profileProvider = StreamProvider<AppProfile>(
  (ref) => ref.watch(settingsRepositoryProvider).watchProfile(),
);

final homeLocationProvider = StreamProvider<HomeLocation?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchHomeLocation(),
);

final weatherProvider = StreamProvider<WeatherSnapshot?>(
  (ref) => ref.watch(weatherRepositoryProvider).watchWeather(),
);

final notificationsProvider = StreamProvider<List<InboxNotification>>(
  (ref) => ref.watch(notificationInboxRepositoryProvider).watchNotifications(),
);

final unreadNotificationsProvider = StreamProvider<int>(
  (ref) => ref.watch(notificationInboxRepositoryProvider).watchUnreadCount(),
);

final initialHomeSnapshotProvider =
    Provider<ValueNotifier<InitialHomeSnapshot?>>((ref) {
      final notifier = ValueNotifier<InitialHomeSnapshot?>(null);
      ref.onDispose(notifier.dispose);
      return notifier;
    });

enum StartupBootstrapKind {
  checkingStoredSession,
  unauthenticated,
  authenticatedHydrating,
  authenticatedReady,
  startupFailed,
}

enum StartupFailureKind { failed, timedOut }

class StartupFailure {
  const StartupFailure({
    required this.stage,
    required this.kind,
    this.operation,
    this.message,
    this.allowConnectionCheck = true,
  });

  final InitialHydrationStage stage;
  final StartupFailureKind kind;
  final String? operation;
  final String? message;
  final bool allowConnectionCheck;

  bool get timedOut => kind == StartupFailureKind.timedOut;
}

class StartupStepException implements Exception {
  const StartupStepException({
    required this.stage,
    required this.kind,
    required this.operation,
    required this.cause,
  });

  final InitialHydrationStage stage;
  final StartupFailureKind kind;
  final String operation;
  final Object cause;
}

class StartupBootstrapState {
  const StartupBootstrapState._({
    required this.kind,
    this.session,
    this.snapshot,
    this.status,
    this.canContinueOffline = false,
    this.offline = false,
    this.failure,
  });

  const StartupBootstrapState.checkingStoredSession()
    : this._(kind: StartupBootstrapKind.checkingStoredSession);

  const StartupBootstrapState.unauthenticated()
    : this._(kind: StartupBootstrapKind.unauthenticated);

  const StartupBootstrapState.authenticatedHydrating({
    required AuthSession session,
    required SyncStatus status,
    required bool canContinueOffline,
  }) : this._(
         kind: StartupBootstrapKind.authenticatedHydrating,
         session: session,
         status: status,
         canContinueOffline: canContinueOffline,
       );

  StartupBootstrapState.authenticatedReady({
    required InitialHomeSnapshot snapshot,
    bool offline = false,
  }) : this._(
         kind: StartupBootstrapKind.authenticatedReady,
         session: snapshot.session,
         snapshot: snapshot,
         offline: offline,
       );

  const StartupBootstrapState.startupFailed({
    required AuthSession session,
    required SyncStatus status,
    required bool canContinueOffline,
    required StartupFailure failure,
  }) : this._(
         kind: StartupBootstrapKind.startupFailed,
         session: session,
         status: status,
         canContinueOffline: canContinueOffline,
         failure: failure,
       );

  final StartupBootstrapKind kind;
  final AuthSession? session;
  final InitialHomeSnapshot? snapshot;
  final SyncStatus? status;
  final bool canContinueOffline;
  final bool offline;
  final StartupFailure? failure;

  bool get isHydrating =>
      kind == StartupBootstrapKind.authenticatedHydrating ||
      kind == StartupBootstrapKind.startupFailed;

  StartupBootstrapState withStatus(SyncStatus nextStatus) {
    return switch (kind) {
      StartupBootstrapKind.authenticatedHydrating =>
        StartupBootstrapState.authenticatedHydrating(
          session: session!,
          status: nextStatus,
          canContinueOffline: canContinueOffline,
        ),
      StartupBootstrapKind.startupFailed => StartupBootstrapState.startupFailed(
        session: session!,
        status: nextStatus,
        canContinueOffline: canContinueOffline,
        failure:
            failure ??
            const StartupFailure(
              stage: InitialHydrationStage.connecting,
              kind: StartupFailureKind.failed,
            ),
      ),
      _ => this,
    };
  }
}

class InitialHomeSnapshot {
  const InitialHomeSnapshot({
    required this.session,
    required this.profile,
    required this.tasks,
    required this.assets,
    required this.rooms,
    required this.backupState,
    required this.unreadNotifications,
    required this.syncStatus,
    required this.loadedAt,
    this.homeLocation,
    this.weather,
    this.avatarProvider,
    this.offline = false,
  });

  final AuthSession session;
  final AppProfile profile;
  final List<TaskItem> tasks;
  final List<Asset> assets;
  final List<Room> rooms;
  final BackupState backupState;
  final int unreadNotifications;
  final HomeLocation? homeLocation;
  final WeatherSnapshot? weather;
  final SyncStatus syncStatus;
  final ImageProvider<Object>? avatarProvider;
  final DateTime loadedAt;
  final bool offline;

  InitialHomeSnapshot copyWithOffline(bool value) {
    return InitialHomeSnapshot(
      session: session,
      profile: profile,
      tasks: tasks,
      assets: assets,
      rooms: rooms,
      backupState: backupState,
      unreadNotifications: unreadNotifications,
      homeLocation: homeLocation,
      weather: weather,
      syncStatus: syncStatus,
      avatarProvider: avatarProvider,
      loadedAt: loadedAt,
      offline: value,
    );
  }
}

final startupRestoreTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 140),
);

final startupRestoreServiceStopperProvider = Provider<Future<void> Function()>(
  (ref) => stopRestoreForegroundService,
);

final startupBootstrapControllerProvider = Provider<StartupBootstrapController>(
  (ref) {
    final controller = StartupBootstrapController(ref);
    ref.onDispose(controller.dispose);
    return controller;
  },
);

class StartupBootstrapController {
  StartupBootstrapController(this._ref);

  static const _startupProviderTimeout = Duration(seconds: 4);
  static const _startupAvatarTimeout = Duration(seconds: 2);
  static const _avatarDownloadTimeout = Duration(milliseconds: 1400);
  static const _restoreServiceStopTimeout = Duration(seconds: 2);

  final Ref _ref;
  final _state = ValueNotifier<StartupBootstrapState>(
    const StartupBootstrapState.checkingStoredSession(),
  );

  ValueListenable<StartupBootstrapState> get stateListenable => _state;

  StartupBootstrapState get currentState => _state.value;

  var _startupGeneration = 0;
  var _routeHomeAfterReady = false;
  var _disposed = false;
  var _navigationCompleted = false;
  String? _activeUserId;
  Future<void>? _activeBootstrap;
  InitialHomeSnapshot? _offlineSnapshotCandidate;
  Future<void>? _restoreServiceStopWork;

  void dispose() {
    _disposed = true;
    _startupGeneration += 1;
    _offlineSnapshotCandidate = null;
    _state.dispose();
  }

  void handleAuthValue(AsyncValue<AuthStateChange> next) {
    final authState = next.value;
    if (authState != null) {
      unawaited(handleAuthState(authState));
    } else if (next.hasError) {
      unawaited(_bootstrapFromRepositorySession());
    }
  }

  void handleSyncStatusValue(AsyncValue<SyncStatus> next) {
    final status = next.value;
    if (status == null) return;
    final current = _state.value;
    if (!current.isHydrating) return;
    _publishStartupState(
      current.withStatus(_mergeStartupSyncStatus(current.status, status)),
    );
  }

  Future<void> handleAuthState(AuthStateChange state) async {
    final session = state.session;
    if (session == null) {
      await _transitionSignedOut();
      return;
    }

    final current = _state.value;
    final alreadyReadyForUser =
        current.kind == StartupBootstrapKind.authenticatedReady &&
        current.session?.userId == session.userId;
    if (state.event == AuthEventType.signedIn && !alreadyReadyForUser) {
      _routeHomeAfterReady = true;
      _navigationCompleted = false;
    }

    if (_activeBootstrap != null && _activeUserId == session.userId) {
      AppLogger.info('startup_restore_reused_active');
      return _activeBootstrap;
    }

    if (current.session?.userId == session.userId &&
        current.kind == StartupBootstrapKind.authenticatedReady) {
      _goHomeAfterReadyIfRequested(session);
      return;
    }

    if (current.session?.userId == session.userId &&
        current.kind == StartupBootstrapKind.startupFailed) {
      AppLogger.info('startup_restore_waiting_for_retry');
      return;
    }

    if (state.event != AuthEventType.signedIn &&
        current.session?.userId == session.userId &&
        current.kind != StartupBootstrapKind.checkingStoredSession) {
      return;
    }

    await _bootstrapForSession(session);
  }

  Future<void> retryStartupRestore() async {
    final session =
        _state.value.session ??
        _ref.read(authRepositoryProvider)?.currentSession;
    if (session == null) {
      _publishStartupState(const StartupBootstrapState.unauthenticated());
      return;
    }
    if (_activeBootstrap != null && _activeUserId == session.userId) {
      AppLogger.info('startup_restore_retry_reused_active');
      return _activeBootstrap;
    }
    AppLogger.info('startup_restore_retry');
    await _bootstrapForSession(session, forceRestore: true);
  }

  Future<void> continueStartupOffline() async {
    final session = _state.value.session;
    if (session == null) return;
    final snapshot = _offlineSnapshotCandidate;
    if (snapshot == null || snapshot.session.userId != session.userId) {
      return;
    }

    final generation = ++_startupGeneration;
    if (!_isCurrentStartup(generation, session)) return;
    _ref.read(initialHomeSnapshotProvider).value = snapshot;
    _publishReady(snapshot, offline: true);
  }

  Future<void> signOutFromStartup() async {
    final session = _state.value.session;
    _startupGeneration += 1;
    _activeBootstrap = null;
    _activeUserId = null;
    _routeHomeAfterReady = false;
    _navigationCompleted = false;
    _offlineSnapshotCandidate = null;
    try {
      if (session != null) {
        await _ref
            .read(notificationSchedulerProvider)
            .clearAllScheduledReminders();
        await _ref.read(notificationInboxRepositoryProvider).clear();
        await _ref
            .read(localSyncStoreProvider)
            ?.clearPartialBootstrapForUser(session.userId);
      }
      await _ref.read(authRepositoryProvider)?.signOut();
    } on Object catch (error) {
      AppLogger.warning('startup_sign_out', error: error);
    }
    _ref.read(initialHomeSnapshotProvider).value = null;
    _publishStartupState(const StartupBootstrapState.unauthenticated());
    _scheduleRestoreServiceStop();
  }

  Future<void> _bootstrapFromRepositorySession() async {
    final session = _ref.read(authRepositoryProvider)?.currentSession;
    if (session == null) {
      await _transitionSignedOut();
      return;
    }
    await _bootstrapForSession(session);
  }

  Future<void> _transitionSignedOut() async {
    _startupGeneration += 1;
    _activeBootstrap = null;
    _activeUserId = null;
    _routeHomeAfterReady = false;
    _navigationCompleted = false;
    _offlineSnapshotCandidate = null;
    unawaited(
      _ref.read(notificationSchedulerProvider).clearAllScheduledReminders(),
    );
    unawaited(_ref.read(notificationInboxRepositoryProvider).clear());
    _ref.read(initialHomeSnapshotProvider).value = null;
    _publishStartupState(const StartupBootstrapState.unauthenticated());
    _scheduleRestoreServiceStop();
  }

  Future<void> _bootstrapForSession(
    AuthSession session, {
    bool forceRestore = false,
  }) {
    if (_activeBootstrap != null && _activeUserId == session.userId) {
      AppLogger.info('startup_restore_reused_active');
      return _activeBootstrap!;
    }

    final generation = ++_startupGeneration;
    _activeUserId = session.userId;
    final work =
        Future<void>.microtask(
          () => _runBootstrapForSession(
            session,
            generation: generation,
            forceRestore: forceRestore,
          ),
        ).whenComplete(() {
          if (generation == _startupGeneration) {
            _activeBootstrap = null;
            _activeUserId = null;
          }
        });
    _activeBootstrap = work;
    return work;
  }

  Future<void> _runBootstrapForSession(
    AuthSession session, {
    required int generation,
    required bool forceRestore,
  }) async {
    AppLogger.info('startup_restore_start');
    final previousFailure = _state.value.failure;
    final store = _ref.read(localSyncStoreProvider);
    if (_state.value.session?.userId != session.userId) {
      _offlineSnapshotCandidate = null;
    }
    _offlineSnapshotCandidate = await _verifiedOfflineSnapshot(
      session,
      store: store,
    );
    if (!_isCurrentStartup(generation, session)) return;

    final offlineSnapshot = _offlineSnapshotCandidate;
    final resumeValidatedFinalization =
        forceRestore &&
        previousFailure?.stage == InitialHydrationStage.finalizing &&
        previousFailure?.allowConnectionCheck == false &&
        offlineSnapshot != null;
    if ((!forceRestore || resumeValidatedFinalization) &&
        offlineSnapshot != null) {
      _ref.read(initialHomeSnapshotProvider).value = offlineSnapshot;
      _publishReady(
        offlineSnapshot.copyWithOffline(false),
        refreshCloudAfterReady: !resumeValidatedFinalization,
      );
      return;
    }

    final startingStatus = _hydrationStatusFor(
      _ref.read(syncStatusProvider).value,
      _syntheticStartupStatus(RestoreRunState.running),
    );
    _publishStartupState(
      StartupBootstrapState.authenticatedHydrating(
        session: session,
        status: startingStatus,
        canContinueOffline: offlineSnapshot != null,
      ),
    );

    try {
      await _runCloudRestore(generation);
      if (!_isCurrentStartup(generation, session)) return;
      final snapshot = await _buildInitialHomeSnapshot(
        session,
        generation: generation,
      );
      if (!_isCurrentStartup(generation, session)) return;
      _ref.read(initialHomeSnapshotProvider).value = snapshot;
      _publishReady(snapshot);
    } on Object catch (error) {
      if (!_isCurrentStartup(generation, session)) return;
      final observedFailureStatus = await _guardStartup(
        'failed sync status',
        () => _ref.read(cloudSyncRepositoryProvider).status(),
        timeout: _startupProviderTimeout,
      );
      if (!_isCurrentStartup(generation, session)) return;
      _offlineSnapshotCandidate ??= await _verifiedOfflineSnapshot(
        session,
        store: store,
      );
      if (!_isCurrentStartup(generation, session)) return;
      final failureContextStatus = observedFailureStatus == null
          ? _state.value.status
          : _mergeStartupSyncStatus(_state.value.status, observedFailureStatus);
      final failure = _startupFailureFor(error, failureContextStatus);
      final fallback = _syntheticStartupStatus(
        RestoreRunState.failed,
        phase: failure.allowConnectionCheck
            ? SyncPhase.offline
            : SyncPhase.error,
        message: failure.message,
        stage: failure.stage,
        failure: failure.message,
      );
      final failureStatus =
          observedFailureStatus != null &&
              const {
                SyncPhase.error,
                SyncPhase.offline,
                SyncPhase.blocked,
              }.contains(observedFailureStatus.phase)
          ? observedFailureStatus
          : fallback;
      final status = _mergeStartupSyncStatus(
        _state.value.status,
        failureStatus,
      );
      _publishStartupState(
        StartupBootstrapState.startupFailed(
          session: session,
          status: status,
          canContinueOffline: _offlineSnapshotCandidate != null,
          failure: failure,
        ),
      );
      AppLogger.warning('startup_restore_failed', error: error);
    }
  }

  Future<InitialHomeSnapshot?> _verifiedOfflineSnapshot(
    AuthSession session, {
    required LocalSyncStore? store,
  }) async {
    if (store == null ||
        !await store.hasCompleteSnapshotForUser(session.userId)) {
      return null;
    }
    try {
      return await _buildInitialHomeSnapshot(session, offline: true);
    } on Object catch (error) {
      AppLogger.warning('startup_cached_snapshot_invalid', error: error);
      return null;
    }
  }

  Future<InitialHomeSnapshot> _buildInitialHomeSnapshot(
    AuthSession session, {
    bool offline = false,
    int? generation,
  }) async {
    final profileFuture = _requiredStartup<AppProfile>(
      'load_profile',
      () => _ref.read(settingsRepositoryProvider).profile(),
    );
    final tasksFuture = _requiredStartup<List<TaskItem>>(
      'load_tasks',
      () => _ref.read(maintenanceRepositoryProvider).listTasks(),
    );
    final assetsFuture = _requiredStartup<List<Asset>>(
      'load_assets',
      () => _ref.read(assetRepositoryProvider).listAssets(),
    );
    final roomsFuture = _requiredStartup<List<Room>>(
      'load_rooms',
      () => _ref.read(assetRepositoryProvider).listRooms(),
    );
    final profile = await profileFuture;
    final tasks = await tasksFuture;
    final assets = await assetsFuture;
    final rooms = await roomsFuture;
    await _criticalStartup<void>(
      'validate_first_home_frame',
      () async {
        if (generation != null && !_isCurrentStartup(generation, session)) {
          throw StateError('A newer startup attempt replaced this one.');
        }
        final roomIds = {for (final room in rooms) room.id};
        for (final asset in assets) {
          if (!roomIds.contains(asset.roomId)) {
            throw StateError(
              'The local Home snapshot contains an asset without a room.',
            );
          }
        }
      },
      timeout: _startupProviderTimeout,
      stage: InitialHydrationStage.finalizing,
    );
    final backupState =
        _ref.read(backupStateProvider).value ?? const BackupState();
    final unreadNotifications =
        _ref.read(unreadNotificationsProvider).value ?? 0;
    final homeLocation = _ref.read(homeLocationProvider).value;
    final weather = _ref.read(weatherProvider).value;
    final syncStatus =
        _ref.read(syncStatusProvider).value ??
        const SyncStatus(phase: SyncPhase.ready);
    final avatarProvider = await _guardStartup<ImageProvider<Object>?>(
      'profile_avatar',
      () => _resolveStartupAvatar(profile, session),
      timeout: _startupAvatarTimeout,
    );
    return InitialHomeSnapshot(
      session: session,
      profile: profile,
      tasks: List.unmodifiable(tasks),
      assets: List.unmodifiable(assets),
      rooms: List.unmodifiable(rooms),
      backupState: backupState,
      unreadNotifications: unreadNotifications,
      homeLocation: homeLocation,
      weather: weather,
      syncStatus: syncStatus,
      avatarProvider: avatarProvider,
      loadedAt: DateTime.now(),
      offline: offline,
    );
  }

  Future<void> _runCloudRestore(int generation) async {
    final repository = _ref.read(cloudSyncRepositoryProvider);
    if (repository is! SyncCoordinator) {
      return _criticalStartup<void>(
        'cloud_restore',
        repository.enable,
        timeout: _ref.read(startupRestoreTimeoutProvider),
        stage: InitialHydrationStage.connecting,
      );
    }
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_step_start_cloud_restore',
      fields: {'attempt': generation},
    );
    final cloudRestoreTimeout = _ref.read(startupRestoreTimeoutProvider);
    try {
      await repository.enable().timeout(cloudRestoreTimeout);
      AppLogger.info(
        'startup_step_completed_cloud_restore',
        fields: {
          'attempt': generation,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } on TimeoutException catch (error) {
      AppLogger.warning(
        'startup_step_timeout_cloud_restore',
        error: error,
        fields: {
          'attempt': generation,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'timeout_ms': cloudRestoreTimeout.inMilliseconds,
        },
      );
      throw StartupStepException(
        stage: InitialHydrationStage.connecting,
        kind: StartupFailureKind.timedOut,
        operation: 'cloud_restore',
        cause: TimeoutException(
          'Cloud restore timed out.',
          cloudRestoreTimeout,
        ),
      );
    } on Object catch (error) {
      AppLogger.warning(
        'startup_step_failed_cloud_restore',
        error: error,
        fields: {
          'attempt': generation,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      throw StartupStepException(
        stage: InitialHydrationStage.connecting,
        kind: StartupFailureKind.failed,
        operation: 'cloud_restore',
        cause: error,
      );
    }
  }

  Future<T> _requiredStartup<T>(String label, Future<T> Function() operation) {
    return _criticalStartup(
      label,
      operation,
      timeout: _startupProviderTimeout,
      stage: InitialHydrationStage.finalizing,
    );
  }

  Future<T> _criticalStartup<T>(
    String label,
    Future<T> Function() operation, {
    required Duration timeout,
    required InitialHydrationStage stage,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_step_start_${label.replaceAll(' ', '_')}',
      fields: {
        'attempt': _startupGeneration,
        'timeout_ms': timeout.inMilliseconds,
      },
    );
    try {
      final value = await operation().timeout(timeout);
      AppLogger.info(
        'startup_step_completed_${label.replaceAll(' ', '_')}',
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return value;
    } on TimeoutException catch (error) {
      AppLogger.warning(
        'startup_step_timeout_${label.replaceAll(' ', '_')}',
        error: error,
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'timeout_ms': timeout.inMilliseconds,
        },
      );
      throw StartupStepException(
        stage: stage,
        kind: StartupFailureKind.timedOut,
        operation: label,
        cause: TimeoutException('Startup step timed out.', timeout),
      );
    } on Object catch (error) {
      AppLogger.warning(
        'startup_step_failed_${label.replaceAll(' ', '_')}',
        error: error,
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      throw StartupStepException(
        stage: stage,
        kind: StartupFailureKind.failed,
        operation: label,
        cause: error,
      );
    }
  }

  Future<T?> _guardStartup<T>(
    String label,
    Future<T> Function() operation, {
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_optional_start_${label.replaceAll(' ', '_')}',
      fields: {
        'attempt': _startupGeneration,
        'timeout_ms': timeout.inMilliseconds,
      },
    );
    try {
      final result = await operation().timeout(timeout);
      AppLogger.info(
        'startup_optional_completed_${label.replaceAll(' ', '_')}',
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return result;
    } on Object catch (error) {
      AppLogger.warning(
        'startup_optional_failed_${label.replaceAll(' ', '_')}',
        error: error,
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return null;
    }
  }

  Future<ImageProvider<Object>?> _resolveStartupAvatar(
    AppProfile profile,
    AuthSession session,
  ) async {
    final localPath = profile.avatarPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        final provider = FileImage(file);
        if (await _warmImageProvider(provider)) return provider;
      }
    }
    final avatarUrl = session.avatarUrl?.trim();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return null;
    }
    final cached = await _cachedAvatarFile(session.userId, avatarUrl);
    if (await cached.exists()) {
      final provider = FileImage(cached);
      if (await _warmImageProvider(provider)) return provider;
    }
    try {
      final response = await http
          .get(Uri.parse(avatarUrl))
          .timeout(_avatarDownloadTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await cached.parent.create(recursive: true);
        await cached.writeAsBytes(response.bodyBytes, flush: true);
        final provider = FileImage(cached);
        if (await _warmImageProvider(provider)) return provider;
      }
    } on Object catch (error) {
      AppLogger.warning('startup_avatar_download', error: error);
    }
    return null;
  }

  Future<File> _cachedAvatarFile(String userId, String avatarUrl) async {
    final digest = sha1.convert(utf8.encode('$userId|$avatarUrl')).toString();
    final directory = await getApplicationCacheDirectory();
    return File(p.join(directory.path, 'avatars', '$digest.avatar'));
  }

  Future<bool> _warmImageProvider(ImageProvider<Object> provider) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<bool>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!completer.isCompleted) completer.complete(true);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    stream.addListener(listener);
    try {
      return await completer.future.timeout(
        _avatarDownloadTimeout,
        onTimeout: () => false,
      );
    } finally {
      stream.removeListener(listener);
    }
  }

  StartupFailure _startupFailureFor(Object error, SyncStatus? status) {
    final progress = status?.initialHydrationProgress;
    final stepError = error is StartupStepException ? error : null;
    final errorStage = stepError?.stage ?? InitialHydrationStage.finalizing;
    final observedStage = progress?.stage;
    final stage =
        observedStage != null && observedStage.index > errorStage.index
        ? observedStage
        : errorStage;
    final statusFailed =
        status != null &&
        const {
          SyncPhase.error,
          SyncPhase.offline,
          SyncPhase.blocked,
          SyncPhase.signedOut,
        }.contains(status.phase);
    final detail = progress?.failure?.trim().isNotEmpty == true
        ? progress!.failure!.trim()
        : statusFailed && status.message?.trim().isNotEmpty == true
        ? status.message!.trim()
        : null;
    final finalizationOperation = stage == InitialHydrationStage.finalizing
        ? _finalizationOperationFromDetail(detail)
        : null;
    final kind =
        stepError?.kind == StartupFailureKind.timedOut ||
            detail?.toLowerCase().contains('timed out') == true
        ? StartupFailureKind.timedOut
        : StartupFailureKind.failed;
    return StartupFailure(
      stage: stage,
      kind: kind,
      operation: finalizationOperation ?? stepError?.operation,
      message: detail,
      allowConnectionCheck:
          stage != InitialHydrationStage.finalizing &&
          (status?.phase == SyncPhase.offline ||
              stepError?.operation == 'cloud_restore'),
    );
  }

  String? _finalizationOperationFromDetail(String? detail) {
    final normalized = detail?.toLowerCase() ?? '';
    if (normalized.contains('commit local home snapshot')) {
      return 'commit_local_home_snapshot';
    }
    if (normalized.contains('validate local home')) {
      return 'validate_local_home';
    }
    return null;
  }

  void _schedulePostReadySync({required bool refreshCloud}) {
    scheduleMicrotask(() async {
      await WidgetsBinding.instance.endOfFrame;
      if (_disposed) return;
      _ref.read(syncCoordinatorProvider)?.startPostReadyWork();
      try {
        if (refreshCloud) {
          await _ref.read(cloudSyncRepositoryProvider).syncNow();
        }
      } on Object {
        // The ready Home snapshot remains authoritative while background sync
        // reports its own status through syncStatusProvider.
      }
      final location = _ref.read(homeLocationProvider).value;
      if (location != null) {
        try {
          await _ref.read(weatherRepositoryProvider).refreshWeather();
        } on Object catch (error) {
          AppLogger.warning('startup_post_ready_weather_failed', error: error);
        }
      }
    });
  }

  void _scheduleRestoreServiceStop() {
    if (_restoreServiceStopWork != null) return;
    final completion = Completer<void>();
    _restoreServiceStopWork = completion.future;
    scheduleMicrotask(() async {
      try {
        await _ref
            .read(startupRestoreServiceStopperProvider)()
            .timeout(_restoreServiceStopTimeout);
      } on Object catch (error) {
        AppLogger.warning('startup_restore_service_stop', error: error);
      } finally {
        completion.complete();
        if (identical(_restoreServiceStopWork, completion.future)) {
          _restoreServiceStopWork = null;
        }
      }
    });
  }

  bool _isCurrentStartup(int generation, AuthSession session) {
    return !_disposed &&
        generation == _startupGeneration &&
        _isCurrentSession(session);
  }

  bool _isCurrentSession(AuthSession session) {
    final currentSession =
        _ref.read(authSessionProvider).value ??
        _ref.read(authRepositoryProvider)?.currentSession;
    return currentSession?.userId == session.userId;
  }

  void _publishReady(
    InitialHomeSnapshot snapshot, {
    bool offline = false,
    bool refreshCloudAfterReady = false,
  }) {
    final current = _state.value;
    if (current.kind == StartupBootstrapKind.authenticatedReady &&
        current.session?.userId == snapshot.session.userId) {
      _goHomeAfterReadyIfRequested(snapshot.session);
      return;
    }
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_finalization_publish_ready_start',
      fields: {'attempt': _startupGeneration},
    );
    AppLogger.info('startup_restore_completed');
    _publishStartupState(
      StartupBootstrapState.authenticatedReady(
        snapshot: snapshot,
        offline: offline,
      ),
    );
    AppLogger.info(
      'startup_finalization_publish_ready_completed',
      fields: {
        'attempt': _startupGeneration,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
      },
    );
    _goHomeAfterReadyIfRequested(snapshot.session);
    if (!offline) {
      _schedulePostReadySync(refreshCloud: refreshCloudAfterReady);
    }
    _scheduleRestoreServiceStop();
  }

  void _publishStartupState(StartupBootstrapState state) {
    if (_disposed) return;
    _state.value = state;
  }

  void _goHomeAfterReadyIfRequested(AuthSession session) {
    if (!_routeHomeAfterReady || _navigationCompleted) return;
    _routeHomeAfterReady = false;
    _navigationCompleted = true;
    AppLogger.info(
      'startup_finalization_navigation_scheduled',
      fields: {'attempt': _startupGeneration},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_isCurrentSession(session)) return;
      _ref.read(routerProvider).go('/');
      AppLogger.info(
        'startup_navigation_home',
        fields: {'attempt': _startupGeneration},
      );
    });
  }
}

final notificationPreferencesProvider = StreamProvider<NotificationPreferences>(
  (ref) => ref.watch(settingsRepositoryProvider).watchNotificationPreferences(),
);

final notificationPermissionStateProvider =
    FutureProvider.autoDispose<NotificationPermissionState>(
      (ref) => ref.watch(notificationSchedulerProvider).permissionState(),
    );

final assetsProvider = StreamProvider<List<Asset>>(
  (ref) => ref
      .watch(assetRepositoryProvider)
      .watchAssets()
      .distinctByFingerprint(assetListFingerprint),
);

final roomAssetsProvider = StreamProvider.family<List<Asset>, String>(
  (ref, roomId) => ref
      .watch(assetRepositoryProvider)
      .watchAssets(roomId: roomId)
      .distinctByFingerprint(assetListFingerprint),
);

final areasProvider = StreamProvider<List<Area>>(
  (ref) => ref
      .watch(assetRepositoryProvider)
      .watchAreas()
      .distinctByFingerprint(areaListFingerprint),
);

final roomsProvider = StreamProvider<List<Room>>(
  (ref) => ref
      .watch(assetRepositoryProvider)
      .watchRooms()
      .distinctByFingerprint(roomListFingerprint),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref
      .watch(assetRepositoryProvider)
      .watchCategories()
      .distinctByFingerprint(categoryListFingerprint),
);

final tasksProvider = StreamProvider<List<TaskItem>>(
  (ref) => ref
      .watch(maintenanceRepositoryProvider)
      .watchTasks()
      .distinctByFingerprint(taskListFingerprint),
);

final taskDetailProvider = StreamProvider.autoDispose.family<TaskItem?, String>(
  (ref, planId) => ref
      .watch(maintenanceRepositoryProvider)
      .watchTask(planId)
      .distinctByFingerprint(
        (task) => task == null ? 0 : taskFingerprint(task),
      ),
);

final taskRecordsProvider = StreamProvider.autoDispose
    .family<List<MaintenanceRecord>, String>((ref, planId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchRecordsForPlan(planId)
          .distinctByFingerprint(maintenanceRecordListFingerprint);
    });

final assetDetailProvider = StreamProvider.autoDispose.family<Asset?, String>((
  ref,
  assetId,
) {
  return ref
      .watch(assetRepositoryProvider)
      .watchAsset(assetId)
      .distinctByFingerprint(
        (asset) => asset == null ? 0 : assetFingerprint(asset),
      );
});

final assetTasksProvider = StreamProvider.autoDispose
    .family<List<TaskItem>, String>((ref, assetId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchTasksForAsset(assetId)
          .distinctByFingerprint(taskListFingerprint);
    });

final assetSavedTasksProvider = StreamProvider.autoDispose
    .family<List<TaskItem>, String>((ref, assetId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchSavedTasksForAsset(assetId)
          .distinctByFingerprint(taskListFingerprint);
    });

final assetTagsProvider = StreamProvider.autoDispose.family<List<Tag>, String>((
  ref,
  assetId,
) {
  return ref
      .watch(assetRepositoryProvider)
      .watchTagsForAsset(assetId)
      .distinctByFingerprint(tagListFingerprint);
});

final assetPhotosProvider = StreamProvider.autoDispose
    .family<List<AssetPhoto>, String>((ref, assetId) {
      return ref
          .watch(assetRepositoryProvider)
          .watchPhotosForAsset(assetId)
          .distinctByFingerprint(assetPhotoListFingerprint);
    });

final archivedAreasProvider = StreamProvider.autoDispose<List<Area>>((ref) {
  return ref
      .watch(assetRepositoryProvider)
      .watchArchivedAreas()
      .distinctByFingerprint(areaListFingerprint);
});

final archivedRoomsProvider = StreamProvider.autoDispose<List<Room>>((ref) {
  return ref
      .watch(assetRepositoryProvider)
      .watchArchivedRooms()
      .distinctByFingerprint(roomListFingerprint);
});

final archivedAssetsProvider = StreamProvider.autoDispose<List<Asset>>((ref) {
  return ref
      .watch(assetRepositoryProvider)
      .watchArchivedAssets()
      .distinctByFingerprint(assetListFingerprint);
});

final archivedTasksProvider = StreamProvider.autoDispose<List<TaskItem>>((ref) {
  return ref
      .watch(maintenanceRepositoryProvider)
      .watchArchivedTasks()
      .distinctByFingerprint(taskListFingerprint);
});

final assetRecordsProvider = StreamProvider.autoDispose
    .family<List<MaintenanceRecord>, String>((ref, assetId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchRecordsForAsset(assetId)
          .distinctByFingerprint(maintenanceRecordListFingerprint);
    });

final dashboardProvider = StreamProvider.autoDispose<DashboardSummary>((ref) {
  return ref
      .watch(statisticsRepositoryProvider)
      .watchDashboardSummary()
      .distinctByFingerprint(dashboardSummaryFingerprint);
});

final statisticsProvider = StreamProvider.autoDispose<StatisticsSummary>(
  (ref) => ref
      .watch(statisticsRepositoryProvider)
      .watchStatisticsSummary()
      .distinctByFingerprint(statisticsSummaryFingerprint),
);

final streakRefreshProvider = FutureProvider.autoDispose<StreakState>((
  ref,
) async {
  return ref.watch(streakServiceProvider).refresh(DateTime.now());
});

Page<void> _appRoutePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  if (_prefersReducedMotion(context)) {
    return NoTransitionPage<void>(
      key: state.pageKey,
      name: normalizeSentryRoute(state.fullPath ?? state.uri.path),
      child: child,
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: normalizeSentryRoute(state.fullPath ?? state.uri.path),
    child: child,
    transitionDuration: _routeTransitionDuration,
    reverseTransitionDuration: _routeTransitionReverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.992, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    observers: [homePilotSentryNavigatorObserver()],
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/assets',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const RoomsScreen()),
          ),
          GoRoute(
            path: '/assets/room/:roomId',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              RoomDetailScreen(roomId: state.pathParameters['roomId']!),
            ),
          ),
          GoRoute(
            path: '/assets/thing/:assetId',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              ThingDetailScreen(assetId: state.pathParameters['assetId']!),
            ),
          ),
          GoRoute(
            path: '/maintenance',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              MaintenanceScreen(
                initialFilter: state.uri.queryParameters['filter'],
              ),
            ),
          ),
          GoRoute(
            path: '/maintenance/:planId',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              TaskDetailScreen(planId: state.pathParameters['planId']!),
            ),
          ),
          GoRoute(
            path: '/calendar',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const CalendarScreen()),
          ),
          GoRoute(
            path: '/more',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const MoreScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const SearchScreen()),
          ),
          GoRoute(
            path: '/trash',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const TrashScreen()),
          ),
          GoRoute(
            path: '/statistics',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const StatisticsScreen()),
          ),

          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const SettingsScreen()),
          ),
          GoRoute(path: '/profile', redirect: (context, state) => '/account'),
          GoRoute(
            path: '/account',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const AccountScreenHost()),
          ),
          GoRoute(
            path: '/backup',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const BackupScreen()),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const NotificationsScreen()),
          ),
          GoRoute(
            path: '/permissions/setup',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              PermissionSetupScreen(
                onChooseLocationManually: (context) =>
                    showModalBottomSheet<HomeLocation>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const LocationPickerSheet(),
                    ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
});

class HomePilotApp extends ConsumerStatefulWidget {
  const HomePilotApp({this.startupTheme, super.key});

  final ThemeStartupSettings? startupTheme;

  @override
  ConsumerState<HomePilotApp> createState() => _HomePilotAppState();
}

class _HomePilotAppState extends ConsumerState<HomePilotApp>
    with WidgetsBindingObserver {
  Locale _deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final startup = ref.read(startupBootstrapControllerProvider);
    ref.listenManual(authStateProvider, (previous, next) {
      startup.handleAuthValue(next);
    }, fireImmediately: true);
    ref.listenManual(syncStatusProvider, (previous, next) {
      startup.handleSyncStatusValue(next);
    }, fireImmediately: true);
    ref.listenManual(streakRefreshProvider, (_, _) {});
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    final next =
        locales?.firstOrNull ??
        WidgetsBinding.instance.platformDispatcher.locale;
    if (next == _deviceLocale) return;
    setState(() => _deviceLocale = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localePreference =
        ref.watch(appLocalePreferenceProvider).value ??
        AppLocalePreference(
          language: AppLanguage.en,
          isExplicit: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
    final appLanguage = localePreference.isExplicit
        ? localePreference.language
        : _supportedDeviceLanguage(_deviceLocale);
    final startupTheme =
        widget.startupTheme ??
        ref.watch(startupThemeSettingsProvider) ??
        const ThemeStartupSettings(
          preference: ThemePreference.light,
          timeOfDayEnabled: false,
        );
    final themePreference =
        ref.watch(themePreferenceProvider).value ?? startupTheme.preference;
    final timeOfDayThemeEnabled =
        ref.watch(timeOfDayThemeEnabledProvider).value ??
        startupTheme.timeOfDayEnabled;
    final themeNow =
        ref.watch(localThemeClockProvider).value ?? DateTime.now().toLocal();
    final themeMode = _effectiveThemeMode(
      themePreference,
      timeOfDayThemeEnabled: timeOfDayThemeEnabled,
      now: themeNow,
    );
    final locale = Locale(appLanguage.name);
    Intl.defaultLocale = locale.toLanguageTag();

    const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
    final startupController = ref.watch(startupBootstrapControllerProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'HomePilot',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: hkRootScaffoldMessengerKey,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: localizationsDelegates,
      routerConfig: router,
      themeAnimationDuration: _themeTransitionDuration,
      themeAnimationCurve: _themeTransitionCurve,
      themeMode: themeMode,
      theme: HomePilotTheme.light(),
      darkTheme: HomePilotTheme.dark(),
      builder: (context, child) {
        return ValueListenableBuilder<StartupBootstrapState>(
          valueListenable: startupController.stateListenable,
          builder: (context, startupState, _) {
            final effectiveStartupStatus =
                startupState.status ??
                _syntheticStartupStatus(RestoreRunState.running);
            if (startupState.kind != StartupBootstrapKind.authenticatedReady) {
              return _StartupHome(
                state: startupState,
                status: effectiveStartupStatus,
                language: appLanguage,
                onLanguageChanged: (language) => ref
                    .read(settingsRepositoryProvider)
                    .setAppLocalePreference(language),
                onRetry: startupController.retryStartupRestore,
                onCheckConnection: startupController.retryStartupRestore,
                onContinueOffline: startupState.canContinueOffline
                    ? startupController.continueStartupOffline
                    : null,
                onSignOut: startupController.signOutFromStartup,
              );
            }
            return MonetizationBootstrap(
              child: CloudSyncBootstrap(
                child: NotificationBootstrap(
                  child: StandardSystemUi(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StartupHome extends StatelessWidget {
  const _StartupHome({
    required this.state,
    required this.status,
    required this.language,
    required this.onLanguageChanged,
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
  });

  final StartupBootstrapState state;
  final SyncStatus status;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return switch (state.kind) {
      StartupBootstrapKind.unauthenticated => AuthenticationGate(
        language: language,
        onLanguageChanged: onLanguageChanged,
        child: const SizedBox.shrink(),
      ),
      StartupBootstrapKind.authenticatedHydrating ||
      StartupBootstrapKind.startupFailed => _StartupRestorationScreen(
        status: status,
        failure: state.failure,
        canContinueOffline: state.canContinueOffline,
        onRetry: onRetry,
        onCheckConnection: onCheckConnection,
        onContinueOffline: onContinueOffline,
        onSignOut: onSignOut,
      ),
      StartupBootstrapKind.checkingStoredSession ||
      StartupBootstrapKind.authenticatedReady => const Scaffold(
        backgroundColor: HkColors.appBackground,
        body: SizedBox.expand(),
      ),
    };
  }
}

class _StartupRestorationScreen extends ConsumerStatefulWidget {
  const _StartupRestorationScreen({
    required this.status,
    required this.failure,
    required this.canContinueOffline,
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
  });

  final SyncStatus status;
  final StartupFailure? failure;
  final bool canContinueOffline;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;

  @override
  ConsumerState<_StartupRestorationScreen> createState() =>
      _StartupRestorationScreenState();
}

class _StartupRestorationScreenState
    extends ConsumerState<_StartupRestorationScreen> {
  bool _restoreServiceRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restoreServiceRequested) {
      _restoreServiceRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_startStartupRestoreService(context));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InitialCloudHydrationOverlay(
      status: widget.status,
      failure: widget.failure,
      canContinueOffline: widget.canContinueOffline,
      onRetry: widget.onRetry,
      onCheckConnection: widget.onCheckConnection,
      onContinueOffline: widget.onContinueOffline,
      onSignOut: widget.onSignOut,
    );
  }
}

Future<void> _startStartupRestoreService(BuildContext context) async {
  if (!context.mounted || !Platform.isAndroid) return;
  final localeCode = Localizations.localeOf(context).languageCode;
  await startRestoreForegroundService(localeCode: localeCode);
}

SyncStatus _hydrationStatusFor(SyncStatus? observed, SyncStatus fallback) {
  if (observed?.initialHydrationProgress != null) {
    return _mergeStartupSyncStatus(fallback, observed!);
  }
  if (observed != null &&
      const {
        SyncPhase.error,
        SyncPhase.offline,
        SyncPhase.blocked,
      }.contains(observed.phase)) {
    return SyncStatus(
      phase: observed.phase,
      enabled: observed.enabled,
      pendingChanges: observed.pendingChanges,
      pendingMediaCleanup: observed.pendingMediaCleanup,
      lastSyncedAt: observed.lastSyncedAt,
      lastSyncAttemptAt: observed.lastSyncAttemptAt,
      lastSyncFailureAt: observed.lastSyncFailureAt,
      message: observed.message,
      boundUserId: observed.boundUserId,
      realtime: observed.realtime,
      nextRetryAt: observed.nextRetryAt,
      initialHydrationProgress:
          fallback.initialHydrationProgress ??
          _syntheticStartupProgress(RestoreRunState.failed),
      mergeConfirmationRequired: observed.mergeConfirmationRequired,
      blockedReason: observed.blockedReason,
      migrationState: observed.migrationState,
      restorePending: observed.restorePending,
      backgroundResult: observed.backgroundResult,
      clockSkewConflicts: observed.clockSkewConflicts,
    );
  }
  return fallback;
}

SyncStatus _mergeStartupSyncStatus(SyncStatus? current, SyncStatus next) {
  final currentProgress = current?.initialHydrationProgress;
  final nextProgress = next.initialHydrationProgress;
  if (currentProgress == null) return next;
  if (nextProgress == null) {
    return _syncStatusWithHydration(next, currentProgress);
  }
  final progress = _isHydrationProgressBefore(nextProgress, currentProgress)
      ? currentProgress
      : nextProgress;
  return _syncStatusWithHydration(next, progress);
}

bool _isHydrationProgressBefore(
  InitialHydrationProgress candidate,
  InitialHydrationProgress floor,
) {
  if (floor.state == RestoreRunState.completed &&
      candidate.state != RestoreRunState.completed) {
    return true;
  }
  if (candidate.state == RestoreRunState.completed) return false;
  if (floor.state == RestoreRunState.failed &&
      candidate.state == RestoreRunState.running) {
    return candidate.percentage < floor.percentage;
  }
  if (candidate.stage.index < floor.stage.index) return true;
  if (candidate.stage.index > floor.stage.index) return false;
  return candidate.percentage < floor.percentage;
}

SyncStatus _syncStatusWithHydration(
  SyncStatus status,
  InitialHydrationProgress progress,
) {
  return SyncStatus(
    phase: status.phase,
    enabled: status.enabled,
    pendingChanges: status.pendingChanges,
    pendingMediaCleanup: status.pendingMediaCleanup,
    lastSyncedAt: status.lastSyncedAt,
    lastSyncAttemptAt: status.lastSyncAttemptAt,
    lastSyncFailureAt: status.lastSyncFailureAt,
    message: status.message,
    boundUserId: status.boundUserId,
    realtime: status.realtime,
    nextRetryAt: status.nextRetryAt,
    initialHydrationProgress: progress,
    mergeConfirmationRequired: status.mergeConfirmationRequired,
    blockedReason: status.blockedReason,
    migrationState: status.migrationState,
    restorePending: status.restorePending,
    backgroundResult: status.backgroundResult,
    clockSkewConflicts: status.clockSkewConflicts,
  );
}

SyncStatus _syntheticStartupStatus(
  RestoreRunState state, {
  SyncPhase phase = SyncPhase.initializing,
  String? message,
  InitialHydrationStage stage = InitialHydrationStage.connecting,
  String? failure,
}) {
  return SyncStatus(
    phase: phase,
    message: message,
    initialHydrationProgress: _syntheticStartupProgress(
      state,
      stage: stage,
      failure: failure,
    ),
  );
}

InitialHydrationProgress _syntheticStartupProgress(
  RestoreRunState state, {
  InitialHydrationStage stage = InitialHydrationStage.connecting,
  String? failure,
}) {
  final now = DateTime.now();
  return InitialHydrationProgress(
    runId: 'startup',
    state: state,
    stage: stage,
    completedUnits: 0,
    totalUnits: 1,
    startedAt: now,
    updatedAt: now,
    failure: state == RestoreRunState.failed
        ? failure ?? 'Startup restore failed.'
        : null,
  );
}

AppLanguage _supportedDeviceLanguage(Locale locale) {
  return locale.languageCode.toLowerCase() == AppLanguage.ar.name
      ? AppLanguage.ar
      : AppLanguage.en;
}

String _failureMessage(
  BuildContext context,
  Object error, {
  AppFailureCode fallback = AppFailureCode.general,
}) => localizedFailureMessage(
  context.l10n,
  appFailureCodeFor(error, fallback: fallback),
);

String _localeTag(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

String _formatShortDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(_localeTag(context)).format(value);

String _formatLongDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMMEEEEd(_localeTag(context)).format(value);

String _formatShortTime(BuildContext context, DateTime value) =>
    DateFormat.jm(_localeTag(context)).format(value);

String _formatShortDateTime(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(_localeTag(context)).add_jm().format(value);

String _formatMonthDay(BuildContext context, DateTime value) =>
    DateFormat.MMMd(_localeTag(context)).format(value);

String _formatInteger(BuildContext context, num value) =>
    NumberFormat.decimalPattern(_localeTag(context)).format(value);

String _localizedFeatureMessage(BuildContext context, String value) {
  final l10n = context.l10n;
  final countMatch = RegExp(
    r'^(\d+) (overdue task\(s\)|item\(s\)|due today|warranty alert\(s\))\.$',
  ).firstMatch(value);
  if (countMatch != null) {
    final count = int.parse(countMatch.group(1)!);
    return switch (countMatch.group(2)) {
      'overdue task(s)' => l10n.overdueTaskSentence(count),
      'item(s)' => l10n.itemCountSentence(count),
      'due today' => l10n.dueTodayTaskSentence(count),
      'warranty alert(s)' => l10n.warrantyAlertSentence(count),
      _ => value,
    };
  }
  return switch (value) {
    'No maintenance plan yet.' => l10n.noMaintenancePlanYet,
    'Add a maintenance task.' => l10n.addAMaintenanceTask,
    'Critical task due today.' => l10n.criticalTaskDueToday,
    'Critical care is due soon.' => l10n.criticalCareIsDueSoon,
    'Warranty has expired.' => l10n.warrantyHasExpired,
    'Warranty expires within 30 days.' => l10n.warrantyExpiresWithin30Days,
    'Maintenance is on track.' => l10n.maintenanceIsOnTrack,
    'Review upcoming maintenance.' => l10n.reviewUpcomingMaintenance,
    'No items in this room yet.' => l10n.noItemsInThisRoomYet,
    'Add the first item.' => l10n.addTheFirstItem,
    'Room is on track.' => l10n.roomIsOnTrack,
    'Add maintenance tasks for this room.' =>
      l10n.addMaintenanceTasksForThisRoom,
    'Home setup is incomplete.' => l10n.homeSetupIsIncomplete,
    'No successful backup yet.' => l10n.noSuccessfulBackupYet,
    'Home maintenance is ready.' => l10n.homeMaintenanceIsReady,
    'Review upcoming tasks.' => l10n.reviewUpcomingTasks,
    _ => value,
  };
}

ThemeMode _effectiveThemeMode(
  ThemePreference preference, {
  required bool timeOfDayThemeEnabled,
  required DateTime now,
}) {
  final automaticUsesLocalClock =
      preference == ThemePreference.system || timeOfDayThemeEnabled;
  return switch (preference) {
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.system =>
      automaticUsesLocalClock && _isLocalDaytime(now)
          ? ThemeMode.light
          : ThemeMode.dark,
  };
}

bool _isLocalDaytime(DateTime value) {
  final local = value.toLocal();
  return local.hour >= 6 && local.hour < 18;
}

class NotificationBootstrap extends ConsumerStatefulWidget {
  const NotificationBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationBootstrap> createState() =>
      _NotificationBootstrapState();
}

class _NotificationBootstrapState extends ConsumerState<NotificationBootstrap>
    with WidgetsBindingObserver {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(_initializeNotifications);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      scheduleMicrotask(_refreshNotifications);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _initializeNotifications() async {
    if (_started) {
      return;
    }
    _started = true;
    final syncAccount = await ref.read(localSyncStoreProvider)?.account();
    await configureCloudSyncBackgroundTask(syncAccount?.enabled ?? false);
    await _refreshNotifications();
    unawaited(_runAutomaticBackup());
  }

  Future<void> _refreshNotifications() async {
    if (!ref.read(notificationAutoStartProvider)) {
      return;
    }
    try {
      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      await scheduler.refreshSchedules();
    } on Object catch (error) {
      AppLogger.warning('notification_refresh', error: error);
    }
  }

  Future<void> _runAutomaticBackup() async {
    if (!ref.read(backupAutoStartProvider)) {
      return;
    }
    try {
      await ref.read(backupRepositoryProvider).exportAutomaticBackupIfDue();
    } catch (_) {
      // Backup status is persisted by the backup service; startup should continue.
    }
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _paths = ['/', '/assets', '/maintenance', '/calendar', '/more'];

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final path = uri.path;
    final selectedIndex = _selectedIndex(path);
    final showBottomNav = const {
      '/',
      '/assets',
      '/maintenance',
      '/calendar',
      '/more',
    }.contains(path);
    return Scaffold(
      extendBody: showBottomNav,
      body: widget.child,
      bottomNavigationBar: showBottomNav
          ? hk_ui.SereneBottomNavigationBar(
              selectedIndex: selectedIndex,
              destinations: const [
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.home_rounded,
                  selectedIcon: Symbols.home_filled_rounded,
                  label: hk_ui.SereneBottomNavLabel.home,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.inventory_2_rounded,
                  selectedIcon: Symbols.inventory_2_rounded,
                  label: hk_ui.SereneBottomNavLabel.rooms,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.task_alt_rounded,
                  selectedIcon: Symbols.task_alt_rounded,
                  label: hk_ui.SereneBottomNavLabel.tasks,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.calendar_month_rounded,
                  selectedIcon: Symbols.calendar_month_rounded,
                  label: hk_ui.SereneBottomNavLabel.calendar,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.settings_rounded,
                  selectedIcon: Symbols.settings_rounded,
                  label: hk_ui.SereneBottomNavLabel.tools,
                ),
              ],
              onDestinationSelected: (index) => context.go(_paths[index]),
            )
          : null,
    );
  }

  int _selectedIndex(String path) {
    if (path == '/assets') {
      return 1;
    }
    if (path == '/maintenance') {
      return 2;
    }
    if (path == '/calendar') {
      return 3;
    }
    if (path == '/more') {
      return 4;
    }
    return 0;
  }
}

class _InitialCloudHydrationOverlay extends StatefulWidget {
  const _InitialCloudHydrationOverlay({
    required this.status,
    required this.failure,
    required this.canContinueOffline,
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
  });

  final SyncStatus status;
  final StartupFailure? failure;
  final bool canContinueOffline;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;

  @override
  State<_InitialCloudHydrationOverlay> createState() =>
      _InitialCloudHydrationOverlayState();
}

class _InitialCloudHydrationOverlayState
    extends State<_InitialCloudHydrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = _prefersReducedMotion(context);
    if (_reducedMotion == reducedMotion) {
      return;
    }
    _reducedMotion = reducedMotion;
    if (reducedMotion) {
      _ambientController
        ..stop()
        ..value = 0.28;
    } else {
      _ambientController.repeat();
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  bool get _failedStatus =>
      widget.status.phase == SyncPhase.error ||
      widget.status.phase == SyncPhase.offline ||
      widget.status.phase == SyncPhase.blocked;

  InitialHydrationProgress get _progress =>
      widget.status.initialHydrationProgress ??
      _syntheticStartupProgress(
        _failedStatus ? RestoreRunState.failed : RestoreRunState.running,
      );

  InitialHydrationStage get _stage => widget.failure?.stage ?? _progress.stage;

  double get _ambientProgress => _progress.fraction;

  String get _stageMessage => switch (_stage) {
    InitialHydrationStage.connecting =>
      context.l10n.hydrationConnectingSecurely,
    InitialHydrationStage.restoringCloudData =>
      context.l10n.hydrationRestoringCloudData,
    InitialHydrationStage.restoringPhotos =>
      context.l10n.hydrationRestoringPhotos,
    InitialHydrationStage.syncingLocalChanges =>
      context.l10n.hydrationSyncingLocalChanges,
    InitialHydrationStage.checkingLatestUpdates =>
      context.l10n.hydrationCheckingLatestUpdates,
    InitialHydrationStage.finalizing => context.l10n.finalizingHomePilot,
  };

  String get _failureMessage {
    final explicit = widget.failure?.message?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (widget.failure?.timedOut == true) {
      return context.l10n.hydrationStageTimedOutMessage(_stageMessage);
    }
    return context.l10n.hydrationStageFailedMessage(_stageMessage);
  }

  @override
  Widget build(BuildContext context) {
    final failed = _failedStatus;
    final reducedMotion = _reducedMotion ?? false;

    return FullCanvasSystemUi(
      child: Theme(
        data: HomePilotTheme.light(),
        child: Builder(
          builder: (context) {
            return RepaintBoundary(
              key: const ValueKey('initial-cloud-hydration'),
              child: Material(
                color: HkColors.appBackground,
                child: FullBleedIllustrationBackground(
                  key: const ValueKey('restore-hero-illustration'),
                  illustration: _HydrationHero(
                    animation: _ambientController,
                    reducedMotion: reducedMotion,
                  ),
                  alignment: Alignment.center,
                  fit: BoxFit.contain,
                  backgroundGradient: const RadialGradient(
                    center: Alignment(0.08, -0.02),
                    radius: 1.15,
                    colors: [
                      Color(0xFFE3ECE2),
                      Color(0xFFF5F4F0),
                      HkColors.appBackground,
                    ],
                    stops: [0, 0.62, 1],
                  ),
                  topFade: 0.10,
                  bottomFade: 0.20,
                  leftFade: 0.08,
                  rightFade: 0.08,
                  decorativeOverlay: RepaintBoundary(
                    child: CustomPaint(
                      painter: _HydrationBackdropPainter(
                        animation: _ambientController,
                        progress: _ambientProgress,
                        parallax: Offset.zero,
                        reducedMotion: reducedMotion,
                      ),
                    ),
                  ),
                  illustrationOverlay: failed
                      ? ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.16),
                        )
                      : null,
                  scrim: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xEBF5F4F0),
                      Color(0x00F5F4F0),
                      Color(0x00F5F4F0),
                      Color(0xE8F7F9FC),
                    ],
                    stops: [0, 0.18, 0.52, 1],
                  ),
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final horizontalPadding = constraints.maxWidth < 400
                            ? 12.0
                            : 24.0;
                        final contentWidth = math.min(
                          640.0,
                          constraints.maxWidth - horizontalPadding * 2,
                        );
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(10) / 10;
                        final compact =
                            constraints.maxHeight < 760 || textScale > 1.12;
                        final verticalPadding = compact ? 4.0 : 8.0;
                        final availableHeight = math.max(
                          0.0,
                          constraints.maxHeight - verticalPadding * 2,
                        );
                        final baseLayoutHeight = math.min(
                          compact ? 740.0 : 980.0,
                          availableHeight,
                        );
                        final rawScale = math
                            .min(
                              contentWidth / 560,
                              constraints.maxHeight / 844,
                            )
                            .clamp(0.68, 1.0);
                        final sizeScale =
                            (rawScale / math.max(1, textScale * 0.8)).clamp(
                              0.58,
                              1.0,
                            );
                        final progressHeight = failed
                            ? textScale > 1.25
                                  ? widget.canContinueOffline
                                        ? 290.0
                                        : 258.0
                                  : contentWidth < 420
                                  ? widget.canContinueOffline
                                        ? 246.0
                                        : 214.0
                                  : widget.canContinueOffline
                                  ? 220.0
                                  : 184.0
                            : compact
                            ? 82.0
                            : 100.0;
                        final stageHeight = compact ? 194.0 : 224.0;
                        final tipHeight = compact ? 60.0 : 72.0;
                        final gap = compact ? 7.0 : 10.0;
                        final minimumHeroHeight = failed
                            ? progressHeight + (compact ? 124.0 : 154.0)
                            : 250.0;
                        final minimumLayoutHeight =
                            minimumHeroHeight +
                            stageHeight +
                            tipHeight +
                            gap * 2;
                        final layoutHeight = failed
                            ? math.max(baseLayoutHeight, minimumLayoutHeight)
                            : baseLayoutHeight;
                        final needsScroll =
                            failed && layoutHeight > availableHeight;
                        final heroSectionHeight = math.max(
                          minimumHeroHeight,
                          layoutHeight - stageHeight - tipHeight - gap * 2,
                        );
                        final frame = ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: SizedBox(
                            key: const ValueKey('restore-reference-frame'),
                            width: contentWidth,
                            height: layoutHeight,
                            child: Column(
                              children: [
                                SizedBox(
                                  key: const ValueKey('restore-hero-section'),
                                  height: heroSectionHeight,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        left: 4,
                                        right: 4,
                                        top: 0,
                                        height: failed
                                            ? compact
                                                  ? 58
                                                  : 72
                                            : compact
                                            ? 38
                                            : 48,
                                        child: _HydrationTitle(
                                          failed: failed,
                                          stageLabel: _stageMessage,
                                          sizeScale: sizeScale,
                                        ),
                                      ),
                                      Positioned(
                                        left: compact ? 12 : 24,
                                        right: compact ? 12 : 24,
                                        top: failed
                                            ? compact
                                                  ? 58
                                                  : 72
                                            : compact
                                            ? 34
                                            : 46,
                                        height: failed
                                            ? compact
                                                  ? 64
                                                  : 78
                                            : compact
                                            ? 50
                                            : 58,
                                        child: _HydrationSubtitle(
                                          failed: failed,
                                          message: failed
                                              ? _failureMessage
                                              : null,
                                          sizeScale: sizeScale,
                                        ),
                                      ),
                                      if (failed &&
                                          heroSectionHeight >
                                              progressHeight + 190)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: compact ? 86 : 104,
                                          bottom: progressHeight + 8,
                                          child: Center(
                                            child: hk_ui.BreathingStatusIcon(
                                              icon: Symbols.cloud_off_rounded,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                              size: compact ? 52 : 64,
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        left: contentWidth >= 520 ? 30 : 0,
                                        right: contentWidth >= 520 ? 30 : 0,
                                        bottom: 0,
                                        height: progressHeight,
                                        child: failed
                                            ? _HydrationFailureActions(
                                                onRetry: widget.onRetry,
                                                onCheckConnection:
                                                    widget.onCheckConnection,
                                                onContinueOffline:
                                                    widget.onContinueOffline,
                                                onSignOut: widget.onSignOut,
                                                canContinueOffline:
                                                    widget.canContinueOffline,
                                                showConnectionCheck:
                                                    widget
                                                        .failure
                                                        ?.allowConnectionCheck ??
                                                    true,
                                                sizeScale: sizeScale,
                                                percentage:
                                                    _progress.percentage,
                                                stageLabel: _stageMessage,
                                              )
                                            : _HydrationProgress(
                                                label: _stageMessage,
                                                reducedMotion: reducedMotion,
                                                sizeScale: sizeScale,
                                                compact: compact,
                                                fraction: _progress.fraction,
                                                percentage:
                                                    _progress.percentage,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: gap),
                                SizedBox(
                                  key: const ValueKey('restore-stage-card'),
                                  height: stageHeight,
                                  child: _RestoreStageList(
                                    stage: _stage,
                                    failed: failed,
                                    sizeScale: sizeScale,
                                    compact: compact,
                                  ),
                                ),
                                SizedBox(height: gap),
                                SizedBox(
                                  key: const ValueKey('restore-tip-card'),
                                  height: tipHeight,
                                  child: _HydrationTipCard(
                                    key: const ValueKey('hydration-tip'),
                                    tip: widget.canContinueOffline
                                        ? context
                                              .l10n
                                              .tipYourTasksStayAvailableEvenWhenYouAreOffline
                                        : context
                                              .l10n
                                              .yourTasksRoutinesAndRemindersRestoreInDependencyOrder,
                                    reducedMotion: reducedMotion,
                                    sizeScale: sizeScale,
                                    compact: compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: verticalPadding,
                          ),
                          child: needsScroll
                              ? SingleChildScrollView(
                                  key: const ValueKey('restore-scroll-view'),
                                  child: Center(child: frame),
                                )
                              : Center(child: frame),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HydrationTitle extends StatelessWidget {
  const _HydrationTitle({
    required this.failed,
    required this.stageLabel,
    required this.sizeScale,
  });

  final bool failed;
  final String stageLabel;
  final double sizeScale;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: Text(
          context.l10n.hydrationStageFailureTitle(stageLabel),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            color: HkColors.appTextPrimary,
            fontSize: 38 * sizeScale,
            height: 1.04,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Text(
          context.l10n.restoringYourFlow,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: HkColors.appTextPrimary,
            fontFamily: 'Geist',
            fontSize: 38 * sizeScale,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        PositionedDirectional(
          end: 25 * sizeScale,
          top: -4 * sizeScale,
          child: Transform.rotate(
            angle: -0.45,
            child: Icon(
              Symbols.trending_up_rounded,
              color: HkColors.appPrimary,
              size: 25 * sizeScale,
            ),
          ),
        ),
      ],
    );
  }
}

class _HydrationSubtitle extends StatelessWidget {
  const _HydrationSubtitle({
    required this.failed,
    required this.message,
    required this.sizeScale,
  });

  final bool failed;
  final String? message;
  final double sizeScale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        failed
            ? message ?? context.l10n.hydrationStageFailedMessage('')
            : context.l10n.securelyRestoringTasksRoutinesAndReminders,
        maxLines: failed ? 3 : 2,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: HkColors.appTextSecondary,
          fontFamily: 'Geist',
          fontSize: 17.5 * sizeScale,
          height: 1.25,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _HydrationFailureActions extends StatelessWidget {
  const _HydrationFailureActions({
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
    required this.canContinueOffline,
    required this.showConnectionCheck,
    required this.sizeScale,
    required this.percentage,
    required this.stageLabel,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;
  final bool canContinueOffline;
  final bool showConnectionCheck;
  final double sizeScale;
  final int percentage;
  final String stageLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stackActions =
        MediaQuery.sizeOf(context).width < 400 ||
        MediaQuery.textScalerOf(context).scale(10) > 11.5;
    final actions = <Widget>[
      FilledButton.icon(
        key: const ValueKey('restore-retry-button'),
        onPressed: onRetry,
        icon: Icon(Symbols.refresh_rounded, size: 20 * sizeScale),
        label: Text(context.l10n.retry),
      ),
      if (showConnectionCheck)
        OutlinedButton.icon(
          key: const ValueKey('restore-check-connection-button'),
          onPressed: onCheckConnection,
          icon: Icon(Symbols.wifi_rounded, size: 20 * sizeScale),
          label: Text(context.l10n.checkConnection),
        ),
      if (canContinueOffline && onContinueOffline != null)
        OutlinedButton(
          key: const ValueKey('restore-continue-offline-button'),
          onPressed: onContinueOffline,
          child: Text(context.l10n.continueOffline),
        ),
      OutlinedButton(
        key: const ValueKey('restore-sign-out-button'),
        onPressed: onSignOut,
        child: Text(context.l10n.signOut),
      ),
    ];
    return _HydrationCard(
      radius: 28 * sizeScale,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10 * sizeScale,
          vertical: 10 * sizeScale,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.cloud_off_rounded,
              color: scheme.error,
              size: 38 * sizeScale,
            ),
            SizedBox(height: 4 * sizeScale),
            Text(
              '$percentage% - $stageLabel',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18 * sizeScale,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 7 * sizeScale),
            if (stackActions)
              Column(
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: actions[index],
                    ),
                    if (index != actions.length - 1)
                      SizedBox(height: 5 * sizeScale),
                  ],
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 8 * sizeScale,
                runSpacing: 7 * sizeScale,
                children: actions,
              ),
          ],
        ),
      ),
    );
  }
}

class _HydrationHero extends StatelessWidget {
  const _HydrationHero({required this.animation, required this.reducedMotion});

  final Animation<double> animation;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: Image.asset(
        'assets/illustrations/homepilot-restore-hero-target.png',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
      builder: (context, child) {
        final phase = animation.value * math.pi * 2;
        final float = reducedMotion ? 0.0 : math.sin(phase) * 3;
        return Transform.translate(offset: Offset(0, float), child: child);
      },
    );
  }
}

class _RestoreStageList extends StatelessWidget {
  const _RestoreStageList({
    required this.stage,
    required this.failed,
    required this.sizeScale,
    required this.compact,
  });

  final InitialHydrationStage stage;
  final bool failed;
  final double sizeScale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final stages = <(InitialHydrationStage, String)>[
      (
        InitialHydrationStage.connecting,
        context.l10n.hydrationConnectingSecurely,
      ),
      (
        InitialHydrationStage.restoringCloudData,
        context.l10n.hydrationRestoringCloudData,
      ),
      (
        InitialHydrationStage.restoringPhotos,
        context.l10n.hydrationRestoringPhotos,
      ),
      (
        InitialHydrationStage.syncingLocalChanges,
        context.l10n.hydrationSyncingLocalChanges,
      ),
      (
        InitialHydrationStage.checkingLatestUpdates,
        context.l10n.hydrationCheckingLatestUpdates,
      ),
      (InitialHydrationStage.finalizing, context.l10n.finalizingHomePilot),
    ];
    return _HydrationCard(
      radius: 24 * sizeScale,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < stages.length; index++)
            _RestoreStageRow(
              label: stages[index].$2,
              rowStage: stages[index].$1,
              currentStage: stage,
              failed: failed,
              sizeScale: sizeScale,
              compact: compact,
              isLast: index == stages.length - 1,
            ),
        ],
      ),
    );
  }
}

class _RestoreStageRow extends StatelessWidget {
  const _RestoreStageRow({
    required this.label,
    required this.rowStage,
    required this.currentStage,
    required this.failed,
    required this.sizeScale,
    required this.compact,
    required this.isLast,
  });

  final String label;
  final InitialHydrationStage rowStage;
  final InitialHydrationStage currentStage;
  final bool failed;
  final double sizeScale;
  final bool compact;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final complete = rowStage.index < currentStage.index;
    final active = rowStage == currentStage;
    const activeColor = HkColors.appPrimary;
    const pendingColor = HkColors.appTextTertiary;
    final color = complete || active ? activeColor : pendingColor;
    final rowHeight = compact ? 31.0 : 36.0;
    final indicatorSize = compact ? 20.0 : 24.0;
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          SizedBox(
            width: compact ? 34 : 46,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (!isLast)
                  Positioned(
                    top: rowHeight / 2 + indicatorSize / 2,
                    bottom: -(rowHeight / 2 - indicatorSize / 2),
                    child: Container(
                      width: compact ? 1.5 : 2,
                      color: (complete || active ? activeColor : pendingColor)
                          .withValues(alpha: complete ? 0.72 : 0.42),
                    ),
                  ),
                Container(
                  width: indicatorSize,
                  height: indicatorSize,
                  decoration: BoxDecoration(
                    color: complete
                        ? activeColor
                        : active
                        ? HkColors.appPrimaryMuted
                        : HkColors.appSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: complete ? 1 : 0.86),
                      width: compact ? 1.4 : 1.7,
                    ),
                    boxShadow: active || complete
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.34),
                              blurRadius: compact ? 8 : 11,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: complete
                      ? Icon(
                          Symbols.check_rounded,
                          size: compact ? 13 : 16,
                          color: const Color(0xFFF6FFF9),
                        )
                      : active
                      ? Center(
                          child: Container(
                            width: compact ? 5 : 7,
                            height: compact ? 5 : 7,
                            decoration: BoxDecoration(
                              color: activeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: active || complete
                    ? HkColors.appTextPrimary
                    : HkColors.appTextSecondary.withValues(alpha: 0.82),
                fontSize: (compact ? 16.5 : 17.5) * sizeScale,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 9),
          Text(
            complete
                ? context.l10n.hydrationStepCompleted
                : active
                ? failed
                      ? context.l10n.hydrationStepNeedsAttention
                      : context.l10n.hydrationStepInProgress
                : context.l10n.hydrationStepPending,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active || complete
                  ? activeColor
                  : HkColors.appTextTertiary,
              fontSize: (compact ? 13.5 : 15) * sizeScale,
              fontWeight: active || complete
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          SizedBox(width: compact ? 9 : 16),
        ],
      ),
    );
  }
}

class _HydrationProgress extends StatelessWidget {
  const _HydrationProgress({
    required this.label,
    required this.reducedMotion,
    required this.sizeScale,
    required this.compact,
    required this.fraction,
    required this.percentage,
  });

  final String label;
  final bool reducedMotion;
  final double sizeScale;
  final bool compact;
  final double fraction;
  final int percentage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.cloudRestorationInProgress,
      value: '$percentage percent, $label',
      child: _HydrationCard(
        radius: (compact ? 19 : 23) * sizeScale,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (compact ? 14 : 22) * sizeScale,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.cloud_sync_rounded,
                    color: HkColors.appPrimary,
                    size: (compact ? 23 : 28) * sizeScale,
                  ),
                  SizedBox(width: (compact ? 7 : 9) * sizeScale),
                  Text(
                    '$percentage%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: HkColors.appPrimary,
                      fontSize: (compact ? 20 : 24) * sizeScale,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: (compact ? 7 : 9) * sizeScale),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      child: Text(
                        label,
                        key: ValueKey(label),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: HkColors.appTextPrimary,
                          fontSize: (compact ? 15.5 : 18) * sizeScale,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: (compact ? 7 : 9) * sizeScale),
              ClipRRect(
                key: const ValueKey('hydration-progress-bar'),
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: compact ? 5 : 7,
                  backgroundColor: HkColors.surfaceContainerHigh,
                  color: HkColors.appPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HydrationTipCard extends StatelessWidget {
  const _HydrationTipCard({
    required this.tip,
    required this.reducedMotion,
    required this.sizeScale,
    required this.compact,
    super.key,
  });

  final String tip;
  final bool reducedMotion;
  final double sizeScale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _HydrationCard(
      radius: (compact ? 18 : 21) * sizeScale,
      child: Row(
        children: [
          SizedBox(width: (compact ? 14 : 24) * sizeScale),
          Container(
            width: (compact ? 38 : 50) * sizeScale,
            height: (compact ? 38 : 50) * sizeScale,
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE9BD58).withValues(alpha: 0.92),
                width: (compact ? 1.4 : 1.8) * sizeScale,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE9BD58).withValues(alpha: 0.24),
                  blurRadius: (compact ? 10 : 14) * sizeScale,
                ),
              ],
            ),
            child: Icon(
              Symbols.lightbulb_rounded,
              color: const Color(0xFFE9BD58),
              size: (compact ? 21 : 28) * sizeScale,
            ),
          ),
          SizedBox(width: (compact ? 10 : 16) * sizeScale),
          Expanded(
            child: AnimatedSwitcher(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 360),
              child: Text(
                tip,
                key: ValueKey(tip),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HkColors.appTextSecondary,
                  fontSize: (compact ? 15 : 17) * sizeScale,
                  height: 1.22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          SizedBox(width: (compact ? 12 : 18) * sizeScale),
        ],
      ),
    );
  }
}

class _HydrationCard extends StatelessWidget {
  const _HydrationCard({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: HkColors.appTextPrimary.withValues(alpha: 0.10),
            blurRadius: radius * 1.08,
            offset: Offset(0, radius * 0.36),
          ),
          BoxShadow(
            color: HkColors.appPrimary.withValues(alpha: 0.08),
            blurRadius: radius * 1.2,
            spreadRadius: -radius * 0.18,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: HkColors.appSurface.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: HkColors.appBorder.withValues(alpha: 0.88),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.98),
                  Colors.white.withValues(alpha: 0.92),
                  HkColors.appSurfaceMuted.withValues(alpha: 0.86),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: child),
                Positioned(
                  left: radius * 0.8,
                  right: radius * 0.8,
                  top: 0,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.24),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HydrationBackdropPainter extends CustomPainter {
  _HydrationBackdropPainter({
    required this.animation,
    required this.progress,
    required this.parallax,
    required this.reducedMotion,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final double progress;
  final Offset parallax;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final phase = reducedMotion ? 0.28 : animation.value;
    final primaryGlowCenter = Offset(
      size.width * (0.18 + progress * 0.58) + parallax.dx * 24,
      size.height * 0.30 + parallax.dy * 20,
    );
    canvas.drawCircle(
      primaryGlowCenter,
      math.min(size.width, size.height) * 0.42,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                HkColors.appPrimary.withValues(alpha: 0.12),
                HkColors.appPrimaryMuted.withValues(alpha: 0.08),
                HkColors.appPrimary.withValues(alpha: 0),
              ],
              stops: const [0, 0.45, 1],
            ).createShader(
              Rect.fromCircle(
                center: primaryGlowCenter,
                radius: math.min(size.width, size.height) * 0.42,
              ),
            ),
    );

    final warmGlowCenter = Offset(size.width * 0.18, size.height * 0.86);
    canvas.drawCircle(
      warmGlowCenter,
      math.min(size.width, size.height) * 0.22,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFE8BD58).withValues(alpha: 0.08),
                const Color(0xFFE8BD58).withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: warmGlowCenter,
                radius: math.min(size.width, size.height) * 0.22,
              ),
            ),
    );

    for (var index = 0; index < 28; index++) {
      final seed = index * 1.713;
      final x =
          ((math.sin(seed * 2.1) + 1) * 0.5 * size.width) +
          (parallax.dx * (12 + index));
      final travel = reducedMotion
          ? 0.0
          : ((phase * (18 + index * 1.6)) % (size.height + 80));
      final baseY = ((math.cos(seed) + 1) * 0.5 * size.height);
      final y = (baseY - travel + size.height + 40) % (size.height + 80) - 40;
      final radius = 1.2 + (index % 5) * 0.72;
      final pulse = reducedMotion
          ? 0.55
          : (0.45 + math.sin(phase * math.pi * 2 + seed) * 0.18);
      canvas.drawCircle(
        Offset(x, y + parallax.dy * (10 + index)),
        radius,
        Paint()
          ..color =
              (index.isEven ? const Color(0xFF58DD80) : const Color(0xFFE0C15D))
                  .withValues(alpha: (0.11 + progress * 0.08) * pulse),
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [
            Colors.transparent,
            HkColors.appTextPrimary.withValues(alpha: 0.06),
          ],
          stops: const [0.56, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _HydrationBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.parallax != parallax ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  static const _homeDataSettleDuration = Duration(milliseconds: 180);

  late _HomeRenderData _homeData;
  Timer? _homeDataTimer;
  final LayerLink _weatherEducationLink = LayerLink();
  final LayerLink _notificationEducationLink = LayerLink();
  final GlobalKey _weatherEducationTargetKey = GlobalKey();
  final GlobalKey _notificationEducationTargetKey = GlobalKey();
  late final NativeAdPresentationDepth _nativeAdPresentationDepth;
  bool _forcePermissionEducationHandled = false;
  bool _permissionOverlaySuspendsNativeAds = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeAdPresentationDepth = ref.read(
      nativeAdPresentationDepthProvider.notifier,
    );
    _homeData = _readHomeData();
    ref.listenManual(tasksProvider, (_, _) => _scheduleHomeDataCommit());
    ref.listenManual(assetsProvider, (_, _) => _scheduleHomeDataCommit());
    ref.listenManual(roomsProvider, (_, _) => _scheduleHomeDataCommit());
    ref.listenManual(permissionEducationControllerProvider, (_, next) {
      _setPermissionOverlayNativeAdSuspension(
        next.isVisible && next.activeCapability != null,
      );
    });
    scheduleMicrotask(() {
      if (mounted) {
        ref.read(permissionEducationControllerProvider.notifier).initialize();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final force =
        GoRouter.maybeOf(context)
            ?.routeInformationProvider
            .value
            .uri
            .queryParameters['permissionSetup'] ==
        '1';
    if (force && !_forcePermissionEducationHandled) {
      _forcePermissionEducationHandled = true;
      scheduleMicrotask(() {
        if (mounted) {
          ref
              .read(permissionEducationControllerProvider.notifier)
              .initialize(
                source: PermissionEducationSource.settings,
                forceShow: true,
              );
          _clearPermissionSetupQuery();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(permissionEducationControllerProvider.notifier)
            .handleAppResume(),
      );
    }
  }

  @override
  void dispose() {
    _setPermissionOverlayNativeAdSuspension(false);
    WidgetsBinding.instance.removeObserver(this);
    _homeDataTimer?.cancel();
    super.dispose();
  }

  void _setPermissionOverlayNativeAdSuspension(bool shouldSuspend) {
    if (_permissionOverlaySuspendsNativeAds == shouldSuspend) return;
    _permissionOverlaySuspendsNativeAds = shouldSuspend;
    if (shouldSuspend) {
      _nativeAdPresentationDepth.push();
    } else {
      _nativeAdPresentationDepth.pop();
    }
  }

  _HomeRenderData _readHomeData() {
    final snapshot = ref.read(initialHomeSnapshotProvider).value;
    if (snapshot != null) {
      return _HomeRenderData(
        tasks: snapshot.tasks,
        assets: snapshot.assets,
        rooms: snapshot.rooms,
      );
    }
    return _HomeRenderData(
      tasks: ref.read(tasksProvider).value ?? const [],
      assets: ref.read(assetsProvider).value ?? const [],
      rooms: ref.read(roomsProvider).value ?? const [],
    );
  }

  void _scheduleHomeDataCommit() {
    _homeDataTimer?.cancel();
    _homeDataTimer = Timer(_homeDataSettleDuration, () {
      if (!mounted) {
        return;
      }
      final next = _HomeRenderData(
        tasks: ref.read(tasksProvider).value ?? _homeData.tasks,
        assets: ref.read(assetsProvider).value ?? _homeData.assets,
        rooms: ref.read(roomsProvider).value ?? _homeData.rooms,
      );
      if (next.fingerprint == _homeData.fingerprint) {
        return;
      }
      setState(() => _homeData = next);
    });
  }

  void _clearPermissionSetupQuery() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    final uri = router?.routeInformationProvider.value.uri;
    if (uri == null) return;
    if (uri.queryParameters.containsKey('permissionSetup')) {
      final newParams = Map<String, String>.from(uri.queryParameters)
        ..remove('permissionSetup');
      final newUri = uri.replace(
        queryParameters: newParams.isEmpty ? null : newParams,
      );
      router!.replace<void>(newUri.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _homeData.tasks;
    final now = DateTime.now();
    final taskBuckets = getTaskBuckets(tasks, now);
    final homeTaskSections = _homeTaskSections(context, taskBuckets);
    const homeTaskLimit = 3;
    final assets = _homeData.assets;
    final rooms = _homeData.rooms;
    final topPadding = MediaQuery.paddingOf(context).top;
    final headerExtent = _dashboardHeaderExtent(context, topPadding);
    final hasThings = assets.isNotEmpty;
    final canAddThing = rooms.isNotEmpty;
    final permissionState = ref.watch(permissionEducationControllerProvider);
    final weatherCapability = permissionState.setupSnapshot?.weather;
    return Scaffold(
      floatingActionButton: hasThings
          ? Padding(
              padding: const EdgeInsets.only(bottom: HkSpacing.bottomNav),
              child: hk_ui.HomePilotFloatingActionButton(
                tooltip: context.l10n.addTask,
                onPressed: () => showPlanEditorSheet(context),
                icon: Symbols.add_task_rounded,
                label: context.l10n.addTask,
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: const ValueKey('home-stability-boundary'),
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(streakServiceProvider).refresh(DateTime.now()),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DashboardHeaderDelegate(
                      topPadding: topPadding,
                      extent: headerExtent,
                      notificationEducationLink: _notificationEducationLink,
                      notificationEducationTargetKey:
                          _notificationEducationTargetKey,
                      onNotificationEducationTap: null,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            HkSpacing.gutter,
                            HkSpacing.sm,
                            HkSpacing.gutter,
                            HkSpacing.bottomAction + HkSpacing.bottomNav,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              RepaintBoundary(
                                child: _DashboardWeatherCard(
                                  educationLink: _weatherEducationLink,
                                  educationTargetKey:
                                      _weatherEducationTargetKey,
                                  capability: weatherCapability,
                                  onEducationTap: () => unawaited(
                                    ref
                                        .read(
                                          permissionEducationControllerProvider
                                              .notifier,
                                        )
                                        .initialize(
                                          source: PermissionEducationSource
                                              .weatherCard,
                                          forceShow: true,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: HkSpacing.sm),
                              RepaintBoundary(
                                child: _DashboardReadinessCard(
                                  rooms: rooms,
                                  assets: assets,
                                  tasks: tasks,
                                  taskBuckets: taskBuckets,
                                ),
                              ),
                              const SizedBox(height: HkSpacing.sm),
                              const HkNativeAdCard(placement: 'home'),
                              const SizedBox(height: HkSpacing.sm),
                              if (homeTaskSections.isEmpty)
                                hk_ui.PremiumEmptyState(
                                  icon: hasThings
                                      ? Symbols.task_alt_rounded
                                      : Symbols.inventory_2_rounded,
                                  title: hasThings
                                      ? context.l10n.noMaintenancePlansYet
                                      : canAddThing
                                      ? context.l10n.createYourFirstItem
                                      : context.l10n.createYourFirstRoom,
                                  body: hasThings
                                      ? context
                                            .l10n
                                            .scheduleRecurringCareForAnItemToStartTracking
                                      : canAddThing
                                      ? context.l10n.addAHomeItemFirst
                                      : context
                                            .l10n
                                            .addARoomOrZoneBeforeAddingItems,
                                  action: FilledButton.icon(
                                    onPressed: () => hasThings
                                        ? showPlanEditorSheet(context)
                                        : startThingSetupFlow(context, ref),
                                    icon: Icon(
                                      hasThings
                                          ? Symbols.add_task_rounded
                                          : canAddThing
                                          ? Symbols.add_home_work_rounded
                                          : Symbols.meeting_room_rounded,
                                    ),
                                    label: Text(
                                      hasThings
                                          ? context.l10n.addTask
                                          : canAddThing
                                          ? context.l10n.createFirstItem
                                          : context.l10n.createFirstRoom,
                                    ),
                                  ),
                                )
                              else
                                Column(
                                  children: [
                                    for (final section in homeTaskSections) ...[
                                      hk_ui.SectionHeader(
                                        title: section.title,
                                        actionLabel: context.l10n.seeAll,
                                        onAction: () =>
                                            context.push('/maintenance'),
                                      ),
                                      for (final task in section.tasks.take(
                                        homeTaskLimit,
                                      ))
                                        hk_ui.SwipeDelete(
                                          margin: const EdgeInsets.only(
                                            bottom: HkSpacing.sm,
                                          ),
                                          dismissKey: ValueKey(
                                            'home-task-delete-${task.plan.id}',
                                          ),
                                          action: hk_ui.SwipeAction.moveToTrash(
                                            onAction: () =>
                                                deleteTaskWithConfirmation(
                                                  context,
                                                  ref,
                                                  task,
                                                ),
                                          ),
                                          child: hk_ui.TaskCard(
                                            task: task,
                                            margin: EdgeInsets.zero,
                                            onTap: () => context.push(
                                              '/maintenance/${task.plan.id}',
                                            ),
                                            onComplete: () => _completeTask(
                                              context,
                                              ref,
                                              task,
                                            ),
                                            onSnooze: () =>
                                                snoozeTaskWithFeedback(
                                                  context,
                                                  ref,
                                                  task,
                                                ),
                                            onSetEnabled: (enabled) =>
                                                setTaskEnabledWithFeedback(
                                                  context,
                                                  ref,
                                                  task,
                                                  enabled,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          PermissionEducationOverlayWrapper(
            targetLink: _weatherEducationLink,
            onChooseLocationManually: () => runWithNativeAdsSuspended(
              context,
              () => showModalBottomSheet<HomeLocation>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const LocationPickerSheet(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _completeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    return completeTaskWithFeedback(context, ref, task);
  }
}

class _HomeTaskSectionData {
  const _HomeTaskSectionData({required this.title, required this.tasks});

  final String title;
  final List<TaskItem> tasks;
}

List<_HomeTaskSectionData> _homeTaskSections(
  BuildContext context,
  TaskBuckets buckets,
) {
  if (buckets.today.isNotEmpty || buckets.tomorrow.isNotEmpty) {
    return [
      if (buckets.today.isNotEmpty)
        _HomeTaskSectionData(
          title: context.l10n.todaySTasks,
          tasks: buckets.today,
        ),
      if (buckets.tomorrow.isNotEmpty)
        _HomeTaskSectionData(
          title: context.l10n.tomorrowSTasks,
          tasks: buckets.tomorrow,
        ),
    ];
  }
  if (buckets.upcoming.isNotEmpty) {
    return [
      _HomeTaskSectionData(
        title: context.l10n.upcomingTasks,
        tasks: buckets.upcoming,
      ),
    ];
  }
  return const [];
}

class _HomeRenderData {
  _HomeRenderData({
    required this.tasks,
    required this.assets,
    required this.rooms,
  }) : fingerprint = Object.hash(
         taskListFingerprint(tasks),
         assetListFingerprint(assets),
         roomListFingerprint(rooms),
       );

  final List<TaskItem> tasks;
  final List<Asset> assets;
  final List<Room> rooms;
  final int fingerprint;
}

class _DashboardWeatherCard extends ConsumerWidget {
  const _DashboardWeatherCard({
    required this.educationLink,
    required this.educationTargetKey,
    required this.capability,
    this.onEducationTap,
  });

  final LayerLink educationLink;
  final GlobalKey educationTargetKey;
  final WeatherAreaCapabilitySnapshot? capability;
  final VoidCallback? onEducationTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(initialHomeSnapshotProvider).value;
    final themeNow =
        ref.watch(localThemeClockProvider).value ?? DateTime.now().toLocal();
    final brightness = Theme.of(context).brightness;
    final location =
        ref.watch(homeLocationProvider).value ?? snapshot?.homeLocation;
    return CompositedTransformTarget(
      link: educationLink,
      child: KeyedSubtree(
        key: educationTargetKey,
        child: _WeatherCard(
          weather: ref.watch(weatherProvider).value ?? snapshot?.weather,
          location: location,
          capability: capability,
          localNow: themeNow,
          isDark: brightness == Brightness.dark,
          onToggleTheme: () => _toggleWeatherTheme(context, ref, brightness),
          onCapabilityAction: onEducationTap,
        ),
      ),
    );
  }

  Future<void> _toggleWeatherTheme(
    BuildContext context,
    WidgetRef ref,
    Brightness brightness,
  ) async {
    try {
      final repository = ref.read(settingsRepositoryProvider);
      final next = brightness == Brightness.dark
          ? ThemePreference.light
          : ThemePreference.dark;
      await repository.setThemePreference(next);
      await repository.setTimeOfDayThemeEnabled(false);
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.themeUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
}

class _DashboardReadinessCard extends ConsumerWidget {
  const _DashboardReadinessCard({
    required this.rooms,
    required this.assets,
    required this.tasks,
    required this.taskBuckets,
  });

  final List<Room> rooms;
  final List<Asset> assets;
  final List<TaskItem> tasks;
  final TaskBuckets taskBuckets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = feature_selectors.homeSetupProgress(
      rooms: rooms,
      assets: assets,
      tasks: tasks,
    );
    final reduceMotion = _prefersReducedMotion(context);
    if (!setup.isEligible) {
      return AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        child: _HomeSetupProgressCard(
          key: const ValueKey('home-setup-progress-card'),
          progress: setup,
          nextLabel: _setupNextLabel(context, setup.nextStep),
          onNext: () => unawaited(_openSetupStep(context, ref, setup.nextStep)),
        ),
      );
    }
    final snapshot = ref.watch(initialHomeSnapshotProvider).value;
    final readiness = feature_selectors.homeReadiness(
      rooms: rooms,
      assets: assets,
      tasks: tasks,
      backupState:
          ref.watch(backupStateProvider).value ??
          snapshot?.backupState ??
          const BackupState(),
      now: DateTime.now(),
    );
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      child: _HomeReadinessSummaryCard(
        key: const ValueKey('home-readiness-card'),
        score: readiness!.score,
        overdueCount: taskBuckets.overdueCount,
        todayCount: taskBuckets.todayCount,
        nextAction: _localizedFeatureMessage(context, readiness.nextBestAction),
        today: taskBuckets.todayCount,
        nextSeven: taskBuckets.next7DaysCount,
        overdue: taskBuckets.overdueCount,
        onToday: () => context.push('/maintenance?filter=today'),
        onNextSeven: () => context.push('/maintenance?filter=next7'),
        onOverdue: () => context.push('/maintenance?filter=overdue'),
      ),
    );
  }

  String _setupNextLabel(BuildContext context, features.HomeSetupStep? step) =>
      switch (step) {
        features.HomeSetupStep.room => context.l10n.nextCreateFirstRoom,
        features.HomeSetupStep.maintainedItem =>
          context.l10n.nextAddMaintainedItem,
        features.HomeSetupStep.scheduledTask =>
          context.l10n.nextScheduleMaintenanceTask,
        null => '',
      };

  Future<void> _openSetupStep(
    BuildContext context,
    WidgetRef ref,
    features.HomeSetupStep? step,
  ) async {
    switch (step) {
      case features.HomeSetupStep.room:
        await startThingSetupFlow(context, ref);
        return;
      case features.HomeSetupStep.maintainedItem:
        await showAssetEditorSheet(context, roomId: rooms.first.id);
        return;
      case features.HomeSetupStep.scheduledTask:
        await showPlanEditorSheet(context, assetId: assets.first.id);
        return;
      case null:
        return;
    }
  }
}

double _dashboardHeaderExtent(BuildContext context, double topPadding) {
  final width = MediaQuery.sizeOf(context).width;
  final scaledUnit = MediaQuery.textScalerOf(context).scale(16);
  final scaleAdjustment = ((scaledUnit / 16) - 1).clamp(0.0, 1.0) * 14;
  final contentExtent = width < 600 ? 82.0 : 88.0;
  return topPadding + contentExtent + scaleAdjustment;
}

class _DashboardHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DashboardHeaderDelegate({
    required this.topPadding,
    required this.extent,
    required this.notificationEducationLink,
    required this.notificationEducationTargetKey,
    this.onNotificationEducationTap,
  });

  final double topPadding;
  final double extent;
  final LayerLink notificationEducationLink;
  final GlobalKey notificationEducationTargetKey;
  final VoidCallback? onNotificationEducationTap;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _DashboardHeader(
      overlapsContent: overlapsContent,
      notificationEducationLink: notificationEducationLink,
      notificationEducationTargetKey: notificationEducationTargetKey,
      onNotificationEducationTap: onNotificationEducationTap,
    );
  }

  @override
  bool shouldRebuild(_DashboardHeaderDelegate oldDelegate) {
    return topPadding != oldDelegate.topPadding ||
        extent != oldDelegate.extent ||
        notificationEducationLink != oldDelegate.notificationEducationLink ||
        notificationEducationTargetKey !=
            oldDelegate.notificationEducationTargetKey ||
        onNotificationEducationTap != oldDelegate.onNotificationEducationTap;
  }
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({
    required this.overlapsContent,
    required this.notificationEducationLink,
    required this.notificationEducationTargetKey,
    this.onNotificationEducationTap,
  });

  final bool overlapsContent;
  final LayerLink notificationEducationLink;
  final GlobalKey notificationEducationTargetKey;
  final VoidCallback? onNotificationEducationTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(initialHomeSnapshotProvider).value;
    final unreadCount =
        ref.watch(unreadNotificationsProvider).value ??
        snapshot?.unreadNotifications ??
        0;
    final profile =
        ref.watch(profileProvider).value ??
        snapshot?.profile ??
        const AppProfile();
    final session = ref.watch(authSessionProvider).value ?? snapshot?.session;
    final greetingName = _greetingName(context, profile, session);
    // Step 2: The outer pill container is removed. Components now float
    // independently on the transparent canvas per the refactoring spec.
    // The bottom border is preserved via a thin DecoratedBox wrapper so the
    // scroll-depth affordance (overlapsContent) continues to function.
    return RepaintBoundary(
      key: const ValueKey('dashboard-header-card'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(
                alpha: overlapsContent ? 0.28 : 0,
              ),
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = constraints.maxWidth;
                  final isCompact = screenWidth < 360;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HkSpacing.md,
                      HkSpacing.xs,
                      HkSpacing.md,
                      HkSpacing.xs,
                    ),
                    child: _DashboardHeaderActions(
                      screenWidth: screenWidth,
                      isCompact: isCompact,
                      unreadCount: unreadCount,
                      notificationEducationLink: notificationEducationLink,
                      notificationEducationTargetKey:
                          notificationEducationTargetKey,
                      avatarUrl: session?.avatarUrl,
                      avatarProvider: snapshot?.avatarProvider,
                      fallbackName: greetingName,
                      onSearch: () => context.push('/search'),
                      onPoints: () => showPointsWalletSheet(context, ref),
                      onNotifications:
                          onNotificationEducationTap ??
                          () => context.push('/notifications'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHeaderActions extends StatelessWidget {
  const _DashboardHeaderActions({
    required this.screenWidth,
    required this.isCompact,
    required this.unreadCount,
    required this.notificationEducationLink,
    required this.notificationEducationTargetKey,
    required this.avatarUrl,
    required this.avatarProvider,
    required this.fallbackName,
    required this.onSearch,
    required this.onPoints,
    required this.onNotifications,
  });

  /// Logical width of the header row, used for responsive placeholder text.
  final double screenWidth;

  /// True when [screenWidth] < 360 px (compact/small breakpoint).
  final bool isCompact;

  final int unreadCount;
  final LayerLink notificationEducationLink;
  final GlobalKey notificationEducationTargetKey;
  final String? avatarUrl;
  final ImageProvider<Object>? avatarProvider;
  final String fallbackName;
  final VoidCallback onSearch;
  final VoidCallback onPoints;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final componentHeight = isCompact ? 40.0 : 44.0;
    final gap = isCompact ? 6.0 : HkSpacing.xs;
    final search = _DashboardSearchField(
      onPressed: onSearch,
      isCompact: isCompact,
      screenWidth: screenWidth,
    );
    final points = HkPointsPill(
      key: const ValueKey('home-points-control'),
      onTap: onPoints,
      compact: isCompact,
    );
    final notifications = CompositedTransformTarget(
      link: notificationEducationLink,
      child: KeyedSubtree(
        key: notificationEducationTargetKey,
        child: _NotificationButton(
          key: const ValueKey('home-notifications-control'),
          size: componentHeight,
          isCompact: isCompact,
          unreadCount: unreadCount,
          onPressed: onNotifications,
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DashboardAvatarButton(
          size: componentHeight,
          avatarUrl: avatarUrl,
          avatarProvider: avatarProvider,
          fallbackName: fallbackName,
        ),
        SizedBox(width: gap),
        Expanded(child: search),
        SizedBox(width: gap),
        points,
        SizedBox(width: gap),
        notifications,
      ],
    );
  }
}

class _DashboardAvatarButton extends StatelessWidget {
  const _DashboardAvatarButton({
    required this.size,
    required this.avatarUrl,
    required this.avatarProvider,
    required this.fallbackName,
  });

  final double size;
  final String? avatarUrl;
  final ImageProvider<Object>? avatarProvider;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.openAccount,
      excludeSemantics: true,
      child: Tooltip(
        message: context.l10n.openAccount,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push('/account'),
              child: Center(
                child: hk_ui.ProfileAvatar(
                  avatarUrl: avatarUrl,
                  imageProvider: avatarProvider,
                  fallbackName: fallbackName,
                  radius: (size - 4) / 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardSearchField extends StatelessWidget {
  const _DashboardSearchField({
    required this.onPressed,
    required this.isCompact,
    required this.screenWidth,
  });

  final VoidCallback onPressed;

  /// True when the available width is below 360 px.
  final bool isCompact;

  /// Available layout width, used to select the responsive placeholder text.
  final double screenWidth;

  /// Returns the responsive placeholder text for the three mobile breakpoints
  /// defined in the header refactoring spec (Section 3):
  ///   W < 360 px  → short form
  ///   360 ≤ W ≤ 400 px → medium form
  ///   W > 400 px  → full form
  String _placeholder(AppLocalizations l10n) {
    if (screenWidth < 360) return l10n.searchShort;
    if (screenWidth <= 400) return l10n.searchRoomsItems;
    return l10n.searchRoomsItemsTasksNotes;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = isCompact ? 40.0 : 44.0;
    final hPad = isCompact ? 10.0 : HkSpacing.sm;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.full),
      side: BorderSide(color: scheme.outlineVariant),
    );
    final placeholder = _placeholder(context.l10n);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: context.l10n.searchHomePilot,
      child: Tooltip(
        message: context.l10n.searchHomePilot,
        excludeFromSemantics: true,
        child: SizedBox(
          key: const ValueKey('home-search-control'),
          height: height,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: shape,
              onTap: onPressed,
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: hPad, end: hPad),
                child: Row(
                  children: [
                    Icon(
                      Symbols.search_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      child: Text(
                        placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.78,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.size,
    required this.isCompact,
    required this.unreadCount,
    required this.onPressed,
    super.key,
  });

  /// Component height and width (44 px standard, 40 px compact).
  final double size;

  /// True when the available width is below 360 px.
  final bool isCompact;

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semanticLabel = unreadCount > 0
        ? '${context.l10n.notifications}, ${context.l10n.unreadCount(unreadCount)}'
        : context.l10n.notifications;
    // Spec Component D: independent squircle tile with an inline absolute dot
    // badge (8 × 8 px at top: 10, right: 10) replacing the former oversized
    // external badge (20 px at top: -7, right: -7).
    final dotOffset = isCompact ? 8.0 : 10.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.lg),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: Tooltip(
        message: context.l10n.notifications,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HkRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: HkColors.appTextPrimary.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: InkWell(
                customBorder: shape,
                onTap: onPressed,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Symbols.notifications_rounded,
                        size: 20,
                        // Neutral dark icon per spec (icon_neutral: #344054)
                        color: const Color(0xFF344054),
                      ),
                    ),
                    if (unreadCount > 0)
                      PositionedDirectional(
                        top: dotOffset,
                        end: dotOffset,
                        child: Container(
                          key: const ValueKey('home-notification-unread-badge'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            // spec: status_danger #EF4444
                            color: const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Legacy implementation retained for source compatibility; all live identity
// surfaces use the shared fixed-square ProfileAvatar component.
// ignore: unused_element
class _GoogleProfileAvatar extends StatefulWidget {
  const _GoogleProfileAvatar({
    required this.avatarUrl,
    required this.fallbackName,
    required this.radius,
  });

  final String? avatarUrl;
  final String fallbackName;
  final double radius;

  @override
  State<_GoogleProfileAvatar> createState() => _GoogleProfileAvatarState();
}

class _GoogleProfileAvatarState extends State<_GoogleProfileAvatar> {
  String? _failedAvatarUrl;

  @override
  void didUpdateWidget(covariant _GoogleProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _failedAvatarUrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _profileInitials(widget.fallbackName);
    final avatarUrl = widget.avatarUrl;
    final showNetworkAvatar =
        avatarUrl != null &&
        avatarUrl.trim().isNotEmpty &&
        avatarUrl != _failedAvatarUrl;
    final size = (widget.radius * 2).round();
    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surfaceContainerLowest, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: showNetworkAvatar
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              cacheWidth: size * MediaQuery.devicePixelRatioOf(context).ceil(),
              cacheHeight: size * MediaQuery.devicePixelRatioOf(context).ceil(),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return child;
                }
                return const Center(
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _failedAvatarUrl != avatarUrl) {
                    setState(() => _failedAvatarUrl = avatarUrl);
                  }
                });
                return _AvatarFallback(initials: initials);
              },
            )
          : _AvatarFallback(initials: initials),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: initials.isEmpty
          ? Icon(Symbols.person_rounded, color: scheme.primary)
          : Text(
              initials,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

String _profileInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'H';
  return parts
      .take(2)
      .map((part) => part.characters.first)
      .join()
      .toUpperCase();
}

class _HomeSetupProgressCard extends StatelessWidget {
  const _HomeSetupProgressCard({
    required this.progress,
    required this.nextLabel,
    required this.onNext,
    super.key,
  });

  final features.HomeSetupProgress progress;
  final String nextLabel;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderColor: scheme.primary.withValues(alpha: 0.20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(HkRadii.lg),
                ),
                child: Icon(Symbols.home_rounded, color: scheme.primary),
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.setUpYourHome,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: HkSpacing.space4),
                    Text(
                      context.l10n.setupHomeSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.md),
          Text(
            context.l10n.setupProgress(progress.completedSteps),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: HkSpacing.xs),
          Row(
            children: [
              for (
                var index = 0;
                index < features.HomeSetupProgress.totalSteps;
                index++
              ) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: _prefersReducedMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    height: 8,
                    decoration: BoxDecoration(
                      color: index < progress.completedSteps
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(HkRadii.full),
                    ),
                  ),
                ),
                if (index < features.HomeSetupProgress.totalSteps - 1)
                  const SizedBox(width: HkSpacing.space6),
              ],
            ],
          ),
          const SizedBox(height: HkSpacing.md),
          Semantics(
            button: true,
            label: context.l10n.nextValue(nextLabel),
            child: Material(
              color: scheme.primaryContainer.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(HkRadii.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(HkRadii.lg),
                onTap: onNext,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HkSpacing.sm,
                      vertical: HkSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.nextValue(nextLabel),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Icon(
                          Symbols.arrow_forward_rounded,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeReadinessSummaryCard extends StatelessWidget {
  const _HomeReadinessSummaryCard({
    required this.score,
    required this.overdueCount,
    required this.todayCount,
    required this.nextAction,
    required this.today,
    required this.nextSeven,
    required this.overdue,
    required this.onToday,
    required this.onNextSeven,
    required this.onOverdue,
    super.key,
  });

  final int score;
  final int overdueCount;
  final int todayCount;
  final String nextAction;
  final int today;
  final int nextSeven;
  final int overdue;
  final VoidCallback onToday;
  final VoidCallback onNextSeven;
  final VoidCallback onOverdue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alert = overdueCount > 0;
    final color = alert
        ? scheme.error
        : score >= 85
        ? HkColors.green
        : HkColors.appWarning;
    final progress = (score / 100).clamp(0.0, 1.0).toDouble();
    final headline = alert
        ? context.l10n.homeReadinessNeedsAttention
        : todayCount > 0
        ? context.l10n.homeReadinessNextTaskReady
        : context.l10n.homeReadinessReadyForToday;
    final cleanNextAction = nextAction.trim().isEmpty
        ? context.l10n.reviewUpcomingTasks
        : nextAction.trim();
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(12),
      borderColor: color.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Text(
                      '$score%',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          alert
                              ? Symbols.warning_rounded
                              : Symbols.health_and_safety_rounded,
                          color: color,
                          size: 18,
                        ),
                        const SizedBox(width: HkSpacing.space4),
                        Expanded(
                          child: Text(
                            context.l10n.homeReadiness,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.nextValue(cleanNextAction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: context.l10n.today,
                  value: today,
                  icon: Symbols.today_rounded,
                  onTap: onToday,
                ),
              ),
              const SizedBox(width: HkSpacing.space6),
              Expanded(
                child: _SummaryMetric(
                  label: context.l10n.next7,
                  value: nextSeven,
                  icon: Symbols.upcoming_rounded,
                  onTap: onNextSeven,
                ),
              ),
              const SizedBox(width: HkSpacing.space6),
              Expanded(
                child: _SummaryMetric(
                  label: context.l10n.overdue,
                  value: overdue,
                  icon: Symbols.warning_rounded,
                  alert: overdue > 0,
                  onTap: onOverdue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.alert = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = alert ? HkColors.appDanger : scheme.primary;
    return Semantics(
      button: true,
      label: '$label, $value',
      child: Material(
        color: color.withValues(alpha: alert ? 0.12 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadii.md),
          side: BorderSide(color: color.withValues(alpha: 0.14)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(HkRadii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HkSpacing.xs,
              vertical: HkSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: HkSpacing.space4),
                    Text(
                      '$value',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.location,
    required this.capability,
    required this.localNow,
    required this.isDark,
    required this.onToggleTheme,
    required this.onCapabilityAction,
  });

  final WeatherSnapshot? weather;
  final HomeLocation? location;
  final WeatherAreaCapabilitySnapshot? capability;
  final DateTime localNow;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback? onCapabilityAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = weather;
    final day = _isLocalDaytime(localNow);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.18),
            HkColors.secondaryFixed.withValues(alpha: 0.78),
            scheme.surfaceContainerLowest,
          ],
          stops: const [0, 0.58, 1],
        ),
        borderRadius: BorderRadius.circular(HkRadii.xl),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            end: -12,
            top: -18,
            child: Icon(
              current == null
                  ? Symbols.cloud_rounded
                  : _weatherIcon(current.weatherCode),
              size: 96,
              color: scheme.primary.withValues(alpha: 0.055),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(HkSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current == null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _WeatherIconBadge(icon: Symbols.location_on_rounded),
                      const SizedBox(width: HkSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location == null
                                  ? context.l10n.weatherNotSet
                                  : context.l10n.weatherUnavailable,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: HkSpacing.space2),
                            Text(
                              location == null
                                  ? context.l10n.addHomeLocationInSettings
                                  : context
                                        .l10n
                                        .weatherWillUpdateWhenConnectionReturns,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      _WeatherThemeButton(
                        daytime: day,
                        isDark: isDark,
                        onPressed: onToggleTheme,
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(10) / 10;
                          final compactHeader =
                              constraints.maxWidth < 300 || textScale > 1.3;
                          final gap = compactHeader
                              ? HkSpacing.xs
                              : HkSpacing.sm;
                          final temperatureWidth = compactHeader ? 46.0 : 58.0;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _shortWeatherLocationLabel(
                                        context,
                                        current.location.label,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: HkSpacing.space2),
                                    Text(
                                      '${_localizedWeatherSummary(context, current.weatherCode)} \u00B7 ${context.l10n.updatedTime(_formatShortTime(context, current.updatedAt))}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: gap),
                              _WeatherThemeButton(
                                daytime: day,
                                isDark: isDark,
                                onPressed: onToggleTheme,
                              ),
                              SizedBox(width: gap),
                              SizedBox(
                                width: temperatureWidth,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    '${current.temperature.round()}\u00B0C',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: HkSpacing.xs),
                      WeatherDetailChips(weather: current),
                    ],
                  ),
                if (capability != null) ...[
                  const SizedBox(height: HkSpacing.xs),
                  _WeatherCapabilityStatus(
                    capability: capability!,
                    onAction: onCapabilityAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherCapabilityStatus extends StatelessWidget {
  const _WeatherCapabilityStatus({
    required this.capability,
    required this.onAction,
  });

  final WeatherAreaCapabilitySnapshot capability;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isManual = capability.mode == WeatherAreaMode.manual;
    final isDeviceActive =
        capability.mode == WeatherAreaMode.device &&
        capability.effectiveState == EffectiveCapabilityState.active;
    final label = isManual && capability.selectedArea != null
        ? context.l10n.permissionSelectedArea(capability.selectedArea!.label)
        : isDeviceActive
        ? context.l10n.permissionUsingCurrentLocation
        : capability.locationServiceEnabled == false
        ? context.l10n.locationServicesAreOff
        : capability.isConfigured
        ? context.l10n.permissionLocationAccessRequired
        : context.l10n.weatherNotSet;
    final showAction = !isDeviceActive;
    final actionLabel = isManual
        ? context.l10n.change
        : capability.locationServiceEnabled == false
        ? context.l10n.turnOnLocationServices
        : context.l10n.configure;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        children: [
          Icon(
            isManual
                ? Symbols.location_city_rounded
                : isDeviceActive
                ? Symbols.my_location_rounded
                : Symbols.location_off_rounded,
            size: 18,
            color: isManual || isDeviceActive ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              label,
              key: const ValueKey('dashboard-weather-capability-status'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (showAction)
            SizedBox(
              height: 48,
              child: TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Symbols.settings_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeatherThemeButton extends StatelessWidget {
  const _WeatherThemeButton({
    required this.daytime,
    required this.isDark,
    required this.onPressed,
  });

  final bool daytime;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = isDark
        ? context.l10n.switchToLightMode
        : context.l10n.switchToDarkMode;
    return Tooltip(
      message: message,
      child: Semantics(
        button: true,
        label: message,
        child: SizedBox.square(
          dimension: 44,
          child: IconButton(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerLowest.withValues(
                alpha: 0.86,
              ),
              foregroundColor: daytime ? HkColors.appWarning : scheme.primary,
              shape: const CircleBorder(),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.12)),
            ),
            icon: Icon(
              daytime ? Symbols.wb_sunny_rounded : Symbols.dark_mode_rounded,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class WeatherDetailChips extends StatelessWidget {
  const WeatherDetailChips({required this.weather, super.key});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final compact = constraints.maxWidth < 340 || textScale > 1.3;
        final showIcons = constraints.maxWidth >= 320 && textScale <= 1.3;
        final gap = compact ? HkSpacing.space4 : HkSpacing.space6;
        return Row(
          children: [
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.thermostat_rounded,
                label: context.l10n.feels,
                value: '${weather.apparentTemperature.round()}\u00B0C',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.water_drop_rounded,
                label: context.l10n.humidity,
                value: '${weather.humidity}%',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.air_rounded,
                label: context.l10n.wind,
                value: '${weather.windSpeed.round()} km/h',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeatherIconBadge extends StatelessWidget {
  const _WeatherIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: scheme.primary, size: 20),
    );
  }
}

bool _prefersReducedMotion(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  return media?.disableAnimations == true ||
      media?.accessibleNavigation == true;
}

class _WeatherDetailChip extends StatelessWidget {
  const _WeatherDetailChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.compact,
    required this.showIcon,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool compact;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 32 : 34),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? HkSpacing.space4 : HkSpacing.xs,
        vertical: HkSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: showIcon
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: compact ? 13 : 15, color: scheme.primary),
                    SizedBox(width: compact ? 3 : HkSpacing.space4),
                    _WeatherDetailText(
                      label: label,
                      value: value,
                      compact: compact,
                    ),
                  ],
                )
              : _WeatherDetailText(
                  label: label,
                  value: value,
                  compact: compact,
                ),
        ),
      ),
    );
  }
}

class _WeatherDetailText extends StatelessWidget {
  const _WeatherDetailText({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $value',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        fontSize: compact ? 10.5 : null,
      ),
    );
  }
}

Future<File?> _localFile(String? relativePath) async {
  if (relativePath == null || relativePath.trim().isEmpty) {
    return null;
  }
  final path = relativePath.trim();
  final file = p.isAbsolute(path)
      ? File(path)
      : File(
          p.joinAll([
            (await getApplicationDocumentsDirectory()).path,
            ...path.split('/'),
          ]),
        );
  return await file.exists() ? file : null;
}

Future<void> _syncProfileIfEnabled(WidgetRef ref) async {
  try {
    final sync = ref.read(cloudSyncRepositoryProvider);
    final status = await sync.status();
    if (status.enabled) {
      await sync.syncNow();
    }
  } catch (_) {
    // Profile sync is best-effort; visible sync status surfaces failures.
  }
}

String _shortWeatherLocationLabel(BuildContext context, String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return context.l10n.home;
  }
  final firstPart = trimmed.split(RegExp(r'[,\n]')).first.trim();
  final withoutDistrict = firstPart.replaceFirst(
    RegExp(r'\s+District$', caseSensitive: false),
    '',
  );
  if (withoutDistrict.trim().isNotEmpty) {
    return withoutDistrict.trim();
  }
  return firstPart.isEmpty ? trimmed : firstPart;
}

IconData _weatherIcon(int code) {
  return switch (code) {
    0 => Symbols.sunny_rounded,
    1 || 2 || 3 => Symbols.partly_cloudy_day_rounded,
    45 || 48 => Symbols.foggy_rounded,
    51 || 53 || 55 || 56 || 57 => Symbols.rainy_light_rounded,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => Symbols.rainy_rounded,
    71 || 73 || 75 || 77 || 85 || 86 => Symbols.weather_snowy_rounded,
    95 || 96 || 99 => Symbols.thunderstorm_rounded,
    _ => Symbols.cloud_rounded,
  };
}

String _localizedWeatherSummary(BuildContext context, int code) {
  return switch (code) {
    0 => context.l10n.clearWeather,
    1 || 2 => context.l10n.partlyCloudy,
    3 => context.l10n.cloudy,
    45 || 48 => context.l10n.fog,
    51 || 53 || 55 || 56 || 57 => context.l10n.drizzle,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => context.l10n.rain,
    71 || 73 || 75 || 77 || 85 || 86 => context.l10n.snow,
    95 || 96 || 99 => context.l10n.storms,
    _ => context.l10n.weather,
  };
}

String _greetingName(
  BuildContext context,
  AppProfile profile,
  AuthSession? session,
) {
  for (final candidate in [
    profile.nickname,
    session?.fullName,
    session?.name,
    _emailUsername(session?.email),
    context.l10n.there,
  ]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return context.l10n.there;
}

String? _emailUsername(String? email) {
  final trimmed = email?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0) {
    return trimmed;
  }
  return trimmed.substring(0, atIndex);
}

String _taskGroupCountLabel(BuildContext context, int count) {
  return context.l10n.taskCountLabel(count);
}

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  static const _roomsDataSettleDuration = Duration(milliseconds: 180);

  String? _selectedAreaId;
  String _roomQuery = '';
  late _RoomsRenderData _roomsData;
  Timer? _roomsDataTimer;

  @override
  void initState() {
    super.initState();
    _roomsData = _readRoomsData();
    ref.listenManual(areasProvider, (_, _) => _scheduleRoomsDataCommit());
    ref.listenManual(roomsProvider, (_, _) => _scheduleRoomsDataCommit());
    ref.listenManual(assetsProvider, (_, _) => _scheduleRoomsDataCommit());
    ref.listenManual(tasksProvider, (_, _) => _scheduleRoomsDataCommit());
  }

  @override
  void dispose() {
    _roomsDataTimer?.cancel();
    super.dispose();
  }

  _RoomsRenderData _readRoomsData() {
    final areas = ref.read(areasProvider);
    return _RoomsRenderData(
      areas: areas.value ?? const [],
      rooms: ref.read(roomsProvider).value ?? const [],
      assets: ref.read(assetsProvider).value ?? const [],
      tasks: ref.read(tasksProvider).value ?? const [],
      ready: areas.value != null,
      error: areas.error,
    );
  }

  void _scheduleRoomsDataCommit() {
    _roomsDataTimer?.cancel();
    _roomsDataTimer = Timer(_roomsDataSettleDuration, () {
      if (!mounted) {
        return;
      }
      final areaState = ref.read(areasProvider);
      final next = _RoomsRenderData(
        areas: areaState.value ?? _roomsData.areas,
        rooms: ref.read(roomsProvider).value ?? _roomsData.rooms,
        assets: ref.read(assetsProvider).value ?? _roomsData.assets,
        tasks: ref.read(tasksProvider).value ?? _roomsData.tasks,
        ready: areaState.value != null || _roomsData.ready,
        error: areaState.error,
      );
      if (next.fingerprint == _roomsData.fingerprint) {
        return;
      }
      AppLogger.info(
        'rooms_render_data_committed',
        fields: {
          'area_count': next.areas.length,
          'room_count': next.rooms.length,
          'asset_count': next.assets.length,
          'task_count': next.tasks.length,
        },
      );
      setState(() => _roomsData = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas = _roomsData.ready
        ? AsyncValue<List<Area>>.data(_roomsData.areas)
        : _roomsData.error != null
        ? AsyncValue<List<Area>>.error(_roomsData.error!, StackTrace.empty)
        : const AsyncValue<List<Area>>.loading();
    final rooms = _roomsData.rooms;
    final assets = _roomsData.assets;
    final tasks = _roomsData.tasks;
    final areaItems = _roomsData.areas;
    final selectedAreaForAction =
        areaItems.any((area) => area.id == _selectedAreaId)
        ? _selectedAreaId
        : areaItems.firstOrNull?.id;
    final selectedAreaRooms = selectedAreaForAction == null
        ? <Room>[]
        : rooms.where((room) => room.areaId == selectedAreaForAction).toList();
    final selectedActionArea = selectedAreaForAction == null
        ? null
        : areaItems
              .where((area) => area.id == selectedAreaForAction)
              .firstOrNull;
    final actionAreaIsOutdoor = selectedActionArea?.kind == AreaKind.outdoor;
    final fabLabel = selectedAreaForAction == null
        ? context.l10n.addArea
        : selectedAreaRooms.isEmpty
        ? actionAreaIsOutdoor
              ? context.l10n.addZone
              : context.l10n.addRoom
        : context.l10n.addItem;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.rooms),
        actions: [
          HkPointsPill(onTap: () => showPointsWalletSheet(context, ref)),
          IconButton(
            tooltip: context.l10n.addArea,
            onPressed: () => showAreaEditorSheet(context),
            icon: const Icon(Symbols.add_home_rounded),
          ),
        ],
      ),
      floatingActionButton: selectedAreaRooms.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: HkSpacing.bottomNav),
              child: hk_ui.HomePilotFloatingActionButton(
                onPressed: () => showAssetEditorSheet(
                  context,
                  roomId: selectedAreaRooms.first.id,
                ),
                icon: Symbols.add_home_work_rounded,
                label: fabLabel,
              ),
            ),
      body: RepaintBoundary(
        key: const ValueKey('rooms-stability-boundary'),
        child: areas.when(
          data: (areaItems) {
            if (areaItems.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  HkSpacing.bottomAction + HkSpacing.bottomNav,
                ),
                children: [
                  hk_ui.PremiumEmptyState(
                    icon: Symbols.home_work_rounded,
                    title: context.l10n.noAreasYet,
                    body: context.l10n.createAreaToOrganizeRoomsAndZones,
                    action: FilledButton.icon(
                      onPressed: () => showAreaEditorSheet(context),
                      icon: const Icon(Symbols.add_home_rounded),
                      label: Text(context.l10n.addArea),
                    ),
                  ),
                ],
              );
            }
            final selectedArea =
                areaItems.any((area) => area.id == _selectedAreaId)
                ? _selectedAreaId!
                : areaItems.first.id;
            final visibleRooms = rooms
                .where((room) => room.areaId == selectedArea)
                .toList();
            final filteredRooms = _filterRooms(visibleRooms);
            final selectedAreaModel = areaItems.firstWhere(
              (area) => area.id == selectedArea,
            );
            final roomsByArea = <String, int>{};
            for (final room in rooms) {
              roomsByArea.update(
                room.areaId,
                (value) => value + 1,
                ifAbsent: () => 1,
              );
            }
            final assetsByRoom = <String, List<Asset>>{};
            for (final asset in assets) {
              assetsByRoom.putIfAbsent(asset.roomId, () => []).add(asset);
            }
            final tasksByRoom = <String, List<TaskItem>>{};
            for (final task in tasks) {
              tasksByRoom.putIfAbsent(task.room.id, () => []).add(task);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.gutter,
                8,
                HkSpacing.gutter,
                HkSpacing.bottomAction + HkSpacing.bottomNav,
              ),
              children: [
                const HkNativeAdCard(placement: 'assets'),
                const SizedBox(height: HkSpacing.sm),
                AreaSelector(
                  areas: areaItems,
                  selectedAreaId: selectedArea,
                  roomCountsByArea: roomsByArea,
                  onSelected: (areaId) {
                    setState(() => _selectedAreaId = areaId);
                  },
                ),
                const SizedBox(height: HkSpacing.sm),
                SelectedAreaTools(
                  area: selectedAreaModel,
                  canMoveBack: areaItems.indexOf(selectedAreaModel) > 0,
                  canMoveForward:
                      areaItems.indexOf(selectedAreaModel) <
                      areaItems.length - 1,
                  onEdit: () =>
                      showAreaEditorSheet(context, area: selectedAreaModel),
                  onDelete: () async {
                    final deleted = await deleteAreaWithConfirmation(
                      context,
                      ref,
                      selectedAreaModel,
                    );
                    if (deleted && mounted) {
                      setState(() => _selectedAreaId = null);
                    }
                    return deleted;
                  },
                  onMoveBack: () => _moveArea(areaItems, selectedAreaModel, -1),
                  onMoveForward: () =>
                      _moveArea(areaItems, selectedAreaModel, 1),
                ),
                if (visibleRooms.length > 6) ...[
                  const SizedBox(height: HkSpacing.sm),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Symbols.search_rounded),
                      labelText: selectedAreaModel.kind == AreaKind.outdoor
                          ? context.l10n.searchZones
                          : context.l10n.searchRooms,
                    ),
                    onChanged: (value) => setState(() => _roomQuery = value),
                  ),
                ],
                hk_ui.SectionHeader(
                  title: selectedAreaModel.kind == AreaKind.outdoor
                      ? context.l10n.outdoorZones
                      : context.l10n.rooms,
                  subtitle: _roomCountLabel(
                    context,
                    filteredRooms.length,
                    selectedAreaModel,
                    filtered: _roomQuery.trim().isNotEmpty,
                  ),
                  actionLabel: visibleRooms.isEmpty
                      ? null
                      : selectedAreaModel.kind == AreaKind.outdoor
                      ? context.l10n.addZone
                      : context.l10n.addRoom,
                  onAction: () =>
                      showRoomEditorSheet(context, areaId: selectedArea),
                ),
                if (visibleRooms.isEmpty)
                  hk_ui.PremiumEmptyState(
                    icon: Symbols.meeting_room_rounded,
                    title: selectedAreaModel.kind == AreaKind.outdoor
                        ? context.l10n.noZonesYet
                        : context.l10n.noRoomsYet,
                    body: selectedAreaModel.kind == AreaKind.outdoor
                        ? context.l10n.zonesOrganizeOutdoorCare
                        : context.l10n.roomsOrganizeCareByLocation,
                    action: FilledButton.icon(
                      onPressed: () =>
                          showRoomEditorSheet(context, areaId: selectedArea),
                      icon: const Icon(Symbols.add_home_work_rounded),
                      label: Text(
                        selectedAreaModel.kind == AreaKind.outdoor
                            ? context.l10n.addZone
                            : context.l10n.addRoom,
                      ),
                    ),
                  )
                else if (filteredRooms.isEmpty)
                  hk_ui.PremiumEmptyState(
                    icon: Symbols.search_rounded,
                    illustrationTone: hk_ui.HkIllustrationTone.neutral,
                    title: context.l10n.noResultsFound,
                    body: context.l10n.tryADifferentNameOrType,
                    action: OutlinedButton(
                      onPressed: () => setState(() => _roomQuery = ''),
                      child: Text(context.l10n.clearSearch),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 620 ? 2 : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredRooms.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: columns == 1 ? 68 : 76,
                          crossAxisSpacing: HkSpacing.xs,
                          mainAxisSpacing: HkSpacing.xs,
                        ),
                        itemBuilder: (context, index) {
                          final room = filteredRooms[index];
                          return hk_ui.SwipeDelete(
                            dismissKey: ValueKey('room-delete-${room.id}'),
                            action: hk_ui.SwipeAction.moveToTrash(
                              onAction: () => deleteRoomWithConfirmation(
                                context,
                                ref,
                                room,
                              ),
                            ),
                            child: RoomCard(
                              key: ValueKey('room-card-${room.id}'),
                              room: room,
                              thingCount: assetsByRoom[room.id]?.length ?? 0,
                              tasks: tasksByRoom[room.id] ?? const [],
                              onTap: () =>
                                  context.push('/assets/room/${room.id}'),
                              onAddThing: () => showAssetEditorSheet(
                                context,
                                roomId: room.id,
                              ),
                              onEdit: () => showRoomEditorSheet(
                                context,
                                areaId: room.areaId,
                                room: room,
                              ),
                              onMoveUp: index > 0
                                  ? () => _moveRoom(filteredRooms, room, -1)
                                  : null,
                              onMoveDown: index < filteredRooms.length - 1
                                  ? () => _moveRoom(filteredRooms, room, 1)
                                  : null,
                              onArchive: () => deleteRoomWithConfirmation(
                                context,
                                ref,
                                room,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
              ],
            );
          },
          error: (error, _) =>
              ErrorPanel(message: _failureMessage(context, error)),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  List<Room> _filterRooms(List<Room> rooms) {
    final query = _roomQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return rooms;
    }
    return rooms.where((room) {
      return room.name.toLowerCase().contains(query) ||
          _roomTypeLabel(context, room.roomType).toLowerCase().contains(query);
    }).toList();
  }

  String _roomCountLabel(
    BuildContext context,
    int count,
    Area area, {
    required bool filtered,
  }) {
    if (filtered) {
      return area.kind == AreaKind.outdoor
          ? context.l10n.matchingZoneCount(count)
          : context.l10n.matchingRoomCount(count);
    }
    return area.kind == AreaKind.outdoor
        ? context.l10n.zoneCount(count)
        : context.l10n.roomCount(count);
  }

  Future<void> _moveArea(List<Area> areas, Area area, int direction) async {
    final index = areas.indexWhere((item) => item.id == area.id);
    final targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= areas.length) {
      return;
    }
    final target = areas[targetIndex];
    final repo = ref.read(assetRepositoryProvider);
    await repo.saveArea(
      id: area.id,
      name: area.name,
      kind: area.kind,
      sortOrder: target.sortOrder,
    );
    await repo.saveArea(
      id: target.id,
      name: target.name,
      kind: target.kind,
      sortOrder: area.sortOrder,
    );
  }

  Future<void> _moveRoom(List<Room> rooms, Room room, int direction) async {
    final index = rooms.indexWhere((item) => item.id == room.id);
    final targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= rooms.length) {
      return;
    }
    final target = rooms[targetIndex];
    final repo = ref.read(assetRepositoryProvider);
    await repo.saveRoom(
      id: room.id,
      areaId: room.areaId,
      name: room.name,
      roomType: room.roomType,
      notes: room.notes,
      sortOrder: target.sortOrder,
    );
    await repo.saveRoom(
      id: target.id,
      areaId: target.areaId,
      name: target.name,
      roomType: target.roomType,
      notes: target.notes,
      sortOrder: room.sortOrder,
    );
  }
}

class _RoomsRenderData {
  _RoomsRenderData({
    required this.areas,
    required this.rooms,
    required this.assets,
    required this.tasks,
    required this.ready,
    required this.error,
  }) : fingerprint = Object.hash(
         areaListFingerprint(areas),
         roomListFingerprint(rooms),
         assetListFingerprint(assets),
         taskListFingerprint(tasks),
         ready,
         error?.toString(),
       );

  final List<Area> areas;
  final List<Room> rooms;
  final List<Asset> assets;
  final List<TaskItem> tasks;
  final bool ready;
  final Object? error;
  final int fingerprint;
}

class AreaSelector extends StatelessWidget {
  const AreaSelector({
    required this.areas,
    required this.selectedAreaId,
    required this.roomCountsByArea,
    required this.onSelected,
    super.key,
  });

  final List<Area> areas;
  final String selectedAreaId;
  final Map<String, int> roomCountsByArea;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('area-selector-row'),
      children: [
        for (var index = 0; index < areas.length; index++) ...[
          Expanded(
            child: AreaChip(
              area: areas[index],
              selected: areas[index].id == selectedAreaId,
              roomCount: roomCountsByArea[areas[index].id] ?? 0,
              onTap: () => onSelected(areas[index].id),
            ),
          ),
          if (index != areas.length - 1) const SizedBox(width: HkSpacing.xs),
        ],
      ],
    );
  }
}

class AreaChip extends StatelessWidget {
  const AreaChip({
    required this.area,
    required this.selected,
    required this.roomCount,
    required this.onTap,
    super.key,
  });

  final Area area;
  final bool selected;
  final int roomCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    final countLabel = area.kind == AreaKind.outdoor
        ? context.l10n.zoneCount(roomCount)
        : context.l10n.roomCount(roomCount);
    return Semantics(
      selected: selected,
      button: true,
      label: '${area.name}, $countLabel',
      child: InkWell(
        key: ValueKey('area-chip-${area.id}'),
        borderRadius: BorderRadius.circular(HkRadii.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          padding: const EdgeInsets.symmetric(
            horizontal: HkSpacing.xs,
            vertical: HkSpacing.base,
          ),
          decoration: BoxDecoration(
            color: selected
                ? scheme.secondaryContainer
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(HkRadii.lg),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.36)
                  : scheme.outlineVariant.withValues(alpha: 0.34),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? Symbols.check_rounded : _iconForArea(area),
                    color: foreground,
                    size: 15,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: DynamicText(
                        area.name,
                        contentType: 'area.name',
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                countLabel,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SelectedAreaTools extends StatelessWidget {
  const SelectedAreaTools({
    required this.area,
    required this.canMoveBack,
    required this.canMoveForward,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveBack,
    required this.onMoveForward,
    super.key,
  });

  final Area area;
  final bool canMoveBack;
  final bool canMoveForward;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;
  final VoidCallback onMoveBack;
  final VoidCallback onMoveForward;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.SwipeDelete(
      dismissKey: ValueKey('area-delete-${area.id}'),
      action: hk_ui.SwipeAction.moveToTrash(onAction: onDelete),
      child: hk_ui.PremiumCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        borderRadius: hk_ui.kSwipeRowRadius,
        child: Row(
          children: [
            Icon(_iconForArea(area), color: scheme.primary, size: 20),
            const SizedBox(width: HkSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DynamicText(
                    area.name,
                    contentType: 'area.name',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    _areaKindLabel(context, area.kind),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              useRootNavigator: true,
              tooltip: context.l10n.areaActions,
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'delete') {
                  onDelete();
                } else if (value == 'back') {
                  onMoveBack();
                } else if (value == 'forward') {
                  onMoveForward();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.l10n.editArea),
                ),
                PopupMenuItem(
                  value: 'back',
                  enabled: canMoveBack,
                  child: Text(context.l10n.moveEarlier),
                ),
                PopupMenuItem(
                  value: 'forward',
                  enabled: canMoveForward,
                  child: Text(context.l10n.moveLater),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.moveAreaToTrash),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PopupActionLabel extends StatelessWidget {
  const _PopupActionLabel({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: HkSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: destructive ? color : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaSeparator extends StatelessWidget {
  const _MetaSeparator();

  @override
  Widget build(BuildContext context) {
    return Text(
      ' | ',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class RoomCard extends StatelessWidget {
  const RoomCard({
    required this.room,
    required this.thingCount,
    required this.tasks,
    required this.onTap,
    required this.onAddThing,
    required this.onEdit,
    this.onMoveUp,
    this.onMoveDown,
    this.onArchive,
    super.key,
  });

  final Room room;
  final int thingCount;
  final List<TaskItem> tasks;
  final VoidCallback onTap;
  final VoidCallback onAddThing;
  final VoidCallback onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final buckets = getTaskBuckets(tasks, DateTime.now());
    final overdue = buckets.overdueCount;
    final dueToday = buckets.todayCount;
    final scheme = Theme.of(context).colorScheme;
    final statusColor = overdue > 0
        ? HkColors.tertiary
        : dueToday > 0
        ? HkColors.amber
        : scheme.primary;
    final taskStatus = tasks.isEmpty
        ? context.l10n.roomTaskStatusNoTasks
        : overdue > 0
        ? context.l10n.roomTaskStatusOverdue(overdue)
        : dueToday > 0
        ? context.l10n.roomTaskStatusDueToday(dueToday)
        : context.l10n.onTrack;
    final typeLabel = _roomTypeLabel(context, room.roomType);
    final itemCountLabel = context.l10n.itemCount(thingCount);
    return hk_ui.PremiumCard(
      padding: EdgeInsets.zero,
      borderRadius: hk_ui.kSwipeRowRadius,
      child: InkWell(
        borderRadius: BorderRadius.circular(hk_ui.kSwipeRowRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconForRoom(room),
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DynamicText(
                      room.name,
                      contentType: 'room.name',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 1,
                      children: [
                        if (typeLabel != room.name) ...[
                          Text(
                            typeLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const _MetaSeparator(),
                        ],
                        Text(
                          itemCountLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const _MetaSeparator(),
                        Text(
                          taskStatus,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              SizedBox(
                width: 44,
                height: 44,
                child: PopupMenuButton<String>(
                  useRootNavigator: true,
                  tooltip: context.l10n.roomActions,
                  constraints: const BoxConstraints(minWidth: 196),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: const Icon(Symbols.more_vert_rounded),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'thing') {
                      onAddThing();
                    } else if (value == 'up') {
                      onMoveUp?.call();
                    } else if (value == 'down') {
                      onMoveDown?.call();
                    } else if (value == 'archive') {
                      onArchive?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'thing',
                      child: _PopupActionLabel(
                        icon: Symbols.add_home_work_rounded,
                        label: context.l10n.addItem,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: _PopupActionLabel(
                        icon: Symbols.edit_rounded,
                        label: context.l10n.edit,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'up',
                      enabled: onMoveUp != null,
                      child: _PopupActionLabel(
                        icon: Symbols.arrow_upward_rounded,
                        label: context.l10n.moveUp,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'down',
                      enabled: onMoveDown != null,
                      child: _PopupActionLabel(
                        icon: Symbols.arrow_downward_rounded,
                        label: context.l10n.moveDown,
                      ),
                    ),
                    if (onArchive != null)
                      PopupMenuItem(
                        value: 'archive',
                        child: _PopupActionLabel(
                          icon: Symbols.delete_rounded,
                          label: context.l10n.moveRoomToTrash,
                          destructive: true,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoomDetailScreen extends ConsumerWidget {
  const RoomDetailScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider).value ?? [];
    final areas = ref.watch(areasProvider).value ?? [];
    final categories = ref.watch(categoriesProvider).value ?? [];
    final assets = ref.watch(roomAssetsProvider(roomId));
    final tasks = ref.watch(tasksProvider).value ?? [];
    final room = rooms.where((item) => item.id == roomId).firstOrNull;
    final areaName = room == null
        ? null
        : areas.where((area) => area.id == room.areaId).firstOrNull?.name;
    final categoryById = {
      for (final category in categories) category.id: category,
    };
    return Scaffold(
      appBar: AppBar(
        title: room == null
            ? Text(context.l10n.room)
            : DynamicText(room.name, contentType: 'room.name'),
        actions: [
          IconButton(
            tooltip: context.l10n.addItem,
            onPressed: () => showAssetEditorSheet(context, roomId: roomId),
            icon: const Icon(Symbols.add_home_work_rounded),
          ),
          if (room != null)
            IconButton(
              tooltip: context.l10n.editRoom,
              onPressed: () =>
                  showRoomEditorSheet(context, areaId: room.areaId, room: room),
              icon: const Icon(Symbols.edit_rounded),
            ),
        ],
      ),
      body: assets.when(
        data: (items) {
          final grouped = <AssetType, List<Asset>>{
            for (final type in AssetType.values) type: [],
          };
          for (final asset in items) {
            grouped[asset.assetType]?.add(asset);
          }
          final roomTasks = tasks
              .where((task) => task.room.id == roomId)
              .toList();
          final now = DateTime.now();
          final roomHealth = room == null
              ? null
              : feature_selectors.roomHealthScore(
                  room: room,
                  assets: items,
                  tasks: tasks,
                  now: now,
                );
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              HkSpacing.bottomAction,
            ),
            children: [
              const HkNativeAdCard(placement: 'room_detail'),
              const SizedBox(height: HkSpacing.sm),
              hk_ui.PremiumCard(
                child: Row(
                  children: [
                    const hk_ui.BrandMark(size: 44),
                    const SizedBox(width: HkSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            areaName ?? context.l10n.homeArea,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '${context.l10n.itemCount(items.length)} \u00B7 ${context.l10n.taskCountLabel(roomTasks.length)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (roomHealth != null)
                            Text(
                              context.l10n.roomHealthSemantic(
                                roomHealth.score,
                                _healthStateLabel(context, roomHealth.state),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HkSpacing.md),
              if (items.isEmpty)
                hk_ui.PremiumEmptyState(
                  icon: Symbols.inventory_2_rounded,
                  title: context.l10n.noItemsInThisRoom,
                  body: context.l10n.addItemsToRoomBody,
                  action: FilledButton.icon(
                    onPressed: () =>
                        showAssetEditorSheet(context, roomId: roomId),
                    icon: const Icon(Symbols.add_home_work_rounded),
                    label: Text(context.l10n.addItem),
                  ),
                )
              else
                for (final entry in grouped.entries.where(
                  (entry) => entry.value.isNotEmpty,
                )) ...[
                  hk_ui.SectionHeader(
                    title:
                        '${_assetTypePluralLabel(context, entry.key)} · ${entry.value.length}',
                  ),
                  for (final asset in entry.value)
                    hk_ui.SwipeDelete(
                      margin: const EdgeInsets.only(bottom: HkSpacing.xs),
                      dismissKey: ValueKey('thing-delete-${asset.id}'),
                      action: hk_ui.SwipeAction.moveToTrash(
                        onAction: () =>
                            deleteThingWithConfirmation(context, ref, asset),
                      ),
                      child: ThingCard(
                        asset: asset,
                        category: categoryById[asset.categoryId],
                        dueStatus: itemTaskStatusFor(asset, tasks, now),
                        margin: EdgeInsets.zero,
                        onTap: () => context.push('/assets/thing/${asset.id}'),
                        onEdit: () =>
                            showAssetEditorSheet(context, asset: asset),
                        onPhoto: () => addPhotoToAsset(context, ref, asset),
                        onArchive: () =>
                            deleteThingWithConfirmation(context, ref, asset),
                      ),
                    ),
                ],
            ],
          );
        },
        error: (error, _) =>
            ErrorPanel(message: _failureMessage(context, error)),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.planId, super.key});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskState = ref.watch(taskDetailProvider(planId));
    return taskState.when(
      data: (task) {
        if (task == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.task)),
            body: Center(child: Text(context.l10n.taskNotFound)),
          );
        }
        final records = ref.watch(taskRecordsProvider(planId));
        return Scaffold(
          appBar: AppBar(
            title: DynamicText(
              task.plan.title,
              contentType: 'maintenance_plan.title',
            ),
            actions: [
              IconButton(
                tooltip: context.l10n.editTask,
                onPressed: () => showPlanEditorSheet(context, task: task),
                icon: const Icon(Symbols.edit_rounded),
              ),
              PopupMenuButton<String>(
                useRootNavigator: true,
                tooltip: context.l10n.taskActions,
                onSelected: (value) async {
                  if (value == 'skip') {
                    await skipTaskWithConfirmation(context, ref, task);
                    return;
                  }
                  if (value == 'postpone') {
                    await postponeTaskWithDialog(context, ref, task);
                    return;
                  }
                  if (value == 'set_enabled') {
                    await setTaskEnabledWithFeedback(
                      context,
                      ref,
                      task,
                      !task.plan.isEnabled,
                    );
                    return;
                  }
                  if (value == 'delete') {
                    final deleted = await deleteTaskWithConfirmation(
                      context,
                      ref,
                      task,
                    );
                    if (deleted && context.mounted) {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/maintenance');
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  if (task.plan.isEnabled)
                    PopupMenuItem(
                      value: 'skip',
                      child: _PopupActionLabel(
                        icon: Symbols.skip_next_rounded,
                        label: context.l10n.skipThisOccurrence,
                      ),
                    ),
                  if (task.plan.isEnabled)
                    PopupMenuItem(
                      value: 'postpone',
                      child: _PopupActionLabel(
                        icon: Symbols.edit_calendar_rounded,
                        label: context.l10n.postponeDueDate,
                      ),
                    ),
                  PopupMenuItem(
                    value: 'set_enabled',
                    child: _PopupActionLabel(
                      icon: task.plan.isEnabled
                          ? Symbols.pause_circle_rounded
                          : Symbols.play_circle_rounded,
                      label: task.plan.isEnabled
                          ? 'Disable task'
                          : 'Enable task',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _PopupActionLabel(
                      icon: Symbols.delete_rounded,
                      label: context.l10n.moveTaskToTrash,
                      destructive: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          bottomNavigationBar: task.plan.isEnabled
              ? hk_ui.PremiumBottomActionBar(
                  label: context.l10n.completeTask,
                  icon: Symbols.check_circle_rounded,
                  onPressed: () async {
                    await completeTaskWithFeedback(
                      context,
                      ref,
                      task,
                      collectNotes: true,
                    );
                  },
                )
              : null,
          body: RepaintBoundary(
            key: const ValueKey('task-detail-stability-boundary'),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                HkSpacing.bottomAction,
              ),
              children: [
                hk_ui.PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            child: Icon(_iconForGroup(task.plan.healthGroup)),
                          ),
                          const SizedBox(width: HkSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DynamicText(
                                  task.plan.title,
                                  contentType: 'maintenance_plan.title',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                DynamicText(
                                  '${task.asset.name} \u00B7 ${task.room.name}',
                                  contentType: 'task.location',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: HkSpacing.xs),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (task.plan.isEnabled)
                            hk_ui.StatusPill(
                              label: _taskStatusLabel(context, task.status),
                              color: _taskStatusColor(context, task.status),
                            )
                          else
                            hk_ui.StatusPill(
                              label: context.l10n.disabled,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              icon: Symbols.pause_circle_rounded,
                              semanticLabel: context.l10n.taskDisabled,
                            ),
                          hk_ui.StatusPill(
                            label: _recurrenceLabel(
                              context,
                              task.plan.recurrence,
                            ),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          hk_ui.StatusPill(
                            label: _priorityLabel(context, task.plan.priority),
                            color: HkColors.tertiary,
                          ),
                        ],
                      ),
                      const SizedBox(height: HkSpacing.xs),
                      _DetailRow(
                        icon: Symbols.event_rounded,
                        label: context.l10n.nextDue,
                        value: _formatLongDate(context, task.plan.nextDueDate),
                      ),
                      _DetailRow(
                        icon: Symbols.category_rounded,
                        label: context.l10n.category,
                        value: task.category.name,
                      ),
                      if (task.plan.reminderDaysBefore > 0)
                        _DetailRow(
                          icon: Symbols.notifications_active_rounded,
                          label: context.l10n.reminder,
                          value:
                              '${task.plan.reminderDaysBefore} ${task.plan.reminderDaysBefore == 1 ? 'day' : 'days'} before due',
                        ),
                      if (task.plan.instructions?.trim().isNotEmpty ?? false)
                        _DetailRow(
                          icon: Symbols.notes_rounded,
                          label: context.l10n.instructions,
                          value: task.plan.instructions!,
                          contentType: 'maintenance_plan.instructions',
                        ),
                      ..._taskMetadataRows(context, task.plan.metadata),
                      const SizedBox(height: HkSpacing.xs),
                      _TaskItemActionRow(
                        itemName: task.asset.name,
                        roomName: task.room.name,
                        onOpen: () =>
                            context.push('/assets/thing/${task.asset.id}'),
                      ),
                    ],
                  ),
                ),
                hk_ui.SectionHeader(
                  title: context.l10n.timeline,
                  subtitle: context.l10n.completionHistoryForThisTask,
                ),
                records.when(
                  data: (items) => _MaintenanceTimeline(
                    records: items,
                    taskTitle: task.plan.title,
                  ),
                  error: (error, _) =>
                      ErrorPanel(message: _failureMessage(context, error)),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
        );
      },
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.task)),
        body: ErrorPanel(message: _failureMessage(context, error)),
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class _TaskItemActionRow extends StatelessWidget {
  const _TaskItemActionRow({
    required this.itemName,
    required this.roomName,
    required this.onOpen,
  });

  final String itemName;
  final String roomName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(HkRadii.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Symbols.inventory_2_rounded,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.item,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$itemName · $roomName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onOpen,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(context.l10n.openItem),
          ),
        ],
      ),
    );
  }
}

class ThingDetailScreen extends ConsumerStatefulWidget {
  const ThingDetailScreen({required this.assetId, super.key});

  final String assetId;

  @override
  ConsumerState<ThingDetailScreen> createState() => _ThingDetailScreenState();
}

class _ItemActionButtons extends StatelessWidget {
  const _ItemActionButtons({required this.onAddPhoto, required this.onAddTask});

  final VoidCallback onAddPhoto;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 304;
        final photo = _ItemActionButton(
          key: const ValueKey('item-add-photo'),
          icon: Symbols.add_photo_alternate_rounded,
          label: context.l10n.addPhoto,
          onPressed: onAddPhoto,
        );
        final task = _ItemActionButton(
          key: const ValueKey('item-add-task'),
          icon: Symbols.add_task_rounded,
          label: context.l10n.addTask,
          onPressed: onAddTask,
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [photo, const SizedBox(height: 8), task],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: photo),
            const SizedBox(width: 10),
            Expanded(child: task),
          ],
        );
      },
    );
  }
}

class _ItemActionButton extends StatelessWidget {
  const _ItemActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 21),
            const SizedBox(width: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ItemHealthCard extends StatelessWidget {
  const _ItemHealthCard({required this.score, this.warrantyUntil});

  final features.EntityHealthScore score;
  final DateTime? warrantyUntil;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (score.state) {
      features.HealthState.excellent ||
      features.HealthState.good => scheme.primary,
      features.HealthState.attention => HkColors.amber,
      features.HealthState.critical => scheme.error,
      features.HealthState.insufficientData => scheme.outline,
    };
    final healthValue = score.state == features.HealthState.insufficientData
        ? context.l10n.needsSetup
        : context.l10n.itemHealthPercent(score.score);
    return hk_ui.PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.health_and_safety_rounded, color: color),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Text(
                  context.l10n.itemHealthSemantic(healthValue),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              hk_ui.StatusPill(
                compact: true,
                label: _healthStateLabel(context, score.state),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.xs),
          for (final reason in score.reasons)
            Text('- ${_localizedFeatureMessage(context, reason)}'),
          if (score.nextBestAction != null) ...[
            const SizedBox(height: HkSpacing.space4),
            Text(
              context.l10n.nextValue(
                _localizedFeatureMessage(context, score.nextBestAction!),
              ),
            ),
          ],
          if (warrantyUntil != null) ...[
            const SizedBox(height: HkSpacing.xs),
            Text(
              context.l10n.warrantyUntilDate(
                _formatShortDate(context, warrantyUntil!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<Widget> _taskMetadataRows(BuildContext context, TaskMetadata? metadata) {
  if (metadata == null) {
    return const [];
  }
  return [
    if (metadata.taskType?.trim().isNotEmpty ?? false)
      _DetailRow(
        icon: Symbols.build_circle_rounded,
        label: context.l10n.taskType,
        value: metadata.taskType!.trim(),
      ),
    if (metadata.locationLabel?.trim().isNotEmpty ?? false)
      _DetailRow(
        icon: Symbols.place_rounded,
        label: context.l10n.location,
        value: metadata.locationLabel!.trim(),
      ),
    if (metadata.estimatedDurationMinutes != null)
      _DetailRow(
        icon: Symbols.timer_rounded,
        label: context.l10n.duration,
        value:
            '${metadata.estimatedDurationMinutes} ${metadata.estimatedDurationMinutes == 1 ? 'minute' : 'minutes'}',
      ),
    if (metadata.requiredMaterials.isNotEmpty)
      _DetailRow(
        icon: Symbols.construction_rounded,
        label: context.l10n.materials,
        value: metadata.requiredMaterials.join(', '),
      ),
    if (metadata.dependencyPlanIds.isNotEmpty)
      _DetailRow(
        icon: Symbols.account_tree_rounded,
        label: context.l10n.dependsOn,
        value:
            '${metadata.dependencyPlanIds.length} linked ${metadata.dependencyPlanIds.length == 1 ? 'task' : 'tasks'}',
      ),
    if (metadata.reminderRecommendation?.trim().isNotEmpty ?? false)
      _DetailRow(
        icon: Symbols.notification_important_rounded,
        label: context.l10n.reminder,
        value: metadata.reminderRecommendation!.trim(),
      ),
  ];
}

class _ThingDetailScreenState extends ConsumerState<ThingDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final assetState = ref.watch(assetDetailProvider(widget.assetId));
    return assetState.when(
      data: (asset) {
        if (asset == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.item)),
            body: Center(child: Text(context.l10n.itemNotFound)),
          );
        }
        final categories = ref.watch(categoriesProvider).value ?? [];
        final rooms = ref.watch(roomsProvider).value ?? [];
        final category = categories
            .where((item) => item.id == asset.categoryId)
            .firstOrNull;
        final room = rooms.where((item) => item.id == asset.roomId).firstOrNull;
        final tasks = ref.watch(assetSavedTasksProvider(asset.id));
        final tags = ref.watch(assetTagsProvider(asset.id)).value ?? [];
        final photos = ref.watch(assetPhotosProvider(asset.id)).value ?? [];
        final relatedTasks = tasks.value ?? [];
        final hasCriticalAlert = relatedTasks.any(
          (task) =>
              isTaskActionable(task) &&
              task.plan.priority == PriorityLevel.critical,
        );
        final activeRelatedTaskCount = relatedTasks
            .where(isTaskActionable)
            .length;
        return Scaffold(
          appBar: AppBar(
            title: DynamicText(asset.name, contentType: 'asset.name'),
            actions: [
              IconButton(
                tooltip: context.l10n.editItem,
                onPressed: () => showAssetEditorSheet(context, asset: asset),
                icon: const Icon(Symbols.edit_rounded),
              ),
              PopupMenuButton<String>(
                useRootNavigator: true,
                tooltip: context.l10n.itemActions,
                onSelected: (value) async {
                  if (value == 'move_copy') {
                    await showMoveCopyItemSheet(context, asset);
                    return;
                  }
                  if (value == 'delete') {
                    final deleted = await deleteThingWithConfirmation(
                      context,
                      ref,
                      asset,
                    );
                    if (deleted && context.mounted) {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/assets/room/${asset.roomId}');
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'move_copy',
                    child: _PopupActionLabel(
                      icon: Symbols.drive_file_move_rounded,
                      label: context.l10n.moveOrCopy,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _PopupActionLabel(
                      icon: Symbols.delete_rounded,
                      label: context.l10n.moveItemToTrash,
                      destructive: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: RepaintBoundary(
            key: const ValueKey('item-detail-stability-boundary'),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.gutter,
                8,
                HkSpacing.gutter,
                HkSpacing.xl,
              ),
              children: [
                if (!hasCriticalAlert) ...[
                  const HkNativeAdCard(placement: 'thing_detail'),
                  const SizedBox(height: HkSpacing.sm),
                ],
                hk_ui.PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _ThingAvatar(asset: asset, photos: photos, size: 40),
                          const SizedBox(width: HkSpacing.xs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DynamicText(
                                  asset.name,
                                  contentType: 'asset.name',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  [
                                    _assetTypeLabel(context, asset.assetType),
                                    if (category != null) category.name,
                                    if (room != null) room.name,
                                    if (asset.placement != null)
                                      asset.placement!,
                                  ].join(' \u00B7 '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: HkSpacing.xs),
                      _ThingDetailFields(asset: asset),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: HkSpacing.sm),
                        Wrap(
                          spacing: HkSpacing.xs,
                          runSpacing: HkSpacing.xs,
                          children: [
                            for (final tag in tags)
                              hk_ui.StatusPill(
                                label: tag.name,
                                color: Theme.of(context).colorScheme.primary,
                                contentType: 'tag.name',
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: HkSpacing.sm),
                      _ItemActionButtons(
                        onAddPhoto: () => addPhotoToAsset(context, ref, asset),
                        onAddTask: () =>
                            showPlanEditorSheet(context, assetId: asset.id),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HkSpacing.sm),
                _ItemHealthCard(
                  score: feature_selectors.itemHealthScore(
                    asset: asset,
                    tasks: relatedTasks,
                    now: DateTime.now(),
                  ),
                  warrantyUntil: asset.deviceDetails?.warrantyUntil,
                ),
                hk_ui.SectionHeader(
                  title: context.l10n.relatedTasks,
                  subtitle: context.l10n.activeTaskCount(
                    activeRelatedTaskCount,
                  ),
                ),
                tasks.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return hk_ui.PremiumEmptyState(
                        icon: Symbols.task_alt_rounded,
                        title: context.l10n.noTasksYet,
                        body: context.l10n.createRecurringCareForThisItem,
                        action: hk_ui.CompactActionGroup(
                          children: [
                            FilledButton.icon(
                              onPressed: () => showPlanEditorSheet(
                                context,
                                assetId: asset.id,
                              ),
                              icon: const Icon(Symbols.add_task_rounded),
                              label: Text(context.l10n.addTask),
                            ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final task in items)
                          hk_ui.SwipeDelete(
                            margin: const EdgeInsets.only(bottom: HkSpacing.sm),
                            dismissKey: ValueKey(
                              'thing-task-delete-${task.plan.id}',
                            ),
                            action: hk_ui.SwipeAction.moveToTrash(
                              onAction: () => deleteTaskWithConfirmation(
                                context,
                                ref,
                                task,
                              ),
                            ),
                            child: hk_ui.TaskCard(
                              task: task,
                              margin: EdgeInsets.zero,
                              onTap: () =>
                                  context.push('/maintenance/${task.plan.id}'),
                              onComplete: () => completeTaskWithFeedback(
                                context,
                                ref,
                                task,
                                collectNotes: true,
                              ),
                              onEdit: () =>
                                  showPlanEditorSheet(context, task: task),
                              onSnooze: () =>
                                  snoozeTaskWithFeedback(context, ref, task),
                              onSetEnabled: (enabled) =>
                                  setTaskEnabledWithFeedback(
                                    context,
                                    ref,
                                    task,
                                    enabled,
                                  ),
                              onArchive: () => deleteTaskWithConfirmation(
                                context,
                                ref,
                                task,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                  error: (error, _) =>
                      ErrorPanel(message: _failureMessage(context, error)),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                ),
                hk_ui.SectionHeader(
                  title: context.l10n.timeline,
                  subtitle: context.l10n.completionHistoryAcrossRelatedTasks,
                ),
                _ThingTimeline(
                  tasks: relatedTasks,
                  records: ref.watch(assetRecordsProvider(asset.id)),
                ),
                if (photos.isNotEmpty) ...[
                  hk_ui.SectionHeader(
                    title: context.l10n.photos,
                    subtitle: context.l10n.savedPhotoCount(photos.length),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 520 ? 3 : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: photos.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: HkSpacing.sm,
                          mainAxisSpacing: HkSpacing.sm,
                          mainAxisExtent: 176,
                        ),
                        itemBuilder: (context, index) {
                          final photo = photos[index];
                          return _ThingPhotoTile(
                            photo: photo,
                            onPrimary: () =>
                                _setPrimaryPhoto(ref, asset, photo),
                            onDelete: () =>
                                _deletePhoto(context, ref, asset, photo),
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.item)),
        body: ErrorPanel(message: _failureMessage(context, error)),
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }

  Future<void> _setPrimaryPhoto(
    WidgetRef ref,
    Asset asset,
    AssetPhoto photo,
  ) async {
    await ref.read(assetRepositoryProvider).setPrimaryPhoto(asset.id, photo.id);
  }

  Future<void> _deletePhoto(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
    AssetPhoto photo,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deletePhoto,
      message: context.l10n.deleteSavedPhotoFromItem(asset.name),
    );
    if (!confirmed) {
      return;
    }
    await ref.read(assetRepositoryProvider).deletePhoto(photo.id);
    if (!context.mounted) {
      return;
    }
  }
}

class _ThingDetailFields extends StatelessWidget {
  const _ThingDetailFields({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (asset.notes?.trim().isNotEmpty ?? false)
        _DetailRow(
          icon: Symbols.notes_rounded,
          label: context.l10n.notes,
          value: asset.notes!,
          contentType: 'asset.notes',
        ),
      if (asset.purchaseDate != null)
        _DetailRow(
          icon: Symbols.shopping_bag_rounded,
          label: context.l10n.purchased,
          value: _formatShortDate(context, asset.purchaseDate!),
        ),
      ..._typedRows(context),
    ];
    if (rows.isEmpty) {
      return Row(
        children: [
          const hk_ui.HkStateIllustration(
            icon: Symbols.info_rounded,
            tone: hk_ui.HkIllustrationTone.neutral,
            size: 42,
            compact: true,
          ),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              context.l10n.noExtraDetailsYet,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    return Column(children: rows);
  }

  List<Widget> _typedRows(BuildContext context) {
    final device = asset.deviceDetails;
    final pet = asset.petDetails;
    final plant = asset.plantDetails;
    final safety = asset.safetyDetails;
    return [
      if (device?.brand != null)
        _DetailRow(
          icon: Symbols.memory_rounded,
          label: context.l10n.brand,
          value: device!.brand!,
        ),
      if (device?.model != null)
        _DetailRow(
          icon: Symbols.info_rounded,
          label: context.l10n.model,
          value: device!.model!,
        ),
      if (device?.consumable != null)
        _DetailRow(
          icon: Symbols.inventory_2_rounded,
          label: context.l10n.consumable,
          value: device!.consumable!,
          contentType: 'asset.device.consumable',
        ),
      if (pet?.species != null)
        _DetailRow(
          icon: Symbols.pets_rounded,
          label: context.l10n.species,
          value: pet!.species!,
          contentType: 'asset.pet.species',
        ),
      if (pet?.feedingNotes != null)
        _DetailRow(
          icon: Symbols.restaurant_rounded,
          label: context.l10n.feeding,
          value: pet!.feedingNotes!,
          contentType: 'asset.pet.feeding_notes',
        ),
      if (plant?.species != null)
        _DetailRow(
          icon: Symbols.yard_rounded,
          label: context.l10n.species,
          value: plant!.species!,
          contentType: 'asset.plant.species',
        ),
      if (plant?.wateringIntervalDays != null)
        _DetailRow(
          icon: Symbols.water_drop_rounded,
          label: context.l10n.watering,
          value: context.l10n.recurrenceEveryMany(
            plant!.wateringIntervalDays!,
            context.l10n.days2,
          ),
        ),
      if (safety?.safetyType != null)
        _DetailRow(
          icon: Symbols.health_and_safety_rounded,
          label: context.l10n.safetyType,
          value: safety!.safetyType!,
          contentType: 'asset.safety.type',
        ),
      if (safety?.testIntervalDays != null)
        _DetailRow(
          icon: Symbols.fact_check_rounded,
          label: context.l10n.testInterval,
          value: context.l10n.recurrenceEveryMany(
            safety!.testIntervalDays!,
            context.l10n.days2,
          ),
        ),
    ];
  }
}

class _ThingTimeline extends StatelessWidget {
  const _ThingTimeline({required this.tasks, required this.records});

  final List<TaskItem> tasks;
  final AsyncValue<List<MaintenanceRecord>> records;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return hk_ui.PremiumEmptyState(
        icon: Symbols.history_rounded,
        title: context.l10n.noTimelineYet,
        body: context.l10n.completedTasksForThisItemAppearHere,
      );
    }
    return records.when(
      data: (items) => _MaintenanceTimeline(
        records: items,
        taskTitleByPlanId: {
          for (final task in tasks) task.plan.id: task.plan.title,
        },
      ),
      error: (error, _) => ErrorPanel(message: _failureMessage(context, error)),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _MaintenanceTimeline extends StatelessWidget {
  const _MaintenanceTimeline({
    required this.records,
    this.taskTitle,
    this.taskTitleByPlanId = const {},
  });

  final List<MaintenanceRecord> records;
  final String? taskTitle;
  final Map<String, String> taskTitleByPlanId;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return hk_ui.PremiumEmptyState(
        icon: Symbols.history_rounded,
        title: context.l10n.noTimelineYet,
        body: context.l10n.completedWorkWillAppearHere,
      );
    }
    final sorted = [...records]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    final children = <Widget>[];
    DateTime? previousDay;
    for (var index = 0; index < sorted.length; index++) {
      final record = sorted[index];
      final day = hk_dates.dateOnly(record.completedAt);
      if (previousDay == null || !hk_dates.isSameDate(day, previousDay)) {
        children.add(_TimelineDateHeader(date: record.completedAt));
        previousDay = day;
      }
      final title =
          taskTitleByPlanId[record.planId] ?? taskTitle ?? context.l10n.task;
      children.add(
        _TimelineRecordTile(
          record: record,
          title: title,
          isLast: index == sorted.length - 1,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _TimelineDateHeader extends StatelessWidget {
  const _TimelineDateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, HkSpacing.sm, 2, HkSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(HkRadii.md),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(
              Symbols.calendar_month_rounded,
              color: scheme.primary,
              size: 16,
            ),
          ),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              _formatLongDate(context, date),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRecordTile extends StatelessWidget {
  const _TimelineRecordTile({
    required this.record,
    required this.title,
    required this.isLast,
  });

  final MaintenanceRecord record;
  final String title;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notes = record.notes?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: HkShadows.ambient(tint: scheme.primary),
                ),
                child: Icon(
                  Symbols.check_rounded,
                  color: scheme.onPrimary,
                  size: 14,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 64,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(HkRadii.full),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: HkSpacing.xs),
        Expanded(
          child: hk_ui.PremiumCard(
            margin: const EdgeInsets.only(bottom: HkSpacing.xs),
            padding: const EdgeInsets.all(10),
            borderRadius: HkRadii.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    hk_ui.StatusPill(
                      label: _formatShortTime(context, record.completedAt),
                      color: HkColors.green,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: HkSpacing.space4),
                Text(
                  context.l10n.dueDateTimeLabel(
                    _formatShortDateTime(context, record.dueDate),
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: HkSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(HkRadii.md),
                    ),
                    child: Text(
                      notes,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.contentType,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? contentType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HkSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: HkSpacing.xs),
          SizedBox(
            width: 92,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: contentType == null
                ? Text(value)
                : DynamicText(value, contentType: contentType!),
          ),
        ],
      ),
    );
  }
}

class _ThingAvatar extends StatelessWidget {
  const _ThingAvatar({
    required this.asset,
    required this.photos,
    this.size = 52,
  });

  final Asset asset;
  final List<AssetPhoto> photos;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary =
        photos.where((photo) => photo.isPrimary).firstOrNull ??
        photos.firstOrNull;
    return FutureBuilder<File?>(
      future: _localFile(primary?.relativePath),
      builder: (context, snapshot) {
        final file = snapshot.data;
        final hasImage = file != null && file.existsSync();
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            color: scheme.secondaryContainer,
            child: hasImage
                ? Image.file(file, fit: BoxFit.cover)
                : Icon(
                    _iconForAssetType(asset.assetType),
                    color: scheme.primary,
                  ),
          ),
        );
      },
    );
  }
}

class _ThingPhotoTile extends StatelessWidget {
  const _ThingPhotoTile({
    required this.photo,
    required this.onPrimary,
    required this.onDelete,
  });

  final AssetPhoto photo;
  final VoidCallback onPrimary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FutureBuilder<File?>(
              future: _localFile(photo.relativePath),
              builder: (context, snapshot) {
                final file = snapshot.data;
                final hasImage = file != null && file.existsSync();
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(HkRadii.lg),
                  ),
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: hasImage
                        ? Image.file(file, fit: BoxFit.cover)
                        : const Icon(Symbols.broken_image_rounded),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    photo.isPrimary
                        ? context.l10n.primary
                        : _formatMonthDay(context, photo.createdAt),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: photo.isPrimary ? scheme.primary : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  useRootNavigator: true,
                  tooltip: context.l10n.photoActions,
                  onSelected: (value) {
                    if (value == 'primary') {
                      onPrimary();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'primary',
                      enabled: !photo.isPrimary,
                      child: _PopupActionLabel(
                        icon: Symbols.account_circle_rounded,
                        label: context.l10n.setPrimary,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: _PopupActionLabel(
                        icon: Symbols.delete_rounded,
                        label: context.l10n.delete,
                        destructive: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ThingCard extends ConsumerWidget {
  const ThingCard({
    required this.asset,
    required this.category,
    required this.onTap,
    required this.onEdit,
    required this.onPhoto,
    required this.onArchive,
    this.dueStatus,
    this.margin,
    super.key,
  });

  final Asset asset;
  final Category? category;
  final ItemTaskStatusSummary? dueStatus;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPhoto;
  final VoidCallback onArchive;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(assetPhotosProvider(asset.id)).value ?? const [];
    final status = dueStatus;
    final statusColor = status == null
        ? null
        : hk_ui.itemDueAccentColor(context, status.status);
    final subtitle = [
      _assetTypeLabel(context, asset.assetType),
      if (category != null) category!.name,
      if (asset.placement != null) asset.placement!,
    ].join(' · ');
    final card = hk_ui.PremiumCard(
      margin: margin ?? const EdgeInsets.only(bottom: HkSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      borderRadius: hk_ui.kSwipeRowRadius,
      borderColor: statusColor?.withValues(alpha: 0.22),
      child: Stack(
        children: [
          if (statusColor != null)
            Positioned(
              left: -10,
              top: -8,
              bottom: -8,
              child: Container(width: 3, color: statusColor),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ThingAvatar(asset: asset, photos: photos, size: 32),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DynamicText(
                      asset.name,
                      contentType: 'asset.name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    DynamicText(
                      subtitle,
                      contentType: 'asset.summary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (status != null) ...[
                      const SizedBox(height: HkSpacing.space4),
                      Wrap(
                        spacing: HkSpacing.space4,
                        runSpacing: HkSpacing.space4,
                        children: [
                          hk_ui.ItemDueIndicator(summary: status),
                          if (status.priority == PriorityLevel.critical)
                            hk_ui.StatusPill(
                              label: context.l10n.critical,
                              color: HkColors.appDanger,
                              compact: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              SizedBox(
                width: 44,
                height: 44,
                child: PopupMenuButton<String>(
                  useRootNavigator: true,
                  tooltip: context.l10n.itemActions,
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: const Icon(Symbols.more_vert_rounded),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'photo') {
                      onPhoto();
                    } else if (value == 'archive') {
                      onArchive();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(context.l10n.edit),
                    ),
                    PopupMenuItem(
                      value: 'photo',
                      child: Text(context.l10n.addPhoto),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(context.l10n.moveItemToTrash),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: [
        asset.name,
        subtitle,
        if (status != null) hk_ui.itemDueLabel(context, status),
        if (status?.priority == PriorityLevel.critical) context.l10n.critical,
      ].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({this.initialFilter, super.key});

  final String? initialFilter;

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final hasThings = ref.watch(
      assetsProvider.select((state) => state.value?.isNotEmpty ?? false),
    );
    final canAddThing = ref.watch(
      roomsProvider.select((state) => state.value?.isNotEmpty ?? false),
    );
    final taskItems = tasks.value ?? const <TaskItem>[];
    final taskBuckets = getTaskBuckets(taskItems, DateTime.now());
    final showFab =
        widget.initialFilter != 'today' || taskBuckets.today.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_taskScreenTitle(context, widget.initialFilter)),
        actions: [
          HkPointsPill(onTap: () => showPointsWalletSheet(context, ref)),
        ],
      ),
      floatingActionButton: showFab
          ? Padding(
              padding: const EdgeInsets.only(bottom: HkSpacing.bottomNav),
              child: hk_ui.HomePilotFloatingActionButton(
                tooltip: context.l10n.addTask,
                onPressed: _showCreateTaskMenu,
                icon: Symbols.add_rounded,
                label: context.l10n.addTask,
              ),
            )
          : null,
      body: hk_ui.ProductivityBackdrop(
        child: RepaintBoundary(
          key: const ValueKey('tasks-stability-boundary'),
          child: tasks.when(
            data: (items) {
              if (items.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    HkSpacing.bottomAction + HkSpacing.bottomNav,
                  ),
                  children: [
                    hk_ui.PremiumEmptyState(
                      icon: Symbols.task_alt_rounded,
                      title: hasThings
                          ? context.l10n.noScheduledTasks
                          : canAddThing
                          ? context.l10n.createAnItemFirst
                          : context.l10n.createARoomFirst,
                      body: hasThings
                          ? context.l10n.createRecurringPlanForMaintenanceQueue
                          : canAddThing
                          ? context.l10n.maintenanceTasksNeedAnItem
                          : context.l10n.addRoomOrZoneBeforeItemsAndTasks,
                      action: hasThings
                          ? FilledButton.icon(
                              onPressed: () => showPlanEditorSheet(context),
                              icon: const Icon(Symbols.add_task_rounded),
                              label: Text(context.l10n.addTask),
                            )
                          : FilledButton.icon(
                              onPressed: () =>
                                  startThingSetupFlow(context, ref),
                              icon: Icon(
                                canAddThing
                                    ? Symbols.add_home_work_rounded
                                    : Symbols.meeting_room_rounded,
                              ),
                              label: Text(
                                canAddThing
                                    ? context.l10n.createFirstItem
                                    : context.l10n.createFirstRoom,
                              ),
                            ),
                    ),
                  ],
                );
              }
              final buckets = getTaskBuckets(items, DateTime.now());
              final groups = _visibleTaskGroups(
                filter: widget.initialFilter,
                buckets: buckets,
                context: context,
              );
              final visibleCount = groups.fold<int>(
                0,
                (count, group) => count + group.tasks.length,
              );
              if (visibleCount == 0 && widget.initialFilter != null) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    HkSpacing.gutter,
                    HkSpacing.md,
                    HkSpacing.gutter,
                    HkSpacing.bottomAction + HkSpacing.bottomNav,
                  ),
                  children: [
                    _FilteredTaskEmptyState(
                      filter: widget.initialFilter!,
                      onAddTask: () => !hasThings
                          ? startThingSetupFlow(context, ref)
                          : showPlanEditorSheet(context),
                      onNextSeven: () =>
                          context.push('/maintenance?filter=next7'),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.gutter,
                  8,
                  HkSpacing.gutter,
                  HkSpacing.bottomAction + HkSpacing.bottomNav,
                ),
                children: [
                  const HkNativeAdCard(placement: 'maintenance'),
                  const SizedBox(height: HkSpacing.sm),
                  for (final group in groups)
                    TaskGroup(
                      title: widget.initialFilter == null
                          ? group.title
                          : _filteredTaskGroupTitle(
                              context,
                              widget.initialFilter!,
                              group.tasks.length,
                            ),
                      tasks: group.tasks,
                      color: group.color,
                      onComplete: (task) => _completeTask(context, ref, task),
                      onEdit: (task) =>
                          showPlanEditorSheet(context, task: task),
                      onSnooze: (task) =>
                          snoozeTaskWithFeedback(context, ref, task),
                      onSetEnabled: (task, enabled) =>
                          setTaskEnabledWithFeedback(
                            context,
                            ref,
                            task,
                            enabled,
                          ),
                      onDelete: (task) =>
                          deleteTaskWithConfirmation(context, ref, task),
                    ),
                ],
              );
            },
            error: (error, _) =>
                ErrorPanel(message: _failureMessage(context, error)),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateTaskMenu() async {
    final assets = ref.read(assetsProvider).value ?? const <Asset>[];
    final rooms = ref.read(roomsProvider).value ?? const <Room>[];
    final hasThings = assets.isNotEmpty;
    final canAddThing = rooms.isNotEmpty;
    final action = await runWithNativeAdsSuspended(
      context,
      () => showModalBottomSheet<_TaskCreateAction>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HkSpacing.gutter,
              0,
              HkSpacing.gutter,
              HkSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    hasThings
                        ? Symbols.add_task_rounded
                        : canAddThing
                        ? Symbols.add_home_work_rounded
                        : Symbols.meeting_room_rounded,
                  ),
                  title: Text(
                    hasThings
                        ? context.l10n.addTask
                        : canAddThing
                        ? context.l10n.createFirstItem
                        : context.l10n.createFirstRoom,
                  ),
                  subtitle: Text(
                    hasThings
                        ? context.l10n.createMaintenancePlanManually
                        : canAddThing
                        ? context.l10n.tasksNeedItemFirst
                        : context.l10n.itemsNeedRoomFirst,
                  ),
                  onTap: () => Navigator.of(context).pop(
                    hasThings
                        ? _TaskCreateAction.manual
                        : _TaskCreateAction.setup,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _TaskCreateAction.manual:
        showPlanEditorSheet(context);
        break;
      case _TaskCreateAction.setup:
        startThingSetupFlow(context, ref);
        break;
    }
  }

  Future<bool> _completeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    return completeTaskWithFeedback(context, ref, task, collectNotes: true);
  }
}

enum _TaskCreateAction { manual, setup }

class _TaskGroupData {
  const _TaskGroupData({
    required this.title,
    required this.tasks,
    required this.color,
  });

  final String title;
  final List<TaskItem> tasks;
  final Color color;
}

String _taskScreenTitle(BuildContext context, String? filter) {
  return switch (filter) {
    'today' => context.l10n.today,
    'next7' => context.l10n.next7Days,
    'overdue' => context.l10n.overdue,
    _ => context.l10n.tasks,
  };
}

String _filteredTaskGroupTitle(BuildContext context, String filter, int count) {
  return switch (filter) {
    'overdue' => context.l10n.needsAttention,
    'next7' => context.l10n.itemStatusDueSoon(count),
    'today' => context.l10n.dueToday,
    _ => context.l10n.taskCountLabel(count),
  };
}

List<_TaskGroupData> _visibleTaskGroups({
  required String? filter,
  required TaskBuckets buckets,
  required BuildContext context,
}) {
  final all = [
    _TaskGroupData(
      title: context.l10n.overdue,
      tasks: buckets.overdue,
      color: HkColors.red,
    ),
    _TaskGroupData(
      title: context.l10n.today,
      tasks: buckets.today,
      color: HkColors.amber,
    ),
    _TaskGroupData(
      title: context.l10n.tomorrow,
      tasks: buckets.tomorrow,
      color: HkColors.green,
    ),
    _TaskGroupData(
      title: context.l10n.next7Days,
      tasks: buckets.next7Days,
      color: HkColors.indigo,
    ),
    _TaskGroupData(
      title: context.l10n.later,
      tasks: buckets.later,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  ];
  return switch (filter) {
    'today' => [all[1]],
    'next7' => [
      _TaskGroupData(
        title: context.l10n.next7Days,
        tasks: buckets.dueSoon,
        color: HkColors.indigo,
      ),
    ],
    'overdue' => [all[0]],
    _ => all,
  };
}

class _FilteredTaskEmptyState extends StatelessWidget {
  const _FilteredTaskEmptyState({
    required this.filter,
    required this.onAddTask,
    required this.onNextSeven,
  });

  final String filter;
  final VoidCallback onAddTask;
  final VoidCallback onNextSeven;

  @override
  Widget build(BuildContext context) {
    final details = switch (filter) {
      'today' => (
        icon: Symbols.task_alt_rounded,
        title: context.l10n.noTasksDueToday,
        body: context.l10n.yourMaintenancePlanIsClearToday,
      ),
      'overdue' => (
        icon: Symbols.task_alt_rounded,
        title: context.l10n.noOverdueTasks,
        body: context.l10n.yourMaintenancePlanIsUpToDate,
      ),
      'next7' => (
        icon: Symbols.event_available_rounded,
        title: context.l10n.noTasksInTheNext7Days,
        body: context.l10n.upcomingMaintenanceWillAppearHere,
      ),
      _ => (
        icon: Symbols.task_alt_rounded,
        title: context.l10n.noTasks,
        body: context.l10n.createATaskToStartPlanningMaintenance,
      ),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: HkSpacing.space40),
        child: hk_ui.PremiumEmptyState(
          icon: details.icon,
          illustrationTone: filter == 'overdue'
              ? hk_ui.HkIllustrationTone.success
              : hk_ui.HkIllustrationTone.info,
          title: details.title,
          body: details.body,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: filter == 'overdue'
                    ? FilledButton.icon(
                        onPressed: onNextSeven,
                        icon: const Icon(Symbols.event_available_rounded),
                        label: Text(context.l10n.viewUpcomingTasks),
                      )
                    : FilledButton.icon(
                        onPressed: onAddTask,
                        icon: const Icon(Symbols.add_task_rounded),
                        label: Text(context.l10n.addTask),
                      ),
              ),
              if (filter == 'overdue') ...[
                const SizedBox(height: HkSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onAddTask,
                    icon: const Icon(Symbols.add_task_rounded),
                    label: Text(context.l10n.addTask),
                  ),
                ),
              ],
              if (filter == 'today') ...[
                const SizedBox(height: HkSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onNextSeven,
                    child: Text(context.l10n.viewNext7Days),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final today = hk_dates.dateOnly(DateTime.now());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = today;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider).value ?? [];
    final buckets = getTaskBuckets(tasks, DateTime.now());
    final grouped = groupTasksByDueDate(tasks);
    final taskCounts = {
      for (final entry in grouped.entries) entry.key: entry.value.length,
    };
    final selectedTasks = grouped[_selectedDate] ?? const <TaskItem>[];
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.calendar)),
      body: hk_ui.ProductivityBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            HkSpacing.gutter,
            8,
            HkSpacing.gutter,
            HkSpacing.bottomAction + HkSpacing.bottomNav,
          ),
          children: [
            const HkNativeAdCard(placement: 'calendar'),
            const SizedBox(height: HkSpacing.sm),
            hk_ui.PremiumEntrance(
              child: _CalendarSummaryCard(
                overdue: buckets.overdueCount,
                today: buckets.todayCount,
                upcoming: buckets.upcomingCount,
              ),
            ),
            const SizedBox(height: HkSpacing.sm),
            hk_ui.PremiumEntrance(
              delay: const Duration(milliseconds: 80),
              child: _CalendarMonthCard(
                month: _visibleMonth,
                selectedDate: _selectedDate,
                taskCounts: taskCounts,
                onDateSelected: (date) {
                  setState(() => _selectedDate = date);
                },
                onPreviousMonth: () => _changeMonth(-1),
                onNextMonth: () => _changeMonth(1),
              ),
            ),
            const SizedBox(height: HkSpacing.xs),
            Text(
              context.l10n.calendarLegend,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (selectedTasks.isEmpty)
              hk_ui.PremiumEmptyState(
                icon: Symbols.event_available_rounded,
                illustrationTone: hk_ui.HkIllustrationTone.neutral,
                title: context.l10n.noTasksOnThisDay,
                body: context.l10n.selectedDateLabel(
                  _formatLongDate(context, _selectedDate),
                ),
              )
            else
              hk_ui.PremiumCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(HkRadii.md),
                          ),
                          child: Center(
                            child: Text(
                              '${_selectedDate.day}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _formatLongDate(context, _selectedDate),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final task in selectedTasks)
                      hk_ui.SwipeDelete(
                        margin: const EdgeInsets.only(bottom: HkSpacing.xs),
                        dismissKey: ValueKey(
                          'calendar-task-delete-${task.plan.id}',
                        ),
                        action: hk_ui.SwipeAction.moveToTrash(
                          onAction: () =>
                              deleteTaskWithConfirmation(context, ref, task),
                        ),
                        child: hk_ui.TaskCard(
                          task: task,
                          dense: true,
                          margin: EdgeInsets.zero,
                          onTap: () =>
                              context.push('/maintenance/${task.plan.id}'),
                          onComplete: () =>
                              completeTaskWithFeedback(context, ref, task),
                          onSnooze: () =>
                              snoozeTaskWithFeedback(context, ref, task),
                          onSetEnabled: (enabled) => setTaskEnabledWithFeedback(
                            context,
                            ref,
                            task,
                            enabled,
                          ),
                          onArchive: () =>
                              deleteTaskWithConfirmation(context, ref, task),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
    final selectedDay = _selectedDate.day > lastDay
        ? lastDay
        : _selectedDate.day;
    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = hk_dates.dateOnly(
        DateTime(nextMonth.year, nextMonth.month, selectedDay),
      );
    });
  }
}

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.tools)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          HkSpacing.gutter,
          HkSpacing.xs,
          HkSpacing.gutter,
          HkSpacing.bottomAction + HkSpacing.bottomNav,
        ),
        children: [
          const HkNativeAdCard(placement: 'more'),
          const SizedBox(height: HkSpacing.sm),
          hk_ui.ToolTile(
            icon: Symbols.stars_rounded,
            title: context.l10n.earnFreePoints,
            subtitle: context.l10n.earnFreePointsSubtitle,
            onTap: () => showEarnPointsFlow(context, ref, entryPoint: 'more'),
          ),
          hk_ui.ToolTile(
            icon: Symbols.search_rounded,
            title: context.l10n.search,
            subtitle: context.l10n.findRoomsItemsTagsNotesPhotosAndTasks,
            onTap: () => context.push('/search'),
          ),
          hk_ui.SectionHeader(title: context.l10n.insights),
          hk_ui.ToolTile(
            icon: Symbols.query_stats_rounded,
            title: context.l10n.statistics,
            subtitle: context.l10n.completionTrendsAndTaskDistribution,
            onTap: () => context.push('/statistics'),
          ),
          hk_ui.SectionHeader(title: context.l10n.data),
          hk_ui.ToolTile(
            icon: Symbols.cloud_sync_rounded,
            title: context.l10n.accountAndCloudSync,
            subtitle: context.l10n.optionalGoogleSignInAndPrivateDeviceSync,
            onTap: () => context.push('/account'),
          ),
          hk_ui.ToolTile(
            icon: Symbols.cloud_upload_rounded,
            title: context.l10n.backupAndRestore,
            subtitle: context.l10n.createShareOrRestoreLocalZipBackups,
            onTap: () => context.push('/backup'),
          ),
          hk_ui.ToolTile(
            icon: Symbols.restore_from_trash_rounded,
            title: context.l10n.trash,
            subtitle: context.l10n.restoreRecentlyRemovedRoomsItemsAndTasks,
            onTap: () => context.push('/trash'),
          ),
          hk_ui.SectionHeader(title: context.l10n.system),
          hk_ui.ToolTile(
            icon: Symbols.settings_rounded,
            title: context.l10n.settings,
            subtitle: context.l10n.themeRemindersPrivacyAndReleaseReadiness,
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = const [];
  bool _loading = false;
  bool _indexReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleSearch);
    unawaited(_rebuildIndex());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_scheduleSearch);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _rebuildIndex() async {
    try {
      await ref.read(searchRepositoryProvider).rebuildIndex();
      _indexReady = true;
    } catch (_) {
      // Search still renders its explicit error when a user queries.
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(_controller.text));
    });
  }

  Future<void> _runSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const [];
          _error = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(searchRepositoryProvider);
      if (!_indexReady) {
        await repository.rebuildIndex();
        _indexReady = true;
      }
      final results = await repository.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _failureMessage(context, error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.search)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          HkSpacing.gutter,
          HkSpacing.xs,
          HkSpacing.gutter,
          HkSpacing.bottomAction,
        ),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Symbols.search_rounded),
              suffixIcon: hasQuery
                  ? IconButton(
                      tooltip: context.l10n.clearSearch,
                      onPressed: () => _controller.clear(),
                      icon: const Icon(Symbols.close_rounded),
                    )
                  : null,
              labelText: context.l10n.searchRoomsItemsTasksNotes,
            ),
            onSubmitted: _runSearch,
          ),
          if (_loading) ...[
            const SizedBox(height: HkSpacing.sm),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: HkSpacing.sm),
            ErrorPanel(message: _error!),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: HkSpacing.sm),
            const HkNativeAdCard(placement: 'search'),
          ],
          const SizedBox(height: HkSpacing.sm),
          if (!hasQuery)
            hk_ui.PremiumEmptyState(
              icon: Symbols.manage_search_rounded,
              title: context.l10n.searchYourHome,
              body: context.l10n.findAllHomeContent,
            )
          else if (!_loading && _results.isEmpty && _error == null)
            hk_ui.PremiumEmptyState(
              icon: Symbols.search_off_rounded,
              illustrationTone: hk_ui.HkIllustrationTone.neutral,
              title: context.l10n.noResults,
              body: context.l10n.tryAnotherSearchTerm,
            )
          else
            for (final result in _results)
              hk_ui.PremiumCard(
                margin: const EdgeInsets.only(bottom: HkSpacing.xs),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_searchResultIcon(result.entityType)),
                  title: Text(result.title),
                  subtitle: Text(
                    _searchResultSubtitle(context, result),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => _openSearchResult(context, result),
                ),
              ),
        ],
      ),
    );
  }
}

IconData _searchResultIcon(String type) {
  return switch (type) {
    'area' => Symbols.home_work_rounded,
    'room' => Symbols.meeting_room_rounded,
    'asset' => Symbols.inventory_2_rounded,
    'plan' => Symbols.task_alt_rounded,
    'tag' => Symbols.sell_rounded,
    'category' => Symbols.category_rounded,
    _ => Symbols.search_rounded,
  };
}

String _searchResultSubtitle(BuildContext context, SearchResult result) {
  final type = switch (result.entityType) {
    'area' => context.l10n.area,
    'room' => context.l10n.room,
    'asset' => context.l10n.item,
    'plan' => context.l10n.task,
    'tag' => context.l10n.tag,
    'category' => context.l10n.category,
    _ => context.l10n.result,
  };
  final snippet = result.snippet.trim();
  return snippet.isEmpty
      ? type
      : context.l10n.searchResultWithSnippet(type, snippet);
}

void _openSearchResult(BuildContext context, SearchResult result) {
  switch (result.entityType) {
    case 'room':
      context.push('/assets/room/${result.entityId}');
    case 'asset':
      context.push('/assets/thing/${result.entityId}');
    case 'plan':
      context.push('/maintenance/${result.entityId}');
    default:
      context.push('/assets');
  }
}

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(archivedAreasProvider);
    final rooms = ref.watch(archivedRoomsProvider);
    final assets = ref.watch(archivedAssetsProvider);
    final tasks = ref.watch(archivedTasksProvider);
    final areaItems = areas.value ?? const <Area>[];
    final roomItems = rooms.value ?? const <Room>[];
    final assetItems = assets.value ?? const <Asset>[];
    final taskItems = tasks.value ?? const <TaskItem>[];
    final total =
        areaItems.length +
        roomItems.length +
        assetItems.length +
        taskItems.length;
    final loading =
        areas.isLoading ||
        rooms.isLoading ||
        assets.isLoading ||
        tasks.isLoading;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.trash)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          hk_ui.PremiumCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Symbols.restore_from_trash_rounded),
              title: Text(
                total == 0
                    ? context.l10n.trashIsEmpty
                    : context.l10n.trashItemCount(total),
              ),
              subtitle: Text(context.l10n.restoreOrDeleteForever),
            ),
          ),
          if (loading) ...[
            const SizedBox(height: HkSpacing.sm),
            const LinearProgressIndicator(),
          ],
          if (!loading && total == 0)
            Padding(
              padding: EdgeInsets.only(top: HkSpacing.md),
              child: hk_ui.PremiumEmptyState(
                icon: Symbols.delete_sweep_rounded,
                illustrationTone: hk_ui.HkIllustrationTone.success,
                title: context.l10n.nothingToRestore,
                body: context.l10n.trashedContentAppearsHere,
              ),
            ),
          _TrashSection(
            title: context.l10n.areas,
            count: areaItems.length,
            children: [
              for (final area in areaItems)
                _TrashRow(
                  icon: Symbols.home_work_rounded,
                  title: area.name,
                  subtitle: context.l10n.trashAreaType(
                    _areaKindLabel(context, area.kind),
                  ),
                  onRestore: () => _restoreArea(context, ref, area),
                  onDeleteForever: () => _deleteAreaForever(context, ref, area),
                ),
            ],
          ),
          _TrashSection(
            title: context.l10n.rooms,
            count: roomItems.length,
            children: [
              for (final room in roomItems)
                _TrashRow(
                  icon: Symbols.meeting_room_rounded,
                  title: room.name,
                  subtitle: context.l10n.trashRoomType(
                    _roomTypeLabel(context, room.roomType),
                  ),
                  onRestore: () => _restoreRoom(context, ref, room),
                  onDeleteForever: () => _deleteRoomForever(context, ref, room),
                ),
            ],
          ),
          _TrashSection(
            title: context.l10n.items,
            count: assetItems.length,
            children: [
              for (final asset in assetItems)
                _TrashRow(
                  icon: _iconForAssetType(asset.assetType),
                  title: asset.name,
                  subtitle: context.l10n.trashItemType(
                    _assetTypeLabel(context, asset.assetType),
                  ),
                  onRestore: () => _restoreAsset(context, ref, asset),
                  onDeleteForever: () =>
                      _deleteAssetForever(context, ref, asset),
                ),
            ],
          ),
          _TrashSection(
            title: context.l10n.tasks,
            count: taskItems.length,
            children: [
              for (final task in taskItems)
                _TrashRow(
                  icon: Symbols.task_alt_rounded,
                  title: task.plan.title,
                  subtitle: '${task.asset.name} - ${task.room.name}',
                  onRestore: () => _restoreTask(context, ref, task),
                  onDeleteForever: () => _deleteTaskForever(context, ref, task),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restoreArea(
    BuildContext context,
    WidgetRef ref,
    Area area,
  ) async {
    await ref.read(assetRepositoryProvider).restoreArea(area.id);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(area.name),
    );
  }

  Future<void> _restoreRoom(
    BuildContext context,
    WidgetRef ref,
    Room room,
  ) async {
    await ref.read(assetRepositoryProvider).restoreRoom(room.id);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(room.name),
    );
  }

  Future<void> _restoreAsset(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
  ) async {
    await ref.read(assetRepositoryProvider).restoreAsset(asset.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(asset.name),
    );
  }

  Future<void> _restoreTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    await ref.read(maintenanceRepositoryProvider).restorePlan(task.plan.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(task.plan.title),
    );
  }

  Future<void> _deleteAreaForever(
    BuildContext context,
    WidgetRef ref,
    Area area,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteAreaForever,
      message: context.l10n.permanentlyDeleteAreaMessage(area.name),
    );
    if (!confirmed) return;
    await ref.read(assetRepositoryProvider).deleteArea(area.id);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(area.name),
    );
  }

  Future<void> _deleteRoomForever(
    BuildContext context,
    WidgetRef ref,
    Room room,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteRoomForever,
      message: context.l10n.permanentlyDeleteRoomMessage(room.name),
    );
    if (!confirmed) return;
    await ref.read(assetRepositoryProvider).deleteRoom(room.id);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(room.name),
    );
  }

  Future<void> _deleteAssetForever(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteItemForever,
      message: context.l10n.permanentlyDeleteItemMessage(asset.name),
    );
    if (!confirmed) return;
    await ref.read(assetRepositoryProvider).deleteAsset(asset.id);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(asset.name),
    );
  }

  Future<void> _deleteTaskForever(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteTaskForever,
      message: context.l10n.permanentlyDeleteTaskMessage(task.plan.title),
    );
    if (!confirmed) return;
    await ref.read(maintenanceRepositoryProvider).deletePlan(task.plan.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(task.plan.title),
    );
  }

  Future<void> _afterTrashMutation(
    BuildContext context,
    WidgetRef ref,
    String message,
  ) async {
    await ref.read(searchRepositoryProvider).rebuildIndex();
    if (!context.mounted) return;
    hk_ui.showToast(context, content: Text(message));
  }
}

class _TrashSection extends StatelessWidget {
  const _TrashSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hk_ui.SectionHeader(
          title: title,
          subtitle: context.l10n.trashSectionItemCount(count),
        ),
        ...children,
      ],
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDeleteForever;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      margin: const EdgeInsets.only(bottom: HkSpacing.xs),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: context.l10n.restore,
              onPressed: () => unawaited(onRestore()),
              icon: const Icon(Symbols.restore_rounded),
            ),
            IconButton(
              tooltip: context.l10n.deleteForever,
              onPressed: () => unawaited(onDeleteForever()),
              icon: Icon(
                Symbols.delete_forever_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _healthStateLabel(BuildContext context, features.HealthState state) {
  return switch (state) {
    features.HealthState.excellent => context.l10n.excellent,
    features.HealthState.good => context.l10n.good,
    features.HealthState.attention => context.l10n.needsAttention,
    features.HealthState.critical => context.l10n.critical,
    features.HealthState.insufficientData => context.l10n.needsSetup,
  };
}

enum _NotificationFilter { all, unread, tasks, system }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _NotificationFilter _filter = _NotificationFilter.all;

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationsProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.inbox),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () =>
                  ref.read(notificationInboxRepositoryProvider).markAllRead(),
              child: Text(context.l10n.markAllRead),
            ),
        ],
      ),
      body: notifications.when(
        data: (items) {
          final unread = items.where((item) => item.unread).length;
          final visible = _groupNotifications(_filterNotifications(items));
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                hk_ui.PremiumEmptyState(
                  icon: Symbols.notifications_rounded,
                  title: context.l10n.noNotifications,
                  body: context.l10n.inboxMessagesAppearHere,
                ),
              ],
            );
          }
          final taskCount = items.where((item) => item.kind == 'task').length;
          final hasCriticalGuidance = items.any((item) {
            final text = '${item.title} ${item.body}'.toLowerCase();
            return text.contains('critical') || text.contains('overdue');
          });
          final children = <Widget>[
            if (!hasCriticalGuidance) ...[
              const HkNativeAdCard(placement: 'notifications'),
              const SizedBox(height: HkSpacing.sm),
            ],
            _NotificationSummaryCard(
              total: items.length,
              unread: unread,
              tasks: taskCount,
            ),
            const SizedBox(height: HkSpacing.xs),
            _NotificationFilterChips(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
              unreadCount: unread,
            ),
            const SizedBox(height: HkSpacing.sm),
          ];
          if (visible.isEmpty) {
            children.add(
              hk_ui.PremiumEmptyState(
                icon: Symbols.filter_alt_off_rounded,
                illustrationTone: hk_ui.HkIllustrationTone.neutral,
                title: _filteredNotificationEmptyTitle(context, _filter),
                body: context.l10n.changeFilterForOtherUpdates,
                action: OutlinedButton(
                  onPressed: () =>
                      setState(() => _filter = _NotificationFilter.all),
                  child: Text(context.l10n.showAll),
                ),
              ),
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: children,
            );
          }
          DateTime? previousDay;
          for (final item in visible) {
            final completionRecords = item.planId == null
                ? const <MaintenanceRecord>[]
                : ref.watch(taskRecordsProvider(item.planId!)).value ??
                      const <MaintenanceRecord>[];
            final completedAt = _completedTaskNotificationAt(
              item,
              completionRecords,
            );
            final itemDay = hk_dates.dateOnly(item.createdAt);
            if (previousDay == null ||
                !hk_dates.isSameDate(previousDay, itemDay)) {
              children.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    _notificationDateLabel(context, item.createdAt),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              );
              previousDay = itemDay;
            }
            children.add(
              NotificationCard(
                notification: item,
                completedAt: completedAt,
                onTap: () => _openNotification(context, ref, item),
                onAction: (action) => _handleAction(context, ref, item, action),
                onComplete: item.planId == null || completedAt != null
                    ? null
                    : () => _completeFromNotification(context, ref, item),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: children,
          );
        },
        error: (error, _) =>
            ErrorPanel(message: _failureMessage(context, error)),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    InboxNotification item,
    NotificationAction action,
  ) async {
    switch (action) {
      case NotificationAction.open:
        await _openNotification(context, ref, item);
      case NotificationAction.markRead:
        await ref.read(notificationInboxRepositoryProvider).markRead(item.id);
    }
  }

  Future<void> _completeFromNotification(
    BuildContext context,
    WidgetRef ref,
    InboxNotification item,
  ) async {
    final planId = item.planId;
    if (planId == null) {
      return;
    }
    final task = await ref.read(maintenanceRepositoryProvider).getTask(planId);
    if (!context.mounted) {
      return;
    }
    if (task == null) {
      hk_ui.showToast(
        context,
        content: Text(context.l10n.taskIsNoLongerAvailable),
        severity: hk_ui.HkToastSeverity.error,
      );
      return;
    }
    await completeTaskWithFeedback(context, ref, task, collectNotes: true);
    await ref.read(notificationInboxRepositoryProvider).markRead(item.id);
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    InboxNotification item,
  ) async {
    await ref.read(notificationInboxRepositoryProvider).markRead(item.id);
    if (!context.mounted) {
      return;
    }
    final route = item.route;
    final destination = route == null
        ? null
        : _validatedNotificationRoute(route);
    if (destination != null) {
      context.push(destination);
    }
  }

  List<InboxNotification> _filterNotifications(List<InboxNotification> items) {
    return switch (_filter) {
      _NotificationFilter.all => items,
      _NotificationFilter.unread => items.where((item) => item.unread).toList(),
      _NotificationFilter.tasks =>
        items
            .where((item) => item.kind == 'task' || item.planId != null)
            .toList(),
      _NotificationFilter.system =>
        items
            .where((item) => item.kind != 'task' && item.kind != 'digest')
            .toList(),
    };
  }
}

DateTime? _completedTaskNotificationAt(
  InboxNotification notification,
  List<MaintenanceRecord> records,
) {
  if (notification.planId == null || records.isEmpty) {
    return null;
  }
  final completedAfterNotification =
      records
          .where(
            (record) => !record.completedAt.isBefore(notification.createdAt),
          )
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  if (completedAfterNotification.isEmpty) {
    return null;
  }
  return completedAfterNotification.first.completedAt;
}

enum NotificationAction { open, markRead }

class _NotificationSummaryCard extends StatelessWidget {
  const _NotificationSummaryCard({
    required this.total,
    required this.unread,
    required this.tasks,
  });

  final int total;
  final int unread;
  final int tasks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = String.fromCharCode(0x2022);
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      borderRadius: 26,
      backgroundColor: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.035),
        scheme.surfaceContainerLowest,
      ),
      borderColor: scheme.outlineVariant.withValues(alpha: 0.62),
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          return Row(
            children: [
              _NotificationSummaryIcon(
                size: compact ? 52 : 58,
                hasUnread: unread > 0,
              ),
              SizedBox(width: compact ? HkSpacing.xs : HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        context.l10n.inboxUpdateCount(total),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.onSurface,
                          fontSize: compact ? 19 : 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: HkSpacing.space6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${context.l10n.unreadCount(unread)} $dot ${context.l10n.taskReminderCount(tasks)}',
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: compact ? 12 : 14,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.xs),
              _InboxEnvelopeIllustration(size: compact ? 62 : 88),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationSummaryIcon extends StatelessWidget {
  const _NotificationSummaryIcon({required this.size, required this.hasUnread});

  final double size;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.notifications_active_rounded,
                color: scheme.primary,
                size: size * 0.44,
              ),
            ),
          ),
          if (hasUnread)
            PositionedDirectional(
              end: size * 0.06,
              top: size * 0.08,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
                child: SizedBox.square(dimension: size * 0.20),
              ),
            ),
        ],
      ),
    );
  }
}

class _InboxEnvelopeIllustration extends StatelessWidget {
  const _InboxEnvelopeIllustration({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size * 0.76,
      child: CustomPaint(
        painter: _InboxEnvelopePainter(
          primary: scheme.primary,
          surface: scheme.surfaceContainerLowest,
          muted: scheme.primary.withValues(alpha: 0.18),
          line: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _InboxEnvelopePainter extends CustomPainter {
  const _InboxEnvelopePainter({
    required this.primary,
    required this.surface,
    required this.muted,
    required this.line,
  });

  final Color primary;
  final Color surface;
  final Color muted;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final envelopeRect = Rect.fromLTWH(
      size.width * 0.23,
      size.height * 0.38,
      size.width * 0.65,
      size.height * 0.48,
    );
    final paperRect = Rect.fromLTWH(
      size.width * 0.34,
      size.height * 0.14,
      size.width * 0.42,
      size.height * 0.48,
    );

    paint
      ..color = muted
      ..strokeWidth = size.width * 0.035
      ..style = PaintingStyle.stroke;
    final stem = Path()
      ..moveTo(size.width * 0.18, size.height * 0.70)
      ..quadraticBezierTo(
        size.width * 0.10,
        size.height * 0.47,
        size.width * 0.22,
        size.height * 0.27,
      );
    canvas.drawPath(stem, paint);
    paint.style = PaintingStyle.fill;
    for (final leaf in [
      Offset(size.width * 0.13, size.height * 0.48),
      Offset(size.width * 0.22, size.height * 0.38),
      Offset(size.width * 0.16, size.height * 0.28),
    ]) {
      canvas.save();
      canvas.translate(leaf.dx, leaf.dy);
      canvas.rotate(-0.72);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * 0.14,
          height: size.height * 0.08,
        ),
        paint,
      );
      canvas.restore();
    }

    paint.color = surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(paperRect, Radius.circular(size.width * 0.04)),
      paint,
    );
    paint.color = line.withValues(alpha: 0.56);
    for (var index = 0; index < 3; index += 1) {
      final y = paperRect.top + paperRect.height * (0.30 + (index * 0.18));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            paperRect.left + paperRect.width * 0.16,
            y,
            paperRect.width * 0.68,
            size.height * 0.026,
          ),
          Radius.circular(size.height * 0.02),
        ),
        paint,
      );
    }

    paint.color = primary.withValues(alpha: 0.90);
    canvas.drawRRect(
      RRect.fromRectAndRadius(envelopeRect, Radius.circular(size.width * 0.07)),
      paint,
    );
    final flap = Path()
      ..moveTo(envelopeRect.left, envelopeRect.top)
      ..lineTo(envelopeRect.center.dx, envelopeRect.top - size.height * 0.22)
      ..lineTo(envelopeRect.right, envelopeRect.top)
      ..lineTo(envelopeRect.right, envelopeRect.bottom)
      ..lineTo(envelopeRect.center.dx, envelopeRect.center.dy)
      ..lineTo(envelopeRect.left, envelopeRect.bottom)
      ..close();
    paint.color = primary.withValues(alpha: 0.62);
    canvas.drawPath(flap, paint);

    paint.color = muted;
    for (final star in [
      Offset(size.width * 0.22, size.height * 0.12),
      Offset(size.width * 0.91, size.height * 0.11),
      Offset(size.width * 0.78, size.height * 0.02),
    ]) {
      _drawSpark(canvas, paint, star, size.width * 0.04);
    }
  }

  void _drawSpark(Canvas canvas, Paint paint, Offset center, double radius) {
    paint
      ..strokeWidth = radius * 0.36
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      paint,
    );
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      paint,
    );
    paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(covariant _InboxEnvelopePainter oldDelegate) {
    return primary != oldDelegate.primary ||
        surface != oldDelegate.surface ||
        muted != oldDelegate.muted ||
        line != oldDelegate.line;
  }
}

class _NotificationFilterChips extends StatelessWidget {
  const _NotificationFilterChips({
    required this.selected,
    required this.onSelected,
    required this.unreadCount,
  });

  final _NotificationFilter selected;
  final ValueChanged<_NotificationFilter> onSelected;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final filters = [
      (_NotificationFilter.all, context.l10n.all, null),
      (_NotificationFilter.unread, context.l10n.unread, unreadCount),
      (_NotificationFilter.tasks, context.l10n.tasks, null),
      (_NotificationFilter.system, context.l10n.system, null),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final gap = compact ? HkSpacing.space6 : HkSpacing.xs;
        final children = <Widget>[];
        for (var index = 0; index < filters.length; index += 1) {
          final filter = filters[index];
          children.add(
            Expanded(
              child: _NotificationFilterButton(
                label: filter.$2,
                badgeCount: filter.$3,
                selected: selected == filter.$1,
                compact: compact,
                onTap: () => onSelected(filter.$1),
              ),
            ),
          );
          if (index != filters.length - 1) {
            children.add(SizedBox(width: gap));
          }
        }
        return Row(mainAxisSize: MainAxisSize.max, children: children);
      },
    );
  }
}

class _NotificationFilterButton extends StatelessWidget {
  const _NotificationFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
    this.badgeCount,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showBadge = badgeCount != null && badgeCount! > 0;
    final foreground = selected ? scheme.onPrimary : HkColors.appPrimaryDark;
    final semanticLabel = showBadge
        ? context.l10n.filterUnreadCount(label, badgeCount!)
        : label;
    const chipHeight = 38.0;
    const tapHeight = 48.0;
    final badgeSpace = compact ? 5.0 : 6.0;
    final fontSize = compact ? 12.0 : 14.0;
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        child: SizedBox(
          height: tapHeight + badgeSpace,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: (tapHeight - chipHeight) / 2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: chipHeight,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 3 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : Color.alphaBlend(
                                scheme.primary.withValues(alpha: 0.025),
                                scheme.surfaceContainerLowest,
                              ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? scheme.primary.withValues(alpha: 0.48)
                              : scheme.outlineVariant.withValues(alpha: 0.74),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (selected ? scheme.primary : Colors.black)
                                .withValues(alpha: selected ? 0.18 : 0.045),
                            blurRadius: selected ? 18 : 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: foreground,
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showBadge)
                PositionedDirectional(
                  top: 0,
                  end: compact ? 2 : 8,
                  child: _NotificationFilterBadge(
                    count: badgeCount!,
                    selected: selected,
                    compact: compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationFilterBadge extends StatelessWidget {
  const _NotificationFilterBadge({
    required this.count,
    required this.selected,
    required this.compact,
  });

  final int count;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';
    final size = compact ? 20.0 : 22.0;
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.surfaceContainerLowest : scheme.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.surfaceContainerLowest, width: 2),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: selected ? scheme.primary : scheme.onPrimary,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class NotificationCard extends StatelessWidget {
  const NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onAction,
    this.completedAt,
    this.onComplete,
    super.key,
  });

  final InboxNotification notification;
  final VoidCallback onTap;
  final ValueChanged<NotificationAction> onAction;
  final DateTime? completedAt;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizedNotification = localizeInboxNotification(
      context.l10n,
      notification,
    );
    final completed = completedAt != null;
    final accent = completed
        ? HkColors.green
        : _notificationAccent(context, notification);
    return hk_ui.PremiumCard(
      margin: const EdgeInsets.only(bottom: HkSpacing.sm),
      backgroundColor: completed
          ? Color.alphaBlend(
              HkColors.green.withValues(alpha: 0.07),
              scheme.surfaceContainerLowest,
            )
          : null,
      borderColor: completed
          ? HkColors.green.withValues(alpha: 0.34)
          : notification.unread
          ? accent.withValues(alpha: 0.34)
          : scheme.outlineVariant,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadii.xl),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 38,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      completed
                          ? Symbols.check_circle_rounded
                          : _notificationIcon(notification.kind),
                      size: 18,
                      color: accent,
                    ),
                  ),
                  if (notification.unread && !completed)
                    PositionedDirectional(
                      end: 1,
                      top: 0,
                      child: Semantics(
                        label: context.l10n.unread,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: HkColors.appDanger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: HkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          localizedNotification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      Text(
                        _formatShortTime(context, notification.createdAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: HkSpacing.space4),
                  Text(
                    localizedNotification.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (completed) ...[
                    const SizedBox(height: HkSpacing.xs),
                    _CompletedNotificationBadge(completedAt: completedAt!),
                  ] else if (onComplete != null) ...[
                    const SizedBox(height: HkSpacing.xs),
                    Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 176,
                          maxWidth: 220,
                        ),
                        child: SizedBox(
                          key: const ValueKey('inbox-complete-action'),
                          height: 48,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onComplete,
                              borderRadius: BorderRadius.circular(14),
                              child: Center(
                                child: Container(
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Symbols.check_rounded,
                                        size: 17,
                                        color: scheme.onSecondaryContainer,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        context.l10n.completeAction,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color:
                                                  scheme.onSecondaryContainer,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<NotificationAction>(
              useRootNavigator: true,
              tooltip: context.l10n.notificationActions,
              onSelected: onAction,
              itemBuilder: (context) => [
                if (notification.route?.isNotEmpty ?? false)
                  PopupMenuItem(
                    value: NotificationAction.open,
                    child: Text(context.l10n.open),
                  ),
                if (notification.unread)
                  PopupMenuItem(
                    value: NotificationAction.markRead,
                    child: Text(context.l10n.markRead),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedNotificationBadge extends StatelessWidget {
  const _CompletedNotificationBadge({required this.completedAt});

  final DateTime completedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HkSpacing.xs,
        vertical: HkSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: HkColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: HkColors.green.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Symbols.check_circle_rounded,
            color: HkColors.green,
            size: 16,
          ),
          const SizedBox(width: HkSpacing.space4),
          Text(
            context.l10n.completedAtTime(
              _completedNotificationTimeLabel(context, completedAt),
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: HkColors.green,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _completedNotificationTimeLabel(BuildContext context, DateTime value) {
  return MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(value));
}

List<InboxNotification> _groupNotifications(List<InboxNotification> items) {
  final seen = <String>{};
  final grouped = <InboxNotification>[];
  for (final item in items) {
    final day = hk_dates.dateOnly(item.createdAt).toIso8601String();
    final key = switch (item.kind) {
      'task' => 'task:${item.planId ?? item.route ?? item.title}:$day',
      'digest' => 'digest:$day',
      _ => '${item.kind}:${item.title}:${item.route ?? ''}:$day',
    };
    if (seen.add(key)) {
      grouped.add(item);
    }
  }
  return grouped;
}

String _filteredNotificationEmptyTitle(
  BuildContext context,
  _NotificationFilter filter,
) {
  return switch (filter) {
    _NotificationFilter.unread => context.l10n.noUnreadNotifications,
    _NotificationFilter.tasks => context.l10n.noTaskNotifications,
    _NotificationFilter.system => context.l10n.noSystemNotifications,
    _NotificationFilter.all => context.l10n.noNotifications,
  };
}

Color _notificationAccent(BuildContext context, InboxNotification item) {
  final body = '${item.title} ${item.body}'.toLowerCase();
  if (body.contains('critical') || body.contains('overdue')) {
    return HkColors.appDanger;
  }
  return switch (item.kind) {
    'task' => HkColors.appWarning,
    'digest' => Theme.of(context).colorScheme.onSurfaceVariant,
    'weather' => HkColors.appWarning,
    _ => Theme.of(context).colorScheme.primary,
  };
}

IconData _notificationIcon(String kind) {
  return switch (kind) {
    'weather' => Symbols.rainy_rounded,
    'task' => Symbols.task_alt_rounded,
    'digest' => Symbols.summarize_rounded,
    _ => Symbols.notifications_rounded,
  };
}

String _notificationDateLabel(BuildContext context, DateTime value) {
  final today = DateTime.now();
  if (hk_dates.isSameDate(value, today)) {
    return context.l10n.today;
  }
  if (hk_dates.isSameDate(value, today.subtract(const Duration(days: 1)))) {
    return context.l10n.yesterday;
  }
  final locale = Localizations.localeOf(context).toLanguageTag();
  if (value.isAfter(today.subtract(const Duration(days: 7)))) {
    return DateFormat.EEEE(locale).add_MMMd().format(value);
  }
  return DateFormat.yMMMd(locale).format(value);
}

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statisticsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.statistics)),
      body: RepaintBoundary(
        key: const ValueKey('statistics-stability-boundary'),
        child: stats.when(
          data: (summary) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 640;
                  final charts = [
                    Expanded(
                      child: _CompactChartPanel(
                        title: context.l10n.monthlyCompletions,
                        child: MonthlyCompletionsChart(
                          data: summary.completedByMonth,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: wide ? HkSpacing.sm : 0,
                      height: wide ? 0 : HkSpacing.sm,
                    ),
                    Expanded(
                      child: _CompactChartPanel(
                        title: context.l10n.taskDistribution,
                        child: TaskDistributionChart(
                          data: summary.taskDistribution,
                        ),
                      ),
                    ),
                  ];
                  return Column(
                    children: [
                      const HkNativeAdCard(placement: 'statistics'),
                      const SizedBox(height: HkSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: _StatisticMetric(
                              label: context.l10n.historyCompletion,
                              value:
                                  '${(summary.completionRate * 100).round()}%',
                              icon: Symbols.done_all_rounded,
                              color: HkColors.green,
                            ),
                          ),
                          const SizedBox(width: HkSpacing.sm),
                          Expanded(
                            child: _StatisticMetric(
                              label: context.l10n.activeOverdue,
                              value: '${(summary.overdueRate * 100).round()}%',
                              icon: Symbols.warning_rounded,
                              color: HkColors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: HkSpacing.sm),
                      Expanded(
                        child: wide
                            ? Row(children: charts)
                            : Column(children: charts),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          error: (error, _) =>
              ErrorPanel(message: _failureMessage(context, error)),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _StatisticMetric extends StatelessWidget {
  const _StatisticMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactChartPanel extends StatelessWidget {
  const _CompactChartPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: HkSpacing.space4),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AccountScreenHost extends ConsumerWidget {
  const AccountScreenHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value ?? const AppProfile();
    return AccountScreen(
      profile: profile,
      onSaveNickname: (nickname) => _saveAccountNickname(ref, nickname),
    );
  }
}

Future<void> _saveAccountNickname(WidgetRef ref, String? nickname) async {
  await ref.read(settingsRepositoryProvider).setProfile(nickname: nickname);
  ref.invalidate(profileProvider);
  unawaited(_syncProfileIfEnabled(ref));
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(
          ref
              .read(permissionEducationControllerProvider.notifier)
              .refreshCapabilities(),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(permissionEducationControllerProvider.notifier)
            .handleAppResume(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(homeLocationProvider).value;
    final weather = ref.watch(weatherProvider).value;
    final startupTheme = ref.watch(startupThemeSettingsProvider);
    final themePreference =
        ref.watch(themePreferenceProvider).value ?? startupTheme.preference;
    final localePreference =
        ref.watch(appLocalePreferenceProvider).value ??
        AppLocalePreference(
          language: _supportedDeviceLanguage(
            WidgetsBinding.instance.platformDispatcher.locale,
          ),
          isExplicit: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
    final notificationPreferences =
        ref.watch(notificationPreferencesProvider).value ??
        const NotificationPreferences();
    final capabilitySetup = ref
        .watch(permissionEducationControllerProvider)
        .setupSnapshot;
    final consent = ref.watch(consentSnapshotProvider).value;
    final reminderHours = {
      ...[7, 8, 9, 10, 12, 18],
      notificationPreferences.reminderHour,
    }.toList()..sort();
    final digestHours = {
      ...[8, 12, 17, 18, 20],
      notificationPreferences.digestHour,
    }.toList()..sort();
    final snoozeOptions = {
      30,
      60,
      180,
      24 * 60,
      notificationPreferences.defaultSnoozeMinutes,
    }.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          hk_ui.PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Symbols.contrast_rounded),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      child: Text(
                        context.l10n.appearance,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HkSpacing.xs),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactSegments = constraints.maxWidth < 420;
                    return SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemePreference>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: ThemePreference.light,
                            label: Text(context.l10n.light),
                            icon: Icon(Symbols.light_mode_rounded),
                          ),
                          ButtonSegment(
                            value: ThemePreference.dark,
                            label: Text(context.l10n.dark),
                            icon: Icon(Symbols.dark_mode_rounded),
                          ),
                          ButtonSegment(
                            value: ThemePreference.system,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                compactSegments
                                    ? context.l10n.auto
                                    : context.l10n.automatic,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                            icon: const Icon(Symbols.schedule_rounded),
                          ),
                        ],
                        selected: {themePreference},
                        onSelectionChanged: (selection) {
                          final preference = selection.single;
                          _setThemePreference(context, ref, preference);
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: HkSpacing.space6),
                Text(
                  themePreference == ThemePreference.system
                      ? context
                            .l10n
                            .automaticUsesYourLocalTimeLightFrom6AmTo6PmDarkOvernight
                      : context
                            .l10n
                            .manualSelectionStaysActiveUntilYouChooseAnotherMode,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HkSpacing.xs),
          hk_ui.PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Symbols.language_rounded),
                    const SizedBox(width: HkSpacing.xs),
                    Text(
                      context.l10n.language,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: HkSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AppLanguage>(
                    key: const ValueKey('settings-language-selector'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AppLanguage.en,
                        label: Text(
                          'English',
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                      ButtonSegment(
                        value: AppLanguage.ar,
                        label: Text(
                          'العربية',
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                    selected: {localePreference.language},
                    onSelectionChanged: (selection) =>
                        _setAppLanguage(context, ref, selection.single),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HkSpacing.xs),
          if (consent?.privacyOptionsRequired ?? false) ...[
            hk_ui.PremiumCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Symbols.privacy_tip_rounded),
                title: Text(context.l10n.privacyChoices),
                subtitle: Text(context.l10n.privacyChoicesSubtitle),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () =>
                    ref.read(consentServiceProvider).showPrivacyOptions(),
              ),
            ),
            const SizedBox(height: HkSpacing.xs),
          ],
          hk_ui.PremiumCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                weather == null
                    ? Symbols.location_on_rounded
                    : _weatherIcon(weather.weatherCode),
              ),
              title: Text(context.l10n.weatherLocation),
              subtitle: Text(
                weather == null
                    ? context.l10n.setACityZipOrCurrentDeviceLocation
                    : '${location?.label ?? context.l10n.home}\n${_localizedWeatherSummary(context, weather.weatherCode)} \u00B7 ${_formatInteger(context, weather.temperature.round())}\u00B0C',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: context.l10n.searchLocation,
                    onPressed: () => _searchLocation(context, ref),
                    icon: const Icon(Symbols.search_rounded),
                  ),
                  IconButton(
                    tooltip: context.l10n.useDeviceLocation,
                    onPressed: () => _useDeviceLocation(context, ref),
                    icon: const Icon(Symbols.my_location_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: HkSpacing.xs),
          hk_ui.PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.notifications,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: HkSpacing.xs),
                Text(
                  context.l10n.permissions,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: HkSpacing.space4),
                if (capabilitySetup == null)
                  const LinearProgressIndicator()
                else
                  Column(
                    children: [
                      _NotificationStatusRow(
                        icon: Symbols.notifications_rounded,
                        label: context.l10n.deviceReminders,
                        value: _effectiveCapabilityLabel(
                          context,
                          capabilitySetup.notifications.deviceReminderState,
                        ),
                        good:
                            capabilitySetup.notifications.deviceReminderState ==
                            EffectiveCapabilityState.active,
                      ),
                      _NotificationStatusRow(
                        icon: Symbols.alarm_on_rounded,
                        label: context.l10n.alarmsAndReminders,
                        value: _effectiveCapabilityLabel(
                          context,
                          capabilitySetup.notifications.exactTimingState,
                          approximateWhenDegraded: true,
                        ),
                        good:
                            capabilitySetup.notifications.exactTimingState ==
                            EffectiveCapabilityState.active,
                      ),
                      _NotificationStatusRow(
                        icon: Symbols.inbox_rounded,
                        label: context.l10n.inAppInbox,
                        value: _effectiveCapabilityLabel(
                          context,
                          capabilitySetup.notifications.inboxState,
                        ),
                        good:
                            capabilitySetup.notifications.inboxState ==
                            EffectiveCapabilityState.active,
                      ),
                      _NotificationStatusRow(
                        icon: Symbols.rainy_rounded,
                        label: context.l10n.weatherAlerts,
                        value: _effectiveCapabilityLabel(
                          context,
                          capabilitySetup.notifications.weatherAlertState,
                        ),
                        good:
                            capabilitySetup.notifications.weatherAlertState ==
                            EffectiveCapabilityState.active,
                      ),
                    ],
                  ),
                const SizedBox(height: HkSpacing.xs),
                ListTile(
                  key: const ValueKey('settings-permission-education'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.health_and_safety_rounded),
                  title: Text(context.l10n.permissionSetup),
                  subtitle: Text(context.l10n.permissionSetupSubtitle),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => _openPermissionSetup(context, ref),
                ),
                const SizedBox(height: HkSpacing.xs),
                Text(
                  context.l10n.preferences,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: HkSpacing.space4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(context.l10n.homePilotAlerts),
                  subtitle: Text(context.l10n.homePilotAlertsDescription),
                  value: notificationPreferences.enabled,
                  onChanged: (value) => _saveNotificationPreferences(
                    context,
                    ref,
                    notificationPreferences.copyWith(enabled: value),
                  ),
                ),
                if (capabilitySetup != null &&
                    notificationPreferences.allowsLocalReminders &&
                    capabilitySetup.notifications.deviceReminderState !=
                        EffectiveCapabilityState.active)
                  _EffectiveCapabilityPreferenceTile(
                    key: const ValueKey('device-reminders-recovery'),
                    icon: Symbols.alarm_rounded,
                    title: context.l10n.deviceReminders,
                    subtitle: context.l10n.scheduledAndroidReminderDelivery,
                    state: capabilitySetup.notifications.deviceReminderState,
                    onFix: () => _enableDeviceReminders(context, ref),
                  )
                else
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Symbols.alarm_rounded),
                    title: Text(context.l10n.deviceReminders),
                    subtitle: Text(
                      context.l10n.scheduledAndroidReminderDelivery,
                    ),
                    value:
                        notificationPreferences.enabled &&
                        notificationPreferences.localReminders,
                    onChanged: notificationPreferences.enabled
                        ? (value) => value
                              ? _enableDeviceReminders(context, ref)
                              : _saveNotificationPreferences(
                                  context,
                                  ref,
                                  notificationPreferences.copyWith(
                                    localReminders: false,
                                    preferExactReminders: false,
                                  ),
                                )
                        : null,
                  ),
                if (capabilitySetup != null &&
                    notificationPreferences.preferExactReminders &&
                    capabilitySetup.notifications.exactTimingState !=
                        EffectiveCapabilityState.active)
                  _EffectiveCapabilityPreferenceTile(
                    key: const ValueKey('exact-reminders-recovery'),
                    icon: Symbols.alarm_on_rounded,
                    title: context.l10n.preciseReminderAlarms,
                    subtitle:
                        context.l10n.askAndroidForAlarmsAndRemindersAccess,
                    state: capabilitySetup.notifications.exactTimingState,
                    approximateWhenDegraded: true,
                    onFix: notificationPreferences.allowsLocalReminders
                        ? () => _enableExactTiming(context, ref)
                        : null,
                  )
                else
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Symbols.alarm_on_rounded),
                    title: Text(context.l10n.preciseReminderAlarms),
                    subtitle: Text(
                      context.l10n.askAndroidForAlarmsAndRemindersAccess,
                    ),
                    value:
                        notificationPreferences.enabled &&
                        notificationPreferences.preferExactReminders,
                    onChanged: notificationPreferences.allowsLocalReminders
                        ? (value) => value
                              ? _enableExactTiming(context, ref)
                              : _saveNotificationPreferences(
                                  context,
                                  ref,
                                  notificationPreferences.copyWith(
                                    preferExactReminders: false,
                                  ),
                                )
                        : null,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Symbols.inbox_rounded),
                  title: Text(context.l10n.inAppInbox),
                  subtitle: Text(
                    context.l10n.unreadTaskWeatherAndDigestUpdates,
                  ),
                  value:
                      notificationPreferences.enabled &&
                      notificationPreferences.inAppInbox,
                  onChanged: notificationPreferences.enabled
                      ? (value) => _saveNotificationPreferences(
                          context,
                          ref,
                          notificationPreferences.copyWith(inAppInbox: value),
                        )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Symbols.rainy_rounded),
                  title: Text(context.l10n.weatherAlerts),
                  subtitle: Text(context.l10n.weatherAlertsInboxDescription),
                  value:
                      notificationPreferences.enabled &&
                      notificationPreferences.weatherAlerts,
                  onChanged: notificationPreferences.enabled
                      ? (value) => _saveNotificationPreferences(
                          context,
                          ref,
                          notificationPreferences.copyWith(
                            weatherAlerts: value,
                          ),
                        )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Symbols.do_not_disturb_on_rounded),
                  title: Text(context.l10n.quietHours),
                  subtitle: Text(
                    '${_minutesLabel(context, notificationPreferences.quietHoursStartMinutes)} - ${_minutesLabel(context, notificationPreferences.quietHoursEndMinutes)}',
                  ),
                  value:
                      notificationPreferences.enabled &&
                      notificationPreferences.quietHoursEnabled,
                  onChanged: notificationPreferences.enabled
                      ? (value) => _saveNotificationPreferences(
                          context,
                          ref,
                          notificationPreferences.copyWith(
                            quietHoursEnabled: value,
                          ),
                        )
                      : null,
                ),
                if (notificationPreferences.quietHoursEnabled) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: HkSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Symbols.bedtime_rounded),
                          title: Text(context.l10n.quietHoursStart),
                          subtitle: Text(
                            _minutesLabel(
                              context,
                              notificationPreferences.quietHoursStartMinutes,
                            ),
                          ),
                          trailing: Icon(
                            Directionality.of(context) == TextDirection.rtl
                                ? Symbols.chevron_left_rounded
                                : Symbols.chevron_right_rounded,
                          ),
                          onTap: notificationPreferences.enabled
                              ? () => _pickQuietHour(
                                  context,
                                  ref,
                                  notificationPreferences,
                                  start: true,
                                )
                              : null,
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Symbols.wb_sunny_rounded),
                          title: Text(context.l10n.quietHoursEnd),
                          subtitle: Text(
                            _minutesLabel(
                              context,
                              notificationPreferences.quietHoursEndMinutes,
                            ),
                          ),
                          trailing: const Icon(Symbols.chevron_right_rounded),
                          onTap: notificationPreferences.enabled
                              ? () => _pickQuietHour(
                                  context,
                                  ref,
                                  notificationPreferences,
                                  start: false,
                                )
                              : null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Symbols.priority_high_rounded),
                          title: Text(context.l10n.criticalRemindersBypass),
                          subtitle: Text(
                            context
                                .l10n
                                .criticalTasksCanStillAlertDuringQuietHours,
                          ),
                          value:
                              notificationPreferences.enabled &&
                              notificationPreferences.criticalBypassQuietHours,
                          onChanged: notificationPreferences.enabled
                              ? (value) => _saveNotificationPreferences(
                                  context,
                                  ref,
                                  notificationPreferences.copyWith(
                                    criticalBypassQuietHours: value,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Symbols.privacy_tip_rounded),
                  title: Text(context.l10n.hideLockScreenDetails),
                  subtitle: Text(
                    context.l10n.showGenericReminderTextOutsideTheApp,
                  ),
                  value:
                      notificationPreferences.enabled &&
                      notificationPreferences.privacyMode,
                  onChanged: notificationPreferences.enabled
                      ? (value) => _saveNotificationPreferences(
                          context,
                          ref,
                          notificationPreferences.copyWith(privacyMode: value),
                        )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Symbols.summarize_rounded),
                  title: Text(context.l10n.dailyDigest),
                  subtitle: Text(context.l10n.groupedReminderSummary),
                  value:
                      notificationPreferences.enabled &&
                      notificationPreferences.dailyDigest,
                  onChanged: notificationPreferences.enabled
                      ? (value) => _saveNotificationPreferences(
                          context,
                          ref,
                          notificationPreferences.copyWith(dailyDigest: value),
                        )
                      : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.snooze_rounded),
                  title: Text(context.l10n.defaultSnooze),
                  subtitle: Text(
                    _durationLabel(
                      context,
                      Duration(
                        minutes: notificationPreferences.defaultSnoozeMinutes,
                      ),
                    ),
                  ),
                  trailing: DropdownButton<int>(
                    value: notificationPreferences.defaultSnoozeMinutes,
                    items: [
                      for (final minutes in snoozeOptions)
                        DropdownMenuItem(
                          value: minutes,
                          child: Text(
                            _durationLabel(context, Duration(minutes: minutes)),
                          ),
                        ),
                    ],
                    onChanged: notificationPreferences.enabled
                        ? (minutes) {
                            if (minutes == null) {
                              return;
                            }
                            _saveNotificationPreferences(
                              context,
                              ref,
                              notificationPreferences.copyWith(
                                defaultSnoozeMinutes: minutes,
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.notifications_rounded),
                  title: Text(context.l10n.maxRemindersPerDay),
                  subtitle: Text(
                    context.l10n.reminderCountLabel(
                      notificationPreferences.maxRemindersPerDay,
                    ),
                  ),
                  trailing: DropdownButton<int>(
                    value: notificationPreferences.maxRemindersPerDay,
                    items: [
                      for (final count in const [2, 4, 6, 8, 12, 24])
                        DropdownMenuItem(
                          value: count,
                          child: Text(_formatInteger(context, count)),
                        ),
                    ],
                    onChanged: notificationPreferences.enabled
                        ? (count) {
                            if (count == null) {
                              return;
                            }
                            _saveNotificationPreferences(
                              context,
                              ref,
                              notificationPreferences.copyWith(
                                maxRemindersPerDay: count,
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.schedule_rounded),
                  title: Text(context.l10n.reminderTime),
                  subtitle: Text(
                    _hourLabel(context, notificationPreferences.reminderHour),
                  ),
                  trailing: DropdownButton<int>(
                    value: notificationPreferences.reminderHour,
                    items: [
                      for (final hour in reminderHours)
                        DropdownMenuItem(
                          value: hour,
                          child: Text(_hourLabel(context, hour)),
                        ),
                    ],
                    onChanged: notificationPreferences.enabled
                        ? (hour) {
                            if (hour == null) {
                              return;
                            }
                            _saveNotificationPreferences(
                              context,
                              ref,
                              notificationPreferences.copyWith(
                                reminderHour: hour,
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.event_note_rounded),
                  title: Text(context.l10n.digestTime),
                  subtitle: Text(
                    _hourLabel(context, notificationPreferences.digestHour),
                  ),
                  trailing: DropdownButton<int>(
                    value: notificationPreferences.digestHour,
                    items: [
                      for (final hour in digestHours)
                        DropdownMenuItem(
                          value: hour,
                          child: Text(_hourLabel(context, hour)),
                        ),
                    ],
                    onChanged: notificationPreferences.enabled
                        ? (hour) {
                            if (hour == null) {
                              return;
                            }
                            _saveNotificationPreferences(
                              context,
                              ref,
                              notificationPreferences.copyWith(
                                digestHour: hour,
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                _ReminderSettingsActions(
                  onSendTest: () => _sendTestNotification(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setThemePreference(
    BuildContext context,
    WidgetRef ref,
    ThemePreference preference,
  ) async {
    try {
      final repository = ref.read(settingsRepositoryProvider);
      await repository.setThemePreference(preference);
      await repository.setTimeOfDayThemeEnabled(
        preference == ThemePreference.system,
      );
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.themeUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _openPermissionSetup(BuildContext context, WidgetRef ref) async {
    await context.push('/permissions/setup');
  }

  Future<void> _setAppLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLanguage language,
  ) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setAppLocalePreference(language);
    } on Object {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(context.l10n.languageUpdateFailedPleaseTryAgain),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _searchLocation(BuildContext context, WidgetRef ref) async {
    final location = await _showEditorModal<HomeLocation>(
      context,
      builder: (context) => const LocationPickerSheet(),
    );
    if (location == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await ref.read(settingsRepositoryProvider).setHomeLocation(location);
    await ref.read(weatherRepositoryProvider).refreshWeather();
    await refreshNotificationSchedules(ref);
    await ref
        .read(permissionEducationControllerProvider.notifier)
        .refreshCapabilities();
    if (!context.mounted) {
      return;
    }
    ref.invalidate(homeLocationProvider);
    ref.invalidate(weatherProvider);
  }

  Future<void> _useDeviceLocation(BuildContext context, WidgetRef ref) async {
    try {
      final controller = ref.read(
        permissionEducationControllerProvider.notifier,
      );
      await controller.refreshCapabilities();
      await controller.useCurrentLocation();
      if (!context.mounted) {
        return;
      }
      final location =
          controller.currentState.setupSnapshot?.weather.selectedArea;
      if (location == null || location.source.toLowerCase() != 'device') {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.deviceLocationIsUnavailable),
          severity: hk_ui.HkToastSeverity.error,
        );
        return;
      }
      await ref.read(weatherRepositoryProvider).refreshWeather();
      await refreshNotificationSchedules(ref);
      if (!context.mounted) {
        return;
      }
      ref.invalidate(homeLocationProvider);
      ref.invalidate(weatherProvider);
      hk_ui.showToast(
        context,
        content: Text(context.l10n.weatherLocationUpdated),
      );
    } catch (error) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(
              context,
              error,
              fallback: AppFailureCode.locationUpdate,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }

  Future<void> _pickQuietHour(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences, {
    required bool start,
  }) async {
    final initialMinutes = start
        ? preferences.quietHoursStartMinutes
        : preferences.quietHoursEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDayFromMinutes(initialMinutes),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    final minutes = _minutesFromTimeOfDay(picked);
    await _saveNotificationPreferences(
      context,
      ref,
      start
          ? preferences.copyWith(quietHoursStartMinutes: minutes)
          : preferences.copyWith(quietHoursEndMinutes: minutes),
    );
  }

  Future<void> _saveNotificationPreferences(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences,
  ) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setNotificationPreferences(preferences);
      ref.invalidate(notificationPreferencesProvider);
      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      await scheduler.refreshSchedules();
      ref.invalidate(notificationPermissionStateProvider);
      await ref
          .read(permissionEducationControllerProvider.notifier)
          .refreshCapabilities();
      if (!context.mounted) {
        return;
      }
      hk_ui.showToast(
        context,
        content: Text(context.l10n.notificationSettingsUpdated),
      );
    } catch (error) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(
              context,
              error,
              fallback: AppFailureCode.notificationSetup,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }

  Future<void> _enableDeviceReminders(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final controller = ref.read(
        permissionEducationControllerProvider.notifier,
      );
      await controller.refreshCapabilities();
      await controller.enableNotifications();
      ref.invalidate(notificationPreferencesProvider);
      ref.invalidate(notificationPermissionStateProvider);
      if (!context.mounted) return;
      final effective = controller
          .currentState
          .setupSnapshot
          ?.notifications
          .deviceReminderState;
      if (effective == EffectiveCapabilityState.active) {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.notificationSettingsUpdated),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(
            context,
            error,
            fallback: AppFailureCode.notificationSetup,
          ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _enableExactTiming(BuildContext context, WidgetRef ref) async {
    try {
      final controller = ref.read(
        permissionEducationControllerProvider.notifier,
      );
      await controller.refreshCapabilities();
      await controller.enableExactTiming();
      ref.invalidate(notificationPreferencesProvider);
      ref.invalidate(notificationPermissionStateProvider);
      if (!context.mounted) return;
      final effective =
          controller.currentState.setupSnapshot?.notifications.exactTimingState;
      hk_ui.showToast(
        context,
        content: Text(
          effective == EffectiveCapabilityState.active
              ? context.l10n.notificationSettingsUpdated
              : context.l10n.approximateReminderTimingWarning,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(
            context,
            error,
            fallback: AppFailureCode.notificationSetup,
          ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _sendTestNotification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final allowed = await _ensurePermission(
        context,
        ref,
        kind: AppPermissionKind.notifications,
        title: context.l10n.sendATestReminder,
        message: context.l10n.allowNotificationsForReminders,
      );
      if (!allowed || !context.mounted) return;
      await ref.read(notificationSchedulerProvider).sendTestReminder();
      if (!context.mounted) {
        return;
      }
      ref.invalidate(notificationPermissionStateProvider);
      hk_ui.showToast(
        context,
        content: Text(context.l10n.testReminderScheduled),
      );
    } catch (error) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(
              context,
              error,
              fallback: AppFailureCode.testReminder,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }

  Future<bool> _ensurePermission(
    BuildContext context,
    WidgetRef ref, {
    required AppPermissionKind kind,
    required String title,
    required String message,
  }) async {
    final coordinator = ref.read(permissionCoordinatorProvider);
    var state = await coordinator.check(kind);
    if (state == AppPermissionState.granted) return true;
    if (!context.mounted) return false;
    if (state == AppPermissionState.serviceDisabled) {
      final open = await _permissionDialog(
        context,
        title: context.l10n.locationServicesAreOff,
        message: context.l10n.turnOnLocationServices,
        action: context.l10n.openSettings,
      );
      if (open) await coordinator.openLocationServiceSettings();
      return false;
    }
    if (state == AppPermissionState.permanentlyDenied ||
        state == AppPermissionState.restricted) {
      final open = await _permissionDialog(
        context,
        title: context.l10n.permissionNeeded,
        message: context.l10n.allowInSystemSettings(message),
        action: context.l10n.openSettings,
      );
      if (open) await coordinator.openAppPermissionSettings();
      return false;
    }
    if (state == AppPermissionState.unavailable) return false;
    final continueRequest = await _permissionDialog(
      context,
      title: title,
      message: message,
      action: context.l10n.continueLabel,
    );
    if (!continueRequest) return false;
    state = await coordinator.request(kind);
    if (state == AppPermissionState.granted) return true;
    if (context.mounted && state == AppPermissionState.permanentlyDenied) {
      final open = await _permissionDialog(
        context,
        title: context.l10n.permissionBlocked,
        message: context.l10n.allowPermissionInSystemSettings,
        action: context.l10n.openSettings,
      );
      if (open) await coordinator.openAppPermissionSettings();
    }
    return false;
  }

  Future<bool> _permissionDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.notNow),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _ReminderSettingsActions extends StatelessWidget {
  const _ReminderSettingsActions({required this.onSendTest});

  final VoidCallback onSendTest;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onSendTest,
          icon: const Icon(Symbols.notification_add_rounded, size: 19),
          label: Text(context.l10n.sendTest, maxLines: 1),
        ),
      ),
    );
  }
}

class _NotificationStatusRow extends StatelessWidget {
  const _NotificationStatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.good,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? HkColors.green : HkColors.tertiary;
    return Padding(
      padding: const EdgeInsets.only(bottom: HkSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: HkSpacing.xs),
          Expanded(child: Text(label)),
          hk_ui.StatusPill(label: value, color: color, compact: true),
        ],
      ),
    );
  }
}

class _EffectiveCapabilityPreferenceTile extends StatelessWidget {
  const _EffectiveCapabilityPreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onFix,
    this.approximateWhenDegraded = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final EffectiveCapabilityState state;
  final VoidCallback? onFix;
  final bool approximateWhenDegraded;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Semantics(
      container: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: HkSpacing.xs,
          children: [
            hk_ui.StatusPill(
              label: _effectiveCapabilityLabel(
                context,
                state,
                approximateWhenDegraded: approximateWhenDegraded,
              ),
              color: color,
              compact: true,
            ),
            if (onFix != null)
              TextButton(onPressed: onFix, child: Text(context.l10n.fix)),
          ],
        ),
      ),
    );
  }
}

String _effectiveCapabilityLabel(
  BuildContext context,
  EffectiveCapabilityState state, {
  bool approximateWhenDegraded = false,
}) {
  return switch (state) {
    EffectiveCapabilityState.active => context.l10n.allowed,
    EffectiveCapabilityState.degraded =>
      approximateWhenDegraded
          ? context.l10n.approximateTiming
          : context.l10n.limited,
    EffectiveCapabilityState.blocked => context.l10n.blocked,
    EffectiveCapabilityState.disabledByUser => context.l10n.disabled,
    EffectiveCapabilityState.notConfigured => context.l10n.notSet,
    EffectiveCapabilityState.unavailable => context.l10n.unavailable,
  };
}

String _hourLabel(BuildContext context, int hour) {
  return MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay(hour: hour, minute: 0));
}

String _minutesLabel(BuildContext context, int minutes) {
  final clamped = minutes.clamp(0, 1439).toInt();
  return MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60));
}

TimeOfDay _timeOfDayFromMinutes(int minutes) {
  final clamped = minutes.clamp(0, 1439).toInt();
  return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
}

int _minutesFromTimeOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

class LocationPickerSheet extends ConsumerStatefulWidget {
  const LocationPickerSheet({super.key});

  @override
  ConsumerState<LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<LocationPickerSheet> {
  final _controller = TextEditingController();
  Future<List<HomeLocation>>? _results;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EditorSheetFrame(
      title: context.l10n.homeLocation,
      saveLabel: context.l10n.close,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Symbols.search_rounded),
              labelText: context.l10n.cityOrZip,
            ),
            onSubmitted: _search,
          ),
          const SizedBox(height: HkSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _search(_controller.text),
              icon: const Icon(Symbols.search_rounded),
              label: Text(context.l10n.search),
            ),
          ),
          const SizedBox(height: HkSpacing.md),
          FutureBuilder<List<HomeLocation>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                );
              }
              final results = snapshot.data ?? const <HomeLocation>[];
              if (results.isEmpty) {
                return hk_ui.PremiumEmptyState(
                  icon: Symbols.location_on_rounded,
                  title: context.l10n.searchForALocation,
                  body: context.l10n.weatherContextImprovesOutdoorTasks,
                );
              }
              return Column(
                children: [
                  for (final location in results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.location_on_rounded),
                      title: Text(location.label),
                      subtitle: Text(
                        '${location.latitude.toStringAsFixed(2)}, ${location.longitude.toStringAsFixed(2)}',
                      ),
                      onTap: () => Navigator.of(context).pop(location),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _search(String query) {
    setState(() {
      _results = ref.read(weatherRepositoryProvider).searchLocations(query);
    });
  }
}

enum _RestoreCloudChoice { localOnlyPause, updateCloud }

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  bool _backupLoadingIndicatorVisible = false;
  int _backupOperationId = 0;
  Timer? _backupLoadingTimer;
  bool _showBackupDetails = false;
  String _busyLabel = '';
  BackupState _state = const BackupState();
  BackupPreview? _restorePreview;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_loadBackupState);
  }

  @override
  Widget build(BuildContext context) {
    final last = _state.lastBackup;
    final backupRunning = _busy && _busyLabel == context.l10n.creatingBackup;
    final canShare =
        !_busy && last?.successful == true && (last?.path?.isNotEmpty ?? false);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.backupAndRestore)),
      body: hk_ui.ProductivityBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  HkSpacing.gutter,
                  HkSpacing.xs,
                  HkSpacing.gutter,
                  96 + bottomPadding,
                ),
                children: [
                  _BackupStatusPanel(
                    status: last,
                    description: _statusDescription(context, last),
                    showDetails: _showBackupDetails,
                    onToggleDetails: last?.path == null
                        ? null
                        : () => setState(
                            () => _showBackupDetails = !_showBackupDetails,
                          ),
                  ),
                  const SizedBox(height: HkSpacing.sm),
                  _BackupCreatePanel(
                    busy: backupRunning,
                    showLoadingIndicator: _backupLoadingIndicatorVisible,
                    automaticBackupsEnabled: _state.automaticBackupsEnabled,
                    canShare: canShare,
                    onCreate: _exportBackup,
                    onShare: _shareBackup,
                    onAutomaticChanged: _setAutomaticBackupsEnabled,
                  ),
                  const SizedBox(height: HkSpacing.sm),
                  _BackupRestorePanel(
                    busy: _busy,
                    preview: _restorePreview,
                    onChoose: _chooseRestoreBackup,
                    onRestore: _confirmRestore,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadBackupState() async {
    try {
      final state = await ref.read(backupRepositoryProvider).backupState();
      if (mounted) {
        setState(() => _state = state);
      }
    } catch (_) {
      // The screen can still create a fresh backup if local status is unreadable.
    }
  }

  Future<void> _exportBackup() async {
    if (_busy) {
      return;
    }
    final operationId = ++_backupOperationId;
    _setBusy(context.l10n.creatingBackup);
    _scheduleBackupLoadingIndicator(operationId);
    try {
      final path = await ref.read(backupRepositoryProvider).exportBackup();
      if (!mounted || operationId != _backupOperationId) {
        return;
      }
      _cancelBackupLoadingIndicator();
      await _loadBackupState();
      if (!mounted) {
        return;
      }
      hk_ui.showToast(
        context,
        content: Text(context.l10n.backupCreatedFilename(p.basename(path))),
      );
    } catch (error) {
      if (mounted && operationId == _backupOperationId) {
        _cancelBackupLoadingIndicator();
        AppLogger.warning('backup_export', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted && operationId == _backupOperationId) {
        _cancelBackupLoadingIndicator();
        _clearBusy();
      }
    }
  }

  Future<void> _shareBackup() async {
    final path = _state.lastBackup?.path;
    if (path == null) {
      return;
    }
    if (!await File(path).exists()) {
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.lastBackupFileMissing),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
      return;
    }
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: context.l10n.homePilotBackupShareText,
      ),
    );
  }

  Future<void> _setAutomaticBackupsEnabled(bool enabled) async {
    _setBusy(context.l10n.updatingBackupSettings);
    try {
      await ref
          .read(backupRepositoryProvider)
          .setAutomaticBackupsEnabled(enabled);
      await _loadBackupState();
    } catch (error) {
      if (mounted) {
        AppLogger.warning('backup_settings_update', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        _clearBusy();
      }
    }
  }

  Future<void> _chooseRestoreBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    _setBusy(context.l10n.checkingBackup);
    try {
      final preview = await ref
          .read(backupRepositoryProvider)
          .inspectBackup(path);
      if (!mounted) {
        return;
      }
      setState(() => _restorePreview = preview);
    } catch (error) {
      if (mounted) {
        AppLogger.warning('backup_inspection', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        _clearBusy();
      }
    }
  }

  Future<void> _confirmRestore() async {
    final preview = _restorePreview;
    if (preview == null) {
      return;
    }
    final syncStatus = await ref.read(cloudSyncRepositoryProvider).status();
    if (!mounted) return;
    final choice = await showDialog<_RestoreCloudChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const _BackupIconBadge(
          icon: Symbols.restore_rounded,
          color: HkColors.green,
          size: 58,
        ),
        title: Text(context.l10n.restoreThisBackup),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.restoreReplacesLocalData(
                  _formatDate(context, preview.createdAt),
                ),
              ),
              const SizedBox(height: HkSpacing.sm),
              _BackupDialogNotice(
                icon: Symbols.warning_rounded,
                color: HkColors.appDanger,
                text: context.l10n.restoreReplacementWarning,
              ),
              if (syncStatus.enabled) ...[
                const SizedBox(height: HkSpacing.sm),
                _BackupDialogNotice(
                  icon: Symbols.cloud_sync_rounded,
                  color: HkColors.green,
                  text: context.l10n.cloudRestoreSafetyNotice,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          if (syncStatus.enabled)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_RestoreCloudChoice.updateCloud),
              child: Text(context.l10n.restoreAndUpdateCloudBackup),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_RestoreCloudChoice.localOnlyPause),
            child: Text(
              syncStatus.enabled
                  ? context.l10n.restoreLocallyAndPauseCloudBackup
                  : context.l10n.restoreBackup,
            ),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _restoreSelectedBackup(preview, choice);
    }
  }

  Future<void> _restoreSelectedBackup(
    BackupPreview preview,
    _RestoreCloudChoice choice,
  ) async {
    _setBusy(context.l10n.restoringBackup);
    try {
      if (choice == _RestoreCloudChoice.updateCloud) {
        await ref.read(cloudSyncRepositoryProvider).syncNow();
      } else {
        await ref.read(cloudSyncRepositoryProvider).disable();
      }
      await ref.read(backupRepositoryProvider).restoreBackup(preview.path);
      final localStore = ref.read(localSyncStoreProvider);
      if (choice == _RestoreCloudChoice.localOnlyPause) {
        await localStore?.pauseAfterLocalRestore();
      } else {
        await localStore?.enqueueRestoreSnapshot(DateTime.now());
        await ref.read(cloudSyncRepositoryProvider).fullReconcile();
      }
      _reloadRestoredProviders();
      await ref.read(searchRepositoryProvider).rebuildIndex();
      if (ref.read(notificationAutoStartProvider)) {
        final scheduler = ref.read(notificationSchedulerProvider);
        await scheduler.initialize();
        await scheduler.refreshSchedules();
      }
      await _loadBackupState();
      if (!mounted) {
        return;
      }
      setState(() => _restorePreview = null);
      hk_ui.showToast(context, content: Text(context.l10n.backupRestored));
    } catch (error) {
      if (mounted) {
        AppLogger.warning('backup_restore', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        _clearBusy();
      }
    }
  }

  void _reloadRestoredProviders() {
    ref.invalidate(databaseProvider);
    ref.invalidate(assetRepositoryProvider);
    ref.invalidate(maintenanceRepositoryProvider);
    ref.invalidate(calendarRepositoryProvider);
    ref.invalidate(streakServiceProvider);
    ref.invalidate(statisticsRepositoryProvider);
    ref.invalidate(settingsRepositoryProvider);
    ref.invalidate(notificationInboxRepositoryProvider);
    ref.invalidate(weatherRepositoryProvider);
    ref.invalidate(backupRepositoryProvider);
    ref.invalidate(searchRepositoryProvider);
    ref.invalidate(notificationSchedulerProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(homeLocationProvider);
    ref.invalidate(weatherProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
    ref.invalidate(notificationPreferencesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(areasProvider);
    ref.invalidate(roomsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(assetsProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(statisticsProvider);
    ref.invalidate(streakRefreshProvider);
  }

  void _setBusy(String label) {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
  }

  void _clearBusy() {
    setState(() {
      _busy = false;
      _busyLabel = '';
      _backupLoadingIndicatorVisible = false;
    });
  }

  void _scheduleBackupLoadingIndicator(int operationId) {
    _backupLoadingTimer?.cancel();
    _backupLoadingTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || operationId != _backupOperationId || !_busy) {
        return;
      }
      setState(() {
        _backupLoadingIndicatorVisible = true;
      });
    });
  }

  void _cancelBackupLoadingIndicator() {
    _backupLoadingTimer?.cancel();
    _backupLoadingTimer = null;
    if (_backupLoadingIndicatorVisible && mounted) {
      setState(() {
        _backupLoadingIndicatorVisible = false;
      });
    } else {
      _backupLoadingIndicatorVisible = false;
    }
  }

  @override
  void dispose() {
    _backupLoadingTimer?.cancel();
    super.dispose();
  }

  String _statusDescription(BuildContext context, BackupStatus? status) {
    if (status == null) {
      return context.l10n.noBackupCreatedOnThisDevice;
    }
    final when = status.createdAt ?? status.updatedAt;
    final action = switch (status.trigger) {
      BackupTrigger.manual => context.l10n.manualBackup,
      BackupTrigger.automatic => context.l10n.automaticBackup,
      BackupTrigger.preRestore => context.l10n.safetyBackup,
    };
    if (status.successful) {
      final date = _formatDate(context, when);
      return status.sizeBytes == null
          ? context.l10n.lastBackupAt(date)
          : context.l10n.lastBackupAtWithSize(
              date,
              _formatBytes(context, status.sizeBytes!),
            );
    }
    return context.l10n.backupFailedAt(
      action,
      _formatDate(context, status.updatedAt),
    );
  }
}

class _BackupStatusPanel extends StatelessWidget {
  const _BackupStatusPanel({
    required this.status,
    required this.description,
    required this.showDetails,
    required this.onToggleDetails,
  });

  final BackupStatus? status;
  final String description;
  final bool showDetails;
  final VoidCallback? onToggleDetails;

  @override
  Widget build(BuildContext context) {
    final color = _backupStatusColor(context, status);
    final path = status?.path;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderRadius: HkRadii.xxl,
      backgroundColor: _backupTintedSurface(context, color, 0.035),
      borderColor: color.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackupIconBadge(
                icon: _backupStatusIcon(status),
                color: color,
                size: 50,
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status?.successful == true
                          ? context.l10n.latestBackup
                          : context.l10n.backupStatus,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: HkSpacing.space4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.sm),
              hk_ui.StatusPill(
                label: _backupStatusLabel(context, status),
                color: color,
                icon: _backupStatusPillIcon(status),
                compact: true,
              ),
            ],
          ),
          if (status?.message != null) ...[
            const SizedBox(height: HkSpacing.sm),
            _BackupInlineNote(
              icon: Symbols.info_rounded,
              color: color,
              text: status!.successful
                  ? context.l10n.backupComplete
                  : context.l10n.backupFailedPleaseTryAgain,
            ),
          ],
          if (path != null) ...[
            const SizedBox(height: HkSpacing.sm),
            TextButton.icon(
              onPressed: onToggleDetails,
              icon: const Icon(Symbols.folder_rounded),
              label: Text(
                showDetails
                    ? context.l10n.hideBackupDetails
                    : context.l10n.viewBackupDetails,
              ),
            ),
            if (showDetails)
              _BackupPathBox(
                path: path,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _BackupCreatePanel extends StatelessWidget {
  const _BackupCreatePanel({
    required this.busy,
    required this.showLoadingIndicator,
    required this.automaticBackupsEnabled,
    required this.canShare,
    required this.onCreate,
    required this.onShare,
    required this.onAutomaticChanged,
  });

  final bool busy;
  final bool showLoadingIndicator;
  final bool automaticBackupsEnabled;
  final bool canShare;
  final VoidCallback onCreate;
  final VoidCallback onShare;
  final ValueChanged<bool> onAutomaticChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderRadius: HkRadii.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackupPanelHeader(
            icon: Symbols.backup_rounded,
            color: HkColors.green,
            title: context.l10n.createBackup,
            subtitle: context.l10n.backupsAreSavedLocallyAsPrivateZipFiles,
          ),
          const SizedBox(height: HkSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 520;
              final createButton = Semantics(
                button: true,
                enabled: !busy,
                liveRegion: false,
                child: FilledButton(
                  onPressed: busy ? null : onCreate,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: showLoadingIndicator
                        ? Row(
                            key: const ValueKey('backup-loading'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: RepaintBoundary(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: HkSpacing.xs),
                              Flexible(
                                child: Text(
                                  context.l10n.creatingBackup,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            key: const ValueKey('backup-idle'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Symbols.backup_rounded),
                              const SizedBox(width: HkSpacing.xs),
                              Text(
                                context.l10n.createBackup,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                ),
              );
              final shareButton = OutlinedButton.icon(
                onPressed: canShare ? onShare : null,
                icon: const Icon(Symbols.ios_share_rounded),
                label: Text(context.l10n.shareLatestBackup),
              );
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: createButton),
                    const SizedBox(width: HkSpacing.sm),
                    Expanded(child: shareButton),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  createButton,
                  const SizedBox(height: HkSpacing.xs),
                  shareButton,
                ],
              );
            },
          ),
          const SizedBox(height: HkSpacing.md),
          Container(
            padding: const EdgeInsets.all(HkSpacing.sm),
            decoration: BoxDecoration(
              color: _backupTintedSurface(context, HkColors.green, 0.045),
              borderRadius: BorderRadius.circular(HkRadii.lg),
              border: Border.all(color: HkColors.green.withValues(alpha: 0.14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BackupIconBadge(
                  icon: Symbols.autorenew_rounded,
                  color: HkColors.green,
                  size: 42,
                ),
                const SizedBox(width: HkSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.automaticLocalBackups,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: HkSpacing.space4),
                      Text(
                        context.l10n.automaticBackupsDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: HkSpacing.xs),
                Switch(
                  value: automaticBackupsEnabled,
                  onChanged: busy ? null : onAutomaticChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupRestorePanel extends StatelessWidget {
  const _BackupRestorePanel({
    required this.busy,
    required this.preview,
    required this.onChoose,
    required this.onRestore,
  });

  final bool busy;
  final BackupPreview? preview;
  final VoidCallback onChoose;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderRadius: HkRadii.xxl,
      backgroundColor: _backupTintedSurface(context, HkColors.green, 0.026),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackupPanelHeader(
            icon: Symbols.restore_rounded,
            color: HkColors.green,
            title: context.l10n.restoreFromABackup,
            subtitle: context.l10n.restorePreviewDescription,
          ),
          const SizedBox(height: HkSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onChoose,
              icon: const Icon(Symbols.upload_file_rounded),
              label: Text(context.l10n.chooseBackupZip),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: HkSpacing.md),
            _BackupPreviewPanel(
              preview: preview!,
              onRestore: busy ? null : onRestore,
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupPanelHeader extends StatelessWidget {
  const _BackupPanelHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackupIconBadge(icon: icon, color: color, size: 48),
        const SizedBox(width: HkSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: HkSpacing.space4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackupIconBadge extends StatelessWidget {
  const _BackupIconBadge({
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, color, 0.12),
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class _BackupInlineNote extends StatelessWidget {
  const _BackupInlineNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HkSpacing.xs),
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, color, 0.07),
        borderRadius: BorderRadius.circular(HkRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupPathBox extends StatelessWidget {
  const _BackupPathBox({required this.path, required this.color});

  final String path;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HkSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(HkRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: SelectableText(path, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _BackupDialogNotice extends StatelessWidget {
  const _BackupDialogNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _BackupInlineNote(icon: icon, color: color, text: text);
  }
}

class _BackupPreviewPanel extends StatelessWidget {
  const _BackupPreviewPanel({required this.preview, required this.onRestore});

  final BackupPreview preview;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(HkSpacing.md),
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, HkColors.green, 0.05),
        borderRadius: BorderRadius.circular(HkRadii.xl),
        border: Border.all(color: HkColors.green.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BackupIconBadge(
                icon: Symbols.inventory_2_rounded,
                color: HkColors.green,
                size: 44,
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.backupFromDate(
                        _formatDate(context, preview.createdAt),
                      ),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: HkSpacing.space4),
                    Text(
                      context.l10n.backupFormatSummary(
                        preview.formatVersion,
                        preview.schemaVersion,
                        _formatBytes(context, preview.backupSizeBytes),
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.md),
          Wrap(
            spacing: HkSpacing.xs,
            runSpacing: HkSpacing.xs,
            children: [
              _BackupMetric(
                label: context.l10n.tasks,
                value: preview.taskCount,
              ),
              _BackupMetric(
                label: context.l10n.items,
                value: preview.thingCount,
              ),
              _BackupMetric(
                label: context.l10n.history,
                value: preview.historyCount,
              ),
              _BackupMetric(
                label: context.l10n.files,
                value: preview.fileCount,
              ),
              _BackupMetric(
                label: context.l10n.notifications,
                value: preview.notificationCount,
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.sm),
          _BackupInlineNote(
            icon: Symbols.check_circle_rounded,
            color: HkColors.green,
            text: context.l10n.backupWillRestore(
              preview.includedData
                  .map((value) => _localizedBackupDetail(context, value))
                  .join(', '),
            ),
          ),
          const SizedBox(height: HkSpacing.xs),
          _BackupInlineNote(
            icon: Symbols.remove_circle_rounded,
            color: scheme.onSurfaceVariant,
            text: context.l10n.backupNotIncluded(
              preview.excludedData
                  .map((value) => _localizedBackupDetail(context, value))
                  .join(', '),
            ),
          ),
          if (preview.warnings.isNotEmpty) ...[
            const SizedBox(height: HkSpacing.sm),
            for (final warning in preview.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: HkSpacing.space4),
                child: _BackupInlineNote(
                  icon: Symbols.warning_rounded,
                  color: HkColors.appWarning,
                  text: _localizedBackupWarning(context, warning),
                ),
              ),
          ],
          const SizedBox(height: HkSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRestore,
              icon: const Icon(Symbols.restore_rounded),
              label: Text(context.l10n.restoreThisBackup2),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupMetric extends StatelessWidget {
  const _BackupMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HkSpacing.xs,
        vertical: HkSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, HkColors.green, 0.08),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: HkColors.green.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Symbols.check_circle_rounded,
            size: 16,
            color: HkColors.green,
          ),
          const SizedBox(width: HkSpacing.space4),
          Text(
            '$label $value',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: HkColors.green,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _backupStatusLabel(BuildContext context, BackupStatus? status) {
  if (status == null) {
    return context.l10n.noBackup;
  }
  return status.successful ? context.l10n.available : context.l10n.failed;
}

IconData _backupStatusIcon(BackupStatus? status) {
  if (status == null) {
    return Symbols.history_rounded;
  }
  return status.successful
      ? Symbols.verified_user_rounded
      : Symbols.error_rounded;
}

IconData _backupStatusPillIcon(BackupStatus? status) {
  if (status == null) {
    return Symbols.history_rounded;
  }
  return status.successful
      ? Symbols.check_circle_rounded
      : Symbols.error_rounded;
}

Color _backupStatusColor(BuildContext context, BackupStatus? status) {
  if (status == null) {
    return Theme.of(context).colorScheme.outline;
  }
  return status.successful
      ? HkColors.green
      : Theme.of(context).colorScheme.error;
}

Color _backupTintedSurface(BuildContext context, Color tint, double alpha) {
  final scheme = Theme.of(context).colorScheme;
  return Color.alphaBlend(
    tint.withValues(alpha: alpha),
    scheme.surfaceContainerLowest,
  );
}

String _formatDate(BuildContext context, DateTime value) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(value.toLocal());
}

String _formatBytes(BuildContext context, int bytes) {
  final number = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toLanguageTag(),
  );
  if (bytes < 1024) {
    return '${number.format(bytes)} B';
  }
  if (bytes < 1024 * 1024) {
    return '${number.format(bytes / 1024)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${number.format(bytes / (1024 * 1024))} MB';
  }
  return '${number.format(bytes / (1024 * 1024 * 1024))} GB';
}

String _localizedBackupDetail(BuildContext context, String value) {
  return switch (value) {
    'Tasks and due dates' => context.l10n.backupIncludedTasks,
    'Items, rooms, areas, categories, tags, and photos' =>
      context.l10n.backupIncludedItems,
    'Task history, timeline, streaks, and statistics source data' =>
      context.l10n.backupIncludedHistory,
    'Notification preferences, inbox history, and snooze defaults' =>
      context.l10n.backupIncludedNotifications,
    'Theme, profile, weather location, and app settings' =>
      context.l10n.backupIncludedSettings,
    'Android scheduled alarm handles are recreated from restored tasks and settings' =>
      context.l10n.backupExcludedAlarms,
    _ => context.l10n.backupGenericWarning,
  };
}

String _localizedBackupWarning(BuildContext context, String value) {
  return switch (value) {
    'This is an older backup format. HomePilot will migrate it during restore.' =>
      context.l10n.backupOlderFormatWarning,
    'Profile settings could not be previewed.' =>
      context.l10n.backupProfilePreviewWarning,
    _ => context.l10n.backupGenericWarning,
  };
}

Future<void> addPhotoToAsset(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 82,
    maxWidth: 1800,
  );
  if (image == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  try {
    await ref.read(assetRepositoryProvider).addPhoto(asset.id, image.path);
    if (!context.mounted) {
      return;
    }
    hk_ui.showToast(context, content: Text(context.l10n.photoSaved));
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.photoSave),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
}

enum _SnoozePreset { thirtyMinutes, oneHour, threeHours, tomorrow, custom }

Future<void> snoozeTaskWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  if (!task.plan.isEnabled) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.enableThisTaskBeforeSnoozingIt),
      severity: hk_ui.HkToastSeverity.error,
    );
    return;
  }
  final preferences =
      ref.read(notificationPreferencesProvider).value ??
      await ref.read(settingsRepositoryProvider).notificationPreferences();
  if (!context.mounted) {
    return;
  }
  final preset = await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<_SnoozePreset>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.snooze_rounded),
              title: Text(context.l10n.snoozeTask(task.plan.title)),
              subtitle: Text(context.l10n.snoozeReminderDescription),
            ),
            ListTile(
              leading: const Icon(Symbols.timer_rounded),
              title: Text(context.l10n.message30Minutes),
              onTap: () =>
                  Navigator.of(context).pop(_SnoozePreset.thirtyMinutes),
            ),
            ListTile(
              leading: const Icon(Symbols.schedule_rounded),
              title: Text(context.l10n.message1Hour),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.oneHour),
            ),
            ListTile(
              leading: const Icon(Symbols.more_time_rounded),
              title: Text(context.l10n.message3Hours),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.threeHours),
            ),
            ListTile(
              leading: const Icon(Symbols.today_rounded),
              title: Text(
                context.l10n.tomorrowAtTime(
                  _hourLabel(context, preferences.reminderHour),
                ),
              ),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.tomorrow),
            ),
            ListTile(
              leading: const Icon(Symbols.edit_calendar_rounded),
              title: Text(context.l10n.customDateAndTime),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.custom),
            ),
          ],
        ),
      ),
    ),
  );
  if (preset == null || !context.mounted) {
    return;
  }
  final duration = await _durationForSnoozePreset(context, preset, preferences);
  if (duration == null || !context.mounted) {
    return;
  }
  await ref
      .read(notificationSchedulerProvider)
      .snoozePlan(task.plan.id, duration);
  if (!context.mounted) {
    return;
  }
  hk_ui.showToast(
    context,
    content: Text(
      context.l10n.taskSnoozedForDuration(
        task.plan.title,
        _durationLabel(context, duration),
      ),
    ),
  );
}

Future<bool> skipTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final reason = await _taskReasonDialog(
    context,
    title: context.l10n.skipThisOccurrence2,
    message: context.l10n.skipCurrentCycleMessage,
    actionLabel: context.l10n.skipOccurrence,
    icon: Symbols.skip_next_rounded,
  );
  if (reason == null || !context.mounted) {
    return false;
  }
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .skipPlanOccurrence(task.plan.id, reason: reason);
    await cancelPlanReminderSchedules(ref, [task.plan.id]);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) {
      return true;
    }
    hk_ui.showToast(
      context,
      content: Text(context.l10n.taskSkippedForThisCycle(task.plan.title)),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
}

Future<bool> postponeTaskWithDialog(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final date = await showDatePicker(
    context: context,
    initialDate: task.plan.nextDueDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );
  if (date == null || !context.mounted) {
    return false;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(task.plan.nextDueDate),
  );
  if (time == null || !context.mounted) {
    return false;
  }
  final nextDueDate = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final reason = await _taskReasonDialog(
    context,
    title: context.l10n.postponeTask,
    message: context.l10n.postponeCurrentCycleMessage,
    actionLabel: context.l10n.postpone,
    icon: Symbols.edit_calendar_rounded,
  );
  if (reason == null || !context.mounted) {
    return false;
  }
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .postponePlan(task.plan.id, nextDueDate, reason: reason);
    await cancelPlanReminderSchedules(ref, [task.plan.id]);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) {
      return true;
    }
    hk_ui.showToast(
      context,
      content: Text(
        context.l10n.taskPostponedUntil(
          task.plan.title,
          DateFormat.yMMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).add_jm().format(nextDueDate),
        ),
      ),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
}

Future<String?> _taskReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required IconData icon,
}) async {
  final controller = TextEditingController();
  try {
    return await runWithNativeAdsSuspended(
      context,
      () => showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(icon),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: HkSpacing.sm),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.reason,
                  hintText: context.l10n.optional,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<Duration?> _durationForSnoozePreset(
  BuildContext context,
  _SnoozePreset preset,
  NotificationPreferences preferences,
) async {
  final now = DateTime.now();
  switch (preset) {
    case _SnoozePreset.thirtyMinutes:
      return const Duration(minutes: 30);
    case _SnoozePreset.oneHour:
      return const Duration(hours: 1);
    case _SnoozePreset.threeHours:
      return const Duration(hours: 3);
    case _SnoozePreset.tomorrow:
      return DateTime(
        now.year,
        now.month,
        now.day + 1,
        preferences.reminderHour,
      ).difference(now);
    case _SnoozePreset.custom:
      final date = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(hours: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 30)),
      );
      if (date == null || !context.mounted) {
        return null;
      }
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );
      if (time == null) {
        return null;
      }
      final scheduled = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      return scheduled.isAfter(now)
          ? scheduled.difference(now)
          : const Duration(minutes: 5);
  }
}

String _durationLabel(BuildContext context, Duration duration) {
  if (duration.inMinutes < 60) {
    return context.l10n.durationMinutesShort(duration.inMinutes);
  }
  if (duration.inHours < 24) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? context.l10n.durationHoursMinutesShort(duration.inHours, 0)
        : context.l10n.durationHoursMinutesShort(duration.inHours, minutes);
  }
  return duration.inDays == 1
      ? context.l10n.durationDay(duration.inDays)
      : context.l10n.durationDays(duration.inDays);
}

Future<void> refreshNotificationSchedules(WidgetRef ref) async {
  try {
    await ref.read(notificationSchedulerProvider).refreshSchedules();
  } catch (_) {
    // Reminder refresh should not block the primary task action.
  }
}

Future<void> cancelPlanReminderSchedules(
  WidgetRef ref,
  Iterable<String> planIds,
) async {
  final uniqueIds = planIds.toSet();
  if (uniqueIds.isEmpty) {
    return;
  }
  try {
    final scheduler = ref.read(notificationSchedulerProvider);
    for (final planId in uniqueIds) {
      await scheduler.cancelPlanReminders(planId);
    }
  } catch (_) {
    // Stale OS notifications are undesirable, but should not block data changes.
  }
}

Future<bool> setTaskEnabledWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
  bool enabled,
) async {
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .setTaskEnabled(task.plan.id, enabled);
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          enabled
              ? _failureMessage(
                  context,
                  error,
                  fallback: AppFailureCode.taskUpdate,
                )
              : _failureMessage(
                  context,
                  error,
                  fallback: AppFailureCode.taskUpdate,
                ),
        ),
        severity: hk_ui.HkToastSeverity.error,
        bottomOffset: _taskDeletionSnackBarBottomOffset(context),
      );
    }
    return false;
  }

  Object? reminderError;
  try {
    final scheduler = ref.read(notificationSchedulerProvider);
    if (!enabled) {
      await scheduler.cancelPlanReminders(task.plan.id);
    }
    await scheduler.refreshSchedules();
  } catch (error) {
    reminderError = error;
  }

  if (!context.mounted) {
    return true;
  }
  if (reminderError != null) {
    hk_ui.showToast(
      context,
      content: Text(
        _failureMessage(
          context,
          reminderError,
          fallback: AppFailureCode.notificationSetup,
        ),
      ),
      severity: hk_ui.HkToastSeverity.error,
      bottomOffset: _taskDeletionSnackBarBottomOffset(context),
    );
    return true;
  }
  hk_ui.showToast(
    context,
    content: Text(
      enabled
          ? context.l10n.taskEnabledConfirmation
          : context.l10n.taskDisabledConfirmation,
    ),
    bottomOffset: _taskDeletionSnackBarBottomOffset(context),
  );
  return true;
}

enum _TaskActionFeedbackType { created, completed, deleted }

void _showTaskActionFeedback(
  BuildContext context,
  _TaskActionFeedbackType type, {
  String? label,
}) {
  unawaited(_playTaskActionFeedback(type));
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return;
  }
  var removed = false;
  late final OverlayEntry entry;
  void removeEntry() {
    if (removed) {
      return;
    }
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _TaskActionBurstOverlay(
      type: type,
      label: label ?? _taskActionFeedbackLabel(context, type),
      onDone: removeEntry,
    ),
  );
  overlay.insert(entry);
}

Future<void> _playTaskActionFeedback(_TaskActionFeedbackType type) async {
  switch (type) {
    case _TaskActionFeedbackType.completed:
      await hkActionFeedbackService.playCompleted();
    case _TaskActionFeedbackType.created:
      await hkActionFeedbackService.playCreated();
    case _TaskActionFeedbackType.deleted:
      await hkActionFeedbackService.playDeleted();
  }
}

String _taskActionFeedbackLabel(
  BuildContext context,
  _TaskActionFeedbackType type,
) {
  return switch (type) {
    _TaskActionFeedbackType.created => context.l10n.taskAdded,
    _TaskActionFeedbackType.completed => context.l10n.taskDone,
    _TaskActionFeedbackType.deleted => context.l10n.taskDeleted,
  };
}

class _TaskActionBurstOverlay extends StatefulWidget {
  const _TaskActionBurstOverlay({
    required this.type,
    required this.label,
    required this.onDone,
  });

  final _TaskActionFeedbackType type;
  final String label;
  final VoidCallback onDone;

  @override
  State<_TaskActionBurstOverlay> createState() =>
      _TaskActionBurstOverlayState();
}

class _TaskActionBurstOverlayState extends State<_TaskActionBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1180),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.onDone();
          }
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _TaskActionFeedbackStyle.from(context, widget.type);
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            final intro = Curves.easeOutBack.transform(
              (progress / 0.36).clamp(0.0, 1.0),
            );
            final fadeOut = progress < 0.76
                ? 1.0
                : (1 - ((progress - 0.76) / 0.24)).clamp(0.0, 1.0);
            final slide = Curves.easeOutCubic.transform(
              progress.clamp(0.0, 1.0),
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TaskActionBurstPainter(
                      progress: progress,
                      accent: style.accent,
                      secondary: style.secondary,
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Transform.translate(
                      offset: Offset(0, 50 - (18 * slide)),
                      child: Opacity(
                        opacity: fadeOut,
                        child: Transform.scale(
                          scale: 0.82 + (0.18 * intro),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                style.accent.withValues(alpha: 0.07),
                                scheme.surfaceContainerLowest,
                              ).withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(HkRadii.full),
                              border: Border.all(
                                color: style.accent.withValues(alpha: 0.24),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: style.accent.withValues(alpha: 0.22),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: HkSpacing.md,
                                vertical: HkSpacing.sm,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: style.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      style.icon,
                                      color: style.onAccent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: HkSpacing.xs),
                                  Text(
                                    widget.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskActionFeedbackStyle {
  const _TaskActionFeedbackStyle({
    required this.icon,
    required this.accent,
    required this.secondary,
    required this.onAccent,
  });

  final IconData icon;
  final Color accent;
  final Color secondary;
  final Color onAccent;

  factory _TaskActionFeedbackStyle.from(
    BuildContext context,
    _TaskActionFeedbackType type,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (type) {
      _TaskActionFeedbackType.created => _TaskActionFeedbackStyle(
        icon: Symbols.add_task_rounded,
        accent: scheme.primary,
        secondary: HkColors.appInfo,
        onAccent: scheme.onPrimary,
      ),
      _TaskActionFeedbackType.completed => _TaskActionFeedbackStyle(
        icon: Symbols.check_circle_rounded,
        accent: HkColors.green,
        secondary: scheme.primary,
        onAccent: Colors.white,
      ),
      _TaskActionFeedbackType.deleted => _TaskActionFeedbackStyle(
        icon: Symbols.delete_rounded,
        accent: scheme.error,
        secondary: HkColors.appWarning,
        onAccent: scheme.onError,
      ),
    };
  }
}

class _TaskActionBurstPainter extends CustomPainter {
  const _TaskActionBurstPainter({
    required this.progress,
    required this.accent,
    required this.secondary,
  });

  final double progress;
  final Color accent;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 92);
    final outward = Curves.easeOutCubic.transform(
      (progress / 0.72).clamp(0.0, 1.0),
    );
    final fade = progress < 0.72
        ? 1.0
        : (1 - ((progress - 0.72) / 0.28)).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < 18; index += 1) {
      final angle = (-math.pi * 0.88) + (index * math.pi * 1.76 / 17);
      final stagger = 0.76 + ((index % 4) * 0.08);
      final radius = (18 + (72 * outward)) * stagger;
      final particleCenter =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final particleSize = 3.5 + ((index % 3) * 1.8);
      paint.color = (index.isEven ? accent : secondary).withValues(
        alpha: (0.78 * fade).clamp(0.0, 1.0),
      );
      if (index % 5 == 0) {
        canvas.save();
        canvas.translate(particleCenter.dx, particleCenter.dy);
        canvas.rotate(angle + (progress * math.pi));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particleSize * 2.2,
              height: particleSize,
            ),
            Radius.circular(particleSize / 2),
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(particleCenter, particleSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TaskActionBurstPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        accent != oldDelegate.accent ||
        secondary != oldDelegate.secondary;
  }
}

Future<List<String>> _planIdsForAssets(
  WidgetRef ref,
  Iterable<String> assetIds,
) async {
  final maintenance = ref.read(maintenanceRepositoryProvider);
  final planIds = <String>{};
  for (final assetId in assetIds.toSet()) {
    final tasks = await maintenance.listTasksForAsset(assetId);
    planIds.addAll(tasks.map((task) => task.plan.id));
  }
  return planIds.toList();
}

Future<bool> completeTaskWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task, {
  bool collectNotes = false,
}) async {
  final controllerNotifier = ref.read(
    taskCompletionControllerProvider(task.plan.id),
  );
  if (collectNotes) {
    if (!controllerNotifier.tryBeginNotesCollection()) {
      return false;
    }
  }

  final dueTodayBefore = getTaskBuckets(
    ref.read(tasksProvider).value ?? const <TaskItem>[],
    DateTime.now(),
  ).today;
  final completesFinalDueToday =
      dueTodayBefore.length == 1 &&
      dueTodayBefore.single.plan.id == task.plan.id;
  String? notes;
  if (collectNotes) {
    notes = await _showEditorModal<String>(
      context,
      builder: (context) => CompleteTaskDialog(task: task),
    );
    if (notes == null) {
      controllerNotifier.cancelNotesCollection();
      return false;
    }
    if (!context.mounted) {
      return false;
    }
  }
  final previousDueDate = task.plan.nextDueDate;
  final result = await controllerNotifier.complete(
    completedAt: DateTime.now(),
    notes: notes,
    expectedNextDueDate: previousDueDate,
  );

  if (!context.mounted) {
    return result.isApplied;
  }
  if (!result.isApplied) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.thisTaskWasAlreadyUpdated),
      severity: hk_ui.HkToastSeverity.error,
    );
    return false;
  }
  try {
    await ref.read(streakServiceProvider).refresh(DateTime.now());
  } catch (_) {}
  if (!context.mounted) {
    return true;
  }
  _showTaskActionFeedback(context, _TaskActionFeedbackType.completed);
  if (!_prefersReducedMotion(context)) {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }
  if (!context.mounted) {
    return true;
  }
  hk_ui.showUndoToast(
    context,
    content: Text(context.l10n.taskCompleted),
    onUndo: () async {
      try {
        await ref
            .read(maintenanceRepositoryProvider)
            .undoLastCompletion(task.plan.id, previousDueDate);
        try {
          await ref.read(streakServiceProvider).refresh(DateTime.now());
          await refreshNotificationSchedules(ref);
        } catch (_) {}
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.completionUndone),
          );
        }
      } catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  if (completesFinalDueToday) {
    try {
      await _offerDailyCompletionReward(context, ref);
    } catch (_) {}
  } else if (context.mounted) {
    final config =
        ref.read(monetizationConfigProvider).value ??
        const MonetizationConfig.failClosed();
    await ref
        .read(completionAdCoordinatorProvider)
        .onTaskCompleted(
          config: config,
          keyboardVisible: MediaQuery.viewInsetsOf(context).bottom > 0,
          modalActive: false,
        );
  }
  return true;
}

Future<void> _offerDailyCompletionReward(
  BuildContext context,
  WidgetRef ref,
) async {
  final config =
      ref.read(monetizationConfigProvider).value ??
      const MonetizationConfig.failClosed();
  final wallet = ref.read(pointWalletProvider).value;
  if (!config.adsEnabled ||
      !config.rewardedInterstitialEnabled ||
      (wallet?.balance ?? config.walletCap) + 2 > config.walletCap) {
    return;
  }
  final accepted = await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          HkSpacing.gutter,
          0,
          HkSpacing.gutter,
          HkSpacing.gutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.celebration_rounded, size: 44),
            const SizedBox(height: HkSpacing.sm),
            Text(
              context.l10n.todayCareComplete,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: HkSpacing.xs),
            Text(
              context.l10n.optionalDailyRewardDescription,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HkSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(context.l10n.notNow),
                  ),
                ),
                const SizedBox(width: HkSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Symbols.play_circle_rounded),
                    label: Text(context.l10n.earnTwoPoints),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (accepted != true || !context.mounted) return;
  final result = await ref
      .read(homePilotAdsProvider)
      .showReward(
        RewardAdType.rewardedInterstitial,
        timeZone: wallet?.timeZone,
        entryPoint: 'today_complete_milestone',
      );
  if (!context.mounted) return;
  final message = switch (result) {
    RewardShowResult.shownAwaitingServerVerification =>
      context.l10n.rewardWatchedVerifyingTwo,
    RewardShowResult.unavailable => context.l10n.noRewardAvailable,
    RewardShowResult.rejected => context.l10n.dailyRewardAlreadyClaimed,
    RewardShowResult.dismissed => context.l10n.rewardAdClosedEarly,
  };
  hk_ui.showToast(context, content: Text(message));
}

Future<void> showPointsWalletSheet(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(monetizationRepositoryProvider);
  final transactions = repository?.listTransactions();
  await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final wallet = ref.watch(pointWalletProvider).value;
          final config =
              ref.watch(monetizationConfigProvider).value ??
              const MonetizationConfig.failClosed();
          final pendingClaims =
              ref.watch(pendingRewardClaimsProvider).value ?? const [];
          return FractionallySizedBox(
            heightFactor: 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.gutter,
                0,
                HkSpacing.gutter,
                HkSpacing.gutter,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Symbols.stars_rounded, size: 30),
                      const SizedBox(width: HkSpacing.sm),
                      Expanded(
                        child: Text(
                          context.l10n.pointsWallet,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      Text(
                        '${wallet?.balance ?? 0} / ${config.walletCap}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: HkSpacing.sm),
                  if (pendingClaims.isNotEmpty) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(HkRadii.md),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(HkSpacing.sm),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: HkSpacing.sm),
                            Expanded(
                              child: Text(
                                context.l10n.rewardVerificationPending,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: HkSpacing.sm),
                  ],
                  FilledButton.icon(
                    onPressed:
                        (wallet?.balance ?? config.walletCap) >=
                            config.walletCap
                        ? null
                        : () async {
                            await showEarnPointsFlow(
                              context,
                              ref,
                              entryPoint: 'wallet',
                            );
                          },
                    icon: const Icon(Symbols.play_circle_rounded),
                    label: Text(context.l10n.earnFreePoints),
                  ),
                  const SizedBox(height: HkSpacing.sm),
                  Text(
                    context.l10n.pointsRuleExplanation,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: HkSpacing.md),
                  Text(
                    context.l10n.recentActivity,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: HkSpacing.xs),
                  Expanded(
                    child: transactions == null
                        ? Center(child: Text(context.l10n.activityUnavailable))
                        : FutureBuilder<List<Map<String, dynamic>>>(
                            future: transactions,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              final rows = snapshot.data!;
                              if (rows.isEmpty) {
                                return Center(
                                  child: Text(context.l10n.noPointActivity),
                                );
                              }
                              return ListView.builder(
                                itemCount: rows.length,
                                itemBuilder: (context, index) {
                                  final row = rows[index];
                                  final amount = row['amount'] as int? ?? 0;
                                  final created = DateTime.tryParse(
                                    row['created_at'] as String? ?? '',
                                  )?.toLocal();
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      child: Icon(
                                        amount > 0
                                            ? Symbols.add_rounded
                                            : Symbols.remove_rounded,
                                      ),
                                    ),
                                    title: Text(
                                      _pointTransactionLabel(
                                        context,
                                        row['transaction_type'] as String? ??
                                            '',
                                      ),
                                    ),
                                    subtitle: created == null
                                        ? null
                                        : Text(
                                            DateFormat.yMMMd().add_jm().format(
                                              created,
                                            ),
                                          ),
                                    trailing: Text(
                                      '${amount > 0 ? '+' : ''}$amount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: amount > 0
                                                ? HkColors.green
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

String _pointTransactionLabel(BuildContext context, String type) =>
    switch (type) {
      'initial_grant' => context.l10n.startingPoints,
      'task_creation' => context.l10n.taskCreatedPointTransaction,
      'asset_creation' => context.l10n.itemCreatedPointTransaction,
      'rewarded_ad' => context.l10n.rewardedAdPointTransaction,
      'rewarded_interstitial' => context.l10n.dailyCompletionReward,
      'refund' => context.l10n.refundPointTransaction,
      _ => context.l10n.pointAdjustment,
    };

Future<void> showEarnPointsFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entryPoint,
}) => runWithNativeAdsSuspended(
  context,
  () => _showEarnPointsFlow(context, ref, entryPoint: entryPoint),
);

Future<void> _showEarnPointsFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entryPoint,
}) async {
  final config =
      ref.read(monetizationConfigProvider).value ??
      const MonetizationConfig.failClosed();
  final wallet = ref.read(pointWalletProvider).value;
  if (!config.adsEnabled || !config.rewardedAdsEnabled) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.pointRewardsUnavailable),
    );
    return;
  }
  if ((wallet?.balance ?? config.walletCap) >= config.walletCap) {
    hk_ui.showToast(context, content: Text(context.l10n.walletAlreadyFull));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.earnOnePoint),
      content: Text(context.l10n.earnOnePointDescription),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Symbols.play_circle_rounded),
          label: Text(context.l10n.watchAd),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  hk_ui.showToast(context, content: Text(context.l10n.loadingRewardedAd));
  final result = await ref
      .read(homePilotAdsProvider)
      .showReward(
        RewardAdType.rewardedAd,
        timeZone: wallet?.timeZone,
        entryPoint: entryPoint,
      );
  if (!context.mounted) return;
  switch (result) {
    case RewardShowResult.shownAwaitingServerVerification:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.adWatchedVerifyingPoint),
      );
    case RewardShowResult.unavailable:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.noRewardedAdAvailable),
      );
    case RewardShowResult.rejected:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.rewardUnavailableOrClaimed),
      );
    case RewardShowResult.dismissed:
      hk_ui.showToast(context, content: Text(context.l10n.rewardAdClosedEarly));
  }
}

Future<void> showPointShortageDialog(
  BuildContext context,
  WidgetRef ref, {
  required String attemptedAction,
}) async {
  unawaited(
    ref.read(monetizationRepositoryProvider)?.recordEvent(
      'point_shortage_encountered',
      {'attempted_action': attemptedAction},
    ),
  );
  final earn = await runWithNativeAdsSuspended(
    context,
    () => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.needOnePoint),
        content: Text(context.l10n.pointShortageDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.earnAPoint),
          ),
        ],
      ),
    ),
  );
  if (earn == true && context.mounted) {
    await showEarnPointsFlow(context, ref, entryPoint: 'shortage');
  }
}

bool _isInsufficientPointsError(Object error) {
  if (error case PostgrestException(:final message)) {
    return message == 'INSUFFICIENT_POINTS';
  }
  return error.toString().contains('INSUFFICIENT_POINTS');
}

Future<bool> confirmPermanentDelete(
  BuildContext context, {
  required String title,
  required String message,
  String? actionLabel,
}) async {
  final confirmed = await runWithNativeAdsSuspended(
    context,
    () => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Symbols.delete_rounded),
            label: Text(actionLabel ?? context.l10n.delete),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

Future<bool> deleteTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveTaskToTrash2,
    message: context.l10n.moveTaskToTrashMessage(task.plan.title),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  return moveTaskToTrashWithUndo(context, ref, task);
}

Future<bool> moveTaskToTrashWithUndo(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  try {
    await ref.read(maintenanceRepositoryProvider).archivePlan(task.plan.id);
  } on Object catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
  try {
    await cancelPlanReminderSchedules(ref, [task.plan.id]);
    await refreshNotificationSchedules(ref);
  } on Object catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(
            context,
            error,
            fallback: AppFailureCode.notificationSetup,
          ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
  if (!context.mounted) {
    return true;
  }
  hk_ui.showTaskMovedToTrashSnackBar(
    context,
    duration: const Duration(seconds: 5),
    bottomOffset: _taskDeletionSnackBarBottomOffset(context),
    reserveFloatingActionButton: _routeShowsTaskFab(_routePathOf(context)),
    onUndo: () async {
      try {
        await ref.read(maintenanceRepositoryProvider).restorePlan(task.plan.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(context, content: Text(context.l10n.taskRestored));
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}

double _taskDeletionSnackBarBottomOffset(BuildContext context) {
  final path = _routePathOf(context);
  var bottomChromeHeight = 0.0;
  if (_routeShowsShellBottomNav(path)) {
    bottomChromeHeight = math.max(
      bottomChromeHeight,
      hk_ui.kHomePilotBottomNavVisualHeight,
    );
  }
  if (_routeShowsTaskFab(path)) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 560) {
      bottomChromeHeight = math.max(
        bottomChromeHeight,
        hk_ui.kHomePilotFloatingActionButtonClearance,
      );
    }
  }
  if (_routeShowsTaskDetailActionBar(path)) {
    bottomChromeHeight = math.max(
      bottomChromeHeight,
      hk_ui.kHomePilotBottomActionBarHeight,
    );
  }
  return MediaQuery.viewPaddingOf(context).bottom +
      bottomChromeHeight +
      hk_ui.kHomePilotSnackBarBottomSpacing;
}

String? _routePathOf(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.path;
  } on Object {
    try {
      return GoRouter.of(context).routeInformationProvider.value.uri.path;
    } on Object {
      return null;
    }
  }
}

bool _routeShowsShellBottomNav(String? path) {
  return const {
    '/',
    '/assets',
    '/maintenance',
    '/calendar',
    '/more',
  }.contains(path);
}

bool _routeShowsTaskFab(String? path) {
  return path == '/' || path == '/maintenance';
}

bool _routeShowsTaskDetailActionBar(String? path) {
  return path?.startsWith('/maintenance/') ?? false;
}

Future<bool> deleteThingWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveItemToTrash2,
    message: context.l10n.moveItemToTrashMessage(asset.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final planIds = await _planIdsForAssets(ref, [asset.id]);
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashAsset(asset.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(asset.name)),
    bottomOffset: _taskDeletionSnackBarBottomOffset(context),
    reserveFloatingActionButton: _routeShowsTaskFab(_routePathOf(context)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreAsset(asset.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(asset.name)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}

Future<bool> deleteRoomWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Room room,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveRoomToTrash2,
    message: context.l10n.moveRoomToTrashMessage(room.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final assets = await ref
      .read(assetRepositoryProvider)
      .listAssets(roomId: room.id);
  final planIds = await _planIdsForAssets(ref, assets.map((asset) => asset.id));
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashRoom(room.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(room.name)),
    bottomOffset: _taskDeletionSnackBarBottomOffset(context),
    reserveFloatingActionButton: _routeShowsTaskFab(_routePathOf(context)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreRoom(room.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(room.name)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}

Future<bool> deleteAreaWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Area area,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveAreaToTrash2,
    message: context.l10n.moveAreaToTrashMessage(area.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final rooms = await ref
      .read(assetRepositoryProvider)
      .listRooms(areaId: area.id);
  final assetIds = <String>[];
  for (final room in rooms) {
    final assets = await ref
        .read(assetRepositoryProvider)
        .listAssets(roomId: room.id);
    assetIds.addAll(assets.map((asset) => asset.id));
  }
  final planIds = await _planIdsForAssets(ref, assetIds);
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashArea(area.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(area.name)),
    bottomOffset: _taskDeletionSnackBarBottomOffset(context),
    reserveFloatingActionButton: _routeShowsTaskFab(_routePathOf(context)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreArea(area.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(area.name)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}

class CompleteTaskDialog extends StatefulWidget {
  const CompleteTaskDialog({required this.task, super.key});

  final TaskItem task;

  @override
  State<CompleteTaskDialog> createState() => _CompleteTaskDialogState();
}

class _CompleteTaskDialogState extends State<CompleteTaskDialog> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EditorSheetFrame(
      title: context.l10n.completeTaskTitleCase,
      saveLabel: context.l10n.completeAction,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => Navigator.of(context).pop(_notesController.text),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hk_ui.PremiumCard(
            padding: const EdgeInsets.all(14),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              '${widget.task.plan.title} - ${widget.task.asset.name}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: HkSpacing.sm),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.l10n.completionNotes,
              hintText:
                  context.l10n.whatChangedWhatWasReplacedOrWhatNeedsFollowUp,
            ),
          ),
        ],
      ),
    );
  }
}

Future<T?> _showEditorModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return SizedBox(
          key: const ValueKey('editor-modal-hit-surface'),
          height: MediaQuery.sizeOf(sheetContext).height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboardInset,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: builder(sheetContext),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _EditorSheetFrame extends StatelessWidget {
  const _EditorSheetFrame({
    required this.title,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
    required this.child,
    this.saveEnabled = true,
    this.secondarySaveLabel,
    this.onSecondarySave,
  });

  final String title;
  final String saveLabel;
  final bool saveEnabled;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String? secondarySaveLabel;
  final VoidCallback? onSecondarySave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(HkRadii.xxl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: HkSpacing.xs),
            Center(
              child: Container(
                key: const ValueKey('editor-sheet-drag-handle'),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(HkRadii.full),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.md,
                HkSpacing.xs,
                HkSpacing.xs,
                HkSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: onCancel,
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.md,
                  0,
                  HkSpacing.md,
                  HkSpacing.md,
                ),
                child: child,
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.md,
                  HkSpacing.xs,
                  HkSpacing.md,
                  HkSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (secondarySaveLabel != null &&
                        onSecondarySave != null) ...[
                      OutlinedButton(
                        onPressed: saveEnabled ? onSecondarySave : null,
                        child: Text(secondarySaveLabel!),
                      ),
                      const SizedBox(height: HkSpacing.xs),
                    ],
                    FilledButton(
                      onPressed: saveEnabled ? onSave : null,
                      child: Text(saveLabel),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MoveCopyItemDialog extends ConsumerStatefulWidget {
  const MoveCopyItemDialog({required this.asset, super.key});

  final Asset asset;

  @override
  ConsumerState<MoveCopyItemDialog> createState() => _MoveCopyItemDialogState();
}

class _MoveCopyItemDialogState extends ConsumerState<MoveCopyItemDialog> {
  static const _uuid = Uuid();
  String? _roomId;
  bool _copy = false;
  bool _includeTasks = true;
  bool _includePhotos = false;
  bool _saving = false;
  String? _copyOperationId;
  String? _copiedAssetId;
  final Map<String, String> _copiedTaskIds = {};

  @override
  void initState() {
    super.initState();
    _roomId = widget.asset.roomId;
    scheduleMicrotask(_restoreOfflineDraft);
  }

  String get _offlineDraftKey {
    final userId = ref.read(monetizationRepositoryProvider)?.currentUserId;
    return 'asset_copy_${userId ?? 'local'}_${widget.asset.id}';
  }

  Future<void> _saveOfflineDraft() {
    return ref.read(offlineCreationDraftStoreProvider).save(_offlineDraftKey, {
      'room_id': _roomId,
      'copy': _copy,
      'include_tasks': _includeTasks,
      'include_photos': _includePhotos,
      'operation_id': _copyOperationId ??= _uuid.v7(),
      'asset_id': _copiedAssetId ??= _uuid.v7(),
      'task_ids': _copiedTaskIds,
    });
  }

  Future<void> _restoreOfflineDraft() async {
    final draft = await ref
        .read(offlineCreationDraftStoreProvider)
        .load(_offlineDraftKey);
    if (!mounted || draft == null) return;
    final taskIds = draft['task_ids'];
    setState(() {
      _roomId = draft['room_id'] as String? ?? widget.asset.roomId;
      _copy = draft['copy'] as bool? ?? false;
      _includeTasks = draft['include_tasks'] as bool? ?? true;
      _includePhotos = draft['include_photos'] as bool? ?? false;
      _copyOperationId = draft['operation_id'] as String?;
      _copiedAssetId = draft['asset_id'] as String?;
      _copiedTaskIds
        ..clear()
        ..addAll(
          taskIds is Map
              ? taskIds.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                )
              : const {},
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsProvider);
    return _EditorSheetFrame(
      title: context.l10n.moveOrCopyItem,
      saveLabel: _saving
          ? context.l10n.saving
          : _copy
          ? context.l10n.copyItem
          : context.l10n.moveItem,
      saveEnabled: !_saving,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: rooms.when(
        data: (items) {
          final activeRooms = items
              .where((room) => room.archivedAt == null)
              .toList(growable: false);
          final selectedRoomId = activeRooms.any((room) => room.id == _roomId)
              ? _roomId
              : activeRooms.firstOrNull?.id;
          if (activeRooms.isEmpty) {
            return hk_ui.PremiumEmptyState(
              icon: Symbols.meeting_room_rounded,
              title: context.l10n.createARoomFirst,
              body: context.l10n.itemsNeedARoomToMoveOrCopy,
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              hk_ui.PremiumCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(_iconForAssetType(widget.asset.assetType)),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      child: DynamicText(
                        widget.asset.name,
                        contentType: 'asset.name',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HkSpacing.sm),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Symbols.drive_file_move_rounded),
                    label: Text(context.l10n.move),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Symbols.content_copy_rounded),
                    label: Text(context.l10n.copy),
                  ),
                ],
                selected: {_copy},
                onSelectionChanged: (values) =>
                    setState(() => _copy = values.single),
              ),
              const SizedBox(height: HkSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: selectedRoomId,
                decoration: InputDecoration(labelText: context.l10n.room),
                items: [
                  for (final room in activeRooms)
                    DropdownMenuItem(
                      value: room.id,
                      child: DynamicText(room.name, contentType: 'room.name'),
                    ),
                ],
                onChanged: (value) => setState(() => _roomId = value),
              ),
              if (_copy) ...[
                const SizedBox(height: HkSpacing.xs),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeTasks,
                  onChanged: (value) =>
                      setState(() => _includeTasks = value ?? true),
                  title: Text(context.l10n.includeRelatedTasks),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includePhotos,
                  onChanged: (value) =>
                      setState(() => _includePhotos = value ?? false),
                  title: Text(context.l10n.includePhotos),
                ),
              ],
            ],
          );
        },
        error: (error, _) =>
            ErrorPanel(message: _failureMessage(context, error)),
        loading: () => const LinearProgressIndicator(),
      ),
    );
  }

  Future<void> _save() async {
    final rooms = ref.read(roomsProvider).value ?? const <Room>[];
    final activeRooms = rooms
        .where((room) => room.archivedAt == null)
        .toList(growable: false);
    final roomId = activeRooms.any((room) => room.id == _roomId)
        ? _roomId
        : activeRooms.firstOrNull?.id;
    if (_saving || roomId == null) {
      return;
    }
    if (!_copy && roomId == widget.asset.roomId) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(assetRepositoryProvider);
      if (_copy) {
        final online = await ref
            .read(syncConnectivityInstanceProvider)
            .isOnline();
        if (!online) {
          await _saveOfflineDraft();
          if (mounted) {
            hk_ui.showToast(
              context,
              content: Text(context.l10n.offlineCopyDraftMessage),
            );
          }
          return;
        }
        final copiedAssetId = _copiedAssetId ??= _uuid.v7();
        final sourceTasks = _includeTasks
            ? await ref
                  .read(maintenanceRepositoryProvider)
                  .listTasksForAsset(widget.asset.id)
            : const <TaskItem>[];
        for (final task in sourceTasks) {
          _copiedTaskIds.putIfAbsent(task.plan.id, _uuid.v7);
        }
        final monetization = ref.read(monetizationRepositoryProvider);
        if (monetization == null) {
          throw StateError('Cloud points service is unavailable.');
        }
        final debit = await monetization.createAsset({
          'operation_id': _copyOperationId ??= _uuid.v7(),
          'asset': {
            'id': copiedAssetId,
            'name': widget.asset.name,
            'asset_type': widget.asset.assetType.name,
            'category_id': widget.asset.categoryId,
            'room_id': roomId,
            'placement': widget.asset.placement,
            'notes': widget.asset.notes,
            'purchase_date': widget.asset.purchaseDate
                ?.toUtc()
                .toIso8601String(),
          },
          'details': _assetDetailsPayload(widget.asset),
          'initial_plans': [
            for (final task in sourceTasks)
              {
                'id': _copiedTaskIds[task.plan.id],
                'asset_id': copiedAssetId,
                'title': task.plan.title,
                'instructions': task.plan.instructions,
                'recurrence_interval': task.plan.recurrence.interval,
                'recurrence_unit': task.plan.recurrence.unit.name,
                'priority': task.plan.priority.name,
                'next_due_date': task.plan.nextDueDate
                    .toUtc()
                    .toIso8601String(),
                'reminder_days_before': task.plan.reminderDaysBefore,
                'health_group': task.plan.healthGroup.name,
                'is_enabled': true,
                'metadata': _taskMetadataPayload(task.plan.metadata),
              },
          ],
        });
        await repository.copyAsset(
          assetId: widget.asset.id,
          roomId: roomId,
          includeTasks: _includeTasks,
          includePhotos: _includePhotos,
          newAssetId: copiedAssetId,
          taskIdBySource: _copiedTaskIds,
        );
        await ref
            .read(offlineCreationDraftStoreProvider)
            .clear(_offlineDraftKey);
        if (debit.charged == 1) {
          unawaited(
            monetization.recordEvent('points_debited', {
              'entity_type': 'asset_copy',
              'entity_id': copiedAssetId,
              'cost': debit.charged,
              'new_balance': debit.balance,
              'included_task_count': sourceTasks.length,
            }),
          );
        }
      } else {
        await repository.moveAsset(assetId: widget.asset.id, roomId: roomId);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        if (_isInsufficientPointsError(error)) {
          await showPointShortageDialog(context, ref, attemptedAction: 'asset');
          return;
        }
        hk_ui.showToast(
          context,
          content: Text(_failureMessage(context, error)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

Map<String, dynamic> _assetDetailsPayload(Asset asset) =>
    switch (asset.assetType) {
      AssetType.device => {
        'brand': asset.deviceDetails?.brand,
        'model': asset.deviceDetails?.model,
        'serial_number': asset.deviceDetails?.serialNumber,
        'power_source': asset.deviceDetails?.powerSource?.name,
        'warranty_until': asset.deviceDetails?.warrantyUntil
            ?.toUtc()
            .toIso8601String(),
        'manual_url': asset.deviceDetails?.manualUrl,
        'consumable': asset.deviceDetails?.consumable,
      },
      AssetType.pet => {
        'species': asset.petDetails?.species,
        'breed': asset.petDetails?.breed,
        'birth_date': asset.petDetails?.birthDate?.toUtc().toIso8601String(),
        'microchip_id': asset.petDetails?.microchipId,
        'vet_name': asset.petDetails?.vetName,
        'vet_phone': asset.petDetails?.vetPhone,
        'feeding_notes': asset.petDetails?.feedingNotes,
        'medical_notes': asset.petDetails?.medicalNotes,
      },
      AssetType.plant => {
        'species': asset.plantDetails?.species,
        'sunlight': asset.plantDetails?.sunlight?.name,
        'watering_interval_days': asset.plantDetails?.wateringIntervalDays,
        'pot_size': asset.plantDetails?.potSize,
        'last_repotted_at': asset.plantDetails?.lastRepottedAt
            ?.toUtc()
            .toIso8601String(),
        'toxicity_notes': asset.plantDetails?.toxicityNotes,
      },
      AssetType.safety => {
        'safety_type': asset.safetyDetails?.safetyType,
        'installed_at': asset.safetyDetails?.installedAt
            ?.toUtc()
            .toIso8601String(),
        'expires_at': asset.safetyDetails?.expiresAt?.toUtc().toIso8601String(),
        'battery_type': asset.safetyDetails?.batteryType,
        'test_interval_days': asset.safetyDetails?.testIntervalDays,
      },
      AssetType.general => const <String, dynamic>{},
    };

Map<String, dynamic> _taskMetadataPayload(TaskMetadata? metadata) =>
    metadata == null
    ? const <String, dynamic>{}
    : {
        'task_type': metadata.taskType,
        'location_label': metadata.locationLabel,
        'estimated_duration_minutes': metadata.estimatedDurationMinutes,
        'required_materials': metadata.requiredMaterials,
        'dependency_plan_ids': metadata.dependencyPlanIds,
        'reminder_recommendation': metadata.reminderRecommendation,
        'sort_order': metadata.sortOrder,
      };

String? _nullableEditText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _commaList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Future<void> showAreaEditorSheet(BuildContext context, {Area? area}) {
  return _showEditorModal<void>(
    context,
    builder: (context) => AreaEditorDialog(area: area),
  );
}

Future<void> showRoomEditorSheet(
  BuildContext context, {
  required String areaId,
  Room? room,
}) {
  return _showEditorModal<void>(
    context,
    builder: (context) => RoomEditorDialog(areaId: areaId, room: room),
  );
}

Future<void> showAssetEditorSheet(
  BuildContext context, {
  Asset? asset,
  String? roomId,
}) {
  return _showEditorModal<void>(
    context,
    builder: (context) => AssetEditorDialog(asset: asset, roomId: roomId),
  );
}

Future<void> showMoveCopyItemSheet(BuildContext context, Asset asset) {
  return _showEditorModal<void>(
    context,
    builder: (context) => MoveCopyItemDialog(asset: asset),
  );
}

Future<void> startThingSetupFlow(BuildContext context, WidgetRef ref) async {
  final rooms = ref.read(roomsProvider).value ?? const <Room>[];
  if (rooms.isNotEmpty) {
    return showAssetEditorSheet(context, roomId: rooms.first.id);
  }
  final areas = ref.read(areasProvider).value ?? const <Area>[];
  if (areas.isNotEmpty) {
    return showRoomEditorSheet(context, areaId: areas.first.id);
  }
  return showAreaEditorSheet(context);
}

Future<void> showPlanEditorSheet(
  BuildContext context, {
  TaskItem? task,
  String? assetId,
}) {
  return _showEditorModal<void>(
    context,
    builder: (context) => PlanEditorDialog(task: task, assetId: assetId),
  );
}

class AreaEditorDialog extends ConsumerStatefulWidget {
  const AreaEditorDialog({this.area, super.key});

  final Area? area;

  @override
  ConsumerState<AreaEditorDialog> createState() => _AreaEditorDialogState();
}

class _AreaEditorDialogState extends ConsumerState<AreaEditorDialog> {
  late final TextEditingController _nameController;
  late AreaKind _kind;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.area?.name ?? '');
    _nameController.addListener(_onFormChanged);
    _kind = widget.area?.kind ?? AreaKind.indoor;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return _EditorSheetFrame(
      title: widget.area == null ? context.l10n.addArea : context.l10n.editArea,
      saveLabel: widget.area == null
          ? context.l10n.createArea
          : context.l10n.saveArea,
      saveEnabled: !_saving && _nameController.text.trim().isNotEmpty,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: context.l10n.areaName),
          ),
          const SizedBox(height: HkSpacing.sm),
          DropdownButtonFormField<AreaKind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: context.l10n.areaType),
            items: [
              for (final kind in AreaKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(_areaKindLabel(context, kind)),
                ),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || _nameController.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final editing = widget.area != null;
    AppLogger.info('area_save_started', fields: {'editing': editing});
    try {
      final repository = ref.read(assetRepositoryProvider);
      await repository.saveArea(
        id: widget.area?.id,
        name: _nameController.text,
        kind: _kind,
      );
      final localAreaCount = (await repository.listAreas()).length;
      AppLogger.info(
        'area_save_completed',
        fields: {'editing': editing, 'local_area_count': localAreaCount},
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      AppLogger.warning(
        'area_save_failed',
        error: error,
        fields: {'editing': editing},
      );
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(_failureMessage(context, error)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class RoomEditorDialog extends ConsumerStatefulWidget {
  const RoomEditorDialog({required this.areaId, this.room, super.key});

  final String areaId;
  final Room? room;

  @override
  ConsumerState<RoomEditorDialog> createState() => _RoomEditorDialogState();
}

class _RoomEditorDialogState extends ConsumerState<RoomEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late RoomType _roomType;
  late String _areaId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.room?.name ?? '');
    _nameController.addListener(_onFormChanged);
    _notesController = TextEditingController(text: widget.room?.notes ?? '');
    _roomType = widget.room?.roomType ?? RoomType.other;
    _areaId = widget.room?.areaId ?? widget.areaId;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(areasProvider).value ?? [];
    final selectedArea = areas.where((area) => area.id == _areaId).firstOrNull;
    final areaKind = selectedArea?.kind ?? AreaKind.indoor;
    final isOutdoor = areaKind == AreaKind.outdoor;
    final typeItems = _roomTypesFor(areaKind);
    final selectedType = typeItems.contains(_roomType)
        ? _roomType
        : typeItems.first;
    return _EditorSheetFrame(
      title: widget.room == null
          ? isOutdoor
                ? context.l10n.addZone
                : context.l10n.addRoom
          : isOutdoor
          ? context.l10n.editZone
          : context.l10n.editRoom,
      saveLabel: widget.room == null
          ? isOutdoor
                ? context.l10n.createZone
                : context.l10n.createRoom
          : isOutdoor
          ? context.l10n.saveZone
          : context.l10n.saveRoom,
      saveEnabled: !_saving && _nameController.text.trim().isNotEmpty,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: isOutdoor
                  ? context.l10n.zoneName
                  : context.l10n.roomName,
            ),
          ),
          const SizedBox(height: HkSpacing.sm),
          DropdownButtonFormField<RoomType>(
            initialValue: selectedType,
            decoration: InputDecoration(
              labelText: isOutdoor
                  ? context.l10n.zoneType
                  : context.l10n.roomType,
            ),
            items: [
              for (final type in typeItems)
                DropdownMenuItem(
                  value: type,
                  child: Text(_roomTypeLabel(context, type)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _roomType = value ?? _roomType),
          ),
          const SizedBox(height: HkSpacing.sm),
          if (areas.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: areas.any((area) => area.id == _areaId)
                  ? _areaId
                  : areas.first.id,
              decoration: InputDecoration(labelText: context.l10n.area),
              items: [
                for (final area in areas)
                  DropdownMenuItem(
                    value: area.id,
                    child: DynamicText(area.name, contentType: 'area.name'),
                  ),
              ],
              onChanged: (value) {
                final nextArea = areas
                    .where((area) => area.id == value)
                    .firstOrNull;
                final nextTypes = _roomTypesFor(
                  nextArea?.kind ?? AreaKind.indoor,
                );
                setState(() {
                  _areaId = value ?? _areaId;
                  if (!nextTypes.contains(_roomType)) {
                    _roomType = nextTypes.first;
                  }
                });
              },
            ),
            const SizedBox(height: HkSpacing.sm),
          ],
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(labelText: context.l10n.notes),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || _nameController.text.trim().isEmpty) {
      return;
    }
    final areas = ref.read(areasProvider).value ?? [];
    final areaKind =
        areas.where((area) => area.id == _areaId).firstOrNull?.kind ??
        AreaKind.indoor;
    final allowedTypes = _roomTypesFor(areaKind);
    setState(() => _saving = true);
    try {
      await ref
          .read(assetRepositoryProvider)
          .saveRoom(
            id: widget.room?.id,
            areaId: _areaId,
            name: _nameController.text,
            roomType: allowedTypes.contains(_roomType)
                ? _roomType
                : allowedTypes.first,
            notes: _notesController.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(_failureMessage(context, error)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class AssetEditorDialog extends ConsumerStatefulWidget {
  const AssetEditorDialog({this.asset, this.roomId, super.key});

  final Asset? asset;
  final String? roomId;

  @override
  ConsumerState<AssetEditorDialog> createState() => _AssetEditorDialogState();
}

class _AssetEditorDialogState extends ConsumerState<AssetEditorDialog> {
  static const _uuid = Uuid();
  late final TextEditingController _nameController;
  late final TextEditingController _placementController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _serialController;
  late final TextEditingController _manualController;
  late final TextEditingController _consumableController;
  late final TextEditingController _petSpeciesController;
  late final TextEditingController _petBreedController;
  late final TextEditingController _microchipController;
  late final TextEditingController _vetNameController;
  late final TextEditingController _vetPhoneController;
  late final TextEditingController _feedingController;
  late final TextEditingController _medicalController;
  late final TextEditingController _plantSpeciesController;
  late final TextEditingController _wateringController;
  late final TextEditingController _potSizeController;
  late final TextEditingController _toxicityController;
  late final TextEditingController _safetyTypeController;
  late final TextEditingController _batteryTypeController;
  late final TextEditingController _testIntervalController;
  AssetType _assetType = AssetType.general;
  String _petType = 'Dog';
  String _fishType = 'Goldfish';
  PowerSource _powerSource = PowerSource.mains;
  Sunlight _sunlight = Sunlight.medium;
  DateTime? _purchaseDate;
  DateTime? _warrantyUntil;
  DateTime? _petBirthDate;
  DateTime? _lastRepottedAt;
  DateTime? _installedAt;
  DateTime? _expiresAt;
  String? _areaId;
  String? _categoryId;
  String? _roomId;
  bool _saving = false;
  String? _creationOperationId;
  String? _creationAssetId;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    final device = asset?.deviceDetails;
    final pet = asset?.petDetails;
    final plant = asset?.plantDetails;
    final safety = asset?.safetyDetails;
    _assetType = asset?.assetType ?? AssetType.general;
    _nameController = TextEditingController(text: asset?.name ?? '');
    _nameController.addListener(_onFormChanged);
    _placementController = TextEditingController(text: asset?.placement ?? '');
    _notesController = TextEditingController(text: asset?.notes ?? '');
    _tagsController = TextEditingController();
    _brandController = TextEditingController(text: device?.brand ?? '');
    _modelController = TextEditingController(text: device?.model ?? '');
    _serialController = TextEditingController(text: device?.serialNumber ?? '');
    _manualController = TextEditingController(text: device?.manualUrl ?? '');
    _consumableController = TextEditingController(
      text: device?.consumable ?? '',
    );
    _petSpeciesController = TextEditingController(text: pet?.species ?? '');
    _petBreedController = TextEditingController(text: pet?.breed ?? '');
    _microchipController = TextEditingController(text: pet?.microchipId ?? '');
    _vetNameController = TextEditingController(text: pet?.vetName ?? '');
    _vetPhoneController = TextEditingController(text: pet?.vetPhone ?? '');
    _feedingController = TextEditingController(text: pet?.feedingNotes ?? '');
    _medicalController = TextEditingController(text: pet?.medicalNotes ?? '');
    _plantSpeciesController = TextEditingController(text: plant?.species ?? '');
    _wateringController = TextEditingController(
      text: plant?.wateringIntervalDays?.toString() ?? '',
    );
    _potSizeController = TextEditingController(text: plant?.potSize ?? '');
    _toxicityController = TextEditingController(
      text: plant?.toxicityNotes ?? '',
    );
    _safetyTypeController = TextEditingController(
      text: safety?.safetyType ?? '',
    );
    _batteryTypeController = TextEditingController(
      text: safety?.batteryType ?? '',
    );
    _testIntervalController = TextEditingController(
      text: safety?.testIntervalDays?.toString() ?? '',
    );
    _powerSource = device?.powerSource ?? PowerSource.mains;
    _petType = _petTypeOptions.contains(pet?.species)
        ? pet!.species!
        : (pet?.species?.trim().isNotEmpty ?? false)
        ? 'Other'
        : 'Dog';
    _fishType = _fishTypeOptions.contains(pet?.breed)
        ? pet!.breed!
        : (pet?.breed?.trim().isNotEmpty ?? false)
        ? 'Other'
        : 'Goldfish';
    _sunlight = plant?.sunlight ?? Sunlight.medium;
    _purchaseDate = asset?.purchaseDate;
    _warrantyUntil = device?.warrantyUntil;
    _petBirthDate = pet?.birthDate;
    _lastRepottedAt = plant?.lastRepottedAt;
    _installedAt = safety?.installedAt;
    _expiresAt = safety?.expiresAt;
    _categoryId = asset?.categoryId;
    _roomId = asset?.roomId ?? widget.roomId;
    if (asset != null) {
      scheduleMicrotask(_loadInitialTags);
    } else {
      scheduleMicrotask(_restoreOfflineDraft);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _nameController.dispose();
    _placementController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _manualController.dispose();
    _consumableController.dispose();
    _petSpeciesController.dispose();
    _petBreedController.dispose();
    _microchipController.dispose();
    _vetNameController.dispose();
    _vetPhoneController.dispose();
    _feedingController.dispose();
    _medicalController.dispose();
    _plantSpeciesController.dispose();
    _wateringController.dispose();
    _potSizeController.dispose();
    _toxicityController.dispose();
    _safetyTypeController.dispose();
    _batteryTypeController.dispose();
    _testIntervalController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _loadInitialTags() async {
    final asset = widget.asset;
    if (asset == null) {
      return;
    }
    final tags = await ref.read(assetTagsProvider(asset.id).future);
    if (!mounted || _tagsController.text.trim().isNotEmpty) {
      return;
    }
    _tagsController.text = tags.map((tag) => tag.name).join(', ');
  }

  String get _offlineDraftKey {
    final userId = ref.read(monetizationRepositoryProvider)?.currentUserId;
    return 'asset_${userId ?? 'local'}_${widget.roomId ?? 'any'}';
  }

  Future<void> _saveOfflineDraft() {
    String? date(DateTime? value) => value?.toUtc().toIso8601String();
    return ref.read(offlineCreationDraftStoreProvider).save(_offlineDraftKey, {
      'operation_id': _creationOperationId ??= _uuid.v7(),
      'asset_id': _creationAssetId ??= _uuid.v7(),
      'name': _nameController.text,
      'placement': _placementController.text,
      'notes': _notesController.text,
      'tags': _tagsController.text,
      'asset_type': _assetType.name,
      'power_source': _powerSource.name,
      'pet_type': _petType,
      'fish_type': _fishType,
      'sunlight': _sunlight.name,
      'purchase_date': date(_purchaseDate),
      'warranty_until': date(_warrantyUntil),
      'pet_birth_date': date(_petBirthDate),
      'last_repotted_at': date(_lastRepottedAt),
      'installed_at': date(_installedAt),
      'expires_at': date(_expiresAt),
      'area_id': _areaId,
      'category_id': _categoryId,
      'room_id': _roomId,
      'brand': _brandController.text,
      'model': _modelController.text,
      'serial': _serialController.text,
      'manual': _manualController.text,
      'consumable': _consumableController.text,
      'pet_species': _petSpeciesController.text,
      'pet_breed': _petBreedController.text,
      'microchip': _microchipController.text,
      'vet_name': _vetNameController.text,
      'vet_phone': _vetPhoneController.text,
      'feeding': _feedingController.text,
      'medical': _medicalController.text,
      'plant_species': _plantSpeciesController.text,
      'watering': _wateringController.text,
      'pot_size': _potSizeController.text,
      'toxicity': _toxicityController.text,
      'safety_type': _safetyTypeController.text,
      'battery_type': _batteryTypeController.text,
      'test_interval': _testIntervalController.text,
    });
  }

  Future<void> _restoreOfflineDraft() async {
    final draft = await ref
        .read(offlineCreationDraftStoreProvider)
        .load(_offlineDraftKey);
    if (!mounted || draft == null || _nameController.text.isNotEmpty) return;
    String text(String key) => draft[key] as String? ?? '';
    DateTime? date(String key) => DateTime.tryParse(text(key))?.toLocal();
    _creationOperationId = draft['operation_id'] as String?;
    _creationAssetId = draft['asset_id'] as String?;
    _nameController.text = text('name');
    _placementController.text = text('placement');
    _notesController.text = text('notes');
    _tagsController.text = text('tags');
    _brandController.text = text('brand');
    _modelController.text = text('model');
    _serialController.text = text('serial');
    _manualController.text = text('manual');
    _consumableController.text = text('consumable');
    _petSpeciesController.text = text('pet_species');
    _petBreedController.text = text('pet_breed');
    _microchipController.text = text('microchip');
    _vetNameController.text = text('vet_name');
    _vetPhoneController.text = text('vet_phone');
    _feedingController.text = text('feeding');
    _medicalController.text = text('medical');
    _plantSpeciesController.text = text('plant_species');
    _wateringController.text = text('watering');
    _potSizeController.text = text('pot_size');
    _toxicityController.text = text('toxicity');
    _safetyTypeController.text = text('safety_type');
    _batteryTypeController.text = text('battery_type');
    _testIntervalController.text = text('test_interval');
    setState(() {
      _assetType =
          AssetType.values
              .where((value) => value.name == text('asset_type'))
              .firstOrNull ??
          AssetType.general;
      _powerSource =
          PowerSource.values
              .where((value) => value.name == text('power_source'))
              .firstOrNull ??
          PowerSource.mains;
      _sunlight =
          Sunlight.values
              .where((value) => value.name == text('sunlight'))
              .firstOrNull ??
          Sunlight.medium;
      _petType = text('pet_type').isEmpty ? 'Dog' : text('pet_type');
      _fishType = text('fish_type').isEmpty ? 'Goldfish' : text('fish_type');
      _purchaseDate = date('purchase_date');
      _warrantyUntil = date('warranty_until');
      _petBirthDate = date('pet_birth_date');
      _lastRepottedAt = date('last_repotted_at');
      _installedAt = date('installed_at');
      _expiresAt = date('expires_at');
      _areaId = draft['area_id'] as String?;
      _categoryId = draft['category_id'] as String?;
      _roomId = draft['room_id'] as String? ?? widget.roomId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(areasProvider).value ?? [];
    final categories = ref.watch(categoriesProvider);
    final rooms = ref.watch(roomsProvider);
    final roomItems = rooms.value ?? [];
    final selectedRoom = _roomId == null
        ? null
        : roomItems.where((room) => room.id == _roomId).firstOrNull;
    final selectedAreaId =
        _areaId ?? selectedRoom?.areaId ?? areas.firstOrNull?.id;
    final visibleRooms = selectedAreaId == null
        ? roomItems
        : roomItems.where((room) => room.areaId == selectedAreaId).toList();
    final categoryItems = categories.value ?? const <Category>[];
    final selectedCategoryId =
        _categoryId ??
        _categoryForType(_assetType, categoryItems)?.id ??
        categoryItems.firstOrNull?.id;
    final selectedRoomId = _roomId ?? visibleRooms.firstOrNull?.id;
    final saveEnabled =
        !_saving &&
        _nameController.text.trim().isNotEmpty &&
        selectedCategoryId != null &&
        selectedRoomId != null;
    return _EditorSheetFrame(
      title: widget.asset == null
          ? context.l10n.addItem
          : context.l10n.editItem,
      saveLabel: widget.asset == null
          ? context.l10n.createItem
          : context.l10n.saveItem,
      saveEnabled: saveEnabled,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          hk_ui.PremiumCard(
            padding: const EdgeInsets.all(14),
            backgroundColor: HkColors.appSurfaceGreen,
            child: Row(
              children: [
                Icon(
                  _iconForAssetType(_assetType),
                  color: HkColors.appPrimaryDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.trackItemBody,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HkColors.appPrimaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SubsectionTitle(
            title: context.l10n.basic,
            icon: Symbols.inventory_2_rounded,
          ),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: context.l10n.itemName),
          ),
          const SizedBox(height: 12),
          categories.when(
            data: (items) => DropdownButtonFormField<AssetType>(
              initialValue: _assetType,
              decoration: InputDecoration(labelText: context.l10n.itemType),
              items: [
                for (final type in AssetType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(_assetTypeLabel(context, type)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _changeType(value, items);
                }
              },
            ),
            error: (error, _) => Text(_failureMessage(context, error)),
            loading: () => const LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
          _SubsectionTitle(
            title: context.l10n.location,
            icon: Symbols.location_on_rounded,
          ),
          if (areas.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: selectedAreaId,
              decoration: InputDecoration(labelText: context.l10n.area),
              items: [
                for (final area in areas)
                  DropdownMenuItem(
                    value: area.id,
                    child: DynamicText(area.name, contentType: 'area.name'),
                  ),
              ],
              onChanged: (value) {
                final firstRoom = roomItems
                    .where((room) => room.areaId == value)
                    .firstOrNull;
                setState(() {
                  _areaId = value;
                  _roomId = firstRoom?.id;
                });
              },
            ),
          if (areas.isNotEmpty) const SizedBox(height: 12),
          rooms.when(
            data: (_) {
              final selected =
                  _roomId != null &&
                      visibleRooms.any((item) => item.id == _roomId)
                  ? _roomId
                  : visibleRooms.firstOrNull?.id;
              return DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: context.l10n.roomOrZone),
                items: [
                  for (final item in visibleRooms)
                    DropdownMenuItem(
                      value: item.id,
                      child: DynamicText(item.name, contentType: 'room.name'),
                    ),
                ],
                onChanged: (value) => setState(() => _roomId = value),
              );
            },
            error: (error, _) => Text(_failureMessage(context, error)),
            loading: () => const LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
          _SubsectionTitle(
            title: context.l10n.details,
            icon: Symbols.category_rounded,
          ),
          categories.when(
            data: (items) {
              final selected =
                  _categoryId != null &&
                      items.any((item) => item.id == _categoryId)
                  ? _categoryId
                  : items.firstOrNull?.id;
              return DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: context.l10n.category),
                items: [
                  for (final item in items)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              );
            },
            error: (error, _) => Text(_failureMessage(context, error)),
            loading: () => const LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _placementController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.placement,
              hintText: context.l10n.shelfCornerBalconyKennelArea,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pickDate(_purchaseDate, (value) {
              setState(() => _purchaseDate = value);
            }),
            icon: const Icon(Symbols.event_rounded),
            label: Text(
              _purchaseDate == null
                  ? context.l10n.purchaseDate
                  : context.l10n.purchasedDate(
                      _formatShortDate(context, _purchaseDate!),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(labelText: context.l10n.notes),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              labelText: context.l10n.tags,
              hintText: context.l10n.commaSeparated,
            ),
          ),
          const SizedBox(height: 12),
          _typeSpecificFields(),
        ],
      ),
    );
  }

  Widget _typeSpecificFields() {
    return switch (_assetType) {
      AssetType.device => _deviceFields(),
      AssetType.pet => _petFields(),
      AssetType.plant => _plantFields(),
      AssetType.safety => _safetyFields(),
      AssetType.general => const SizedBox.shrink(),
    };
  }

  Widget _deviceFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.deviceDetails,
          icon: Symbols.memory_rounded,
        ),
        TextField(
          controller: _brandController,
          decoration: InputDecoration(labelText: context.l10n.brand),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelController,
          decoration: InputDecoration(labelText: context.l10n.model),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _serialController,
          decoration: InputDecoration(labelText: context.l10n.serialNumber),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PowerSource>(
          initialValue: _powerSource,
          decoration: InputDecoration(labelText: context.l10n.powerSource),
          items: [
            for (final source in PowerSource.values)
              DropdownMenuItem(
                value: source,
                child: Text(_powerSourceLabel(context, source)),
              ),
          ],
          onChanged: (value) =>
              setState(() => _powerSource = value ?? _powerSource),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_warrantyUntil, (value) {
            setState(() => _warrantyUntil = value);
          }),
          icon: const Icon(Symbols.verified_user_rounded),
          label: Text(
            _warrantyUntil == null
                ? context.l10n.warrantyDate
                : context.l10n.warrantyUntilDate(
                    _formatShortDate(context, _warrantyUntil!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _manualController,
          decoration: InputDecoration(labelText: context.l10n.manualUrl),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _consumableController,
          decoration: InputDecoration(
            labelText: context.l10n.consumable,
            hintText: context.l10n.filterBatteriesCartridges,
          ),
        ),
      ],
    );
  }

  Widget _petFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.petDetails,
          icon: Symbols.pets_rounded,
        ),
        DropdownButtonFormField<String>(
          initialValue: _petType,
          decoration: InputDecoration(labelText: context.l10n.petType),
          items: [
            for (final item in _petTypeOptions)
              DropdownMenuItem(
                value: item,
                child: Text(_petTypeLabel(context, item)),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() => _petType = value);
          },
        ),
        const SizedBox(height: 12),
        if (_petType == 'Fish') ...[
          DropdownButtonFormField<String>(
            initialValue: _fishType,
            decoration: InputDecoration(labelText: context.l10n.fishType),
            items: [
              for (final item in _fishTypeOptions)
                DropdownMenuItem(
                  value: item,
                  child: Text(_fishTypeLabel(context, item)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _fishType = value ?? _fishType),
          ),
          const SizedBox(height: 12),
          if (_fishType == 'Other') ...[
            TextField(
              controller: _petBreedController,
              decoration: InputDecoration(
                labelText: context.l10n.fishBreedOrType,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ] else if (_petType == 'Other') ...[
          TextField(
            controller: _petSpeciesController,
            decoration: InputDecoration(labelText: context.l10n.species),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _petBreedController,
            decoration: InputDecoration(labelText: context.l10n.breed),
          ),
          const SizedBox(height: 12),
        ] else ...[
          TextField(
            controller: _petBreedController,
            decoration: InputDecoration(labelText: context.l10n.breed),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () => _pickDate(_petBirthDate, (value) {
            setState(() => _petBirthDate = value);
          }),
          icon: const Icon(Symbols.cake_rounded),
          label: Text(
            _petBirthDate == null
                ? context.l10n.birthDate
                : context.l10n.bornDate(
                    _formatShortDate(context, _petBirthDate!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _microchipController,
          decoration: InputDecoration(labelText: context.l10n.microchipId),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _vetNameController,
          decoration: InputDecoration(labelText: context.l10n.vetName),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _vetPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: context.l10n.vetPhone),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _feedingController,
          maxLines: 2,
          decoration: InputDecoration(labelText: context.l10n.feedingNotes),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _medicalController,
          maxLines: 2,
          decoration: InputDecoration(labelText: context.l10n.medicalNotes),
        ),
      ],
    );
  }

  Widget _plantFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.plantDetails,
          icon: Symbols.yard_rounded,
        ),
        TextField(
          controller: _plantSpeciesController,
          decoration: InputDecoration(labelText: context.l10n.species),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Sunlight>(
          initialValue: _sunlight,
          decoration: InputDecoration(labelText: context.l10n.sunlight),
          items: [
            for (final item in Sunlight.values)
              DropdownMenuItem(
                value: item,
                child: Text(_sunlightLabel(context, item)),
              ),
          ],
          onChanged: (value) => setState(() => _sunlight = value ?? _sunlight),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _wateringController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.l10n.wateringInterval,
            suffixText: context.l10n.days2,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _potSizeController,
          decoration: InputDecoration(labelText: context.l10n.potSize),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_lastRepottedAt, (value) {
            setState(() => _lastRepottedAt = value);
          }),
          icon: const Icon(Symbols.potted_plant_rounded),
          label: Text(
            _lastRepottedAt == null
                ? context.l10n.lastRepotted
                : context.l10n.repottedDate(
                    _formatShortDate(context, _lastRepottedAt!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _toxicityController,
          decoration: InputDecoration(labelText: context.l10n.toxicityNotes),
        ),
      ],
    );
  }

  Widget _safetyFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.safetyDetails,
          icon: Symbols.health_and_safety_rounded,
        ),
        TextField(
          controller: _safetyTypeController,
          decoration: InputDecoration(labelText: context.l10n.safetyType),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_installedAt, (value) {
            setState(() => _installedAt = value);
          }),
          icon: const Icon(Symbols.construction_rounded),
          label: Text(
            _installedAt == null
                ? context.l10n.installedDate
                : context.l10n.installedDateValue(
                    _formatShortDate(context, _installedAt!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_expiresAt, (value) {
            setState(() => _expiresAt = value);
          }),
          icon: const Icon(Symbols.event_busy_rounded),
          label: Text(
            _expiresAt == null
                ? context.l10n.expirationDate
                : context.l10n.expiresDate(
                    _formatShortDate(context, _expiresAt!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _batteryTypeController,
          decoration: InputDecoration(labelText: context.l10n.batteryType),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _testIntervalController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.l10n.testInterval,
            suffixText: context.l10n.days2,
          ),
        ),
      ],
    );
  }

  Future<void> _changeType(AssetType value, List<Category> categories) async {
    if (value == _assetType) {
      return;
    }
    if (_hasTypedDetailInput()) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.changeItemType),
          content: Text(context.l10n.changeItemTypeWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.change),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _assetType = value;
      _categoryId = _categoryForType(value, categories)?.id ?? _categoryId;
    });
  }

  bool _hasTypedDetailInput() {
    return [
      _brandController,
      _modelController,
      _serialController,
      _manualController,
      _consumableController,
      _petSpeciesController,
      _petBreedController,
      _microchipController,
      _vetNameController,
      _vetPhoneController,
      _feedingController,
      _medicalController,
      _plantSpeciesController,
      _wateringController,
      _potSizeController,
      _toxicityController,
      _safetyTypeController,
      _batteryTypeController,
      _testIntervalController,
    ].any((controller) => controller.text.trim().isNotEmpty);
  }

  Future<void> _pickDate(
    DateTime? current,
    ValueChanged<DateTime?> onSelected,
  ) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null && mounted) {
      onSelected(selected);
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final categoryItems =
        ref.read(categoriesProvider).value ?? const <Category>[];
    final categoryId =
        _categoryId ??
        _categoryForType(_assetType, categoryItems)?.id ??
        categoryItems.firstOrNull?.id;
    final roomItems = ref.read(roomsProvider).value ?? const <Room>[];
    final selectedRoom = _roomId == null
        ? null
        : roomItems.where((room) => room.id == _roomId).firstOrNull;
    final selectedAreaId =
        _areaId ??
        selectedRoom?.areaId ??
        ref.read(areasProvider).value?.firstOrNull?.id;
    final visibleRooms = selectedAreaId == null
        ? roomItems
        : roomItems.where((room) => room.areaId == selectedAreaId).toList();
    final roomId =
        _roomId != null && visibleRooms.any((room) => room.id == _roomId)
        ? _roomId
        : visibleRooms.firstOrNull?.id;
    if (_nameController.text.trim().isEmpty ||
        categoryId == null ||
        roomId == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final isCreating = widget.asset == null;
      final assetId = widget.asset?.id ?? (_creationAssetId ??= _uuid.v7());
      PointDebitResult? debitResult;
      if (isCreating) {
        final online = await ref
            .read(syncConnectivityInstanceProvider)
            .isOnline();
        if (!online) {
          await _saveOfflineDraft();
          if (mounted) {
            hk_ui.showToast(
              context,
              content: Text(context.l10n.offlineItemDraftMessage),
            );
          }
          return;
        }
        final monetization = ref.read(monetizationRepositoryProvider);
        if (monetization == null) {
          throw StateError('Cloud points service is unavailable.');
        }
        debitResult = await monetization.createAsset({
          'operation_id': _creationOperationId ??= _uuid.v7(),
          'asset': {
            'id': assetId,
            'name': _nameController.text.trim(),
            'asset_type': _assetType.name,
            'category_id': categoryId,
            'room_id': roomId,
            'placement': _placementController.text.trim(),
            'notes': _notesController.text.trim(),
            'purchase_date': _purchaseDate?.toUtc().toIso8601String(),
          },
          'details': _pointAssetDetailsPayload(),
          'initial_plans': const <Map<String, dynamic>>[],
        });
      }
      await ref
          .read(assetRepositoryProvider)
          .saveAsset(
            id: assetId,
            name: _nameController.text,
            assetType: _assetType,
            categoryId: categoryId,
            roomId: roomId,
            placement: _placementController.text,
            notes: _notesController.text,
            purchaseDate: _purchaseDate,
            tagNames: _tagsController.text.split(','),
            deviceDetails: _assetType == AssetType.device
                ? DeviceDetails(
                    brand: _brandController.text,
                    model: _modelController.text,
                    serialNumber: _serialController.text,
                    powerSource: _powerSource,
                    warrantyUntil: _warrantyUntil,
                    manualUrl: _manualController.text,
                    consumable: _consumableController.text,
                  )
                : null,
            petDetails: _assetType == AssetType.pet
                ? PetDetails(
                    species: _petType == 'Other'
                        ? _petSpeciesController.text
                        : _petType,
                    breed: _petType == 'Fish'
                        ? _fishType == 'Other'
                              ? _petBreedController.text
                              : _fishType
                        : _petBreedController.text,
                    birthDate: _petBirthDate,
                    microchipId: _microchipController.text,
                    vetName: _vetNameController.text,
                    vetPhone: _vetPhoneController.text,
                    feedingNotes: _feedingController.text,
                    medicalNotes: _medicalController.text,
                  )
                : null,
            plantDetails: _assetType == AssetType.plant
                ? PlantDetails(
                    species: _plantSpeciesController.text,
                    sunlight: _sunlight,
                    wateringIntervalDays: int.tryParse(
                      _wateringController.text,
                    ),
                    potSize: _potSizeController.text,
                    lastRepottedAt: _lastRepottedAt,
                    toxicityNotes: _toxicityController.text,
                  )
                : null,
            safetyDetails: _assetType == AssetType.safety
                ? SafetyDetails(
                    safetyType: _safetyTypeController.text,
                    installedAt: _installedAt,
                    expiresAt: _expiresAt,
                    batteryType: _batteryTypeController.text,
                    testIntervalDays: int.tryParse(
                      _testIntervalController.text,
                    ),
                  )
                : null,
          );
      if (isCreating) {
        await ref
            .read(offlineCreationDraftStoreProvider)
            .clear(_offlineDraftKey);
      }
      if (debitResult?.charged == 1) {
        unawaited(
          ref
              .read(monetizationRepositoryProvider)
              ?.recordEvent('points_debited', {
                'entity_type': 'asset',
                'entity_id': assetId,
                'cost': debitResult!.charged,
                'new_balance': debitResult.balance,
              }),
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        if (_isInsufficientPointsError(error)) {
          await showPointShortageDialog(context, ref, attemptedAction: 'asset');
          return;
        }
        hk_ui.showToast(
          context,
          content: Text(_failureMessage(context, error)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Map<String, dynamic> _pointAssetDetailsPayload() => switch (_assetType) {
    AssetType.device => {
      'brand': _brandController.text.trim(),
      'model': _modelController.text.trim(),
      'serial_number': _serialController.text.trim(),
      'power_source': _powerSource.name,
      'warranty_until': _warrantyUntil?.toUtc().toIso8601String(),
      'manual_url': _manualController.text.trim(),
      'consumable': _consumableController.text.trim(),
    },
    AssetType.pet => {
      'species': _petType == 'Other'
          ? _petSpeciesController.text.trim()
          : _petType,
      'breed': _petType == 'Fish'
          ? _fishType == 'Other'
                ? _petBreedController.text.trim()
                : _fishType
          : _petBreedController.text.trim(),
      'birth_date': _petBirthDate?.toUtc().toIso8601String(),
      'microchip_id': _microchipController.text.trim(),
      'vet_name': _vetNameController.text.trim(),
      'vet_phone': _vetPhoneController.text.trim(),
      'feeding_notes': _feedingController.text.trim(),
      'medical_notes': _medicalController.text.trim(),
    },
    AssetType.plant => {
      'species': _plantSpeciesController.text.trim(),
      'sunlight': _sunlight.name,
      'watering_interval_days': int.tryParse(_wateringController.text),
      'pot_size': _potSizeController.text.trim(),
      'last_repotted_at': _lastRepottedAt?.toUtc().toIso8601String(),
      'toxicity_notes': _toxicityController.text.trim(),
    },
    AssetType.safety => {
      'safety_type': _safetyTypeController.text.trim(),
      'installed_at': _installedAt?.toUtc().toIso8601String(),
      'expires_at': _expiresAt?.toUtc().toIso8601String(),
      'battery_type': _batteryTypeController.text.trim(),
      'test_interval_days': int.tryParse(_testIntervalController.text),
    },
    AssetType.general => const <String, dynamic>{},
  };
}

class _SubsectionTitle extends StatelessWidget {
  const _SubsectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: HkSpacing.xs, bottom: HkSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

class PlanEditorDialog extends ConsumerStatefulWidget {
  const PlanEditorDialog({this.task, this.assetId, super.key});

  final TaskItem? task;
  final String? assetId;

  @override
  ConsumerState<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends ConsumerState<PlanEditorDialog> {
  static const _uuid = Uuid();
  late final TextEditingController _titleController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _intervalController;
  late final TextEditingController _taskTypeController;
  late final TextEditingController _locationController;
  late final TextEditingController _durationController;
  late final TextEditingController _materialsController;
  late final TextEditingController _reminderDaysController;
  late final TextEditingController _reminderRecommendationController;
  String? _assetId;
  Set<String> _dependencyPlanIds = const {};
  late RecurrenceUnit _unit;
  late PriorityLevel _priority;
  late HealthGroup _healthGroup;
  late DateTime _dueDate;
  bool _saving = false;
  String? _creationOperationId;
  String? _creationPlanId;

  @override
  void initState() {
    super.initState();
    final plan = widget.task?.plan;
    _titleController = TextEditingController(text: plan?.title ?? '');
    _titleController.addListener(_onFormChanged);
    _instructionsController = TextEditingController(
      text: plan?.instructions ?? '',
    );
    _intervalController = TextEditingController(
      text: plan?.recurrence.interval.toString() ?? '1',
    );
    _intervalController.addListener(_onFormChanged);
    final metadata = plan?.metadata;
    _taskTypeController = TextEditingController(text: metadata?.taskType ?? '');
    _locationController = TextEditingController(
      text: metadata?.locationLabel ?? '',
    );
    _durationController = TextEditingController(
      text: metadata?.estimatedDurationMinutes?.toString() ?? '',
    );
    _durationController.addListener(_onFormChanged);
    _materialsController = TextEditingController(
      text: metadata?.requiredMaterials.join(', ') ?? '',
    );
    _reminderDaysController = TextEditingController(
      text: plan?.reminderDaysBefore.toString() ?? '0',
    );
    _reminderDaysController.addListener(_onFormChanged);
    _reminderRecommendationController = TextEditingController(
      text: metadata?.reminderRecommendation ?? '',
    );
    _dependencyPlanIds = {...metadata?.dependencyPlanIds ?? const <String>[]};
    _assetId = plan?.assetId ?? widget.assetId;
    _unit = plan?.recurrence.unit ?? RecurrenceUnit.months;
    _priority = plan?.priority ?? PriorityLevel.medium;
    _healthGroup = plan?.healthGroup ?? HealthGroup.appliances;
    _dueDate = plan?.nextDueDate ?? _defaultPlanDueDate();
    if (plan == null) scheduleMicrotask(_restoreOfflineDraft);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFormChanged);
    _intervalController.removeListener(_onFormChanged);
    _durationController.removeListener(_onFormChanged);
    _reminderDaysController.removeListener(_onFormChanged);
    _titleController.dispose();
    _instructionsController.dispose();
    _intervalController.dispose();
    _taskTypeController.dispose();
    _locationController.dispose();
    _durationController.dispose();
    _materialsController.dispose();
    _reminderDaysController.dispose();
    _reminderRecommendationController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  String get _offlineDraftKey {
    final userId = ref.read(monetizationRepositoryProvider)?.currentUserId;
    return 'task_${userId ?? 'local'}_${widget.assetId ?? 'any'}';
  }

  Future<void> _saveOfflineDraft() {
    return ref.read(offlineCreationDraftStoreProvider).save(_offlineDraftKey, {
      'operation_id': _creationOperationId ??= _uuid.v7(),
      'plan_id': _creationPlanId ??= _uuid.v7(),
      'asset_id': _assetId,
      'title': _titleController.text,
      'instructions': _instructionsController.text,
      'interval': _intervalController.text,
      'unit': _unit.name,
      'priority': _priority.name,
      'health_group': _healthGroup.name,
      'due_date': _dueDate.toUtc().toIso8601String(),
      'task_type': _taskTypeController.text,
      'location': _locationController.text,
      'duration': _durationController.text,
      'materials': _materialsController.text,
      'reminder_days': _reminderDaysController.text,
      'reminder_recommendation': _reminderRecommendationController.text,
      'dependency_ids': _dependencyPlanIds.toList(growable: false),
    });
  }

  Future<void> _restoreOfflineDraft() async {
    final draft = await ref
        .read(offlineCreationDraftStoreProvider)
        .load(_offlineDraftKey);
    if (!mounted || draft == null || _titleController.text.isNotEmpty) return;
    String text(String key) => draft[key] as String? ?? '';
    _creationOperationId = draft['operation_id'] as String?;
    _creationPlanId = draft['plan_id'] as String?;
    _titleController.text = text('title');
    _instructionsController.text = text('instructions');
    _intervalController.text = text('interval').isEmpty
        ? '1'
        : text('interval');
    _taskTypeController.text = text('task_type');
    _locationController.text = text('location');
    _durationController.text = text('duration');
    _materialsController.text = text('materials');
    _reminderDaysController.text = text('reminder_days').isEmpty
        ? '0'
        : text('reminder_days');
    _reminderRecommendationController.text = text('reminder_recommendation');
    final dependencies = draft['dependency_ids'];
    setState(() {
      _assetId = draft['asset_id'] as String? ?? widget.assetId;
      _unit =
          RecurrenceUnit.values
              .where((value) => value.name == text('unit'))
              .firstOrNull ??
          RecurrenceUnit.months;
      _priority =
          PriorityLevel.values
              .where((value) => value.name == text('priority'))
              .firstOrNull ??
          PriorityLevel.medium;
      _healthGroup =
          HealthGroup.values
              .where((value) => value.name == text('health_group'))
              .firstOrNull ??
          HealthGroup.appliances;
      _dueDate =
          DateTime.tryParse(text('due_date'))?.toLocal() ??
          _defaultPlanDueDate();
      _dependencyPlanIds = dependencies is List
          ? dependencies.whereType<String>().toSet()
          : const {};
    });
  }

  bool get _metadataNumbersValid {
    final durationText = _durationController.text.trim();
    final reminderText = _reminderDaysController.text.trim();
    final duration = durationText.isEmpty ? null : int.tryParse(durationText);
    final reminder = reminderText.isEmpty ? 0 : int.tryParse(reminderText);
    return (durationText.isEmpty || (duration != null && duration > 0)) &&
        reminder != null &&
        reminder >= 0;
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetsProvider);
    final saveEnabled = assets.maybeWhen(
      data: (items) =>
          !_saving &&
          items.isNotEmpty &&
          _titleController.text.trim().isNotEmpty &&
          (int.tryParse(_intervalController.text) ?? 0) > 0 &&
          _metadataNumbersValid,
      orElse: () => false,
    );
    return _EditorSheetFrame(
      title: widget.task == null ? context.l10n.addTask : context.l10n.editTask,
      saveLabel: widget.task == null
          ? context.l10n.createTask
          : context.l10n.saveTask,
      secondarySaveLabel: widget.task == null
          ? context.l10n.createAndAddAnother
          : null,
      onSecondarySave: widget.task == null
          ? () => _save(closeAfterSave: false)
          : null,
      saveEnabled: saveEnabled,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => _save(closeAfterSave: true),
      child: assets.when(
        data: (items) {
          if (items.isEmpty) {
            return hk_ui.PremiumEmptyState(
              icon: Icons.inventory_2_outlined,
              title: context.l10n.createAnItemFirst,
              body: context.l10n.maintenancePlansNeedItemBody,
            );
          }
          final selected =
              _assetId != null && items.any((item) => item.id == _assetId)
              ? _assetId
              : items.first.id;
          final dependencyCandidates =
              (ref.watch(tasksProvider).value ?? const <TaskItem>[])
                  .where(
                    (task) =>
                        task.asset.id == selected &&
                        task.plan.id != widget.task?.plan.id,
                  )
                  .toList(growable: false);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              hk_ui.PremiumCard(
                padding: const EdgeInsets.all(10),
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 18,
                    ),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      child: Text(
                        context.l10n.planEditorIntro,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: context.l10n.item),
                items: [
                  for (final item in items)
                    DropdownMenuItem(
                      value: item.id,
                      child: DynamicText(item.name, contentType: 'asset.name'),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _assetId = value;
                  _dependencyPlanIds = const {};
                }),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: context.l10n.taskTitle),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _instructionsController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.instructions,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.every,
                      ),
                    ),
                  ),
                  const SizedBox(width: HkSpacing.xs),
                  Expanded(
                    child: DropdownButtonFormField<RecurrenceUnit>(
                      initialValue: _unit,
                      decoration: InputDecoration(labelText: context.l10n.unit),
                      items: [
                        for (final item in RecurrenceUnit.values)
                          DropdownMenuItem(
                            value: item,
                            child: Text(_recurrenceUnitLabel(context, item)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _unit = value ?? _unit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HkSpacing.xs),
              DropdownButtonFormField<PriorityLevel>(
                initialValue: _priority,
                decoration: InputDecoration(labelText: context.l10n.priority),
                items: [
                  for (final item in PriorityLevel.values)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_priorityLabel(context, item)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: HkSpacing.xs),
              DropdownButtonFormField<HealthGroup>(
                initialValue: _healthGroup,
                decoration: InputDecoration(
                  labelText: context.l10n.healthGroup,
                ),
                items: [
                  for (final item in HealthGroup.values)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_healthGroupLabel(context, item)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _healthGroup = value ?? _healthGroup),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _taskTypeController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.taskType,
                  hintText: context.l10n.inspectionCleaningFeeding,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _locationController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.locationLabel,
                  hintText: context.l10n.topShelfLeftCabinet,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.estMinutes,
                        errorText:
                            _durationController.text.trim().isNotEmpty &&
                                (int.tryParse(
                                          _durationController.text.trim(),
                                        ) ??
                                        0) <
                                    1
                            ? context.l10n.use1OrMore
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: HkSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: _reminderDaysController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.remindDaysBefore,
                        errorText:
                            (int.tryParse(
                                      _reminderDaysController.text.trim(),
                                    ) ??
                                    -1) <
                                0
                            ? context.l10n.use0OrMore
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _materialsController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.requiredMaterials,
                  hintText: context.l10n.commaSeparated2,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _reminderRecommendationController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.l10n.reminderNote,
                  hintText: context.l10n.optionalContextForNotifications,
                ),
              ),
              if (dependencyCandidates.isNotEmpty) ...[
                const SizedBox(height: HkSpacing.xs),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.account_tree_rounded),
                  title: Text(context.l10n.dependencyTasks),
                  subtitle: Text(
                    _dependencyPlanIds.isEmpty
                        ? context.l10n.noDependenciesSelected
                        : context.l10n.selectedCount(_dependencyPlanIds.length),
                  ),
                  children: [
                    for (final candidate in dependencyCandidates.take(8))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _dependencyPlanIds.contains(candidate.plan.id),
                        title: DynamicText(
                          candidate.plan.title,
                          contentType: 'maintenance_plan.title',
                        ),
                        subtitle: Text(
                          _formatShortDate(context, candidate.plan.nextDueDate),
                        ),
                        onChanged: (selected) => setState(() {
                          final next = {..._dependencyPlanIds};
                          if (selected ?? false) {
                            next.add(candidate.plan.id);
                          } else {
                            next.remove(candidate.plan.id);
                          }
                          _dependencyPlanIds = next;
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: HkSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event),
                      label: Text(
                        context.l10n.dueDate(
                          _formatShortDate(context, _dueDate),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: HkSpacing.xs),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Symbols.schedule_rounded),
                      label: Text(_formatShortTime(context, _dueDate)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        error: (error, _) => Text(_failureMessage(context, error)),
        loading: () => const LinearProgressIndicator(),
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null && mounted) {
      setState(
        () => _dueDate = DateTime(
          selected.year,
          selected.month,
          selected.day,
          _dueDate.hour,
          _dueDate.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate),
    );
    if (selected != null && mounted) {
      setState(
        () => _dueDate = DateTime(
          _dueDate.year,
          _dueDate.month,
          _dueDate.day,
          selected.hour,
          selected.minute,
        ),
      );
    }
  }

  Future<void> _save({required bool closeAfterSave}) async {
    if (_saving) {
      return;
    }
    final assets = ref.read(assetsProvider).value ?? [];
    final assetId = _assetId ?? assets.firstOrNull?.id;
    final interval = int.tryParse(_intervalController.text) ?? 1;
    final reminderText = _reminderDaysController.text.trim();
    final reminderDaysBefore = reminderText.isEmpty
        ? 0
        : int.tryParse(reminderText);
    if (assetId == null ||
        _titleController.text.trim().isEmpty ||
        interval < 1 ||
        reminderDaysBefore == null ||
        !_metadataNumbersValid) {
      return;
    }
    final metadata = _metadataFromForm();
    setState(() => _saving = true);
    try {
      final isCreating = widget.task == null;
      final planId = widget.task?.plan.id ?? (_creationPlanId ??= _uuid.v7());
      final operationId = _creationOperationId ??= _uuid.v7();

      if (isCreating) {
        final monetizationRepo = ref.read(monetizationRepositoryProvider);
        if (monetizationRepo != null) {
          final online = await ref
              .read(syncConnectivityInstanceProvider)
              .isOnline();
          if (!online) {
            await _saveOfflineDraft();
            if (mounted) {
              hk_ui.showToast(
                context,
                content: Text(context.l10n.offlineTaskDraftMessage),
              );
            }
            return;
          }
        }

        final creationController = ref.read(taskCreationControllerProvider);
        final accountScope =
            ref.read(monetizationRepositoryProvider)?.currentUserId ?? 'local';

        final existingOp = TaskCreationOperation(
          operationId: operationId,
          planId: planId,
          accountScope: accountScope,
          requestPayload: const <String, dynamic>{},
          requestHash: '',
          state: TaskCreationOperationState.submitting,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final success = await creationController.createNewTask(
          assetId: assetId,
          title: _titleController.text,
          instructions: _instructionsController.text,
          recurrence: RecurrenceRule(interval: interval, unit: _unit),
          priority: _priority,
          nextDueDate: _dueDate,
          healthGroup: _healthGroup,
          reminderDaysBefore: reminderDaysBefore,
          metadata: metadata,
          accountScope: accountScope,
          existingOperation: existingOp,
        );

        if (!success) {
          final state = creationController.value;
          if (mounted && state.failure != null) {
            if (_isInsufficientPointsError(state.failure!.message)) {
              await showPointShortageDialog(
                context,
                ref,
                attemptedAction: 'task',
              );
              return;
            }
            hk_ui.showToast(
              context,
              content: Text(_failureMessage(context, state.failure!.message)),
              severity: hk_ui.HkToastSeverity.error,
            );
          }
          return;
        }

        await ref
            .read(offlineCreationDraftStoreProvider)
            .clear(_offlineDraftKey);
      }

      await ref
          .read(maintenanceRepositoryProvider)
          .savePlan(
            id: planId,
            assetId: assetId,
            title: _titleController.text,
            instructions: _instructionsController.text,
            recurrence: RecurrenceRule(interval: interval, unit: _unit),
            priority: _priority,
            nextDueDate: _dueDate,
            healthGroup: _healthGroup,
            reminderDaysBefore: reminderDaysBefore,
            metadata: metadata,
          );

      await refreshNotificationSchedules(ref);
      if (mounted) {
        if (widget.task == null) {
          _showTaskActionFeedback(context, _TaskActionFeedbackType.created);
        }
        if (closeAfterSave) {
          Navigator.of(context).pop();
        } else {
          _creationOperationId = null;
          _creationPlanId = null;
          _titleController.clear();
          _instructionsController.clear();
          _taskTypeController.clear();
          _locationController.clear();
          _durationController.clear();
          _materialsController.clear();
          _reminderRecommendationController.clear();
          setState(() {
            _dueDate = _defaultPlanDueDate();
            _dependencyPlanIds = const {};
          });
          hk_ui.showToast(context, content: Text(context.l10n.taskCreated));
        }
      }
    } catch (error) {
      if (mounted) {
        if (_isInsufficientPointsError(error)) {
          await showPointShortageDialog(context, ref, attemptedAction: 'task');
          return;
        }
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(
              context,
              error,
              fallback: AppFailureCode.taskUpdate,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  TaskMetadata? _metadataFromForm() {
    final durationText = _durationController.text.trim();
    final duration = durationText.isEmpty ? null : int.tryParse(durationText);
    final metadata = TaskMetadata(
      taskType: _nullableEditText(_taskTypeController.text),
      locationLabel: _nullableEditText(_locationController.text),
      estimatedDurationMinutes: duration,
      requiredMaterials: _commaList(_materialsController.text),
      dependencyPlanIds: _dependencyPlanIds.toList(growable: false),
      reminderRecommendation: _nullableEditText(
        _reminderRecommendationController.text,
      ),
    );
    if (metadata.taskType == null &&
        metadata.locationLabel == null &&
        metadata.estimatedDurationMinutes == null &&
        metadata.requiredMaterials.isEmpty &&
        metadata.dependencyPlanIds.isEmpty &&
        metadata.reminderRecommendation == null) {
      return null;
    }
    return metadata;
  }
}

DateTime _defaultPlanDueDate() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    const NotificationPreferences().reminderHour,
  );
}

class TaskGroup extends StatelessWidget {
  const TaskGroup({
    required this.title,
    required this.tasks,
    required this.color,
    required this.onComplete,
    required this.onEdit,
    required this.onSnooze,
    required this.onSetEnabled,
    required this.onDelete,
    super.key,
  });

  final String title;
  final List<TaskItem> tasks;
  final Color color;
  final Future<bool> Function(TaskItem) onComplete;
  final ValueChanged<TaskItem> onEdit;
  final ValueChanged<TaskItem> onSnooze;
  final Future<void> Function(TaskItem task, bool enabled) onSetEnabled;
  final Future<bool> Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              hk_ui.StatusPill(
                label: _taskGroupCountLabel(context, tasks.length),
                color: color,
              ),
            ],
          ),
        ),
        for (final task in tasks)
          hk_ui.SwipeDelete(
            margin: const EdgeInsets.only(bottom: HkSpacing.sm),
            dismissKey: ValueKey('task-delete-${task.plan.id}'),
            action: hk_ui.SwipeAction.moveToTrash(
              onAction: () => onDelete(task),
            ),
            child: hk_ui.TaskCard(
              task: task,
              margin: EdgeInsets.zero,
              onTap: () => context.push('/maintenance/${task.plan.id}'),
              onComplete: () => onComplete(task),
              onEdit: () => onEdit(task),
              onSnooze: () => onSnooze(task),
              onSetEnabled: (enabled) => onSetEnabled(task, enabled),
              onArchive: () => onDelete(task),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class TaskTile extends ConsumerWidget {
  const TaskTile({required this.task, this.dense = false, super.key});

  final TaskItem task;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue = task.status == TaskStatus.overdue;
    return Card(
      margin: EdgeInsets.only(bottom: dense ? 4 : 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: overdue
              ? Theme.of(context).colorScheme.errorContainer
              : null,
          child: Icon(_iconForGroup(task.plan.healthGroup)),
        ),
        title: DynamicText(
          task.plan.title,
          contentType: 'maintenance_plan.title',
        ),
        subtitle: Text(
          '${task.asset.name} - ${_formatShortDate(context, task.plan.nextDueDate)} - ${_recurrenceLabel(context, task.plan.recurrence)}',
        ),
        trailing: IconButton(
          tooltip: context.l10n.completeTask,
          onPressed: () => completeTaskWithFeedback(context, ref, task),
          icon: const Icon(Icons.check_circle_outline),
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const hk_ui.HkStateIllustration(
              icon: Symbols.error_rounded,
              tone: hk_ui.HkIllustrationTone.danger,
              size: 88,
            ),
            const SizedBox(height: HkSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

class MoreTile extends StatelessWidget {
  const MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(path),
      ),
    );
  }
}

class ChartCard extends StatelessWidget {
  const ChartCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: HkSpacing.xs),
          SizedBox(height: 150, child: child),
        ],
      ),
    );
  }
}

class MonthlyCompletionsChart extends StatelessWidget {
  const MonthlyCompletionsChart({required this.data, super.key});

  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return hk_ui.PremiumEmptyState(
        icon: Icons.bar_chart,
        title: context.l10n.notEnoughDataYet,
        body: context.l10n.completeMoreTasksToSeeMonthlyTrends,
      );
    }
    final entries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxValue = entries
        .map((entry) => entry.value)
        .fold<int>(0, math.max)
        .clamp(1, 10000)
        .toDouble();
    return BarChart(
      BarChartData(
        borderData: FlBorderData(show: false),
        maxY: maxValue + 1,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Theme.of(context).colorScheme.outlineVariant,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) => Text(
                value.round().toString(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) {
                  return const SizedBox.shrink();
                }
                final parts = entries[index].key.split('-');
                final month = parts.length == 2
                    ? DateFormat.MMM(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(
                        DateTime(int.parse(parts[0]), int.parse(parts[1])),
                      )
                    : entries[index].key;
                return Text(
                  month,
                  style: Theme.of(context).textTheme.labelSmall,
                );
              },
            ),
          ),
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
        barGroups: [
          for (var index = 0; index < entries.length; index++)
            BarChartGroupData(
              x: index,
              showingTooltipIndicators: [0],
              barRods: [
                BarChartRodData(
                  toY: entries[index].value.toDouble(),
                  color: Theme.of(context).colorScheme.primary,
                  width: 18,
                ),
              ],
            ),
        ],
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 2,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                rod.toY.round().toString(),
                Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class TaskDistributionChart extends StatelessWidget {
  const TaskDistributionChart({required this.data, super.key});

  final Map<HealthGroup, int> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return hk_ui.PremiumEmptyState(
        icon: Icons.pie_chart,
        title: context.l10n.noTaskDistribution,
        body: context.l10n.scheduledPlansWillAppearHere,
      );
    }
    final colors = [
      Colors.teal,
      Colors.indigo,
      Colors.orange,
      Colors.green,
      Colors.pink,
      Colors.blueGrey,
    ];
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final splitIndex = (entries.length / 2).ceil();

    Widget legendRow(int start, int end) {
      if (start >= end) {
        return const SizedBox.shrink();
      }
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = start; index < end; index++) ...[
                hk_ui.StatusPill(
                  label:
                      '${_healthGroupLabel(context, entries[index].key)} ${entries[index].value}',
                  color: colors[index % colors.length],
                  compact: true,
                ),
                if (index < end - 1) const SizedBox(width: HkSpacing.xs),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: [
                for (var index = 0; index < entries.length; index++)
                  PieChartSectionData(
                    value: entries[index].value.toDouble(),
                    title: NumberFormat.percentPattern(
                      _localeTag(context),
                    ).format(entries[index].value / total),
                    color: colors[index % colors.length],
                    radius: 62,
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: HkSpacing.xs),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            legendRow(0, splitIndex),
            if (splitIndex < entries.length) ...[
              const SizedBox(height: HkSpacing.space4),
              legendRow(splitIndex, entries.length),
            ],
          ],
        ),
      ],
    );
  }
}

class _CalendarSummaryCard extends StatelessWidget {
  const _CalendarSummaryCard({
    required this.overdue,
    required this.today,
    required this.upcoming,
  });

  final int overdue;
  final int today;
  final int upcoming;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      borderRadius: HkRadii.xxl,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
      child: SizedBox(
        height: 70,
        child: Row(
          children: [
            Expanded(
              child: _MiniCalendarMetric(
                label: context.l10n.overdue,
                value: overdue,
                color: HkColors.tertiary,
                icon: Symbols.warning_rounded,
              ),
            ),
            Expanded(
              child: _MiniCalendarMetric(
                label: context.l10n.today,
                value: today,
                color: HkColors.amber,
                icon: Symbols.today_rounded,
              ),
            ),
            Expanded(
              child: _MiniCalendarMetric(
                label: context.l10n.upcoming,
                value: upcoming,
                color: Theme.of(context).colorScheme.primary,
                icon: Symbols.event_upcoming_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCalendarMetric extends StatelessWidget {
  const _MiniCalendarMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CalendarMonthCard extends StatelessWidget {
  const _CalendarMonthCard({
    required this.month,
    required this.selectedDate,
    required this.taskCounts,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime month;
  final DateTime selectedDate;
  final Map<DateTime, int> taskCounts;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final weeks = hk_dates.calendarMonthGrid(month);
    final today = hk_dates.dateOnly(DateTime.now());
    final weekdayFormat = DateFormat.E(_localeTag(context));
    final weekdays = [
      for (var offset = 0; offset < DateTime.daysPerWeek; offset += 1)
        weekdayFormat.format(DateTime(2024, 1, 7 + offset)),
    ];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return hk_ui.PremiumCard(
      borderRadius: HkRadii.xxl,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat.yMMMM(_localeTag(context)).format(month),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: context.l10n.previousMonth,
                onPressed: onPreviousMonth,
                iconSize: 18,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  rtl
                      ? Symbols.chevron_right_rounded
                      : Symbols.chevron_left_rounded,
                ),
              ),
              IconButton(
                tooltip: context.l10n.nextMonth,
                onPressed: onNextMonth,
                iconSize: 18,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  rtl
                      ? Symbols.chevron_left_rounded
                      : Symbols.chevron_right_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.space4),
          Row(
            children: [
              for (final weekday in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      weekday,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: HkSpacing.space4),
          Column(
            children: [
              for (
                var weekIndex = 0;
                weekIndex < weeks.length;
                weekIndex++
              ) ...[
                Row(
                  children: [
                    for (
                      var dayIndex = 0;
                      dayIndex < weeks[weekIndex].length;
                      dayIndex++
                    ) ...[
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _CalendarDayCell(
                            date: weeks[weekIndex][dayIndex],
                            selectedDate: selectedDate,
                            today: today,
                            taskCounts: taskCounts,
                            onDateSelected: onDateSelected,
                          ),
                        ),
                      ),
                      if (dayIndex != weeks[weekIndex].length - 1)
                        const SizedBox(width: HkSpacing.space4),
                    ],
                  ],
                ),
                if (weekIndex != weeks.length - 1)
                  const SizedBox(height: HkSpacing.space4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.selectedDate,
    required this.today,
    required this.taskCounts,
    required this.onDateSelected,
  });

  final DateTime? date;
  final DateTime selectedDate;
  final DateTime today;
  final Map<DateTime, int> taskCounts;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final dateValue = date;
    if (dateValue == null) {
      return const SizedBox.shrink();
    }
    final dayValue = dateValue.day;
    final dateOnly = hk_dates.dateOnly(dateValue);
    final selected = hk_dates.isSameDate(dateOnly, selectedDate);
    final isToday = hk_dates.isSameDate(dateOnly, today);
    final count = taskCounts[dateOnly] ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primary
        : count > 0
        ? scheme.secondaryContainer
        : scheme.surfaceContainerLowest;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.calendarDaySummary(
        isToday.toString(),
        DateFormat.yMMMMd(
          Localizations.localeOf(context).toLanguageTag(),
        ).format(dateOnly),
        count,
      ),
      child: InkWell(
        key: ValueKey('calendar-day-${dateOnly.toIso8601String()}'),
        borderRadius: BorderRadius.circular(HkRadii.md),
        onTap: () => onDateSelected(dateOnly),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(HkRadii.md),
            border: Border.all(
              color: isToday && !selected
                  ? scheme.primary.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dayValue',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: selected || isToday
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
              SizedBox(
                height: 11,
                child: count > 0
                    ? Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconForGroup(HealthGroup group) {
  return switch (group) {
    HealthGroup.safety => Icons.health_and_safety,
    HealthGroup.pets => Icons.pets,
    HealthGroup.appliances => Icons.kitchen,
    HealthGroup.plants => Icons.local_florist,
    HealthGroup.cleaning => Icons.cleaning_services,
    HealthGroup.other => Icons.home_repair_service,
  };
}

IconData _iconForArea(Area area) {
  return switch (area.kind) {
    AreaKind.indoor => Symbols.home_work_rounded,
    AreaKind.outdoor => Symbols.yard_rounded,
  };
}

IconData _iconForRoom(Room room) {
  return switch (room.roomType) {
    RoomType.living => Symbols.chair_rounded,
    RoomType.bedroom => Symbols.bed_rounded,
    RoomType.kitchen => Symbols.skillet_rounded,
    RoomType.bathroom => Symbols.bathtub_rounded,
    RoomType.utility => Symbols.build_rounded,
    RoomType.storage => Symbols.inventory_2_rounded,
    RoomType.office => Symbols.desk_rounded,
    RoomType.dining => Symbols.dining_rounded,
    RoomType.hallway => Symbols.door_front_rounded,
    RoomType.entry => Symbols.door_open_rounded,
    RoomType.garage => Symbols.garage_home_rounded,
    RoomType.garden => Symbols.yard_rounded,
    RoomType.outdoor => Symbols.deck_rounded,
    RoomType.patio => Symbols.deck_rounded,
    RoomType.balcony => Symbols.balcony_rounded,
    RoomType.pool => Symbols.pool_rounded,
    RoomType.lawn => Symbols.grass_rounded,
    RoomType.shed => Symbols.cabin_rounded,
    RoomType.driveway => Symbols.local_parking_rounded,
    RoomType.other => Symbols.meeting_room_rounded,
  };
}

IconData _iconForAssetType(AssetType type) {
  return switch (type) {
    AssetType.device => Symbols.memory_rounded,
    AssetType.pet => Symbols.pets_rounded,
    AssetType.plant => Symbols.yard_rounded,
    AssetType.safety => Symbols.health_and_safety_rounded,
    AssetType.general => Symbols.inventory_2_rounded,
  };
}

String _areaKindLabel(BuildContext context, AreaKind kind) {
  return switch (kind) {
    AreaKind.indoor => context.l10n.indoor,
    AreaKind.outdoor => context.l10n.outdoor,
  };
}

String _roomTypeLabel(BuildContext context, RoomType type) {
  return switch (type) {
    RoomType.living => context.l10n.livingRoom,
    RoomType.bedroom => context.l10n.bedroom,
    RoomType.kitchen => context.l10n.kitchen,
    RoomType.bathroom => context.l10n.bathroom,
    RoomType.utility => context.l10n.utility,
    RoomType.storage => context.l10n.storage,
    RoomType.office => context.l10n.office,
    RoomType.dining => context.l10n.diningRoom,
    RoomType.hallway => context.l10n.hallway,
    RoomType.entry => context.l10n.entry,
    RoomType.garage => context.l10n.garage,
    RoomType.garden => context.l10n.garden,
    RoomType.outdoor => context.l10n.outdoorZone,
    RoomType.patio => context.l10n.patio,
    RoomType.balcony => context.l10n.balcony,
    RoomType.pool => context.l10n.pool,
    RoomType.lawn => context.l10n.lawn,
    RoomType.shed => context.l10n.shed,
    RoomType.driveway => context.l10n.driveway,
    RoomType.other => context.l10n.other,
  };
}

List<RoomType> _roomTypesFor(AreaKind kind) {
  return switch (kind) {
    AreaKind.indoor => const [
      RoomType.living,
      RoomType.bedroom,
      RoomType.kitchen,
      RoomType.bathroom,
      RoomType.dining,
      RoomType.office,
      RoomType.entry,
      RoomType.hallway,
      RoomType.utility,
      RoomType.storage,
      RoomType.garage,
      RoomType.other,
    ],
    AreaKind.outdoor => const [
      RoomType.garden,
      RoomType.patio,
      RoomType.balcony,
      RoomType.pool,
      RoomType.lawn,
      RoomType.shed,
      RoomType.driveway,
      RoomType.outdoor,
      RoomType.other,
    ],
  };
}

String _assetTypeLabel(BuildContext context, AssetType type) {
  return switch (type) {
    AssetType.device => context.l10n.deviceOrAppliance,
    AssetType.pet => context.l10n.pet,
    AssetType.plant => context.l10n.plant,
    AssetType.safety => context.l10n.safetyItem,
    AssetType.general => context.l10n.generalItem,
  };
}

String _assetTypePluralLabel(BuildContext context, AssetType type) {
  return switch (type) {
    AssetType.device => context.l10n.devicesAndAppliances,
    AssetType.pet => context.l10n.pets,
    AssetType.plant => context.l10n.plants,
    AssetType.safety => context.l10n.safetyItems,
    AssetType.general => context.l10n.generalItems,
  };
}

String _powerSourceLabel(BuildContext context, PowerSource source) {
  return switch (source) {
    PowerSource.mains => context.l10n.mains,
    PowerSource.battery => context.l10n.battery,
    PowerSource.solar => context.l10n.solar,
    PowerSource.none => context.l10n.none,
    PowerSource.other => context.l10n.other,
  };
}

String _sunlightLabel(BuildContext context, Sunlight sunlight) {
  return switch (sunlight) {
    Sunlight.low => context.l10n.lowLight,
    Sunlight.medium => context.l10n.mediumLight,
    Sunlight.brightIndirect => context.l10n.brightIndirect,
    Sunlight.fullSun => context.l10n.fullSun,
  };
}

String _taskStatusLabel(BuildContext context, TaskStatus status) {
  return switch (status) {
    TaskStatus.overdue => context.l10n.overdue,
    TaskStatus.dueToday => context.l10n.dueToday,
    TaskStatus.upcoming => context.l10n.upcoming,
    TaskStatus.completed => context.l10n.completed,
  };
}

String _priorityLabel(BuildContext context, PriorityLevel priority) {
  return switch (priority) {
    PriorityLevel.low => context.l10n.routine,
    PriorityLevel.medium => context.l10n.medium,
    PriorityLevel.high => context.l10n.high,
    PriorityLevel.critical => context.l10n.critical,
  };
}

String _healthGroupLabel(BuildContext context, HealthGroup group) {
  return switch (group) {
    HealthGroup.safety => context.l10n.safety,
    HealthGroup.pets => context.l10n.pets,
    HealthGroup.appliances => context.l10n.appliances,
    HealthGroup.plants => context.l10n.plants,
    HealthGroup.cleaning => context.l10n.cleaning,
    HealthGroup.other => context.l10n.general,
  };
}

String _recurrenceUnitLabel(BuildContext context, RecurrenceUnit unit) {
  return switch (unit) {
    RecurrenceUnit.hours => context.l10n.hours2,
    RecurrenceUnit.days => context.l10n.days2,
    RecurrenceUnit.weeks => context.l10n.weeks2,
    RecurrenceUnit.months => context.l10n.months2,
    RecurrenceUnit.years => context.l10n.years2,
  };
}

String _recurrenceLabel(BuildContext context, RecurrenceRule rule) {
  final plural = rule.interval != 1;
  final unit = switch (rule.unit) {
    RecurrenceUnit.hours => plural ? context.l10n.hours2 : context.l10n.hour,
    RecurrenceUnit.days => plural ? context.l10n.days2 : context.l10n.day,
    RecurrenceUnit.weeks => plural ? context.l10n.weeks2 : context.l10n.week,
    RecurrenceUnit.months => plural ? context.l10n.months2 : context.l10n.month,
    RecurrenceUnit.years => plural ? context.l10n.years2 : context.l10n.year,
  };
  if (rule.interval == 1) {
    return context.l10n.recurrenceEveryOne(unit);
  }
  return context.l10n.recurrenceEveryMany(rule.interval, unit);
}

Color _taskStatusColor(BuildContext context, TaskStatus status) {
  return switch (status) {
    TaskStatus.overdue => HkColors.tertiary,
    TaskStatus.dueToday => HkColors.amber,
    TaskStatus.upcoming => Theme.of(context).colorScheme.primary,
    TaskStatus.completed => HkColors.primary,
  };
}

Category? _categoryForType(AssetType type, List<Category> categories) {
  final preferredGroup = switch (type) {
    AssetType.device => HealthGroup.appliances,
    AssetType.pet => HealthGroup.pets,
    AssetType.plant => HealthGroup.plants,
    AssetType.safety => HealthGroup.safety,
    AssetType.general => HealthGroup.other,
  };
  return categories
      .where((item) => item.healthGroup == preferredGroup)
      .firstOrNull;
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
