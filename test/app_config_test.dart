import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/core/config/app_config.dart';

void main() {
  test('test configuration supplies local Supabase placeholders', () {
    final config = AppConfig.test(environment: AppEnvironment.dev);

    expect(config.supabaseUrl.host, '127.0.0.1');
    expect(config.redactedDescription, isNot(contains('key')));
  });

  test('production configuration requires a Google Web client', () {
    final config = AppConfig.configured(
      environment: AppEnvironment.prod,
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
    );

    expect(config.googleWebClientId, '123-example.apps.googleusercontent.com');
  });

  test('environment configuration fails without Supabase values', () {
    expect(AppConfig.fromEnvironment, throwsA(isA<AppConfigException>()));
  });

  test('rejects insecure hosted URLs', () {
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.prod,
        supabaseUrl: 'http://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: '123-example.apps.googleusercontent.com',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('rejects service role JWTs', () {
    final header = base64Url.encode(utf8.encode('{"alg":"HS256"}'));
    final payload = base64Url.encode(utf8.encode('{"role":"service_role"}'));
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.dev,
        supabaseUrl: 'http://127.0.0.1:54321',
        supabasePublishableKey: '$header.$payload.signature',
        googleWebClientId: '123-example.apps.googleusercontent.com',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('rejects a malformed Google OAuth client ID', () {
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.prod,
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: 'not-a-google-client-id',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });
}
