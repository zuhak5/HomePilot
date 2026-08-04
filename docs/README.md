# HomePilot Documentation

This directory is the canonical entry point for product, architecture, development, operations, governance, and agent-workflow documentation.

## Product

- [`product/feature-catalog.md`](product/feature-catalog.md): user-visible capabilities and product boundaries.
- [`../PRIVACY.md`](../PRIVACY.md): data collection, storage, third parties, retention, and deletion.

## Architecture

- [`architecture/system-overview.md`](architecture/system-overview.md): major components and data flows.
- [`architecture/data-model.md`](architecture/data-model.md): local and cloud data domains.
- [`architecture/sync-protocol.md`](architecture/sync-protocol.md): offline-first synchronization model.
- [`architecture/auth-and-account-deletion.md`](architecture/auth-and-account-deletion.md): identity and deletion lifecycle.
- [`architecture/monetization.md`](architecture/monetization.md): ads, points, charged creation, and SSV.
- [`architecture/backup-and-restore.md`](architecture/backup-and-restore.md): archive format and restore safety.

## Development

- [`development/getting-started.md`](development/getting-started.md): workstation setup and local execution.
- [`development/testing.md`](development/testing.md): test strategy and commands.
- [`development/localization-and-rtl.md`](development/localization-and-rtl.md): English/Arabic localization and RTL requirements.

## Operations

- [`operations/release-runbook.md`](operations/release-runbook.md): protected Android release process.
- [`SENTRY_OPERATIONS.md`](SENTRY_OPERATIONS.md): Sentry configuration and incident workflow.
- [`versiondeck-release-runbook.md`](versiondeck-release-runbook.md): VersionDeck validation and deployment.
- [`versiondeck-live-build-status.md`](versiondeck-live-build-status.md): live build-status model and cache behavior.

## Reference

- [`reference/configuration.md`](reference/configuration.md): configuration sources and secret handling.
- [`reference/routes-and-permissions.md`](reference/routes-and-permissions.md): application routes and Android permissions.

## Decisions

- [`adr/0001-offline-first-sync.md`](adr/0001-offline-first-sync.md)
- [`adr/ADR-SENTRY-OBSERVABILITY.md`](adr/ADR-SENTRY-OBSERVABILITY.md)
- [`adr/0002-versiondeck-release-verification.md`](adr/0002-versiondeck-release-verification.md)

## Agent workflows

- [`agent-skills/README.md`](agent-skills/README.md): proposed skill catalog and installation model.
- [`agent-skills/source-policy.md`](agent-skills/source-policy.md): provenance and pinning rules.
- [`agent-skills/audit-checklist.md`](agent-skills/audit-checklist.md): security and compatibility review.
- [`agent-skills/update-runbook.md`](agent-skills/update-runbook.md): controlled update process.

## Documentation rules

- Implementation, tests, migrations, workflows, and configuration remain executable sources of truth.
- Link to mutable values instead of duplicating them where practical.
- Update documents in the same change as the behavior they describe.
- Mark planned behavior clearly; do not present a roadmap item as implemented.
- Archive superseded design plans under `docs/history/` instead of leaving conflicting operational instructions.
- Validate paths and commands before merging documentation changes.