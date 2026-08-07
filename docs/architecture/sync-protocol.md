# Offline-First Synchronization Protocol

## Purpose

HomePilot must accept useful local work without connectivity and later synchronize it without losing mutation intent, mixing accounts, duplicating charged or completion operations, or silently overwriting newer cloud state.

The implementation under `lib/src/core/sync/`, synchronized repositories, Drift synchronization tables, Supabase migrations, RPCs, and tests is authoritative.

## State model

The coordinator exposes states equivalent to:

- Disabled: synchronization is not configured or intentionally unavailable.
- Signed out: no authenticated cloud account is bound.
- Ready: initialized and able to schedule work.
- Initializing: account binding and local runtime preparation are in progress.
- Syncing: push, pull, reconciliation, or cleanup work is active.
- Offline: network-dependent work is deferred while local operation continues.
- Blocked: an authorization, account, conflict, or protocol condition requires intervention.
- Error: a recoverable or terminal failure is visible.

Hydration and realtime readiness have their own lifecycle and must not be collapsed into a single boolean.

## Account binding

Every synchronized local working set is associated with an authenticated account identity.

On sign-in or account transition, the coordinator must:

1. Resolve the current Supabase user.
2. Compare it with the locally bound identity.
3. Prevent pending work from a previous account being pushed under the new account.
4. Initialize or hydrate the correct account state.
5. Clear or quarantine incompatible runtime data through an explicit recovery path.

Never silently reassign local records between accounts.

## Local mutation path

A synchronized mutation should:

1. Validate domain behavior locally.
2. Apply the local database change transactionally.
3. Create a durable outbox operation with a stable operation identifier.
4. Record enough payload and revision context to retry after restart.
5. Notify local readers immediately.
6. Schedule synchronization when the environment permits.

The UI must not wait for network success to reflect valid offline-first changes, but it must show blocked or failed cloud state when that distinction matters.

## Push path

The push worker:

1. Selects eligible outbox work for the current account.
2. Orders operations when dependencies require it.
3. Sends an idempotent RPC or cloud mutation.
4. Distinguishes success, duplicate success, conflict, retryable failure, authorization failure, and terminal validation failure. Zero-row mutation updates returning PostgREST `PGRST116` (HTTP 406) due to revision mismatch or missing remote records are classified as sync conflicts and trigger canonical remote fetching.
5. Updates local revisions/shadows and removes or resolves the outbox entry transactionally.
6. Schedules targeted reconciliation when the cloud result differs from local assumptions.

A network timeout after a server commit must be safe to retry.

## Pull path

The pull worker:

1. Uses the account's cursor or checkpoint.
2. Reads bounded cloud changes in deterministic order.
3. Applies ownership and schema validation.
4. Compares remote revision, local row, shadow, and pending outbox intent.
5. Applies non-conflicting changes transactionally.
6. Records shadows and advances the cursor only after successful application.
7. Continues until the current window is drained.

Cursor advancement must not precede durable local application.

## Initial hydration

Initial hydration builds a trusted local view for a newly bound account. It must be restartable and must not present partial hydration as fully synchronized. Existing offline local work requires an explicit policy before cloud data is applied.

Hydration completion should be recorded independently from ordinary incremental synchronization.

## Realtime invalidation

Realtime events are wake-up or invalidation signals. They can trigger targeted or incremental pulls, but they should not bypass normal validation, revision comparison, ownership checks, or transactional application.

The system must tolerate dropped, duplicated, delayed, and out-of-order realtime events.

## Conflict handling

A conflict exists when local and cloud changes cannot be safely merged under the entity contract.

Conflict behavior must be entity-specific and visible in tests. Valid strategies include:

- Server-authoritative overwrite for protected server state.
- Local retry against a new revision.
- Field-aware merge where semantics are deterministic.
- Explicit blocked state requiring reconciliation.
- Compensating local correction after a rejected operation.

Do not treat a conflict as generic success and do not discard pending local work silently.

## Clock skew

Device clocks are not a sole source of truth for global ordering. Prefer server revisions, server timestamps, stable operation identifiers, and monotonic local sequencing. Time-based UI values may use device time, but synchronization correctness must tolerate skew.

## Maintenance completion

Maintenance completion affects history, recurrence, due state, reminders, statistics, and potentially multiple devices. Completion operations require stable idempotency keys. Maintenance completion timestamps (`completedAt`, `expectedNextDueDate`, `previousDueDate`, `nextDueDate`) MUST be canonicalized to whole-second UTC precision (`date_trunc('second', ...)` in SQL, `canonicalSyncSecond` in Dart) across Drift SQLite, outbox JSON payloads, and Supabase Postgres to eliminate sub-second precision mismatch rejections. If the server rejects or resolves a duplicate, local reminder and recurrence state must reconcile to the accepted cloud result rather than advance permanently from an unaccepted local assumption.

## Media synchronization

Media requires coordination between local metadata, file availability, Storage objects, upload state, and deletion cleanup.

- Uploads and deletes must be retryable.
- Metadata must not claim cloud availability before verification.
- Cleanup must not delete another account's object.
- Account deletion can suspend ordinary sync while allowing deletion-specific cleanup.
- Orphan cleanup should be bounded and observable without logging private object names.

## Retry and backoff

Retryable failures should use bounded exponential backoff with jitter and persistence where appropriate. Authorization, schema, ownership, and terminal validation errors should not spin indefinitely. User-visible state should distinguish offline waiting from protocol failure.

## Account deletion interaction

Before remote account deletion, normal synchronization is suspended to prevent new cloud writes. The deletion workflow then removes remote media and account state, records a verifiable result, and clears local data. If deletion succeeds remotely but local cleanup fails, restart recovery must finish local cleanup without attempting to resurrect the deleted cloud account.

## Required test matrix

Every protocol change should cover relevant combinations of:

- Online and offline mutation.
- Restart before push.
- Timeout after possible server commit.
- Duplicate operation.
- Stale local revision.
- Newer cloud revision.
- Concurrent changes from two devices.
- Realtime event missing or duplicated.
- Cursor-page failure and retry.
- Account switch with pending work.
- Revoked session.
- Hydration interruption.
- Media upload or delete failure.
- Maintenance completion conflict.
- Clock skew.
- Account deletion during queued work.

## Change checklist

A synchronized field or entity is incomplete until local schema, cloud schema, serialization, outbox, push, pull, shadows, revisions, hydration, realtime invalidation, conflict behavior, retry, account binding, backup, deletion, and tests are all addressed.