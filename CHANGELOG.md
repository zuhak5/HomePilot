# Changelog

HomePilot uses Git history, pull requests, and GitHub Releases as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`. Released versions may be recorded below after their version and build numbers have been finalized.

## Unreleased

### Changed

- Added a mandatory documentation-maintenance policy for humans, AI agents, bots, and Agent Skills.
- Required every change and pull request to report documentation impact, update affected documents in the same branch, and identify any unverified documentation claims.
- Added a pull-request template with documentation, validation, privacy, synchronization, and release-impact checks.

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
