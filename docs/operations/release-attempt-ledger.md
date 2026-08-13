# Release Attempt Ledger

## Purpose

The release attempt ledger is the immutable identity record for a protected HomePilot release or deployment attempt. It binds the exact source SHA, workflow file digest, workflow run identity, intended target environment, version/build metadata when applicable, and named evidence aggregates before any protected mutation can proceed.

The executable implementation is [`tool/release_attempt_ledger.mjs`](../../tool/release_attempt_ledger.mjs), covered by [`tool/release-attempt-ledger.test.mjs`](../../tool/release-attempt-ledger.test.mjs) and the release workflow source tests. Ledger IDs are opaque values shaped like `hpra_<32 lowercase hex characters>` and must be copied from workflow output or retained artifacts, not invented by operators.

## State Model

Schema version 1 supports these states:

- `created`
- `prerequisites_verified`
- `mutation_started`
- `artifact_verified`
- `published`
- `externally_verified`
- `failed`
- `superseded`
- `reconciled`

Allowed forward movement is enforced by the tool. A successful prerequisites check does not imply publication, and a failed or superseded attempt can only become reconciled through an explicit reconciliation record. Do not reuse an attempt ID for a different source SHA, workflow path, workflow run, target environment, version, build, or release tag.

## Backend Aggregate

Android release rails and the dry-run workflow require a backend validation aggregate from `Validate Google Backend and Release Contracts` for the exact source SHA. The aggregate is accepted only when the workflow run is:

- workflow name `Validate Google Backend and Release Contracts`
- workflow path `.github/workflows/validate-google-backend.yml`
- event `workflow_dispatch`
- branch `main`
- status `completed`
- conclusion `success`
- head SHA equal to the release attempt source SHA

The job set must be exact. Missing, skipped, neutral, failed, duplicated, renamed, or extra jobs fail closed. Version 1 requires these job names:

- `Deno SSV tests`
- `Google contract/static checks`
- `Supabase database tests`
- `Require current main Advisor source`
- `Hosted Supabase Advisors`

Push and pull-request backend runs are still useful validation, but they cannot authorize release attempts because the protected Advisor jobs are skipped outside manual dispatch.

## Workflow Binding

`Build Production APK`, `Build Play Store AAB`, and `Release Attempt Dry Run` create a ledger artifact named `HomePilot-release-attempt-<attempt_id>` before protected work. The Android rails then bind that same ID into their protected jobs and safe evidence context. The APK rail also requires the ID before Sentry and GitHub Release mutation.

Downstream mutation workflows must receive or derive the same release attempt ID:

- `Deploy Supabase Migrations` requires `release_attempt_id` in addition to `source_sha`, `project_ref`, and explicit confirmation.
- `Deploy VersionDeck` requires `release_attempt_id` on manual recovery dispatch and derives it from the upstream APK run's retained release-attempt artifact on `workflow_run`.
- The Pages deployment job refuses to deploy without a valid attempt ID.

These checks bind the rails to a single attempt identity. They do not prove that a hosted environment reviewer approved a job, that a protected secret exists, that an artifact was signed, that Sentry or Pages mutated successfully, or that a public endpoint reflects the new state.

## Protected Dry Run

`Release Attempt Dry Run` is the Task 06 evidence workflow. It accepts the backend validation run ID, recreates the attempt identity after `production-github-release` approval, validates the exact named backend aggregate, advances the attempt to `prerequisites_verified`, and uploads `HomePilot-release-attempt-dry-run-<attempt_id>`.

The dry run performs no production signing, Sentry release mutation, GitHub Release publication, Supabase deployment, Pages deployment, Play upload, or artifact build. A successful dry run proves only the attempt identity, protected approval boundary, exact-source recheck, and named backend aggregate behavior for that commit.

## Failure Handling

- If the backend aggregate is missing, skipped, stale, duplicated, renamed, or from the wrong event/ref/SHA, stop before any protected mutation.
- If source changes after the attempt is created, create a new attempt at the new current `main` SHA and restart evidence collection.
- If a mutation starts and later fails, record the attempt state and partial external state instead of retrying under a different identity.
- If a downstream workflow lacks a valid attempt ID, treat it as unauthorized even when the upstream workflow conclusion is `success`.

Never edit retained ledger JSON, fabricate an attempt ID, or merge evidence from multiple attempts into one release record.
