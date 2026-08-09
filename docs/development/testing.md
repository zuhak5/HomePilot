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

Functions require formatting, locked type-checking, unit/request-validation tests, and explicit negative-security cases. [`validate-google-backend.yml`](../../.github/workflows/validate-google-backend.yml) enforces the canonical Deno checks for AdMob SSV and account deletion. These isolated tests do not prove that the reviewed function revision or secrets are deployed to a hosted project.

### Browser deletion and Google/Android contract tests

Node tests cover the public account-deletion PKCE flow, token-storage boundary, explicit confirmation, protected function call, strict receipt, exact CORS origins, service-worker navigation policy, and release-workflow source contracts. The static validator also cross-checks Android, ads, reward, auth, and deletion invariants. These checks inspect source/build output; they are not a hosted OAuth, Pages, Supabase, AdMob, or Play Console test.

### VersionDeck tests

Use Node's test runner for manifest schema, build status, cache policy, relative time, APK-verification helpers, and UI state helpers. Build and validate the static artifact after focused tests.

### Protected release validation

The AAB and APK rails are separate. Both require a successful `Validate Google Backend and Release Contracts` run for their exact commit SHA. The AAB rail verifies one signed bundle and emits manifest, dependency, signing, checksum, and provenance evidence; it does not upload to Google Play. The APK rail additionally verifies the standalone signer/package/version, mutates Sentry release state, and creates a GitHub Release. Play Console acceptance, Play App Signing, rollout, public Pages behavior, hosted backend deployment, and physical-device behavior remain operator/hosted evidence. Local tests and workflow-source tests cannot substitute for them.

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
npx supabase stop --no-backup
```

The local Docker stack must be healthy on the ports configured in `supabase/config.toml`. A connection failure or host port reservation is an environment block, not a passing database result.

## Focused remediation contracts

Run focused tests first while iterating, then run the complete relevant suites above.

Startup topology, localization, accessibility, and reduced motion:

```powershell
flutter test --no-pub test/homepilot_splash_lifecycle_test.dart
flutter test --no-pub test/homepilot_splash_overlay_test.dart
flutter test --no-pub test/startup_resources_test.dart
```

Permission/capability derivation, serialized education, settings targeting, and the canonical requester adapters:

```powershell
flutter test --no-pub test/features/permissions
```

Protected transient feedback, runtime ads, and native-ad schema:

```powershell
flutter test --no-pub test/feedback_coordinator_test.dart
flutter test --no-pub test/monetization_test.dart
flutter test --no-pub test/native_ad_factory_contract_test.dart
```

Authentication/deletion client contracts:

```powershell
flutter test --no-pub test/native_google_sign_in_test.dart
flutter test --no-pub test/supabase_auth_repository_test.dart
flutter test --no-pub test/supabase_android_config_test.dart
```

Edge Functions, public browser deletion, and release/static contracts:

```powershell
deno fmt --check `
  supabase/functions/admob-ssv-handler/index.ts `
  supabase/functions/admob-ssv-handler/index_test.ts `
  supabase/functions/delete-account/index.ts `
  supabase/functions/delete-account/index_test.ts

deno check --frozen supabase/functions/admob-ssv-handler/index.ts
deno check --frozen supabase/functions/delete-account/index.ts
deno test --frozen --allow-env --allow-net `
  supabase/functions/admob-ssv-handler/index_test.ts `
  supabase/functions/delete-account/index_test.ts

npm run test:account-deletion
npm run test:release-workflows
npm run validate:google-contracts
```

The package scripts and workflow files are authoritative if this focused command list changes.

## Risk-based matrices

### Synchronization

Test offline mutation, restart, timeout after possible commit, duplicate retry, stale revision, concurrent device changes, missing/duplicate realtime events, cursor-page failure, account switch, revoked session, hydration interruption, media failure, and deletion during queued work.

### Account deletion

Test confirmation, cancellation, wrong Google account, stale session, offline state, duplicate request, Storage/database/Auth ordering, failed cleanup finalization, strict same-user receipt, cloud success/local failure, restart recovery, web PKCE/state handling, exact CORS origins, and exported backups remaining outside app control.

### Monetization

Test every global/per-format runtime gate, generation invalidation, stale callbacks, retry classification/budgets/dormancy/jitter, the 55-minute boundary, exact-once leases, fullscreen serialization, native palette fallback, consent unavailable, no reward, pending claim, valid SSV, replay, invalid signature, wrong account, expiry, insufficient balance, duplicate charged creation, timeout after commit, and offline draft behavior.

### Backup and restore

Test valid current/historical backups, unsupported versions, path traversal, duplicate paths, oversized expansion, hash mismatch, insufficient storage, interrupted replacement, rollback, account mismatch, and sync restart.

### Notifications

Test the separation of user preference, OS/service/special-access state, scheduler truth, and effective capability. Include manual weather with denied location, service-disabled location, notification denial and disabled channel, exact preference off, exact denial with inexact fallback, settings-return refresh, time-zone change, reboot, application update, stale snapshots, completion rescheduling, and duplicate prevention.

### Startup and transient feedback

Test the first Flutter owner, fixed splash lifetime across startup/failure branch changes, non-blank fallback, English and Arabic semantics, compact/large-text layout, interaction blocking, and no repeating animation under reduced motion. For feedback, test protected Undo ordering, exact-key batching, visible counts and deadline reset, LIFO Undo, FIFO finalization, exactly-once callbacks, accessible persistence, callback failure, directional layout, and all Trash restoration call sites.

## Test-writing rules

- Test behavior and invariants, not implementation trivia.
- Use stable clocks, UUIDs, and deterministic fixtures where possible.
- Never use production credentials or services.
- Do not suppress flaky tests without identifying the source of nondeterminism.
- Do not change expected values simply to match an unexplained failure.
- Keep security-denial tests alongside success tests.
- State explicitly when a device, hosted service, or protected workflow remains untested.

## Evidence gaps to track

The backend workflow now runs Edge Function and local Supabase database gates in CI, while the Flutter workflow remains a separate rail. A passing workflow still does not prove deployment to the intended Supabase project, OAuth/AdMob/UMP/Play Console configuration, signed provider callbacks, Google Play delivery, public Pages state, or physical-device behavior. Integration tests should also be expanded beyond localization/screen contracts to exercise synchronization against local services. Report each missing class of evidence explicitly; do not convert source or CI coverage into a hosted/device claim.
