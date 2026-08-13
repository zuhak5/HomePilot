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

`Release Attempt Dry Run` creates the canonical ledger and uploads `HomePilot-release-attempt-dry-run-<attempt_id>` after protected approval and backend aggregate validation. `Build Production APK`, `Build Play Store AAB`, and hosted migration workflows require both the attempt ID and the dry-run workflow run ID, restore that retained ledger, and verify it is still `prerequisites_verified` for the exact repository and source SHA before any protected work can continue.

Downstream mutation workflows must receive or derive the same release attempt ID:

- `Build Production APK` requires `release_attempt_id` and `release_attempt_run_id`, advances the restored ledger to `artifact_verified` only after the APK digest and signer evidence are bound, and advances it to `published` only after the GitHub Release target and assets are verified.
- `Build Play Store AAB` requires `release_attempt_id` and `release_attempt_run_id`, advances the restored ledger to `artifact_verified` only after the AAB digest and upload-certificate evidence are bound, and retains the exact AAB attempt/digest/upload-signer handoff for manual Play Console work.
- `Deploy Supabase Migrations` requires `release_attempt_id` and `release_attempt_run_id` in addition to `source_sha`, `project_ref`, and explicit confirmation. It revalidates the restored dry-run ledger before the dry run, again immediately before `supabase db push --linked`, then records `mutation_started`, `published`, and `externally_verified` evidence as the hosted state changes and no-pending verification complete.
- `Deploy VersionDeck` requires `release_attempt_id` on manual recovery dispatch and derives it from the upstream APK run's retained release-attempt artifact on `workflow_run`.
- The Pages build job revalidates the attempt, source, and generated manifest immediately before Pages artifact upload. The Pages deployment job checks out the exact source again and refuses to deploy without the same valid attempt ID and current-`main` SHA.
- The APK Sentry release job verifies the `artifact_verified` ledger before release mutation. A later Sentry deploy marker is created only after the GitHub Release job verifies the published release and advances the ledger to `published`.

These checks bind the rails to a single attempt identity. They do not prove that a hosted environment reviewer approved a job, that a protected secret exists, that an artifact was signed, that Sentry or Pages mutated successfully, or that a public endpoint reflects the new state.

## Protected Dry Run

`Release Attempt Dry Run` is the Task 06/07 evidence workflow. It accepts the backend validation run ID, recreates the attempt identity after `production-github-release` approval, validates the exact named backend aggregate, advances the attempt to `prerequisites_verified`, proves negative mutation-boundary fixtures for mismatched, incomplete, missing-evidence, and invalid-transition ledgers, and uploads `HomePilot-release-attempt-dry-run-<attempt_id>`.

The dry run performs no production signing, Sentry release mutation, GitHub Release publication, Supabase deployment, Pages deployment, Play upload, or artifact build. A successful dry run proves only the attempt identity, protected approval boundary, exact-source recheck, and named backend aggregate behavior for that commit.

## Failure Handling

- If the backend aggregate is missing, skipped, stale, duplicated, renamed, or from the wrong event/ref/SHA, stop before any protected mutation.
- If source changes after the attempt is created, create a new attempt at the new current `main` SHA and restart evidence collection.
- If a mutation starts and later fails, record the attempt state and partial external state instead of retrying under a different identity.
- If a downstream workflow lacks a valid attempt ID, treat it as unauthorized even when the upstream workflow conclusion is `success`.
- If a retry is needed after `artifact_verified`, restore the same attempt ledger and require the bound artifact digest to match the retained artifact before repeating Sentry, attestation, GitHub Release, Pages, Play handoff, or migration recovery work.
- If GitHub Release publication succeeds, create at most one Sentry deploy marker for the same release/attempt/environment. The deploy step lists existing deploys by deterministic name and environment before creating one, so retries reconcile instead of duplicating deploy evidence.
- If Supabase migration apply starts but no-pending verification does not finish, treat the hosted project as partially mutated. Resume with the same attempt and record whether the already-applied migration state is reconciled to `externally_verified`, superseded by a later attempt, or failed with explicit operator evidence.
- If an attempt is superseded, preserve the old ledger and create a new attempt at the new current `main` SHA. Do not reuse a superseded attempt for a different artifact, migration target, or public deployment.

Never edit retained ledger JSON, fabricate an attempt ID, or merge evidence from multiple attempts into one release record.

## Task 06 Hosted Evidence

TASK-006 source changes merged to `main` in commit `7b7ae23640b3f5ad5e35e5a2e4d2a2e2fe517c42` through PR #42 on 2026-08-13. The required protected dry-run evidence was then collected on that exact SHA without production signing, Sentry mutation, GitHub Release publication, Supabase deployment, Pages deployment, or Play upload.

Backend aggregate:

- Workflow: `Validate Google Backend and Release Contracts`
- Run: `31710431362`
- URL: `https://github.com/zuhak5/HomePilot/actions/runs/31710431362`
- Event: `workflow_dispatch`
- Branch: `main`
- Source SHA: `7b7ae23640b3f5ad5e35e5a2e4d2a2e2fe517c42`
- Conclusion: `success`
- Required jobs: `Deno SSV tests`, `Google contract/static checks`, `Supabase database tests`, `Require current main Advisor source`, `Hosted Supabase Advisors`
- Advisor evidence artifact: `supabase-advisors-7b7ae23640b3f5ad5e35e5a2e4d2a2e2fe517c42`, artifact ID `9185411857`, expires `2026-08-27T14:41:28Z`

