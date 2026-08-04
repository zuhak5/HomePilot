# Testing Strategy

## Goals

HomePilot tests should protect user data, offline behavior, account isolation, backend authorization, monetization integrity, backup safety, localization, and release trust—not only line coverage.

## Test layers

### Pure Dart and service tests

Use for recurrence, formatting, configuration, backup validation, synchronization decisions, monetization state, and deterministic helpers. Prefer these for fast exhaustive edge cases.

### Repository and database tests

Use temporary Drift databases to verify queries, transactions, schema migrations, outbox behavior, reminder snapshots, cleanup, and restart persistence. Migration tests must begin from historical schema fixtures rather than only creating the latest schema.

### Widget tests

Cover visible state, navigation, forms, accessibility, localization, RTL layout, loading, empty, error, offline, signed-out, and blocked behavior. Override Riverpod dependencies instead of contacting real services.

### Integration tests

Use for cross-layer application journeys that cannot be proven by isolated tests. Current integration coverage is limited; new synchronization-sensitive journeys should add real local-service integration coverage where maintainable.

### Supabase database tests

`supabase/tests/database` should verify tables, constraints, RLS, RPCs, ownership, idempotency, and cross-user denial. Run against the local Supabase stack.

### Edge Function tests

Functions require formatting, type-checking, unit tests, request validation tests, and local invocation tests. Establish canonical Deno commands before making them a CI requirement. Account deletion and AdMob SSV require explicit negative-security cases.

### VersionDeck tests

Use Node's test runner for manifest schema, build status, cache policy, relative time, APK-verification helpers, and UI state helpers. Build and validate the static artifact after focused tests.

### Protected release validation

Signing identity, production configuration, Sentry release mutation, provenance, GitHub Release publication, real APK inspection, and public Pages smoke tests are CI/protected-environment evidence. Local tests cannot substitute for them.

## Standard Flutter commands

```powershell
flutter pub get
flutter gen-l10n
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Production configuration schema:

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

## Supabase commands

```powershell
npm ci
npx supabase start
npm run supabase:lint
npm run supabase:test
```

## Risk-based matrices

### Synchronization

Test offline mutation, restart, timeout after possible commit, duplicate retry, stale revision, concurrent device changes, missing/duplicate realtime events, cursor-page failure, account switch, revoked session, hydration interruption, media failure, and deletion during queued work.

### Account deletion

Test confirmation, cancellation, wrong Google account, stale session, offline state, duplicate request, remote partial failure, cloud success/local failure, restart recovery, and exported backups remaining outside app control.

### Monetization

Test consent unavailable, ad failure, no reward, pending claim, valid SSV, replay, invalid signature, wrong account, expiry, insufficient balance, duplicate charged creation, timeout after commit, and offline draft behavior.

### Backup and restore

Test valid current/historical backups, unsupported versions, path traversal, duplicate paths, oversized expansion, hash mismatch, insufficient storage, interrupted replacement, rollback, account mismatch, and sync restart.

### Notifications

Test denied permission, disabled channel, exact-alarm availability, time-zone change, reboot, application update, stale snapshots, completion rescheduling, and duplicate prevention.

## Test-writing rules

- Test behavior and invariants, not implementation trivia.
- Use stable clocks, UUIDs, and deterministic fixtures where possible.
- Never use production credentials or services.
- Do not suppress flaky tests without identifying the source of nondeterminism.
- Do not change expected values simply to match an unexplained failure.
- Keep security-denial tests alongside success tests.
- State explicitly when a device, hosted service, or protected workflow remains untested.

## CI gaps to track

The primary Flutter validation workflow does not currently prove the entire local Supabase and Edge Function stack. Integration tests should be expanded beyond localization/screen checks to exercise actual synchronization against local services. These are documented gaps, not evidence that the underlying behavior is absent.