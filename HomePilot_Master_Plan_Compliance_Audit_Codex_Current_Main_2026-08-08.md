# HomePilot Master Remediation Plan Compliance Audit — Codex Current-Main Handoff

**Audit date:** 2026-08-08  
**Fresh GitHub recheck for Codex handoff:** 2026-08-08  
**Target consumer/executor:** OpenAI Codex coding agent  
**Repository:** `zuhak5/HomePilot`  
**Audited branch:** `main`  
**Current audited HEAD (freshly re-confirmed):** `1f2084069bb8e278c8e8974e83193659f5cf4c32`  
**Remediation PR:** #24 — `Release master remediation to main`  
**Master-plan baseline:** `075cd6ff5c36bb9c05b03f10a20598310ecf000d`  
**Current app version:** `1.4.9+35`


## Codex execution handoff

This audit is not merely a review artifact. Use it as the **current-main delta checklist** for implementation.

### Fresh recheck result

GitHub `main` remains at `1f2084069bb8e278c8e8974e83193659f5cf4c32` (`Release master remediation to main (#24)`), and `pubspec.yaml` remains `1.4.9+35`. No newer commit was found during this adaptation, so the audit's branch baseline remains current.

A fresh path-level check also reconfirmed the most consequential findings:

- `lib/main.dart` still exposes `_DeferredHomePilotBootstrap` and `startup-theme-placeholder` blank Flutter surfaces before `HomePilotSplashOverlay`;
- manual weather selection still records `AppPermissionState.granted`;
- the feedback coordinator still allows error/destructive feedback to finalize and hide an active Undo;
- monetization retries remain uncapped in count and cached ads lack the planned centralized freshness contract;
- `download-site/account-deletion.js` still simulates authentication and deletion with `setTimeout()` and no backend request;
- `native_google_sign_in.dart` has `disconnect()` but retains the concurrent failed-initialization clearing race;
- `android/app/google-services.json.example` remains;
- the workflow directory still lacks dedicated backend SSV/database/Google validation.

### Codex mandate

1. Read repository `AGENTS.md` and `docs/governance/documentation-maintenance.md` before editing.
2. Re-run `git status`, `git rev-parse HEAD`, and `git log -1 --oneline`.
3. If `main` has moved beyond `1f2084069bb8e278c8e8974e83193659f5cf4c32`, do a scoped drift audit; never force-reset to this audit's SHA.
4. Preserve already-correct parts of PR #24 rather than replaying the historical master prompt wholesale.
5. Correct false documentation claims early, especially the external account-deletion and "completed remediation" claims.
6. Implement the remaining requirements in focused, reviewable changes with target tests.
7. Never weaken RLS, SSV, reward authority, signing checks, privacy boundaries, production/test ad separation, or account-deletion authorization.
8. Never claim device, Play Console, AdMob, Google Cloud/OAuth, hosted Supabase, Pages, signing, or protected-workflow verification unless evidence was actually observed.
9. Do not push/deploy/publish/trigger protected production workflows or destructive hosted operations without explicit operator authorization.
10. Final output must enumerate code changed, tests run, documents updated, remaining operator actions, and all unverified evidence.

### Recommended Codex execution order

- **P0 truthfulness:** disable/remove fake deletion success behavior and correct contradictory `PRIVACY.md` / 1.4.9 changelog claims.
- **P0 deletion:** build the real authenticated external deletion flow and its tests.
- **P0 monetization safety:** runtime eligibility, lifecycle/config/consent gates, generation invalidation, bounded retry, 55-minute freshness, ownership/fullscreen tests.
- **P1 permissions:** capability snapshots, canonical platform gateway, manual-location semantics, target-specific settings, deterministic resume, pure preference persistence.
- **P1 splash:** first usable Flutter frame must contain the process splash while preserving the stable Material/router/messenger ownership already landed.
- **P1 feedback:** protected Undo policy, visible batching/deadline reset, semantic rendering/placement/a11y, migrate all Trash and legacy transient call sites.
- **P1 hygiene:** finish native-ad theme contract, Google init identity guard, remove obsolete Google Services example if no longer needed, add no-Analytics guard.
- **P1/P2 release:** backend CI gate and Play AAB evidence bundle.
- **Final:** documentation synchronization, full automated validation, then clearly separate unperformed device/console/hosted verification.

