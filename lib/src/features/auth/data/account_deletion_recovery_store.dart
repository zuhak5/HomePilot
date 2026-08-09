import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/supabase/secure_supabase_storage.dart';

typedef AccountDeletionRecoveryKeyFactory = String Function();

final RegExp _recoveryKeyPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

class AccountDeletionRecoveryOperation {
  const AccountDeletionRecoveryOperation({
    required this.expectedUserId,
    required this.recoveryKey,
  });

  final String expectedUserId;
  final String recoveryKey;

  bool get isValid =>
      expectedUserId.isNotEmpty && _recoveryKeyPattern.hasMatch(recoveryKey);

  Map<String, String> toJson() => {
    'expected_user_id': expectedUserId,
    'recovery_key': recoveryKey,
  };

  static AccountDeletionRecoveryOperation? fromJson(Object? value) {
    if (value is! Map) return null;
    final operation = AccountDeletionRecoveryOperation(
      expectedUserId: value['expected_user_id'] as String? ?? '',
      recoveryKey: value['recovery_key'] as String? ?? '',
    );
    return operation.isValid ? operation : null;
  }
}

abstract interface class AccountDeletionRecoveryStore {
  Future<AccountDeletionRecoveryOperation?> read();
  Future<void> write(AccountDeletionRecoveryOperation operation);
  Future<void> clear();
}

class SecureAccountDeletionRecoveryStore
    implements AccountDeletionRecoveryStore {
  SecureAccountDeletionRecoveryStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: homePilotAndroidSecureStorageOptions,
          );

  static const _storageKey = 'homepilot.account-deletion-recovery.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<AccountDeletionRecoveryOperation?> read() async {
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final operation = AccountDeletionRecoveryOperation.fromJson(
        jsonDecode(encoded),
      );
      if (operation != null) return operation;
    } on FormatException {
      // A malformed record cannot safely identify a logical operation.
    }
    await clear();
    return null;
  }

  @override
  Future<void> write(AccountDeletionRecoveryOperation operation) {
    if (!operation.isValid) {
      throw ArgumentError('Invalid account-deletion recovery operation.');
    }
    return _storage.write(
      key: _storageKey,
      value: jsonEncode(operation.toJson()),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _storageKey);
}

String createAccountDeletionRecoveryKey() {
  final random = math.Random.secure();
  final bytes = Uint8List(32);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = random.nextInt(256);
  }
  return base64UrlEncode(bytes).replaceAll('=', '');
}
