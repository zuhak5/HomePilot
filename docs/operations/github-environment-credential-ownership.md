# GitHub Environment Credential Ownership

> **TASK-004 status:** Complete as of 2026-08-13. Split trust domains,
> owner-scoped credential placement, negative branch-dispatch rejection, and
> approved exact-main hosted Advisor runs were verified without recording
> secret values.

## Purpose

Production credentials are separated by authority domain so a job can request
only the credentials needed for its own rail. Workflow source is a contract, not
proof that hosted secrets or reviewers are correct.

## Environment map

| Environment | Owner domain | Allowed branch | Reviewers | Variables | Secrets | Jobs |
| --- | --- | --- | --- | --- | --- | --- |
| `production-supabase-advisors` | Supabase read-only hosted audit | `main` | Required, prevent self-review | `SUPABASE_PROJECT_REF`, `SUPABASE_URL` | `SUPABASE_ADVISOR_ACCESS_TOKEN` | `Hosted security and performance advisors`, `Hosted Supabase Advisors` |
| `production-supabase-migrations` | Supabase migration/admin deployment | `main` | Required, prevent self-review | `SUPABASE_URL` | `SUPABASE_MIGRATION_ACCESS_TOKEN`, `SUPABASE_MIGRATION_DB_PASSWORD` | `Apply pending production migrations` |
| `production-play-signing` | Google Play upload-key AAB build evidence | `main` | Required, prevent self-review | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `GOOGLE_WEB_CLIENT_ID`, `SENTRY_DSN` | `PLAY_UPLOAD_KEYSTORE_BASE64`, `PLAY_UPLOAD_KEY_ALIAS`, `PLAY_UPLOAD_KEY_PASSWORD`, `PLAY_UPLOAD_STORE_PASSWORD` | `Build and verify signed production AAB` |
| `production-android-signing` | Standalone APK signing and artifact evidence | `main` | Required, prevent self-review | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `GOOGLE_WEB_CLIENT_ID`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_DSN` | `ANDROID_APK_KEYSTORE_BASE64`, `ANDROID_APK_KEY_ALIAS`, `ANDROID_APK_KEY_PASSWORD`, `ANDROID_APK_STORE_PASSWORD` | `Build signed production APK` |
| `production-sentry` | Sentry release/deploy mutation | `main` | Required, prevent self-review | `SENTRY_ORG`, `SENTRY_PROJECT` | `SENTRY_AUTH_TOKEN` | `Publish Sentry release`, `Create Sentry deploy marker` |
| `production-github-release` | GitHub Release and provenance mutation | `main` | Required, prevent self-review | None | None | `Publish GitHub Release` |
| `github-pages` | VersionDeck Pages publication | `main` | Required, prevent self-review | None in deploy job | None | `Publish VersionDeck` |

The legacy pooled `production` environment must remain inaccessible and unused
after cutover until task 05 records the exposure disposition. It no longer
retains active Android signing, Supabase, or Sentry secret names after the split
environment secrets were re-entered and verified on 2026-08-13.

## Source-trust rules

- Secret-bearing jobs must be manually dispatched or chained only from `main`.
- A no-secret preflight must reject non-`main` dispatches and require the
  selected SHA to equal current `origin/main`.
- Every protected job must revalidate the exact current `main` SHA after the
  environment approval wait.
- Advisor jobs check out only the validated SHA with persisted credentials
  disabled and use `SUPABASE_ADVISOR_ACCESS_TOKEN`, not migration/admin
  authority.
- APK signing, Sentry publication, GitHub Release publication, and Sentry
  deploy-marker creation use separate jobs. The signing job uploads an
  immutable APK/checksum/evidence handoff; later jobs re-download and verify
  that handoff or the published ledger state before their own mutations.
- Artifact handoffs may contain built artifacts, checksums, safe evidence, and
  symbol material required by Sentry, but never secret values or temporary
  signing/configuration files.

## Required hosted evidence

Task 04 closure evidence was captured on 2026-08-13 without secret values:

1. Environment API evidence showed required reviewers `movinesta` and
   `sijelna`, disabled admin bypass, and a custom `main` branch policy for
   `production-supabase-advisors`, `production-supabase-migrations`,
   `production-play-signing`, `production-android-signing`,
   `production-sentry`, `production-github-release`, and `github-pages`.
2. Secret-name inventory showed each required secret only in its intended
   split environment. The legacy pooled `production` environment had no active
   secret names.
3. Credential placement confirmed Advisor uses
   `SUPABASE_ADVISOR_ACCESS_TOKEN`, while migration/admin access uses only
   `SUPABASE_MIGRATION_ACCESS_TOKEN` and `SUPABASE_MIGRATION_DB_PASSWORD`.
4. Negative branch dispatches failed before secret injection:
   `Audit Supabase Advisors` run `31701249975` failed in no-secret
   `Require current main Advisor source` / `Reject a non-main dispatch`, and
   `Validate Google Backend and Release Contracts` run `31701252869` failed in
   the same preflight while `Hosted Supabase Advisors` remained skipped.
5. Cross-domain workflow contract evidence passed through
   `npm run test:release-workflows`, which enumerates environment and secret
   ownership and rejects cross-domain secret references.
6. Approved exact-current-main hosted Advisor runs succeeded on merged SHA
   `197fd7cd4653caa366a87b94f52fc3dbe027a28a`: standalone Advisor run
   `31701549478` and backend validation run `31701552364`. In both runs the
   no-secret preflight passed, the protected job waited for
   `production-supabase-advisors`, and the secret-bearing job revalidated
   current `origin/main` after approval before querying Advisors.

Do not record secret values, token bodies, keystore material, private keys,
database passwords, Sentry tokens, or private user data in evidence.
