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

Functions require formatting, locked type-checking, unit/request-validation tests, and explicit negative-security cases. [`validate-google-backend.yml`](../../.github/workflows/validate-google-backend.yml) enforces the canonical Deno checks for AdMob SSV, account deletion, and deletion-status recovery. These isolated tests do not prove that the reviewed function revision or secrets are deployed to a hosted project.

### Browser deletion and Google/Android contract tests

Node tests cover the public account-deletion PKCE flow, token-storage boundary, Web Crypto recovery key, explicit confirmation, protected function call, same-key status recovery across reload or ambiguous responses, strict receipt, exact CORS origins, service-worker navigation policy, and release-workflow source contracts. The static validator also cross-checks Android, ads, reward, auth, and deletion invariants. These checks inspect source/build output; they are not a hosted OAuth, Pages, Supabase, AdMob, or Play Console test.

### VersionDeck tests

Use Node's test runner for manifest schema, provenance policy, build status, cache policy, relative time, APK-verification helpers, and UI state helpers. Build and validate the static artifact after focused tests.

### Protected release validation

The AAB and APK rails are separate. Both create an immutable release attempt ID and require a successful manually dispatched `Validate Google Backend and Release Contracts` aggregate for their exact commit SHA, including the protected Advisor source and hosted Advisor jobs. The AAB rail verifies one signed bundle and emits manifest, dependency, signing, checksum, release-attempt, and exact provenance-tuple evidence; it does not upload to Google Play. The APK rail additionally verifies the standalone signer/package/version, mutates Sentry release state, and creates a GitHub Release only after binding the same attempt ID and retaining the exact attestation tuple. VersionDeck can then publish either a verified manifest from that successful current-SHA APK run or an explicit disabled manifest from current `main` via reviewed publication control. Play Console acceptance, Play App Signing, rollout, public Pages behavior, hosted backend deployment, protected release-attempt dry-run execution, and physical-device behavior remain operator/hosted evidence. Local tests and workflow-source tests cannot substitute for them.

### Hosted source-protection tests

The current `main` ruleset strictly requires the real `Format, analyze, and
test` context from the active `Validate Flutter` workflow plus one independent
review and resolved conversations. The backend workflow object remains
disabled under production containment, so its three pull-request job contexts
must not be required until the owning tasks make them active and executable.

TASK-002 probes have demonstrated rejection of administrator direct and force
pushes, an unreviewed merge, human production-pattern tag creation, and app
tag movement/deletion. A reviewer-approved empty pull request with the real
required check merged successfully. The narrowly installed release app created
one disposable production-pattern tag, after which its short-lived token and
private-key material were destroyed and the test ref was removed under an
exact temporary exclusion. See the
[`TASK-002 protection record`](../operations/github-source-and-tag-protection.md).
Do not replace missing hosted evidence with local source inspection.

### GitHub Actions source contract

`tool/github-actions-policy.mjs` scans every workflow and any local composite
action. It allows only the reviewed owner/action/commit pairs in its ledger,
requires full 40-character SHAs and exact release comments, and rejects tags,
branches, shortened or unknown references, YAML aliases, and local-action path
escapes. The locked YAML parser evaluates escaped and explicit mapping keys
semantically, while custom tags, anchors, and aliases fail closed.
`tool/release-workflows.test.mjs` and `tool/release-attempt-ledger.test.mjs`
validate the current 59-reference workflow inventory, release attempt state
machine, exact backend aggregate, and negative fixtures:

```powershell
npm run test:release-workflows
```

The active `Validate Flutter` job installs the locked tooling dependencies and
runs this contract before Flutter setup, so the existing required
`Format, analyze, and test` context fails on a pin-policy regression. The disabled backend workflow also includes the test in source.
Local execution remains `R-EXECUTED` evidence; completion additionally requires
an observed successful `CI-RUN` for the exact HomePilot commit. See the
[reviewed ledger and update procedure](github-actions-supply-chain.md). Task 05
separately owns hosted require-SHA/owner policy evidence.

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
flutter test --no-pub test/task_creation_insufficient_points_test.dart
node --test tool/supabase-advisors.test.mjs
```

The Supabase pgTAP monetization suite also proves that zero-balance task and
asset creation return the structured shortage state and leave no target row
behind. Widget coverage proves the shortage dialog remains visible with inline
recovery status when rewarded ads are unavailable.

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
  supabase/functions/delete-account/index_test.ts `
  supabase/functions/account-deletion-status/index.ts `
  supabase/functions/account-deletion-status/index_test.ts

deno check --frozen supabase/functions/admob-ssv-handler/index.ts
deno check --frozen supabase/functions/delete-account/index.ts
deno check --frozen supabase/functions/account-deletion-status/index.ts
deno test --frozen --allow-env --allow-net `
  supabase/functions/admob-ssv-handler/index_test.ts `
  supabase/functions/delete-account/index_test.ts `
  supabase/functions/account-deletion-status/index_test.ts

npm run test:account-deletion
npm run test:release-workflows
npm run validate:google-contracts
```

The package scripts and workflow files are authoritative if this focused command list changes.

## Risk-based matrices

### Synchronization

Test offline mutation, restart, timeout after possible commit, duplicate retry, stale revision, concurrent device changes, missing/duplicate realtime events, cursor-page failure, account switch, revoked session, hydration interruption, media failure, and deletion during queued work.

### Account deletion

Test confirmation, cancellation, wrong Google account, stale session, offline state, 32-byte/43-character recovery-key validation, secure operation persistence, duplicate requests with the same key, pending/temporary/not-found status recovery, Storage/database/Auth ordering, failed cleanup finalization, strict same-user receipt, cloud success/local failure, restart recovery, web PKCE/state and `sessionStorage` handling without token persistence, exact CORS origins, and exported backups remaining outside app control.

### Monetization

Test every global/per-format runtime gate, generation invalidation, stale callbacks, retry classification/budgets/dormancy/jitter, the 55-minute boundary, exact-once leases, fullscreen serialization, native palette fallback, consent unavailable, no reward, pending claim, valid SSV, replay, invalid signature, wrong account, expiry, insufficient balance, duplicate charged creation, timeout after commit, and offline draft behavior.

### Backup and restore

Test valid current/historical backups, unsupported versions, path traversal, duplicate paths, oversized expansion, hash mismatch, insufficient storage, interrupted replacement, rollback, account mismatch, and sync restart.

### Notifications

Test the separation of user preference, OS/service/special-access state, scheduler truth, and effective capability. Include manual weather with denied location, service-disabled location, notification denial and disabled channel, exact preference off, exact denial with inexact fallback, settings-return refresh, time-zone change, reboot, application update, stale snapshots, completion rescheduling, and duplicate prevention.

### Startup and transient feedback

Test the first Flutter owner, fixed splash lifetime across startup/failure branch changes, non-blank fallback, English and Arabic semantics, compact/large-text layout, interaction blocking, and no repeating animation under reduced motion. For settings, exercise narrow English and Arabic layouts with scaled text, especially capability status and recovery actions. For feedback, test protected Undo ordering, exact-key batching, visible counts and deadline reset, LIFO Undo, FIFO finalization, exactly-once callbacks, accessible persistence, callback failure, directional layout, one visual gap above real Scaffold bottom navigation and floating actions, feedback above modal-sheet barriers, and all Trash restoration call sites. Schema migration coverage must preserve tasks and remaining metadata while removing retired dependency links. Native-ad contract coverage must enumerate every routed content placement and verify the shared light/dark surface palette. Sync gateway coverage guards the zero-row list-response path that avoids expected PostgREST 406 warnings without weakening revision checks.

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
