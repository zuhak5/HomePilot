# Account Deletion

HomePilot account deletion is an authenticated, server-authoritative operation.
The Flutter client never receives or embeds the Supabase service-role key.

## Flow

1. The account screen presents an explicit destructive confirmation that lists
   cloud data, private media, local app data, and app-private backups.
2. The client authenticates with Google again and verifies that the resulting
   Supabase user is the same user who initiated deletion.
3. The client invokes `delete-account` with a fixed confirmation payload. The
   Edge Function validates the JWT through Auth and takes the target user ID
   only from that verified identity.
4. A service-role-only database function verifies that the JWT's `session_id`
   belongs to that user and was created within the previous five minutes.
5. The Edge Function records a private cleanup job, globally revokes the
   user's sessions, removes and re-lists every object beneath the user's
   `user-media` prefix, and only then deletes the Auth user.
6. `ON DELETE CASCADE` removes all user-scoped public rows, legacy archive
   rows, and the cleanup job. Storage RLS requires both the user-owned prefix
   and a live `auth.sessions` row, using a narrowly granted `SECURITY DEFINER`
   helper in the non-exposed `homepilot_security` schema. A revoked but
   unexpired JWT therefore cannot upload new orphaned objects during deletion,
   and the helper is not exposed as a Data API RPC.
7. After the server confirms deletion, Flutter clears the local Drift data,
   sync queues and bindings, downloaded/local media, avatar cache, backup ZIPs,
   and backup state. A marker makes interrupted device cleanup resumable on
   the next launch before cloud initialization.

Storage cleanup failures do not delete the Auth user or report success. The
cleanup job retains only the user ID, enumerated object paths, and a bounded
error code while that Auth user still exists; it cascades on successful user
deletion. Because Storage and Auth are separate services, a batch that partly
succeeds can temporarily leave missing media references, but the operation is
idempotent and a freshly authenticated retry completes the cleanup.

## Verification

Safe checks do not create or delete production users:

```text
deno fmt --check supabase/functions/delete-account/index.ts supabase/functions/delete-account/index_test.ts
deno check --node-modules-dir=none --config supabase/functions/delete-account/deno.json supabase/functions/delete-account/index.ts supabase/functions/delete-account/index_test.ts
deno test --node-modules-dir=none --config supabase/functions/delete-account/deno.json supabase/functions/delete-account/index_test.ts
supabase db reset --local
supabase test db --local supabase/tests/database
supabase db lint --local --level error --fail-on error
dart analyze --fatal-infos
flutter test
```

Before deployment, confirm the linked project reference is
`iajvkvvvhwjdiuaufymh`, review `supabase db push --linked --dry-run`, push the
migration, deploy `delete-account` with JWT verification enabled, and inspect
the deployed catalog and function metadata. Do not invoke a successful delete
against a real production account as a deployment test.

## Deployment Record

On 2026-08-01, migration `20260801091024_harden_account_deletion` and
`delete-account` Edge Function version 17 were deployed to project
`iajvkvvvhwjdiuaufymh`. Post-deployment catalog checks, database advisors,
aggregate integrity checks, JWT-gateway rejection, and a downloaded-source
SHA-256 comparison all passed. No production user was deleted during
verification.

Migration `20260801113638_address_account_deletion_advisors` subsequently
moved the authenticated session helper out of the exposed `public` schema and
added covering indexes for all three account-deletion foreign keys. Full
security and performance advisor output is reviewed at `info` severity for
future releases.