Protected release-attempt dry run:

- Workflow: `Release Attempt Dry Run`
- Run: `31711402040`
- URL: `https://github.com/zuhak5/HomePilot/actions/runs/31711402040`
- Event: `workflow_dispatch`
- Branch: `main`
- Source SHA: `7b7ae23640b3f5ad5e35e5a2e4d2a2e2fe517c42`
- Conclusion: `success`
- Attempt ID: `hpra_7db313dec918ab64a9c2d77daed89b88`
- Final dry-run state: `prerequisites_verified`
- Created-attempt artifact: `HomePilot-release-attempt-hpra_7db313dec918ab64a9c2d77daed89b88`, artifact ID `9185440417`, expires `2026-09-12T14:42:23Z`
- Protected dry-run evidence artifact: `HomePilot-release-attempt-dry-run-hpra_7db313dec918ab64a9c2d77daed89b88`, artifact ID `9185467678`, expires `2026-09-12T14:43:17Z`

The downloaded protected dry-run artifact was locally inspected. `release-attempt.prerequisites-verified.json` contained attempt ID `hpra_7db313dec918ab64a9c2d77daed89b88`, state `prerequisites_verified`, source SHA `7b7ae23640b3f5ad5e35e5a2e4d2a2e2fe517c42`, backend run `31710431362`, and the five required backend job names listed above.

After evidence collection, `Validate Google Backend and Release Contracts` and `Release Attempt Dry Run` were disabled again. As of the post-evidence workflow inventory, only `Validate Flutter` and Dependabot remained active; the Android signing, Sentry/GitHub Release, Supabase migration/advisor, VersionDeck, Play AAB, and release-attempt dry-run workflow objects were disabled.

This evidence proves the Task 06 source contract, exact-source backend aggregate, protected dry-run approval boundary, and rejection surface for incomplete or mismatched backend evidence. It does not prove production signing, release publication, hosted migration application, Pages publication, Play upload, public endpoint behavior, or device behavior.

## Task 07 Hosted Evidence

TASK-007 source changes merged to `main` in commit `a077dee0e9cfb46220ee848c854fa85ca66f6957` through PR #44 on 2026-08-13. The required protected dry-run evidence was then collected on that exact SHA without production signing, Sentry mutation, GitHub Release publication, Supabase migration apply, Pages deployment, or Play upload.

Backend aggregate:

- Workflow: `Validate Google Backend and Release Contracts`
- Run: `31715596729`
- URL: `https://github.com/zuhak5/HomePilot/actions/runs/31715596729`
- Event: `workflow_dispatch`
- Branch: `main`
- Source SHA: `a077dee0e9cfb46220ee848c854fa85ca66f6957`
- Conclusion: `success`
- Required jobs: `Deno SSV tests`, `Google contract/static checks`, `Supabase database tests`, `Require current main Advisor source`, `Hosted Supabase Advisors`
- Advisor evidence artifact: `supabase-advisors-a077dee0e9cfb46220ee848c854fa85ca66f6957`, artifact ID `9187118421`, expires `2026-08-27T15:29:28Z`

Protected release-attempt dry run:

- Workflow: `Release Attempt Dry Run`
- Run: `31715833390`
- URL: `https://github.com/zuhak5/HomePilot/actions/runs/31715833390`
- Event: `workflow_dispatch`
- Branch: `main`
- Source SHA: `a077dee0e9cfb46220ee848c854fa85ca66f6957`
- Conclusion: `success`
- Attempt ID: `hpra_d1c127e20f1a6c755742cbdbac0d4a88`
- Final dry-run state: `prerequisites_verified`
- Created-attempt artifact: `HomePilot-release-attempt-hpra_d1c127e20f1a6c755742cbdbac0d4a88`, artifact ID `9187191604`, expires `2026-09-12T15:31:20Z`
- Protected dry-run evidence artifact: `HomePilot-release-attempt-dry-run-hpra_d1c127e20f1a6c755742cbdbac0d4a88`, artifact ID `9187204981`, expires `2026-09-12T15:31:42Z`

The downloaded protected dry-run artifact was locally inspected. `release-attempt.prerequisites-verified.json` contained attempt ID `hpra_d1c127e20f1a6c755742cbdbac0d4a88`, state `prerequisites_verified`, source SHA `a077dee0e9cfb46220ee848c854fa85ca66f6957`, backend run `31715596729`, and the five required backend job names listed above. The protected dry-run job also completed the task 07 negative mutation-boundary fixture step, proving mismatched attempt ID, mismatched source SHA, incomplete state, missing `apk_artifact` evidence, and invalid direct `prerequisites_verified` to `published` transition are rejected without production mutation.

After evidence collection, `Validate Google Backend and Release Contracts` and `Release Attempt Dry Run` were disabled again. As of the post-evidence workflow inventory, only `Validate Flutter` and Dependabot remained active; the Android signing, Sentry/GitHub Release, Supabase migration/advisor, VersionDeck, Play AAB, and release-attempt dry-run workflow objects were disabled.

This evidence proves the Task 07 source contract, exact-source backend aggregate, protected dry-run approval boundary, and ledger rejection surface for mutation-boundary prerequisites. It does not prove production signing, release publication, hosted migration application, Pages publication, Play upload, public endpoint behavior, or device behavior.
