# HomePilot Localization Audit

Audit date: 2026-07-26

## Scope and implementation

- Replaced the application-owned JSON/string-key translator and shadow `Text`
  widget with Flutter `gen_l10n`.
- Added typed English and Arabic ARB catalogs with 901 messages in each locale.
- Verified exact key parity and ICU placeholder parity between the catalogs.
- Added plural/select messages for count-sensitive content.
- Localized application-owned routes, onboarding, dashboard, assets, rooms,
  maintenance, calendar, search, trash, statistics, settings, account, backup,
  notifications, dialogs, validation, empty/loading/error states, accessibility
  labels, notification snapshots, and background-service messages.
- Preserved `HomePilot`, user-authored values, identifiers, and external data.
- Localized dates, numbers, durations, weather, and geocoding requests using the
  active locale.

## Locale resolution and synchronization

`AppLocalePreference` stores `app_language` and
`app_language_explicit`. Resolution uses the newest explicit local or cloud
choice by `updated_at`, then a supported device locale, then English. Legacy
Arabic is migrated as explicit; legacy/default English remains non-explicit.
The preference is retained across restart and sign-out and synchronizes after
authentication.

Autonym language controls are available during onboarding and in Settings.
Changing the selection rebuilds the application immediately without requiring
a restart.

## RTL and accessibility

Layout-sensitive padding, alignment, positioning, icons, navigation, and
animations use directional behavior where semantics mirror. Widget and golden
coverage includes Arabic RTL, mixed Arabic/Latin content, representative phone
sizes, dialogs, forms, notifications, settings, and increased text scale.

The application intentionally uses Android's Arabic platform font fallback
rather than bundling a separate Arabic font. Windows golden rendering cannot
prove Android glyph shaping because the test host lacks an equivalent platform
fallback; Android release-device verification is therefore a separate release
gate recorded in `RELEASE_REPORT.md`.

## Validation

Commands:

```text
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart fix --dry-run
flutter test --concurrency=1
flutter test --coverage --concurrency=1
```

Results:

- Strict analysis: no issues.
- `dart fix --dry-run`: nothing to fix.
- Serialized Flutter suite: 238 passed; one production-configuration test was
  intentionally skipped when its ignored configuration file was not supplied.
- The same production-configuration test passed when run with the ignored
  production configuration.
- Coverage excluding generated Drift and localization output: 10,759 of 16,562
  lines, 64.96%.
- A source scan found no application `debugPrint` calls outside the redacting
  logger and no simple hard-coded English `Text(...)` literals.