---

## Executive verdict

The current repository **does not satisfy the final HomePilot Master Remediation Plan**.

PR #24 contains some real and useful changes—particularly a stable `MaterialApp.router` splash owner, exact-alarm capability checks through `flutter_local_notifications`, removal of direct Firebase Analytics packaging, Google `disconnect()` support, basic native-ad theme options/AdChoices binding, and a separate Play AAB workflow.

However, several of the master plan's core requirements remain unimplemented, and multiple changelog/privacy claims describe functionality that the current code does not actually provide.

The highest-severity gap is the external account-deletion page: its JavaScript simulates authentication and deletion with `setTimeout()` calls. It does not authenticate with Google/Supabase, does not call the protected `delete-account` Edge Function, and nevertheless tells the user that the account and cloud data were deleted. That should be treated as a release blocker for Google Play.

Other major gaps include:

- the animated Flutter splash is still mounted after blank Flutter placeholders;
- the permission model still conflates manual weather configuration with OS location permission;
- notification settings still persist preferences and then request permissions for unrelated preference changes;
- the new feedback coordinator can still destroy active Undo feedback and the non-task Trash flows still have no Undo;
- the planned monetization runtime state machine, generation invalidation, bounded retry policy, and 55-minute ad cache control are absent;
- backend SSV/database validation was not added to CI;
- the Play AAB workflow exists but has never been run on `main`;
- documentation/changelog/privacy claims materially overstate implementation status.

A green existing Flutter CI run and successful production APK build show that the merged code compiles and passes the repository's current automated suite. They do **not** demonstrate compliance with the master plan, because some existing tests still encode behavior the plan explicitly required replacing.

---

# Compliance scorecard

| Master phase | Status | Audit conclusion |
|---|---|---|
| Phase 0 — baseline / branch / inventory | PARTIAL | Correct baseline and remediation branch were used, but implementation was one omnibus commit rather than small reviewable phase commits; no full phase evidence report. |
| Phase 1 — target characterization tests | FAIL | Major target tests were not added; old tests that encode known defects remain. |
| Phase 2 — stable root / single splash owner | MOSTLY PASS | One stable `MaterialApp.router` and one production splash owner now exist. |
| Phase 3 — earliest splash / continuity / reduced motion | FAIL | Reduced-motion handling improved, but blank pre-splash Flutter placeholders remain and stale timing APIs remain. |
| Phase 4 — capability domain / canonical permission layer | FAIL | Only `EffectiveCapabilityState` enum/default and exact-alarm API work landed. Manual location still fakes OS grant; duplicate permission implementations remain. |
| Phase 5 — settings / setup / weather / scheduler UX | FAIL | Original persistence-before-permission and unrelated-prompt behavior remains; setup UI remains OS-permission-centric/hardcoded. |
| Phase 6 — unified feedback foundation | PARTIAL / FLAWED | Model/coordinator introduced, but policy, rendering, batching, accessibility, and finalization semantics do not meet the plan. |
| Phase 7 — migrate all transient feedback | FAIL | Asset/room/area Trash still lack Undo; dozens of old `showToast()` calls remain. |
| Phase 8 — ad runtime eligibility / generation | FAIL | No central `AdRuntimeEligibility` or generation/epoch implementation exists in production code. |
| Phase 9 — bounded retry / cache / ownership / fullscreen | FAIL | Retry remains effectively unbounded; no 55-minute cache wrapper/freshness enforcement; ownership architecture not implemented. |
| Phase 10 — native-ad theme parity / AdChoices | PARTIAL | AdChoices registration and basic background/text custom options were added; complete app-owned chrome/theme contract and no-request theme transition proof are missing. |
| Phase 11 — Google auth / Firebase cleanup | PARTIAL / MATERIAL PROGRESS | Direct Analytics removed; disconnect added; init retry logic still has a concurrency race and obsolete `google-services.json.example` remains. |
| Phase 12 — external Play account deletion | CRITICAL FAIL | Page is a simulation, not an authenticated deletion implementation. |
| Phase 13 — Play AAB / backend CI / evidence | PARTIAL | AAB script/workflow exists; backend CI, release evidence, signer/certificate proof, manifest/dependency artifacts missing. AAB workflow has not been run. |
| Phase 14 — docs / privacy / Data Safety | FAIL | Only changelog/privacy changed, and both contain claims contradicted by current code. Required docs/evidence/runbook missing. |
| Phase 15 — full validation / device / console / rollout | PARTIAL / UNVERIFIED | Flutter CI and production APK passed; no GitHub evidence for required device matrix/console checks; Play AAB workflow has zero runs. |

