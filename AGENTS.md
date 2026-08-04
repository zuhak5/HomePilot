# AGENTS.md

## Purpose

This file defines repository-wide instructions for coding agents and automated contributors working on HomePilot. Follow the user's request, then this file, then the nearest more-specific repository instructions. Detailed architecture belongs in `docs/`; task-specific reusable workflows belong in project Agent Skills.

## Project summary

HomePilot is an Android-first Flutter application for household asset organization and maintenance. It uses Riverpod and GoRouter, an offline-first Drift database, authenticated Supabase synchronization, local notifications and background work, Google sign-in, Google Mobile Ads with server-verified rewards, privacy-preserving Sentry observability, protected Android release automation, and the VersionDeck download site.

## Repository map

- `lib/`: Flutter application, domain services, repositories, synchronization, monetization, authentication, backup, and generated localization.
- `test/`: Flutter unit and widget tests.
- `integration_test/`: Flutter integration tests.
- `android/`: Android host application, permissions, flavors, and release guards.
- `supabase/`: local Supabase configuration, SQL migrations, database tests, and Edge Functions.
- `download-site/`: VersionDeck source.
- `tool/`: production build, Sentry, validation, and VersionDeck tooling.
- `.github/workflows/`: validation, production build, and VersionDeck deployment.
- `config/`: safe examples; real configuration files are ignored.
- `docs/`: canonical project documentation.

## Sources of truth

Use executable sources before prose when they conflict:

1. Tests and security assertions.
2. Current implementation.
3. SQL migrations, RLS policies, RPC definitions, and Edge Functions.
4. CI workflows and build scripts.
5. `pubspec.yaml`, `package.json`, `supabase/config.toml`, Gradle files, and example configuration.
6. Documentation.

Do not copy mutable versions, ports, route lists, permissions, or workflow commands into new files without linking to their authoritative source.

## Non-negotiable safety rules

- Never commit secrets, production configuration, signing material, tokens, private user data, database exports, or service-role credentials.
- Never place a Supabase service-role credential in Flutter code or a distributable configuration file.
- Never disable Row Level Security to make a feature work.
- Never run destructive linked Supabase operations unless the user explicitly requests the exact operation and target.
- Never trigger production signing, release publication, public deployment, Sentry release mutation, or protected workflows without explicit authorization.
- Never force-push, discard unrelated work, run destructive reset or clean commands, or rewrite history without explicit authorization.
- Never edit generated Drift or localization output manually.
- Never weaken tests, package verification, signer verification, provenance, privacy scrubbing, account-deletion authorization, or reward verification merely to pass validation.
- Preserve user changes and keep each change task-scoped.

## Standard work protocol

### Before editing

1. Read this file and relevant documents in `docs/`.
2. Inspect repository status and identify unrelated changes.
3. Locate the implementation, tests, generated files, configuration, migrations, and workflows for the target subsystem.
4. Identify data-integrity, synchronization, privacy, security, permission, backup, and release implications.
5. Choose the smallest complete change.

### During editing

- Preserve existing architectural boundaries.
- Add or update tests with behavior changes.
- Localize all user-visible strings in English and Arabic.
- Check RTL behavior for layout changes.
- Avoid logging user content, direct identifiers, location, tokens, media paths, or raw requests.
- Keep server-authoritative decisions on the server.
- Use additive migrations unless an explicitly approved destructive migration is required.
- Update documentation when contracts, commands, permissions, data handling, or operations change.

### Before completion

1. Regenerate required source files.
2. Format changed Dart source.
3. Run focused tests.
4. Run the broader relevant validation suite.
5. Inspect the final diff for generated noise, secrets, and unrelated changes.
6. Report checks executed, checks not executed, and protected validation still required.

## Generated files

### Drift

The source schema is the relevant `app_database.dart` implementation. Generated `*.g.dart` output must be refreshed with:

```powershell
dart run build_runner build
```

Do not manually patch generated database code.

### Localization

ARB files and `l10n.yaml` are the sources. Refresh generated localization with:

```powershell
flutter gen-l10n
```

Do not edit generated localization Dart files directly.

### VersionDeck

Treat generated manifests and static build output according to the scripts under `tool/`. Do not hand-author release verification results or publish unverified artifacts.

## Validation matrix

### Flutter and Dart

