# Contributing to HomePilot

## Before making changes

1. Read [`AGENTS.md`](AGENTS.md) and the relevant documentation under [`docs/`](docs/README.md).
2. Inspect the affected implementation, tests, generated files, migrations, workflows, and configuration.
3. Keep changes narrowly scoped and preserve unrelated work.
4. Never commit credentials, production configuration, signing material, service-role keys, or private user data.

## Local setup

Use Flutter 3.44.7 or the version pinned by CI. Copy an example configuration file:

```powershell
Copy-Item config/dev.example.json config/dev.json
flutter pub get
flutter gen-l10n
dart run build_runner build
```

For local Supabase work:

```powershell
npm ci
npx supabase start
npm run supabase:lint
npm run supabase:test
```

Use the local ports in `supabase/config.toml`. Real configuration files and Supabase environment files are intentionally ignored.

## Change requirements

### Flutter and Dart

- Preserve Riverpod and repository boundaries.
- Use GoRouter instead of introducing a second navigation system.
- Add English and Arabic localization for user-visible text.
- Check both left-to-right and right-to-left layouts.
- Do not edit generated Drift or localization output manually.
- Add focused tests for behavior changes.

### Database and synchronization

- Treat local and cloud schema changes as coordinated work.
- Add forward migrations and migration tests.
- Preserve outbox durability, account binding, idempotency, revision handling, conflict recovery, and restart safety.
- Review backup compatibility and account deletion whenever persistent data changes.
- Keep Row Level Security enabled and test cross-user denial.

### Privacy and observability

- Do not log user content, identity data, location, media paths, tokens, or raw request payloads.
- Preserve the Sentry scrubber and disabled screenshot, replay, view-hierarchy, and raw-HTTP capture settings.
- Update `PRIVACY.md` when data collection, storage, transmission, retention, deletion, permissions, advertising, or third-party processing changes.

### Monetization

- Wallet and reward state remain server-authoritative.
- Reward callbacks from the device are not sufficient to credit points.
- Preserve idempotency, server-side verification, consent behavior, and offline failure handling.

### Release and VersionDeck

- Do not run production signing, release publication, hosted database mutation, or public deployment commands without explicit authorization.
- Preserve independent APK verification, package and signer checks, checksums, provenance, and fail-closed download behavior.

## Validation

Run the narrowest relevant checks, then the standard Flutter suite when Flutter code changed:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Validate production configuration shape with the example file:

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

Supabase changes require:

```powershell
npm run supabase:lint
npm run supabase:test
```

VersionDeck changes require the JavaScript syntax checks, focused Node tests, static site build, and `tool/validate_versiondeck.mjs` used by `.github/workflows/deploy-download-site.yml`.

## Pull requests

A pull request should state:

- What changed and why.
- User and developer impact.
- Data, privacy, migration, synchronization, permission, and release impact.
- Tests and validation executed.
- Checks not executed and why.
- Screenshots for meaningful visual changes in both layout directions where relevant.

Do not weaken tests or security checks merely to make CI pass.