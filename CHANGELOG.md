# Changelog

HomePilot uses Git history, pull requests, and GitHub Releases as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`. Released versions may be recorded below after their version and build numbers have been finalized.

## 1.4.0 (Build 25) — 2026-08-06

### Fixed and Improved

- **Database & Sync Contracts**: Aligned `user_settings_key_check` PostgreSQL constraint to include `permission_education_seen_v2`. Enforced pre-enqueue validation against Dart setting key allowlist (`userSettingSyncSpec`).
- **Composite Task Creation**: Extended `create_task_with_point_debit_impl` RPC to return canonical `plan` and `metadata` JSON. Implemented `acknowledgeTaskCreationComposite` in `LocalSyncStore` to apply canonical rows and clear outbox entries atomically without redundant POST attempts.
- **Batch Conflict Recovery**: Updated `writeNewBatch` handling in `SupabaseSyncGateway` and `SyncCoordinator` with `BatchWriteResult`. 23505 primary key conflicts fetch/merge canonical records directly instead of issuing second blind inserts.
- **Failed Mutation Diagnostics**: Implemented single-row `resolveFailedMutation` (`dismiss`, `retry`, `acknowledge`) and `exportFailedMutationDiagnostics()` with strict DLP PII scrubbing.
- **AdMob SSV Edge Function**: Updated setup probe response mode to `verified_debug_noop` with `credited: false` and `duplicate: false`.
- **Realtime Observability**: Added ephemeral process instance ID, channel lifecycle tracking, and active subscription count metrics.
- **Startup Performance**: Instrumented release-safe startup spans and added cold launch performance benchmarks.

## 1.3.9 (Build 24) — 2026-08-05

### Maintenance and governance

- Added a mandatory documentation-maintenance policy for humans, AI coding agents, automated agents, bots, and reusable Agent Skills.
- Required documentation-impact review and same-pull-request documentation updates for every repository change.
- Added a subsystem-to-document impact matrix covering application behavior, architecture, data, synchronization, Supabase, authentication, monetization, backups, permissions, observability, releases, VersionDeck, localization, testing, and agent workflows.
- Added a pull-request template requiring documentation, validation, privacy, synchronization, permission, compatibility, and release-impact reporting.
- Updated repository agent instructions, contributor guidance, documentation governance, and Agent Skill audit/update procedures.
- Chained VersionDeck deployment to successful protected production APK workflow completions while preserving independent release verification and manual/release recovery triggers.

### Compatibility

- No application runtime behavior changed.
- No database migration is required.
- No permissions, synchronization protocol, backup format, privacy behavior, or account behavior changed.
- No user action is required.
- Existing local data, accounts, settings, backups, and synchronization state remain compatible.

## 1.3.8 (Build 23) — 2026-08-04

### Improved

- Improved the VersionDeck live production-build experience on mobile devices.
- Grouped technical build steps into clearer, easier-to-read phases.
- Improved progress, ETA, freshness, and target-version information.
- Refined the build timeline with consistent completed, active, and upcoming states.
- Clearly separated the current stable APK from a newer build that is still in progress.
- Improved long-text wrapping, narrow-screen layouts, scrolling, accessibility, and reduced-motion support.

### Maintenance

- Reconstructed project documentation covering product behavior, architecture, synchronization, authentication, account deletion, monetization, backup and restore, Supabase, Sentry, testing, localization, privacy, releases, VersionDeck, and agent workflows.
- Added repository-level contribution, security, privacy, and agent operating policies.
- Added operational runbooks and architecture decision records for release verification, observability, and offline-first synchronization.
- Aligned the development Supabase example URL with the local API port declared in `supabase/config.toml`.

### Compatibility

- No database migration is required.
- No user action is required.
- Existing local data, accounts, settings, backups, and synchronization state remain compatible.

## Historical releases

For released versions, checksums, Android artifacts, and release notes, use GitHub Releases and the independently generated VersionDeck manifest. Earlier repository history includes the addition of authenticated Supabase synchronization, conflict recovery, account deletion, Sentry observability, points and advertising workflows, backup protections, and VersionDeck release verification.

## Maintenance rules

Add entries under `Unreleased` when a change is:

- User-visible.
- Security- or privacy-relevant.
- A data migration or compatibility change.
- A material synchronization or backend protocol change.
- A new or changed permission, SDK, external service, or operational dependency.
- A release, deployment, backup-format, VersionDeck trust-chain, documentation-governance, or agent-workflow change.

Do not add routine refactoring, formatting, generated-file refreshes, or test-only changes unless they materially affect contributors or operators.