```powershell
flutter pub get
flutter gen-l10n
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Use focused tests first when iterating. Do not claim the complete Flutter suite passed unless every command actually ran successfully.

### Production configuration schema

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

This validates only the example configuration contract; it does not create or validate a real signed production release.

### Supabase

```powershell
npm ci
npm run supabase:lint
npm run supabase:test
```

The local Supabase service must be running. Use the ports in `supabase/config.toml`. Establish and document canonical Deno formatting, type-checking, and function-test commands before treating them as mandatory.

### VersionDeck

Follow `.github/workflows/deploy-download-site.yml` and `docs/versiondeck-release-runbook.md`. Run JavaScript syntax checks, all current focused Node tests, the static-site build, and `tool/validate_versiondeck.mjs`. Do not claim real APK, attestation, Pages, or public-manifest verification from local checks.

### Documentation

Verify internal links, referenced paths, commands, permissions, and configuration against the repository. Do not present assumptions as implemented behavior.

## Flutter and UI rules

- Use Riverpod for state and dependency management already represented by the project.
- Use GoRouter for navigation; do not add a competing router.
- Keep widgets focused and move business logic into services, repositories, or providers.
- Represent loading, empty, error, signed-out, offline, and blocked states explicitly.
- Preserve accessibility labels, text scaling, focus behavior, and touch-target sizing.
- Test English and Arabic where layout or text behavior changes.
- Do not expand permissions or background behavior without a product, privacy, and operations review.

## Local persistence rules

- Increment the Drift schema version for schema changes.
- Add migration coverage from the immediately previous schema and relevant older fixtures.
- Define behavior for existing rows, nullability, defaults, indexes, and rollback.
- Review synchronization, backup, restore, deletion, and account isolation for every persistent field.
- Preserve synchronization metadata tables and runtime state unless the protocol change explicitly requires modification.

## Synchronization rules

Synchronization is a data-integrity boundary. Preserve:

- Durable outbox intent across process restart.
- Account binding and prevention of cross-account attachment.
- Initial hydration and cursor correctness.
- Remote revision and conflict semantics.
- Retry classification, backoff, and idempotency.
- Realtime invalidation without treating realtime events as authoritative data payloads.
- Clock-skew handling.
- Maintenance-completion idempotency and reminder reconciliation.
- Media upload and cleanup consistency.
- Safe suspension and recovery during account deletion.

Do not silently discard local work, overwrite newer remote state, convert conflicts into success, or bypass the synchronization coordinator for synchronized domain mutations.

## Supabase rules

- Derive user ownership from the authenticated identity, not an untrusted client parameter.
- Keep private media in the private `user-media` bucket.
- Test owner access, cross-user denial, anonymous denial, and invalid inputs.
- Review `SECURITY DEFINER` functions for explicit authorization and safe `search_path` behavior.
- Make externally retried mutations idempotent.
- Use new forward migrations; never edit an already-applied production migration to change behavior.

## Authentication and account deletion

Production authentication is Google-based. Preserve same-identity reauthentication, secure session storage, sign-out behavior, account binding, and recovery from expired or revoked sessions.

Account deletion must remain a coordinated workflow: recent reauthentication, synchronization suspension, protected backend deletion, private-media cleanup, authentication-user deletion, receipt/status validation, and local cleanup. Test cancellation, wrong account, offline failure, cloud success with local failure, and restart during cleanup.

## Privacy, logging, and Sentry

- Do not send names, email addresses, user-entered text, room or asset names, maintenance details, location, media, tokens, or raw request/response bodies to Sentry.
- Preserve strict event scrubbing.
- Keep screenshots, session replay, view hierarchy, and raw HTTP body capture disabled unless a separately reviewed privacy decision explicitly changes policy.
- Use stable technical identifiers only when necessary and non-identifying.
- Review `PRIVACY.md` whenever data or third-party processing changes.

## Monetization rules

- Point balances, charged creation, and reward claims are server-authoritative.
- Device callbacks cannot directly credit rewards.
- Preserve SSV verification, opaque claims, replay protection, idempotency, cooldowns, and pending-claim recovery.
- Do not log ad verification signatures or credentials.
- Consent and ad unavailability must not corrupt core data.
- Offline charged creation must fail safely or remain an explicit unfinished draft; it must not appear completed without server confirmation.

## Notifications, permissions, and background work

- Ask for permissions in context and handle denial gracefully.
- Preserve exact-alarm and boot-restoration behavior only where needed for reminders.
- Do not introduce fine or background location without explicit approval and privacy documentation.
- Keep foreground-service declarations aligned with actual work.
- Test time-zone changes, reboot restoration, app updates, disabled notifications, and stale reminder snapshots.

## Backup and restore

Treat every imported archive as untrusted. Preserve:

- Format versioning.
- Manifest and hash validation.
- Path traversal prevention.
- Extraction size and entry limits.
- Schema compatibility checks.
- Pre-restore safety backup.
- Staged media replacement.
- Rollback on failure.
- Retention behavior.

Review backup inclusion whenever persistent data changes. Account deletion does not remove backups exported outside the application.

## VersionDeck rules

VersionDeck is an independent release-verification and download surface. Preserve:

- APK digest, package, version, build, signer, ancestry, and provenance verification.
- Separation between live build-status information and verified stable-release identity.
- Fail-closed download behavior for missing, invalid, or stale metadata.
- Service-worker revisioning and cache-state correctness.
- Accessibility and reduced-motion behavior.
- No public GitHub token or release secret in static assets.

Never publish an APK because release notes claim it is valid; verification must derive from the artifact and trusted release metadata.

## Release workflow rules

- Keep workflow permissions minimal.
- Preserve protected environment and `main` guards.
- Preserve signing restoration, configuration validation, package/version/build checks, non-debuggable verification, signer verification, checksum generation, Sentry publication, provenance, and GitHub Release steps.
- Do not make production release commands part of normal local development documentation.
- Clearly separate locally validated behavior from CI-only and protected-environment evidence.

## Documentation requirements

Update documentation when changing:

- Routes, features, architecture, data models, or synchronization contracts.
- Configuration keys or local ports.
- Permissions, background work, external SDKs, privacy behavior, or retention.
- Migrations, RPCs, RLS, Storage, or Edge Functions.
- Authentication or account deletion.
- Monetization or reward authority.
- Backup format or restore behavior.
- Build, release, Sentry, VersionDeck, or operational procedures.

Prefer stable explanations and links to executable sources over copied mutable values.

## Definition of done

A change is complete only when:

- The requested behavior is implemented without unrelated edits.
- Relevant tests are added or updated.
- Generated files are current.
- Formatting, analysis, and relevant test suites have passed or failures are disclosed.
- Data, sync, privacy, security, permissions, backup, and release impacts are reviewed.
- Documentation is updated.
- No secrets or private data are introduced.
- The final report distinguishes local evidence from CI, device, hosted, and protected-environment validation.