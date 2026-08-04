# Backend Migrations and Edge Functions

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

Requires a valid JWT and protects destructive account cleanup. It verifies confirmation and recent session state, removes private media with retry handling, signs out sessions, deletes the Auth user, and returns/records a result suitable for client recovery.

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

Canonical Deno commands should be established from the function import maps and lock files, then added to CI. Until those commands are verified, do not claim Edge Functions are fully validated solely because database tests pass.

## Deployment evidence

Record migration identifiers, function versions/source commits, local test results, hosted target, deployment operator, compatibility assumptions, and any required mobile release ordering.