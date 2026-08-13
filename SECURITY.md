# Security Policy

## Active production containment

Production release, signing, Sentry, Supabase mutation/advisor, Play AAB, and
VersionDeck publication rails were paused on 2026-08-11, and GitHub Pages was
unpublished without deleting historical Build 44 evidence. The redacted
evidence, action ledger, limits, and re-enable owners are recorded in
[`docs/operations/production-containment.md`](docs/operations/production-containment.md).
Do not treat workflow source or historical release evidence as authorization to
lift containment.

## Protected source status

GitHub now reports active rules for reviewed, current-check pull requests into
`main`, automation-only production-tag creation, and no-bypass
production-tag update/deletion denial. Repository owner `zuhak5` is the
ruleset owner and `movinesta` and `sijelna` are the independent source
reviewers. Dedicated GitHub App `homepilot-release-authority-zuhak5` is the
only production-tag creation bypass and is installed only on this repository
with Metadata read-only and Contents read/write. There is no standing human or
administrator bypass; an emergency ruleset edit requires a recorded reason,
before/after ruleset evidence, restoration, and post-event review.

TASK-002 is complete, but production containment remains active and the app has
no retained private credential. Later tasks own release authorization and any
credential rotation decision. TASK-004 split GitHub credential environments are
complete: hosted inventory, branch policies, reviewer gates, negative
branch-dispatch rejection, and approved exact-main Advisor runs were recorded.
See the
[`TASK-002 source and tag protection record`](docs/operations/github-source-and-tag-protection.md)
for exact hosted source/tag state, positive/negative probes, and evidence
limits, and the
[GitHub environment credential ownership runbook](docs/operations/github-environment-credential-ownership.md)
for the credential-domain contract. TASK-005 now enforces GitHub's hosted
selected-action and full-SHA policy and records the credential exposure
disposition in the
[GitHub hosted policy and exposure record](docs/operations/github-hosted-policy-and-exposure.md).

## GitHub Actions supply chain

Every current external Action reference is pinned to an allowlisted full commit
SHA with its reviewed upstream release retained as a comment. The deterministic
contract scans workflows and local composite actions and rejects movable,
shortened, aliased, unknown, or unreviewed references. See the
[GitHub Actions supply-chain policy](docs/development/github-actions-supply-chain.md)
for the owner/release/commit ledger, upstream review notes, Dependabot limits,
independent-review procedure, and hosted selected-action enforcement.

Action update pull requests never auto-merge. A proposed digest must be checked
against the official upstream release and security information, the policy and
ledger must change together, and required CI must pass for the exact HomePilot
commit. Repository source does not prove that GitHub's hosted owner allowlist or
require-full-SHA option is enabled; task 05 owns that protected-setting evidence.

## Reporting a vulnerability

Do not report security vulnerabilities in public issues, pull requests, discussions, screenshots, or release notes.

Use GitHub's private vulnerability-reporting feature when it is enabled for this repository. If that feature is unavailable, contact the repository owner privately through a verified channel listed on the owner's GitHub profile. Include the affected component, reproduction steps, expected impact, and any evidence that can be shared safely.

Do not include production secrets, private user data, access tokens, signing files, or complete exploit payloads in an initial report.

## Response expectations

The maintainer will attempt to:

1. Acknowledge a valid report.
2. Assess severity and affected versions.
3. Contain active exposure where necessary.
4. Prepare and validate a correction.
5. Coordinate disclosure and release timing.

No service-level response time is guaranteed.

## Security-sensitive areas

Changes in these areas require elevated review:

- Supabase migrations, Row Level Security, RPCs, Storage policies, and Edge Functions.
- Google authentication, session storage, account binding, sign-out, and account deletion.
- Offline synchronization, conflict recovery, maintenance-completion idempotency, and media cleanup.
- AdMob server-side verification, reward claims, point balances, and charged creation.
- Backup archive parsing, restore staging, schema compatibility, and rollback.
- Sentry initialization, scrubbing, event processors, release publication, and telemetry fields.
- Android permissions, exact alarms, foreground services, boot receivers, and location.
- Production configuration, Android signing, APK verification, provenance, GitHub Releases, and VersionDeck.
- GitHub environment protection, credential ownership, and workflow source
  trust for secret-bearing jobs.

## Secret handling

Never commit:

- Real files under `config/*.json` other than committed examples.
- `.env` files or `supabase/.env`.
- Supabase service-role credentials.
- Google OAuth secrets.
- Sentry authentication tokens.
- Android keystores, signing passwords, or `android/key.properties`.
- Private user content or production database exports.

If a secret is committed, remove it from active use immediately, rotate it, assess exposure, and then clean repository history when appropriate. Deleting the file in a later commit is not sufficient.

## Supported version

Security fixes target the current `main` branch and the most recent published Android release unless the maintainer states otherwise. Version information is authoritative in `pubspec.yaml` and GitHub Releases.

## Safe testing

Use local or dedicated non-production environments. Do not test destructive behavior against production accounts, hosted databases, public Storage objects, signing infrastructure, Sentry projects, or release workflows without explicit authorization.
