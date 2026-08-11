# Production Containment Record — TASK-001

## Status and authority

**Status:** active since 2026-08-11 07:42 UTC.

This is the redacted incident-style record for remediation source `TASK-001`
(`HP-015`–`HP-018`, `RC-008`). The repository operator requested task 01
through the sequential remediation procedure, and the containment actions were
executed with the GitHub account `zuhak5`, which the repository API reported as
an administrator. That account is the acting containment owner for the
repository, GitHub Actions, Releases, Pages, and the environment-stored Android
signing, Sentry, and Supabase rails until later tasks record any separate
trust-domain owners. Authenticated Supabase and Sentry access was observed, but
their membership roles were not independently exported. No secret value,
signing material, private user data, raw request, or raw response is retained
here.

The operator moratorium is part of the containment: do not use GitHub, Sentry,
Supabase, Google Play, AdMob, or signing-console authority to build, sign,
migrate, deploy, publish, upload, roll out, or mark a release deployed until the
owning remediation task's re-enable criteria below are met. The Supabase and
Sentry consoles were reachable by the operator during capture. The Google Play
Console account was not enrolled, and the repository contains no Play-upload
automation, so Play publication was independently blocked. AdMob already
reported ad serving disabled while review was in progress; that is context, not
release evidence and not a reason to alter monetization state.

## Redacted pre-containment evidence

Evidence was captured from the frozen audited checkout and hosted APIs between
2026-08-11 07:20 and 07:42 UTC, before changing hosted state.

- Frozen and then-current `main` SHA:
  `be95eb8bcc98298398158bb3eb47e103ffa94d7a`.
- Current history root:
  `f335402277b2abebf857f25d633a3c320a7268e5`.
- Build 44 SHA `6f5606925964c9794d0f1ba863ec954239a47c9b`
  was not an ancestor of the frozen `main` SHA.
- `main` had no branch protection and the repository had no rulesets. The
  `production` environment had no protection rules or deployment-branch
  policy. The `github-pages` environment used a custom `main` branch policy.
- Actions allowed all actions with no SHA-pinning policy. Default workflow
  token permission was read-only and could not approve pull requests.
- Secret scanning and push protection were enabled. They were not changed.
- The pooled `production` environment contained seven secret names: the four
  Android signing names and the Sentry and Supabase authentication names. No
  values were read. No signing file, production configuration, Sentry token, or
  Supabase administration credential was present in the local checkout or
  process environment.

### Workflow and trigger inventory

| Hosted workflow object | ID | Trigger inventory | Authority or mutation boundary | Last relevant run before containment |
| --- | ---: | --- | --- | ---: |
| Audit Supabase Advisors | `330585361` | manual | `production` Supabase token, read-only hosted audit | `31329297477` |
| Build Play Store AAB | `330070553` | manual | `production` signing secrets; signed AAB and attestation | `31330571768` |
| Build Production APK | `325667276` | manual | signing, Sentry, attestation, GitHub Release | `31329512924` |
| Deploy VersionDeck | `325715586` | pull request, APK `workflow_run`, manual recovery | Pages artifact and public deployment | `31330451454` |
| Deploy Supabase Migrations | `330590844` | manual | `production` Supabase administration credentials and linked database mutation | `31329242615` |
| Validate Google Backend and Release Contracts | `330127486` | pull request, `main` push, manual | manual path could read the pooled `production` Supabase token | `31445493507` |
| Remediation Backend Apply | `330127997` | legacy remediation-branch push and manual | retained hosted object with repository-content write authority | `31274240668` |
| Remediation Completion Apply | `330121343` | legacy remediation-branch push and manual | retained hosted object with repository-content write authority | `31274216023` |
| Validate Flutter | `326307067` | pull request and manual | read-only validation; no production environment, secret, publication, or mutation rail | `31328774364` |

The two legacy remediation workflow files were absent from frozen `main`, but
their hosted workflow objects were still active. Their last-run source was read
before disablement to confirm the repository-write boundary. VersionDeck run
`31118560852` was still queued from 2026-08-06 and was preserved in the record
before cancellation.

