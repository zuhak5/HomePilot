# Supabase Backend

## Responsibilities

Supabase provides HomePilot's authenticated cloud layer:

- Google-backed Supabase Auth sessions.
- Postgres domain and operational tables.
- Row Level Security and ownership enforcement.
- RPCs for atomic or protected operations.
- Realtime invalidation.
- Private `user-media` Storage.
- Edge Functions for account deletion, deletion-status recovery, and AdMob server-side verification.

The committed local configuration is `supabase/config.toml`. SQL migrations are append-only history under `supabase/migrations/`; database tests are under `supabase/tests/database/`.

## Local environment

Install dependencies and start the stack:

```powershell
npm ci
npx supabase start
```

Use the API, database, Studio, mail, and analytics ports declared in `supabase/config.toml`. Development configuration must point to that API endpoint or an emulator-accessible equivalent.

Validate:

```powershell
npm run supabase:lint
npm run supabase:test
```

Do not link to or mutate a hosted project during ordinary local validation.

## Authentication

The local configuration enables Google as the external provider and disables email sign-up. Production authentication behavior depends on correctly configured Google OAuth clients, package identity, redirect behavior, and protected Supabase environment values.

Backend authorization must derive ownership from the authenticated JWT identity rather than trusting a user ID supplied by Flutter.

## Database and RLS

Every user-owned table should have explicit RLS policies for intended owner operations and denial tests for anonymous and cross-user access. Constraints and indexes should enforce invariants independently of client behavior.

Review `SECURITY DEFINER` functions carefully:

- Set a safe `search_path`.
- Authenticate and authorize inside the function.
- Minimize privileges and returned data.
- Validate inputs and bound resource use.
- Make externally retried mutations idempotent.

Never disable RLS to resolve an application error.

## RPCs

Use RPCs when an operation must be atomic or server-authoritative, including point debit plus entity creation, revision-aware mutation, protected cleanup, or idempotent completion.

RPC contracts should define:

- Authentication and ownership.
- Input schema and limits.
- Idempotency key behavior.
- Success and duplicate-success responses.
- Conflict and stale-revision responses.
- Retryable versus terminal errors.
- Server timestamp/revision semantics.
- Audit and privacy-safe diagnostics.

## Storage

The `user-media` bucket is private and limited to supported image MIME types and configured size limits. Object paths and policies must prevent cross-user access. Signed URLs, if used, are temporary credentials and must not appear in logs, Sentry, or public artifacts.

Media metadata, object creation, replacement, and cleanup should tolerate partial failure and retry without exposing or deleting another user's data.

## Realtime

Realtime is an invalidation mechanism, not a replacement for authenticated pull and revision checks. The client must tolerate dropped, duplicated, delayed, and out-of-order events.

## Edge Functions

Functions run in the Deno-based Supabase runtime and must validate all untrusted requests. Secrets belong in function environment configuration, not source or Flutter. Canonical locked formatting, type-checking, and unit-test commands are enforced by the backend and Android release workflows.

### `delete-account` HTTP contract

[`supabase/functions/delete-account/index.ts`](../../supabase/functions/delete-account/index.ts) is the shared remote-deletion authority for the installed application and the public browser page.

- `POST` is the only deletion method. The body must contain `{ "confirmation": "delete-my-account", "recovery_key": "<43-character base64url value>" }` and the `Authorization` header must contain the user's bearer token. The unpadded base64url value must decode to exactly 32 bytes.
- The function extracts the session ID from the JWT, verifies the user through Supabase Auth, and checks recent-session state. It never accepts a client-supplied user ID as ownership authority.
- It hashes the recovery key and a key/user binding before persistence. Raw keys, tokens, and direct identifiers are not logged.
- A successful response is HTTP `200` with `deleted: true`, `status: "deleted"`, and `user_id` set to the verified authenticated user. Browser code must match all three fields, including the verified user ID, before reporting success.
- Responses use `Cache-Control: no-store`. Failure responses expose stable technical error codes rather than raw requests, tokens, provider payloads, or user content.

The function's browser CORS allowlist is exact and contains only:

- `https://zuhak5.github.io`
- `http://localhost:4173`
- `http://127.0.0.1:4173`

An allowed `OPTIONS` preflight returns `204`, echoes that exact origin in `Access-Control-Allow-Origin`, varies on `Origin`, and permits `POST, OPTIONS` plus the `authorization`, `apikey`, `content-type`, and `x-client-info` request headers. A missing or non-allowlisted preflight origin is rejected. A non-preflight browser request with an unapproved `Origin` is rejected before authorization or body processing, and allowed browser origins receive readable CORS headers on both success and failure responses. Wildcard origins and credentialed cookies are not used.

Native Flutter HTTP requests normally have no `Origin` header. They continue through the full JWT, confirmation, recent-session, cleanup, and receipt checks, but receive no `Access-Control-Allow-Origin` header. Absence of `Origin` is compatibility behavior, not an authorization bypass.

### `account-deletion-status` HTTP contract

[`supabase/functions/account-deletion-status/index.ts`](../../supabase/functions/account-deletion-status/index.ts) recovers an operation after the destructive response or client process is lost.

- `POST` is the only status method. The body requires the original `recovery_key` and an `expected_user_id` UUID.
- The endpoint does not accept a bearer token as its authority because the Auth user may already be deleted. Possession of the high-entropy key is necessary but not sufficient: lookup and completion are also bound to the expected subject using SHA-256-derived values stored by the backend.
- It returns HTTP `200` only with the same strict deletion receipt, HTTP `202` for a pending stage, HTTP `503` for a temporary recovery failure, or HTTP `404` with `recovery_not_found` when no matching recoverable operation exists.
- If the recorded operation reached Auth deletion and the Auth user is already absent, status recovery can finalize the operation before returning the strict receipt.
- Responses are `no-store`; raw keys, bearer tokens, and user identifiers are never logged.

