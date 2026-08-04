# Changelog

HomePilot uses Git history, pull requests, and GitHub Releases as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`; do not duplicate it here as a mutable heading.

## Unreleased

### Added

- Reconstructed project documentation covering product behavior, architecture, synchronization, development, privacy, testing, releases, Sentry, VersionDeck, and agent workflows.
- Added repository-level contribution, security, privacy, and agent operating policies.

### Changed

- Aligned the development Supabase example URL with the local API port declared in `supabase/config.toml`.

## Historical releases

For released versions, checksums, Android artifacts, and release notes, use GitHub Releases and the independently generated VersionDeck manifest. Earlier repository history includes the addition of authenticated Supabase synchronization, conflict recovery, account deletion, Sentry observability, points and advertising workflows, backup protections, and VersionDeck release verification.

## Maintenance rules

Add entries under `Unreleased` when a change is:

- User-visible.
- Security- or privacy-relevant.
- A data migration or compatibility change.
- A material synchronization or backend protocol change.
- A new or changed permission, SDK, external service, or operational dependency.
- A release, deployment, backup-format, or VersionDeck trust-chain change.

Do not add routine refactoring, formatting, generated-file refreshes, or test-only changes unless they materially affect contributors or operators.