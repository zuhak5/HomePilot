# GitHub Source and Tag Protection Record — TASK-002

## Status

**Status:** completed on 2026-08-11. The final repository-scoped release-app
installation and production-tag creation rule were active by 09:44 UTC.

This record covers the source/tag/protection portion of remediation source
`TASK-002` (`HP-015`, `INV-017`, `RC-008`). It does not authorize production
workflow, environment, signing, migration, Sentry, release, Play, or Pages
activity. The [TASK-001 production containment](production-containment.md)
remains active.

## Authority decision

- Repository and emergency ruleset owner: `zuhak5`.
- Independent source reviewer: `movinesta`, whose accepted collaborator role
  was reported by the repository API as `write`.
- Additional independent source reviewer: `sijelna`, who accepted invitation
  `328739917` and whose collaborator role is reported by the repository API as
  `write`.
- Approved production-tag creation authority: dedicated GitHub App
  `homepilot-release-authority-zuhak5` (app ID `4556704`), owned by `zuhak5`.
  It is registered as account-only with repository Contents read/write and
  Metadata read-only, no webhook, and no user OAuth or device flow. Human
  creation, movement, and deletion are not approved.
- Standing administrator bypass: none.

If an emergency requires a ruleset change, `zuhak5` must record the reason and
scope before the change, preserve the ruleset API state and history before and
after it, restore the policy as soon as the emergency ends, and obtain
post-event review from `movinesta`. A personal-account repository has no
organization audit-log API, so ruleset history, pull requests, Actions runs,
and this redacted change record are the available audit trail. An emergency
edit is not evidence that the affected release or source transition was
authorized.

## Active hosted configuration

The following repository rulesets were created through the GitHub API. Their
identifiers are durable hosted state, not workflow-source claims.

| Ruleset | ID | Target | Bypass | Active rules |
| --- | ---: | --- | --- | --- |
| `Protect main source authority` | `20683472` | `refs/heads/main` | none | deletion denied; force pushes blocked; pull request required; one approval; stale approvals dismissed; latest push requires another approver; review threads resolved; current required check |
| `Protect production tag immutability` | `20683475` | `refs/tags/v*-build.*` | none | updates denied; deletion denied |
| `Restrict production tag creation to release app` | `20687747` | `refs/tags/v*-build.*` | GitHub App `4556704` only | creation denied unless the actor is the approved release app |

The `main` ruleset requires the GitHub Actions check context
`Format, analyze, and test`, pinned to integration ID `15368`, with strict
up-to-date status enforcement. That context is real: it was emitted by the
active `Validate Flutter` workflow, including successful pull-request run
`31328774364`. It is the only safe current required context because every other
hosted workflow object remains disabled by TASK-001. The three pull-request
contexts from `Validate Google Backend and Release Contracts` must not be made
required while that mixed secret-bearing workflow object is disabled; its
split/re-enable and the later canonical CI inventory belong to their owning
tasks.

Default workflow token permission remains read-only and cannot approve pull
requests. Secret scanning and push protection remain enabled. The release app
installation and rulesets changed, but no workflow, environment, secret,
release, artifact, attestation, Pages site, Sentry state, or Supabase state was
re-enabled or mutated.

## Executed negative evidence

The following hosted probes were executed as repository administrator
`zuhak5` after activating the rulesets:

- An empty disposable commit `514eb246bdeafd25ff8c5d9846a674f93c4e80dc`
  was pushed directly and force-pushed to `main`. Both attempts were rejected
  with `GH013`; GitHub reported that a pull request and the required
  `Format, analyze, and test` context were missing.
- Deleting `main` was rejected, and the active ruleset independently contains
  the no-bypass deletion rule.
- Disposable tag `v0.0.0-build.0-task02-20260811-1133` was created at
  `be95eb8bcc98298398158bb3eb47e103ffa94d7a`. Retargeting it to Build 44 SHA
  `6f5606925964c9794d0f1ba863ec954239a47c9b` and deleting it were both rejected
  with repository-rule HTTP `422` responses.
- The disposable tag was excluded only long enough to delete it, then the
  ruleset was immediately restored with an empty exclusion list. The API
  reports the final production pattern above; ruleset history retains the
  test transition.

Historical Build 44 tag `v1.5.0-build.44` and its release evidence were not
rewritten.

## Reviewed pull-request evidence

Disposable pull request `#32` contains only empty commit
`edb47df2959f6788e04724d49edd0d5c69270274`. The real
`Format, analyze, and test` check passed in hosted run `31474832699`, job
`93726030013`. With zero reviews and the check green, an administrator merge
attempt was rejected with HTTP `405`; GitHub reported that new changes require
approval from someone other than the last pusher.

Reviewer `sijelna` then approved that exact unchanged head SHA. The protected
merge succeeded as operator `zuhak5` at 2026-08-11 09:21:40 UTC, producing
`main` merge commit `27becebd0bffd018e28cf6fc4fc83f10ea1a31c2`. The disposable
head branch was deleted after the repository API confirmed the merge. This
proves both the unreviewed denial and reviewed positive `main` path.

## Production-tag creation authority evidence

The built-in GitHub Actions app (`github-actions`, integration ID `15368`) was
not eligible as a ruleset bypass actor for this user-owned repository. The
repository owner therefore explicitly authorized the dedicated app described
above instead of weakening the boundary with an administrator-role, deploy-key,
personal-token, or unrelated-app bypass.

GitHub App `homepilot-release-authority-zuhak5` is installed as installation
`152876924` with repository selection `selected`; its installation API exposed
exactly one repository, `zuhak5/HomePilot` (repository ID `1319597440`). The app
has only repository Contents read/write and mandatory Metadata read-only. It
has no webhook, user OAuth, device flow, organization permission, or standing
human bypass. Ruleset `20687747` has one bypass actor only: integration app ID
`4556704`.

The following hosted probes exercised the effective boundary:

- Human operator `zuhak5` attempted to create
  `refs/tags/v0.0.0-build.0-task02-human-20260811`; GitHub rejected creation
  with HTTP `422`.
- A short-lived installation token for installation `152876924` created
  `refs/tags/v0.0.0-build.0-task02-app-20260811` at current `main` SHA
  `27becebd0bffd018e28cf6fc4fc83f10ea1a31c2` with HTTP `201`.
- The same app token attempted to retarget that tag to Build 44 and delete it.
  The no-bypass immutability ruleset rejected both operations with HTTP `422`.
- The installation token was explicitly revoked with HTTP `204`. The
  disposable app tag was then given one exact temporary immutability exclusion,
  deleted, and the ruleset restored. Both probe refs are absent and ruleset
  `20683475` is active with an empty exclusion list.

The one downloaded private-key file used for this probe was deleted from the
operator's Downloads directory, and no matching private-key file remains.
GitHub retains the corresponding public-key fingerprint because its UI does
not allow deletion of the only registered public key; without the destroyed
private half it cannot authenticate. No private key or installation token was
printed, committed, or retained. A later release-rail task must provision a
fresh protected app credential and integrate it with the approved workflow;
Task 02 does not enable that workflow or any production rail.

Historical Build 44 remains at
`6f5606925964c9794d0f1ba863ec954239a47c9b`. The three active rulesets now prove
reviewed source entry, automation-only production-tag creation, and no-bypass
production-tag movement/deletion while production containment remains active.

## Evidence boundaries

This record contains `R-DOC`, hosted API, and executed positive and negative
Task 02 protection evidence. It does not claim organization audit history,
environment/secret separation, immutable Action pins, a successful protected
release, artifact/device/console evidence, or production readiness.
