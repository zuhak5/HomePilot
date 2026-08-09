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

## In-app deletion sequence

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

## Browser deletion sequence

The public account-deletion page is a separate, remote-only client of the same protected backend. Its executable contract is [`download-site/account-deletion.js`](../../download-site/account-deletion.js); it does not reuse a session from an installed HomePilot application.

1. The production static-site build injects the public Supabase URL, public publishable/anonymous key, and canonical callback URL. If that public configuration is missing, disabled, malformed, or points elsewhere, the page keeps sign-in disabled and reports that deletion is unavailable.
2. The page creates a random PKCE verifier and SHA-256 challenge. It keeps the verifier temporarily in `sessionStorage` so the OAuth callback can consume it; it does not store an access token or refresh token there.
3. The browser redirects to the Supabase Google authorization endpoint with the PKCE challenge and the exact canonical deletion-page callback.
4. On callback, the page removes OAuth parameters from the address bar, consumes and removes the verifier, exchanges the authorization code, and verifies the returned user through Supabase Auth.
5. The access token remains only in the current page's JavaScript memory. Reloading or closing the page requires a new Google sign-in.
6. The page shows a masked account identity and requires a separate permanent-deletion checkbox before enabling the destructive action.
7. The page sends `POST /functions/v1/delete-account` with the bearer token, public API key, and `{ "confirmation": "delete-my-account" }`.
8. Success is accepted only for a successful HTTP response whose JSON contains all three required values consistent with the verified account: `deleted` is `true`, `status` is `deleted`, and `user_id` equals the user ID returned by the authenticated-user lookup. Missing, malformed, pending, or mismatched receipts remain failures.
9. After a valid receipt, the page attempts local Supabase sign-out, discards its in-memory identity and token, and reports remote deletion complete without displaying backend identifiers.

The browser can remove the Supabase account, synchronized Postgres data, and private Supabase Storage handled by the backend. It cannot directly inspect or erase Drift data, media, notifications, secure storage, caches, or exported backups on an installed device. A subsequently opened installation must handle the revoked/deleted session and finish its ordinary local cleanup or recovery path. Therefore a successful browser receipt is evidence of remote deletion, not evidence that every device-local copy or user-exported backup was erased.

## Browser security boundaries

- The generated page receives only public Supabase configuration. Service-role credentials remain exclusively in the Edge Function environment.
- OAuth PKCE protects the authorization-code exchange; the access token is never written to persistent browser storage or logged.
- CORS limits which supported browser origins can read the function response, but it is not authorization. The Edge Function still derives the user from the verified bearer token, requires confirmation, and checks recent session state.
- The displayed identity is masked. Operators must not capture access tokens, OAuth codes, full email addresses, user IDs, or response bodies containing identifiers in smoke-test evidence.
- An offline account-deletion navigation fails with a network-required response. It must never receive the cached VersionDeck home page or claim deletion succeeded.

## Partial failure handling

### Reauthentication cancelled or wrong account

Do not call the deletion function. Restore ordinary account state without deleting data.

### Offline before backend deletion

Do not pretend deletion succeeded. Keep the account and local data intact, and allow retry after connectivity returns.

For the browser flow, an unavailable network or unreadable/mismatched receipt leaves the page in a retryable failure state. The browser must not infer completion from a redirect, a successful Google interaction, or an HTTP response alone.

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

Browser-focused coverage additionally verifies PKCE request construction, code exchange, authenticated-user lookup, exact receipt matching, best-effort sign-out, public-config rejection, confirmation gating, revisioned assets, service-worker isolation, allowed and denied CORS origins, and successful native requests without an `Origin` header. A hosted disposable-account test is still required because local tests cannot prove Google OAuth configuration, hosted Edge Function deployment, Auth deletion, Postgres cleanup, or private Storage cleanup.

## Privacy and support

Changes to authentication or deletion require updates to `PRIVACY.md`, support guidance, database tests, Edge Function tests, synchronization tests, and release notes where user behavior changes.
