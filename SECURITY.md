# Security Policy

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