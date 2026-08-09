# Documentation Reconstruction Record

## Context

The repository previously contained a root README, privacy documentation, Sentry operations guidance, a Sentry architecture decision record, and several VersionDeck plans/runbooks. Those files were removed on August 4, 2026 while active workflows and project complexity still depended on documented operational knowledge.

## Reconstruction approach

The documentation foundation was rebuilt from current executable sources rather than restoring deleted prose unchanged. Sources reviewed included:

- `pubspec.yaml`, `package.json`, `.metadata`, `l10n.yaml`, and analysis configuration.
- Flutter routes, models, services, repositories, authentication, synchronization, monetization, backup, notifications, and tests.
- Drift schema and migration tests.
- Supabase configuration, migrations, database tests, Storage, RPCs, and Edge Functions.
- Android manifest, Gradle configuration, flavors, and permissions.
- Flutter validation, production Android, and VersionDeck workflows.
- PowerShell and Node build/release tooling.
- Recent pull requests and release-oriented changes.

## Key corrections

- Version references were removed from prose where `pubspec.yaml` is the authoritative mutable value.
- The local Supabase development example was aligned with the API port in `supabase/config.toml`.
- Deleted Sentry and VersionDeck paths referenced by workflows were restored with current architecture and safety requirements.
- Documentation distinguishes implemented behavior, known validation gaps, and future governance work.
- The absence of a repository license is documented without selecting one on behalf of the owner.

## Canonical structure

The rebuilt documentation is organized into product, architecture, backend, development, operations, reference, decisions, governance, history, and agent-skill governance.

## Maintenance rule

Do not restore historical documents blindly. When an old path is needed for workflow compatibility, update the content against the current implementation or make it a clear pointer to the new canonical document.

Future behavior changes should update the relevant document in the same pull request. This record should not become an operational runbook.