---

# Detailed findings

## 1. Splash and application root

### Implemented correctly

`HomePilotApp` now returns one stable `MaterialApp.router` with:

- the root `hkRootScaffoldMessengerKey`;
- one router configuration;
- one `HomePilotSplashOverlay` in the `builder`;
- startup/authenticated content changing below the overlay instead of replacing the Material application.

This substantially fixes the previous duplicate-splash ownership issue.

`HomePilotSplashOverlay` remains presentation-only and uses its fixed 3200 ms display plus 250 ms fade.

Decorative loop animation now stops when `MediaQuery.disableAnimationsOf(context)` is true.

### Still incorrect

The splash is **not** the first usable Flutter presentation.

`main()` still runs `_DeferredHomePilotBootstrap`. Before that bootstrap is ready, its `build()` returns:

```dart
return const ColoredBox(color: HkColors.appBackground);
```

Only later does it create `HomePilotBootstrap`.

`_HomeStartupGate` then has another startup-theme gate that returns:

```dart
return const ColoredBox(
  key: ValueKey('startup-theme-placeholder'),
  color: HkColors.appBackground,
);
```

before `HomePilotApp`—and therefore before `HomePilotSplashOverlay`—is created.

That means the exact sequence the master plan rejected is still structurally possible:

```text
Android native splash
→ plain Flutter background
→ startup/theme placeholder
→ animated Flutter splash
```

The current widget test explicitly preserves this behavior:

> `startup bootstrap stays blank until theme load completes`

and asserts that `homepilot-animated-splash` is absent while the placeholder is visible.

The master plan explicitly identified that test as defect characterization that had to be replaced with an early-splash target test.

Legacy timing contracts such as `minimumNativeSplashDuration` and `remainingNativeSplashDuration()` also remain.

### Required correction

Move stable splash ownership above both `_DeferredHomePilotBootstrap` readiness and startup-theme loading, or otherwise make those operations execute beneath an already-mounted splash-capable Material root. Replace the old blank-startup tests.

---

## 2. Permission, notification, reminder, and weather state

### Implemented correctly

- `preferExactReminders` now defaults to `false`.
- `EffectiveCapabilityState` enum was added.
- Exact alarm checks/requests use:
  - `canScheduleExactNotifications()`
  - `requestExactAlarmsPermission()`
- `SCHEDULE_EXACT_ALARM` remains in the manifest.
- The manifest still requests coarse location only; fine/background location were not added.

### Major requirements still missing

#### Manual weather still falsifies OS permission

`PermissionEducationController.chooseLocationManually()` still records:

```dart
PermissionEducationOutcome.configuredManually,
AppPermissionState.granted,
```

A manually selected city does not grant Android location permission. This was one of the master plan's explicit semantic defects.

#### No real capability snapshots

The repository has the enum `EffectiveCapabilityState`, but not the requested derived capability layer equivalent to:

- `WeatherAreaCapabilitySnapshot`
- `NotificationCapabilitySnapshot`
- `CapabilitySetupSnapshot`

The UI therefore still reasons primarily from raw OS permission state.

#### Duplicate platform permission implementations remain

Both:

- `AppPermissionCoordinator`
- `FlutterDevicePermissionGateway`

still independently call `permission_handler`, Geolocator, and `flutter_local_notifications`.

The master plan required a single canonical implementation with feature adapters delegating to it.

#### Settings action still targets current capability, not tapped capability

The controller still exposes:

```dart
openSettingsForCurrent()
```

and the setup screen uses it for every card. No target-specific:

```dart
openSettingsFor(PermissionCapability capability)
```

was implemented.

#### Exact-alarm settings remain generic

Feature-level `openSettings(PermissionCapability.exactReminderTiming)` still calls generic `openAppSettings()`.

#### Resume race remains

