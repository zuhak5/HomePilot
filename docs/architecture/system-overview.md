# System Overview

## Context

HomePilot is an Android-first Flutter application. Its central architectural requirement is that users can continue organizing assets and recording maintenance while offline, then synchronize safely after authentication and connectivity return.

## Major components

```text
Flutter UI
  -> Riverpod providers and application services
  -> Domain repositories
  -> Drift/SQLite local database
  -> Sync coordinator and media pipeline
  -> Supabase Auth, Postgres, Storage, Realtime, RPCs, Edge Functions

Flutter services
  -> Local notifications, exact alarms, foreground tasks, Workmanager
  -> Google Sign-In
  -> Google Mobile Ads
  -> Sentry

Protected GitHub Actions
  -> Android release build and verification
  -> Sentry release publication
  -> Provenance and GitHub Release
  -> VersionDeck independent verification and GitHub Pages deployment
```

## Flutter application

`lib/main.dart` currently contains application bootstrap, routing, and substantial presentation behavior. Feature and core code under `lib/src/` contains reusable models, services, repositories, authentication, synchronization, monetization, backup, notifications, and configuration.

Riverpod is the dependency and state-management mechanism. GoRouter is the navigation mechanism. New work should reduce coupling rather than adding more unrelated responsibilities to the bootstrap file.

## Local persistence

Drift manages the SQLite database. The schema stores product entities and operational state including synchronization outbox entries, pull cursors, remote shadows, hydration/runtime state, account binding, reminder snapshots, and cleanup work.

The local database is the immediate user-facing working set. Cloud synchronization does not make every UI read depend on network availability.

## Cloud backend

Supabase provides:

- Google-backed user sessions through Supabase Auth.
- Postgres tables, indexes, RLS policies, and RPCs.
- Private `user-media` Storage.
- Realtime invalidation signals.
- Edge Functions for protected workflows such as account deletion and AdMob server-side verification.

The backend is authoritative for ownership, point balances, charged operations, verified rewards, and globally coordinated revisions.

## Synchronization

Local mutations become durable outbox work. The coordinator binds work to an authenticated account, pushes idempotent operations, pulls cloud changes using cursors and revisions, records shadows, handles retry and conflicts, and uses realtime events as invalidation rather than as complete authoritative payloads.

See `sync-protocol.md`.

## Authentication and deletion

Production authentication is Google-based. Session state is stored through Supabase and secure platform storage. Account deletion is a coordinated workflow across Flutter, synchronization, Storage, Postgres, and Auth and requires recent same-identity reauthentication.

## Monetization

Google Mobile Ads runs in Flutter with consent-aware presentation. Points and charged creation are implemented as backend-authoritative operations. Reward callbacks become pending claims and are credited only after server verification and replay protection.

## Notifications and background execution

The Android host declares permissions and components required for internet access, approximate location, notifications, exact alarms, boot handling, wake locks, vibration, foreground data synchronization, and local notification receivers. Background work restores or reconciles reminders and synchronization without introducing background location.

## Backup and restore

HomePilot produces versioned ZIP archives with a manifest and hashes. Restore treats archives as untrusted input, validates compatibility and extraction bounds, creates a safety backup, stages media, applies data, and rolls back on failure.

## Observability

Sentry is optional by configuration. Events are scrubbed and should contain only technical diagnostics. Production workflows associate releases with source and artifacts without uploading user data.

## Build and distribution

The protected Android workflow validates source, configuration, signing material, package identity, version/build values, APK debuggability, signer identity, checksums, tests, Sentry release state, provenance, and GitHub Release publication.

VersionDeck is separate from the application build. It discovers releases and independently verifies APK identity before generating a static download site. Live workflow status is informational and must remain separate from verified stable-release identity.

## Trust boundaries

Highest-risk boundaries are:

- Imported backup archives.
- Client-to-Supabase ownership and RPC inputs.
- Cross-account local data binding.
- Synchronization conflicts and retries.
- Ad reward callbacks and SSV requests.
- Account deletion authorization and partial failure.
- Production configuration and signing material.
- Release metadata and public download enablement.
- Diagnostic data sent to Sentry.

Changes crossing these boundaries require explicit tests and documentation.