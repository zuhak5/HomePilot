# GitHub Hosted Policy and Exposure Disposition

> **TASK-005 status:** Complete as of 2026-08-13. Hosted selected-action and
> full-SHA policy enforcement, negative policy probes, positive pinned workflow
> execution, source/tag/environment interlock checks, and evidence-limited
> credential dispositions were recorded without secret values.

## Purpose

This record ties HomePilot's source-level workflow policy to GitHub's hosted
Actions, ruleset, and environment controls. It also records the evidence limits
for the historical unprotected period and the credential-domain disposition
made from available repository evidence.

## Hosted Actions Policy

As of 2026-08-13, repository Actions settings are:

- Actions enabled: `true`.
- Allowed actions: `selected`.
- Full-length SHA pinning required: `true`.
- GitHub-owned actions broadly allowed: `false`.
- Verified Marketplace actions broadly allowed: `false`.
- Selected external action patterns:
  - `actions/attest-build-provenance@*`
  - `actions/checkout@*`
  - `actions/configure-pages@*`
  - `actions/deploy-pages@*`
  - `actions/setup-java@*`
  - `actions/setup-node@*`
  - `actions/upload-artifact@*`
  - `actions/upload-pages-artifact@*`
  - `denoland/setup-deno@*`

The selected patterns are intentionally broader than exact commits because
GitHub's hosted allowlist is repository-pattern based. The exact accepted
commits remain enforced by the source contract in
[`tool/github-actions-policy.mjs`](../../tool/github-actions-policy.mjs) and by
the required `Format, analyze, and test` check. `subosito/flutter-action` is no
longer allowed because the hosted full-SHA policy rejected its transitive
`actions/cache@v5` reference.

Default `GITHUB_TOKEN` workflow permission remains `contents: read`, and
workflow tokens cannot approve pull-request reviews.

## Hosted Policy Evidence

The hosted policy was exercised without production secrets:

- Mutable action ref rejection: `Validate Flutter` run `31704403865` on branch
  `codex/task05-mutable-action-probe` failed with `startup_failure` after the
  workflow changed a checkout step to `actions/checkout@v6`.
- Unknown owner rejection: `Validate Flutter` run `31704474707` on branch
  `codex/task05-unknown-action-probe` failed with `startup_failure` after the
  workflow changed a checkout step to
  `example/checkout@d23441a48e516b6c34aea4fa41551a30e30af803`.
- Positive PR evidence: `Validate Flutter` run `31704947840`, job
  `94463032472`, passed on task branch commit
  `668e1692845e8e208c0170510b34621559d2a668` under the hosted policy.
- Positive `main` evidence: after PR #40 merged at
  `1d7e59c18d3ca69f91cc1cd7a17ad03801f22e41`, `Validate Flutter` run
  `31705746697`, job `94465736345`, passed on `main` under the hosted policy.

## Source, Tag, and Environment Interlock

Current policy relies on the task 02 and task 04 hosted controls:

- `main` ruleset `20683472` denies deletion and force pushes, requires a pull
  request, requires one approval from someone other than the latest pusher,
  dismisses stale approvals, requires resolved review threads, and requires the
  current `Format, analyze, and test` check.
- Production tag rulesets `20683475` and `20687747` deny human production-tag
  creation and deny production-tag update/deletion without bypass.
- Split production environments require reviewers `movinesta` and `sijelna`,
  disable admin bypass, and allow only `main` branch deployments.
- Advisor arbitrary-ref dispatch rejection and approved exact-main execution
  were recorded in the
  [GitHub environment credential ownership runbook](github-environment-credential-ownership.md).

These controls were rechecked through the repository APIs on 2026-08-13 before
task closure. Actions policy reported `allowed_actions: selected` and
`sha_pinning_required: true`; workflow token policy reported
`default_workflow_permissions: read` and
`can_approve_pull_request_reviews: false`; the repository reported secret
scanning and push protection enabled.

## Historical Evidence Coverage

