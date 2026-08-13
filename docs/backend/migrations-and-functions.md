# Backend Migrations and Edge Functions

> **Hosted mutation containment is active.** The Supabase migration workflow,
> the secret-bearing Advisor paths, and retained legacy repository-write
> workflow objects have been disabled since 2026-08-11. Local validation is
> still allowed, but no hosted migration or function deployment is authorized.
> See the [TASK-001 containment record](../operations/production-containment.md)
> before any rail is re-enabled.

## Migration policy

Supabase SQL migrations are ordered, append-only production history. Once a migration may have been applied outside a disposable local environment, do not edit it to change behavior. Add a new forward migration.

Each migration should be:

- Transactional where supported.
- Idempotent only where repeated execution is intentionally safe.
- Explicit about ownership, constraints, indexes, defaults, and nullability.
- Backward-compatible with the currently released mobile client when rollout order requires it.
- Accompanied by database tests.
- Reviewed for synchronization and account deletion.

## Migration workflow

1. Inspect all prior migrations affecting the objects.
2. Define the desired schema and compatibility window.
3. Write a new timestamped migration.
4. Add constraints and indexes deliberately.
5. Add or update RLS policies.
6. Add database tests for success and denial.
7. Run local lint and tests.
8. Inspect the generated database diff where available.
9. Document deployment order and recovery.
10. Apply to hosted environments only through an explicitly authorized process.

Active TASK-001 containment is not such authorization. The owning later task
must identify the exact target, change, operator, split GitHub environment,
release attempt ID, and protection prerequisites.

## Destructive changes

Avoid dropping columns, tables, policies, or functions in the same rollout that removes client use. Prefer expand-and-contract:

1. Add the new representation.
2. Deploy compatible backend behavior.
3. Release clients that write/read the new representation.
4. Backfill and verify.
5. Stop old writes.
6. Remove obsolete structures in a later reviewed migration.

## Database tests

Test:

- Authenticated owner success.
- Cross-user denial.
- Anonymous denial.
- Invalid input and boundary conditions.
- Constraint enforcement.
- Idempotent duplicate behavior.
- Stale revision or conflict behavior.
- Account deletion cleanup.
- Point and reward conservation where applicable.

## Edge Function inventory

### `delete-account`

Requires a valid JWT and protects destructive account cleanup. It verifies confirmation, recent session state, and a 32-byte recovery key; stores only SHA-256-derived recovery values; removes private media with retry handling; signs out sessions; deletes the Auth user; and records/returns a strict result suitable for client recovery.

### `account-deletion-status`

Recovers a deletion operation when the authenticated destructive response can no longer be trusted or retrieved. It validates the original recovery key and expected user ID, performs a hash- and subject-bound service-role lookup, can finalize an operation whose Auth user is already absent, and returns only strict completed, pending, temporary, or not-found states. It never treats a client user ID alone as authority.

### `admob-ssv-handler`

Receives Google Mobile Ads server-side verification callbacks. It validates provider request/signature data, associates an opaque claim with the intended account, prevents replay, and credits the wallet idempotently. The function is externally callable for provider callbacks and must not trust request identity without cryptographic and backend checks.

## Function engineering rules

- Validate method, content type, query/body schema, size, and required headers.
- Keep secrets in the Supabase function environment.
- Use bounded timeouts and retries for external or Storage work.
- Make repeated requests safe.
- Return stable technical errors without leaking internals.
- Do not log tokens, signatures, direct identifiers, user content, signed URLs, or raw payloads.
- Test malformed, unauthorized, replayed, expired, and partial-failure paths.

## Deno validation

The backend and Android release workflows enforce locked `deno fmt --check`, `deno check --frozen`, and `deno test --frozen` commands for `admob-ssv-handler`, `delete-account`, and `account-deletion-status`. Passing them validates committed source contracts only; it does not prove which revision or secrets are deployed to a hosted project.

## Account-deletion recovery operations

[`20260809120000_add_account_deletion_recovery.sql`](../../supabase/migrations/20260809120000_add_account_deletion_recovery.sql) adds a private service-role-only operation table for ambiguous deletion recovery. It stores a unique request hash, a subject binding, the active user UUID only while needed, bounded stage/error metadata, timestamps, and a seven-day default expiry. Row Level Security is enabled without client policies; the later hosted-Advisor cleanup adds an explicit service-role policy without granting client access. Completion clears the active user UUID, and a scheduled hourly prune at minute 17 removes expired rows. [`0014_account_deletion_recovery.test.sql`](../../supabase/tests/database/0014_account_deletion_recovery.test.sql) checks the schema, privileges, RLS, completion behavior, and pruning contract.

## Deployment evidence

Production migration workflow source uses the `production-supabase-migrations`
environment with `SUPABASE_MIGRATION_ACCESS_TOKEN` and
`SUPABASE_MIGRATION_DB_PASSWORD`. Hosted evidence must still prove those names
exist only in that environment and are not pooled with Advisor or signing
credentials; see the [GitHub environment credential ownership runbook](../operations/github-environment-credential-ownership.md).

The workflow also requires a `release_attempt_id` shaped like `hpra_<32 lowercase hex characters>` alongside the exact current `main` SHA, project ref, and `apply-pending-migrations` confirmation. This binds hosted migration mutation to the release attempt ledger described in the [release attempt ledger runbook](../operations/release-attempt-ledger.md). A syntactically valid attempt ID is not, by itself, hosted deployment approval or proof that the backend aggregate passed; retain the dry-run ledger evidence and protected workflow approvals in the release record.

Record migration identifiers, function versions/source commits, local test results, hosted target, deployment operator, compatibility assumptions, and any required mobile release ordering.
