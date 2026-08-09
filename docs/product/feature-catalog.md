# Product Feature Catalog

## Product purpose

HomePilot helps users inventory household assets and keep recurring or one-time maintenance work visible, scheduled, and recoverable across offline and signed-in use.

The first Flutter frame is owned by one process-lifetime splash above deferred startup, theme loading, application, and failure branches. A non-blank startup surface remains available underneath. English/Arabic semantics, scaled compact layout, and reduced-motion behavior are part of the widget contract; a physical release launch still requires device validation.

## Navigation surfaces

The current application exposes dashboard, assets, maintenance, calendar, search, trash, statistics, settings, account, backup, notifications, capability setup at `/permissions/setup`, and additional utility surfaces through GoRouter. `/profile` redirects to `/account`. The route definitions in `lib/main.dart` remain authoritative.

## Organization model

- Areas and rooms organize the home.
- Categories classify assets.
- Assets represent maintained things and can carry tags, photos, notes, warranty information, and type-specific detail.
- Specialized detail models support devices, pets, plants, and safety-related assets.
- Trash and cleanup flows protect against accidental permanent deletion. Moving a task, asset, room, or area to Trash offers restoration through the protected Undo coordinator; permanent deletion remains separately confirmed.

## Maintenance

- One-time and recurring maintenance plans.
- Due, overdue, completed, and historical views.
- Completion history and attachments.
- Calendar integration and date-based filtering.
- Recommendations, timelines, readiness or health summaries, streaks, and warranty alerts.
- Local reminders that can be restored after reboot or application update.

Maintenance completion is a synchronized, idempotent operation. UI changes must not bypass repository and synchronization semantics.

Transient feedback has one protected queue. Passive messages and errors wait behind an active Undo opportunity, compatible operations batch only under an exact non-null key, Trash never batches with maintenance completion, and accessible-navigation mode keeps actionable Undo available until action or dismissal. See [`transient-feedback.md`](../development/transient-feedback.md).

## Search and insights

- Search across supported home and maintenance data.
- Statistics and chart-based summaries.
- Dashboard summaries and actionable status.
- Health, readiness, and warranty indicators where data is available.

## Accounts and synchronization

- Google-based production sign-in.
- Offline-first local operation.
- Authenticated Supabase synchronization.
- Initial hydration, incremental pull, queued local changes, retry, realtime invalidation, and conflict recovery.
- Account deletion with recent reauthentication and coordinated local/remote cleanup.
- A public VersionDeck deletion page that authenticates with Google OAuth PKCE through Supabase, requires explicit confirmation, and invokes the protected deletion function with the signed-in bearer token.

Signed-out or offline operation must remain explicit; the application should not imply cloud protection when synchronization is unavailable.

The public page is not an anonymous deletion endpoint. It accepts success only when the protected function returns a deletion receipt for the authenticated user. Repository coverage does not prove the page, OAuth redirect configuration, or Edge Function is deployed to production.

## Notifications and background work

- Local notification permission education.
- A capability-setup surface that distinguishes application preferences from Android permission/special-access state, service availability, scheduler truth, and effective feature state.
- Manual weather-area selection without requesting device location; the real OS location state remains unchanged.
- Optional exact-alarm scheduling when exact timing is selected and available, with inexact allow-while-idle scheduling as the reminder fallback.
- Boot and application-update restoration.
- Foreground data-sync capability and Workmanager for bounded background work.
- Time-zone-aware reminders.

The first-dashboard education flow considers weather-area and notification setup; it does not pressure users for exact-alarm access. Exact timing is surfaced from settings or reminder/task scheduling context. Denied or unavailable access must leave useful manual-weather, in-app inbox, and inexact-reminder paths where their prerequisites are met.

## Backup and restore

- Versioned ZIP backups.
- Manifest and cryptographic hash validation.
- Media inclusion and staging.
- Retention of automatic backups.
- Pre-restore safety backup.
- Compatibility checks and rollback on failure.

Backups exported outside the app are user-controlled sensitive files.

## Monetization

- Consent-aware Google Mobile Ads integration.
- Native, interstitial, rewarded, and rewarded-interstitial experiences where configured.
- Fail-closed runtime gates for supported platform, resumed lifecycle, refreshed consent, UMP permission, global enablement, and per-format switches.
- Bounded retry/dormancy, 55-minute ad freshness, exact-once native ownership, and one shared fullscreen presentation gate.
- Server-authoritative points wallet.
- Point-gated creation through backend RPCs.
- Server-side verification and replay-resistant reward claims.
- Explicit unfinished drafts when charged creation cannot be completed offline.

Ads and points must not become the authority for core domain data.

Repository tests cover the application eligibility, ownership, native schema, and reward-security contracts. AdMob/UMP console state, provider ownership, hosted SSV settlement, merged release dependencies, and physical-device presentation remain external release evidence. See [Monetization architecture](../architecture/monetization.md).

## Localization and accessibility

- English and Arabic localization.
- Right-to-left layout for Arabic.
- Locale-aware dates, numbers, plurals, and placeholders.
- Accessible labels, scalable text, focus behavior, protected actionable feedback, and reduced-motion behavior for startup and navigation.

## Observability

Sentry provides technical error and performance diagnostics when enabled. The intended policy excludes user content and direct identifiers and disables screenshots, session replay, view hierarchy, and raw HTTP payload capture.

## Distribution

Release validation begins with an exact-SHA backend workflow covering Edge Functions, browser deletion/static contracts, and local-stack database security. Separate protected rails then produce a Play AAB and a standalone APK. The AAB rail creates evidence and provenance but does not upload to Google Play; Console upload and rollout require explicit operator authorization and evidence. The APK rail can publish Sentry state and a GitHub Release, after which VersionDeck independently verifies release identity before exposing a download. Workflow source is not evidence that any hosted run, upload, release, or deployment succeeded.

## Product change checklist

A new feature is complete only when its local data, cloud data, synchronization, localization, permissions, privacy, backup, deletion, tests, documentation, and release implications have been reviewed.
