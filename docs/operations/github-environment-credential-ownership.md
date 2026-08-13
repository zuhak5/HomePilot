# GitHub Environment Credential Ownership

> **TASK-004 status:** Source and hosted secret-name placement now use split
> trust domains, but task closure still requires negative workflow evidence and
> owner-scoped credential review. Do not dispatch protected rails during active
> containment.

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
| `production-sentry` | Sentry release/deploy mutation | `main` | Required, prevent self-review | `SENTRY_ORG`, `SENTRY_PROJECT` | `SENTRY_AUTH_TOKEN` | `Publish Sentry release` |
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
- APK signing, Sentry publication, and GitHub Release publication use separate
  jobs and environments. The signing job uploads an immutable APK/checksum/
  evidence handoff; later jobs re-download and verify that handoff before their
  own mutations.
- Artifact handoffs may contain built artifacts, checksums, safe evidence, and
  symbol material required by Sentry, but never secret values or temporary
  signing/configuration files.

## Required hosted evidence

Before task 04 can close, capture without secret values:

1. Environment API or screenshots showing required reviewers, disabled admin
   bypass, and `main` branch policy for every environment in the map.
2. Secret-name inventory showing each required secret exists only in its
   intended environment and the legacy pooled `production` environment no
   longer holds active pooled secrets.
3. Credential owner confirmation that Advisor uses a read-only token and
   migration/admin credentials are separate.
4. Negative dispatch evidence that arbitrary branch/ref Advisor runs fail
   before secret injection.
5. Cross-domain workflow contract evidence showing no rail references another
   rail's secret names.
6. Deployment history or workflow-run evidence for approved exact-current-main
   protected jobs after the split, while containment remains respected.

Do not record secret values, token bodies, keystore material, private keys,
database passwords, Sentry tokens, or private user data in evidence.
