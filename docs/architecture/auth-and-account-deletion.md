# Authentication and Account Deletion

## Authentication model

HomePilot production authentication is based on Google sign-in connected to Supabase Auth. Email-and-password sign-up is disabled in the committed local Supabase configuration.

The Flutter authentication layer is responsible for:

- Starting and cancelling Google sign-in.
- Exchanging Google identity for a Supabase session.
- Persisting session material through secure platform storage.
- Restoring and refreshing sessions.
- Exposing signed-in, signed-out, loading, and error states.
- Binding synchronization to the authenticated Supabase user.
- Handling expired, revoked, or invalid sessions without attaching data to another account.

## Identity invariants

- The Supabase user ID is the cloud ownership identity.
- Reauthentication for a destructive action must resolve to the same account.
- A local database bound to one account must not be pushed under another account.
- Sign-out must stop authenticated synchronization before local account cleanup.
- Authentication failures must not expose tokens or provider payloads in logs or Sentry.

## Sign-in sequence

1. User initiates Google sign-in.
2. Google returns an identity credential or the user cancels.
3. The app establishes a Supabase session.
4. Secure session storage is updated.
5. The synchronization coordinator resolves account binding.
6. Initial hydration or incremental synchronization begins.
7. UI reflects account and sync state independently.

A successful Google UI interaction is not sufficient if the Supabase session cannot be established.

## Sign-out sequence

1. Stop or suspend authenticated synchronization.
2. Cancel account-specific background work.
3. Sign out from Supabase and the Google provider as required by implementation.
4. Remove secure session material.
5. Apply the local account-data retention or cleanup policy.
6. Reset account-specific providers and diagnostic context.

Sign-out is not account deletion. Cloud data remains unless the deletion workflow succeeds.

## Account deletion goals

Account deletion must remove the authenticated cloud account and associated private data while preventing another Google identity, stale session, queued synchronization work, or partial cleanup from producing inconsistent results.

## Deletion sequence

1. Explain consequences and obtain explicit confirmation.
2. Require recent Google reauthentication.
3. Verify that the reauthenticated Google identity corresponds to the currently signed-in Supabase user.
4. Suspend normal synchronization and new account-scoped writes.
5. Call the protected `delete-account` Edge Function with the required confirmation and current JWT.
6. The function validates authentication, confirmation, and recent session state.
7. The backend removes private media with bounded retries.
8. The backend performs global sign-out and deletes the Supabase Auth user.
9. The backend records or returns a deletion status/receipt suitable for recovery.
10. The client verifies the result and completes local database, media, session, notification, cache, and provider cleanup.
11. Restart recovery finishes local cleanup when cloud deletion succeeded but the client stopped before completion.

## Partial failure handling

### Reauthentication cancelled or wrong account

Do not call the deletion function. Restore ordinary account state without deleting data.

### Offline before backend deletion

Do not pretend deletion succeeded. Keep the account and local data intact, and allow retry after connectivity returns.

### Remote cleanup partially fails

The backend should retry bounded cleanup or return a state that can be retried safely. Repeated requests must be idempotent.

### Auth user deleted but client cleanup fails

On restart, detect the completed remote deletion and finish local cleanup. Do not re-enable synchronization or recreate the account implicitly.

### Session expires during deletion

Fail closed. Require renewed authentication rather than weakening recent-session checks.

## Cleanup inventory

Review at least:

- Drift domain and synchronization tables.
- Local media and temporary files.
- Secure session storage.
- Pending notifications and reminder snapshots.
- Background work registrations.
- Cached profile, wallet, and monetization state.
- Sentry user/context information.
- Private Supabase Storage objects.
- Postgres domain and operational rows.
- Pending reward or cleanup records.
- Exported backups, which remain outside application control.

## Tests

Cover successful deletion, cancellation, wrong Google account, stale session, revoked session, offline start, backend retry, private-media failure, duplicate deletion request, cloud success/local failure, process restart, and pending synchronization work.

## Privacy and support

Changes to authentication or deletion require updates to `PRIVACY.md`, support guidance, database tests, Edge Function tests, synchronization tests, and release notes where user behavior changes.