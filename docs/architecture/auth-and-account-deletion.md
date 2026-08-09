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
5. Generate a cryptographically secure 32-byte recovery key, encode it as 43-character unpadded base64url, and persist it with the expected Supabase user ID in secure platform storage before the destructive request.
6. Call the protected `delete-account` Edge Function with the current JWT, required confirmation, and that recovery key.
7. The function validates authentication, confirmation, recent session state, and the recovery-key schema. It stores only hashes and operation state, never the raw recovery key.
8. The backend removes private media with bounded retries, performs global sign-out, and deletes the Supabase Auth user.
9. The backend records a recoverable operation state and returns the strict deletion receipt when completion is known.
10. If the destructive response is lost, malformed, or otherwise ambiguous, the client queries `account-deletion-status` with the same recovery key and expected user ID. It never creates a replacement key for the same operation.
11. The client accepts completion only when `deleted` is `true`, `status` is `deleted`, and `user_id` equals the expected user ID, then completes local database, media, session, notification, cache, provider, and recovery-record cleanup.
12. Pending or temporarily unavailable status keeps synchronization suspended and the secure recovery record intact. A definitive `recovery_not_found` clears the stale recovery record and safely cancels the barrier without claiming deletion.
13. Restart recovery resumes status lookup and finishes local cleanup when cloud deletion succeeded but the client stopped before completion.

## Browser deletion sequence

The public account-deletion page is a separate, remote-only client of the same protected backend. Its executable contract is [`download-site/account-deletion.js`](../../download-site/account-deletion.js); it does not reuse a session from an installed HomePilot application.

1. The production static-site build injects the public Supabase URL, public publishable/anonymous key, and canonical callback URL. If that public configuration is missing, disabled, malformed, or points elsewhere, the page keeps sign-in disabled and reports that deletion is unavailable.
2. The page creates a random PKCE verifier and SHA-256 challenge. It keeps the verifier temporarily in `sessionStorage` so the OAuth callback can consume it; it does not store an access token or refresh token there.
3. The browser redirects to the Supabase Google authorization endpoint with the PKCE challenge and the exact canonical deletion-page callback.
4. On callback, the page removes OAuth parameters from the address bar, consumes and removes the verifier, exchanges the authorization code, and verifies the returned user through Supabase Auth.
5. The access token remains only in the current page's JavaScript memory. Reloading or closing the page requires a new Google sign-in, but a pending deletion operation can still be recovered without restoring a bearer token.
6. The page shows a masked account identity and requires a separate permanent-deletion checkbox before enabling the destructive action.
7. Immediately before the first destructive request, Web Crypto generates a 32-byte recovery key encoded as 43-character unpadded base64url. The page stores only that key and the expected user ID in `sessionStorage` for the pending operation.
8. The page sends `POST /functions/v1/delete-account` with the bearer token, public API key, and `{ "confirmation": "delete-my-account", "recovery_key": "<43-character base64url value>" }`.
9. Success is accepted only for a successful HTTP response whose JSON contains all three required values consistent with the verified account: `deleted` is `true`, `status` is `deleted`, and `user_id` equals the user ID returned by the authenticated-user lookup.
10. A reload or ambiguous deletion response queries `POST /functions/v1/account-deletion-status` with the saved `recovery_key` and `expected_user_id`. Pending and temporary results preserve the operation; a strict matching receipt completes it; a definitive `recovery_not_found` clears it without reporting success. The same key is reused throughout one operation.
11. After a valid receipt, the page removes the recovery record, attempts local Supabase sign-out when a token is still available, discards its in-memory identity and token, and reports remote deletion complete without displaying backend identifiers.

The browser can remove the Supabase account, synchronized Postgres data, and private Supabase Storage handled by the backend. It cannot directly inspect or erase Drift data, media, notifications, secure storage, caches, or exported backups on an installed device. A subsequently opened installation must handle the revoked/deleted session and finish its ordinary local cleanup or recovery path. Therefore a successful browser receipt is evidence of remote deletion, not evidence that every device-local copy or user-exported backup was erased.

## Browser security boundaries

- The generated page receives only public Supabase configuration. Service-role credentials remain exclusively in the Edge Function environment.
- OAuth PKCE protects the authorization-code exchange; the access token is never written to persistent browser storage or logged. `sessionStorage` contains only the short-lived PKCE verifier and, while deletion is unresolved, the recovery key plus expected user ID.
- The recovery key is a capability secret. It is never placed in a URL, log, Sentry event, retained smoke-test evidence, or distributable configuration, and the backend stores only SHA-256-derived values.
- CORS limits which supported browser origins can read the function response, but it is not authorization. The Edge Function still derives the user from the verified bearer token, requires confirmation, and checks recent session state.
- The displayed identity is masked. Operators must not capture access tokens, OAuth codes, full email addresses, user IDs, or response bodies containing identifiers in smoke-test evidence.
- An offline account-deletion navigation fails with a network-required response. It must never receive the cached VersionDeck home page or claim deletion succeeded.

## Partial failure handling

### Reauthentication cancelled or wrong account

Do not call the deletion function. Restore ordinary account state without deleting data.

### Offline before backend deletion

Do not pretend deletion succeeded. Keep the account and local data intact, and allow retry after connectivity returns.

For either client, an unavailable network or unreadable/mismatched deletion response keeps the recovery operation intact and triggers or permits status recovery with the same key. The browser must not infer completion from a redirect, a successful Google interaction, or an HTTP response alone.

### Remote cleanup partially fails

The backend performs bounded cleanup and records a stage that can be queried safely. Repeated deletion and status requests with the same recovery key are idempotent; clients must not rotate the key to escape an ambiguous response.

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

Cover successful deletion, cancellation, wrong Google account, stale session, revoked session, offline start, recovery-key shape and secure persistence, same-key duplicate/status requests, pending/temporary/not-found status results, backend retry, private-media failure, cloud success/local failure, process restart, and pending synchronization work.

Browser-focused coverage additionally verifies PKCE request construction, code exchange, authenticated-user lookup, Web Crypto recovery-key generation, `sessionStorage` recovery without token persistence, same-key status recovery, exact receipt matching, best-effort sign-out, public-config rejection, confirmation gating, revisioned assets, service-worker isolation, allowed and denied CORS origins, and successful native requests without an `Origin` header. A hosted disposable-account test is still required because local tests cannot prove Google OAuth configuration, hosted Edge Function deployment, Auth deletion, Postgres cleanup, or private Storage cleanup.

## Privacy and support

Changes to authentication or deletion require updates to `PRIVACY.md`, support guidance, database tests, Edge Function tests, synchronization tests, and release notes where user behavior changes.
