# HomePilot Supabase Deployment Report

Deployment date: 2026-07-26

Project reference: `iajvkvvvhwjdiuaufymh`

Region: `ap-northeast-2`

## Local validation

The local Supabase stack was reset from migrations and seed data before remote
changes. Database lint completed without errors, all 10 pgTAP files and 107
tests passed, and the local `public` schema diff was empty.

The `delete-account` function passed Deno formatting, type checking, and three
function tests with Deno 2.9.3 and pinned
`@supabase/supabase-js` 2.110.8.

## Production preflight

The linked reference was re-confirmed as `iajvkvvvhwjdiuaufymh`; project health
was `ACTIVE_HEALTHY`. Migration history matched before deployment, remote
error-level database lint was clean, and the reviewed dry run contained only:

```text
20260722061630_reconcile_live_relationship_indexes_and_service_role_grants.sql
20260722061634_localize_notification_messages_and_language_preference.sql
```

The first additive migration reconciles the eight exact live relationship
indexes and existing `service_role` CRUD grants using idempotent statements.
The second adds nullable notification `message_code` and object-validated
`message_args` columns and extends the user-settings key constraint for
`app_language_explicit`. Neither migration broadens anonymous or authenticated
access.

Managed physical backups/PITR were not enabled (`backups: null`,
`pitr_enabled: false`); WAL archiving was enabled. No production user data was
read or extracted.

## Deployment and postflight

The two migrations were applied through a linked transactional database push.
Notices were limited to expected idempotent existing indexes/check constraints.
No reset, migration repair, drop, or destructive backfill was used.

Post-deployment evidence:

- Local and remote migration histories match.
- Remote error-level database lint is clean.
- The application `public` schema diff is empty and contains no destructive SQL.
- RLS/ownership pgTAP coverage verifies owner and non-owner behavior, update
  `WITH CHECK`, grants, JSON-object validation, locale settings, and unchanged
  cleanup behavior.

The `delete-account` Edge Function was then deployed with JWT verification
enabled. The deployed function is active at version 15. Required secret names
were verified without reading or recording secret values.

## Advisors and forward fixes

The post-deployment advisors retain one password-protection warning. HomePilot
is intentionally Google-only and does not enable password, magic-link,
anonymous, or guest authentication, so the authentication model was not
changed. Informational unused-index findings remain observable; indexes were
preserved because this release explicitly reconciles the known live
relationship indexes and does not authorize destructive index removal.
