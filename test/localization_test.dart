import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/l10n/app_localizations.dart';
import 'package:homepilot/src/core/domain/models.dart';
import 'package:homepilot/src/core/services/notification_localization.dart';

void main() {
  test(
    'English and Arabic ARB files have exact key and placeholder parity',
    () {
      final english = _arb('lib/l10n/app_en.arb');
      final arabic = _arb('lib/l10n/app_ar.arb');
      final englishKeys = english.keys.where(_isMessageKey).toSet();
      final arabicKeys = arabic.keys.where(_isMessageKey).toSet();

      expect(arabicKeys, englishKeys);
      expect(englishKeys.length, greaterThanOrEqualTo(650));
      for (final key in englishKeys) {
        final englishValue = english[key] as String;
        final arabicValue = arabic[key] as String;
        expect(arabicValue.trim(), isNotEmpty, reason: key);
        expect(
          _placeholders(arabicValue),
          _placeholders(englishValue),
          reason: 'Placeholder mismatch for $key',
        );
      }
    },
  );

  test('Arabic ICU plural forms and notification arguments are localized', () {
    final arabic = lookupAppLocalizations(const Locale('ar'));
    expect(arabic.roomCount(0), contains('لا'));
    expect(arabic.roomCount(2), contains('غرفتان'));

    final content = localizeInboxNotification(
      arabic,
      InboxNotification(
        id: 'notification-1',
        title: 'Water the basil is overdue',
        body: 'Legacy snapshot',
        kind: 'task',
        createdAt: DateTime.utc(2026, 7, 22),
        messageCode: NotificationMessageCode.taskOverdue.wireValue,
        messageArgs: const {'task': 'Water the basil'},
      ),
    );

    expect(content.title, contains('Water the basil'));
    expect(content.title, contains('تأخرت'));
    expect(content.body, contains('HomePilot'));
  });

  test(
    'unknown controlled notifications use the localized generic fallback',
    () {
      final english = lookupAppLocalizations(const Locale('en'));
      final content = localizeInboxNotification(
        english,
        InboxNotification(
          id: 'notification-2',
          title: 'Backend details must not be shown',
          body: 'Raw payload',
          kind: 'system',
          createdAt: DateTime.utc(2026, 7, 22),
          messageCode: 'future_message_code',
        ),
      );

      expect(content.title, english.notificationGenericTitle);
      expect(content.body, english.notificationGenericBody);
    },
  );
}

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

bool _isMessageKey(String key) => !key.startsWith('@');

Set<String> _placeholders(String value) => RegExp(
  r'\{([A-Za-z][A-Za-z0-9_]*)(?:,|\})',
).allMatches(value).map((match) => match.group(1)!).toSet();
