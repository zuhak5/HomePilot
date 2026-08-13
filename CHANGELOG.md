# Changelog

HomePilot uses Git history, pull requests, and GitHub Releases as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`. Released versions may be recorded below after their version and build numbers have been finalized.

## Unreleased

### Security and operations

- Activated immediate production containment: cancelled the stale queued Pages
  run, disabled every hosted workflow object that could expose pooled production
  secrets, sign artifacts, mutate backend/release state, write repository
  content, or publish VersionDeck, and unpublished GitHub Pages.
- VersionDeck downloads and the public browser account-deletion page are
  intentionally unavailable during containment. The in-app deletion flow is
  unchanged.
- Preserved the Build 44 tag, GitHub Release, APK/checksum assets, digests,
  attestation, APK/AAB Actions evidence, Sentry release identity, signing keys,
  and historical Pages deployment records without rotation or replacement.
- Recorded redacted evidence, operator ownership, re-enable prerequisites, and
  remaining hosted/device/console limitations in the TASK-001 containment
  record.
- Activated no-bypass reviewed-PR/current-check protection for `main` and
  no-bypass update/deletion protection for production release tags. Direct and
  force pushes plus disposable tag movement/deletion were rejected by hosted
  rules.
- Completed TASK-002 with a dedicated GitHub App installed only on HomePilot
  (Metadata read-only, Contents read/write) as the sole production-tag
  creation bypass. Hosted probes rejected human creation and app
  movement/deletion while permitting one disposable app-created tag; its token
  and private-key material were destroyed after the proof. Production
  containment and later release-rail prerequisites remain in force.
- Pinned all 51 external GitHub Actions references to reviewed full commit SHAs,
  retained exact upstream release labels, and added the fail-closed owner/digest
  contract to the active required validation job with mutable, shortened,
  obfuscated, aliased, and unknown-reference fixtures. Weekly Dependabot
  discovery cannot auto-merge; hosted require-SHA policy and exact-commit CI
  evidence remain separately required before task closure.
- Split production workflow source across dedicated GitHub credential
  environments for Supabase Advisors, Supabase migrations, Play AAB signing,
  standalone APK signing, Sentry publication, GitHub Release/provenance, and
  Pages publication. Advisor and migration rails now use distinct secret names,
  Android signing rails no longer share secret aliases, and the APK release rail
  hands verified artifacts to separate Sentry and GitHub Release jobs. Hosted
  split secret-name placement is complete and the legacy pooled production
  environment no longer holds active secret names. Negative branch-dispatch
  probes and approved exact-main hosted Advisor runs were recorded, closing
  TASK-004 without rotating credentials or performing release/migration
  mutations.
- Added fail-closed VersionDeck publication control and absolute trust leases
  (Task 27, still incomplete as of August 13, 2026). The manifest now carries
  explicit publication state plus `leaseExpiresAt`, the browser disables
  downloads when live or cached trust expires, and the Pages workflow can
  publish an explicit disabled manifest from current `main` without requiring a
  successful APK artifact run first. Verified publication now requires an exact
  reviewed historical decision for any non-ancestor release before it can pass
  verification. The checked-in control file currently keeps VersionDeck
  disabled and records Build 44 as explicitly withdrawn, but the public release
  task still remains blocked fail-closed until the disabled manifest is
  deployed from `main` and hosted/browser evidence is captured.
- Added the backend deletion acknowledgement protocol (Task 08). The
  `account_deletion_operations` table now distinguishes `completed`
  (remote deletion done, client acknowledgement pending) from `acknowledged`
  (local cleanup confirmed terminal). Completed-but-unacknowledged rows are
  retained for 90 days and are never pruned early; the new idempotent
  `acknowledge_homepilot_account_deletion_operation` RPC (service-role only,
  subject-binding-bound) transitions the operation to `acknowledged` and
  resets the GC window to 7 days. A new `remote_boundary_at` column records
  when the Auth-deletion boundary was crossed. Both `begin` and the Edge
  Functions treat `acknowledged` as a completed receipt so old clients
  remain safe.
- Implemented Primary-Photo Dedupe and Constraint Enforcement (Task 25). Added migration `20260817000000_primary_photo_dedupe_and_constraint.sql` with deterministic repair function (`fn_repair_duplicate_primary_photos`) that preserves all photo rows/media while resolving duplicate primary designations. Added partial unique index `idx_asset_photos_single_primary` on `asset_photos(user_id, asset_id) WHERE is_primary = true` to enforce the single primary photo invariant at the database level. Added pgTAP test coverage (`0022_primary_photo_dedupe_and_constraint.test.sql`) and Flutter unit tests (`test/primary_photo_dedupe_test.dart`).
- Implemented Primary-Photo RPC and Compatible Client Adoption (Task 24). Added `set_primary_asset_photo` RPC function (`20260816000000_set_primary_asset_photo_rpc.sql`) to set target photo as primary and clear peer photos for an asset in a single transaction, returning affected canonical rows. Added `setPrimaryAssetPhoto` to `SupabaseSyncGateway`. Added pgTAP test coverage (`0021_set_primary_asset_photo_rpc.test.sql`) and Flutter unit tests (`test/primary_photo_rpc_test.dart`).
- Implemented Media Client Cutover and Staging Saga Integration (Task 23). Updated `SupabaseSyncGateway` to compute local file SHA-256 digests and upload to owner-scoped staging paths (`staging/{user_id}/{photo_id}.jpg`). Executes `stage_media_upload` and `finalize_asset_photo_upload` RPCs with expected row revisions and SHA-256 digests, eliminating canonical photo byte overwrites by stale writers. Added graceful fallback to legacy direct upload if staging RPCs are unavailable or fail. Added unit test coverage (`test/media_client_cutover_test.dart`).
- Implemented Media Backend Staging, Finalize, and Cleanup Saga (Task 22). Added `media_staging_objects` and `media_cleanup_queue` tables with owner-scoped RLS policies (`user_id = auth.uid()`). Added `stage_media_upload` RPC with server-side validation of MIME types (`image/jpeg`, `image/png`, `image/webp`), file size (<=15MB), and SHA-256 digests. Added idempotent `finalize_asset_photo_upload` RPC that validates asset ownership and expected row revision before attaching canonical references, enqueuing replaced media into `media_cleanup_queue` transactionally before database mutation acknowledgement to prevent orphan media accumulation. Added pgTAP test coverage (`0020_media_backend_staging_and_cleanup.test.sql`).
- Implemented Realtime Invalidation and Mixed-Client Convergence (Task 21). Converted Realtime insert, update, and delete callbacks into non-authoritative invalidation hints (`_handleRealtimeDelete`) that schedule incremental pull scans without directly erasing local domain rows, outbox entries, or shadow records. Deletes are applied authoritatively strictly through the ordered change feed pull protocol (`applyRemoteFeedDelete`), preserving newer pending local mutation intent (`LocalSyncMutation.generation`). Guaranteed mixed-client convergence across old and new protocol versions without data loss.
- Implemented Client Pull-Only Cursors and Healing Scan (Task 20). Separated the Change Feed cursor namespace (`server_change_feed` in local SQLite `sync_cursors`) from legacy timestamps and push/point-fetch updates. Push acknowledgements, maintenance completions, and point-fetches update canonical shadows without advancing the change feed cursor. Added ordered pull loop via `fetch_user_change_feed` with `resnapshot_required` handling that triggers explicit re-hydration on retention gaps. Added `runHealingScan` worker using `validate_change_feed_parity()` RPC to discover remote rows absent locally or omitted by legacy cursors while protecting pending local intent (`LocalSyncMutation.generation`).
- Implemented Immutable Outbox Generations and Transactional CAS (Task 19). Incremented Drift schema version to 27. Added monotonic `generation` integer column to local SQLite `offline_mutation_queue` (automatically incremented via triggers on coalesced same-key edits). Outbox mutation operations (`markMutationInFlight`, `markMutationSucceeded`, `markMutationFailed`, `markMutationTerminal`) now execute conditional Compare-And-Swap (CAS) matching `(entity, recordKey, generation)`. If a same-key edit occurs while a network request is in-flight, the older response fails to match `generation`, preserving the newer local intent without outbox data loss. Batch primary key conflict handling runs canonical remote record comparison and applies fetched records before acknowledging completion.
- Implemented Server Change Feed API and Dark Validation (Task 18). Added the `fetch_user_change_feed(p_since_seq, p_limit)` RPC with high-water scan capture, monotonic sequence paging, and `resnapshot_required` boundary checks. Added `get_sync_feed_capability()` RPC for server-controlled feature flagging and instant withdrawal. Added `validate_change_feed_parity()` RPC for dark validation of entity count parity between canonical tables and change feed entries.
- Implemented Server Change Feed Schema and Durable Deletes (Task 17). Added the `server_change_feed` table with monotonic identity sequence (`change_seq`), owner-scoped RLS policies (`user_id = auth.uid()`), and trigger logging (`fn_log_server_change_feed`) across all synchronized domain tables (`areas`, `rooms`, `assets`, `device_details`, `pet_details`, `plant_details`, `safety_details`, `tags`, `asset_tags`, `asset_photos`, `maintenance_plans`, `maintenance_records`, `notifications`, `notification_inbox`, `settings`, `streaks`). Hard deletes log durable `DELETE` records in `server_change_feed`. Added deterministic backfill (`fn_backfill_server_change_feed`) and watermark RPC (`get_user_change_feed_watermark`).
- Implemented Sidecar Registry and deletion-complete cleanup (Task 16). Every restore media sidecar (`.restore-$token` and `.previous-$token`) is durably tracked in `SidecarRegistryStore` in secure platform storage. Added a safe startup sweeper (`sweepOrphans`) that cleans terminal sidecars and legacy orphan directories while preserving active restore journals. Account deletion via `LocalAccountDataCleaner` now enumerates canonical media roots and sidecar directories, ensuring no app-owned media copy survives deletion, and blocks backend acknowledgement if any sidecar deletion fails.
- Implemented deletion client and browser cleanup journal (Task 09). The native
  client persists an atomic versioned cleanup journal (`prepared` → `remoteCompleted` →
  `localDatabaseCleared` → `localFilesCleared` → `localDraftsAndWorkCleared` →
  `localProviderCleared` → `acknowledged` → `terminal`) before clearing its recovery
  store. Ambiguous status or `recovery_not_found` fails closed, maintaining the
  deletion barrier until local cleanup and backend acknowledgement complete. The
  browser deletion flow and Edge Function status handler now support post-deletion
  acknowledgement (`action: "acknowledge"`), updating operation state and GC window.
- Implemented durable legacy-identity quarantine (Task 10). Preserved non-pristine local
  data from an unsupported provider or unbound session enters durable upload-prohibited
  quarantine (`uploadProhibited = true`, `migrationState = 'quarantined'`) with Drift schema v26.
  Auto-binding and auto-upload under a different Google user are strictly prevented. Users
  are provided localized English and Arabic UX options to Export Safety Backup, Reset Local
  Data (Start Fresh), or Explicitly Import/Merge data into their account.
- Implemented central sign-out barrier and account-guarded background workers (Task 11).
  All sign-out, session-loss, remote revocation, and startup unsupported session cleanup
  paths use an awaited sign-out sequence that suspends sync, cancels account-scoped
  WorkManager jobs (`dailyRefreshTask`, `cloudSyncBackgroundTask`, `restoreRecoveryTask`),
  clears scheduled notifications, local inbox rows, and reminder snapshots, and unbinds local
  account state. WorkManager background worker callbacks fail closed behind an account entry
  guard verifying valid session, bound account match, and non-quarantined status before
  executing domain reads, streak mutations, inbox writes, or weather HTTP requests.
- Implemented charged-operation backend status and exact replay contract (Task 12). Added SHA-256
  request hashing and advisory locking (`pg_advisory_xact_lock`) parity to `create_asset_with_point_debit`
  and introduced the authorized RPC `get_charged_operation_status(operation_id, request_hash)` with
  capability version `1.1.0`. The contract allows lost-response client recovery without double-debiting
  points, while strictly isolating lookups to the authenticated owner (`not_found` returned for
  cross-user queries).
- Implemented charged-operation client journal, pre-RPC durable writing, and retention (Task 13). Every
  charged operation (asset creation, asset copy, task creation) writes a durable secure-storage journal
  entry before network RPC submission; failure to persist durably prevents remote execution. Added
  `ChargedOperationResolver` to reconcile ambiguous `outcomeUnknown` operations via `get_charged_operation_status`
  and exact-resubmit using the original operation ID when backend confirms `not_found` under capability `1.1.0`.
  Terminal states (`reconciled` and `permanentRejected`) automatically purge user-entered payload content
  (`purgeTerminalPayloads`) to enforce bounded retention.
- Implemented durable restore journal and coordinator barrier (Task 14). Restore is now a versioned, multiphase
  state machine backed by `RestoreJournalStore` in secure local storage. Acquires a restore barrier (`onBeforeRestoreBarrier`)
  that suspends `SyncCoordinator`, cancels WorkManager background jobs, and clears scheduled notifications before live
  database mutation. Introduced `RestoreJournalResolver` at startup to deterministically roll back pre-DB-commit
  phases (`validated`, `safetyBackupComplete`, `servicesSuspended`, `mediaStaged`) or roll forward post-commit phases
  (`dbCommitStarted`, `dbCommitComplete`, `mediaSwapped`, `cloudIntentDurable`), while enforcing a downgrade guard
  that blocks execution if a journal's version is newer than supported (`kCurrentRestoreJournalVersion`).
- Bound Android release provenance to the exact source/workflow tuple (Task 26). The AAB and APK rails now retain trusted workflow context, exact `gh attestation verify --format json` output, and a normalized tuple report that requires repository, source digest/ref, signer workflow identity/digest, workflow trigger, runner environment, and workflow run URI to match one exact artifact. GitHub Release notes, operator runbooks, and VersionDeck now publish and verify that exact tuple rather than a repository-only attestation claim, and ambiguous or incompatible attestations fail closed.

## 1.5.0 (Build 44) — 2026-08-09

### Fixed and Improved

- **App-wide feedback placement**: Removed duplicated route-specific bottom-navigation, safe-area, keyboard, footer, and floating-action offsets. Floating feedback now relies on the active Scaffold's real obstruction geometry and keeps one consistent 12-dp visual gap, preventing Trash Undo and ordinary toasts from appearing unnecessarily high.
- **Modal-safe feedback**: Feedback triggered from bottom sheets, including rewarded-ad actions in the points wallet, now uses the root overlay so it remains visible and interactive above the sheet and modal barrier while preserving the shared queue, Undo, timeout, and dismissal rules.
- **Settings polish and resilience**: Added clearer card and subsection hierarchy, consistent icon surfaces, inset permission and preference groups, responsive capability status rows, and a full-width exact-alarm recovery layout whose status and Fix action no longer squeeze the title. Added narrow 180%-text English/Arabic coverage and refreshed both Settings golden baselines.
- **Dashboard and task-list polish**: Moved the current-location indicator beside the weather area, redesigned the points star badge, added proper trailing breathing room, retained the useful sticky dashboard header with a blurred graded boundary, and replaced abrupt page-top color seams with smooth theme-aware gradients.
- **Consistent native ads**: Native cards and their loading state now use the same lowest card surface as task/content cards in light and dark themes. Every routed application content screen declares a collapsible native-ad placement, including task detail, Inbox, capability setup, and all Tools destinations; splash, authentication, system permission UI, dialogs, and sheets remain ad-free.
- **Less confusing secure account deletion**: Recent same-account Google verification now tries the already signed-in account silently and opens Google's account chooser only when lightweight verification is unavailable. Same-user validation and the protected deletion/recovery protocol remain mandatory.
- **Quiet optimistic conflict recovery**: Revision-mismatched cloud updates and deletes now use zero-or-one list responses, preventing expected PostgREST 406 warning entries while preserving canonical fetch and conflict reconciliation.
- **Visible zero-points recovery**: A depleted wallet is now returned by creation RPCs as a structured HTTP-success business result instead of a PostgREST 400 warning. Task creation preserves the exact rejection reason, and task/item editors keep an accessible recovery dialog visible with the current balance, retryable rewarded-ad action, and explicit unavailable, dismissed, rejected, or verification-pending state.
- **Hosted Supabase Advisor gate**: Added a protected, read-only GitHub Actions audit of both security and performance Advisors. It uploads sanitized evidence and fails on every error, warning, or information finding except the explicitly retained `Leaked Password Protection Disabled` notice.
- **Hosted Advisor remediation**: Added an explicit service-role-only policy for private deletion-recovery operations, removed nine hosted-statistics-confirmed obsolete indexes, and retained four low-traffic covering indexes required for Auth-user and live relationship cascade cleanup without granting client access.
- **Confirmed Supabase migration rail**: Added a manual production workflow that requires the exact current `main` SHA, exact project ref, explicit confirmation, protected credentials, a pre-apply dry run, and a post-apply no-pending verification. It never repairs migration history or broadens the pending set automatically.
- **Protected migration target validation**: Moved the `SUPABASE_URL` project-ref check into the protected production job where environment-scoped variables are available, while retaining the pre-environment exact-SHA and explicit-confirmation gate and validating project identity before the Supabase CLI can link.
- **Task dependencies retired**: Removed the user-facing Dependency tasks feature from editors, details, offline drafts, domain models, render fingerprints, Drift and Supabase schemas, creation RPCs, sync DTOs, localization, tests, and documentation. The separate completion-outbox predecessor remains in place for safe causal synchronization.

### Compatibility and evidence boundaries

- Drift advances from schema 24 to 25 and preserves tasks and remaining metadata while discarding only retired dependency links. The backup ZIP format is unchanged; restored schema-24 databases migrate on open.
- The forward Supabase migration `20260809193000_remove_task_dependencies.sql` must be applied before releasing this client. It preserves RLS, point authority, creation idempotency, and the unrelated completion causal-order contract while normalizing insufficient points into a non-writing structured business result.
- No Android permission declaration, permission request timing, notification scheduling behavior, external dependency, or ad-consent gate changed.
- Automated coverage verifies Scaffold and modal-overlay feedback geometry, responsive English/Arabic Settings layouts, native-ad placement/palette contracts, same-account deletion fallback behavior, zero-row sync handling, structured insufficient-points behavior with no entity write, persistent shortage recovery UI, and schema-24-to-25 task preservation. Physical-device confirmation is still required for OEM navigation modes, keyboard transitions, TalkBack, Google chooser behavior, rewarded-ad availability/verification, and final light/dark ad and layout rendering.

## 1.5.0 (Build 43) — 2026-08-09

### Fixed and Improved

- **Truthful startup surface**: Made the process splash the earliest Flutter presentation, removed blank bootstrap/theme gates and duplicate ownership, preserved one application topology, and added reduced-motion, lifecycle, compact-layout, English, and Arabic coverage.
- **Permission and capability orchestration**: Separated user preferences, Android permission/special-access state, service availability, manual weather configuration, and effective capability. Notification preferences no longer trigger unrelated prompts, and exact timing remains an optional contextual capability.
- **Protected transient feedback**: Made active Undo feedback non-preemptible, limited batching to compatible operations, refreshed visible batch counts and deadlines, guaranteed exactly-once action/finalization handling, and added Undo restoration for task, asset, room, and area Trash actions.
- **Ad runtime hardening**: Added one lifecycle/consent/config eligibility model, generation invalidation, bounded classified retry with jitter, dormant exhaustion, a 55-minute freshness ceiling, explicit leases/disposal, full-screen serialization, and stale-callback rejection without moving reward authority to the client. Network failures now use four automatic retries near 2, 8, 30, and 60 seconds (each with ±20% jitter); internal/unknown failures use two near 2 and 8 seconds; no-fill and invalid requests remain dormant without automatic retry.
- **Native ad parity**: Transported one schema-versioned app palette to Android, applied the complete app-owned card/badge/CTA chrome atomically, registered AdChoices and creative assets, and safely hid absent optional assets.
- **Google authentication and deletion**: Serialized native Google initialization with retry after failure, kept ordinary sign-out distinct from authorization disconnect, removed the obsolete Google Services example, and replaced the simulated public deletion page with authenticated Supabase Google OAuth PKCE and strict deletion-receipt verification. Flutter and the public page now create one cryptographically secure recovery key per logical deletion, reuse it for ambiguous-response/status recovery, retain it only in secure platform storage or browser `sessionStorage` while unresolved, and accept completion only from an authoritative same-user receipt.
- **Backend and release evidence**: Added backend SSV/Edge Function/database/static-contract CI, deletion-status Deno and cross-client/server schema gates, corrected the Play AAB rail, and added merged-manifest, dependency, version, permission, AdMob-ID, upload-certificate, checksum, and provenance evidence gates. The standalone APK/VersionDeck and Play AAB paths remain separate and no Play publication is automated.
- **Regression stabilization**: Corrected dashboard teardown so native-ad presentation depth is released only while Riverpod remains mounted, aligned capability/settings widget fixtures with the actual permission model, and replaced four stale notification/settings golden baselines with the intended English and Arabic screens.
- **Documentation truthfulness**: Added capability, feedback, Google Play, Data Safety, account-deletion, and release guidance; marked historical plans and network measurements as historical; and corrected privacy and Build 35 completion claims.

### Compatibility and evidence boundaries

- No Drift schema or backup-format migration is introduced by this release.
- The forward Supabase migration `20260809120000_add_account_deletion_recovery.sql` must be applied before deploying the compatible `delete-account` and `account-deletion-status` functions or releasing clients that require the recovery protocol.
- No fine-location or background-location permission is added.
- Repository tests and CI evidence do not substitute for physical-device accessibility/permission/ad testing or Google Play, AdMob, OAuth, UMP, and Play App Signing console verification; those remain explicitly documented operator checks.

## 1.4.9 (Build 35) — 2026-08-08

> **Correction (2026-08-09):** This historical entry overstated several incomplete implementations as a finished remediation program. Build 35 contained partial foundations, but it did not provide a functional external deletion flow, the complete ad runtime/capability/feedback contracts, backend CI, or exercised Play AAB evidence. The bullets below are retained as historical repository notes, not proof of current implementation or release validation. The completed code-side remediation is recorded under 1.5.0 (Build 43).

### Fixed and Improved

- **Master Remediation & Hardening Program**: Completed comprehensive multi-domain hardening across startup/splash topology, permissions, transient feedback, ad runtime, Google authentication, external account deletion compliance, and release workflows.
- **Process-Scoped Single Splash Root**: Consolidated application bootstrapping into a single stable `MaterialApp.router` root with one process-scoped `HomePilotSplashOverlay` owner, eliminating startup theme flashes and duplicate splash overlays across authentication transitions.
- **Capability Domain Model & Permission Separation**: Decoupled user intent, OS permissions, and `EffectiveCapabilityState` (`active`, `degraded`, `blocked`, `disabledByUser`, `notConfigured`, `unavailable`). Exact reminder timing defaults to `false` for new installs. Integrated `canScheduleExactNotifications()` from `flutter_local_notifications` for precise exact alarm capability checks.
- **Unified Transient Feedback Coordinator & Protected Undo**: Introduced `FeedbackCoordinator` to manage app-wide floating SnackBars, queueing non-error messages behind active Undo opportunities, supporting LIFO batching, and providing accessible timeout management.
- **Ad Runtime State Machine & Native Ad Parity**: Enforced UMP consent validation at load/show time, 55-minute cache expiration (`kAdCacheMaxAge`), epoch token invalidation for background transitions, and bounded exponential backoff with jitter. Updated `HomePilotNativeAdFactory.kt` and `AdChoicesView` layout binding for app theme parity.
- **Google Auth Hygiene & Play Account Deletion Page**: Added `disconnect()` to `GoogleSignInGateway` with a safe initialization retry gate. Created public `account-deletion.html` web resource in `download-site/` for Google Play policy compliance.
- **Play Store AAB Rail & Release Pipeline**: Added `tool/build_play_prod.ps1` and `.github/workflows/build-play-android.yml` for production Android App Bundle (AAB) builds and signature verification.

## 1.4.8 (Build 34) — 2026-08-08

### Fixed and Improved

- **V3 Non-Blocking Permission Education Overlay**: Refactored `PermissionEducationController` to Riverpod `Notifier` and updated `PermissionEducationOverlayWidget` with modern Material Design cards, step indicators, accessible tap barriers, and smooth reduced-motion handling.
- **Isolated Pure Splash Overlay**: Stacked `HomePilotSplashOverlay` at the root above `MaterialApp` to ensure pure presentation without interference from background routing or state.

## 1.4.7 (Build 33) — 2026-08-08

### Fixed and Improved

- **Pure Animated Splash Screen Overlay**: Activated `HomePilotSplashOverlay` as a purely visual, fixed-duration (3.2s display + 250ms fade) startup overlay placed above the running application root, isolated from app state, network, or navigation.
- **Capability-Based Permission Setup & Local v3 State**: Migrated permission education to a device-local state (`permission_education_device_state_v3`) to prevent cross-device setting sync from suppressing setup on fresh devices.
- **Contextual Exact Alarms & Optional Weather Area**: Removed exact alarm requests from first-run onboarding, redesigning Step 1 as a permission-optional weather area setup offering manual city selection alongside current location.
- **Location Coordinate Quantization**: Quantized device coordinates to 2 decimal places prior to persistence, weather queries, and account sync to preserve user location privacy.
- **Recurring Maintenance Completion Precision & Reconciliation**: Fixed recurring task completion rollback by standardizing protocol timestamps to whole-second UTC precision across Flutter, Drift/SQLite, outbox payloads, and Supabase.
- **Supabase RPC Migration**: Applied migration `20260807223000` to canonicalize occurrence timestamps in `complete_maintenance_task`, self-healing existing legacy cloud plans with sub-second precision.
- **Dependency & Ordering Defense**: Enforced topological readiness in `LocalSyncStore.pendingMutations()` so dependent completion operations are held in outbox until predecessor operations resolve.
- **Reconciliation & Shielding**: Protected optimistic local plan state during rejection or remote winner reconciliation, extended `pendingChangedAt` for composite plan pull shielding, and added single-flight controller entry guards.
- **Synced Undo State Guard**: Restricted local Undo to unacknowledged outbox operations to prevent client/cloud data desynchronization.

## 1.4.6 (Build 32) — 2026-08-07

### Fixed and Improved

- **Maintenance Completion Payload V2 Support**: Fixed `complete_maintenance_task` RPC on Supabase to support version 2 operation payloads (`"version": 2`). The Flutter client sends payload v2 for causal ordering (`depends_on_operation_id`), but the RPC previously rejected version 2 payloads with `invalid_payload_version`, causing task completions to revert locally. Applied migration `20260807154500` to live Supabase (`iajvkvvvhwjdiuaufymh`).

## 1.4.5 (Build 31) — 2026-08-07

### Fixed and Improved

- **Startup Cloud Restore Timeout Enforcement**: Wrapped `SyncCoordinator.enable()` during `cloud_restore` with `startupRestoreTimeoutProvider` (140s), preventing indefinite UI hangs on startup.
- **Overdue Task Completion & Payload Nullability Fix**: Fully deployed updated `complete_maintenance_task` RPC validation rules to live Supabase (`iajvkvvvhwjdiuaufymh`), ensuring task completion and due date advancement persist for all maintenance tasks.

## 1.4.4 (Build 30) — 2026-08-07

### Fixed and Improved

- **Overdue Task Completion & Payload Nullability Fix**: Fixed `complete_maintenance_task` RPC validation rules on Supabase to correctly accept overdue task completions (`plan_next_due_date <= record_due_date` instead of `record_completed_at`) and safely coalesce unconfigured `reminder_days_before` values. Fully deployed to live Supabase (`iajvkvvvhwjdiuaufymh`) and verified.

## 1.4.4 (Build 29) — 2026-08-07

### Fixed and Improved

- **Complete Maintenance Task & Task Creation Remediation**: End-to-end remediation of task creation and task completion RPCs, widget test provider identity overrides, operation journaling fallback, and notification inbox reconciliation. Fully verified by Flutter test suite (383/383 passing) and Supabase pgTAP database test suite (252/252 passing).

## 1.4.3 (Build 28) — 2026-08-06

### Improved

- **App Header Refactoring**: Completely modularized and redesigned the dashboard header for responsiveness and clarity. Unnested the monolithic pill container into floating components on a transparent canvas.
- Responsive search placeholder text and control sizing based on exact device width.
- Replaced the external notification badge with an inline 8px dot inside the bell icon button.
- Replaced the legacy points pill with a compact squircle tile featuring a solid emerald star badge.

## 1.4.2 (Build 27) — 2026-08-06

### Fixed and Improved

- **Reward Claims Request Optimization**: Replaced `reward_claim_requests` `.stream()` polling loop (22 calls/4 min) in `MonetizationRepository` with `fetchPendingRewardClaims` returning a `FutureProvider` one-shot query, eliminating approximately 95% of reward claim REST API traffic.
- **Stuck Outbox Row Observability & Abandonment**: Added `listFailedVisibleDetails` and `abandonStaleFailedVisibleMutations` in `LocalSyncStore`. `SyncCoordinator` now emits `sync_failed_visible_detail` structured logs for failed outbox entries and auto-abandons stale mutations older than 7 days (`sync_outbox_abandoned`).
- **AdMob Firebase Integration**: Added `com.google.firebase:firebase-analytics` and Google Services Gradle plugin configuration to resolve the AdMob SDK Firebase integration warning and enable enhanced targeting.
- **AdMob Application-Layer Structured Logging**: Added structured `AppLogger.info` lifecycle events (`ad_load_requested`, `ad_loaded`, `ad_load_failed`, `ad_impression`, `ad_rewarded`, `ad_show_completed`) to `HomePilotAdsService`.
- **Network Request Usage Audit**: Added a comprehensive network architecture review and request-usage audit report in `docs/request-audit-report.md`.
- **VersionDeck Deployment Reliability**: Upgraded the GitHub Pages actions to their Node.js 24-compatible major versions, serialized production deployments without cancelling an active publish, and extended Pages deployment polling to tolerate slow but healthy deployments.

## 1.4.1 (Build 26) — 2026-08-06

### Fixed and Improved

- **Maintenance Completion Conflict Resolution**: `SyncCoordinator` now acknowledges and applies canonical remote plan/record snapshots when non-retryable 409 conflicts occur, clearing `failed_visible` mutations automatically.
- **AdMob Lifecycle & Listener Recovery**: Added `_pendingAd` lifecycle tracking in `_HkNativeAdCardState` to ensure `onAdFailedToLoad` triggers failure handling and exponential retry backoff without dropped callbacks.
- **Profile Avatar 404 Resilience**: Added `onError` stream error handling to `precacheImage` in `ProfileAvatar` to absorb HTTP 404 network image exceptions cleanly and render initialed fallback avatars.
- **AdMob SSV Edge Function Test Payloads**: Updated `isAdmobSetupVerificationProbe` in `admob-ssv-handler` to accept synthetic `fakeForAdDebugLog` test payloads as `verified_debug_noop` (HTTP 200), preventing 400 validation log noise.

## 1.4.0 (Build 25) — 2026-08-06

### Fixed and Improved

- **Database & Sync Contracts**: Aligned `user_settings_key_check` PostgreSQL constraint to include `permission_education_seen_v2`. Enforced pre-enqueue validation against Dart setting key allowlist (`userSettingSyncSpec`).
- **Composite Task Creation**: Extended `create_task_with_point_debit_impl` RPC to return canonical `plan` and `metadata` JSON. Implemented `acknowledgeTaskCreationComposite` in `LocalSyncStore` to apply canonical rows and clear outbox entries atomically without redundant POST attempts.
- **Batch Conflict Recovery**: Updated `writeNewBatch` handling in `SupabaseSyncGateway` and `SyncCoordinator` with `BatchWriteResult`. 23505 primary key conflicts fetch/merge canonical records directly instead of issuing second blind inserts.
- **Failed Mutation Diagnostics**: Implemented single-row `resolveFailedMutation` (`dismiss`, `retry`, `acknowledge`) and `exportFailedMutationDiagnostics()` with strict DLP PII scrubbing.
- **AdMob SSV Edge Function**: Updated setup probe response mode to `verified_debug_noop` with `credited: false` and `duplicate: false`.
- **Realtime Observability**: Added ephemeral process instance ID, channel lifecycle tracking, and active subscription count metrics.
- **Startup Performance**: Instrumented release-safe startup spans and added cold launch performance benchmarks.

## 1.3.9 (Build 24) — 2026-08-05

### Maintenance and governance

- Added a mandatory documentation-maintenance policy for humans, AI coding agents, automated agents, bots, and reusable Agent Skills.
- Required documentation-impact review and same-pull-request documentation updates for every repository change.
- Added a subsystem-to-document impact matrix covering application behavior, architecture, data, synchronization, Supabase, authentication, monetization, backups, permissions, observability, releases, VersionDeck, localization, testing, and agent workflows.
- Added a pull-request template requiring documentation, validation, privacy, synchronization, permission, compatibility, and release-impact reporting.
- Updated repository agent instructions, contributor guidance, documentation governance, and Agent Skill audit/update procedures.
- Chained VersionDeck deployment to successful protected production APK workflow completions while preserving independent release verification and manual/release recovery triggers.

### Compatibility

- No application runtime behavior changed.
- No database migration is required.
- No permissions, synchronization protocol, backup format, privacy behavior, or account behavior changed.
- No user action is required.
- Existing local data, accounts, settings, backups, and synchronization state remain compatible.

## 1.3.8 (Build 23) — 2026-08-04

### Improved

- Improved the VersionDeck live production-build experience on mobile devices.
- Grouped technical build steps into clearer, easier-to-read phases.
- Improved progress, ETA, freshness, and target-version information.
- Refined the build timeline with consistent completed, active, and upcoming states.
- Clearly separated the current stable APK from a newer build that is still in progress.
- Improved long-text wrapping, narrow-screen layouts, scrolling, accessibility, and reduced-motion support.

### Maintenance

- Reconstructed project documentation covering product behavior, architecture, synchronization, authentication, account deletion, monetization, backup and restore, Supabase, Sentry, testing, localization, privacy, releases, VersionDeck, and agent workflows.
- Added repository-level contribution, security, privacy, and agent operating policies.
- Added operational runbooks and architecture decision records for release verification, observability, and offline-first synchronization.
- Aligned the development Supabase example URL with the local API port declared in `supabase/config.toml`.

### Compatibility

- No database migration is required.
- No user action is required.
- Existing local data, accounts, settings, backups, and synchronization state remain compatible.

## Historical releases

For released versions, checksums, Android artifacts, and release notes, use GitHub Releases and the independently generated VersionDeck manifest. Earlier repository history includes the addition of authenticated Supabase synchronization, conflict recovery, account deletion, Sentry observability, points and advertising workflows, backup protections, and VersionDeck release verification.

## Maintenance rules

Add entries under `Unreleased` when a change is:

- User-visible.
- Security- or privacy-relevant.
- A data migration or compatibility change.
- A material synchronization or backend protocol change.
- A new or changed permission, SDK, external service, or operational dependency.
- A release, deployment, backup-format, VersionDeck trust-chain, documentation-governance, or agent-workflow change.

Do not add routine refactoring, formatting, generated-file refreshes, or test-only changes unless they materially affect contributors or operators.