The status endpoint uses the same exact origin allowlist. Its allowed preflight headers are `apikey`, `content-type`, and `x-client-info`; it does not advertise `authorization` because status recovery is capability- and subject-bound rather than session-authorized. Native requests without `Origin` receive no CORS response header and still pass every request validation and binding check.

Focused local validation is:

```powershell
deno fmt --check supabase/functions/delete-account/index.ts supabase/functions/delete-account/index_test.ts supabase/functions/account-deletion-status/index.ts supabase/functions/account-deletion-status/index_test.ts
deno check --frozen supabase/functions/delete-account/index.ts supabase/functions/delete-account/index_test.ts supabase/functions/account-deletion-status/index.ts supabase/functions/account-deletion-status/index_test.ts
deno test --frozen supabase/functions/delete-account/index_test.ts supabase/functions/account-deletion-status/index_test.ts
```

These tests validate handler contracts with fakes. They do not deploy the function or prove hosted Auth, database, or Storage cleanup.

## Deployment

Deploy migrations and functions through an explicit reviewed process with environment confirmation, dry-run or diff evidence where available, backward compatibility, and rollback/forward-fix planning. Mobile and backend release order must be documented when contracts change.

The manual
[`deploy-supabase-migrations.yml`](../../.github/workflows/deploy-supabase-migrations.yml)
workflow is the production migration boundary. It requires the exact current
`main` SHA, an exact project-ref confirmation matching `SUPABASE_URL`, and the
literal confirmation `apply-pending-migrations`. The protected `production`
environment supplies `SUPABASE_URL`, `SUPABASE_ACCESS_TOKEN`, and
`SUPABASE_DB_PASSWORD`; the project-ref match is checked inside that protected
job before the CLI links to any project, and no credential belongs in repository
files or logs. The workflow lists remote migration state,
performs a dry run, applies only the ordinary pending migration set, and dry-runs
again. It intentionally never uses `--include-all`, seeds, roles, or migration
history repair. A migration-history mismatch is a hard stop for operator review.

## Hosted Advisors evidence

The manual [`audit-supabase-advisors.yml`](../../.github/workflows/audit-supabase-advisors.yml)
workflow queries both hosted Management API advisor families with a protected
`SUPABASE_ACCESS_TOKEN` that has `advisors_read`; the project comes from
`SUPABASE_PROJECT_REF` or the host in `SUPABASE_URL`. It uploads a sanitized
JSON report and fails closed on missing credentials, an unavailable/changed API,
an invalid response, or any security/performance finding at any level. The sole
allowed finding is the exact title `Leaked Password Protection Disabled`; every
other error, warning, or information finding fails the workflow. The Management
API advisor endpoints are experimental/deprecated, so an endpoint removal is an
explicit operator-visible failure rather than a false clean result.
The final-SHA manual dispatch of
[`validate-google-backend.yml`](../../.github/workflows/validate-google-backend.yml)
runs the same audit as a protected job, so Android release gates cannot reuse a
backend run that omitted hosted Advisor evidence.

[`20260809210000_address_hosted_advisor_findings.sql`](../../supabase/migrations/20260809210000_address_hosted_advisor_findings.sql)
addresses the final-SHA hosted audit without widening access: it adds an explicit
service-role-only policy to the private deletion-recovery table and retires nine
obsolete indexes reported unused by hosted statistics. The follow-up
[`20260809212000_restore_advisor_fk_indexes.sql`](../../supabase/migrations/20260809212000_restore_advisor_fk_indexes.sql)
retains the two full indexes required to cover live relationship foreign keys;
the two archive indexes required for Auth-user cascade cleanup also remain.
Database test `0015` fixes that exact policy/index contract in local resets and
CI.

For public browser deletion, apply [`20260809120000_add_account_deletion_recovery.sql`](../../supabase/migrations/20260809120000_add_account_deletion_recovery.sql), then deploy and verify compatible `delete-account` and `account-deletion-status` functions before publishing an enabled deletion page or compatible mobile client. `delete-account` requires `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`; status recovery requires `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Keep all of them only in protected function configuration. Then verify both production Pages preflights, intentionally disallowed origins, native no-`Origin` requests in a controlled test, ambiguous-response recovery with one unchanged key, and one disposable-account deletion. Evidence must record project/function identity, deployment version, HTTP status and CORS headers, strict receipt validation, Auth removal, Postgres cleanup, and private `user-media` cleanup without recording tokens, recovery keys, or direct user identifiers.

## Review checklist

For every backend change, review authentication, RLS, cross-user denial, indexes, constraints, idempotency, synchronization, offline retry, privacy, account deletion, backup, tests, observability, deployment order, and compatibility with the previous mobile release.

Before releasing Build 44 clients, apply
[`20260809193000_remove_task_dependencies.sql`](../../supabase/migrations/20260809193000_remove_task_dependencies.sql).
It replaces both point-debited creation implementations without the retired
dependency metadata and then drops that column. It does not remove or alter the
completion outbox's separate `depends_on_operation_id` causal-order field. The
same forward migration changes a depleted wallet from a raised
`INSUFFICIENT_POINTS` exception into a structured `insufficient_points` JSON
result before any entity, operation, wallet, or ledger write. This prevents an
expected product decision from appearing as a PostgREST HTTP 400 warning while
keeping point authority and atomicity on the server.
