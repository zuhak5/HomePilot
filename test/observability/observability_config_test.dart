import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/core/config/app_config.dart';
import 'package:homepilot/src/core/observability/observability_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('release and dist use package-qualified build metadata', () {
    final appConfig = AppConfig.configured(
      environment: AppEnvironment.prod,
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
      sentryDsn: 'https://public@example.ingest.de.sentry.io/123',
      sentryTracesSampleRate: '0.05',
    );

    final config = ObservabilityConfig.fromPackageInfo(
      appConfig,
      PackageInfo(
        appName: 'HomePilot',
        packageName: 'com.homepilot.app',
        version: '1.3.4',
        buildNumber: '19',
      ),
    );

    expect(config.enabled, isTrue);
    expect(config.environment, 'prod');
    expect(config.release, 'com.homepilot.app@1.3.4+19');
    expect(config.dist, '19');
    expect(config.appVersion, '1.3.4');
    expect(config.tracesSampleRate, 0.05);
  });

  test('disabled development config has no transport', () {
    final config = ObservabilityConfig.fromPackageInfo(
      AppConfig.test(),
      PackageInfo(
        appName: 'HomePilot',
        packageName: 'com.homepilot.app.dev',
        version: '1.3.4',
        buildNumber: '19',
      ),
    );

    expect(config.enabled, isFalse);
    expect(config.dsn, isEmpty);
  });
}