### Build 44 and public-state tuple

- Release ID `367559562`; tag `v1.5.0-build.44`; lightweight tag and release
  target both resolve to
  `6f5606925964c9794d0f1ba863ec954239a47c9b`; published
  2026-08-09 18:59:05 UTC; not draft, not prerelease, and not immutable.
- APK asset ID `507804615`, name `HomePilot-1.5.0-build-44.apk`, size
  `92,657,207` bytes, SHA-256
  `2dcb6b153230df5baa9ef6883e86572f01532b6b185b536ea71392cb8fd65caf`.
- Checksum asset ID `507804616`, name
  `HomePilot-1.5.0-build-44.apk.sha256`, size `96` bytes, asset SHA-256
  `fbc1547731ebcb0db80b320071d416ecd43809a69f7bc072efdc3c611b6f7dd8`.
- APK run `31329512924`, attempt 1, source `main` at the Build 44 SHA. Retained
  Actions artifacts are `9042756578` (APK) and `9042744658` (APK evidence),
  both expiring 2026-09-08 unless retention policy changes.
- AAB run `31330571768`, attempt 1, used the same source SHA. Retained Actions
  artifacts are `9043052638` (AAB) and `9043052933` (AAB evidence), both
  expiring 2026-09-08 unless retention policy changes. This run did not upload
  to Google Play.
- The downloaded APK hash matched the release digest. `gh attestation verify`
  succeeded with the exact source digest and ref, signer workflow
  `.github/workflows/build-production-android.yml`, GitHub-hosted runner denial
  policy, `workflow_dispatch`, and run invocation `31329512924/attempts/1`.
  One matching attestation remains available in the repository attestation API.
- The APK workflow's Sentry publication step succeeded for release identity
  `com.homepilot.app@1.5.0+44`. This is retained Actions evidence; it is not a
  new Sentry mutation or a claim about current Sentry console configuration.
- Pre-containment Pages deployment ID `5821871383` and workflow run
  `31330451454` published source SHA
  `6f5606925964c9794d0f1ba863ec954239a47c9b`. The manifest generated at
  2026-08-09 19:01:15.988 UTC and still enabled Build 44 immediately before
  containment.

Personal-account repositories do not expose an organization audit-log API.
The retained Actions runs, jobs, artifacts, releases, tag, attestation, Pages
deployment records, and hosted setting snapshots are the available audit
trail; absence of an organization audit log is not represented as proof of
safe history.

## Containment change ledger

At 2026-08-11 07:42 UTC, operator `zuhak5` performed these recoverable actions:

1. Cancelled stale queued VersionDeck run `31118560852`; it completed with
   conclusion `cancelled` at 07:42:13 UTC.
2. Set workflow objects `330585361`, `330070553`, `325667276`, `325715586`,
   `330590844`, `330127997`, `330121343`, and `330127486` to
   `disabled_manually`.
3. Left only read-only `Validate Flutter` object `326307067` active.
4. Unpublished the GitHub Pages site. This did not delete or alter a GitHub
   Release, tag, asset, attestation, Actions artifact, signing key, Sentry
   release, Supabase data, migration, function, or user record.

No credential or signing-key rotation, production build, release publication,
database migration, Sentry mutation, Play upload, remediation implementation,
or replacement artifact was performed.

## Post-containment verification

- Hosted workflow inventory reports the eight listed objects as
  `disabled_manually`; there are zero queued and zero in-progress Actions runs.
- GitHub Pages configuration now returns API `404`, while historical Pages
  deployment records including `5821871383` remain queryable.
- The site root, `releases.json`, and `account-deletion.html` returned uncached
  public HTTP `404` responses after unpublication. VersionDeck and its public
  browser account-deletion page are therefore intentionally unavailable.
- The last live manifest was 36.69 hours old at verification. The executable
  cache policy classified even a just-fetched record containing that manifest
  as `expired`, and expired cached state disables downloads. The service worker
  does not cache `releases.json` in its application shell.
