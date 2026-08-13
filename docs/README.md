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
- [`development/github-actions-supply-chain.md`](development/github-actions-supply-chain.md): immutable Action ledger, source contract, and reviewed update ownership.
- [`development/localization-and-rtl.md`](development/localization-and-rtl.md): English/Arabic localization and RTL requirements.
- [`development/transient-feedback.md`](development/transient-feedback.md): protected Undo, batching, ordering, accessibility, and layout contracts for transient feedback.

## Operations

- [`operations/production-containment.md`](operations/production-containment.md): active TASK-001 production pause, redacted evidence, and rail-specific re-enable ownership.
- [`operations/github-source-and-tag-protection.md`](operations/github-source-and-tag-protection.md): active partial TASK-002 `main`/tag rules, executed denial evidence, authority policy, and unresolved tag-creation blocker.
- [`operations/github-environment-credential-ownership.md`](operations/github-environment-credential-ownership.md): split GitHub environment, reviewer, branch-policy, and credential-domain contract.
- [`operations/github-hosted-policy-and-exposure.md`](operations/github-hosted-policy-and-exposure.md): hosted Actions allowlist/SHA policy, policy probes, audit coverage limits, and credential-domain exposure disposition.
- [`operations/release-attempt-ledger.md`](operations/release-attempt-ledger.md): immutable release attempt identity, named backend aggregate, dry-run evidence, and downstream mutation binding.
- [`operations/release-runbook.md`](operations/release-runbook.md): protected standalone APK, GitHub Release, and VersionDeck release process.
- [`operations/google-play-release-runbook.md`](operations/google-play-release-runbook.md): verified AAB evidence and the separately authorized Google Play handoff.
- [`operations/google-play-data-safety-evidence.md`](operations/google-play-data-safety-evidence.md): release-scoped Data safety evidence worksheet and operator-owned gaps.
- [`SENTRY_OPERATIONS.md`](SENTRY_OPERATIONS.md): Sentry configuration and incident workflow.
- [`versiondeck-release-runbook.md`](versiondeck-release-runbook.md): VersionDeck validation and deployment.
- [`versiondeck-live-build-status.md`](versiondeck-live-build-status.md): live build-status model and cache behavior.

## Reference

- [`reference/configuration.md`](reference/configuration.md): configuration sources and secret handling.
- [`reference/routes-and-permissions.md`](reference/routes-and-permissions.md): application routes and Android permissions.

## Governance

- [`governance/documentation-maintenance.md`](governance/documentation-maintenance.md): mandatory same-change documentation policy for humans, AI agents, bots, and Agent Skills.
- [`governance/license-decision.md`](governance/license-decision.md): current licensing decision status.

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
- Every AI agent, bot, and automated contributor must perform and report a documentation-impact review under [`governance/documentation-maintenance.md`](governance/documentation-maintenance.md).
- When no documentation change is required, state which documents were reviewed and why they remain accurate.
- Mark planned behavior clearly; do not present a roadmap item as implemented.
- Archive superseded design plans under `docs/history/` instead of leaving conflicting operational instructions.
- Validate paths and commands before merging documentation changes.