`handleAppResume()` still invokes `_advanceNextStep()` without awaiting it, then assigns refreshed state immediately afterward.

#### Setup status is still hardcoded and overly generic

The UI still renders literal English:

- `Allowed`
- `Blocked`
- `Not set`

and still uses a pre-action check icon.

#### Notification settings defect remains intact

Current flow still is:

```text
save any NotificationPreferences
→ persist preferences immediately
→ initialize scheduler
→ if local reminders enabled, request/check notification permission
→ if precise timing preference enabled, request/check exact-alarm access
```

`_saveNotificationPreferences()` still delegates every settings edit to `_enableNotifications()`.

Therefore changing quiet hours, inbox, weather alerts, digest time, privacy mode, etc. can still enter notification/exact-alarm permission orchestration whenever local reminders are enabled.

The master plan required prompts to be attached only to the action that needs the capability.

### Required correction

Implement the domain snapshots first, consolidate the permission gateway, fix manual-area semantics, split pure preference persistence from capability-enabling commands, and redesign Settings/Permission Setup/Weather Card from the derived state.

---

## 3. Unified transient feedback

### Implemented

- `HkFeedbackTone`
- `HkFeedbackMode`
- `HkFeedbackItem`
- singleton `FeedbackCoordinator`
- old helpers now route into the coordinator in some cases.

### Critical policy mismatches

#### An unrelated error can still destroy active Undo

When an Undo item is active, the coordinator queues only items that are neither error nor destructive.

An incoming error/destructive item falls through to `_showItem()`.

`_showItem()` then:
1. calls `_executePendingFinalize()` on the active item;
2. calls `messenger.hideCurrentSnackBar()`;
3. shows the new snackbar.

So an unrelated error can terminate an active Undo opportunity—the behavior the plan explicitly prohibited.

#### Batching does not update the visible UI or reset the visible deadline

`_batchUndoItem()` changes only `_activeItem` in memory:
- batch count;
- composed Undo callback;
- composed finalize callback.

It does not rebuild the current SnackBar, update its message/count, or restart its displayed/actual lifetime.

Therefore the claimed “rapid Trash batching with reset timer” is not implemented.

#### Batch compatibility is too broad

```dart
return active.batchItemType == incoming.batchItemType ||
    (active.batchItemType != null && incoming.batchItemType != null);
```

Any two typed Undo items are therefore considered compatible, even if they represent unrelated semantics.

#### Queue is not the planned policy

It is a simple FIFO list without:
- passive coalescing;
- dedupe key;
- latest-useful-message replacement;
- explicit warning/error slots;
- progress update semantics.

#### Semantic tone is not actually rendered

The coordinator creates a standard `SnackBar(content: item.message)`; `item.tone` is not mapped to visual icon/color/chrome.

#### Placement fields are not applied

`bottomOffset` and `reserveFloatingActionButton` exist in the model but are not consumed by the coordinator's SnackBar.

#### Legacy countdown implementation remains

`TaskDeletionSnackBarContent` and `_UndoCountdownBar` still exist as a separate timer-driven system.

### Migration is incomplete

The plan required **every Move to Trash** to have Undo.

Current code still has:

- task → dedicated Undo flow;
- asset → passive `showToast(nameMovedToTrash(...))`;
- room → passive `showToast(...)`;
- area → passive `showToast(...)`.

There are also dozens of generic `hk_ui.showToast()` call sites remaining, so semantic migration was not completed.

### Required correction

Fix coordinator policy first, then migrate Trash flows and remaining semantic call sites. Add dedicated coordinator tests, including error-behind-Undo, batch deadline reset, visible batch message, failure handling, and accessible navigation.

---

## 4. Monetization / AdMob runtime

This is the largest architectural implementation gap.

### Master-plan components absent from production

Repository search finds no production implementation of:
- `AdRuntimeEligibility`
- `AdRetryPolicy`
- `kAdCacheMaxAge`

The names appear only in the master plan/changelog.

### Current service still uses initialization as its core gate

`HomePilotAdsService` still has:

```dart
bool _initialized = false;
```

and load/show methods mostly gate on:
- `_initialized`;
- `_disposed`;
- loading state;
- existing ad;
- retry timer.

This does not implement the required runtime invariant:

