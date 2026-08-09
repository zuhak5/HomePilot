# Supabase Backend

## Responsibilities

Supabase provides HomePilot's authenticated cloud layer:

- Google-backed Supabase Auth sessions.
- Postgres domain and operational tables.
- Row Level Security and ownership enforcement.
- RPCs for atomic or protected operations.
- Realtime invalidation.
- Private `user-media` Storage.
- Edge Functions for account deletion and AdMob server-side verification.

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

Functions run in the Deno-based Supabase runtime and must validate all untrusted requests. Secrets belong in function environment configuration, not source or Flutter. Establish canonical formatting, type-checking, unit-test, and local-invocation commands and keep them aligned with CI.

### `delete-account` HTTP contract

[`supabase/functions/delete-account/index.ts`](../../supabase/functions/delete-account/index.ts) is the shared remote-deletion authority for the installed application and the public browser page.

- `POST` is the only deletion method. The body must contain `{ "confirmation": "delete-my-account" }` and the `Authorization` header must contain the user's bearer token.
- The function extracts the session ID from the JWT, verifies the user through Supabase Auth, and checks recent-session state. It never accepts a client-supplied user ID as ownership authority.
- A successful response is HTTP `200` with `deleted: true`, `status: "deleted"`, and `user_id` set to the verified authenticated user. Browser code must match all three fields, including the verified user ID, before reporting success.
- Responses use `Cache-Control: no-store`. Failure responses expose stable technical error codes rather than raw requests, tokens, provider payloads, or user content.

The function's browser CORS allowlist is exact and contains only:

- `https://zuhak5.github.io`
- `http://localhost:4173`
- `http://127.0.0.1:4173`

An allowed `OPTIONS` preflight returns `204`, echoes that exact origin in `Access-Control-Allow-Origin`, varies on `Origin`, and permits `POST, OPTIONS` plus the `authorization`, `apikey`, `content-type`, and `x-client-info` request headers. A missing or non-allowlisted preflight origin is rejected. A non-preflight browser request with an unapproved `Origin` is rejected before authorization or body processing, and allowed browser origins receive readable CORS headers on both success and failure responses. Wildcard origins and credentialed cookies are not used.

Native Flutter HTTP requests normally have no `Origin` header. They continue through the full JWT, confirmation, recent-session, cleanup, and receipt checks, but receive no `Access-Control-Allow-Origin` header. Absence of `Origin` is compatibility behavior, not an authorization bypass.

Focused local validation is:

```powershell
deno fmt --check supabase/functions/delete-account/index.ts supabase/functions/delete-account/index_test.ts
deno check --frozen supabase/functions/delete-account/index.ts supabase/functions/delete-account/index_test.ts
deno test --frozen supabase/functions/delete-account/index_test.ts
```

These tests validate handler contracts with fakes. They do not deploy the function or prove hosted Auth, database, or Storage cleanup.

## Deployment

Deploy migrations and functions through an explicit reviewed process with environment confirmation, dry-run or diff evidence where available, backward compatibility, and rollback/forward-fix planning. Mobile and backend release order must be documented when contracts change.

For public browser deletion, deploy and verify the updated `delete-account` function before publishing an enabled deletion page. Confirm the hosted function retains `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` only in protected function configuration. Then verify the production Pages origin preflight, an intentionally disallowed origin, a native no-`Origin` request in a controlled test, and one disposable-account deletion. Evidence must record function/project identity, deployment version, HTTP status and CORS headers, receipt field validation, Auth removal, Postgres cleanup, and private `user-media` cleanup without recording tokens or direct user identifiers.

## Review checklist

For every backend change, review authentication, RLS, cross-user denial, indexes, constraints, idempotency, synchronization, offline retry, privacy, account deletion, backup, tests, observability, deployment order, and compatibility with the previous mobile release.
