# HomePilot

HomePilot is an Android-first Flutter application for organizing household assets and keeping maintenance work on schedule. It combines an offline-first Drift database with authenticated Supabase synchronization, reminders, backup and restore, statistics, Google sign-in, privacy-preserving Sentry observability, and an independently verified APK download site named VersionDeck.

## Current stack

- Flutter 3.44.7 and Dart 3.12
- Riverpod and GoRouter
- Drift and SQLite
- Supabase Auth, Postgres, Storage, Realtime, RPCs, and Edge Functions
- Google sign-in and Google Mobile Ads
- Sentry Flutter
- Flutter local notifications, foreground tasks, Workmanager, and coarse location
- GitHub Actions, PowerShell release tooling, Node.js, and GitHub Pages

The authoritative dependency and SDK versions are in [`pubspec.yaml`](pubspec.yaml), [`package.json`](package.json), and the workflow files under [`.github/workflows`](.github/workflows).

## Product capabilities

HomePilot manages areas, rooms, categories, assets, tags, photos, maintenance plans and history, calendar views, health and readiness summaries, warranty alerts, notifications, search, statistics, settings, cloud accounts, and encrypted-platform storage for sensitive session material. The app supports English and Arabic, including right-to-left layout.

See [`docs/product/feature-catalog.md`](docs/product/feature-catalog.md) for the complete product map.

## Repository map

```text
android/                 Android host, manifests, flavors, signing guards
assets/                  App images, illustrations, audio, and fonts
config/                  Safe configuration examples; real configs are ignored
download-site/           VersionDeck static download site
integration_test/        Flutter integration tests
lib/                     Flutter application and generated localization
supabase/                Local Supabase config, migrations, tests, functions
test/                    Flutter unit and widget tests
tool/                    Build, release, validation, and VersionDeck scripts
docs/                    Product, architecture, development, and operations docs
```

## Getting started

Read [`docs/development/getting-started.md`](docs/development/getting-started.md). The standard local sequence is:

```powershell
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Local Supabase development requires the Supabase CLI and the ports declared in [`supabase/config.toml`](supabase/config.toml). Copy an example configuration file instead of committing secrets.

## Documentation

Start at [`docs/README.md`](docs/README.md). Particularly important documents are:

- [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
- [`docs/architecture/sync-protocol.md`](docs/architecture/sync-protocol.md)
- [`docs/development/testing.md`](docs/development/testing.md)
- [`docs/SENTRY_OPERATIONS.md`](docs/SENTRY_OPERATIONS.md)
- [`docs/versiondeck-release-runbook.md`](docs/versiondeck-release-runbook.md)
- [`PRIVACY.md`](PRIVACY.md)
- [`AGENTS.md`](AGENTS.md)

## Production releases

Production Android builds are created only through the protected GitHub Actions workflow. The workflow validates production configuration, signing identity, package metadata, APK debuggability, checksum, tests, Sentry release publication, provenance, and GitHub Release publication. Do not use the production build or release commands as ordinary local development commands.

See [`docs/operations/release-runbook.md`](docs/operations/release-runbook.md).

## Contributing and security

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing the project. Report vulnerabilities according to [`SECURITY.md`](SECURITY.md); do not disclose sensitive issues in public GitHub issues.

## License status

A repository license has not yet been selected. See [`docs/governance/license-decision.md`](docs/governance/license-decision.md). Until a license is added, no permission to copy, modify, or redistribute the project should be inferred.