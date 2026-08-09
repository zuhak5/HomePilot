import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/features/auth/data/account_deletion_recovery_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('generated recovery key is 32-byte unpadded base64url', () {
    for (var index = 0; index < 16; index++) {
      final key = createAccountDeletionRecoveryKey();
      expect(key, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(base64Url.decode('$key='), hasLength(32));
    }
  });

  test(
    'secure store round-trips and clears one narrow operation record',
    () async {
      final storage = _MockSecureStorage();
      String? encoded;
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        encoded = invocation.namedArguments[#value] as String;
      });
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => encoded);
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async => encoded = null);
      final store = SecureAccountDeletionRecoveryStore(storage: storage);
      const operation = AccountDeletionRecoveryOperation(
        expectedUserId: 'user-1',
        recoveryKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );

      await store.write(operation);
      final restored = await store.read();

      expect(restored?.expectedUserId, 'user-1');
      expect(restored?.recoveryKey, operation.recoveryKey);
      expect(encoded, contains('expected_user_id'));
      await store.clear();
      expect(await store.read(), isNull);
    },
  );

  test('malformed persisted material is discarded', () async {
    final storage = _MockSecureStorage();
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((_) async => '{"recovery_key":"short"}');
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    final store = SecureAccountDeletionRecoveryStore(storage: storage);

    expect(await store.read(), isNull);
    verify(() => storage.delete(key: any(named: 'key'))).called(1);
  });
}
