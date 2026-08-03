// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';
import '../utils/redacting_logger.dart';
import 'observability_config.dart';
import 'sentry_event_scrubber.dart';
import 'sentry_logger_bridge.dart';
import 'sentry_scope.dart';
import 'sentry_tracing.dart';

typedef HomePilotSentryInitializer =
    Future<void> Function(
      void Function(SentryFlutterOptions options) configure,
      Future<void> Function() appRunner,
    );

Future<void> initializeHomePilotSentry({
  required ObservabilityConfig config,
  required Future<void> Function() appRunner,
  HomePilotSentryInitializer? initializer,
}) async {
  var appStarted = false;
  Future<void> guardedAppRunner() async {
    if (appStarted) return;
    appStarted = true;
    SentryLoggerBridge.install();
    unawaited(configureHomePilotSentryScope(config));
    await appRunner();
  }

  final stopwatch = Stopwatch()..start();
  try {
    final initialize =
        initializer ??
        (configure, runner) => SentryFlutter.init(
          (options) => configure(options),
          appRunner: runner,
        );
    await initialize(
      (options) => configureHomePilotSentryOptions(options, config),
      guardedAppRunner,
    );
  } on Object catch (error, stackTrace) {
    AppLogger.warning(
      'sentry_initialization_failed',
      error: error,
      stackTrace: stackTrace,
    );
    await guardedAppRunner();
  } finally {
    AppLogger.info(
      'app.start.sentry_init',
      fields: {'elapsed_ms': stopwatch.elapsedMilliseconds},
    );
  }
}

void configureHomePilotSentryOptions(
  SentryFlutterOptions options,
  ObservabilityConfig config,
) {
  options
    ..dsn = config.dsn
    ..environment = config.environment
    ..release = config.release
    ..dist = config.dist
    ..sendDefaultPii = false
    ..attachStacktrace = true
    ..enableAutoSessionTracking = true
    ..enableNativeCrashHandling = true
    ..anrEnabled = true
    ..enableAutoPerformanceTracing = true
    ..enableUserInteractionTracing = false
    ..enableUserInteractionBreadcrumbs = false
    ..enableFramesTracking = true
    ..enableAppLifecycleBreadcrumbs = true
    ..enableAutoNativeBreadcrumbs = false
    ..enablePrintBreadcrumbs = false
    ..enableLogs = false
    ..enableMetrics = false
    ..attachScreenshot = false
    ..attachViewHierarchy = false
    ..reportViewHierarchyIdentifiers = false
    ..profilesSampleRate = 0
    ..maxBreadcrumbs = 50
    ..tracesSampler = homePilotTracesSampler(config)
    ..beforeSend = scrubSentryEvent
    ..beforeSendTransaction = scrubSentryTransaction
    ..beforeBreadcrumb = scrubSentryBreadcrumb;
  options.tracePropagationTargets.clear();
  options.replay
    ..sessionSampleRate = 0
    ..onErrorSampleRate = 0;
}

Future<bool> initializeBackgroundSentry() async {
  SentryWidgetsFlutterBinding.ensureInitialized();
  if (Sentry.isEnabled) return true;
  try {
    final appConfig = AppConfig.fromEnvironment();
    final observability = await ObservabilityConfig.fromAppConfig(appConfig);
    if (!observability.enabled) return false;
    await SentryFlutter.init(
      (options) => configureHomePilotSentryOptions(options, observability),
    );
    SentryLoggerBridge.install();
    await configureHomePilotSentryScope(observability);
    return true;
  } on Object catch (error, stackTrace) {
    AppLogger.warning(
      'sentry_background_initialization_failed',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}
