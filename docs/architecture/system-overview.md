# System Overview

## Context

HomePilot is an Android-first Flutter application. Its central architectural requirement is that users can continue organizing assets and recording maintenance while offline, then synchronize safely after authentication and connectivity return.

## Major components

```text
HomePilotProcessSplash (first runApp child; stable process owner)
  -> deferred startup, theme loading, failure surface, and Flutter UI
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

GitHub Actions release rails
  -> exact-SHA backend, Edge Function, database, web, and static contracts
  -> signed AAB plus evidence and provenance (no Play upload)
  -> signed APK, evidence, Sentry release, provenance, and GitHub Release
  -> VersionDeck independent verification and GitHub Pages deployment
```

## Flutter application

`lib/main.dart` currently contains application bootstrap, routing, and substantial presentation behavior. Feature and core code under `lib/src/` contains reusable models, services, repositories, authentication, synchronization, monetization, backup, notifications, and configuration.

Riverpod is the dependency and state-management mechanism. GoRouter is the navigation mechanism. New work should reduce coupling rather than adding more unrelated responsibilities to the bootstrap file.

`HomePilotProcessSplash` is the first child passed to every `runApp` branch. It remains mounted while deferred initialization, startup-theme loading, the application, or a startup-failure surface changes beneath it, so those branches cannot reset the fixed splash lifetime or expose a blank Flutter frame. A static startup surface remains underneath if initialization outlives the overlay. The splash selects English or Arabic from the device locale, exposes one localized semantic label, supports compact and scaled layouts, and stops repeating animation when the platform requests reduced motion. These are repository and widget-test contracts; launch behavior on a physical release device remains separate evidence.

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

The public VersionDeck deletion page is an entry point, not an unauthenticated delete API. It performs Google OAuth with PKCE through Supabase, keeps access tokens in memory, requires explicit confirmation, calls the protected `delete-account` Edge Function with the authenticated bearer token, and accepts success only from a matching deletion receipt. Repository tests encode the browser and function contracts; they do not prove that the reviewed site, OAuth redirect, or function revision is deployed. See [Authentication and account deletion](auth-and-account-deletion.md).

## Monetization

Google Mobile Ads runs in Flutter with consent-aware presentation. Points and charged creation are implemented as backend-authoritative operations. Reward callbacks become pending claims and are credited only after server verification and replay protection.

Ad eligibility fails closed across supported platform, resumed lifecycle, launch-fresh consent state, UMP permission, global remote enablement, and per-format switches. Eligibility generations invalidate stale loads and retries; bounded retry classes can become dormant; cached ads expire at 55 minutes; leases own native ads exactly once; and one fullscreen gate serializes interstitial and rewarded presentation. These contracts and the Android native-ad schema have local tests. They do not establish AdMob ownership, UMP/SSV console configuration, resolved release-SDK behavior, hosted settlement, or physical rendering. See [Monetization architecture](monetization.md) and the [Data safety evidence worksheet](../operations/google-play-data-safety-evidence.md).

## Permission and capability truth

Permission education does not treat an application preference as proof that a feature works. Its snapshots combine:

1. user intent, such as reminders enabled or exact timing preferred;
2. Android permission, special-access, and location-service state;
3. runtime service truth, such as whether notification delivery is enabled and exact alarms can actually be scheduled; and
4. the derived effective capability: active, degraded, blocked, disabled by the user, unavailable, or not configured.

A manually chosen weather area is active without changing the real OS location state. Device-derived weather requires current approximate-location access and an available location service. Exact alarm access is an optional timing enhancement: when it is not selected or available, reminder scheduling uses the inexact allow-while-idle mode rather than disabling reminders. The canonical permission coordinator owns checks, requests, prompt history, and targeted settings actions. Physical-device behavior across Android variants remains required evidence.

## Transient feedback

Application SnackBars are coordinated through one protected queue. An active Undo opportunity cannot be replaced by passive feedback or an error; only matching non-null batch keys aggregate; Trash and maintenance completion use separate keys; batch Undo runs newest first; finalization runs oldest first; and callback failure cannot strand the queue. Accessible-navigation mode preserves actionable Undo until the user acts or dismisses it. See [Transient feedback and Undo](../development/transient-feedback.md).

## Notifications and background execution

The Android host declares permissions and components required for internet access, optional approximate location, notifications, optional exact alarms, boot handling, wake locks, vibration, foreground data synchronization, and local notification receivers. Background work restores or reconciles reminders and synchronization without introducing fine or background location.

## Backup and restore

HomePilot produces versioned ZIP archives with a manifest and hashes. Restore treats archives as untrusted input, validates compatibility and extraction bounds, creates a safety backup, stages media, applies data, and rolls back on failure.

## Observability

Sentry is optional by configuration. Events are scrubbed and should contain only technical diagnostics. Production workflows associate releases with source and artifacts without uploading user data.

## Build and distribution

`validate-google-backend.yml` is the exact-SHA prerequisite for both Android release rails. It checks Deno formatting, type safety, and tests for AdMob SSV and account deletion; browser deletion and static Google/Android contracts; and Supabase lint/database authorization tests against a local CI stack. A green run is repository/CI evidence, not proof of hosted Supabase deployment.

The manually dispatched Play rail builds and verifies one signed production AAB, captures manifest/dependency/signature evidence, uploads retained Actions artifacts, and attests provenance. It contains no Google Play API upload or rollout step. Play Console acceptance, App Signing, declarations, and device delivery require the separately authorized operator process in the [Google Play release runbook](../operations/google-play-release-runbook.md).

The separately dispatched APK rail validates source and production configuration, builds and inspects one signed non-debuggable APK, captures evidence, publishes the Sentry release, attests provenance, and creates the GitHub Release. Those mutations occur only in the protected workflow; source inspection does not establish that a run succeeded.

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