```text
platform supported
AND app foreground
AND consent refreshed this session
AND canRequestAds
AND global ads enabled
AND format enabled
```

at every load/show boundary.

### No eligibility generation/epoch

There is no generation counter invalidating stale SDK callbacks when:
- consent changes;
- app backgrounds;
- global ads disable;
- format disables;
- service disposes.

### Retry remains effectively unbounded

Current helper:

```dart
const seconds = [2, 4, 8, 16, 32, 60];
```

caps the delay, not the number of retries.

`_scheduleInterstitialRetry()` increments failure count and schedules another `_loadInterstitial(retry: true)` after every failure indefinitely.

There is no requested error classification for:
- invalid request;
- no fill;
- network;
- internal;
- unknown.

There is no four-attempt epoch cap or dormant state.

### No 55-minute cache freshness

Ready ads have no central `loadedAt` wrapper and no `kAdCacheMaxAge = 55 minutes`.

Stale ads can therefore remain eligible under the old object-presence logic.

### No new monetization tests

`test/monetization_test.dart` was not part of PR #24's changed files even though the master plan required a comprehensive matrix.

### Required correction

Implement the runtime eligibility state machine, epoch/generation guard, bounded retry policy, centralized freshness wrapper, explicit ad ownership/disposal, and fullscreen serialization before treating monetization remediation as complete.

---

## 5. Native ads

### Implemented

Flutter native ads now pass custom options including:
- schema version;
- dark/light;
- placement;
- background color;
- text color.

Kotlin now:
- finds `AdChoicesView`;
- assigns `view.adChoicesView`;
- applies background/text colors.

### Incomplete

The master plan required the entire app-owned native-ad chrome to follow the HomePilot-selected app theme—not merely the root background plus headline/body text.

Current factory does not use most of the contract:
- `schemaVersion` ignored;
- `isDark` ignored;
- `placement` ignored;
- no version fallback diagnostic;
- advertiser color not themed;
- CTA chrome not themed;
- badge/label/border/drawables not comprehensively themed.

Theme transitions also lack the required proof that changing app theme does not increase ad request count.

Status: useful partial fix, not full Phase 10 compliance.

---

## 6. Google authentication and Firebase cleanup

### Strong progress

Direct Firebase Analytics packaging was removed from `android/app/build.gradle.kts`.

The Google Services conditional plugin application is gone.

`GoogleSignInGateway` now has `disconnect()`.

Account deletion now uses Google `disconnect()` during final local auth cleanup with `signOut()` fallback.

Normal sign out still uses `signOut()` rather than revoking authorization.

### Initialization race remains

The new retryable `_initialize()` is better than the original sticky failure, but its outer catch can clear a newer in-flight initialization.

Two callers awaiting the same failed initialization can both enter the catch. One can start a new initialization; the second then sets `_initialization = null` without identity checking and can start another initialization.

The master plan explicitly required at most one initialization attempt in flight and identity/version protection.

### Obsolete Firebase example remains

`android/app/google-services.json.example` still exists and still contains an enabled `analytics_service` example, despite direct Analytics having been removed.

The master plan said to delete that example if it existed only for unused Analytics.

### Missing CI guard

No current CI step specifically proves direct Firebase Analytics cannot be reintroduced.

---

## 7. External account deletion — release blocker

The new page is not functional.

### What the HTML tells the user

It states the user can:

> Authenticate with Google below to verify ownership and confirm deletion.

### What the JavaScript actually does

Authentication button:

```javascript
statusEl.textContent = 'Redirecting to Google Authentication...';

setTimeout(() => {
  statusEl.textContent =
    'Authenticated. Click below to permanently delete your account.';
  ...
}, 1000);
```

There is no redirect, OAuth flow, Supabase session, or identity verification.

Deletion button:

```javascript
statusEl.textContent = 'Processing deletion request...';

setTimeout(() => {
  statusEl.innerHTML =
    '<strong ...>Account successfully deleted. Your cloud data and media have been permanently removed.</strong>';
  ...
}, 1500);
```

There is no HTTP request and no call to `delete-account`.

### Why this is severe

The current UI tells a user their account and cloud data were permanently deleted even though no deletion occurred.

