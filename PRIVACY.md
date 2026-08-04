# HomePilot Privacy and Data Use

_Last reviewed: August 4, 2026_

This document describes the data-handling design represented by the current HomePilot source code. It is technical project documentation, not a substitute for jurisdiction-specific legal review or store disclosures.

## Data HomePilot manages

Depending on the features used, HomePilot can process:

- Home organization data such as areas, rooms, categories, assets, tags, notes, photos, and specialized device, pet, plant, or safety details.
- Maintenance plans, recurrence settings, due dates, completion history, attachments, warranty information, reminders, and notification state.
- Preferences, onboarding state, statistics, streaks, health or readiness summaries, and application settings.
- Account identifiers and session material required for Google sign-in and Supabase authentication.
- Synchronization metadata such as operation identifiers, revisions, cursors, retry state, shadows, hydration state, and cleanup state.
- Backup archives created or selected by the user.
- Approximate location when the user grants coarse-location permission for location-dependent features. HomePilot does not request background-location permission in the current Android manifest.
- Advertising consent state, ad events, reward claims, point balances, charged-creation records, and fraud-prevention metadata used by the monetization system.
- Limited diagnostic and release metadata when Sentry is enabled.

## Where data is stored

HomePilot is offline-first. Application data is stored in a local SQLite database managed through Drift. Media and backup files may also be stored in application-controlled local storage.

When a user signs in and synchronization is enabled, supported data is stored in the project's Supabase Postgres database and private Supabase Storage. Local synchronization metadata is retained to support offline work, retries, conflict handling, and account isolation.

Sensitive session material is stored through platform secure storage where supported.

## Third-party services

### Supabase

Supabase provides authentication, Postgres storage, private media Storage, Realtime invalidation, RPCs, and Edge Functions. Row Level Security and ownership checks are expected to isolate user data. Backend changes must preserve those controls.

### Google Sign-In

Production authentication uses Google sign-in. Google and Supabase process identity and session information needed to authenticate the user. HomePilot does not use email-and-password sign-up in its current local Supabase configuration.

### Google Mobile Ads

HomePilot includes Google Mobile Ads. Depending on consent, configuration, region, and ad availability, Google may process device, advertising, consent, fraud-prevention, and interaction data. Rewarded-ad claims are verified server-side before points are credited. Core application data must not be inserted into ad request or reward identifiers.

### Sentry

Sentry may receive technical error and performance information when enabled. HomePilot's intended observability policy excludes user content and direct identifiers, disables screenshots, session replay, view hierarchy, and raw HTTP payload capture, and applies event scrubbing. See `docs/SENTRY_OPERATIONS.md`.

### Location and network services

Features that use approximate location or external network data should collect only what is required, handle denied permission, and avoid background tracking. Changes that introduce a new external service require a privacy review and an update to this document.

## Notifications and background work

HomePilot schedules local maintenance notifications and may use exact alarms, boot restoration, wake locks, foreground data-sync service capability, and Workmanager. Notification content can reveal maintenance information on the device lock screen; users should configure operating-system notification privacy according to their needs.

The current Android manifest does not request fine or background location.

## Backup and restore

User-created backups can contain substantial HomePilot data and media. Backups should be treated as sensitive files. The application validates archive paths, sizes, hashes, and schema compatibility, and uses safety-backup and rollback procedures during restore. Users control where exported backups are stored or shared.

Android platform backup is disabled for the application in the current manifest; HomePilot's own backup feature is separate.

## Retention and deletion

Local data remains until it is deleted through application behavior, cleared by the user or operating system, removed during sign-out/account cleanup, or replaced through restore.

For account deletion, HomePilot requires recent reauthentication with the same Google identity, suspends synchronization, invokes the protected `delete-account` Edge Function, removes private remote media and the authentication user, verifies the deletion result, and completes local cleanup. Some operational records may be retained only where necessary to complete or prove deletion, prevent replay, investigate abuse, or satisfy legal obligations.

Backup files previously exported outside the application are not automatically deleted by account deletion.

## Security controls

The project uses private Storage, Row Level Security, authenticated RPCs, local secure storage, operation idempotency, account binding, archive validation, release signing, APK verification, and protected CI environments. No control can guarantee absolute security.

## Children's privacy

The project does not intentionally define a child-directed service. Product distribution and legal disclosures should be reviewed before offering the application to children or collecting age-related data.

## Changes to data use

Any change that adds a permission, SDK, telemetry field, external service, persistent field, AI processing path, advertising behavior, location use, or retention/deletion behavior must update this document and the relevant architecture or operations documentation before release.