This is a user-owned public repository. The organization audit-log API is not
available for `zuhak5/HomePilot`; `gh api orgs/zuhak5/audit-log` returned
HTTP `404`. Therefore historical disposition uses only repository-accessible
evidence:

- workflow run history and deployment records;
- pull requests, merge records, and branch names;
- current and historical workflow source from Git;
- ruleset, environment, Actions-policy, secret-name, and workflow-status API
  snapshots captured during tasks 01-05.

These records show multiple historical `production` and `github-pages`
deployments before containment, including one non-main `production`
deployment from `codex/polish-feedback-settings` on 2026-08-09 and older
non-main deployments from `agent/dashboard-onboarding` and
`codex/fix-android-plugin-registration`. They do not expose secret values and
do not prove which exact secret values were read by a job. Absence of an
organization audit log is treated as incomplete coverage, not proof of
non-exposure.

## Credential Disposition

| Domain | Available indicators | Disposition |
| --- | --- | --- |
| Supabase Advisor token | Historical pooled `production` Advisor jobs and later split exact-main Advisor evidence. No secret values in logs or artifacts reviewed. Audit-log coverage incomplete. | Keep split read-only Advisor token in `production-supabase-advisors`; rotate if owner requires conservative revocation. Do not share migration authority. |
| Supabase migration access token and database password | Historical pooled `production` migration deployments existed before task 04 split. No secret values in reviewed logs/artifacts. Audit-log coverage incomplete. | Keep isolated in `production-supabase-migrations` during containment; rotate before future production migration if owner policy requires fresh admin credentials. |
| Standalone APK signing keystore/passwords | Historical APK signing ran from pooled `production`; signing material is irreversible and rotation affects release lineage. No keystore value appeared in reviewed repository evidence. | Do not rotate automatically. Keep isolated in `production-android-signing`; defer key rotation to an explicit signing-owner decision. |
| Play upload keystore/passwords | Historical Play AAB build ran from pooled `production`; no Play publication automation was found. No keystore value appeared in reviewed repository evidence. | Do not rotate automatically. Keep isolated in `production-play-signing`; defer upload-key rotation to a Play-console owner decision. |
| Sentry auth token | Historical APK release rail could publish Sentry from pooled `production`; no token value appeared in reviewed repository evidence. | Keep isolated in `production-sentry`; rotate before release reactivation if Sentry owner requires conservative revocation. |
| GitHub Release/provenance authority | Current `production-github-release` has no secrets; production tag creation remains app-only from task 02. | No credential rotation applies. Future release-app credential provisioning belongs to later release tasks. |
| GitHub Pages | Current `github-pages` has no secrets; historical Pages deployments existed before containment. | No secret rotation applies; Pages remains disabled until VersionDeck tasks authorize reactivation. |

No credential/key rotation was performed for task 05. The repository owner and
independent reviewer accepted this evidence-limited disposition through the
protected PR review and merge path. Any future conservative rotation remains a
domain-owner decision and must be separately authorized and evidenced.

## Monitoring and Bypass Governance

- Policy drift monitor: run `npm run test:release-workflows` on every pull
  request and required `main` validation. This fails if workflow source adds a
  mutable, shortened, unknown, or unreviewed action reference or crosses a
  credential-domain boundary.
- Hosted policy monitor: owner `zuhak5` must re-run the API inventory in this
  record after any Actions-policy, ruleset, environment, or workflow-status
  change. GitHub sends failed required-check notifications for policy probes
  and failed secret-boundary tests.
- Emergency bypass: changing rulesets, environment branch policies, reviewers,
  admin bypass, selected Actions policy, or full-SHA enforcement requires a
  written reason, before/after API snapshots, restoration evidence, and
  independent review from `movinesta` or `sijelna`.
- Unexpected workflow dispatch: any workflow-dispatch run from a non-`main`
  branch that reaches a protected environment is a security incident. The
  current Advisor negative probes demonstrate the preflight fails before
  secret injection.