The current `PRIVACY.md` also claims the external flow:
- requires Google OAuth;
- invokes the protected Edge Function;
- removes private remote media/auth user;
- verifies the deletion result.

Those statements are false for the current web implementation.

### Additional missing requirements

- no pinned/bundled Supabase JS client;
- no public config injection;
- no authenticated session identity;
- no receipt validation;
- no browser signout;
- no deletion-site test harness;
- no build tooling;
- no restrictive page CSP;
- no visible Privacy/Support links;
- no link to account deletion from current VersionDeck navigation/footer.

### Required action

Do not use the current page as evidence of functional external account deletion and do not submit it to Play as complete. Replace the simulation with a real authenticated flow and automated tests.

---

## 8. Play AAB and release pipeline

### Implemented

A separate manual Play AAB workflow exists and:
- restricts production build to `main`;
- uses production environment secrets;
- creates signing material;
- calls a dedicated Play build script;
- uploads the generated AAB.

The build script:
- validates production config;
- runs clean/pub get/gen-l10n/build_runner/analyze/tests;
- runs production-config tests;
- builds `appbundle --flavor prod --release`;
- checks release registrants for integration-test leakage.

The existing production APK rail has remained functional and successfully built current `main`.

### Missing master-plan release evidence

No evidence step currently:
- verifies AAB signer/certificate digest;
- records upload certificate identity;
- distinguishes upload cert from Play App Signing cert;
- generates merged release manifest;
- generates/archives Gradle dependency report;
- asserts target SDK from merged artifact;
- asserts expected permissions/AdMob metadata;
- attests the AAB despite workflow granting attestation/OIDC permissions.

### Play workflow not yet exercised

GitHub reports zero runs for `build-play-android.yml` on `main`.

Therefore the new rail has not yet been demonstrated end-to-end in Actions.

---

## 9. Backend security CI

The master plan required release-gated:
- Deno AdMob SSV tests;
- Supabase database monetization tests;
- Google static/config contracts.

Current workflow directory contains only:
- `build-play-android.yml`
- `build-production-android.yml`
- `deploy-download-site.yml`
- `validate-flutter.yml`

No backend Google/SSV validation workflow exists.

Current `validate-flutter.yml` runs Flutter/Dart tests and production-config schema validation only.

This means strong existing SSV/RLS tests may still exist in the repository, but they were not made part of the required protected CI gate.

---

## 10. Documentation and claims

This area needs correction because documentation currently overstates shipped behavior.

### Changelog claims contradicted by code

The 1.4.9 entry says the program was completed and claims:

- startup theme flashes eliminated;
- capability state/permission separation completed;
- protected Undo implemented;
- 55-minute ad cache expiration implemented;
- epoch invalidation implemented;
- bounded exponential backoff with jitter implemented;
- signature verification added to AAB pipeline.

Those claims do not match the audited current code.

### Privacy claim contradicted by web implementation

`PRIVACY.md` describes a real authenticated external deletion flow, but the website only simulates it.

### Required documentation not added

No repository implementation was found for the requested:
- Google Play release runbook;
- Data Safety evidence document;
- updated permissions documentation;
- updated routes/permissions reference;
- monetization architecture updates;
- request audit corrections;
- testing/localization documentation updates;
- obsolete-plan supersession cleanup.

---

# CI and release evidence observed

## Passed

- PR-head `Validate Flutter` workflow: success.
- Existing production APK workflow on merged `main`: success.
- VersionDeck deployment associated with remediation PR-head: success.

These are meaningful positive signals.

## Not demonstrated

- Play AAB workflow: **0 runs**.
- Deno SSV CI gate: not present.
- Supabase database CI gate: not present.
- account-deletion browser E2E: not present.
- device matrix required by master plan: no GitHub evidence observed.
- TalkBack/accessibility device verification: no GitHub evidence observed.
- AdMob Console verification: no GitHub evidence observed.
- Google Cloud/OAuth certificate verification: no GitHub evidence observed.
- Play Console account-deletion/Data Safety verification: no GitHub evidence observed.

This audit does not claim those operator actions did not happen outside GitHub; only that no repository/GitHub evidence was observed.

---

# Release blockers

Before presenting Build 35 as master-plan compliant, fix at least:

