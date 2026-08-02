import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/core/supabase/secure_supabase_storage.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test(
    'Android secure storage migration preserves data before failing closed',
    () {
      final options = homePilotAndroidSecureStorageOptions.toMap();

      expect(options['migrateOnAlgorithmChange'], 'true');
      expect(options['migrateWithBackup'], 'true');
      expect(options['resetOnError'], 'false');
    },
  );

  test(
    'session namespace and key remain stable across storage upgrades',
    () async {
      final secureStorage = _MockSecureStorage();
      when(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => secureStorage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => 'persisted-session');
      final storage = SecureSupabaseStorage(
        namespace: 'homepilot.production',
        secureStorage: secureStorage,
      );

      await storage.persistSession('persisted-session');
      expect(await storage.accessToken(), 'persisted-session');

      verify(
        () => secureStorage.write(
          key: 'homepilot.production.session',
          value: 'persisted-session',
        ),
      ).called(1);
      verify(
        () => secureStorage.read(key: 'homepilot.production.session'),
      ).called(1);
    },
  );

  test('Android excludes secure storage from device backup', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
  });
}
