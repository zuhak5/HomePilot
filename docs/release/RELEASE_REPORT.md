# HomePilot 1.3.0+15 Release Report

Release audit date: 2026-07-26

## Artifact

```text
dist/HomePilot-production-1.3.0-15.apk
```

| Property | Verified value |
| --- | --- |
| Size | 83,406,886 bytes (79.54 MiB) |
| SHA-256 | `1D323FF563930191FF1DE713E805FAA7A97E90287BE962DF6129E679782E0E4E` |
| Package | `com.homepilot.app` |
| Version name | `1.3.0` |
| Version code | `15` |
| Compile SDK | 36 |
| Target SDK | 36 |
| Minimum SDK | 24 |
| Application label | `HomePilot` |
| Launch activity | `com.homepilot.app.MainActivity` |
| APK signature | One signer; APK Signature Scheme v2 |
| Signing alias | `homepilot-release` |
| Certificate SHA-256 | `3E980EB5BB68A51990E77056D4E10995B2E04FB388A73442B79A46C853361E51` |

The APK certificate fingerprint exactly matches the existing ignored JKS
keystore. The keystore was not converted or modified. `zipalign -c -v 4`
completed with `Verification successful`, and `apksigner verify --verbose
--print-certs` returned success.

The artifact is ignored by Git and its checksum exactly matches
`build/app/outputs/flutter-apk/app-prod-release.apk`.

## Clean build evidence

The guarded production build script performs:

```text
flutter clean
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 2m
flutter test --no-pub test/prod_build_config_test.dart [ignored production defines]
flutter build apk --flavor prod --release [ignored production defines]
```

Flutter test commands can recreate Android's ignored main-source plugin
registrant with the dev-only `integration_test` plugin. The script now removes
only that exact generated source immediately before release compilation, lets
Flutter recreate it in release mode, and rejects any release registrant
containing `integration_test`. The definitive clean-script run completed in
12 minutes 30 seconds; Gradle packaging took 595.4 seconds. The final recursive
registrant scan found zero `integration_test` matches.

The full preceding test checkpoint passed 238 tests with one expected skip when
the ignored production configuration was absent. The production-config test
then passed separately with that configuration. The release-only rerun after
the registrant fix repeated clean dependency resolution, localization and Drift
generation, strict analysis, and signed packaging.

## Backend release evidence

- Supabase project: `iajvkvvvhwjdiuaufymh`
- Applied migrations:
  - `20260722061630_reconcile_live_relationship_indexes_and_service_role_grants.sql`
  - `20260722061634_localize_notification_messages_and_language_preference.sql`
- Local pgTAP: 107 passed
- Remote migration history: matching
- Remote error-level lint: clean
- Remote application-schema diff: empty
- `delete-account`: active version 15, JWT verification enabled

See `SUPABASE_DEPLOYMENT.md` for the database/function audit and
`DEPENDENCY_AUDIT.md` for retained upstream compatibility exceptions.

## Smoke-test status and release limitation

At the user's explicit instruction, the emulator step was skipped after the
prepared API-36 Play Store emulator reached a provisioned launcher. The APK was
therefore not installed or launched, and the two disposable Google-account
production isolation/Realtime/delete-account checks were not executed.

This artifact is build-, alignment-, metadata-, signature-, and
checksum-verified, but this report does **not** claim the original plan's
installability or production device-smoke completion criteria. Before broad
distribution, install this exact checksum on an API-36 Google Play emulator or
physical disposable device and complete:

1. English and Arabic onboarding, navigation, immediate switching, restart and
   sign-out persistence, RTL shaping, mixed Arabic/Latin text, and large text.
2. Owner CRUD/sync, offline recovery, notifications, background work, and deep
   links.
3. Cross-user read/write and Realtime denial with the two disposable Google
   accounts.
4. Deletion of one disposable account followed by Auth, database, and private
   Storage cleanup verification.

Do not perform these checks with real-user data.