1. **Replace the fake external account-deletion implementation.**
2. **Implement the monetization runtime eligibility/generation/retry/cache model.**
3. **Fix permission truth model and notification preference orchestration.**
4. **Mount the animated splash before all Flutter startup placeholders.**
5. **Guarantee protected Undo and implement Undo for asset/room/area Trash.**
6. **Add target tests that enforce the new contracts instead of old defect behavior.**
7. **Add backend SSV/database/Google CI gating.**
8. **Finish Play release evidence/signature checks and execute the AAB workflow.**
9. **Correct changelog/privacy claims immediately so documentation matches reality.**

---

# Recommended remediation order

## P0 — compliance/security truthfulness

1. Disable/remove simulated deletion success until real flow exists.
2. Correct `PRIVACY.md` and 1.4.9 changelog claims.
3. Build authenticated Supabase/Google external deletion + automated site tests.

## P0 — monetization request safety

4. Add central `AdRuntimeEligibility`.
5. Add app-lifecycle gate.
6. Add consent/config/format gates.
7. Add generation invalidation.
8. Add `AdRetryPolicy` with bounded attempts and error classes.
9. Add `CachedAd<T>` and 55-minute freshness.
10. Add ownership/fullscreen/reward race tests.

## P1 — permission correctness

11. Add real capability snapshots.
12. Make manual area configuration independent from OS location permission.
13. Consolidate permission platform access.
14. Add target-specific settings operations.
15. Make resume transition deterministic.
16. Split pure preference save from permission-requiring commands.
17. Redesign setup/weather/settings UI from effective capability state.
18. Add EN/AR/RTL/a11y tests.

## P1 — splash

19. Move splash ownership above deferred bootstrap/theme placeholders.
20. use canonical `#F9FCF8` bridge surface;
21. remove stale timing contracts;
22. replace blank-startup test with earliest-frame splash regression tests.

## P1 — feedback

23. Fix protected Undo policy.
24. Make compatible batching visibly update and reset deadline.
25. Add dedupe/coalescing/error queue policy.
26. Make semantic tone render visually.
27. Migrate asset/room/area Trash to real Undo.
28. Migrate remaining call sites.
29. Remove legacy feedback countdown/special-case infrastructure.
30. Add coordinator-specific tests.

## P1/P2 — release infrastructure

31. Add backend SSV/DB/Google validation workflow.
32. Add signer/certificate verification and release evidence.
33. Add merged manifest/dependency artifacts.
34. Add Play runbook/Data Safety evidence.
35. Run the Play AAB workflow and inspect its artifacts.

---

# Final assessment

The remediation PR made **real partial progress**, especially in:

- stable Material application topology;
- Google account revocation semantics;
- removal of direct Firebase Analytics;
- exact-alarm plugin integration;
- basic native-ad AdChoices/theme plumbing;
- separate Play AAB build scaffolding.

It did **not** implement the final master plan as claimed.

The most consequential unfinished domains are:
- external deletion;
- monetization runtime;
- permission truthfulness;
- splash first-frame continuity;
- protected/migrated feedback;
- backend/release evidence.

Accordingly, this audit rates the current implementation as **not ready for master-plan sign-off** and **not safe to describe as a completed remediation program** until the release blockers above are closed.

---

# Codex completion-status template

The implementing Codex agent should replace this template in its final report:

| Domain | Starting status | Ending status | Evidence |
|---|---|---|---|
| Documentation truthfulness | FAIL |  |  |
| External account deletion | CRITICAL FAIL |  |  |
| Monetization runtime | FAIL |  |  |
| Permission/capability model | FAIL |  |  |
| Notification settings orchestration | FAIL |  |  |
| First-frame splash continuity | FAIL |  |  |
| Feedback protected Undo/migration | FAIL |  |  |
| Native ad theme parity | PARTIAL |  |  |
| Google auth/config hygiene | PARTIAL |  |  |
| Backend security CI | FAIL |  |  |
| Play AAB evidence | PARTIAL |  |  |
| Documentation/Data Safety evidence | FAIL |  |  |
| Device/console/hosted verification | UNVERIFIED |  |  |

For every row marked complete, cite the code/tests/workflow/artifact that proves it. For every row not complete, state the exact blocker and whether it requires code, a secret, a physical device, or an operator console action.