- Release `367559562`, tag target, both public asset IDs/digests, the one
  matching attestation, APK/AAB Actions artifacts, and historical Pages
  deployments remained unchanged after containment.
- TASK-002 subsequently activated reviewed/current-check `main` rules,
  automation-only production-tag creation through a dedicated repository-
  scoped GitHub App, and no-bypass production-tag update/deletion denial. Its
  human/app positive and negative probes are in the
  [source/tag protection record](github-source-and-tag-protection.md).
- Actions policy, environment settings, default read-only workflow permission,
  secret scanning, and push protection remain otherwise unchanged. Tasks
  03–05 own their correction, and every contained workflow and Pages remains
  disabled.
- The Supabase dashboard reported the project healthy during the read-only
  check. No production migration or function deployment was issued; a full
  database-state comparison was not performed and is not claimed.

### Executed local and static verification

- Every checked-out workflow trigger, environment reference, secret reference,
  and mutation boundary was inventoried, and the retained legacy workflow
  sources were inspected at their last-run SHAs.
- The only active hosted workflow was asserted to be `Validate Flutter`
  (`326307067`); its source has zero secret references, environment
  declarations, or write permissions.
- The workflow's complete pull-request VersionDeck sequence passed: JavaScript
  syntax checks, all 40 Node tests, an inert 28-file static build, and
  `tool/validate_versiondeck.mjs`.
- `git diff --check` passed and all relative links in the changed documentation
  resolved. The generated `.versiondeck-site` verification artifact was
  removed after validation.
- The Flutter/Dart and local Supabase baselines were not run because task 01
  changed no Flutter, Android, SQL, function, migration, or generated source.
  A hosted Supabase run would have violated containment and was not used as a
  substitute.

## Documentation impact

Updated in the same change: `README.md`, `SECURITY.md`, `PRIVACY.md`,
`CHANGELOG.md`, `docs/README.md`, the Android and Google Play release runbooks,
the VersionDeck runbook, Sentry operations, backend migration/function
operations, the account-deletion architecture, and the product feature
catalog. `AGENTS.md` and
`docs/governance/documentation-maintenance.md` were reviewed and remain
accurate because task 01 changed operational state, not contributor policy or
validation commands.

## Re-enable ownership and prerequisites

Only the named rail owner may re-enable a rail, using a reviewed change log and
fresh hosted evidence. Re-enablement is not a blanket rollback.

| Rail | Owner | Minimum re-enable prerequisites |
| --- | --- | --- |
| Repository source, tags, environments, and secret access | Repository owner `zuhak5` | Tasks 02–05 complete with hosted rules, reviewer, source-policy, and secret-domain evidence |
| Release attempt, migrations, Sentry deploy, and publication order | Repository, Supabase, and Sentry owners | Tasks 06–07 complete; one exact approved attempt contract; late authority checks; recoverable ordering |
| Android APK/AAB signing and Play handoff | Signing and Play owners | Tasks 26 and 28–33 complete, plus task 36's explicit version/build and protected-release authorization |
| VersionDeck and Pages | Repository/Pages owner | Tasks 26–27 and 32–34 complete; stale/disabled/withdrawal tests; exact release lineage and freshness evidence |
| Supabase migrations and functions | Supabase owner | Owning backend task authorizes the exact target and migration/function; tasks 02–07 protection prerequisites remain satisfied |
| Full production qualification | Cross-service owners | Task 37 dossier closes hosted, protected, artifact, device, console, and owner/legal evidence |

Task 01 containment may be lifted rail-by-rail only. Historical Build 44 cannot
be made immutable retroactively and must not be republished, replaced, or
described as compromised without new evidence.

## Evidence limits

This record distinguishes API/static/executed evidence from unavailable proof.
It does not prove organization audit history, Play App Signing identity, a
Play-delivered artifact, physical-device behavior, current Sentry project
privacy settings, or future credential safety. Those remain console, device,
artifact, protected-environment, or owner evidence for their owning tasks.
