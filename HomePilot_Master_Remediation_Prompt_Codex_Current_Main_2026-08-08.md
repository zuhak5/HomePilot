# HomePilot — Master Remediation, Hardening, UX, Google Play, and Release Implementation Prompt

**Target executor:** OpenAI **Codex coding agent** — use the highest available reasoning effort in the execution environment  
**Repository:** `zuhak5/HomePilot`  
**Target branch:** `main` as the source baseline; implement on a dedicated working branch  
**Historical source-plan baseline:** `075cd6ff5c36bb9c05b03f10a20598310ecf000d`  
**Historical baseline application version:** `1.4.8+34`  
**Current `main` verified for this Codex adaptation:** `1f2084069bb8e278c8e8974e83193659f5cf4c32`  
**Current application version:** `1.4.9+35`  
**Original master-plan synthesis date:** 2026-08-08  
**Codex adaptation / main-branch recheck date:** 2026-08-08  
**Plan type:** implementation-ready, repository-grounded **current-main delta remediation** specification  
**Primary objective:** implement every **remaining** actionable requirement from the master remediation program against current `main`, preserve the partial remediation that is already correct, correct false implementation/documentation claims, and leave HomePilot in a release-verifiable state without weakening security, privacy, offline-first behavior, routing, localization, or release safety.

---

# 0. EXECUTOR MANDATE

You are the implementation agent. Do not merely summarize, recommend, or create another plan.

Your job is to:

1. re-audit the current repository at execution time;
2. create a dedicated implementation branch;
3. implement the complete remediation in small reviewable commits;
4. add or update automated tests with every behavioral change;
5. run the required validation after each major phase;
6. update documentation and changelog in the same change set as behavior;
7. leave the repository in a release-verifiable state;
8. report everything you changed, everything you validated, and anything requiring operator/device/console verification;
9. **never claim a manual, device, Play Console, AdMob Console, Google Cloud, GitHub Pages, or Supabase-hosted verification passed unless you actually observed evidence.**

This master prompt contains the normalized implementation order and conflict-resolution rules. The four original plans are included **verbatim** at the end so no requirement is lost.

## 0.1 Execution profile

Use the highest available reasoning/effort mode supported by the Codex execution environment. Do not rely on model-specific features from the original Gemini/Antigravity prompt.

Work deliberately:

- treat `AGENTS.md` and the nearest repository-scoped agent instructions as mandatory;
- use shell/repository inspection (`git`, `rg`, focused file reads) before changing code;
- operate as a delta implementation against the current branch, not as a replay of the historical baseline;
- do not overwrite or revert already-correct remediation merely to match an older appendix;
- do not push, deploy, publish, trigger protected production workflows, mutate hosted Supabase, or perform console actions unless the operator explicitly authorizes that exact action;
- when a required external secret/console value is unavailable, implement all code/tests/configuration that can be completed safely, fail closed, and report the exact remaining operator action;
- inspect before editing;
- search symbols instead of assuming line numbers;
- make the smallest complete architectural correction;
- preserve unrelated current work;
- avoid broad rewrites;
- prefer deterministic, injectable state machines;
- prefer fail-closed behavior for privacy, consent, release configuration, destructive account operations, and monetization eligibility;
- do not weaken security or tests to make a change easier.

## 0.2 Do not ask the operator to decide routine implementation details

Resolve ordinary implementation choices from:

1. repository governance and tests;
2. current implementation and security invariants;
3. current official platform/package documentation;
4. this normalized master prompt;
5. the original embedded plans.

Only stop a specific subtask when a real external requirement cannot safely be inferred, such as a production secret, Play App Signing value, OAuth certificate, AdMob console value, service-account permission, public domain, or an operator-only console action. Continue all independent work.

---

# 1. SOURCE-OF-TRUTH AND CONFLICT PRECEDENCE

Read `AGENTS.md` before editing and obey it throughout.

For this remediation, use the following precedence:

1. **Security/data invariants that are already enforced by tests, RLS, SQL, Edge Functions, signing checks, or release assertions.**
2. **Current official Google/Android/Flutter/package documentation for requirements that can change over time.**
3. **This normalized master prompt for intended target behavior and cross-plan ordering.**
4. **The four original source plans embedded below.**
5. **Current implementation and existing non-security tests.**
6. **Older documentation or historical plans.**

Important nuance: some current tests intentionally encode defects identified by these plans, for example:
- startup remaining blank before the animated splash owner exists;
- generic feedback replacing an active Undo snackbar;
- queued task-delete snackbars rather than deliberate batching.

Those tests are **characterization evidence, not target behavior**. Replace them with tests for the new contract. Do not use "tests are source of truth" as an excuse to preserve a defect explicitly identified by this plan.

Never weaken:
- RLS;
- service-role boundaries;
- AdMob SSV signature verification;
- transaction replay protection;
- reward amount/ad-unit/claim validation;
- wallet invariants;
- account-deletion identity checks;
- release signing checks;
- production config validation;
- test-vs-production ad-ID separation.

---

# 2. VERIFIED REPOSITORY SNAPSHOT USED TO BUILD THIS MASTER PLAN

The four original source plans were written against the historical baseline:

`075cd6ff5c36bb9c05b03f10a20598310ecf000d`

After remediation PR #24, current GitHub `main` was re-verified for this Codex adaptation at:

`1f2084069bb8e278c8e8974e83193659f5cf4c32` — `Release master remediation to main (#24)`

Therefore, the original appendices are **historical requirement sources**, not a literal description of current code. The current-main delta block below overrides any appendix statement such as "current code still..." when that statement conflicts with the repository at `1f2084069bb8e278c8e8974e83193659f5cf4c32`.

The implementation agent must still re-run:

```bash
git rev-parse HEAD
git status --short
git log -1 --oneline
```

If `main` has moved beyond `1f2084069bb8e278c8e8974e83193659f5cf4c32`, perform a scoped drift audit before editing, compare the new head with this Codex delta, and preserve newer unrelated or already-correct behavior. Do not force-reset to `1f2084069bb8e278c8e8974e83193659f5cf4c32`.


## 2.0A CURRENT-MAIN DELTA OVERRIDE — AUTHORITATIVE FOR CODEX EXECUTION

This subsection is the authoritative implementation-state overlay for current `main`. It is based on the uploaded compliance audit plus a fresh GitHub source recheck on 2026-08-08. The recheck found `main` still at `1f2084069bb8e278c8e8974e83193659f5cf4c32` and `pubspec.yaml` at `1.4.9+35`.

### What is already materially implemented — preserve it

- one stable `MaterialApp.router` once `HomePilotApp` is mounted;
- one root `hkRootScaffoldMessengerKey` within that stable app root;
- one production `HomePilotSplashOverlay` construction site under the app builder;
- reduced-motion suppression for decorative splash looping;
- `preferExactReminders = false` for new/default configuration;
- exact-alarm checks/requests through `flutter_local_notifications`;
- `SCHEDULE_EXACT_ALARM` retained without expanding to fine/background location;
- feedback model/coordinator skeleton;
- AdChoices registration and basic native-ad custom theme options;
- direct Firebase Analytics dependency and conditional Google Services plugin application removed;
- Google `disconnect()` added and used for deletion cleanup while normal sign-out still uses `signOut()`;
- dedicated Play AAB script/workflow scaffolding;
- existing production APK/VersionDeck rail remains intact.

Do not regress these while completing the missing contracts.

### Current release blockers and major gaps — still implement

| Domain | Current-main status | Codex action |
|---|---|---|
| Documentation truthfulness | **FAIL / immediate** | Remove or correct claims that 1.4.9 completed functionality that production code does not implement. |
| External account deletion | **CRITICAL FAIL** | Replace the `setTimeout()` simulation with real Google/Supabase authentication and protected backend deletion; never show success without a verified receipt. |
| Monetization runtime | **FAIL** | Add authoritative runtime eligibility, lifecycle gating, generation/epoch invalidation, bounded retry, 55-minute freshness, ownership and fullscreen serialization. |
| Permission/capability truth model | **FAIL** | Separate user preference, OS permission/special access, and effective capability; manual city selection must never fabricate an OS grant. |
| Notification settings orchestration | **FAIL** | Pure preference edits must not trigger notification/exact-alarm permission flows. |
| Splash first Flutter frame | **FAIL** | Mount splash-capable stable presentation before deferred bootstrap and startup-theme placeholders; remove blank-startup target behavior. |
| Feedback protected Undo | **FAIL / flawed partial** | Errors/destructive feedback must not terminate unrelated active Undo; implement visible compatible batching, deadline reset, coalescing, a11y lifetime, tone/placement, and all Trash Undo flows. |
| Native ad theme parity | **PARTIAL** | Finish app-owned chrome/theme contract and prove theme changes do not cause extra requests. |
| Google initialization gate | **PARTIAL** | Fix the concurrent failed-initialization race with identity/version protection; remove obsolete Analytics-only Google Services example if still unnecessary; add static guard. |
| Backend security CI | **FAIL** | Gate Deno SSV tests, Supabase DB monetization tests, and Google/static contracts. |
| Play release evidence | **PARTIAL** | Add signer/certificate, merged manifest, dependency, target API/permission/metadata and provenance evidence; do not auto-upload to Play. |
| Final device/console evidence | **UNVERIFIED** | Run only what the environment actually supports and report the rest as operator actions. |

### Fresh path-level confirmations at `1f2084069bb8e278c8e8974e83193659f5cf4c32`

Codex must re-open these before editing, but the current recheck observed:

1. `lib/main.dart`
   - `_DeferredHomePilotBootstrap.build()` still returns `ColoredBox(color: HkColors.appBackground)` until `_ready`;
   - `_HomeStartupGate.build()` still returns the keyed `startup-theme-placeholder`;
   - `minimumNativeSplashDuration` and `remainingNativeSplashDuration()` remain.
2. `lib/src/features/permissions/application/permission_education_controller.dart`
   - `chooseLocationManually()` still writes `AppPermissionState.granted`;
   - only `openSettingsForCurrent()` exists;
   - `handleAppResume()` still invokes `_advanceNextStep()` without awaiting it before another state write.
3. `lib/src/features/permissions/data/device_permission_gateway.dart`
   - duplicates direct Geolocator / `permission_handler` / local-notifications platform access;
   - exact-alarm settings still fall back to generic `openAppSettings()`.
4. `lib/src/ui/feedback/feedback_coordinator.dart`
   - unrelated error/destructive feedback falls through to `_showItem()`;
   - `_showItem()` finalizes the active item then calls `hideCurrentSnackBar()`;
   - compatible batching updates only in-memory state and does not rebuild/reset the visible SnackBar;
   - compatibility is overly broad for any two non-null `batchItemType` values.
5. `lib/src/features/monetization/monetization.dart`
   - ad loads still primarily gate on `_initialized`/object/loading/retry state;
   - retry delays cap at 60 seconds but retry count is not bounded;
   - ready ad objects have no central `loadedAt`/55-minute freshness wrapper;
   - native ad load/retry still originates from widget state/build-driven behavior.
6. `download-site/account-deletion.js`
   - Google "authentication" and deletion success are simulated with `setTimeout()`;
   - no OAuth redirect, Supabase session, Edge Function request, or deletion receipt validation occurs.
7. `lib/src/features/auth/data/native_google_sign_in.dart`
   - `disconnect()` is present;
   - the failed initialization retry path still permits multiple awaiters of a failed future to clear a newer attempt because the pre-existing-future catch lacks identity protection.
8. `android/app/google-services.json.example`
   - still exists and contains an `analytics_service` example.
9. `.github/workflows/`
   - currently contains `build-play-android.yml`, `build-production-android.yml`, `deploy-download-site.yml`, and `validate-flutter.yml`;
   - no dedicated backend SSV/DB/Google validation workflow is present.

### Phase status mapping for the original master program

Use this when reading the phases later in this document:

- Phase 0: **redo lightweight baseline evidence for the new working branch**.
- Phase 1: **still required**; target tests remain insufficient.
- Phase 2: **mostly implemented**; preserve stable root, modify only as needed to satisfy Phase 3 without duplicating ownership.
- Phase 3: **still required**.
- Phase 4: **still required** except exact-alarm/default pieces already landed.
- Phase 5: **still required**.
- Phase 6: **partial/flawed**; keep useful model scaffolding, replace policy implementation where necessary.
- Phase 7: **still required**.
- Phase 8: **still required**.
- Phase 9: **still required**.
- Phase 10: **partial**.
- Phase 11: **partial**.
- Phase 12: **critical fail; highest release priority**.
- Phase 13: **partial**.
- Phase 14: **fail; begin truthfulness corrections early, then finish after code**.
- Phase 15: **partially observed / mostly unverified**.

### Codex implementation priority

The original phase order remains useful architecturally, but against current `main` execute with this release-risk ordering:

1. baseline/drift check + documentation-impact assessment;
2. immediately remove/correct false deletion and 1.4.9 completion claims;
3. add target tests for the contracts being changed;
4. replace the fake external account-deletion flow;
5. implement monetization runtime safety;
6. implement permission/capability truthfulness and settings orchestration;
7. fix first-frame splash continuity while preserving the stable app root;
8. correct feedback coordinator policy and migrate all Trash/transient call sites;
9. finish native-ad and Google-auth hygiene;
10. finish backend CI / Play evidence;
11. synchronize all documentation;
12. run automated validation and report device/console/protected-environment work as verified only when evidence actually exists.

Where this ordering conflicts with an older appendix's implementation sequence, this current-main delta ordering wins.

---

## 2.1 Current stack facts verified against the repository

At the audited baseline:

- Flutter requirement: `>=3.44.7`
- Dart requirement: `^3.12.2`
- `flutter_riverpod`: `^3.4.2`
- `go_router`: `^17.3.0`
- `flutter_local_notifications`: `^22.1.0`
- `permission_handler`: `^12.0.3`
- `geolocator`: `^14.0.2`
- `google_sign_in`: `^7.2.0`
- resolved `google_sign_in_android`: `7.2.15`
- `google_mobile_ads`: `^9.0.0`
- `supabase_flutter`: `^2.16.0`
- `flutter_native_splash`: `^2.4.8`
- Android `compileSdk = 36`
- Android `targetSdk = 36`
- Java/Kotlin target: Java 17 / JVM 17

Do not perform a broad dependency-upgrade sweep as part of this remediation.

Run `flutter pub outdated` for awareness. Upgrade a package only if:
- the remediation requires an API/fix not present in the pinned version;
- the change is separately reviewed;
- changelog and migration impact are inspected;
- focused and full regression tests pass.

---

# 3. ONE-BY-ONE REVIEW OF THE FOUR SOURCE PLANS

**Codex current-main note:** this section was originally synthesized from the historical baseline. Its target requirements remain valid unless superseded elsewhere, but its statements about what the "current code" contains are overridden by Section 2.0A when they conflict with current `main`.

This section is the normalized review. The original plans remain authoritative detail appendices when they do not conflict with this master section or the current-main delta override.

---

## 3.1 Source Plan A — Google / AdMob / UMP / Google Play remediation

### Verdict

**Adopt. Implementation-ready and strongly aligned with current repository state.**

### Repository findings confirmed

The current code still exhibits the plan's central findings:

- UMP startup is present, but runtime ad loaders do not use one continuously authoritative eligibility model after initialization.
- retry behavior can continue indefinitely even though delay caps;
- ready ads do not carry one centralized freshness deadline;
- per-format remote flags are not a universal hard load/retry gate;
- ad request work is insufficiently tied to `AppLifecycleState.resumed`;
- async ad callbacks need a generation/epoch invalidation mechanism;
- native-ad ownership can race around dispose/replacement;
- Firebase Analytics is directly added in Android Gradle even though no intentional HomePilot Analytics product feature was found;
- the Google Services plugin is conditionally applied only when a local untracked `google-services.json` happens to exist;
- a sanitized `google-services.json.example` exists for that unused Analytics setup;
- real `google-services.json` paths are not explicitly ignored;
- Google account cleanup uses `signOut()` and does not expose a distinct revocation/disconnect operation;
- Google Sign-In initialization caches a failed Future for the gateway lifetime;
- production release tooling builds APK only;
- backend SSV/DB security tests are not fully represented in the primary Flutter CI gate;
- the native XML includes a custom `AdChoicesView` that the Kotlin factory does not explicitly register;
- native app-owned ad chrome uses static Android resources rather than an explicit HomePilot-selected light/dark palette contract;
- the release process lacks a dedicated Play AAB rail and evidence bundle.

### Correct behavior that must be preserved

- UMP `requestConsentInfoUpdate()` startup ordering.
- Google's demo ad units in non-production.
- conservative interstitial policy: first-session suppression, cooldown, rapid-completion suppression, keyboard/modal suppression, caps and kill switches.
- server-authoritative reward flow.
- claim-before-show behavior.
- SSV ECDSA verification.
- exact signed-query handling.
- key cache below 24 hours.
- transaction replay defense.
- ad-unit/reward/wallet validation.
- native platform-view teardown protections around overlays/navigation.
- no direct wallet mutation from `onUserEarnedReward`.

### 2026 refinement to apply

Do **not** migrate HomePilot to Google's deprecated native Android Google Sign-In SDK. The currently resolved `google_sign_in_android 7.2.15` already uses the Credential Manager-based implementation introduced by the modern Flutter plugin line and supports `disconnect()`.

Use the public `google_sign_in` Dart API:
- `GoogleSignIn.instance`;
- `initialize(...)`;
- `authenticate()`;
- `authorizationClient`;
- `disconnect()`;
- `signOut()`.

Keep authentication and authorization conceptually separate.

### Google initialization refinement

The current gateway uses:

```dart
_initialization ??= _googleSignIn.initialize(...)
```

Replace this with a safe initialization gate:

- at most one initialization attempt in flight;
- successful initialization is retained permanently for that gateway instance;
- if initialization fails, clear **only that failed attempt** so a later explicit sign-in action can retry;
- use identity/version protection so an older failed future cannot clear a newer attempt;
- do not repeatedly initialize after success.

### Google scopes

Do not invent or expand scopes.

Re-audit the exact Supabase + Google native flow before changing:
- ID-token requirement;
- whether current native flow still requires an access token in HomePilot's pinned Supabase API;
- the minimum scopes necessary to obtain that token.

If `email`/`profile` are required only because current flow needs authorization, keep them documented and minimal. If official current Supabase behavior proves the access token is unnecessary for this exact Flutter/native path, change only with tests and documentation.

### SSV reverse-DNS refinement

Current official SSV guidance recommends reverse DNS, but do not turn an untrusted forwarding header into a fake security boundary.

Implement reverse DNS only if the deployed Supabase Edge Runtime exposes an authenticated/trusted peer IP that the client cannot spoof. Otherwise:
- retain ECDSA as the cryptographic security boundary;
- document why reverse DNS is not safely implementable;
- never trust arbitrary `X-Forwarded-For`/`Forwarded`.

### Release refinement

Keep the existing production APK/VersionDeck rail. Add a separate protected Play AAB rail. Do not automatically upload to Play in the first implementation.

---

## 3.2 Source Plan B — Permission, notification, reminder, and weather remediation

### Verdict

**Adopt, with one platform-integration refinement for exact alarms.**

### Repository findings confirmed

Current code still has the defects described by the plan:

- notification preferences can be persisted before permission success;
- unrelated notification preference edits route through generic permission orchestration;
- `NotificationPreferences` defaults imply active capabilities before OS permission exists;
- `preferExactReminders` defaults to `true`;
- manual weather location is incorrectly recorded as `AppPermissionState.granted`;
- setup relevance is too OS-permission-centric;
- a setup card may open settings for `state.activeCapability` instead of the card tapped;
- status labels contain hardcoded English (`Allowed`, `Blocked`, `Not set`);
- pre-action buttons use completion checkmarks;
- exact-alarm contextual entry points are incomplete;
- weather-card recovery/configuration state is not modeled;
- `DevicePermissionGateway` and `AppPermissionCoordinator` duplicate platform permission logic;
- exact-alarm settings navigation is generic;
- lifecycle resume has competing async state writes;
- dismissal/cooldown state requires cleanup;
- coarse/two-decimal weather privacy behavior is good and must be preserved.

### Governing product principle

Never conflate:

```text
user preference
!=
OS permission / special access
!=
effective capability
```

Every UI and scheduler decision must be derived from that distinction.

### Exact-alarm refinement

Prefer the Android-specific APIs of the already-installed `flutter_local_notifications` implementation for exact-notification capability because that plugin is the component that actually schedules HomePilot notifications:

```dart
AndroidFlutterLocalNotificationsPlugin.canScheduleExactNotifications()
AndroidFlutterLocalNotificationsPlugin.requestExactAlarmsPermission()
```

Wrap those APIs behind HomePilot's canonical capability/permission abstraction.

Use `permission_handler` or a narrow native bridge only if the pinned package behavior is verified insufficient.

Keep:

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

Do **not** switch to `USE_EXACT_ALARM` without a separate product/policy review.

The Android model must still respect:
- `canScheduleExactAlarms()` semantics;
- user-driven Alarms & reminders special-access flow;
- re-check on lifecycle resume;
- inexact fallback;
- rescheduling/restoration after permission transitions where necessary.

### New-install exact timing decision

For a truly new/unconfigured user:

```text
preferExactReminders = false
```

Preserve explicit existing preferences.

Do not silently reinterpret an existing user's persisted `true` as `false`.

If the repository cannot distinguish "field absent because legacy/default" from "explicit user choice", introduce a deliberate migration/version marker rather than destructive guesswork.

### Device-reminder default decision

Do not opportunistically flip `localReminders` for all existing users in this remediation.

Make UI truthfulness independent of that legacy preference:
- intent may be ON;
- Android permission may be blocked;
- effective capability then renders blocked/degraded rather than falsely successful.

A future product decision can separately make device reminders fully opt-in for new users once migration semantics are explicit.

---

## 3.3 Source Plan C — Splash full fix and improvement

### Verdict

**Adopt. This should be implemented early because its root topology affects every other plan.**

### Repository findings confirmed

Current `main` still has:
- more than one production `HomePilotSplashOverlay` construction site;
- different root branches involving `MaterialApp` and `MaterialApp.router`;
- deferred/bootstrap/theme placeholders that can render before the animated splash;
- `HkColors.appBackground` (`#F7F9FC`) as a possible pre-splash Flutter surface while the canonical splash background is `#F9FCF8`;
- legacy timing symbols such as `minimumNativeSplashDuration`;
- tests that currently expect a blank startup-theme placeholder before the animated splash.

The visual splash widget itself is already mostly presentation-only and should remain narrow.

### Cross-plan requirement

The splash/root refactor must preserve exactly one:
- top-level provider/container ownership path;
- app/root inherited-widget boundary;
- root `ScaffoldMessenger` key;
- router/navigation observer topology;
- Sentry observer topology;
- monetization bootstrap owner;
- permission education owner.

Do not "fix" duplicate splash ownership by creating duplicate providers, nested `MaterialApp`s, or a second messenger.

### Preferred root topology

Preferred:

```text
runApp
└── stable process root
    └── stable provider/inherited boundary
        └── one stable Material app boundary
            └── builder
                └── one process-scoped HomePilotSplashOverlay
                    └── current application content
                        ├── startup/auth/hydration
                        └── authenticated routing
```

Use one `MaterialApp.router` if GoRouter can exist safely before auth resolves.

Otherwise use one stable `MaterialApp` and embed router content without a nested second Material app.

Only use an overlay above the Material app if you explicitly make the splash self-contained with all required inherited context and prove it with tests.

### Reduced motion

Decorative loop motion must respect reduced-motion settings.

Do not shorten the deterministic process splash lifetime unless HomePilot's established reduced-motion policy specifically requires it.

### Timer/lifecycle

The timer starts once.

Never restart on:
- rebuild;
- auth;
- theme;
- locale;
- route;
- lifecycle resume;
- provider changes.

If the app backgrounds while the splash is active, ensure resume cannot create a fresh presentation lifetime. If implementation uses a deadline/elapsed-time model, use one monotonic/deadline origin and remove the overlay when the original presentation contract has elapsed.

---

## 3.4 Source Plan D — Unified transient feedback system

### Verdict

**Adopt. Build the coordinator before migrating all call sites.**

### Repository findings confirmed

Current code still:
- centralizes the root messenger key but not feedback policy;
- has only `normal/error` severity;
- calls `hideCurrentSnackBar()` for generic feedback;
- therefore can destroy an active Undo opportunity;
- has separate task-trash and generic paths;
- gives task Trash an Undo while area/room/asset Trash flows do not consistently use the same model;
- relies on default `ScaffoldMessenger` queue behavior for some action feedback;
- has tests that codify replacement and queue behavior that must change.

### Architecture decision

Keep Flutter-native `SnackBar` / `ScaffoldMessenger` transport.

Do not add:
- Android `Toast.makeText`;
- `fluttertoast`;
- a third-party overlay/toast dependency.

Create a dedicated feedback domain/coordinator module.

Separate:
- semantic tone: neutral/info/success/warning/error/destructive;
- interaction mode: passive/actionable/undoable/progress.

### Protected Undo invariant

While Undo is active:
- passive/info/success cannot remove it;
- warning cannot remove it;
- unrelated errors wait behind it;
- compatible Undo events may batch;
- incompatible Undo events must use a deliberate policy, never visual stacking;
- an Undo-operation failure may resolve the action state and surface the failure immediately.

### Accessibility refinement

Flutter itself keeps a SnackBar with an action from timing out when screen-reader accessible navigation is active.

Do not create a HomePilot custom countdown that visually reaches zero while the framework action remains valid.

The coordinator's logical deadline and visual countdown must follow the same accessibility-aware lifetime policy.

When `accessibleNavigation == true`, prefer:
- non-auto-expiring or substantially extended actionable feedback;
- explicit dismiss;
- no misleading numeric countdown;
- business finalization only when the actionable state actually closes/expires according to the chosen policy.

### Placement refinement

First use the framework's `SnackBarBehavior.floating` geometry; Flutter already moves floating snackbars above a FAB/footer/bottom navigation.

Add HomePilot-specific placement deltas only where:
- task detail bottom action bars;
- custom persistent surfaces;
- root-scaffold topology

require extra clearance.

Do not manually move the FAB or bottom navigation.

---

# 4. CURRENT OFFICIAL GUIDANCE TO RE-CHECK BEFORE MERGE

The following were re-verified while synthesizing this master prompt. Re-open them immediately before final merge because platform guidance can change.

## UMP / consent

- https://developers.google.com/admob/flutter/privacy

Current rule:
- request consent info update every app launch;
- show required forms;
- check `canRequestAds()` before requesting ads;
- avoid duplicate request work when multiple consent checks return true.

## Native ad freshness / ownership

- https://developers.google.com/admob/android/native

Current rule:
- native ads expire after one hour;
- clear/reload cache before that boundary;
- do not start overlapping loads;
- destroy ads no longer used.

HomePilot target:
- one centralized `kAdCacheMaxAge = 55 minutes` safety threshold.

## AdMob SSV

- https://developers.google.com/admob/android/ssv

Current guidance:
- cryptographic signature verification;
- key cache no longer than 24 hours;
- HTTP 200 on accepted callbacks;
- Google may retry failed delivery;
- reverse-DNS verification is recommended.

Apply the trusted-peer-IP feasibility rule from this master prompt.

## Google Sign-In Flutter

- https://pub.dev/documentation/google_sign_in/latest/
- https://pub.dev/documentation/google_sign_in/latest/google_sign_in/GoogleSignIn-class.html
- https://pub.dev/packages/google_sign_in_android/changelog

Current package behavior:
- top-level `google_sign_in` uses a singleton initialized with configuration;
- authentication and authorization are separate concepts;
- `disconnect()` revokes prior authorization;
- the current Android implementation line uses Credential Manager rather than the deprecated native Google Sign-In Android SDK.

## Exact alarms

- https://developer.android.com/develop/background-work/services/alarms
- https://developer.android.com/reference/android/app/AlarmManager
- https://pub.dev/documentation/flutter_local_notifications/latest/flutter_local_notifications/AndroidFlutterLocalNotificationsPlugin-class.html

Use exact alarms only when precise timing is user-meaningful.
Check capability before exact scheduling.
Request special access contextually.
Keep inexact fallback.

## Google Play account deletion

- https://support.google.com/googleplay/android-developer/answer/10144311
- https://support.google.com/googleplay/android-developer/answer/13327111

Apps with account creation need:
- an in-app deletion path;
- an external web resource that works without reinstalling/opening the app;
- deletion of associated account data except clearly disclosed legitimate retention.

## Google Play target API

- https://support.google.com/googleplay/android-developer/answer/11926878

Starting 2026-08-31, new apps and updates must target API 36 or higher.

HomePilot already targets API 36. Preserve it and add a release assertion against regression.

## Flutter SnackBar accessibility

- https://api.flutter.dev/flutter/material/SnackBar-class.html
- https://api.flutter.dev/flutter/material/ScaffoldMessengerState/showSnackBar.html

Floating snackbars participate in scaffold geometry.
Action snackbars have accessibility-specific timeout behavior.
HomePilot's custom coordinator must not conflict with that behavior.

---

# 5. MASTER CROSS-CUTTING INVARIANTS

These apply to every phase.

## 5.1 One stable application ownership topology

After the splash/root remediation, startup must not create duplicate:
- `ProviderScope` / Riverpod containers;
- Material app roots;
- root messenger keys;
- GoRouter instances merely due auth transition;
- Sentry navigation observers;
- monetization owners/listeners;
- permission education owners.

## 5.2 Startup is concurrent, not serial

Correct:

```text
mount stable app + splash immediately
+
start safe deferred initialization underneath
```

Incorrect:

```text
finish initialization
then
mount splash
```

Do not make network/database/auth bootstrap block the first Flutter splash frame.

## 5.3 No permission UI from startup side effects

The app may calculate capability state underneath the splash.

It must not open Android permission/special-access UI unless:
- the splash has finished;
- the user explicitly invoked the feature action requiring it;
- the action is contextually appropriate.

## 5.4 Preference, permission, and capability stay separate

No UI widget may reconstruct product truth from one boolean.

Use derived domain state.

## 5.5 Feedback never destroys an Undo opportunity

All app-wide transient feedback goes through one coordinator once migration completes.

## 5.6 Monetization eligibility is checked at request/show time

`MobileAds.initialize()` completion is not permission to load forever.

Every request and show operation must consult the current runtime eligibility snapshot.

## 5.7 Consent, lifecycle, remote config, and generation changes invalidate stale ad work

Use an epoch/generation token.

Async callbacks from older eligibility epochs cannot populate current caches.

## 5.8 Rewards remain server-authoritative

Never credit from `onUserEarnedReward`.

## 5.9 No privacy expansion

Do not add:
- fine location;
- background location;
- unreviewed analytics;
- ad-ID logging;
- coordinate logging;
- OAuth token logging;
- SSV raw user/custom data logging;
- third-party tracking to the deletion page.

## 5.10 Existing APK distribution remains intact

The Play AAB rail is additive.

Do not turn VersionDeck/GitHub APK distribution into an AAB-only path.

## 5.11 `download-site/**` scope rule

The feedback plan's "do not modify VersionDeck" rule remains valid for feedback work.

The only authorized `download-site/**` change in this master remediation is the dedicated Google Play account-deletion phase and the minimal navigation/build/deployment changes required to expose that page.

Do not redesign VersionDeck as collateral work.

## 5.12 Localization and accessibility

Every new user-visible application string must be in English and Arabic ARB sources.

Regenerate localization output.

Validate:
- RTL;
- 200% text where applicable;
- screen-reader semantics;
- reduced motion;
- keyboard/switch access;
- 48dp actionable targets where practical;
- narrow phone layouts.

---

# 6. TARGET ARCHITECTURE

---

## 6.1 Stable launch/application root

Conceptual target:

```text
StableHomePilotProcessRoot
├── ProviderScope / stable app dependencies
└── one Material application boundary
    ├── root scaffoldMessengerKey = hkRootScaffoldMessengerKey
    ├── router / navigation ownership
    ├── Sentry/navigation observer ownership
    └── builder
        └── HomePilotSplashOverlay  // exactly one production owner
            └── ApplicationStateHost
                ├── startup/auth/hydration content
                └── authenticated routed content
```

Do not use nested Material apps as a shortcut.

---

## 6.2 Capability-state architecture

Target concepts:

```dart
enum EffectiveCapabilityState {
  active,
  degraded,
  blocked,
  disabledByUser,
  notConfigured,
  unavailable,
}
```

Weather snapshot must include:
- selected area;
- source manual/device;
- OS location permission;
- location service enabled;
- effective state;
- next action.

Notification snapshot must include:
- stored user preferences;
- OS notification permission;
- effective device-reminder capability;
- exact-alarm capability;
- effective exact/inexact timing mode;
- in-app inbox capability;
- weather-alert/inbox capability.

UI consumes these derived snapshots.

---

## 6.3 Feedback architecture

Suggested module:

```text
lib/src/ui/feedback/
  feedback_model.dart
  feedback_coordinator.dart
  feedback_bar.dart
  feedback_placement.dart
```

Coordinator owns:
- active feedback;
- active Undo batch;
- compatible batching;
- latest pending passive/warning/error;
- dedupe;
- progress updates;
- lifetime/deadline;
- accessibility-aware timeout policy;
- dismiss reason;
- exactly-once action callbacks;
- root messenger interaction.

Business operations remain outside the widget.

---

## 6.4 Monetization runtime architecture

Suggested conceptual split:

```text
lib/src/features/monetization/
  ad_runtime.dart
  ad_runtime_controller.dart
  ad_retry_policy.dart
  ad_cache.dart
  home_pilot_ads_service.dart
  consent_service.dart
  native_ad_card.dart
  monetization.dart
```

Do not perform an uncontrolled file split. Move behavior incrementally.

Core concepts:

```dart
enum AdFormat {
  native,
  interstitial,
  rewarded,
  rewardedInterstitial,
}

class AdRuntimeEligibility {
  final bool platformSupported;
  final bool appForeground;
  final bool consentUpdatedThisSession;
  final bool canRequestAds;
  final bool adsEnabled;
  final bool nativeEnabled;
  final bool interstitialEnabled;
  final bool rewardedEnabled;
  final bool rewardedInterstitialEnabled;
}
```

A load is allowed only when all applicable gates are true.

Every eligibility-changing transition increments a generation.

---

## 6.5 Google auth deletion architecture

Normal logout:
- Supabase sign out;
- Google `signOut()`;
- no forced authorization revocation.

Account deletion:
- explicit recent Google reauthentication;
- validate same user;
- protected server deletion;
- local account cleanup;
- Google `disconnect()` as best-effort revocation after remote deletion is confirmed;
- fall back to `signOut()` if revocation cleanup fails;
- do not resurrect or roll back a successfully deleted HomePilot cloud account because Google cleanup had a secondary failure;
- surface privacy-safe recoverable status if needed.

---

## 6.6 Release architecture

Preserve:

```text
tool/build_prod.ps1
.github/workflows/build-production-android.yml
```

Add:

```text
tool/build_play_prod.ps1
.github/workflows/build-play-android.yml
docs/operations/google-play-release-runbook.md
```

No automated Play upload in the first implementation.

---

# 7. ORDERED IMPLEMENTATION PROGRAM

The ordering below is intentional. Do not implement all `lib/main.dart` changes in one giant commit.

---

# PHASE 0 — BASELINE FREEZE, BRANCH, INVENTORY, AND SAFETY BASELINE

## Objective

Establish exact evidence before changing behavior.

## Required actions

1. Read:
   - `AGENTS.md`
   - `docs/governance/documentation-maintenance.md`
   - `docs/README.md`
   - relevant architecture/security/release docs named in the source appendices.
2. Record:
   - branch;
   - HEAD;
   - clean/dirty status;
   - Flutter/Dart/Java/Node/Deno/Supabase CLI versions available.
3. Create or use a dedicated Codex working branch from current `main` (for example `codex/master-remediation-delta`), unless the operator has already supplied a working branch. Never force-reset or discard unrelated work.
4. Run broad symbol searches listed in all four source plans.
5. Inventory all current:
   - splash construction sites;
   - Material app roots;
   - root messenger keys;
   - `ScaffoldMessenger` / `SnackBar` / toast helpers;
   - permission request/settings APIs;
   - exact-alarm paths;
   - weather configuration paths;
   - ad load/retry/show entry points;
   - timers;
   - native-ad ownership/dispose sites;
   - Google sign-in/revocation methods;
   - Firebase/Google Services build references;
   - release scripts/workflows;
   - account-deletion web/deployment paths.
6. Run current focused and broad tests.
7. Record failures that exist before changes.

## Do not edit until

You have verified which source-plan assumptions still match current `main` and reconciled them with the Section 2.0A delta. If HEAD differs from `1f2084069bb8e278c8e8974e83193659f5cf4c32`, record the drift before editing.

---

# PHASE 1 — CHARACTERIZATION TESTS FOR THE CURRENT DEFECTS

## Objective

Create failing target tests or explicit characterization tests before major refactors.

## Splash tests

Add/update tests proving:
- root auth/startup transition must not construct a second splash owner;
- first usable Flutter frame contains the splash even while startup-theme/bootstrap work is delayed;
- splash does not reappear on sign-in/sign-out;
- timer does not restart on theme/locale/provider/lifecycle changes.

Replace the current test contract that intentionally expects a blank pre-splash placeholder.

## Permission tests

Add state-matrix tests proving:
- manual location satisfies weather configuration without granting Android location;
- blocked notifications can coexist with enabled in-app preferences;
- exact preference ON + no exact access => inexact/degraded, not broken;
- unrelated preference edit never requests notifications/exact alarms;
- card-specific settings action opens the correct capability;
- resume recomputation is deterministic.

## Feedback tests

Create coordinator-level target tests for:
- protected active Undo;
- compatible Trash batching;
- exactly-once undo callbacks;
- passive coalescing;
- error-after-Undo policy;
- accessibility timeout mode.

Replace queue/replacement tests that encode the old behavior.

## Monetization tests

Add tests that will drive:
- current-session consent refresh requirement;
- load/show eligibility;
- app foreground gate;
- per-format kill switches;
- generation invalidation;
- bounded retries;
- stale cache rejection;
- single ownership/disposal.

## Acceptance

The test suite clearly captures the target behavior before the large implementation commits.

---

# PHASE 2 — STABLE APPLICATION ROOT AND SINGLE PROCESS SPLASH OWNER

**Current-main delta:** most of this phase is already landed. Preserve the stable `MaterialApp.router`, router, messenger, and single splash construction site. Change topology only to the minimum degree required to satisfy the earlier first-frame splash contract in Phase 3; do not recreate already-solved duplicate-root behavior.

## Objective

Fix the highest-impact cross-plan topology first.

## Primary files

- `lib/main.dart`
- `lib/homepilot_animated_splash_screen.dart`
- router/startup/provider files discovered during audit
- splash/startup tests

## Required implementation

1. Refactor to one stable Material application boundary across startup/auth states.
2. Keep one stable `hkRootScaffoldMessengerKey`.
3. Keep one stable provider/container ownership path.
4. Keep router, Sentry observer, permission education, and monetization listeners from being duplicated by auth transitions.
5. Install exactly one production `HomePilotSplashOverlay`.
6. Put startup/auth/hydration/routed content under that stable owner.
7. Do not create nested `MaterialApp`/`MaterialApp.router`.
8. Do not use a global `hasShownSplash` flag as the primary correctness mechanism.
9. Add an explanatory code comment at the owner:
   `Splash is process-scoped presentation. Do not duplicate inside auth/startup/router branches.`

## Strategy preference

1. One stable `MaterialApp.router` if safe before auth.
2. Otherwise one stable `MaterialApp` with embedded router content.
3. Context-self-sufficient root splash host only if 1/2 are disproportionately unsafe.

Document why fallback 3 is used if selected.

## Acceptance

- exactly one production splash construction site;
- one app root survives startup -> authenticated;
- root messenger survives;
- provider state survives;
- no duplicated monetization initialization;
- no duplicated permission education controller/listener;
- deep links/navigation semantics unchanged.

---

# PHASE 3 — EARLIEST FLUTTER SPLASH, VISUAL CONTINUITY, REDUCED MOTION

## Objective

Guarantee native splash -> animated Flutter splash without a blank app-colored gap.

## Required implementation

1. Mount the splash owner before deferred startup-theme/network/database work.
2. Deferred work runs underneath.
3. Canonical splash background:
   ```dart
   const homePilotSplashBackground = Color(0xFFF9FCF8);
   ```
4. Keep Android native splash resources at `#F9FCF8`.
5. Any Flutter bridge surface exposed before/behind the overlay uses the splash color, not general `HkColors.appBackground`.
6. Remove/retire obsolete splash timing architecture once no longer needed.
7. Keep ~3200ms visible + ~250ms fade unless product requirement explicitly changes.
8. Timer starts once and final removal runs once.
9. Respect `MediaQuery.disableAnimations` for decorative loop/float/rotation effects.
10. Preserve input blocking.
11. Exclude fake progress/countdown from noisy semantics.
12. Verify focus becomes available immediately after overlay removal.

## Android resources

If generator config changes, run the installed `flutter_native_splash` tooling. Do not manually recreate generated bitmap matrices.

## Tests

- first-frame delayed-theme;
- delayed bootstrap;
- auth resolves before splash finishes;
- auth resolves after splash finishes;
- sign out/in same process;
- background/resume;
- theme/locale changes;
- reduced motion;
- small screen;
- large text;
- interaction blocking;
- native resource static checks.

## Acceptance

No:
- blank Flutter frame;
- duplicate branded sequence;
- splash restart;
- background-color flash;
- provider/root recreation.

---

# PHASE 4 — CAPABILITY DOMAIN MODEL AND CANONICAL PLATFORM PERMISSION LAYER

## Objective

Make product state truthful before changing most permission UI.

## Primary files

- `lib/src/core/domain/models.dart`
- `lib/src/core/services/app_permission_coordinator.dart`
- `lib/src/features/permissions/domain/**`
- `lib/src/features/permissions/data/device_permission_gateway.dart`
- `lib/src/features/permissions/application/permission_education_controller.dart`
- notification scheduler/service abstractions
- focused tests

## Required implementation

1. Add pure derived capability state types.
2. Load both:
   - OS state;
   - current HomePilot configuration/preferences.
3. Manual weather configuration:
   - persists `HomeLocation(source: 'manual')`;
   - satisfies weather-area capability;
   - **does not** mutate OS location permission to granted.
4. Device-derived weather:
   - retain existing selected area if OS permission is later lost;
   - represent refresh capability as degraded;
   - weather can continue from saved area.
5. Introduce:
   ```dart
   Future<void> openSettingsFor(PermissionCapability capability)
   ```
   or equivalent target-specific operation.
6. Make one canonical platform permission implementation.
7. Feature-layer gateway delegates rather than reimplementing policy.
8. Refactor resume into one awaited sequence:
   - recheck;
   - derive;
   - advance if appropriate;
   - publish once.
9. Implement or remove unused dismissal/session state deliberately.

## Exact alarm implementation

Use the notification plugin's Android capability methods where available in the pinned version:

- `canScheduleExactNotifications()`
- `requestExactAlarmsPermission()`

Map these into the canonical HomePilot capability model.

Fallback only if necessary:
- `permission_handler`;
- narrow native intent for `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`.

No broad native permission framework.

## New-install preference migration

Implement a safe way for new/unconfigured users to receive:

```text
preferExactReminders = false
```

Preserve existing stored choices.

## Tests

Truth-table tests for:
- manual area;
- device area;
- service off;
- denied/permanent/restricted/unavailable;
- notification preference/permission combinations;
- exact access combinations;
- target settings actions;
- migration behavior.

---

# PHASE 5 — SETTINGS, PERMISSION SETUP, WEATHER CARD, AND SCHEDULING UX

## Objective

Render the domain truth consistently.

## Settings

Separate:
- app preferences;
- Android capability status;
- effective delivery state.

Do not show a plain "success" switch as the only UI when Android blocks delivery.

When enabling device reminders from OFF:
1. user acts;
2. request required notification permission;
3. persist success state only after success, unless intent is explicitly modeled separately;
4. refresh schedules.

Changing inbox, quiet hours, privacy mode, digest, etc. must not trigger unrelated permission prompts.

## Exact timing

Show:
- active exact timing when granted;
- approximate fallback when missing;
- unavailable/not-required where appropriate.

Never disable all reminders merely because exact timing is unavailable.

## Permission setup screen

Implement:
- concise localized title/subtitle;
- localized typed statuses;
- distinct `denied`, `blocked`, `service off`, `restricted`, `configured manually`, `degraded`, `unavailable`;
- action-semantic icons, not pre-success checkmarks;
- card-specific settings actions;
- manual weather configured state;
- contextual exact timing education.

## Weather card

Pass in a derived weather capability snapshot.

States:
- no area: setup/manual affordance;
- manual: no GPS warning;
- device + granted: current-location state;
- device + revoked: saved weather continues + recovery affordance;
- services off: degraded + recovery;
- theme toggle remains a distinct action.

## Privacy

Preserve:
- coarse location only;
- two-decimal coordinate reduction;
- no coordinate logs;
- no background location.

## Scheduling

After relevant preference/permission transitions:
- reconcile pending schedules;
- preserve boot/app-update restoration;
- exact if truly available and requested;
- otherwise inexact fallback.

## Localization/a11y tests

EN + AR, RTL, narrow widths, 200% text.

---

# PHASE 6 — BUILD THE UNIFIED FEEDBACK FOUNDATION

## Objective

Create one app-wide policy without yet migrating every call site.

## Primary files

- `lib/src/core/services/feedback_messenger.dart`
- `lib/src/ui/app_theme.dart`
- new `lib/src/ui/feedback/**`
- `lib/src/ui/components.dart` transitional adapters
- dedicated coordinator/widget tests

## Model

Create types equivalent to:

```dart
enum HkFeedbackTone {
  neutral,
  info,
  success,
  warning,
  error,
  destructive,
}

enum HkFeedbackMode {
  passive,
  actionable,
  undoable,
  progress,
}
```

A request should carry:
- stable ID;
- tone;
- mode;
- localized message/supporting content;
- icon semantics;
- action metadata;
- aggregation key;
- dedupe key;
- optional duration/progress;
- explicit Undo metadata.

## Coordinator policy

Only one feedback bar is visible.

Priority:
1. blocking dialogs/screens — outside coordinator;
2. protected actionable/Undo;
3. error;
4. warning;
5. success/info;
6. noise.

Implement:
- compatible batch merge;
- pending latest passive;
- pending warning/error;
- dedupe;
- exactly-once callback execution;
- lifecycle safety;
- progress update;
- dismiss reason;
- root messenger state recovery after routes.

## Accessibility lifetime

When actionable feedback is in accessible-navigation mode:
- do not run a hidden five-second destructive finalization behind a persistent UI;
- choose a documented non-auto-expiring or substantially extended policy;
- no misleading countdown;
- explicit dismiss path;
- finalization and UI lifetime must agree.

## Visual component

Use a Flutter-native floating SnackBar with:
- HomePilot surface/radii/shadow;
- semantic icon container;
- primary and optional supporting copy;
- trailing action;
- optional progress;
- optional non-semantic visual timer;
- theme-aware semantic colors;
- RTL-safe directional spacing.

Reuse/extend theme tokens rather than hardcoded isolated colors.

## Acceptance

The foundation can be tested independently of business repositories.

---

# PHASE 7 — MIGRATE EVERY TRANSIENT FEEDBACK CALL SITE

## Objective

No ad-hoc production SnackBars remain outside the unified feedback layer.

## Mandatory Trash Undo

Unify:
- task -> Trash;
- asset/item -> Trash;
- room -> Trash;
- area -> Trash.

Single operation:
- 5-second default normal-mode Undo window;
- one Undo callback;
- exactly once.

Rapid compatible Trash:
- one visible batch;
- timer/deadline reset in normal mode;
- type-aware count;
- mixed-type generic count;
- reverse/LIFO undo order unless repository constraints require another explicit safe order.

If one batch Undo fails:
- do not claim total success;
- do not rerun already completed callbacks;
- surface one clear failure;
- retain privacy-safe diagnostics.

## Task completion

Remain undoable.

Batch only if the underlying completion domain exposes reliable multi-operation inverse tokens. Do not fake batching.

## Permanent delete

Keep explicit confirmation.

Post-success:
- destructive, non-undoable result feedback.

Never show Undo for irreversible operations.

## Migrate remaining categories

- creation/save/update success;
- warnings;
- errors;
- permission results;
- weather location results;
- backup/restore/export;
- snooze/skip/postpone;
- reminder scheduling;
- account/auth;
- nickname;
- reward/ad state;
- offline draft;
- photo operations;
- Trash restore;
- progress/pending where appropriate.

## Haptic/audio

Keep `action_feedback_service.dart`.

Do not trigger duplicate haptic/audio when multiple operations are batched.

## Remove/deprecate old API

After migration:
- no direct ad-hoc `SnackBar(` in production outside the unified implementation unless documented exceptional UI;
- no generic helper that can call `hideCurrentSnackBar()` over protected Undo;
- old task-specific feedback implementation removed or converted to compatibility wrapper then removed.

## Tests

Search-based regression assertions plus route/placement/a11y/widget tests.

---

# PHASE 8 — AD RUNTIME: CONSENT, LIFECYCLE, REMOTE CONFIG, GENERATION

## Objective

Turn ad eligibility into one deterministic runtime state machine.

## Primary files

- `lib/src/features/monetization/monetization.dart`
- new split files only as useful
- startup/lifecycle integration
- monetization tests

## Consent service

Separate:
- consent-info refresh state;
- `canRequestAds`;
- privacy-options requirement;
- Mobile Ads SDK initialized state.

`MobileAds.initialize()` is an implementation prerequisite, not eligibility.

## Runtime eligibility

A new ad load is permitted only when:

```text
platform supported
AND
app lifecycle == resumed
AND
consent info was refreshed for this app session
AND
canRequestAds == true
AND
global ads flag == true
AND
specific format flag == true
AND
service not disposed
```

A show additionally requires:
- fresh cached ad;
- format-specific business eligibility;
- no conflicting fullscreen presentation.

## Generation/epoch

Increment generation when:
- consent changes;
- foreground/background changes;
- global ads enabled/disabled;
- format enabled/disabled;
- service disposed;
- any other transition that invalidates current request results.

Every async load captures generation.

Callback rule:

```text
if capturedGeneration != currentGeneration:
    dispose returned ad exactly once
    do not cache
    do not retry
    complete pending operation safely
```

## Widget/build discipline

Do not start ad requests as side effects of arbitrary `build()` calls.

Use explicit lifecycle/controller transitions.

## Tests

Consent/lifecycle/config matrices and stale callback races.

---

# PHASE 9 — BOUNDED RETRY, CACHE FRESHNESS, OWNERSHIP, FULLSCREEN/REWARD HARDENING

## Retry policy

Create injectable `AdRetryPolicy`.

Use stable `LoadAdError.code`/domain rather than parsing English messages where possible.

Classes:
- invalidRequest;
- network;
- noFill;
- internal;
- unknown.

Target policy:
- invalid request/config: 0 automatic retries; dormant until meaningful reset;
- no fill: no immediate loop; dormant until meaningful event;
- network: ~2s, ~8s, ~30s, ~60s with ~±20% jitter; stop;
- internal/unknown: fewer than network; stop;
- default cap: 4 automatic retries per eligibility epoch;
- background: never retry.

Circuit reset only on meaningful event:
- resumed;
- offline -> online if reliable connectivity source exists;
- consent blocked -> allowed;
- config disabled -> enabled;
- explicit rewarded user action.

Do not reset just because a minute passed.

Inject:
- clock;
- random/jitter;
- scheduler/timer abstraction where practical.

No real sleeps in unit tests.

## Cache freshness

One constant:

```dart
const kAdCacheMaxAge = Duration(minutes: 55);
```

Every cached object has `loadedAt`.

Before show:
- eligibility;
- exists;
- fresh;
- otherwise dispose and optionally start one replacement load.

Stale rewarded ad must not create a reward claim.

Resume:
- purge stale;
- then eligible preload.

No periodic background refresh loop.

## Ownership

Every ad object has one explicit owner/handle.

Exactly-once dispose.

Handle:
- generation;
- loading state;
- ready state;
- show state;
- stale state;
- route suppression;
- service disposal.

## Fullscreen serialization

Never show overlapping:
- interstitial;
- rewarded;
- rewarded interstitial.

## Rewarded

Preserve:
- server claim before show;
- SSV user/claim identifiers;
- server-pending client result;
- no direct wallet mutation.

Before show:
- fresh;
- eligible;
- correct current claim;
- no fullscreen conflict.

## Rewarded interstitial

Keep clear reward disclosure and skip path before display.

## Tests

Full matrix from source Plan A.

---

# PHASE 10 — NATIVE AD THEME PARITY, ADCHOICES, AND PLACEMENT DIAGNOSTICS

## Objective

Every native-ad placement visually follows the HomePilot app-selected theme without causing extra ad requests.

## Theme transport

Use schema-versioned `NativeAd.customOptions` or equivalent local presentation contract.

Pass:
- schema version;
- HomePilot light/dark mode;
- explicit app-owned palette tokens required by the Android factory.

Do not rely on `values-night` to infer app theme because HomePilot may override system theme.

All placements use one shared builder/helper so option schema cannot drift.

## Kotlin factory

Parse defensively:
- missing options -> safe default;
- unknown schema -> safe default + sanitized diagnostic;
- no crash for malformed presentation values.

Theme:
- app-owned background;
- badge;
- label;
- headline/body/advertiser;
- CTA;
- borders/radii/drawables as appropriate.

Do not recolor Google-owned creative media.

## Runtime theme change

A theme change must not create extra ad requests merely for presentation.

Prefer:
- recreate/rebind platform view around the same valid native ad only if plugin ownership supports it safely;
- otherwise defer visual recreation until a normal ad lifecycle transition.

Never violate one-owner disposal.

## AdChoices

Either:
- explicitly register/use the custom `AdChoicesView` according to current GMA API; or
- remove the redundant custom view and allow the SDK-supported indicator.

Do not leave a decorative unregistered AdChoices placeholder.

## Diagnostics

Include placement identity independently from shared unit identity.

Log only sanitized:
- placement;
- format;
- theme contract version;
- result class.

No ad identifiers beyond what is necessary for safe internal diagnosis.

## Tests

- all placements pass the same theme schema;
- light/dark palette mapping;
- explicit app theme overrides system;
- theme change does not increment ad request count;
- malformed options safe;
- AdChoices behavior;
- touch/overlay protections retained;
- Android device screenshots.

---

# PHASE 11 — GOOGLE AUTH, FIREBASE ANALYTICS REMOVAL, GOOGLE SERVICES CONFIG HYGIENE

## Firebase Analytics

Because no intentional Analytics product feature was found:

Remove direct Android dependencies:
- Firebase BOM used only for Analytics;
- `firebase-analytics`.

Remove nondeterministic:

```kotlin
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
```

Only after confirming no other required feature depends on Google Services config.

If `google-services.json.example` serves only unused Analytics:
- delete it;
- remove setup docs.

Explicitly ignore:

```gitignore
/android/app/google-services.json
/android/app/src/*/google-services.json
```

Add a CI/static check that the direct Firebase Analytics artifact is not reintroduced. Do not fail because GMA has unrelated measurement transitive components.

## Google gateway contract

Extend gateway with a distinct revocation operation:

```dart
Future<void> disconnect();
```

Normal sign-out remains `signOut()`.

Account deletion uses `disconnect()` after server deletion success / during final auth cleanup according to the safe ordering.

## Initialization recovery

Implement the retryable failed-initialization gate described earlier.

## Scope/token contract

Document why each requested scope exists.

Do not broaden scopes.

## Tests

- init success cached;
- init failure can retry;
- no parallel init;
- normal signout does not disconnect;
- deletion disconnects;
- disconnect failure does not undo completed deletion;
- token exchange contract;
- no token logging.

---

# PHASE 12 — EXTERNAL GOOGLE PLAY ACCOUNT-DELETION WEB RESOURCE

**Current-main release blocker:** the existing `download-site/account-deletion.js` is a simulation. Treat any simulated authentication/deletion success as a correctness and policy defect. The first safe commit in this area must ensure the page cannot claim deletion succeeded without a real authenticated backend result.

## Objective

Provide a stable public account-deletion resource that works without the Android app.

## Authorized scope

This phase may modify `download-site/**` and its build/deploy tooling only as needed for the deletion resource.

Preserve VersionDeck behavior.

## Preferred files

Equivalent to:

```text
download-site/account-deletion.html
download-site/account-deletion.css
download-site/account-deletion.ts|js
tool/build_account_deletion_site.mjs
tool/account-deletion-site.test.mjs
```

Update deployment/build/validation where required.

## Page requirements

- identifies HomePilot;
- prominently explains account deletion;
- explains remote/cloud data deletion;
- discloses legitimate retention;
- functional request/delete path;
- no app reinstall requirement;
- HTTPS stable URL;
- mobile/keyboard accessible;
- privacy/support links;
- no analytics/ads trackers;
- restrictive CSP compatible with bundled dependencies.

## Preferred flow

Use pinned/bundled Supabase JS, not a random runtime CDN.

Browser receives only public config:
- public Supabase URL;
- publishable/anon key;
- site origin/redirect.

Never service-role keys.

Flow:
1. Continue with Google;
2. Supabase OAuth;
3. confirm currently authenticated account in privacy-safe form;
4. explicit destructive confirmation;
5. invoke existing protected `delete-account` Edge Function with bearer session;
6. validate receipt;
7. sign browser session out;
8. show completion without backend identifiers.

Identity comes from the authenticated session, never a submitted email/user ID.

## CORS

If changes required:
- exact production site origins;
- test/local origins only where needed;
- CORS is not authorization;
- bearer auth + body confirmation remain mandatory.

## Device-local note

Do not claim a browser can delete files on a separately installed Android app.

Explain remote deletion accurately.

Audit app behavior after remote account invalidation and ensure account-scoped local state is safely detached without risking unrelated offline data.

## Tests

As listed in Source Plan A.

## Operator step

Do not claim Play Console URL entry complete.

Report the exact deployed URL and required Play Console action.

---

# PHASE 13 — GOOGLE PLAY AAB RAIL, BACKEND CI, AND RELEASE EVIDENCE

**Current-main delta:** `tool/build_play_prod.ps1` and `.github/workflows/build-play-android.yml` already exist. Extend and harden them; do not duplicate the rail. Backend SSV/DB/Google CI and the complete release-evidence bundle are still missing.

## AAB rail

Add `tool/build_play_prod.ps1` with the same safety gates as APK:
- prod config;
- signing;
- analyze;
- full relevant tests;
- production config test;
- no release integration-test plugin leak.

Build:

```text
flutter build appbundle --flavor prod --release --dart-define-from-file=config/prod.json
```

Discover/validate actual output path.

## Workflow

Add `build-play-android.yml`:
- manual dispatch initially;
- only `main`;
- protected environment;
- `cancel-in-progress: false`;
- same Java/Flutter pins as production APK;
- protected signing;
- AAB build;
- signature/certificate verification;
- artifact upload;
- provenance attestation if supported;
- merged manifest/dependency evidence;
- no automatic Play upload.

## Signing documentation

Record distinction:
- upload certificate;
- Play App Signing certificate.

Do not assume they are identical.

Google OAuth may need Play App Signing certificate for Play-installed builds.

## Backend CI

Add/update a workflow to gate:
- Deno SSV tests;
- Supabase database monetization tests;
- Google static/config contracts.

Do not weaken local/CI DB security tests.

## Merged manifest/dependency evidence

Generate and archive:
- merged release manifest;
- Gradle dependency report;
- package/version/target API;
- signing evidence;
- relevant Google/Firebase artifact checks.

Add assertions:
- target API >= 36;
- expected AdMob app metadata;
- no fine/background location;
- exact-alarm permission intentional;
- no direct Firebase Analytics;
- release not debuggable;
- no accidental test ad identifiers in production config path.

---

# PHASE 14 — DOCUMENTATION, PRIVACY, DATA SAFETY EVIDENCE, AND STALE PLAN CLEANUP

**Current-main immediate correction:** before describing Build 35 as compliant, remove or rewrite claims in `CHANGELOG.md` and `PRIVACY.md` that assert implemented behavior not supported by code. Documentation truthfulness is not deferred until the end; correct false safety/deletion claims early, then perform the full documentation synchronization after implementation.

## Required documentation review

At minimum:
- `CHANGELOG.md`
- `PRIVACY.md`
- `docs/permissions.md`
- `docs/reference/routes-and-permissions.md`
- `docs/product/feature-catalog.md`
- `docs/development/localization-and-rtl.md`
- `docs/development/testing.md`
- `docs/architecture/monetization.md`
- `docs/request-audit-report.md`
- configuration/getting-started docs
- VersionDeck release runbook if deletion page changed it
- new Google Play release runbook.

## Correct stale claims

Documentation must reflect:
- one process-scoped splash;
- truthful permission/capability model;
- exact timing fallback;
- weather manual/device semantics;
- unified feedback policy;
- current SDK set after Analytics removal;
- ad runtime eligibility;
- SSV security;
- account deletion in-app + external;
- APK vs Play AAB rails.

## Data Safety evidence

Create/refresh an internal evidence document that maps:
- SDKs;
- permissions;
- data categories;
- purpose;
- collection/sharing;
- account deletion;
- retention;
- consent surfaces;
- store/operator fields requiring manual verification.

Do not claim the Play Console form itself is updated unless the operator actually does it.

## Historical plans

Do not leave older overlapping plans looking simultaneously current.

Mark obsolete permission/splash/feedback/Google plan docs historical/superseded where they exist in the repo, without deleting useful audit history unless repository policy calls for it.

---

# PHASE 15 — COMPLETE AUTOMATED, DEVICE, CONSOLE, AND ROLLOUT VALIDATION

## Repository validation

Run exactly as current `AGENTS.md` requires, including:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Run the production-config test with the documented example configuration.

Run additional:
- Deno SSV tests;
- Supabase DB tests;
- account-deletion site tests;
- site validator;
- Play build script dry/real CI path as available;
- Gradle manifest/dependency static checks.

Do not generate unrelated Drift noise if schema did not change.

## Device matrix

At minimum:
- Android 10;
- Android 11;
- Android 12;
- a current API level supported by HomePilot, including API 36 when environment allows.

Test cold starts, not only hot reload.

## Splash cases

- signed in;
- signed out;
- slow startup;
- offline;
- theme light/dark;
- Arabic/English;
- background/resume;
- deep link/notification routing;
- no native->Flutter flash;
- no duplicate overlay.

## Permission cases

- notification first request;
- denied;
- permanent/blocked;
- settings return;
- exact access denied/granted;
- inexact fallback;
- location denied;
- service off;
- manual location;
- device location then revoke;
- reboot/update scheduling restoration.

## Feedback cases

- rapid Trash;
- Undo;
- route change during Undo;
- keyboard;
- FAB/bottom nav;
- task bottom action bar;
- Arabic RTL;
- 200% text;
- TalkBack/accessibility navigation;
- reduced motion;
- error queued behind Undo;
- Undo failure.

## Monetization cases

Use only test ads / registered test devices.

Never click production ads.

Test:
- UMP allowed/blocked;
- privacy options;
- background/resume;
- remote global/format kill switches;
- offline/no-fill/network errors;
- retry stop;
- stale ads;
- theme switches with native ads;
- route/modal native suppression;
- rewarded/rewarded interstitial;
- full-screen serialization;
- claim pending/recovery.

## Auth/account

- sign in;
- cancel;
- sign out;
- init failure/retry;
- delete with same Google account;
- wrong reauth account rejected;
- Google disconnect;
- disconnect failure after server deletion;
- externally deleted account/session invalidation.

## Console/operator

Report as outstanding unless actually verified:
- AdMob app/units/Privacy & messaging/test devices;
- Google OAuth clients/certificates;
- Play App Signing;
- Data Safety;
- account-deletion URL field;
- privacy policy URL;
- AAB upload/internal track;
- Supabase production CORS/environment.

## Rollout

Use remote monetization flags as emergency rollback.

Recommended:
1. merge code with ads controllable;
2. validate internal/test build;
3. deploy deletion page;
4. verify Play/OAuth/AdMob configuration;
5. build AAB;
6. internal testing;
7. staged rollout;
8. observe privacy-safe metrics/errors;
9. widen only after evidence.

---

# 8. CROSS-PLAN FILE OWNERSHIP / CHANGE MAP

This is not exhaustive; use repository search.

## `lib/main.dart`

Likely touched by:
- stable root/splash;
- Settings notification commands;
- dashboard weather capability state;
- feedback call-site migration;
- monetization provider/listener ownership.

Rule: do not combine all of these into one giant edit/commit. Establish root topology first, then layer behavior changes.

## `lib/homepilot_animated_splash_screen.dart`

- one presentation component;
- splash token;
- reduced motion;
- lifecycle/timer hardening;
- semantics/input.

## `lib/src/core/domain/models.dart`

- notification defaults/migration semantics;
- capability snapshots if domain-appropriate.

Avoid dumping unrelated UI state into core models if feature-domain types fit better.

## Permission files

- one canonical platform capability source;
- feature gateway delegates;
- pure derived snapshots;
- controller no longer fabricates permission state.

## `lib/src/ui/components.dart`

Shrink transient-feedback responsibility over time.
Do not make it an even larger coordinator monolith.

## `lib/src/core/services/feedback_messenger.dart`

Preserve the global root key but centralize policy in the new feedback coordinator.

## `lib/src/ui/app_theme.dart`

Extend semantic feedback palette carefully.
Do not break the rest of the theme.

## Monetization files

Keep existing business/security policy while introducing runtime state machine, retry/cache/ownership helpers.

## `native_google_sign_in.dart`

- disconnect;
- safe initialization gate;
- documented minimal scopes.

## `supabase_auth_repository.dart`

- distinguish logout vs deletion revocation;
- preserve same-user reauth and remote deletion ordering.

## Android Gradle/config

- remove direct unused Firebase Analytics;
- deterministic Google Services behavior;
- explicit ignore;
- target API 36;
- release assertions.

## Native ad XML/Kotlin

- theme options;
- AdChoices cleanup;
- accessibility/touch safety;
- no creative manipulation.

## CI/release

Keep current APK workflow.
Add Play-specific workflow.
Add backend/Google validation.
Archive evidence.

## `download-site/**`

Only account-deletion scope during this remediation.

---

# 9. COMMIT STRATEGY

Use small, reviewable commits. A reasonable sequence:

1. `test(startup): characterize process splash ownership defects`
2. `refactor(startup): establish stable application and splash root`
3. `fix(splash): mount early and harden continuity/accessibility`
4. `refactor(permissions): add effective capability state model`
5. `fix(permissions): separate manual weather setup from OS permission`
6. `fix(notifications): decouple preferences from permission prompts`
7. `fix(reminders): make exact timing contextual with inexact fallback`
8. `feat(feedback): add unified feedback coordinator and surface`
9. `refactor(feedback): migrate Trash/completion/destructive flows`
10. `refactor(feedback): migrate remaining transient messages`
11. `refactor(ads): add runtime eligibility generation state`
12. `fix(ads): bound retries and enforce cache freshness/ownership`
13. `fix(ads): harden rewarded/fullscreen/native behavior`
14. `fix(ads): add native app-theme parity and AdChoices cleanup`
15. `fix(auth): add disconnect and recoverable Google initialization`
16. `chore(android): remove unused Firebase Analytics configuration`
17. `feat(web): add external HomePilot account-deletion resource`
18. `ci(play): add protected production AAB rail and evidence`
19. `ci(security): gate SSV/database/Google contracts`
20. `docs: align privacy, permissions, monetization and release docs`

Combine only when changes are inseparable and still reviewable.

---

# 10. TEST DESIGN PRINCIPLES

1. No real timer sleeps for retry/countdown logic.
2. Inject time/jitter/scheduler where timing policy matters.
3. Assert behavior, not implementation trivia.
4. Keep security tests strong.
5. Add race tests for stale async callbacks.
6. Add exactly-once tests for:
   - ad disposal;
   - Undo callbacks;
   - splash removal;
   - deletion cleanup.
7. Use fakes at domain boundaries instead of platform plugins in pure tests.
8. Device-only claims remain device-only.
9. Avoid brittle screenshot/image hashes for generated splash assets when dimension/resource assertions are sufficient.
10. Test theme/locale/accessibility changes while active UI exists, not only at startup.

---

# 11. OBSERVABILITY RULES

Allowed diagnostic dimensions should be coarse and privacy-safe.

Examples:
- component;
- event;
- ad format;
- placement;
- failure class;
- sanitized SDK error code/domain;
- eligibility reason enum;
- retry attempt number;
- generation;
- capability state enum;
- feedback mode/tone;
- operation category.

Do not log:
- OAuth ID/access tokens;
- authorization codes;
- raw SSV `user_id`;
- raw SSV `custom_data`;
- SSV signatures;
- full ad responses;
- exact coordinates;
- sensitive user content;
- service-role credentials;
- browser auth session tokens;
- unnecessary advertising identifiers.

Rate-limit recurring failure logs.

---

# 12. SECURITY / PRIVACY STOP CONDITIONS

Stop the specific subtask and document the issue if implementation would require:

- weakening RLS;
- exposing a service-role secret;
- accepting browser-provided user identity as deletion authorization;
- directly crediting a reward client-side;
- trusting client-controlled IP forwarding headers for SSV;
- using production ads for automated testing;
- adding fine/background location;
- replacing `SCHEDULE_EXACT_ALARM` with `USE_EXACT_ALARM` without explicit review;
- automatic Play publishing before operator prerequisites are verified;
- inventing OAuth/AdMob/Firebase/Supabase/signing IDs;
- broad dependency/supply-chain additions without review.

Continue independent tasks.

---

# 13. FINAL DEFINITION OF DONE

The remediation is complete only when all applicable items below are true.

## Startup/splash

- one process-scoped Flutter splash owner;
- first meaningful Flutter frame includes splash;
- no restart/reappearance;
- no blank color bridge;
- root/messenger/providers survive auth transitions;
- reduced-motion and interaction tests pass.

## Permission/weather/reminders

- preference != permission != effective capability in the model;
- manual location never fakes OS grant;
- settings cards open the correct target;
- exact timing defaults false for new users without overwriting existing choices;
- no unrelated permission prompts;
- inexact fallback preserved;
- weather privacy preserved;
- EN/AR/RTL/a11y verified.

## Feedback

- one app-wide coordinator;
- protected Undo;
- all Trash flows undoable;
- completion undoable;
- permanent deletion non-undoable;
- no vertical stack;
- batching/coalescing deliberate;
- root FAB/nav do not jump;
- accessibility timeout is coherent;
- no ad-hoc production SnackBars outside approved layer.

## Ads

- runtime consent/lifecycle/config gates at every request/show;
- generation invalidates stale callbacks;
- bounded retry;
- no-fill/config do not loop;
- 55-minute freshness;
- exactly-once ownership;
- fullscreen serialized;
- rewarded remains server-authoritative;
- native theme parity across placements;
- AdChoices correct;
- test ads used for testing.

## Google/Firebase

- unused direct Firebase Analytics removed;
- Google Services config deterministic;
- production Google config explicitly ignored;
- Google init failure recoverable;
- logout vs disconnect semantics correct;
- scopes minimal/documented.

## Account deletion

- in-app deletion still works securely;
- external deletion resource exists and is tested;
- no service-role key exposed;
- browser identity derived from session;
- explicit confirmation;
- public production deployment/operator verification reported honestly.

## Release/CI

- current APK rail still works;
- Play AAB rail exists separately;
- target API 36 protected;
- signing evidence generated;
- backend SSV/DB tests gated;
- merged manifest/dependency evidence available;
- no first-pass auto upload to Play.

## Documentation

- changelog updated;
- privacy reviewed;
- Data Safety evidence aligned;
- permissions/monetization/release/request audit corrected;
- obsolete overlapping plan state handled.

---

# 14. FINAL REPORT FORMAT REQUIRED FROM THE IMPLEMENTING AGENT

Return a final implementation report with exactly these sections:

## 1. Baseline
- starting commit
- ending commit
- branch
- whether baseline drift existed

## 2. Changes by remediation domain
- startup/splash
- permissions/weather/reminders
- feedback
- monetization/ads
- Google auth/Firebase
- account deletion web
- Play/CI/release
- documentation

## 3. Security/privacy invariants preserved
Explicitly name the reward, RLS, deletion, consent, location, logging, and release boundaries.

## 4. Tests run
For each command:
- exact command
- result
- noteworthy output

## 5. Tests not run
State why.

## 6. Device/manual verification
Separate:
- performed and passed;
- not performed / still required.

## 7. External console/operator actions
List outstanding AdMob, Google Cloud, Play Console, GitHub Pages, Supabase, and signing actions.

## 8. Dependency changes
List every dependency change and why.
If none, say none.

## 9. Documentation changes

## 10. Remaining risks / follow-ups
Only genuine remaining items.

Do not claim completion if required automatic tests are failing.

---


## Codex-specific completion report additions

In addition to the report format above, the Codex final response/PR description must include:

1. starting branch and starting HEAD;
2. ending HEAD / commit list if commits were created;
3. a phase-by-phase delta table: `preserved`, `implemented`, `not applicable`, `blocked`, or `unverified`;
4. exact commands run and their exit status;
5. tests added/changed;
6. documentation reviewed/changed;
7. protected or external actions **not** performed;
8. any secrets/configuration/console values still required from the operator;
9. explicit statement that the external deletion page never reports success without backend evidence;
10. explicit statement that no production ad clicking, Play upload, Supabase destructive linked operation, or protected deployment was performed unless separately authorized and evidenced.

# 15. SOURCE FILE INTEGRITY

The following four uploaded source plans are embedded verbatim below.

Their SHA-256 values at synthesis time are recorded so an operator can verify that this master file did not silently substitute a different source.

- `HomePilot_Google_AdMob_Play_Remediation_Plan_v2(1).md` — SHA-256 `609ad490c56fe0c476dfd2318bf2c9f78a37fe29ae0f974039a4db0b2e1fdf59`
- `HomePilot_Permission_Notification_Weather_Full_Remediation_Plan(1).md` — SHA-256 `20ebedb8e43f74490a338de3868b883fb283018713b7844b585f448d46ab63cc`
- `HomePilot_splash_full_fix_improvement_plan(1).md` — SHA-256 `320bf13b3c9bdb32c2612b033868191e1ac3fba37fe0e7ab04909955ee48a251`
- `homepilot_unified_feedback_ai_agent_prompt(1).md` — SHA-256 `75d7e13094820deced12f63b242aa9d06e0f6dd09427534b6528c5ecea6c3342`


---

# 16. ORIGINAL SOURCE PLANS — VERBATIM HISTORICAL APPENDICES

**Codex warning:** the appendices below are preserved verbatim for requirement completeness and audit history. They describe the historical `075cd6ff5c36bb9c05b03f10a20598310ecf000d` baseline. Do not treat their implementation-state claims as current when they conflict with Section 2.0A or repository inspection.

The normalized sections above define execution order and resolve cross-plan conflicts. The appendices preserve the full original requirements, test matrices, file lists, operator checklists, examples, and detailed acceptance criteria.

If an appendix is more specific than the normalized master prompt and does not conflict with it, implement the appendix requirement.

If a current official platform requirement materially contradicts an appendix, follow the newer official requirement, document the delta in the PR, and preserve the intent/security boundary.


---

# APPENDIX A — Original Google / AdMob / UMP / Google Play Remediation Plan

<!-- BEGIN VERBATIM SOURCE: HomePilot_Google_AdMob_Play_Remediation_Plan_v2(1).md -->

# HomePilot Google / AdMob / UMP / Play Remediation — Full AI Agent Implementation Plan

**Repository:** `zuhak5/HomePilot`  
**Baseline branch:** `main`  
**Baseline commit:** `075cd6ff5c36bb9c05b03f10a20598310ecf000d`  
**Application baseline:** `1.4.8+34`  
**Plan date:** 2026-08-08  
**Plan status:** Implementation-ready engineering runbook  
**Revision:** 2026-08-08 — added mandatory native-ad app-theme parity across every placement/screen  
**Primary goal:** Apply all actionable findings from the Google/AdMob/Google Play audit while preserving HomePilot's existing strong reward-security controls and avoiding invalid-traffic, privacy, consent, release, lifecycle, and theme-consistency regressions.

---

## 0. How the coding agent must use this plan

This file is an **execution specification**, not a suggestion list.

The implementing AI agent must:

1. Work from a dedicated branch created from the baseline commit above, or from a later `main` only after completing the baseline-drift check in Phase 0.
2. Re-read every file before modifying it. Do not patch from excerpts in this document.
3. Preserve the existing strong AdMob SSV and database authorization model unless a change in this plan explicitly requires touching it.
4. Never invent production Google, AdMob, Firebase, OAuth, Supabase, Play Console, certificate, package, callback, or signing values.
5. Never click or intentionally interact with live production ads during implementation or testing.
6. Use Google's demo ad units or registered test devices for all development/device verification.
7. Keep existing production APK/VersionDeck distribution working while adding a **separate** Google Play AAB release path.
8. Treat consent state, app lifecycle, remote monetization configuration, format configuration, and ad freshness as **hard request eligibility inputs**, not merely UI hints.
9. Keep all reward credit server-authoritative. `onUserEarnedReward` must never directly credit points.
10. Add tests before or in the same change set as behavioral modifications.
11. Prefer fail-closed behavior for consent, configuration, destructive account operations, and release configuration.
12. Keep logs free of Google ID tokens, OAuth access tokens, SSV signatures, raw SSV `user_id`, raw `custom_data`, sensitive account details, and unnecessary ad identifiers.
13. Do not weaken Row Level Security, service-role boundaries, transaction replay protection, SSV signature validation, reward amount validation, or wallet invariants.
14. Do not add automated Play publishing until the operator has verified Play App Signing, OAuth certificates, store configuration, and service-account permissions. A protected AAB build rail is required; automated upload is a later opt-in step.
15. If implementation discovers a material contradiction between this plan and the current official Google documentation, stop that specific subtask, document the conflict, and follow the newer official requirement.

### Required working style

Use small, reviewable commits. Do not combine unrelated behavioral changes into one giant commit.

At every phase:

- run the phase-specific tests;
- run the full Flutter validation suite;
- inspect the diff for accidental ID/config changes;
- update documentation when behavior changes;
- keep a short implementation note in the PR describing what changed and which acceptance criteria passed.

---

# 1. Baseline audit summary the agent must preserve

The baseline already does several important things correctly. Do **not** regress them.

## 1.1 Existing strengths to preserve

### UMP startup behavior

`HomePilotConsentService` currently:

- calls `requestConsentInfoUpdate()` on app startup;
- uses `loadAndShowConsentFormIfRequired()`;
- retrieves `canRequestAds()`;
- retrieves privacy-options requirement status;
- initializes Google Mobile Ads only when UMP says ads may be requested.

Preserve this basic order.

### Test-vs-production ad IDs

`HomePilotAdUnits` currently uses Google's documented demo IDs outside production and HomePilot production IDs in production.

Preserve this invariant:

> A development/staging build must not accidentally use live production ad units unless an explicit, reviewed test-device workflow requires it.

### Conservative interstitial placement

`InterstitialEligibilityPolicy` already blocks or limits interstitials based on:

- first-ever session;
- rapid completion;
- keyboard visibility;
- active modal;
- global ads flag;
- interstitial-specific flag;
- session cap;
- cooldown.

Preserve all of these controls.

### Reward trust boundary

The client:

1. creates a server-side reward claim;
2. attaches `userId` and claim ID as SSV values;
3. waits for the ad lifecycle;
4. reports `server_pending`;
5. does **not** directly mutate the wallet.

The backend independently validates Google SSV and the database independently validates claim identity, transaction replay, ad unit, reward amount, timestamp, wallet cap, daily limits, and atomic settlement.

This is the correct model. Keep it.

### Native-ad overlay/navigation protections

The current implementation intentionally tears down native ad platform views before overlays/navigation interactions that could otherwise receive accidental gestures.

Preserve that defense while fixing ownership and lifecycle races.

---

# 2. Findings this plan closes

## P1 — release/policy significant

1. UMP eligibility is not continuously enforced by the ad loaders after SDK initialization.
2. Firebase Analytics is packaged even though HomePilot does not intentionally use it, creating unnecessary privacy/consent/Data Safety ambiguity.
3. Google account deletion signs out but does not explicitly disconnect/revoke Google authorization.
4. Google Play external account-deletion resource is not implemented/verified in the repository.
5. The release rail builds APK only; there is no dedicated Play AAB rail.

## P2 — engineering/reliability significant

6. Failed ad requests can retry forever.
7. Cached ads have no one-hour freshness control.
8. Remote per-format kill switches do not actually stop full-screen requests/retries.
9. Full-screen ad loading/retrying is not foreground/background aware.
10. Native-ad ownership can dispose the same object more than once during races.
11. Firebase/Google Services build behavior depends on whether an untracked local `google-services.json` happens to exist.
12. Real Google Services config is not explicitly ignored.
13. SSV/DB tests are not fully release-gated by GitHub CI.
14. `docs/request-audit-report.md` overstates request behavior and is stale relative to current code.

## P3 — lower-severity improvements

15. Google Sign-In initialization failure is sticky for the gateway lifetime.
16. Google authorization scopes/access-token behavior needs an explicit minimal-scope contract.
17. `google-services.json.example` is misleading if Firebase is not intentionally used.
18. Native XML contains a custom `AdChoicesView` that is not registered by the native factory.
19. Shared native unit mapping limits placement-level diagnostics.
20. CI does not archive/assert the final merged Google-related Android manifest and release configuration.

---

# 3. Official requirements and recommendations — source of truth

Before coding, re-open these pages and confirm they have not materially changed.

## Google UMP / consent

- Flutter UMP setup: `https://developers.google.com/admob/flutter/privacy`
- Consent mode: `https://developers.google.com/admob/flutter/privacy/consent-mode`

Key implementation rule:

> Call `requestConsentInfoUpdate()` each launch and gate ad requests using `canRequestAds()`.

The runtime architecture in this plan intentionally enforces that rule at the **load/show boundary**, not only at app startup.

## Google Mobile Ads

- Flutter interstitial: `https://developers.google.com/admob/flutter/interstitial`
- Flutter rewarded: `https://developers.google.com/admob/flutter/rewarded`
- Flutter rewarded interstitial: `https://developers.google.com/admob/flutter/rewarded-interstitial`
- Flutter native/platform implementation: `https://developers.google.com/admob/flutter/native/platforms`
- Android native best practices/cache guidance: `https://developers.google.com/admob/android/native`
- AdMob invalid traffic: `https://support.google.com/admob/answer/3342054`
- Prevent invalid activity: `https://support.google.com/admob/answer/3342099`
- Test-ad enforcement: `https://support.google.com/admob/answer/12251425`

Important behaviors to implement:

- use test ads in development;
- do not generate repetitive live impressions/requests for testing;
- dispose ads when no longer needed;
- show interstitials only at natural transitions;
- rewarded interstitials need clear reward disclosure and a skip path before display;
- clear/reload cached ads before the one-hour lifetime boundary;
- avoid request amplification and uncontrolled retry loops.

## AdMob SSV

- SSV verification: `https://developers.google.com/admob/android/ssv`

Preserve:

- ECDSA signature verification;
- exact signed query handling;
- public key cache below 24 hours;
- transaction replay defense;
- expected HTTP success semantics.

Google currently also recommends reverse-DNS verification. Only add this if Supabase Edge Functions exposes a **trusted** source IP. Never trust a client-controlled forwarded-IP header as a security boundary.

## Google Sign-In

- Current Dart API: `https://pub.dev/documentation/google_sign_in/latest/google_sign_in/GoogleSignIn-class.html`
- Google disconnect/revocation guidance: `https://developers.google.com/identity/sign-in/android/disconnect`
- Supabase native Google ID-token flow: `https://supabase.com/docs/reference/dart/auth-signinwithidtoken`

Important constraint:

Supabase's current native Google documentation states that the Google access token is required for its `signInWithIdToken` flow. Therefore, **do not blindly remove authorization/access-token acquisition**. Keep scopes minimal and documented unless current Supabase behavior is proven otherwise.

## Firebase Analytics

- Analytics collection controls: `https://firebase.google.com/docs/analytics/android/configure-data-collection`

This plan chooses the safest path: **remove Firebase Analytics because HomePilot does not intentionally use it**.

If the product owner later decides to add Firebase Analytics as a real feature, that must be a separate, privacy-reviewed feature with explicit consent-mode and Data Safety work.

## Google Play

- User Data / account deletion: `https://support.google.com/googleplay/android-developer/answer/10144311`
- Account deletion details: `https://support.google.com/googleplay/android-developer/answer/13327111`
- Android App Bundles: `https://developer.android.com/guide/app-bundle`
- Play release preparation: `https://support.google.com/googleplay/android-developer/answer/9859348`
- Target API requirements: `https://support.google.com/googleplay/android-developer/answer/11926878`

The current HomePilot Android config already targets API 36. Preserve that.

---

# 4. Target architecture

The largest remediation is to make ad behavior a deterministic state machine.

## 4.1 Current architectural problem

Today:

- UMP decides whether ads may be initialized;
- `MobileAds.initialize()` creates a permanent `_initialized = true`;
- later loaders mainly check `_initialized`, `_disposed`, loading state, and retry timers;
- UMP revocation, lifecycle, and per-format config are not consistently represented in the loader guard;
- preload work is triggered from both startup and widget build;
- failures own their own timers;
- cached ads have no age;
- in-flight callbacks are not globally invalidated when eligibility changes.

This lets a previously initialized service continue to request ads after its business eligibility has changed.

## 4.2 Required target model

Create one central runtime eligibility model.

Suggested target files:

```text
lib/src/features/monetization/
  ad_runtime.dart
  ad_runtime_controller.dart
  ad_retry_policy.dart
  ad_cache.dart
  home_pilot_ads_service.dart
  consent_service.dart
  native_ad_card.dart
  monetization.dart
```

Do not perform this split as an uncontrolled rewrite. Move behavior incrementally with tests.

### Core enum

```dart
enum AdFormat {
  native,
  interstitial,
  rewarded,
  rewardedInterstitial,
}
```

### Runtime state

```dart
class AdRuntimeEligibility {
  const AdRuntimeEligibility({
    required this.platformSupported,
    required this.appForeground,
    required this.consentUpdated,
    required this.canRequestAds,
    required this.adsEnabled,
    required this.nativeEnabled,
    required this.interstitialEnabled,
    required this.rewardedEnabled,
    required this.rewardedInterstitialEnabled,
  });

  final bool platformSupported;
  final bool appForeground;
  final bool consentUpdated;
  final bool canRequestAds;
  final bool adsEnabled;
  final bool nativeEnabled;
  final bool interstitialEnabled;
  final bool rewardedEnabled;
  final bool rewardedInterstitialEnabled;

  bool canLoad(AdFormat format) { ... }
  bool canShow(AdFormat format) { ... }
}
```

### Required eligibility invariant

A new ad request is allowed **only if**:

```text
platform supported
AND app is resumed/foreground
AND UMP consent info was refreshed for the current app session
AND UMP canRequestAds == true
AND global monetization ads flag == true
AND the specific format flag == true
```

No caller may bypass this invariant.

`MobileAds.initialize()` being complete is **not** equivalent to ad eligibility.

### Runtime generation/epoch

Every eligibility-changing transition increments a generation counter.

Examples:

- consent `true -> false`;
- consent `false -> true`;
- app `resumed -> paused`;
- app `paused -> resumed`;
- global ads disabled/enabled;
- a format disabled/enabled;
- service disposal.

Each async SDK load captures the current generation.

When a callback returns:

```text
if callback generation != current generation:
    dispose returned ad exactly once
    do not cache it
    do not retry
    complete pending future
```

This is the principal race-condition defense.

---

# 5. Phase 0 — baseline freeze, inventory, and pre-change tests

## Objective

Prevent the remediation itself from introducing regressions.

## Files to inspect before any edit

At minimum:

```text
lib/src/features/monetization/monetization.dart
lib/src/features/auth/data/native_google_sign_in.dart
lib/src/features/auth/data/supabase_auth_repository.dart
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/com/homepilot/app/MainActivity.kt
android/app/src/main/kotlin/com/homepilot/app/HomePilotNativeAdFactory.kt
android/app/src/main/res/layout/homepilot_native_ad.xml
pubspec.yaml
pubspec.lock
test/monetization_test.dart
test/supabase_auth_repository_test.dart
test/prod_build_config_test.dart
.github/workflows/validate-flutter.yml
.github/workflows/build-production-android.yml
.github/workflows/deploy-download-site.yml
tool/build_prod.ps1
package.json
PRIVACY.md
docs/architecture/monetization.md
docs/request-audit-report.md
supabase/functions/admob-ssv-handler/index.ts
supabase/functions/admob-ssv-handler/index_test.ts
supabase/functions/delete-account/index.ts
supabase/migrations/*admob*
supabase/tests/database/0012_points_monetization.test.sql
supabase/tests/database/0013_admob_ssv_hardening.test.sql
```

## Baseline drift rule

Run:

```bash
git rev-parse HEAD
git status --short
```

If `HEAD` is not the baseline commit:

1. compare baseline to current HEAD;
2. identify all changed Google/AdMob/auth/release/privacy files;
3. re-audit those changed sections before applying this plan;
4. update the PR description with the new effective baseline.

Do not silently apply line-based assumptions to changed code.

## Create regression tests before behavior changes

Add tests that describe current intentional strengths:

- demo ad unit IDs are used outside production;
- production IDs are selected only for production;
- first-session interstitial suppression;
- cooldown/session cap;
- rewarded result is `server_pending`, never locally credited;
- `showReward()` requires repository;
- native placement is disabled when route is not current;
- native placement is disabled when presentation depth is non-zero;
- UMP snapshot begins in a fail-closed state;
- full-screen `show()` disposes after dismissal/failure;
- SSV claim IDs are opaque IDs and domain data is not inserted into SSV.

These tests become guardrails for the refactor.

## Phase 0 acceptance criteria

- Existing full Flutter test suite is green.
- Current SSV Deno tests are recorded as green or any existing failure is documented.
- Current Supabase DB tests are recorded as green or any existing failure is documented.
- No production IDs/config values were changed.
- A clean baseline test report is attached to the PR.

---

# 6. Phase 1 — separate consent state from SDK initialization

## Objective

Make UMP state a continuously enforced runtime input.

## Current code to replace

`HomePilotConsentService._refreshAndInitializeAds()` currently combines:

1. reading UMP state;
2. publishing consent state;
3. initializing ads.

Separate these responsibilities.

## Required design

### `HomePilotConsentService`

The consent service should own only:

- `requestConsentInfoUpdate`;
- consent form presentation;
- privacy-options form presentation;
- `canRequestAds`;
- privacy-options required status;
- publishing `ConsentSnapshot`.

It must **not** directly preload ads.

### `ConsentSnapshot`

Keep or extend:

```dart
class ConsentSnapshot {
  final bool updated;
  final bool canRequestAds;
  final bool privacyOptionsRequired;
}
```

Optional diagnostic fields:

```dart
final DateTime? refreshedAt;
final ConsentRefreshOutcome outcome;
```

Do not store detailed consent strings or raw regulatory values in logs unless specifically required and reviewed.

### `AdRuntimeController`

Create a Riverpod controller that observes:

- consent snapshot;
- `MonetizationConfig`;
- Flutter app lifecycle;
- platform support;
- `HomePilotAdsService`.

It computes `AdRuntimeEligibility` and calls:

```dart
await ads.applyEligibility(nextEligibility);
```

No unrelated widget may manually call loaders based on partial conditions.

## Remove side effects from `build()`

Current `MonetizationBootstrap.build()` schedules preload work.

Remove request-producing microtasks from widget `build()`.

`build()` must become pure.

Bootstrap should:

- initialize session policy once;
- initialize UMP once;
- register lifecycle observation;
- render child.

All load/reload behavior should be a reaction to controller state transitions, not repeated builds.

## Consent-revocation behavior

When `showPrivacyOptions()` returns and UMP state changes to blocked:

- cancel all retry timers;
- dispose all not-currently-showing cached ads;
- invalidate all in-flight request generations;
- prevent new requests;
- collapse native placements;
- prevent post-dismiss reload.

Do **not** attempt to programmatically dismiss a full-screen ad already being shown.

## Consent restoration behavior

If UMP later returns `canRequestAds == true`:

- ensure SDK initialization is complete;
- move to eligible state;
- preload only enabled full-screen formats;
- let visible native placements request their own ad;
- do not fire duplicate preload requests from multiple listeners.

## Phase 1 tests

1. initial consent `updated=false` blocks every format;
2. `canRequestAds=false` blocks every load;
3. `canRequestAds=true` + ads enabled + foreground allows enabled formats;
4. privacy options `true -> false` cancels retries;
5. privacy options revocation disposes ready cached ads;
6. privacy options revocation invalidates an in-flight callback;
7. stale callback returns an ad and it is disposed, not cached;
8. repeated identical eligibility snapshots do not trigger duplicate work;
9. `build()` does not produce ad requests.

## Phase 1 acceptance criteria

- No ad loader can execute based only on `_initialized`.
- `canRequestAds()` is represented in the actual request guard.
- Consent revocation quiesces future ad traffic without application restart.
- Widget rebuilds do not create ad-request churn.

---

# 7. Phase 2 — app lifecycle as a hard ad-request gate

## Objective

Prevent ad loads/retries while HomePilot is backgrounded or non-interactive.

## Required lifecycle mapping

Treat **only** `AppLifecycleState.resumed` as foreground/request-eligible.

Treat these as not eligible for starting a request:

- `inactive`
- `hidden`
- `paused`
- `detached`

Use the exact lifecycle values supported by the pinned Flutter version.

## Implementation

Add a lifecycle observer owned by the monetization runtime.

Do not distribute `WidgetsBindingObserver` logic through individual ad classes.

When the app leaves `resumed`:

- mark runtime `appForeground=false`;
- cancel retry timers;
- invalidate in-flight request generation;
- keep actively showing full-screen ad ownership untouched;
- dispose ready/preloaded ads under the recommended simple policy;
- native route views should be removed/destroyed when their route is no longer active.

Recommended safest policy:

> Dispose preloaded ads on background and acquire fresh ads after resume.

This trades a small reload cost for simpler consent/freshness/lifecycle reasoning.

When app resumes:

- refresh runtime state;
- do **not** automatically retry every historical failure;
- if eligible, preload enabled full-screen formats once;
- visible native placements may load once;
- reset retry circuit state only as described in Phase 4.

## Important full-screen nuance

Showing a Google full-screen ad may cause app lifecycle changes.

Therefore:

- when `show()` begins, the cached reference is transferred to a **showing owner** and removed from ready cache;
- background/lifecycle cleanup must not dispose that showing object;
- `FullScreenContentCallback` remains the only lifecycle owner for that ad;
- on dismissal/failure, callback disposes it once;
- then request eligibility is re-evaluated before any replacement load.

## Phase 2 tests

- pause while retry timer is active -> timer cancelled;
- pause while ad request is in flight -> stale callback disposed;
- resume -> exactly one eligible preload pass;
- resume while consent false -> zero loads;
- full-screen show causing inactive state does not double-dispose the showing ad;
- dismissal while still paused does not trigger reload;
- dismissal after app resumes may trigger one reload if eligible.

---

# 8. Phase 3 — per-format remote flags become real kill switches

## Objective

Make remote config able to stop traffic, not merely stop presentation.

## Required behavior

For each format:

```text
global ads flag
AND format-specific flag
```

must control:

- load eligibility;
- retry eligibility;
- cache retention;
- show eligibility.

## Required transitions

### Enabled -> disabled

For that format:

- cancel retry;
- invalidate in-flight generation;
- dispose ready ad;
- clear cached timestamp;
- block `show`;
- block post-dismiss load.

### Disabled -> enabled

Do not immediately flood all formats.

If foreground + consent allowed:

- full-screen format: permit one preload;
- native: visible placement initiates one load.

## Tests

For all four formats:

- disable before request;
- disable during request;
- disable while retrying;
- disable while ready;
- re-enable;
- global ads disable overrides every format;
- format disable does not incorrectly disable unrelated formats.


---

# 9. Phase 4 — replace infinite retry loops with bounded retry policy

## Objective

Prevent request amplification, invalid-traffic risk, unnecessary battery/network use, and background churn.

## New component

Create an injectable `AdRetryPolicy`.

Suggested contract:

```dart
enum AdLoadFailureClass {
  invalidRequest,
  network,
  noFill,
  internal,
  unknown,
}

class AdRetryDecision {
  const AdRetryDecision({
    required this.retryAutomatically,
    this.delay,
    required this.requiresMeaningfulEventToReset,
  });

  final bool retryAutomatically;
  final Duration? delay;
  final bool requiresMeaningfulEventToReset;
}

abstract interface class AdRetryPolicy {
  AdRetryDecision decide({
    required AdFormat format,
    required AdLoadFailureClass failureClass,
    required int consecutiveFailures,
  });
}
```

## Failure classification

Use `LoadAdError.code`, `domain`, and other stable fields supported by the pinned `google_mobile_ads` plugin.

Do not parse English message text if a stable code/domain exists.

### Invalid request / configuration error

- zero automatic retries;
- enter dormant state;
- require config/app restart or another explicit meaningful transition.

### No fill

- no immediate loop;
- mark dormant;
- allow a later attempt on a meaningful user/runtime event.

Do not retry every minute indefinitely.

### Network error

Allow bounded retries, for example:

```text
attempt 1: ~2 seconds
attempt 2: ~8 seconds
attempt 3: ~30 seconds
attempt 4: ~60 seconds
then stop
```

Add jitter of approximately ±20%.

### Internal/unknown

Use fewer automatic retries than network errors, then stop.

## Maximum automatic attempts

Recommended default: **4 automatic retries per eligibility epoch**.

After the cap, the format enters a dormant/circuit-open state.

## Meaningful events that may reset the circuit

- app returns to foreground;
- connectivity changes from offline to online if HomePilot already has a reliable connectivity service;
- consent transitions blocked -> allowed;
- format/global config transitions disabled -> enabled;
- explicit user action requests a rewarded ad and no request is already active.

Do not reset simply because one minute elapsed.

## Testability

Inject:

- clock;
- random/jitter source;
- timer scheduler if practical.

Unit tests must not sleep in real time.

## Logging

Log at most:

- failure class;
- format;
- consecutive attempt count;
- retry scheduled yes/no;
- sanitized error code/domain.

Do not log full ad request/response objects.

## Tests

- exact retry count cap;
- jitter range;
- invalid request never retries;
- no-fill does not loop;
- network retries stop at cap;
- success resets failure count;
- eligibility epoch change invalidates old timer;
- disposed service never retries;
- background never retries.

---

# 10. Phase 5 — enforce ad freshness / one-hour cache limit

## Objective

Never intentionally show a cached ad that has exceeded Google's documented cache window.

## New cache wrapper

```dart
class CachedAd<T> {
  const CachedAd({
    required this.ad,
    required this.loadedAt,
  });

  final T ad;
  final DateTime loadedAt;
}
```

Use an injected clock.

## Freshness threshold

Set one internal max age:

```dart
const Duration kAdCacheMaxAge = Duration(minutes: 55);
```

Use 55 minutes rather than exactly 60 to provide margin.

Do not duplicate the threshold across classes.

## Full-screen behavior

Before every `show()`:

1. verify runtime eligibility;
2. verify cached ad exists;
3. verify `now - loadedAt < kAdCacheMaxAge`;
4. if stale:
   - dispose once;
   - clear cache;
   - start at most one eligible replacement load;
   - return unavailable/not-shown.

When app resumes:

- purge stale ready ads before preload.

## Native behavior

For a visible native ad:

- record `loadedAt`;
- do not create a periodic background refresh loop;
- expire on route rebuild, app resume, or a controlled foreground one-shot expiration timer.

If an expiration timer is used:

- cancel on route obscured;
- cancel on app pause;
- cancel on dispose;
- on expiry, destroy old ad first, then allow one new load if eligible.

## Tests

- 54:59 old ad may show;
- 55:00+ old ad is stale and not shown;
- stale ad never produces impression event;
- stale rewarded ad does not create a reward claim;
- resume purges stale cache;
- cache age resets only after a successful new load.

---

# 11. Phase 6 — make ad object ownership single and explicit

## Objective

Eliminate double-dispose and stale-callback races.

## Problem to eliminate

The current native code can hold the same `NativeAd` in `_ad` and `_pendingAd`, allowing route deactivation/dispose/callback paths to destroy the same SDK object multiple times.

## Required ownership abstraction

Use an idempotent lease or equivalent single-owner model:

```dart
class AdLease<T> {
  AdLease(this.ad);

  final T ad;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose(void Function(T ad) disposer) {
    if (_disposed) return;
    _disposed = true;
    disposer(ad);
  }
}
```

The purpose is to make disposal **provably once**.

## Native placement state

Use one active request lease plus explicit state:

```dart
enum NativeAdLoadState {
  idle,
  loading,
  ready,
  failedDormant,
}
```

Conceptual fields:

```dart
AdLease<NativeAd>? _lease;
int _requestGeneration = 0;
DateTime? _loadedAt;
```

Do not keep aliases to the same ad in two fields.

## Load callback

When a native callback arrives:

1. compare request generation;
2. compare lease identity;
3. verify widget mounted;
4. verify current route;
5. verify presentation suppression;
6. verify runtime eligibility;
7. verify app foreground.

If any check fails:

- dispose lease once;
- clear owner only if identity still matches;
- do not retry unless current policy explicitly allows it.

## Route obscuration

On route no longer current:

- invalidate generation;
- cancel retry/expiry timer;
- destroy current lease once;
- reset state to idle;
- do not immediately reload behind the obscuring route.

## Overlay suppression

Keep `runWithNativeAdsSuspended()`.

Verify that:

- depth increments/decrements remain exception-safe;
- nested overlays work;
- Android end-of-frame delay remains only where needed;
- suppression cannot get stuck above zero.

## Tests

- route obscured during load;
- route obscured after load;
- widget disposed during load;
- callback after dispose;
- overlay begins during load;
- nested overlay depth;
- rapid push/pop/push;
- same ad object disposed exactly once;
- failed load object destroyed once.

---

# 12. Phase 7 — rewarded and rewarded-interstitial hardening

## Objective

Keep SSV authoritative and prevent UX/config/cache mismatches.

## Preserve claim-before-show design

Continue to create a server-side reward claim before attaching SSV options.

Do not credit locally.

## Add pre-show freshness and eligibility check

Before creating a reward claim:

1. format is runtime eligible;
2. cached ad exists;
3. cached ad is fresh;
4. no other full-screen ad is showing;
5. format-specific product eligibility allows the attempt.

If any fail, return `unavailable` without creating a claim.

This prevents orphaned pending claims for stale/unshowable ads.

## Full-screen serialization

Add service-level full-screen state:

```dart
enum FullScreenAdState {
  idle,
  showingInterstitial,
  showingRewarded,
  showingRewardedInterstitial,
}
```

Only one full-screen ad may transfer into showing ownership at a time.

A competing show attempt returns unavailable.

## Rewarded interstitial intro requirement

Before `RewardedInterstitialAd.show()` there must be a HomePilot-controlled intro screen that:

- clearly identifies that an ad will appear;
- clearly identifies the reward amount/item;
- provides a visible skip/cancel option;
- appears before the ad;
- does not mimic Google's ad UI.

Audit the existing call site and localization.

If the existing confirmation satisfies this, preserve it and add tests rather than redesigning unnecessarily.

## Reward amount contract

Keep the backend strict mapping for production rewarded units and reward amounts.

Add a contract test that fails when:

- Dart production IDs change without server migration changes;
- DB expected reward amounts diverge from client configuration/documentation.

Do not generate server SQL automatically from client constants; independent validation is intentional defense-in-depth.

## SSV logs

Keep logging only low-risk diagnostics.

Never log raw:

- signature;
- entire callback query;
- `user_id`;
- `custom_data`;
- Google auth/access tokens.

---

# 13. Phase 8 — SSV reverse-DNS feasibility gate

## Objective

Address Google's current defense-in-depth recommendation without creating a fake security control.

## Do not implement blindly

First determine whether Supabase Edge Runtime exposes a **trusted peer/source IP** that cannot be supplied by the client.

### If a trusted source IP exists

Implement forward-confirmed reverse DNS:

1. reverse-resolve source IP;
2. require a Google-controlled hostname per current guidance;
3. forward-resolve that hostname;
4. require original IP among the forward results;
5. treat DNS timeout as retryable infrastructure failure where appropriate;
6. retain cryptographic signature verification as mandatory.

### If no trusted source IP exists

Do **not** trust:

- `X-Forwarded-For`;
- `Forwarded`;
- arbitrary request headers

unless Supabase explicitly documents them as sanitized/trusted for this environment.

Document:

> Reverse DNS is not implemented because the runtime does not expose an authenticated source IP; ECDSA signature verification remains the security boundary.

Add this conclusion to `docs/architecture/monetization.md`.

---

# 14. Phase 9 — remove unused Firebase Analytics and nondeterministic Google Services setup

## Decision

**Remove Firebase Analytics in this remediation.**

Rationale:

- no intentional Firebase Analytics feature was found;
- keeping it adds SDK data collection/disclosure complexity;
- it creates ambiguity around consent mode;
- it makes builds depend on an optional untracked Google Services file;
- AdMob does not require HomePilot to directly depend on Firebase Analytics.

## Files to change

```text
android/app/build.gradle.kts
android/app/google-services.json.example
android/.gitignore and/or root .gitignore
PRIVACY.md
docs/reference/configuration.md
docs/development/getting-started.md
test/prod_build_config_test.dart
test/supabase_android_config_test.dart
```

## Gradle changes

Remove direct dependencies:

```kotlin
implementation(platform("com.google.firebase:firebase-bom:..."))
implementation("com.google.firebase:firebase-analytics")
```

Remove conditional plugin behavior:

```kotlin
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
```

Only remove Google Services references after verifying no other feature depends on them.

## `google-services.json.example`

If its only purpose is unused Firebase integration:

- delete it;
- remove docs that tell developers to copy/create it.

If later review proves another required use:

- keep a sanitized example;
- make behavior deterministic per flavor;
- never use "apply plugin if file happens to exist."

## Ignore rules

Add:

```gitignore
android/app/google-services.json
android/app/src/*/google-services.json
```

## CI proof

Add a Gradle dependency check that fails if `com.google.firebase:firebase-analytics` is unexpectedly reintroduced.

Do **not** fail merely because Google Mobile Ads has its own Google measurement-related transitive implementation.

Target the Firebase Analytics artifact specifically.

## Privacy docs

Do not add a fake Firebase section.

Update documentation to describe the actual shipping SDK set.

## Alternative path — only if owner explicitly requires Firebase Analytics

If retained in a future feature:

1. make Google Services configuration deterministic;
2. default Analytics collection appropriately for consent/legal requirements;
3. implement consent mode;
4. review Advertising ID collection;
5. update privacy policy;
6. create complete Data Safety mapping;
7. add runtime consent tests;
8. add console verification.

---

# 15. Phase 10 — Google Sign-In cleanup, disconnect, and initialization recovery

## Files

```text
lib/src/features/auth/data/native_google_sign_in.dart
lib/src/features/auth/data/supabase_auth_repository.dart
test/supabase_auth_repository_test.dart
new/expanded Google gateway tests
docs/architecture/auth-and-account-deletion.md
PRIVACY.md
```

## 15.1 Extend gateway contract

Change the gateway to include:

```dart
Future<void> disconnect();
```

`disconnect()` must use the current `google_sign_in` API that revokes previous authorization.

## 15.2 Keep normal logout separate

Normal sign-out:

- Supabase local sign-out;
- Google `signOut()`;
- observability cleanup.

Do not revoke authorization on every logout.

## 15.3 Use disconnect on account deletion

After HomePilot cloud deletion is successfully validated:

1. run/attempt local account cleanup;
2. call Google `disconnect()` as best effort;
3. if disconnect fails:
   - log a privacy-safe warning;
   - fall back to `signOut()`;
   - do **not** resurrect or roll back the already-deleted HomePilot account.

Do not disconnect before backend deletion succeeds.

## 15.4 Fix sticky initialization failure

Current `_initialization ??=` caches a failed Future.

Change it so a failed initialization clears the cached future, while a successful initialization stays cached.

Use identity comparison so a late failure cannot clear a newer initialization attempt.

## 15.5 Scope contract

Supabase currently documents the Google access token as required for native `signInWithIdToken`.

Therefore:

- keep authorization only for the minimum required identity scopes;
- do not add Drive, Contacts, Calendar, or other scopes;
- add a code comment explaining why an access token is requested;
- add a test that approved scopes equal the expected minimal set;
- prefer `authorizationForScopes` before interactive `authorizeScopes`;
- interactive authorization must occur only from a user-driven sign-in action.

If a future Supabase version removes the access-token requirement, reevaluate then.

## Tests

- initialize success cached once;
- initialization error may retry on next sign-in;
- normal sign-out calls `signOut`, not `disconnect`;
- successful account deletion calls `disconnect`;
- failed remote deletion does not disconnect;
- disconnect failure falls back safely;
- different Google account during reauth blocks deletion;
- tokens/scopes never appear in logs.


---

# 16. Phase 11 — external Google Play account-deletion web resource

## Objective

Provide a functional web resource where a user can request/delete a HomePilot account without reinstalling the Android app.

Google Play requires this separately from the in-app deletion path.

## Recommended implementation

Use the existing GitHub Pages / `download-site` deployment as the public surface.

Add:

```text
download-site/account-deletion.html
download-site/account-deletion.css
download-site/account-deletion.ts    # or equivalent JS source
tool/build_account_deletion_site.mjs
tool/account-deletion-site.test.mjs
```

Update:

```text
download-site/index.html
tool/build_versiondeck_site.mjs
tool/validate_versiondeck.mjs
.github/workflows/deploy-download-site.yml
package.json
package-lock.json
docs/versiondeck-release-runbook.md
PRIVACY.md
```

## Page requirements

The page must:

- clearly display the HomePilot name;
- explain that it is the HomePilot account deletion page;
- explain what account/cloud data is deleted;
- explain any fraud/security/legal data that may be retained;
- provide a working deletion/request path;
- not require the user to reinstall/open the Android app;
- have a stable public HTTPS URL;
- be mobile accessible;
- support keyboard navigation;
- include privacy/support links;
- avoid analytics and advertising scripts.

## Preferred self-service flow

Use a bundled, pinned Supabase JS client.

Do **not** load an unpinned SDK from a random CDN at runtime.

Build process:

1. add a pinned `@supabase/supabase-js` dependency;
2. bundle deletion page JS with a pinned bundler such as `esbuild`;
3. inject only public browser configuration at build time:
   - Supabase project URL;
   - publishable/anon key;
   - site origin/redirect URL;
4. keep service-role keys entirely server-side.

### User flow

1. user opens `/account-deletion.html`;
2. clicks **Continue with Google**;
3. Supabase Google OAuth authenticates the user;
4. page confirms the signed-in account in a privacy-safe way;
5. user sees destructive confirmation copy;
6. user explicitly confirms;
7. page invokes existing protected `delete-account` Edge Function with the user's bearer session;
8. page validates deletion response;
9. page signs out local browser session;
10. page displays a deletion-complete status without exposing backend identifiers.

## Reauthentication

A newly completed Google OAuth login should satisfy the product's recent-auth intent, subject to the backend's actual enforcement.

Do not weaken or bypass server reauthentication checks.

## CORS

Inspect `supabase/functions/delete-account/index.ts`.

If CORS changes are required:

- allow only known production site origins plus local development origins needed for tests;
- do not treat CORS as authorization;
- continue to require a valid Supabase user bearer token;
- keep explicit deletion confirmation in the request body.

## Public config

The Supabase publishable key is public-client material, not a service-role secret, but deployment still must be deterministic.

Use repository/environment variables such as:

```text
PUBLIC_SUPABASE_URL
PUBLIC_SUPABASE_PUBLISHABLE_KEY
ACCOUNT_DELETION_SITE_URL
```

Production Pages deployment should fail if required public config is absent.

PR builds may use inert test placeholders.

## Link placement

Add a discoverable link to the deletion page from:

- VersionDeck/download-site footer;
- privacy documentation;
- Play Console account-deletion field after deployment.

Do not hide it behind JavaScript-only navigation.

## Security controls

- never expose service-role credentials;
- do not accept a user ID/email from the browser as authorization;
- derive deletion identity only from authenticated Supabase session;
- retain backend same-user checks;
- require explicit confirmation;
- do not log OAuth tokens in browser console;
- clear browser session after success;
- use CSP suitable for the bundled static page;
- avoid third-party trackers.

## Installed-device/local-data note

The web flow controls the server account and associated remote data. The documentation must accurately describe any device-local copies that can remain on an already-installed device until app storage is cleared or the app handles the invalidated session.

Do not promise deletion of device-local files from a web browser if the browser has no technical ability to remove them.

The agent should review whether HomePilot already safely detaches/cleans account-scoped local data after a remotely deleted account invalidates its session. If not, open a clearly scoped follow-up or implement safe cleanup only if the app can distinguish account deletion from ordinary transient auth failure without risking offline data loss.

## Play Console operator task

After deployment:

1. open public URL in private browsing;
2. verify it works without the Android app;
3. complete a test-account deletion;
4. enter exact URL in Play Console's account-deletion/Data Safety field.

The coding agent must not claim this operator step is complete without evidence.

## Tests

- static page identifies HomePilot;
- deletion action requires authenticated session;
- no service-role key in bundle;
- explicit confirmation required;
- function failure gives recoverable UI;
- successful delete signs browser session out;
- page usable without app installation;
- build fails when production public config missing;
- CSP/asset paths work from deployed GitHub Pages path;
- validator confirms account-deletion page exists in deployment artifact.

---

# 17. Phase 12 — Google Play AAB build rail

## Objective

Add a Play-ready AAB path without breaking current APK/VersionDeck distribution.

## Preserve

Keep these working:

```text
.github/workflows/build-production-android.yml
tool/build_prod.ps1
```

Do not silently replace VersionDeck's APK artifact with an AAB.

## Add

Recommended:

```text
.github/workflows/build-play-android.yml
tool/build_play_prod.ps1
docs/operations/google-play-release-runbook.md
```

Optionally add focused build-config tests if existing production tests cannot cover the new path.

## Build script requirements

`build_play_prod.ps1` must enforce the same safety checks as the APK build:

- `APP_ENV=prod`;
- Supabase URL/key present;
- `GOOGLE_WEB_CLIENT_ID` present;
- Sentry production rules;
- release signing configured;
- Flutter analyze;
- Flutter tests;
- production-config tests;
- no `integration_test` plugin leaked into release registrant.

Then run equivalent to:

```text
flutter build appbundle --flavor prod --release --dart-define-from-file=config/prod.json
```

Validate the actual generated path rather than blindly assuming a filename.

Typical location is under:

```text
build/app/outputs/bundle/prodRelease/
```

## Workflow requirements

`build-play-android.yml`:

- `workflow_dispatch` initially;
- only builds from `main`;
- protected `production` or separate `google-play-production` environment;
- `cancel-in-progress: false`;
- Java/Flutter versions pinned consistently with current production workflow;
- signing material restored from protected secrets;
- production config constructed from protected vars;
- AAB built;
- AAB existence checked;
- certificate/signature verified with `jarsigner` or equivalent;
- artifact uploaded to GitHub Actions with retention;
- artifact attestation enabled if compatible;
- merged manifest/dependency reports uploaded;
- **no automatic Play upload during first implementation**.

## Play signing

The AAB build uses the **upload key**.

Do not assume that certificate is the final Play app-signing certificate.

Operator must record both:

- upload certificate SHA-1/SHA-256;
- Play App Signing certificate SHA-1/SHA-256.

Google Sign-In/OAuth configuration may need the Play App Signing certificate for Play-installed builds.

## Automated upload — deferred gate

Only after an operator verifies:

- Play app exists;
- Play App Signing configured;
- service account/API access configured;
- correct track;
- account-deletion URL;
- Data Safety;
- privacy policy;
- AdMob linkage;
- OAuth certificates.

Then a later reviewed change may add internal-track automation.

Do not add broad third-party publishing actions without supply-chain review.

## Target SDK

Current Android config uses `targetSdk = 36` and `compileSdk = 36`.

Preserve both unless a newer required baseline is deliberately adopted.

Add a release assertion that target API does not regress below current Play requirements.

---

# 18. Phase 13 — CI gate SSV, Supabase, and Google contracts

## Objective

Make reward-security and Google-integration regressions release-blocking.

## New workflow

Add:

```text
.github/workflows/validate-google-backend.yml
```

Trigger on PR changes to at least:

```text
lib/src/features/monetization/**
lib/src/features/auth/**
android/**
supabase/functions/admob-ssv-handler/**
supabase/functions/delete-account/**
supabase/migrations/**
supabase/tests/**
package.json
package-lock.json
.github/workflows/**
tool/*google*
tool/*play*
PRIVACY.md
docs/architecture/monetization.md
```

## Job A — Deno SSV tests

- pin/setup Deno;
- use repository lockfile;
- run formatting/type checks if compatible with current project;
- run `supabase/functions/admob-ssv-handler/index_test.ts`.

No live Google callback endpoint is required for unit tests.

## Job B — Supabase database tests

Use Ubuntu/Docker:

1. `npm ci`;
2. verify Docker;
3. start local Supabase;
4. run `npm run supabase:lint`;
5. run `npm run supabase:test`;
6. always stop/cleanup local stack.

Specifically ensure coverage of:

- points monetization;
- SSV hardening;
- replay;
- wallet cap;
- daily rewarded-interstitial rule;
- service-role-only settlement.

## Job C — Google contract/static checks

Create a focused Node or Dart test that validates:

- production rewarded ad ID in Dart equals DB-allowed rewarded ID;
- production rewarded-interstitial ID equals DB-allowed rewarded-interstitial ID;
- expected reward amount mapping matches backend contract;
- demo IDs match project-approved Google sample IDs;
- production AdMob application ID exists in production manifest;
- non-production mapping does not return production ad-unit IDs;
- no raw service-role key in client/download-site;
- no committed `google-services.json`;
- no direct `firebase-analytics` dependency after Phase 9.

## Branch/release gating

Make the workflow a required PR check in branch protection.

Because branch protection is a repository setting, an operator must verify it after merge.

Document exact required check names in the release runbook.

## Production workflow

At minimum, production APK and Play AAB workflows should rerun:

- Flutter tests;
- production config validation;
- fast Google contract tests;
- Deno SSV unit tests.

The heavier local Supabase DB suite may remain a required PR check if the production runner cannot reliably host it, but release policy must require the exact commit to have passed that DB check.

---

# 19. Phase 14 — Android native ad layout / AdChoices cleanup

## Files

```text
lib/src/features/monetization/monetization.dart
lib/src/ui/app_theme.dart
android/app/src/main/kotlin/com/homepilot/app/HomePilotNativeAdFactory.kt
android/app/src/main/res/layout/homepilot_native_ad.xml
android/app/src/main/res/values/colors.xml
android/app/src/main/res/values-night/colors.xml
android/app/src/main/res/drawable/homepilot_native_ad_background.xml
android/app/src/main/res/drawable/homepilot_native_ad_badge.xml
android/app/src/main/res/drawable/homepilot_native_ad_cta.xml
test/monetization_test.dart
```

## Mandatory native-ad theme parity across every screen

### User-visible defect to eliminate

A native ad must never render as a dark-theme card while the surrounding HomePilot screen is light, and it must never render as a light-theme card while HomePilot is dark.

The supplied screenshot demonstrates the exact failure mode this phase must prevent: the Dashboard is visibly using HomePilot's light theme while the native ad card is rendered with the dark native-ad palette.

This is a **global native-ad requirement**, not a Dashboard-only patch. It applies to every current and future `HkNativeAdCard` placement on every route.

### Repository root cause confirmed from current GitHub source

The current repository already contains separate Android ad palettes:

- `android/app/src/main/res/values/colors.xml` contains light native-ad colors.
- `android/app/src/main/res/values-night/colors.xml` contains dark native-ad colors.

The current factory inflates `homepilot_native_ad.xml` from the Android `Context`, and the layout/drawables reference `@color/homepilot_ad_*`. Android therefore chooses the palette using `uiMode` / `values-night`.

The current Flutter `HkNativeAdCard` creates `NativeAd(...)` without passing HomePilot's resolved theme through `customOptions`.

HomePilot's app theme is controlled in Flutter by `HomePilotTheme.light()` / `HomePilotTheme.dark()` and can differ from the Android system theme. Therefore this mismatch is possible:

```text
Android system = dark
HomePilot app   = light
native ad       = dark   <-- incorrect
```

The active native-ad theme must be selected from Flutter's resolved app theme, **not** Android system resource qualifiers.

### Hard invariant

For every visible native ad:

```text
nativeAdVisualBrightness == Theme.of(context).brightness
```

This must remain true when:

- HomePilot is explicitly Light while Android/system is Dark;
- HomePilot is explicitly Dark while Android/system is Light;
- HomePilot follows its time-of-day theme behavior;
- the user changes HomePilot theme while an ad is loading;
- the user changes HomePilot theme while an ad is visible;
- the app resumes after a system-theme change;
- navigation moves among screens containing native ads;
- the ad reloads because of route lifecycle, age, consent, or retry policy.

### Use `NativeAd.customOptions` for local presentation state

The Google Mobile Ads Flutter `NativeAd` API supports `customOptions`, and the existing Android factory already receives `customOptions` in `createNativeAd(...)`.

Use this bridge only for local native-view presentation.

Do **not**:

- create separate light/dark ad units;
- put theme state into `AdRequest` targeting;
- put user/domain data in theme options.

### Flutter side — one schema-versioned theme contract

Define shared constants rather than repeated string literals:

```dart
const _nativeAdThemeSchema = 1;
const _nativeAdThemeSchemaKey = 'homepilotThemeSchema';
const _nativeAdBrightnessKey = 'homepilotBrightness';

String _nativeAdBrightnessValue(Brightness brightness) =>
    brightness == Brightness.dark ? 'dark' : 'light';
```

Every native ad created by the shared HomePilot component must pass:

```dart
final brightness = Theme.of(context).brightness;

final ad = NativeAd(
  adUnitId: ads.units.native(widget.placement),
  factoryId: _nativeFactoryId,
  customOptions: <String, Object>{
    _nativeAdThemeSchemaKey: _nativeAdThemeSchema,
    _nativeAdBrightnessKey: _nativeAdBrightnessValue(brightness),
  },
  request: const AdRequest(),
  listener: ...,
);
```

Never put these into the theme options:

- user ID/account ID/email;
- task/room/item content;
- location;
- consent strings;
- Advertising ID;
- SSV data;
- reward claims;
- arbitrary analytics payloads.

### One shared implementation for all screens

Theme propagation must live inside `HkNativeAdCard` or the shared native-ad loader produced by the monetization refactor.

Do not add placement-specific styling such as:

```dart
if (placement == 'home') useLightTheme();
```

Every native placement must inherit the local Flutter theme automatically.

Add a static test/review rule preventing new direct `NativeAd(...)` construction outside the approved monetization native-ad component unless explicitly reviewed. This prevents a future screen from bypassing theme, consent, ownership, retry, or freshness controls.

### Android factory — explicit app-selected palette

`HomePilotNativeAdFactory.createNativeAd()` must read and validate:

```text
homepilotThemeSchema
homepilotBrightness
```

Accepted brightness values:

```text
light
dark
```

Recommended fallback order for an old/malformed caller:

1. valid explicit Flutter option;
2. Android `Configuration.UI_MODE_NIGHT_*` as a compatibility fallback;
3. light as the final deterministic fallback.

Missing/malformed options must not crash ad rendering.

A debug/test warning may record fallback, but it must not log ad IDs, response IDs, creative data, or user data.

### Stop using implicit `values-night` names as the active selector

The current names:

```text
homepilot_ad_surface
homepilot_ad_border
homepilot_ad_primary
homepilot_ad_text_primary
homepilot_ad_text_secondary
```

implicitly switch because the same names exist in both `values/` and `values-night/`.

Replace or supplement them with explicit resource names:

```text
homepilot_ad_light_surface
homepilot_ad_light_border
homepilot_ad_light_primary
homepilot_ad_light_text_primary
homepilot_ad_light_text_secondary

homepilot_ad_dark_surface
homepilot_ad_dark_border
homepilot_ad_dark_primary
homepilot_ad_dark_text_primary
homepilot_ad_dark_text_secondary
```

At implementation time, compare them to the current canonical Flutter theme in `lib/src/ui/app_theme.dart`.

Relevant Flutter design sources include:

```text
ThemeData.cardTheme.color
ColorScheme.primary
ColorScheme.onSurface
ColorScheme.onSurfaceVariant
ColorScheme.outlineVariant
```

Do not copy stale hex values from this plan.

### Switch the complete app-owned native-ad chrome

The selected Flutter brightness controls:

- outer card surface;
- outer border;
- **Ad** badge border/text;
- **Sponsored** label;
- advertiser text;
- headline text;
- body text;
- CTA border/text;
- HomePilot-owned focus/ripple tint.

Do not recolor advertiser-provided icons or media.

### Preferred drawable strategy

The current background/badge/CTA shapes reference implicit theme colors.

Preferred replacement:

```text
homepilot_native_ad_background_light.xml
homepilot_native_ad_background_dark.xml
homepilot_native_ad_badge_light.xml
homepilot_native_ad_badge_dark.xml
homepilot_native_ad_cta_light.xml
homepilot_native_ad_cta_dark.xml
```

`HomePilotNativeAdFactory` selects one complete set using the Flutter brightness option and applies matching text colors before `setNativeAd(nativeAd)`.

A programmatic `GradientDrawable` approach is acceptable only if it preserves existing radii, borders, padding, touch behavior, accessibility, and tests.

### Do not theme Google-owned creative content

HomePilot may style its native-ad container and registered text/CTA assets within Google's native-ad rules.

Do not:

- color-filter advertiser logos/icons;
- recolor media;
- hide/camouflage **Ad** attribution;
- obscure AdChoices;
- make the ad indistinguishable from ordinary HomePilot task/card content.

The ad should belong visually to HomePilot's theme while remaining clearly identifiable as advertising.

### Runtime theme change while a native ad is visible

A platform view created under the old app theme must not remain visible after Flutter switches brightness.

Track the brightness that owns the active native request/view, e.g.:

```dart
Brightness? _requestedBrightness;
```

In `didChangeDependencies()` or the refactored equivalent:

1. read `Theme.of(context).brightness`;
2. compare it with the active request/view brightness;
3. if unchanged, do nothing;
4. if changed:
   - invalidate the request generation from the native ownership phase;
   - cancel retry/expiry timers tied to the old visual state;
   - dispose the old lease exactly once;
   - clear the old platform view;
   - immediately show `HkNativeAdLoadingSkeleton`, which already uses Flutter `ColorScheme`;
   - allow at most one replacement load in the new brightness if normal runtime eligibility permits it.

A theme change must never:

- bypass UMP;
- bypass foreground gating;
- bypass remote native-ad disable;
- bypass retry/circuit limits;
- create concurrent native requests;
- trigger a request for every frame of HomePilot's animated theme transition.

React only to discrete `Brightness.light` / `Brightness.dark`.

### Theme change while a request is in flight

Requested brightness becomes part of request identity.

If a Light request completes after HomePilot changed to Dark:

```text
callback brightness != current Flutter brightness
=> dispose returned ad exactly once
=> never mount/cache it
=> do not count it as ready
=> allow at most one eligible Dark replacement load
```

Apply the same rule Dark -> Light.

Reuse the same generation/lease mechanism used for route, consent, lifecycle, and stale-callback handling. Do not create a second race-control system only for theme.

### System theme vs HomePilot theme precedence

Automate and manually verify:

| Android/system | HomePilot app | Native ad must render |
|---|---|---|
| Light | Light | Light |
| Dark | Dark | Dark |
| Dark | Light | **Light** |
| Light | Dark | **Dark** |

HomePilot app theme always wins.

If the product preference itself follows system/time-of-day behavior, Flutter resolves that first; the native ad follows final `Theme.of(context).brightness`.

### Loading/failure behavior

`HkNativeAdLoadingSkeleton` is already Flutter-theme aware.

Correct transition:

```text
theme changes
-> old/wrong native platform view removed
-> correctly themed Flutter skeleton
-> correctly themed replacement native ad
```

Never retain a wrong-theme ad just to avoid a short reload.

If replacement cannot load, use normal collapsed/failure behavior; do not restore the old wrong-theme view.

### Request-volume constraint

A discrete user theme change may cause one replacement native-ad request.

It must not reset the native retry circuit or create request amplification.

Acceptance:

```text
one Light -> Dark transition
=> at most one replacement request per visible eligible native placement
```

The same applies Dark -> Light.

### Accessibility and contrast

Verify both themes:

- headline/body contrast;
- sponsored/advertiser readability;
- CTA outline/text visibility;
- **Ad** attribution visibility;
- focus visibility for accessibility navigation.

Do not reduce attribution contrast simply to make the ad blend into the page.

### Automated theme-parity tests

Add tests for:

1. Light app + Light system -> `light`;
2. Dark app + Dark system -> `dark`;
3. Light app + Dark system -> **light**;
4. Dark app + Light system -> **dark**;
5. every known native placement uses the shared themed construction path;
6. Light -> Dark while ready disposes once and produces at most one eligible replacement request;
7. Dark -> Light behaves symmetrically;
8. theme change during in-flight load rejects/disposes stale-theme callback;
9. theme change while route is obscured does not load behind the route;
10. theme change while UMP blocks ads creates zero requests;
11. theme change while app is backgrounded creates zero requests;
12. theme change while native ads are remotely disabled creates zero requests;
13. the Flutter loading skeleton adopts the new theme immediately;
14. malformed/missing Android theme options use the documented fallback;
15. Android factory switches background, border, badge, text, and CTA as one atomic palette.

### Visual/device acceptance

Verify every native-ad route in all four system/app combinations.

At minimum capture:

```text
Dashboard/Home — HomePilot Light
Dashboard/Home — HomePilot Dark
one secondary native-ad screen — HomePilot Light
one secondary native-ad screen — HomePilot Dark
```

While the slot is visible, switch HomePilot Light <-> Dark.

Pass only if:

- no dark-ad/light-app mismatch;
- no light-ad/dark-app mismatch;
- no old-theme platform view reappears after replacement begins;
- no duplicate ad is stacked in the slot;
- no double impression from reattaching the same `NativeAd`;
- AdChoices remains visible;
- **Ad/Sponsored** attribution remains visible;
- RTL/LTR remain correct.

### Future-proof rule

Any future HomePilot native-ad layout, screen, or factory must consume this same app-theme contract.

Code review should reject native-ad rendering whose active theme is determined only by Android system resource qualifiers.

## AdChoices

The baseline XML includes an explicit `AdChoicesView`, but the factory does not register/customize it.

Recommended change:

- remove the dead explicit `AdChoicesView`;
- reserve unobstructed top-corner space for Google's SDK-managed AdChoices overlay;
- keep clear **Ad** / **Sponsored** attribution;
- do not draw app UI over the overlay;
- do not make unsupported styling hacks to AdChoices.

If the pinned plugin/version provides a supported documented way to explicitly register a custom AdChoices view and there is a real product requirement, use that instead. Otherwise prefer SDK ownership.

## Native asset rules

Preserve:

- headline registration;
- body registration when present;
- advertiser registration when present;
- icon registration when present;
- CTA registration;
- `setNativeAd(nativeAd)` after asset population.

For optional assets:

- hide views when data absent;
- do not display stale text/images from recycled views.

## Touch safety

Ensure:

- ad frame does not overlap floating buttons;
- CTA has reasonable spacing from app navigation;
- skeleton does not accept fake ad clicks;
- loading skeleton is not logged as an impression;
- no transparent overlay captures clicks above the ad.

## Verification

Real device + Native Ad Validator is mandatory before release.

---

# 20. Phase 15 — native placement/ad-unit diagnostics

## Objective

Improve diagnostics without inventing new production IDs.

## Code change

Change `HomePilotAdUnits.native(String placement)` from an implicit:

```text
home -> home unit
everything else -> shared unit
```

to an explicit switch/map of known placements.

Example concept:

```dart
switch (placement) {
  case 'home':
    return ...;
  case 'today':
  case 'insights':
    return sharedSecondaryUntilConsoleProvisioned;
  default:
    throw StateError('Unknown native ad placement: $placement');
}
```

For non-production, continue using Google's demo native unit.

This prevents silent placement typos.

## Console-dependent follow-up

If AdMob operator creates dedicated units for high-volume placements:

1. add exact IDs through reviewed code/config;
2. update tests;
3. verify each unit belongs to the correct AdMob app;
4. update operational docs.

Do not invent or auto-create IDs.

Low-volume placements may intentionally share a unit.

---

# 21. Phase 16 — merged manifest and dependency evidence

## Objective

Know what the shipping binary actually declares.

## Add release diagnostics

For prod release variant generate/archive:

- merged Android manifest;
- dependency report;
- application ID;
- target SDK;
- version code/name;
- signing certificate digest;
- AdMob application ID metadata;
- relevant SDK-added permissions.

Use Gradle tasks appropriate to the pinned Android Gradle Plugin.

## Automated assertions

Assert:

- package/application ID is `com.homepilot.app`;
- target SDK is expected;
- production AdMob application ID metadata exists exactly once;
- no debug/test application ID is present;
- Android backup setting remains intended;
- unexpected Google/Firebase components cause review.

Advertising ID permission may be contributed by Google Mobile Ads.

Do not remove it blindly if the SDK legitimately requires it. Reconcile the final merged manifest with Play declarations instead.

## Artifact

Upload diagnostics from both APK and AAB production workflows.

---

# 22. Phase 17 — privacy policy, Data Safety evidence, and documentation

## Update `PRIVACY.md`

Required changes:

- update review date;
- confirm Google Mobile Ads wording matches actual SDK behavior;
- document Google Sign-In disconnect/account-deletion behavior;
- reference external account-deletion page;
- clarify server-side rewarded verification;
- if Firebase Analytics was removed, do not claim it is used;
- explicitly state any retained anti-fraud reward transaction data after account deletion and why;
- keep wording consistent with actual Supabase deletion behavior.

## Add Data Safety evidence doc

Create:

```text
docs/operations/google-play-data-safety-evidence.md
```

This is engineering evidence, not legal advice.

For each category record:

```text
Data category
Collected?
Shared?
Purpose
Required/optional
Encrypted in transit
Deletion behavior
Source code evidence
Third-party SDK
Console verification needed
```

At minimum review:

- account/user identifiers;
- email/profile information from Google Sign-In;
- approximate location;
- app activity;
- ad interactions;
- device/advertising identifiers;
- diagnostics;
- reward/fraud-prevention metadata;
- Supabase data;
- Sentry data.

Do not guess Google SDK Data Safety declarations. Use current Google-provided SDK disclosure documentation during release review.

## Update architecture docs

`docs/architecture/monetization.md` should describe:

- runtime eligibility state machine;
- consent lifecycle;
- format kill switches;
- retry policy;
- cache TTL;
- lifecycle gate;
- native ownership;
- full-screen serialization;
- SSV trust chain.

`docs/architecture/auth-and-account-deletion.md` should describe:

- normal sign-out vs disconnect;
- in-app account deletion;
- external web deletion;
- backend cleanup;
- Google authorization revoke behavior.

## Fix `docs/request-audit-report.md`

Do not delete historical measurement data.

Add a prominent header such as:

```text
Historical point-in-time audit — Build 26.
Not a current architectural compliance guarantee.
```

Fix inaccurate wording:

- remove `zero runaway loops`;
- replace `HMAC ECDSA` with `ECDSA P-256/SHA-256`;
- distinguish observed traffic during one test window from architectural guarantees;
- link to current monetization architecture doc.

---

# 23. Phase 18 — `.gitignore` and config hygiene

## Add explicit ignores

At repository/Android scope include as applicable:

```gitignore
android/app/google-services.json
android/app/src/*/google-services.json
android/app/*.jks
android/app/*.keystore
android/key.properties
config/prod.json
```

Do not accidentally ignore sanitized examples intentionally committed.

## Scan

Add/retain secret scanning tests for:

- service-role keys;
- Google OAuth client secrets;
- keystore passwords;
- private keys;
- Sentry auth token;
- production config files.

Remember:

- OAuth client IDs are identifiers, not private client secrets;
- Supabase publishable/anon key is public-client material, not service role;
- deployment values should still be managed consistently.


---

# 24. Phase 19 — complete automated test matrix

This section is mandatory. The implementation is not done when unit tests alone pass.

## 24.1 Consent

| Case | Expected result |
|---|---|
| first launch, UMP update pending | zero ad requests |
| update says `canRequestAds=false` | zero ad requests |
| update says true | only enabled formats may load |
| UMP update errors but previous session permits | follow current `canRequestAds()` result, no guessing |
| privacy options true -> false | cancel retries, purge ready ads, invalidate in-flight |
| privacy options false -> true | one controlled preload pass |
| rapid privacy-options opening | no duplicate loads |
| widget rebuild during UMP flow | no request duplication |
| consent state unchanged | no generation churn or duplicate work |

## 24.2 Lifecycle

| Case | Expected result |
|---|---|
| pause before load | no load |
| pause during load | callback stale; returned ad disposed |
| pause during retry timer | retry cancelled |
| resume eligible | one preload pass |
| resume with consent blocked | zero preload |
| full-screen ad causes inactive state | showing ad not double-disposed |
| dismissal while backgrounded | no replacement load |
| resume after dismissal | replacement may load once if eligible |
| detach/dispose | all timers cancelled; no new work |

## 24.3 Retry

| Failure class | Expected result |
|---|---|
| invalid request | no automatic retry |
| no fill | no tight timer loop |
| network | bounded retry with jitter |
| internal | conservative bounded retry |
| unknown | conservative bounded retry |
| max attempts reached | circuit dormant |
| success | failure state reset |
| eligibility epoch changes | old timers/callbacks ignored |

Add tests that advance a fake clock/scheduler; do not use long real sleeps.

## 24.4 Cache age

| Age/state | Expected result |
|---|---|
| newly loaded | usable |
| 54m59s | usable |
| >=55m | stale, dispose, no show |
| background beyond max age | purge on resume |
| stale rewarded | no reward claim created |
| stale rewarded interstitial | no claim, no intro-to-show transition |
| stale interstitial | no impression/show |
| stale native | destroy and reload only if visible/eligible |

## 24.5 Native

Test all of:

- load then route obscured;
- route obscured during load;
- overlay during load;
- overlay after load;
- nested overlays;
- widget disposed during load;
- callback after dispose;
- failure retry capped;
- same lease disposed once;
- current route restored triggers at most one new load;
- disabled config destroys ready native ad;
- consent revocation destroys ready native ad;
- app pause destroys or suspends according to chosen policy;
- stale TTL replacement;
- loading skeleton has no ad semantics/impression event;
- app Light + system Light -> light native palette;
- app Dark + system Dark -> dark native palette;
- app Light + system Dark -> **light native palette**;
- app Dark + system Light -> **dark native palette**;
- Light -> Dark while ready disposes/replaces exactly once;
- Dark -> Light while ready disposes/replaces exactly once;
- theme switch while request is in flight rejects stale-theme callback;
- animated Flutter theme transition does not create repeated loads;
- theme switch while consent/config/lifecycle blocks ads produces zero requests;
- every current placement goes through the shared theme-option path;
- background/border/badge/text/CTA change as one palette;
- loading skeleton changes to the new Flutter theme immediately;
- ad attribution remains present in native layout tests where inspectable;
- AdChoices area remains unobstructed;
- Arabic RTL in Light and Dark;
- text scaling in Light and Dark;
- small-screen layout in Light and Dark.

## 24.6 Interstitial

Test:

- first-ever session suppression;
- session cap;
- cooldown;
- rapid completion;
- keyboard visible;
- modal active;
- global config disabled;
- interstitial config disabled;
- full-screen mutex occupied;
- stale ad;
- app background;
- show failure;
- dismissal;
- post-dismiss replacement eligibility;
- no duplicate show from rapid completion callbacks.

## 24.7 Rewarded

Test:

- repository null;
- no cached ad;
- stale cached ad;
- claim creation failure;
- SSV options set before show;
- user dismisses without earning;
- user earns client callback but server still pending;
- failed-to-show;
- no local wallet mutation;
- full-screen mutex;
- config disabled during ready state;
- consent revoked during ready state;
- app paused before show.

## 24.8 Rewarded interstitial

Everything in rewarded tests plus:

- intro screen shown before ad;
- reward amount/item explicit;
- skip option visible;
- skip creates no claim and no ad show;
- daily reward rule messaging;
- exact production ID/reward amount contract.

## 24.9 Google Sign-In

Test:

- initialize success;
- initialize called once after success;
- transient initialize failure then retry succeeds;
- canceled authentication;
- client configuration error;
- provider configuration error;
- expected minimal scope set;
- access token missing/error path if possible;
- ID token missing;
- normal sign-out;
- account deletion disconnect;
- wrong-account reauthentication;
- disconnect failure fallback;
- no token material in structured logs.

## 24.10 External deletion page

Test:

- public page builds;
- page identifies HomePilot;
- sign-in required for destructive action;
- explicit confirmation required;
- delete function success;
- delete function error;
- stale/expired browser session;
- browser sign-out on success;
- no service-role key in bundle;
- no tracking scripts;
- no dependency on installed Android app;
- keyboard navigation;
- responsive mobile layout;
- deployment validator finds the page and assets.

## 24.11 SSV

Keep and expand tests for:

- valid signature;
- invalid signature;
- reordered/tampered fields;
- unknown key -> one forced key refresh;
- key cache expiry below 24h;
- key server failure;
- malformed callback;
- duplicate callback;
- same transaction with changed claim -> rejected;
- expired timestamp;
- future timestamp;
- wrong ad unit;
- wrong reward amount;
- wrong reward item;
- wrong user/claim binding;
- expired claim;
- wallet cap;
- daily rewarded-interstitial rule;
- concurrent duplicate first deliveries;
- service-role-only RPC invocation.

## 24.12 Release

Automate/verify:

- APK production build still works;
- AAB production build works;
- production config validation;
- target SDK assertion;
- signing config present;
- merged manifest generated;
- dependency graph generated;
- no committed Google Services JSON;
- no direct Firebase Analytics dependency;
- no integration-test plugin in release;
- correct version code/name;
- AAB signature verification;
- artifact metadata points to exact source commit.

---

# 25. Phase 20 — observability without PII or request amplification

## Recommended event vocabulary

Use low-cardinality events such as:

```text
ad_runtime_eligibility_changed
ad_load_requested
ad_load_succeeded
ad_load_failed
ad_retry_scheduled
ad_retry_circuit_open
ad_cache_expired
ad_show_started
ad_show_failed
ad_show_dismissed
ad_reward_earned_client
ad_reward_server_pending
ad_native_impression
ad_native_click
```

## Allowed fields

Examples:

- `ad_type`;
- `placement`;
- sanitized SDK error code/domain;
- failure attempt number;
- eligibility reason enum;
- cache age bucket;
- verification status enum.

## Do not log

- Google OAuth access token;
- Google ID token;
- SSV signature;
- full SSV query;
- raw reward claim UUID unless strictly required;
- raw Google transaction ID;
- user email/name;
- precise device identifier;
- Advertising ID.

If correlation is operationally necessary, use an existing approved one-way hash/short fingerprint.

## Rate-limit logging

A failing ad SDK must not generate an unbounded stream of warning events.

When retry circuit opens, emit one state event rather than one warning every minute forever.

---

# 26. Phase 21 — real-device validation protocol

Use only Google demo ads or explicitly registered test devices.

## Device matrix

At minimum:

- Android API 36 current emulator/device;
- Android version near HomePilot minimum supported API;
- physical device with Google Play Services;
- Arabic RTL;
- English LTR;
- light mode;
- dark mode;
- small screen;
- large screen/tablet if supported.

## Native-ad app-theme parity cases

Test the full mismatch matrix, not only the case where app theme follows system theme:

```text
Android Light + HomePilot Light -> native Light
Android Dark  + HomePilot Dark  -> native Dark
Android Dark  + HomePilot Light -> native Light
Android Light + HomePilot Dark  -> native Dark
```

Repeat on every native-ad route available in the current build.

While a native ad is visible, switch HomePilot Light <-> Dark and verify:

- old platform ad view is removed;
- correctly themed Flutter skeleton appears immediately;
- at most one correctly themed replacement request starts;
- no stale old-theme callback mounts;
- AdChoices and ad attribution remain visible.

## Consent cases

Validate:

- first install in a UMP test geography;
- consent required;
- consent not required;
- consent-form error/offline;
- privacy options revisit;
- changing privacy choice;
- app restart after choice;
- background/resume during consent flow.

## Navigation/native cases

Use Native Ad Validator.

Exercise:

- rapid tab changes;
- modal open/close;
- bottom sheet;
- system permission dialog;
- app background/resume;
- back gesture;
- repeated route push/pop;
- long-lived screen beyond cache TTL if practical.

Watch for:

- accidental clicks;
- PlatformView touch leak;
- blank retained view;
- duplicate impression;
- crash;
- double-dispose warning;
- obscured AdChoices;
- broken attribution.

## Full-screen cases

- natural task-completion transition;
- first-session suppression;
- cooldown;
- session cap;
- keyboard/modal guard;
- app pause immediately before expected show;
- full-screen ad followed by background;
- rapid repeated task completion;
- stale cached ad after controlled time manipulation if possible.

## Rewarded cases

- rewarded ad;
- rewarded interstitial;
- cancel/skip;
- complete;
- SSV callback;
- wallet credit only after backend;
- network interruption before ad;
- network interruption after ad;
- duplicate SSV delivery if test tooling permits.

## Google authentication

Using release-signed/internal-track build:

- sign in;
- sign out;
- sign in again;
- delete account;
- verify disconnect/revocation behavior;
- wrong Google account reauth;
- reinstall/sign-in after deletion as appropriate.

---

# 27. Phase 22 — AdMob console verification

The coding agent cannot complete these without console access. Record each as `verified`, `failed`, or `blocked`.

## AdMob app

Verify:

- production package belongs to intended AdMob app;
- app review status;
- store linkage;
- Policy Center status.

## Units

Verify exact production unit IDs for:

- native home;
- native secondary/current shared placements;
- interstitial;
- rewarded;
- rewarded interstitial.

For reward units verify:

- reward item;
- reward amount;
- SSV callback URL.

These must match backend strict validation.

## UMP / Privacy & Messaging

Verify:

- intended messages published;
- geographies/configuration;
- privacy-options entry point behavior;
- app ID mapping;
- consent mode only if a product feature actually needs it.

## Test devices

Verify developer physical devices are registered if live unit IDs are ever loaded during controlled diagnostics.

Prefer demo IDs for non-production builds.

## Invalid traffic

Review:

- Policy Center;
- ad serving limits;
- request/impression anomalies;
- suspicious CTR after rollout.

---

# 28. Phase 23 — Google Cloud / OAuth verification

Operator must verify:

- correct Web OAuth client ID used as `GOOGLE_WEB_CLIENT_ID`;
- Android OAuth client for `com.homepilot.app`;
- SHA-1/SHA-256 for upload/release certificate as applicable;
- SHA-1/SHA-256 for **Play App Signing** certificate;
- Supabase Google provider configuration;
- external deletion page redirect URI if using Google OAuth through Supabase;
- no obsolete OAuth client used by production.

Do not put OAuth client secrets in Flutter or browser bundles.

---

# 29. Phase 24 — Play Console verification

## App integrity

- [ ] Play App Signing enabled/configured.
- [ ] Upload key correct.
- [ ] AAB accepted.
- [ ] App/bundle certificate values recorded.

## App content

- [ ] Privacy policy URL current.
- [ ] External account-deletion URL current.
- [ ] Data Safety answers updated.
- [ ] Target audience reviewed.
- [ ] Families applicability reviewed.
- [ ] Ads declaration correct.
- [ ] Advertising ID declaration consistent with final binary/SDK behavior.

## SDK/release

- [ ] No unresolved Play SDK warnings.
- [ ] Pre-launch report reviewed.
- [ ] Target API accepted.
- [ ] Internal/closed-track install succeeds.
- [ ] Google Sign-In works on Play-signed install.

## Account deletion

Public deletion resource must:

- load without requiring the Android app;
- identify HomePilot;
- make the deletion/request action readily discoverable;
- accurately explain retained data;
- not tell the user to reinstall the app to submit deletion.

---

# 30. Phase 25 — rollout strategy

Do not ship all behavioral changes directly to 100% production if Play staged rollout is available.

## Recommended order

1. Merge code behind existing monetization remote flags.
2. Deploy backend-safe changes/tests.
3. Deploy account deletion page.
4. Verify AdMob/Google/Play console configuration.
5. Build AAB.
6. Internal testing.
7. Closed testing.
8. Small staged production percentage.
9. Observe:
   - crash/ANR;
   - ad request volume;
   - fill rate;
   - invalid-traffic warnings;
   - rewarded callback failures;
   - SSV duplicate/rejection rate;
   - consent-form failures;
   - auth failures.
10. Expand rollout only when stable.

## Remote emergency rollback

Ensure production monetization config can disable:

- all ads;
- native;
- interstitial;
- rewarded;
- rewarded interstitial.

After this remediation those switches must stop **request traffic**, not just hide UI.

---

# 31. Suggested implementation commit sequence

Use approximately this order.

## Commit 1

`test(monetization): lock current Google ad and SSV invariants`

Baseline tests only; no behavior change.

## Commit 2

`refactor(ads): introduce runtime eligibility and consent controller`

Consent separation and pure bootstrap.

## Commit 3

`fix(ads): gate requests by lifecycle consent and remote config`

Lifecycle, format kill switches, generation invalidation.

## Commit 4

`fix(ads): bound retries and enforce cache freshness`

Retry policy, circuit breaker, 55-minute TTL.

## Commit 5

`fix(native-ads): enforce single ownership and stale callback disposal`

Lease and route/overlay lifecycle.

## Commit 6

`fix(rewarded): serialize full-screen ads and protect claim timing`

Full-screen mutex, pre-claim freshness, intro/skip tests.

## Commit 7

`chore(android): remove unused Firebase Analytics integration`

Gradle, Google Services example, ignores/docs.

## Commit 8

`fix(auth): revoke Google authorization on account deletion`

Disconnect, init retry, auth tests.

## Commit 9

`feat(account): add external web account deletion flow`

Pages, web auth, protected delete invocation, tests.

## Commit 10

`ci(google): gate SSV database and monetization contracts`

Deno, Supabase, static contracts.

## Commit 11

`feat(release): add protected Google Play AAB build`

Play build script/workflow, diagnostics.

## Commit 12

`fix(native-ads): follow HomePilot theme and simplify AdChoices ownership`

- pass Flutter Light/Dark brightness through shared native-ad `customOptions`;
- make Android factory use HomePilot's selected app palette instead of implicit system `values-night`;
- invalidate/reload visible or in-flight old-theme native views exactly once;
- Android layout/factory cleanup;
- AdChoices cleanup;
- explicit placements;
- app-theme/system-theme mismatch tests.

## Commit 13

`docs(play): align privacy data safety and release runbooks`

Privacy, architecture, historical audit disclaimer, checklists.

Split further if a commit becomes hard to review. Do not combine more aggressively.

---

# 32. File-by-file implementation checklist

## `lib/src/features/monetization/monetization.dart`

- [ ] remove preload side effect from `build`;
- [ ] move UMP->ads initialization coupling into runtime controller;
- [ ] add central eligibility model;
- [ ] add lifecycle input;
- [ ] add format-specific load gates;
- [ ] add runtime generation;
- [ ] replace infinite retry timers;
- [ ] add cache timestamps;
- [ ] add show freshness guards;
- [ ] add full-screen mutex;
- [ ] fix native ownership;
- [ ] preserve interstitial policy;
- [ ] preserve SSV claim flow;
- [ ] preserve demo IDs.

After behavior stabilizes, split into focused files.

## `lib/src/features/auth/data/native_google_sign_in.dart`

- [ ] add `disconnect`;
- [ ] clear cached init future on failure;
- [ ] document required access-token scopes;
- [ ] do not add broader scopes.

## `lib/src/features/auth/data/supabase_auth_repository.dart`

- [ ] normal logout -> `signOut`;
- [ ] successful account deletion -> `disconnect`;
- [ ] disconnect failure must not undo deletion;
- [ ] retain same-account reauth.

## `android/app/build.gradle.kts`

- [ ] remove Firebase Analytics direct dependency;
- [ ] remove conditional Google Services plugin;
- [ ] keep API 36;
- [ ] keep signing protections;
- [ ] keep flavor separation.

## `android/app/src/main/AndroidManifest.xml`

- [ ] preserve production AdMob app ID;
- [ ] do not add Firebase Analytics collection metadata after removal;
- [ ] inspect final merged permissions in CI.

## `HomePilotNativeAdFactory.kt`

- [ ] read schema-versioned Flutter brightness from `customOptions`;
- [ ] accept only `light` / `dark` plus a documented safe fallback;
- [ ] choose HomePilot's app-selected palette explicitly instead of relying on `values-night`;
- [ ] apply surface, border, badge, text, and CTA styling as one palette;
- [ ] preserve supported NativeAd asset registration;
- [ ] remove dead custom AdChoices assumptions;
- [ ] verify optional assets hide cleanly.

## `homepilot_native_ad.xml`

- [ ] retain visible ad attribution;
- [ ] remove implicit dependence on Android system dark-mode for active styling;
- [ ] remove unregistered custom `AdChoicesView` unless supported/registered;
- [ ] reserve overlay space;
- [ ] verify RTL/theme/text scaling in both app themes.

## `lib/src/features/monetization/monetization.dart` native path

- [ ] derive active native brightness from `Theme.of(context).brightness`;
- [ ] pass it through `NativeAd.customOptions` for every placement;
- [ ] do not place theme state in ad targeting/request extras;
- [ ] track brightness as part of native request/view identity;
- [ ] dispose an old-theme lease exactly once;
- [ ] reject stale old-theme in-flight callbacks;
- [ ] show the Flutter-themed skeleton during replacement;
- [ ] create at most one replacement request per discrete brightness change;
- [ ] never let a theme change bypass consent, lifecycle, remote config, freshness, or retry circuits.

## `.gitignore`

- [ ] ignore real Google Services config;
- [ ] verify signing/config files ignored.

## `test/monetization_test.dart`

- [ ] runtime gating;
- [ ] retry;
- [ ] freshness;
- [ ] lifecycle;
- [ ] config;
- [ ] full-screen mutex;
- [ ] native ownership;
- [ ] reward claim timing.

## SSV tests

- [ ] run in CI;
- [ ] expand if missing replay/concurrency/error cases.

## `.github/workflows/validate-flutter.yml`

- [ ] preserve current Flutter validation;
- [ ] optionally invoke fast Google contract checks.

## new `validate-google-backend.yml`

- [ ] Deno tests;
- [ ] Supabase DB tests;
- [ ] static contracts.

## `tool/build_prod.ps1`

- [ ] preserve APK path and VersionDeck semantics;
- [ ] share safe helpers only if refactor remains low-risk.

## new `tool/build_play_prod.ps1`

- [ ] AAB build;
- [ ] same production guards;
- [ ] release diagnostics.

## `download-site/**`

- [ ] account-deletion page;
- [ ] no trackers;
- [ ] auth/deletion flow;
- [ ] public config injection;
- [ ] discoverable footer link.

## `PRIVACY.md`

- [ ] actual SDK set;
- [ ] external deletion path;
- [ ] Google disconnect;
- [ ] retained anti-fraud data;
- [ ] updated review date.


---

# 33. Definition of done — code

All items in this section must be true before the coding work is considered complete.

## Consent/runtime

- [ ] No ad request starts unless the current UMP/runtime state permits it.
- [ ] Consent revocation stops future load/retry traffic without restart.
- [ ] No ad load is initiated from widget `build()`.
- [ ] Background/non-resumed state stops new load/retry traffic.
- [ ] Remote format flags stop request traffic for disabled formats.
- [ ] Re-enabling a format causes at most one controlled preload/load path.

## Request discipline

- [ ] No infinite automatic retry.
- [ ] No no-fill one-minute request loop.
- [ ] Retry has bounded attempts and jitter.
- [ ] Stale callbacks cannot repopulate cache.
- [ ] Cached ad older than internal max age is not shown.
- [ ] Retry/cached state is cleared on service disposal.

## Ownership and native visual consistency

- [ ] Every ad has one logical owner.
- [ ] Native ad disposal is idempotent.
- [ ] Full-screen disposal occurs through callback ownership.
- [ ] Route/overlay races are covered by tests.
- [ ] Showing full-screen ad is not destroyed merely because lifecycle temporarily becomes inactive.
- [ ] Every native placement follows final Flutter `Theme.of(context).brightness`.
- [ ] Android system Light/Dark cannot override an explicitly selected HomePilot app theme.
- [ ] A visible old-theme native platform view is removed on app-theme change.
- [ ] A stale in-flight old-theme callback is disposed and never mounted.
- [ ] One discrete theme change creates at most one replacement request per visible eligible native placement.
- [ ] Ad attribution and AdChoices remain visible/readable in Light and Dark.

## Rewards

- [ ] No client wallet credit.
- [ ] SSV cryptographic validation intact.
- [ ] Database independent validation intact.
- [ ] Reward claim is not created for stale/unshowable ad.
- [ ] Rewarded-interstitial intro/skip behavior satisfies current Google guidance.
- [ ] Production reward IDs/amounts remain synchronized with backend contract.

## Firebase

- [ ] No intentional Firebase Analytics dependency.
- [ ] No conditional `google-services.json` build behavior.
- [ ] Real Google Services configuration explicitly ignored.
- [ ] Documentation no longer implies unused Firebase setup.

## Google auth

- [ ] Normal logout signs out.
- [ ] Successful account deletion disconnects/revokes Google authorization.
- [ ] Google initialization can recover after transient failure.
- [ ] Scopes remain minimal and documented.
- [ ] No token material enters logs.

## Release

- [ ] APK production rail green.
- [ ] AAB production rail green.
- [ ] Merged manifest archived.
- [ ] Dependency evidence archived.
- [ ] Target SDK 36 retained or deliberately raised.
- [ ] Google backend tests CI-gated.

## Account deletion

- [ ] Public web resource exists.
- [ ] Resource works without installed Android app.
- [ ] Protected authenticated deletion/request flow works.
- [ ] No service-role credentials exposed.
- [ ] Public URL is ready for Play Console entry.

---

# 34. Definition of done — operator/console

The implementation is **not Google Play release-ready** until an operator records evidence for these items.

- [ ] AdMob app verified.
- [ ] Ad unit ownership verified.
- [ ] Rewarded item/amount values verified.
- [ ] SSV callback URL verified and tested.
- [ ] UMP/Privacy & Messaging configuration published.
- [ ] AdMob Policy Center reviewed.
- [ ] Test devices configured as needed.
- [ ] Google OAuth Web client verified.
- [ ] Android OAuth client verified.
- [ ] Play App Signing certificate registered with Google auth where required.
- [ ] External deletion URL deployed.
- [ ] External deletion URL entered in Play Console.
- [ ] Data Safety updated.
- [ ] Privacy policy URL current.
- [ ] Play Ads declaration correct.
- [ ] Advertising ID declaration correct.
- [ ] Target audience/Families reviewed.
- [ ] AAB uploaded to internal/closed track.
- [ ] Pre-launch report reviewed.
- [ ] Release-signed Google Sign-In works.
- [ ] Real-device Native Ad Validator passes.
- [ ] Real SSV callback credits exactly once.

---

# 35. Rollback plan

## Ad behavior rollback

The fastest safe production rollback is remote:

1. disable all ads in monetization config;
2. confirm the remediated app cancels loaders/retries;
3. investigate;
4. re-enable one format at a time.

## Code rollback

If a new runtime controller causes crashes:

- revert the specific controller/lifecycle commit;
- do not revert SSV/database hardening;
- keep ads disabled remotely while validating rollback.

## Auth rollback

If Google disconnect causes unexpected deletion-path failures:

- preserve backend deletion;
- make disconnect best-effort/fallback-to-signout;
- never restore a deleted Supabase account automatically.

## Play release rollback

Keep APK/VersionDeck workflow separate.

A problem in the AAB workflow must not break direct APK builds unless product distribution policy intentionally changes.

---

# 36. Agent PR checklist

The implementing agent should paste this into its PR and fill it with evidence.

## Engineering

- [ ] baseline drift checked
- [ ] Flutter format
- [ ] Flutter analyze
- [ ] Flutter tests
- [ ] production-config tests
- [ ] Deno SSV tests
- [ ] Supabase DB tests
- [ ] Google contract tests
- [ ] APK production build
- [ ] AAB production build
- [ ] merged manifest reviewed
- [ ] dependency graph reviewed
- [ ] no secrets/config accidentally committed

## Ads

- [ ] consent runtime gate
- [ ] lifecycle gate
- [ ] format kill switches
- [ ] bounded retry
- [ ] 55-minute freshness
- [ ] native single ownership
- [ ] native ad follows HomePilot Light/Dark theme on every placement
- [ ] app/system theme mismatch matrix tested
- [ ] theme switch creates at most one eligible replacement load
- [ ] full-screen serialization
- [ ] rewarded-interstitial intro/skip
- [ ] test ads only during testing

## Auth/account

- [ ] disconnect on deletion
- [ ] normal logout unchanged
- [ ] init retry
- [ ] external deletion site

## Privacy/release

- [ ] Firebase Analytics removed
- [ ] privacy docs updated
- [ ] Data Safety evidence updated
- [ ] Play runbook updated
- [ ] historical audit wording corrected

## Operator verification outstanding

List every item requiring:

- AdMob Console;
- Play Console;
- Google Cloud;
- Supabase production;
- physical device;
- production signing.

Do not mark these complete without evidence.

---

# 37. Implementation guardrails for the AI agent

## Do not over-refactor unrelated systems

This remediation touches monetization, authentication, Android config, release tooling, docs, and the deletion site. It does **not** justify unrelated UI, sync, database, or architecture rewrites.

If a required change exposes an unrelated bug, log it separately unless it blocks correctness or safety.

## Do not weaken behavior to make tests pass

Forbidden examples:

- skipping SSV verification in tests by adding production bypasses;
- returning success for invalid callbacks;
- making reward database functions callable by authenticated clients;
- forcing `canRequestAds=true` in production code;
- disabling lifecycle checks to avoid flaky tests;
- increasing retry frequency because ad loading looks slow in tests;
- exposing service-role credentials to make the account deletion webpage work.

## Keep time/random/network injectable

For the state machine, use seams for:

- current time;
- retry jitter/random;
- lifecycle input;
- ad SDK loader abstraction where feasible;
- UMP gateway where feasible.

This enables deterministic tests and reduces dependence on plugin MethodChannels in unit tests.

## Treat production IDs as configuration contracts

When editing any Google/AdMob identifier:

1. inspect all client references;
2. inspect all tests;
3. inspect backend validation;
4. inspect docs;
5. require operator confirmation.

Do not change one copy in isolation.

---

# 38. Suggested target class responsibilities

This section is architectural guidance; exact names may vary if existing conventions require different naming.

## `HomePilotConsentService`

Owns:

- UMP info refresh;
- form presentation;
- privacy-options presentation;
- consent snapshot publication.

Does not own:

- app lifecycle;
- ad retries;
- ad cache;
- full-screen serialization;
- remote format flags.

## `AdRuntimeController`

Owns:

- combining consent/config/lifecycle/platform state;
- generation changes;
- notifying ads service of eligibility changes;
- initial SDK setup trigger.

Does not own raw SDK ad objects.

## `HomePilotAdsService`

Owns:

- GMA SDK initialization state;
- full-screen ad loading/caching/showing;
- per-format retry state;
- cache timestamps;
- full-screen mutex;
- disposal;
- applying eligibility transitions.

Does not decide product placement/cooldown policy beyond format readiness.

## `InterstitialEligibilityPolicy`

Continues to own product timing rules:

- first-session;
- cooldown;
- session cap;
- rapid completion.

It should not know about UMP or SDK objects.

## `HkNativeAdCard`

Owns one visible native placement lifecycle and one ad lease.

It consumes central runtime eligibility rather than reconstructing its own incomplete policy.

## `AdRetryPolicy`

Pure deterministic policy based on failure class/attempt count.

## `AdCachePolicy`

Pure freshness rule.

---

# 39. Suggested production diagnostics after rollout

Observe aggregates, not personal data.

## Ad load metrics

By format:

- requests;
- loads;
- failures by coarse error class;
- circuit-open count;
- cache-expired count;
- shows;
- impressions where available;
- show failures.

## Consent metrics

Use only coarse non-PII operational counts if legally/product-approved:

- UMP update success/failure;
- privacy options required yes/no;
- ads allowed yes/no.

Do not record detailed TCF strings or consent payloads merely for debugging.

## Reward metrics

- claims created;
- client earned callback;
- SSV processed;
- duplicate callbacks;
- rejected callbacks by coarse reason;
- pending claim expiry.

Large divergence between client earned and SSV processed should alert engineering, but do not create a client credit fallback.

---

# 40. Explicit non-goals

This remediation should not:

- add Firebase Analytics;
- add Firebase Crashlytics;
- add Google Drive/Calendar/Contacts scopes;
- change Supabase auth provider away from Google;
- remove SSV in favor of client reward callbacks;
- add ad mediation unless separately approved;
- introduce banners if HomePilot does not currently use them;
- add background ad loading;
- auto-click/test live ads;
- redesign the whole download site except what deletion compliance requires;
- replace current APK distribution with Play-only distribution;
- guess Play Console answers.

---

# Appendix A — target ad runtime pseudocode

The exact implementation may differ, but semantics should be equivalent.

```dart
Future<void> applyEligibility(AdRuntimeEligibility next) async {
  if (_disposed) return;

  final previous = _eligibility;
  if (next == previous) return;

  _eligibility = next;
  _generation++;

  for (final format in AdFormat.values) {
    final wasEligible = previous?.canLoad(format) ?? false;
    final isEligible = next.canLoad(format);

    if (wasEligible && !isEligible) {
      _cancelRetry(format);
      _disposeReady(format);
      _markIneligible(format);
    }
  }

  if (!next.anyAdsMayLoad) return;

  if (!_initialized) {
    await _initializeSdkIfStillEligible();
  }

  if (_initialized && next.appForeground && next.canRequestAds) {
    await _preloadEnabledFullScreenOnce();
  }
}
```

Load path:

```dart
Future<void> load(AdFormat format) async {
  if (!_canStartLoad(format)) return;

  final generation = _generation;
  _markLoading(format);

  sdkLoad(
    onLoaded: (ad) {
      _markNotLoading(format);

      if (_disposed ||
          generation != _generation ||
          !_eligibility.canLoad(format)) {
        ad.dispose();
        return;
      }

      _storeReady(
        format,
        CachedAd(ad: ad, loadedAt: clock.now()),
      );
      _retryState(format).reset();
    },
    onFailed: (error) {
      _markNotLoading(format);

      if (_disposed || generation != _generation) return;

      final decision = retryPolicy.decide(...);
      if (decision.retryAutomatically &&
          _eligibility.canLoad(format)) {
        _scheduleRetry(format, decision.delay);
      } else {
        _markDormant(format);
      }
    },
  );
}
```

Show path:

```dart
Future<bool> showInterstitial() async {
  if (!_eligibility.canShow(AdFormat.interstitial)) return false;
  if (_fullScreenState != FullScreenAdState.idle) return false;

  final cached = _interstitial;
  if (cached == null) {
    unawaited(load(AdFormat.interstitial));
    return false;
  }

  if (clock.now().difference(cached.loadedAt) >= kAdCacheMaxAge) {
    _disposeInterstitial();
    unawaited(load(AdFormat.interstitial));
    return false;
  }

  final ad = _takeInterstitialOwnership();
  _fullScreenState = FullScreenAdState.showingInterstitial;

  ad.fullScreenContentCallback = ...;
  await ad.show();
  return completion.future;
}
```

---

# Appendix B — retry decision example

This is an example policy; exact numeric values may be tuned conservatively.

```text
NETWORK
failure 1 -> 2s ±20%
failure 2 -> 8s ±20%
failure 3 -> 30s ±20%
failure 4 -> 60s ±20%
failure 5+ -> dormant

NO_FILL
automatic -> none
reset -> next foreground / explicit demand / approved event

INVALID_REQUEST
automatic -> none
reset -> config change / app update

INTERNAL
failure 1 -> 5s ±20%
failure 2 -> 30s ±20%
then -> dormant
```

The important property is bounded behavior, not these exact numbers.

---

# Appendix C — release evidence bundle

For every Google Play candidate, retain equivalent artifacts:

```text
release-evidence/
  source-commit.txt
  flutter-version.txt
  dart-version.txt
  java-version.txt
  gradle-dependency-report.txt
  merged-AndroidManifest.xml
  signing-certificate.txt
  aab-jarsigner-verification.txt
  prod-config-validation.txt
  flutter-tests.txt
  ssv-deno-tests.txt
  supabase-db-tests.txt
  google-contract-tests.txt
  native-ad-validator-manual.md
  admob-console-manual.md
  play-console-manual.md
  oauth-console-manual.md
  data-safety-review.md
```

Do not put secrets in this bundle.

---

# Appendix D — items the AI agent must not solve by guessing

Never guess:

- production Google OAuth client IDs;
- OAuth client secrets;
- SHA certificate fingerprints;
- AdMob application ID;
- new production ad-unit IDs;
- reward amount configured in AdMob;
- SSV callback URL;
- Play package ownership;
- Play App Signing state;
- Google Play service-account credentials;
- Data Safety answers unsupported by evidence;
- consent geography;
- children's/Families applicability;
- whether AdMob Policy Center is clear.

Mark these as operator verification gates.

---

# Appendix E — final high-priority order

If implementation time becomes constrained, complete in this order:

1. Runtime UMP eligibility gate.
2. App lifecycle gate.
3. Per-format kill switches.
4. Bounded retries.
5. Cache freshness.
6. Native single ownership.
7. Full-screen serialization and reward pre-show checks.
8. Remove Firebase Analytics.
9. Google disconnect/init recovery.
10. CI SSV/DB gates.
11. External deletion web resource.
12. AAB Play build rail.
13. Merged manifest evidence.
14. Native-ad app-theme parity across every screen + AdChoices/layout cleanup.
15. Documentation/Data Safety evidence.
16. Console/device verification, including the four-way system/app theme matrix.

Do not ship a Google Play production release while required external deletion, console, privacy, OAuth, SSV, or Play-signing gates remain unresolved.

---

# Appendix F — official reference links to re-check before merge

- UMP Flutter: `https://developers.google.com/admob/flutter/privacy`
- Consent mode: `https://developers.google.com/admob/flutter/privacy/consent-mode`
- Flutter interstitial: `https://developers.google.com/admob/flutter/interstitial`
- Flutter rewarded: `https://developers.google.com/admob/flutter/rewarded`
- Flutter rewarded interstitial: `https://developers.google.com/admob/flutter/rewarded-interstitial`
- Flutter native ads: `https://developers.google.com/admob/flutter/native/platforms`
- Android native best practices: `https://developers.google.com/admob/android/native`
- SSV verification: `https://developers.google.com/admob/android/ssv`
- Invalid traffic: `https://support.google.com/admob/answer/3342054`
- Prevent invalid activity: `https://support.google.com/admob/answer/3342099`
- Test ads: `https://support.google.com/admob/answer/12251425`
- Firebase Analytics data collection: `https://firebase.google.com/docs/analytics/android/configure-data-collection`
- Google Sign-In disconnect: `https://developers.google.com/identity/sign-in/android/disconnect`
- `google_sign_in` Dart API: `https://pub.dev/documentation/google_sign_in/latest/google_sign_in/GoogleSignIn-class.html`
- Supabase native Google sign-in: `https://supabase.com/docs/reference/dart/auth-signinwithidtoken`
- Play User Data policy: `https://support.google.com/googleplay/android-developer/answer/10144311`
- Play account deletion: `https://support.google.com/googleplay/android-developer/answer/13327111`
- Android App Bundles: `https://developer.android.com/guide/app-bundle`
- Play release preparation: `https://support.google.com/googleplay/android-developer/answer/9859348`
- Play target API requirements: `https://support.google.com/googleplay/android-developer/answer/11926878`

---

**End of implementation plan.**

<!-- END VERBATIM SOURCE: HomePilot_Google_AdMob_Play_Remediation_Plan_v2(1).md -->

---

# APPENDIX B — Original Permission / Notification / Reminder / Weather Remediation Plan

<!-- BEGIN VERBATIM SOURCE: HomePilot_Permission_Notification_Weather_Full_Remediation_Plan(1).md -->

# HomePilot — Permission, Notification, Reminder, and Weather Location UX Remediation Plan

**Repository:** `zuhak5/HomePilot`  
**Baseline branch:** `main`  
**Baseline commit:** `075cd6ff5c36bb9c05b03f10a20598310ecf000d`  
**Baseline app version:** `1.4.8+34`  
**Plan type:** Implementation-ready plan for an AI coding agent  
**Recommended repository path:** `docs/plans/permission-notification-weather-state-remediation-plan.md`  
**Supersedes for this scope:** the remaining/open portions of `HomePilot_Permission_Education_Fix_Improve_Plan.md` that no longer match the v3 implementation.

---

## 0. Agent mandate

Implement the smallest complete change that makes HomePilot's **permission state, user preferences, and actual capability state truthful and consistent** across:

- Settings
- Permission setup / education
- Dashboard weather card
- Notification/reminder scheduling
- Android exact-alarm access
- Manual vs device-derived weather location
- lifecycle return from Android Settings
- English and Arabic localization
- accessibility / RTL
- tests
- documentation

Do **not** treat this as a visual-only cleanup. The current UI contradictions are consequences of state-model and orchestration problems. Fix the state semantics first, then render them consistently.

Before editing, read and obey:

1. `AGENTS.md`
2. `docs/governance/documentation-maintenance.md`
3. `docs/README.md`
4. `docs/permissions.md`
5. `docs/reference/routes-and-permissions.md`
6. `docs/product/feature-catalog.md`
7. `PRIVACY.md`
8. relevant notification/weather source and tests

Repository source-of-truth order from `AGENTS.md` applies: tests and implementation outrank stale prose.

### Non-negotiable project constraints

- Keep Riverpod and GoRouter.
- Keep coarse/approximate location only. Do not add fine or background location.
- Do not add new permission declarations unless explicitly justified and reviewed.
- Exact-alarm access remains optional/contextual.
- Preserve inexact reminder fallback.
- Preserve reboot/application-update reminder restoration.
- Localize every new user-visible string in English and Arabic.
- Regenerate localization output; never hand-edit generated localization Dart.
- Test RTL, text scaling, denied/blocked states, lifecycle resume, and supported/unsupported Android capability states.
- Do not log coordinates or sensitive user content.
- Update affected documentation and `CHANGELOG.md` in the same implementation PR.

---

# 1. Product principle: three different things must never be conflated

The UI must model these independently:

1. **User preference / intent**  
   Example: “I want device reminders.”

2. **Operating-system permission / special access**  
   Example: Android notifications are blocked, or exact alarms are not allowed.

3. **Effective capability**  
   Example: device reminders are actually deliverable; exact timing is actually available; weather has an area configured.

The fundamental rule for the implementation is:

> **Preference ≠ permission ≠ effective capability.**

A green toggle may represent a preference, but it must not be the only signal when the feature is blocked by Android. A permission card may show Android permission status, but it must not claim a product capability is “not set” when the capability is already configured another way.

---

# 2. Current-state audit

## 2.1 Settings currently persists preference before permission is resolved

Primary implementation: `lib/main.dart`, `SettingsScreen`, `_saveNotificationPreferences`, `_enableNotifications`, `_ensurePermission`.

Current flow:

```text
user changes any notification preference
    ↓
setNotificationPreferences(preferences)       <-- persisted immediately
    ↓
initialize scheduler
    ↓
if local reminders are allowed by preference
    ↓
request/check Android notifications
    ↓
if permission denied -> return
```

This causes the screenshot contradiction:

- HomePilot preference can remain `true`.
- Android permission can be `blocked`.
- Settings renders a green switch from the preference.
- Permissions section simultaneously reports `Blocked`.

This is not merely copy; it is a state-transition defect.

### Secondary consequence

Every preference edit delegates to `_enableNotifications`, so changing an unrelated row such as:

- in-app inbox,
- weather alerts,
- quiet hours,
- privacy mode,
- digest settings,

can trigger notification/exact-alarm permission logic when `localReminders` is already true.

Permission prompts must be attached to the feature action that requires them, not to unrelated preference saves.

---

## 2.2 Notification preference defaults currently imply capabilities before consent

Primary model: `lib/src/core/domain/models.dart`.

`NotificationPreferences` currently defaults to:

```dart
enabled = true
localReminders = true
inAppInbox = true
weatherAlerts = true
dailyDigest = true
preferExactReminders = true
```

Settings also falls back to `const NotificationPreferences()` while the provider is unavailable/loading.

Therefore a fresh or unconfigured state can naturally render:

- master alerts ON,
- device reminders ON,
- precise reminder alarms ON,
- inbox ON,
- weather alerts ON,

before OS permissions exist.

This is particularly inconsistent with the documented least-privilege rule for exact alarms.

### Required direction

At minimum, **exact timing must not default to requested/true for a new unconfigured user**.

Evaluate whether `localReminders` should also be opt-in by default. If changing legacy behavior, preserve existing explicit settings and handle migration deliberately rather than silently changing established users.

---

## 2.3 Permission setup uses OS permission as if it were capability configuration

Primary implementation:

- `lib/src/features/permissions/application/permission_education_controller.dart`
- `lib/src/features/permissions/presentation/permission_setup_screen.dart`

The setup screen derives its status primarily from `AppPermissionState`.

That is wrong for weather.

A user can select a city manually and have perfectly valid weather without granting location permission. The setup screen must therefore distinguish:

```text
Weather area configured?     yes/no
Weather area source?         manual/device
Device location permission?  granted/denied/etc.
Location service enabled?    yes/no
```

The current setup screen can show **“Not set”** even while Settings already displays a valid weather area.

---

## 2.4 Manual weather selection incorrectly mutates the controller's permission state

In `PermissionEducationController.chooseLocationManually(...)`, the controller records:

```dart
PermissionEducationOutcome.configuredManually
AppPermissionState.granted
```

A manually selected city does **not** grant Android location permission.

This creates a false internal permission state.

On a later fresh initialization, the gateway checks the actual OS permission again and sees it denied. Since relevance is currently based mainly on `permissionState != granted`, the location education can reappear even though a manual home area already satisfies the weather capability.

### Required fix

Manual configuration must satisfy the **weather-area capability**, not mutate the **device-location permission**.

---

## 2.5 Setup card “Manage in settings” can target the wrong permission

`_CapabilityStatusCard` gets an `onOpenSettings` callback that calls:

```dart
notifier.openSettingsForCurrent()
```

`openSettingsForCurrent()` acts on `state.activeCapability`.

The Settings setup screen renders multiple capability cards at the same time. If the user taps “Manage in settings” on a card that is not the controller's current active capability, the app may open settings for a different permission.

### Required fix

Use a target-specific API:

```dart
Future<void> openSettingsFor(PermissionCapability capability)
```

Every card must pass its own capability.

---

## 2.6 Setup screen status labels are generic and partially hardcoded

Current status chip logic is effectively:

```dart
isGranted ? 'Allowed' : (isBlocked ? 'Blocked' : 'Not set')
```

Problems:

- Strings are hardcoded instead of localized.
- `Not set` conflates:
  - denied,
  - not requested,
  - restricted,
  - unavailable,
  - capability not configured,
  - optional feature disabled.
- “Blocked” currently covers `permanentlyDenied` and `serviceDisabled` despite those requiring different recovery paths.
- `restricted` is not treated as a blocked/non-actionable state.
- a check icon appears on action buttons before the action succeeds.

### Required fix

Status is a domain value rendered through localization, not ad hoc text.

---

## 2.7 Setup page title is too long for common phone widths

Current English title:

> `Location, notifications, and reminders setup`

The observed phone truncates it in the app bar.

The subtitle:

> `Review how HomePilot uses location and reminders.`

also omits notifications even though notifications are a major card on the screen.

### Recommended copy

**App bar:** `Permissions & setup`

**Subtitle:** `Set up weather location, notifications, and reminder timing.`

Use equivalent concise Arabic copy and validate narrow RTL widths.

---

## 2.8 Checkmarks are used as pre-action icons

The setup screen uses `Symbols.check_rounded` inside filled action buttons such as:

- Use current location
- Enable notifications
- Allow precise timing

A checkmark communicates completion/success while the card simultaneously says the capability is not configured.

### Required fix

Use action-semantic icons before success:

- current location → `my_location`
- notifications → `notifications_active`
- exact timing → `alarm_on`

Reserve checkmarks for completed status indicators.

---

## 2.9 Exact-alarm education exists in code but contextual entry points are not wired

The enum already includes:

- `PermissionEducationSource.reminderSettings`
- `PermissionEducationSource.taskScheduling`
- `PermissionEducationSource.weatherCard`

The controller has logic for reminder settings/task scheduling, but repository search shows no external use of those exact-alarm source values. `weatherCard` is declared but is not handled by `_buildRelevantCapabilities`.

Therefore the architecture says “contextual education,” while actual contextual entry points are incomplete.

### Required fix

Wire sources to real feature interactions.

---

## 2.10 Weather card has no permission/configuration affordance

Primary implementation: `_WeatherCard` in `lib/main.dart`.

The card knows:

- `WeatherSnapshot? weather`
- `HomeLocation? location`
- time/theme state

It does **not** know:

- device-location permission state,
- location service state,
- whether the current location came from `manual` or `device`,
- what recovery action is appropriate.

The existing circular header button is a theme toggle, not a location action.

### Required fix

Add a **stateful location affordance**, not merely a decorative pin.

The affordance should explain both state and action when action is needed.

---

## 2.11 Two permission implementations can drift

Current permission implementations include:

- `lib/src/core/services/app_permission_coordinator.dart`
- `lib/src/features/permissions/data/device_permission_gateway.dart`

Both directly wrap `permission_handler` / Geolocator and map similar permission states.

This creates duplicate policy for:

- checks,
- requests,
- settings navigation,
- unsupported states.

### Required direction

Have one canonical platform permission implementation. A feature-layer adapter is acceptable, but it should delegate to the canonical service rather than reimplement platform calls.

---

## 2.12 Exact-alarm “open settings” is not target-specific

The feature gateway opens generic app settings for both:

- notifications
- exact alarm access

But exact alarm is special Android access. The enum already contains `openExactAlarmSettings`, but current next-action derivation does not select it.

### Required fix

Use the most specific supported system flow for exact-alarm access.

Before adding native code, verify the behavior of the current `permission_handler` version for `Permission.scheduleExactAlarm.request()` on target Android versions. If it cannot reliably reach the special-access surface, implement a narrow Android intent bridge with a generic app-settings fallback.

Do not change the manifest from `SCHEDULE_EXACT_ALARM` to another permission without a separate product/distribution review.

---

## 2.13 Permission resume refresh has an avoidable race

`handleAppResume()` can invoke `_advanceNextStep()` without awaiting it, then immediately assign refreshed status state.

Refactor resume handling so one deterministic state transition:

1. rechecks capability state,
2. recomputes effective status,
3. advances if appropriate,
4. publishes state once.

Avoid asynchronous state writes that can overwrite one another.

---

## 2.14 Session-level dismissal state appears incomplete

`PermissionEducationDeviceState` contains `dismissedUntil`, but current relevance logic relies mainly on per-step `isDeferredFor(...)`.

Either:

- implement the session cooldown consistently, or
- remove unused state after confirming backward compatibility.

Do not keep a field that appears authoritative but is ignored.

---

## 2.15 Current weather privacy reduction is good and must be preserved

`weather_service.dart` already quantizes coordinates to two decimal places and marks `HomeLocation.source` as `manual` or `device`.

Preserve this behavior.

Do not reintroduce raw/finer coordinates into:

- persistence,
- weather queries,
- reverse-geocoding,
- sync,
- logs.

---

## 2.16 Weather alerts currently have in-app semantics

`NotificationPreferences.allowsWeatherAlerts` depends on `allowsInbox`, and notification scheduling creates weather entries through the notification inbox repository.

Therefore the Settings label “Weather alerts” can be interpreted as Android push/local notifications even when the current implementation is primarily in-app.

### Recommended scope decision

For this remediation, do **not** silently change weather-alert delivery semantics.

Instead:

- make the copy explicit that this is an in-app/inbox alert if that remains the intended behavior, or
- split future device weather notifications into a separate permission-dependent feature.

---

# 3. Target domain model

Do not make UI widgets independently infer product state from booleans.

Create a single derived state layer that answers:

> “What does the user want, what does Android allow, what is configured, what is actually working, and what should the user do next?”

A reasonable shape is below. Exact naming may follow existing conventions.

```dart
enum EffectiveCapabilityState {
  active,
  degraded,
  blocked,
  disabledByUser,
  notConfigured,
  unavailable,
}

enum WeatherAreaMode {
  none,
  manual,
  device,
}

class WeatherAreaCapabilitySnapshot {
  final HomeLocation? selectedArea;
  final WeatherAreaMode mode;
  final AppPermissionState deviceLocationPermission;
  final bool locationServiceEnabled;
  final EffectiveCapabilityState effectiveState;
  final PermissionNextAction nextAction;

  bool get isConfigured => selectedArea != null;
}

class NotificationCapabilitySnapshot {
  final NotificationPreferences preferences;
  final AppPermissionState notificationPermission;
  final bool notificationsActuallyEnabled;
  final AppPermissionState exactAlarmPermission;
  final bool canActuallyScheduleExact;

  final EffectiveCapabilityState deviceReminderState;
  final EffectiveCapabilityState exactTimingState;
  final EffectiveCapabilityState inboxState;
  final EffectiveCapabilityState weatherAlertState;
}

class CapabilitySetupSnapshot {
  final WeatherAreaCapabilitySnapshot weather;
  final NotificationCapabilitySnapshot notifications;
}
```

The important requirement is semantic, not the exact class names.

---

# 4. Truth table: weather area

Use `HomeLocation.source` as an input, but do not treat it as the only source of truth.

| Area selected | Source | Location permission | Service | Effective weather state | UI meaning |
|---|---|---|---|---|---|
| No | — | Any | Any | `notConfigured` | Set weather area |
| Yes | manual | denied/blocked | Any | `active` | Manual/selected area works; location permission optional |
| Yes | manual | granted | Any | `active` | Selected area works; user may optionally use current location |
| Yes | device | granted | on | `active` | Using current/device location |
| Yes | device | denied/blocked | Any | `degraded` | Existing selected area can still show weather, but device-location refresh is unavailable |
| Yes | device | granted | off | `degraded` | Existing area works; location services are off |
| Any | — | unavailable | — | based on selected area | Manual location remains available |

### Critical rule

**Manual selection must never be represented as Android location permission granted.**

---

# 5. Truth table: notifications and reminders

## 5.1 Master HomePilot alert preference

The master preference is an **app preference**, not an OS permission indicator.

If retained, rename it to something explicit such as:

> `HomePilot alerts`

Suggested description:

> `Controls maintenance, digest, and in-app alert features.`

Do not label the master preference simply `Enabled`.

---

## 5.2 Device reminders

| App preference | Android notifications | Effective state | Settings UI |
|---|---|---|---|
| Off | Any | `disabledByUser` | Switch/action shows Off |
| On | Allowed | `active` | On / Active |
| On | Blocked | `blocked` | `Blocked by Android` + Fix/Enable action |
| On | Restricted | `blocked` or `unavailable` | Explain non-actionable/restricted state |
| On | Unavailable/not required | platform-dependent | Use truthful platform state |

When a user turns device reminders **on from off**, request notification permission first. Persist `localReminders=true` only after the required permission succeeds, unless product explicitly chooses to retain intent separately.

If notification permission is later revoked externally, preserve the user's stored intent if useful, but render a blocked action state rather than a plain green success switch.

---

## 5.3 Precise reminder timing

| User preference | Exact alarm access | Effective state | Behavior |
|---|---|---|---|
| Off | Any | inexact/disabled | Schedule inexact |
| On | Allowed | `active` | Schedule exact where supported |
| On | Missing | `degraded` / `blocked` | Continue inexact; show `Access required` |
| On | Unsupported | `unavailable` | Continue inexact; hide or label `Not required` |

The scheduler already has an inexact fallback. Preserve it.

### New-install default

`preferExactReminders` should default to **false** for a new/unconfigured user.

Do not automatically request exact-alarm special access during first-run permission onboarding.

---

# 6. Settings redesign

Primary target: `SettingsScreen` in `lib/main.dart`.

## 6.1 Permissions section

Replace the current two-row snapshot + ambiguous setup link with a capability-oriented summary.

Recommended rows:

### Notifications

Status examples:

- `Allowed`
- `Blocked by Android`
- `Permission required`
- `Unavailable`

Action when needed:

- `Enable`
- `Open settings`

### Exact reminder timing

Only meaningful on Android where the capability exists.

Status examples:

- `Allowed`
- `Access required`
- `Using approximate timing`
- `Not supported`

If precise timing preference is off, the normal state should not look like an error.

### Weather/location

Either show location permission in this permissions group or keep it primarily in the weather card. Avoid duplicate warning surfaces.

If included here, separate:

- weather area configuration,
- device location access.

Do not label a manually configured area as missing merely because GPS permission is denied.

---

## 6.2 Permission setup entry

Rename:

> `Location, notifications, and reminders setup`

to:

> `Permissions & setup`

Recommended subtitle:

> `Review weather location, notification access, and reminder timing.`

Always allow the user to open the setup screen.

Remove the current OS-only gate that shows “already enabled” and refuses navigation when all permissions are granted. Setup is also a configuration surface, not only a missing-permission surface.

Use:

```dart
context.push('/permissions/setup')
```

rather than replacing the current route with `context.go(...)` when launched from Settings, so Back naturally returns to Settings.

---

## 6.3 Preferences section hierarchy

Recommended organization:

```text
Preferences

HomePilot alerts                    [master preference]

Device reminders
  Active / Blocked by Android / Off
  [switch only when state is straightforward]
  [Enable/Fix action when permission is missing]

Precise reminder timing
  Exact / Approximate / Access required
  [contextual action]

In-app inbox                        [preference]
Weather inbox alerts                [preference; depends on inbox]
Quiet hours                         [preference]
Lock-screen privacy                 [preference]
Daily digest                        [preference]
...
```

### Do not render a misleading green switch in blocked states

For permission-dependent rows, render by effective state:

- **active:** normal switch
- **off:** normal switch
- **blocked/degraded:** status/action tile or switch + prominent status, not a success-only green state
- **unavailable:** disabled row with explanatory status

A custom reusable widget is preferable to repeating conditionals.

---

## 6.4 Remove permission requests from unrelated preference saves

Replace the current “everything calls `_enableNotifications`” flow with targeted commands.

Recommended application methods:

```dart
Future<void> setMasterAlertsEnabled(bool enabled)
Future<void> setDeviceRemindersEnabled(bool enabled)
Future<void> setPreciseTimingEnabled(bool enabled)
Future<void> setInAppInboxEnabled(bool enabled)
Future<void> setWeatherAlertsEnabled(bool enabled)
Future<void> updateReminderSchedulePreferences(...)
```

### Behavior

#### `setMasterAlertsEnabled`

- Save app preference.
- Reconcile schedules/inbox.
- Do not automatically request exact alarm access.
- Do not prompt for permissions unless the product interaction explicitly says it will enable a permission-dependent feature.

#### `setDeviceRemindersEnabled(true)`

1. check Android notification capability,
2. educate/request in context,
3. on grant, persist `localReminders=true`,
4. reconcile schedules,
5. on denial, leave it off or preserve intent in a separate explicit field; do not falsely show operational success.

#### `setDeviceRemindersEnabled(false)`

- persist false,
- cancel/reconcile local reminder schedules,
- never request permission.

#### `setPreciseTimingEnabled(true)`

1. ensure local reminders are meaningful,
2. show exact-alarm education,
3. request supported special access,
4. persist exact preference only according to chosen intent policy,
5. refresh schedules,
6. if denied, clearly retain approximate fallback.

#### `setPreciseTimingEnabled(false)`

- persist false,
- reconcile to inexact scheduling,
- do not alter OS permission.

#### In-app preferences

- save without requesting OS notification permission.

---

## 6.5 Autosave vs Save button

The current screen appears to autosave individual toggles **and** provides `Save reminder settings`.

Choose one model.

Recommended:

- settings rows autosave,
- remove the redundant save button,
- retain `Send test` as an explicit action.

If product requires a Save button, then stop persisting individual row changes immediately. Do not use both interaction contracts at once.

---

# 7. Permission setup screen redesign

Primary target:

`lib/src/features/permissions/presentation/permission_setup_screen.dart`

## 7.1 Header

Use:

**Title:** `Permissions & setup`

**Subtitle:** `Set up weather location, notifications, and reminder timing.`

Validate:

- small Android screens,
- 200% text scale,
- Arabic RTL,
- device font scaling.

---

## 7.2 Weather card states

### A. No weather area

Status:

> `Not configured`

Body:

> `Choose a city or use your current approximate location for local weather.`

Actions:

- `Use current location`
- `Choose location`

No checkmark icon.

### B. Manual area configured

Status:

> `Area selected`

Detail:

> `Using Al-Diwaniyah`

Actions:

- `Change location`
- `Use current location` (optional)

Do not display an error merely because location permission is denied.

### C. Device area configured and permission granted

Status:

> `Using current location`

Completed check may appear in the status badge.

Action:

- `Change`
- optional refresh/reacquire action

### D. Device area exists but permission revoked

Status:

> `Location access off`

Detail:

> `Weather can continue using the saved area. Enable location to update it from this device.`

Actions:

- `Enable location` / `Open settings`
- `Choose location`

### E. Location services off

Status:

> `Location services off`

Action:

> `Turn on location services`

Manual selection remains available.

---

## 7.3 Notification card states

Rename the card title from marketing-style:

> `Never miss important maintenance`

to a utility heading such as:

> `Notifications`

or:

> `Maintenance notifications`

Description can retain benefit-oriented copy.

States:

- `Off`
- `Permission required`
- `Allowed`
- `Blocked by Android`
- `Restricted`
- `Unavailable`

CTA must match the state.

---

## 7.4 Exact timing card states

Title:

> `Precise reminder timing`

Body:

> `Some Android devices require Alarms & reminders access for reminders at the exact selected time. Without it, HomePilot uses approximate timing.`

States:

- `Using approximate timing`
- `Access required`
- `Allowed`
- `Not supported`

Actions:

- `Allow precise timing`
- `Use approximate timing`
- `Manage in settings` only when appropriate

This directly covers the product requirement discussed: on devices where Android requires **Alarms & reminders** special access, include it in permission education.

---

## 7.5 Status design

Replace generic:

- Allowed
- Blocked
- Not set

with a typed status enum mapped to localized copy.

Suggested enum:

```dart
enum CapabilityUiStatus {
  active,
  configured,
  off,
  permissionRequired,
  accessRequired,
  blocked,
  serviceDisabled,
  restricted,
  degraded,
  unavailable,
}
```

Use status-specific color/icon semantics:

- positive → completed/active
- neutral → optional/off/configured
- warning → degraded/access required
- error only for actual blocking failure

Do not make “optional exact timing off” look like an error.

---

## 7.6 Action icons

Do not use a checkmark on an action that has not succeeded.

Suggested mappings:

| Action | Icon |
|---|---|
| Use current location | `my_location` |
| Choose location | `search` / `location_searching` |
| Enable notifications | `notifications_active` |
| Allow precise timing | `alarm_on` |
| Open settings | `settings` |
| Turn on location services | `location_on` |
| Completed state | `check_circle` |

---

# 8. Weather card location affordance

Primary target:

`_WeatherCard` in `lib/main.dart`.

The user's proposed location icon is correct **only if it represents state and action**.

Do not add an ambiguous pin that could mean:

- current location,
- change location,
- GPS enabled,
- permission denied,
- manual location.

## 8.1 Pass a derived location capability state into the card

Refactor the constructor toward:

```dart
class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.location,
    required this.locationCapability,
    required this.onLocationAction,
    ...
  });
}
```

Do not make `_WeatherCard` directly call platform permission APIs.

---

## 8.2 Weather card behavior matrix

### Manual selected area

Example:

```text
Al-Diwaniyah
Clear · Updated 1:28 PM
Selected area
```

No warning.

Optional action:

> `Use current location`

### Device-derived area + permission available

Example:

```text
Al-Diwaniyah
Clear · Updated 1:28 PM
Current location
```

A subtle pin is acceptable; no prominent warning is necessary.

### Device-derived area + permission revoked

Example:

```text
Al-Diwaniyah
Clear · Updated 1:28 PM
Location access off     Enable
```

The existing saved area/weather remains usable.

### Location services disabled

Example:

```text
Location services off   Turn on
```

### No area configured

The empty card should contain an explicit CTA:

> `Set weather area`

and offer:

- current location,
- manual city.

---

## 8.3 Responsive layout

The header already contains:

- location/weather text,
- theme toggle,
- temperature.

Do not add a permanent second large icon that crowds narrow screens.

Recommended responsive behavior:

- wide layout: compact status chip/button in header or under summary,
- narrow layout: one 44x44 actionable location icon only when action is required, with visible status text below the summary,
- always keep semantic label and tooltip,
- keep theme action distinct.

Touch targets: minimum 44–48 logical pixels.

---

## 8.4 Targeted education entry

`PermissionEducationSource.weatherCard` already exists but is currently unwired.

Implement one of these:

### Preferred

Add a focused controller API:

```dart
initialize(
  source: PermissionEducationSource.weatherCard,
  focus: PermissionCapability.deviceLocation,
)
```

The weather card opens only the location/weather capability education.

### Alternative

Push:

```text
/permissions/setup?focus=location
```

and render the focused card first.

Do not send a weather-card tap into a full multi-permission wizard unless the user explicitly chooses “Review all permissions.”

---

# 9. Fix the permission controller semantics

Primary target:

`lib/src/features/permissions/application/permission_education_controller.dart`

## 9.1 Initialization must load product configuration, not only OS states

During initialization load:

- `SettingsRepository.homeLocation()`
- `SettingsRepository.notificationPreferences()`
- notification effective permission state
- exact scheduling ability
- location permission/service state
- local education state

Build capability snapshots from all sources.

---

## 9.2 Manual location completion

Replace the current false permission mutation.

Bad conceptual result:

```text
configuredManually -> permissionState = granted
```

Correct result:

```text
weatherCapability = configured
weatherAreaMode = manual
locationPermission = actual gateway check result
outcome = configuredManually
```

---

## 9.3 Relevance logic

### First dashboard visit

Show:

- weather area only if no area is configured and cooldown allows,
- notification education only if the user has not already made an explicit choice and capability is not already active,
- never show exact-alarm special access by default.

If a manual weather area exists, device location permission is not relevant to first-run weather setup.

### Settings

Show all applicable setup cards because this is an explicit configuration screen, but render their true configured states.

### Weather card

Only location/weather capability.

### Reminder settings / task scheduling

Only exact timing when:

- precise timing is being enabled/requested,
- supported Android requires special access,
- exact access is missing.

---

## 9.4 Settings navigation API

Replace:

```dart
openSettingsForCurrent()
```

with:

```dart
openSettingsFor(PermissionCapability capability)
```

If the state says:

- location service disabled → location service settings,
- location permission permanently denied → app permission settings,
- notifications blocked → app notification/settings route as supported,
- exact alarms missing → exact-alarm special access flow,
- unavailable/restricted → no invalid CTA.

---

## 9.5 Resume

On `AppLifecycleState.resumed`:

1. re-read platform capability states,
2. re-read effective notification state,
3. re-read weather location/configuration,
4. recompute all currently displayed cards,
5. if a focused education step just became satisfied, advance,
6. publish a single coherent state.

No unawaited state mutation.

---

## 9.6 Errors

Current controller catches several exceptions silently.

Do not expose internal exceptions, but expose a non-sensitive UI failure state where the user needs feedback.

Examples:

- location allowed but position acquisition failed,
- settings screen could not open,
- schedule refresh failed after permission succeeded.

Keep logs privacy-safe and never log coordinates.

---

# 10. Canonical platform permission service

Consolidate policy between:

- `AppPermissionCoordinator`
- `FlutterDevicePermissionGateway`

Recommended approach:

1. Keep `AppPermissionCoordinator` as the platform-level implementation.
2. Turn feature `DevicePermissionGateway` into a thin adapter that maps `PermissionCapability` to `AppPermissionKind`.
3. Keep feature controller testability through the interface.
4. Eliminate duplicated direct calls to `Permission.notification`, `Permission.scheduleExactAlarm`, and Geolocator where possible.

This gives one mapping for:

- denied,
- permanently denied,
- restricted,
- service disabled,
- unavailable.

---

# 11. Notification effective-state service

Do not rely on only one of these:

- app preference,
- `permission_handler` status,
- `FlutterLocalNotificationsPlugin.areNotificationsEnabled()`,
- `canScheduleExactNotifications()`.

Create a single provider/service that derives an effective snapshot.

For example:

```dart
final notificationCapabilityProvider =
    FutureProvider.autoDispose<NotificationCapabilitySnapshot>((ref) async {
  final prefs = await ref.watch(settingsRepositoryProvider).notificationPreferences();
  final schedulerState =
      await ref.watch(notificationSchedulerProvider).permissionState();
  final platform = ref.watch(permissionCoordinatorProvider);

  final notificationPermission =
      await platform.check(AppPermissionKind.notifications);
  final exactPermission =
      await platform.check(AppPermissionKind.exactAlarms);

  return deriveNotificationCapability(
    prefs: prefs,
    permissionState: notificationPermission,
    exactPermissionState: exactPermission,
    notificationsActuallyEnabled: schedulerState.notificationsEnabled,
    canActuallyScheduleExact: schedulerState.canScheduleExact,
  );
});
```

Prefer pure derivation functions so state matrices are unit-testable without widgets.

---

# 12. Safe default / migration strategy

No Drift schema change is required merely to alter JSON preference defaults, but behavior changes still need migration/backward-compatibility reasoning.

## 12.1 Exact timing

Required:

- new/unconfigured users: `preferExactReminders = false`,
- existing persisted explicit `true`: preserve user preference,
- missing exact access: continue inexact scheduling and render `Access required` only if the preference is still desired.

If legacy settings predate the exact preference, do not infer that the user opted into special access.

---

## 12.2 Device reminders

Before changing `localReminders` default, inspect existing legacy mapping.

Preferred semantics for a new user:

```text
HomePilot/in-app features can be enabled
Device reminders are opt-in through notification education
Exact timing is opt-in later
```

If preserving `localReminders=true` for compatibility, blocked UI must still be fixed so it does not render as operational success before permission.

Document whichever migration decision is chosen.

---

# 13. Exact alarms: Android-specific implementation

Current manifest declares:

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

Keep the permission contextual.

## 13.1 Required UX

When exact access is required/missing:

```text
Precise reminder timing
Some Android devices require Alarms & reminders access for exact timing.
Without it, HomePilot uses approximate timing.

[Use approximate timing] [Allow precise timing]
```

## 13.2 Request flow

1. user explicitly selects precise timing,
2. check current exact scheduling capability,
3. if already allowed → enable preference,
4. if missing → show education,
5. invoke exact-alarm request/special access flow,
6. app resumes,
7. recheck `canScheduleExactNotifications`,
8. only report success from the rechecked result,
9. if denied → continue inexact and show non-blocking explanation.

## 13.3 Device testing

At minimum validate:

- Android where exact special access is required,
- Android where it is already allowed,
- unsupported/unavailable state,
- user denies/leaves settings without enabling,
- user enables and returns,
- user later revokes access,
- reboot,
- app update,
- time-zone change.

Do not claim device behavior from widget tests alone.

---

# 14. Location acquisition flow

Current weather service privacy quantization should remain.

Improve the flow so “permission granted” and “area configured” are separate milestones.

Recommended sequence:

```text
User taps Use current location
    ↓
education
    ↓
OS location permission
    ↓
permission granted
    ↓
get low-accuracy current position
    ↓
quantize immediately to 2 decimal places
    ↓
persist selected weather area
    ↓
update capability state = configured
    ↓
reverse-geocode label / refresh weather best-effort
```

If reverse geocoding is slow/unavailable, the user should not be trapped in a permission flow after permission is already granted.

Consider persisting a safe localized fallback label first and updating the label later if reverse geocoding succeeds.

Do not advance to “configured” if no `HomeLocation` was persisted.

---

# 15. Localization plan

Source files:

- `lib/l10n/app_en.arb`
- `lib/l10n/app_ar.arb`

Generated output must be produced with:

```bash
flutter gen-l10n
```

Do not edit generated `app_localizations*.dart` manually.

Suggested new/updated keys:

```text
permissionSetupTitleShort
permissionSetupSubtitleFull

capabilityStatusActive
capabilityStatusConfigured
capabilityStatusOff
capabilityStatusPermissionRequired
capabilityStatusAccessRequired
capabilityStatusBlockedByAndroid
capabilityStatusLocationServicesOff
capabilityStatusRestricted
capabilityStatusUsingApproximateTiming
capabilityStatusUnavailable

weatherAreaSelected
weatherUsingCurrentLocation
weatherLocationAccessOff
weatherLocationAccessOffBody
weatherSetArea
weatherChangeArea
weatherUseCurrentLocation

notificationSettingsTitle
notificationDeviceRemindersBlocked
notificationOpenAndroidSettings
notificationWeatherInboxAlerts
notificationWeatherInboxAlertsBody

exactReminderTimingTitle
exactReminderAccessRequired
exactReminderAllowed
exactReminderApproximate
exactReminderEducationBody
```

Do not mechanically translate English word order into Arabic. Validate natural Arabic copy and RTL layout.

---

# 16. Accessibility requirements

For every changed surface:

- 44–48dp minimum interactive target.
- Tooltip + semantic label on icon-only buttons.
- Status color must not be the only indicator.
- 200% text scale must not overflow/truncate critical meaning.
- App bar title should fit ordinary narrow phones.
- Arabic RTL chevrons/actions must follow directionality.
- Focus should return sensibly after Android Settings.
- Overlay education must retain accessible modal isolation and reduced-motion handling.
- “Blocked”, “Access required”, and “Off” need text, not only icons/colors.

---

# 17. Test plan

## 17.1 Pure domain tests

Add tests for derived state.

### Weather

- no location + permission denied → notConfigured
- manual location + permission denied → configured/active
- manual location + permission granted → configured/active
- device location + permission granted + service on → active
- device location + permission denied → degraded
- device location + service off → degraded/serviceDisabled
- unavailable location API + manual area → active

### Notifications

- master off → dependent effective states off
- local reminders on + OS allowed → active
- local reminders on + OS blocked → blocked
- exact preference off + no access → approximate, not warning/error
- exact preference on + exact access → active
- exact preference on + no exact access → degraded/accessRequired
- in-app inbox on + push blocked → inbox remains active
- weather inbox alert on + inbox off → dependent state clearly inactive

---

## 17.2 Permission controller tests

Expand `test/features/permissions/permission_education_controller_test.dart`.

Required cases:

1. manual weather area suppresses first-run location education,
2. manual choice leaves actual OS location permission denied,
3. weather-card source targets location only,
4. reminder-settings source targets exact only when relevant,
5. task-scheduling source targets exact only when relevant,
6. settings source populates configured and missing cards,
7. `openSettingsFor(cap)` opens the tapped capability, not active capability,
8. location service disabled uses location service settings,
9. exact timing uses exact settings/request path,
10. resume recomputes state without race,
11. permission granted but current position fails → permission allowed / area still not configured,
12. finish later / deferral cooldown behavior,
13. restricted/unavailable states do not expose invalid actions.

---

## 17.3 Permission setup widget tests

Add a dedicated test file if the existing `widget_test.dart` coverage is too broad:

`test/features/permissions/permission_setup_screen_test.dart`

Test:

- short title does not overflow at narrow width,
- subtitle includes notifications,
- no checkmark on pre-action buttons,
- localized status labels,
- manual configured location shows `Area selected`,
- blocked notifications show `Blocked by Android`,
- exact off shows approximate/optional state rather than `Not set`,
- exact missing while desired shows `Access required`,
- exact unavailable is hidden or labeled according to final design,
- each card opens its own settings target,
- 200% text scale,
- Arabic RTL.

---

## 17.4 Settings widget tests

Add focused Settings tests for the contradictions seen in the screenshots.

Cases:

### Push blocked, app preferences present

Expected:

- permission summary says blocked,
- device reminder row does not look fully operational,
- in-app inbox can remain active,
- weather inbox alerts can remain active if their actual dependency is satisfied.

### Exact access missing

Expected:

- no “successful” precise timing state,
- `Access required` if precise preference is desired,
- approximate fallback described.

### Exact preference off

Expected:

- no warning,
- no exact permission prompt from unrelated settings changes.

### Unrelated toggle

Changing:

- inbox,
- weather inbox alert,
- quiet hours,
- privacy mode,

must not invoke Android notification or exact-alarm permission request.

---

## 17.5 Weather card widget tests

Create focused tests for `_WeatherCard` or extract it to a testable public/internal widget file.

Cases:

- manual area → neutral selected-area state,
- device area + permission allowed → current-location state,
- device area + permission revoked → location-off state + enable action,
- service disabled → settings action,
- no area → set-area CTA,
- narrow width,
- 200% text scale,
- Arabic RTL,
- theme button remains distinct and accessible.

---

## 17.6 Notification scheduling tests

Verify:

- exact preference false → inexact schedule mode,
- exact preference true + access allowed → exact mode,
- exact preference true + access denied → inexact fallback,
- toggling exact off reschedules existing reminders inexactly,
- disabling device reminders removes schedules,
- enabling inbox without push permission does not require push,
- weather inbox alerts remain inbox-only unless product intentionally changes scope.

---

## 17.7 Integration/device tests

Manual or automated device matrix:

- notifications first grant,
- notification denial,
- notification permanent/block state,
- notifications revoked in Android Settings while app is backgrounded,
- location grant,
- location denial,
- location service off,
- manual city with location permission denied,
- exact access enable/deny/revoke,
- return from system settings,
- process recreation if feasible,
- reboot restoration,
- app update restoration,
- time-zone change.

Record what is tested on physical device/emulator versus only unit/widget tests.

---

# 18. Documentation impact

The implementation PR must review and update at minimum:

### `docs/permissions.md`

Update:

- source-of-truth model,
- effective capability distinction,
- manual location semantics,
- exact-alarm contextual entry points,
- Settings recovery behavior.

### `docs/reference/routes-and-permissions.md`

Current route reference does not list `/permissions/setup` even though the route exists in `lib/main.dart`.

Add it and document focused setup behavior if a query parameter is introduced.

### `docs/product/feature-catalog.md`

Clarify:

- in-app notification capability vs device notifications,
- exact timing fallback,
- weather-area setup.

### `PRIVACY.md`

Review; likely no data expansion if plan is implemented as written.

If no privacy behavior changes, explicitly record “reviewed, no change” and why.

### `docs/development/localization-and-rtl.md`

Review if new UI patterns or copy affect localization guidance.

### `docs/development/testing.md`

Update if new device/integration commands or test matrix become canonical.

### `CHANGELOG.md`

Required because this is user-visible permission/settings behavior.

### Existing root plan

`HomePilot_Permission_Education_Fix_Improve_Plan.md` predates the current v3 state.

Do not leave two documents both appearing current.

When this new plan is committed/implemented:

- mark the old plan historical/superseded, or
- move it to `docs/history/`,
- preserve it only as historical design context.

---

# 19. Suggested implementation sequence

## Phase 1 — pure state semantics

1. Add effective capability state models / pure derivation functions.
2. Load real weather configuration + notification preferences into the permission/capability layer.
3. Fix manual location semantics.
4. Add focused `openSettingsFor(capability)`.
5. Add unit tests for state matrices.

Do not touch visual styling heavily until these pass.

---

## Phase 2 — permission platform consolidation

1. Make one platform permission coordinator canonical.
2. Adapt the feature permission gateway to delegate.
3. Implement/verify exact-alarm special access path.
4. Fix lifecycle resume recomputation.
5. Add controller tests.

---

## Phase 3 — notification preference commands

1. Split generic `_enableNotifications` into targeted commands.
2. Prevent unrelated toggles from prompting permissions.
3. Normalize exact default to false for new/unconfigured state.
4. Preserve existing explicit preferences.
5. Reconcile notification schedules after each relevant change.
6. Add Settings/state tests.

---

## Phase 4 — Permission setup UI

1. Short title/subtitle.
2. Typed localized statuses.
3. capability-aware cards.
4. correct action icons.
5. target-specific settings action.
6. manual weather configured state.
7. exact contextual education.
8. accessibility/RTL tests.

---

## Phase 5 — weather card

1. derive location capability state at Dashboard level/provider,
2. pass state into weather card,
3. add stateful location affordance,
4. wire focused weather-card education/action,
5. keep theme action distinct,
6. test responsive layout.

---

## Phase 6 — documentation and validation

1. update docs,
2. update changelog,
3. regenerate localization,
4. format,
5. analyze,
6. run focused tests,
7. run complete relevant Flutter suite,
8. perform Android device verification,
9. inspect final diff for unrelated/generated noise.

---

# 20. Suggested commit breakdown

Keep commits reviewable.

```text
refactor(permissions): add effective capability state model

fix(permissions): separate manual weather setup from location permission

fix(notifications): decouple preference saves from Android permission prompts

fix(reminders): make exact timing contextual and truthful

ui(settings): render permission-aware notification states

ui(permissions): redesign capability setup states and copy

ui(weather): add stateful location access affordance

test(permissions): cover denied blocked manual and exact-alarm states

docs(permissions): align current capability and settings behavior
```

Do not force this exact breakdown if the implementation is cleaner another way.

---

# 21. Acceptance criteria

The change is not complete until all of these are true.

## Settings

- [ ] Push notification status can say `Blocked` without a contradictory “fully working” device-reminder presentation.
- [ ] Exact alarm access missing cannot look like a completed precise-reminder capability.
- [ ] Master HomePilot alert preference is clearly an app preference.
- [ ] In-app inbox is correctly shown as independent of Android push permission where applicable.
- [ ] Weather-alert copy matches actual delivery semantics.
- [ ] Unrelated preference changes never trigger OS permission prompts.
- [ ] Permission setup always opens as a configuration screen.
- [ ] Back navigation returns to Settings.

## Permission setup

- [ ] App bar title fits a narrow phone.
- [ ] Subtitle covers weather/location, notifications, and reminder timing.
- [ ] No pre-action button uses a success checkmark.
- [ ] Statuses are localized.
- [ ] Statuses distinguish permission required, blocked, service off, unavailable, optional/off, configured, and active as needed.
- [ ] Manual weather area counts as configured.
- [ ] Manual weather area does not fake location permission granted.
- [ ] Each card opens settings for itself.
- [ ] Exact alarm education appears contextually on supported devices.
- [ ] Approximate reminder fallback remains usable.
- [ ] Arabic RTL and 200% text scale pass.

## Weather card

- [ ] Location affordance is stateful, not decorative.
- [ ] Manual city is not treated as an error when GPS permission is off.
- [ ] Device-derived area with revoked permission shows a clear recovery action.
- [ ] No-location state offers setup/manual selection.
- [ ] Theme toggle remains distinct.
- [ ] Narrow layout remains usable.

## Architecture

- [ ] One canonical platform permission implementation exists.
- [ ] UI reads a derived capability state rather than reconstructing semantics ad hoc.
- [ ] exact-alarm contextual source is actually wired.
- [ ] weather-card source is actually wired or replaced with a focused route.
- [ ] lifecycle resume recomputation has no unawaited state race.
- [ ] unused dismissal state is implemented or removed deliberately.
- [ ] exact default does not cause unrequested special-access intent for new users.

## Privacy / platform

- [ ] coarse location only.
- [ ] two-decimal privacy reduction preserved.
- [ ] no background location.
- [ ] no coordinates in logs.
- [ ] exact alarm remains optional/contextual.
- [ ] reboot/update restoration remains functional.

---

# 22. Validation commands

Follow the repository instructions exactly.

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Use focused tests first while iterating.

If no Drift schema/source change requires regeneration, do not create unrelated generated noise. Still follow repository validation policy for the final branch as applicable.

Also perform the documentation impact review required by:

`docs/governance/documentation-maintenance.md`

Final agent report must state:

- tests run and results,
- tests not run,
- device-only verification still needed,
- documents reviewed,
- documents changed,
- any remaining unverified Android behavior.

---

# 23. AI-agent execution checklist

Before coding:

- [ ] Confirm baseline is still close to `075cd6ff...`; if `main` moved, re-audit changed files.
- [ ] Read `AGENTS.md`.
- [ ] Read documentation maintenance policy.
- [ ] Inspect current `git status`; preserve unrelated work.
- [ ] Search symbols instead of relying only on baseline line numbers.
- [ ] Confirm current notification preference persistence and legacy mapping.
- [ ] Confirm current Android exact-alarm plugin behavior before introducing native code.

During coding:

- [ ] Build pure state derivation first.
- [ ] Add tests before/with behavior changes.
- [ ] Do not persist a permission-dependent success before permission success.
- [ ] Do not fake OS permission state for manual weather configuration.
- [ ] Do not request permission from unrelated setting edits.
- [ ] Do not introduce precise/background location.
- [ ] Keep approximate reminder fallback.
- [ ] Keep user-visible strings in ARB sources.

Before completion:

- [ ] Regenerate localization.
- [ ] Run focused tests.
- [ ] Run broad Flutter validation.
- [ ] Test Arabic and 200% text.
- [ ] Device-test notification, location, and exact-alarm return flows.
- [ ] Update docs + changelog in the same PR.
- [ ] Inspect final diff for stale old-plan claims.
- [ ] Report device/CI claims honestly.

---

# 24. High-risk regressions to guard against

1. **Manual weather users repeatedly prompted for location.**
2. **A permission denial leaves a green “success” state.**
3. **Exact alarm request appears during first-run onboarding.**
4. **Changing an inbox/quiet-hours preference unexpectedly opens Android permission UI.**
5. **Revoking notification permission does not update Settings after app resume.**
6. **Exact permission denial disables reminders completely instead of falling back to inexact.**
7. **Weather card treats manual area as missing because GPS is off.**
8. **A card opens Android settings for a different capability.**
9. **Arabic layout overflows after shorter English-only assumptions.**
10. **Location precision increases during refactor.**
11. **Notification scheduling is not reconciled after a preference/permission transition.**
12. **Old docs still claim contextual flows that are not actually wired.**

---

# 25. Final target user experience

A user should be able to understand the state without knowing Android permission terminology.

### Example: notifications blocked

```text
Notifications
Android notifications: Blocked                         [Fix]

HomePilot alerts                                      ON
In-app inbox                                          ON
Weather inbox alerts                                  ON

Device reminders
Blocked by Android                                    [Enable]

Precise reminder timing
Using approximate timing
```

No contradiction: HomePilot's in-app capabilities can be on while Android device delivery is blocked.

### Example: exact access needed

```text
Precise reminder timing
Access required

Android may require Alarms & reminders access for exact timing.
Without it, reminders use approximate timing.

[Use approximate timing] [Allow precise timing]
```

### Example: manually selected weather location

```text
Al-Diwaniyah
Clear · Updated 1:28 PM
Selected area                                         [Change]
```

No GPS warning is necessary.

### Example: device location permission later revoked

```text
Al-Diwaniyah
Clear · Updated 1:28 PM
Location access off                                   [Enable]
Weather continues using your saved area.
```

This is the intended conceptual endpoint of the remediation.

---

# 26. Baseline files most likely to change

Implementation:

- `lib/main.dart`
- `lib/src/core/domain/models.dart`
- `lib/src/core/data/repositories.dart`
- `lib/src/core/services/app_permission_coordinator.dart`
- `lib/src/core/services/notification_service.dart`
- `lib/src/core/services/weather_service.dart` only if acquisition/configuration flow needs separation
- `lib/src/features/permissions/domain/permission_capability.dart`
- `lib/src/features/permissions/domain/permission_education_state.dart`
- `lib/src/features/permissions/data/device_permission_gateway.dart`
- `lib/src/features/permissions/application/permission_education_controller.dart`
- `lib/src/features/permissions/presentation/permission_setup_screen.dart`
- `lib/src/features/permissions/presentation/permission_education_overlay.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ar.arb`

Tests:

- `test/features/permissions/permission_education_controller_test.dart`
- `test/features/permissions/permission_education_overlay_test.dart`
- new `test/features/permissions/permission_setup_screen_test.dart`
- focused Settings/weather tests in `test/widget_test.dart` or extracted dedicated files
- notification scheduling tests as appropriate
- integration tests for device settings return if the test harness supports them

Documentation:

- `docs/permissions.md`
- `docs/reference/routes-and-permissions.md`
- `docs/product/feature-catalog.md`
- `PRIVACY.md` review
- `docs/development/localization-and-rtl.md` review
- `docs/development/testing.md` review
- `CHANGELOG.md`
- old permission plan archival/supersession

---

## End state

Do not optimize for “all toggles are green.”

Optimize for **truthful, recoverable capability state**:

- what HomePilot is configured to do,
- what Android currently permits,
- what will actually work,
- what fallback is active,
- and exactly what the user can do next.

<!-- END VERBATIM SOURCE: HomePilot_Permission_Notification_Weather_Full_Remediation_Plan(1).md -->

---

# APPENDIX C — Original Splash Full Fix & Improvement Plan

<!-- BEGIN VERBATIM SOURCE: HomePilot_splash_full_fix_improvement_plan(1).md -->

# HomePilot Splash — Full Fix & Improvement Implementation Plan

**Repository:** `zuhak5/HomePilot`  
**Target area:** Native Android splash → Flutter animated splash → startup/auth/hydration → routed application  
**Primary implementation files:** `lib/main.dart`, `lib/homepilot_animated_splash_screen.dart`, Android launch resources, splash tests, startup tests, changelog/docs  
**Audience:** AI coding agent implementing the changes  
**Priority:** High  
**Goal:** Make the splash system truly process-scoped, purely presentational, deterministic, visually continuous, and regression-tested across real HomePilot startup transitions.

---

## 1. Executive summary

HomePilot already contains a substantially improved splash component: `HomePilotSplashOverlay` keeps the application mounted underneath, blocks interaction while visible, fades out after a fixed duration, and no longer owns navigation/auth/sync/bootstrap decisions.

The remaining problems are primarily **ownership and startup topology**, not animation design.

Two high-severity issues must be corrected:

1. **The application currently creates more than one splash overlay across startup root branches.**  
   The startup branch and the authenticated router branch each construct their own `HomePilotSplashOverlay`. When the app changes from one root branch to the other, Flutter disposes the first overlay state and constructs another state. The splash timer therefore restarts and the splash can visibly reappear.

2. **The animated Flutter splash is instantiated too late.**  
   Deferred bootstrap and startup-theme loading can render plain `ColoredBox` placeholders before the application tree that contains the animated splash exists. This allows native splash → blank Flutter surface → animated splash instead of a continuous native splash → animated Flutter splash handoff.

The implementation must establish one stable splash lifecycle owner from the earliest viable Flutter frame until its fixed display/fade duration finishes. Startup, authentication, hydration, routing, theme loading, and sync must continue independently underneath it.

Do **not** solve this by reintroducing route-driven splash behavior, waiting for bootstrap completion, adding a second startup state machine, or hiding the underlying app until it is ready.

---

# 2. Required behavior

The final implementation must satisfy all of the following invariants.

## 2.1 Process-scoped lifetime

The animated Flutter splash must appear **once per Flutter process launch**.

It must not restart or reappear when:

- startup state changes;
- stored-session checking completes;
- authentication resolves;
- cloud hydration starts or finishes;
- `authenticatedReady` becomes true;
- the root navigation configuration changes;
- the user signs in;
- the user signs out;
- the app navigates between screens;
- the theme changes;
- locale changes;
- the app is backgrounded and resumed;
- a provider rebuilds;
- the underlying application root rebuilds;
- a deep link or notification route is processed.

A true process restart may display the splash again.

---

## 2.2 Pure presentation

The splash may own only presentation-specific state such as:

- animation controllers;
- a fixed display timer;
- a fade-out timer/controller;
- whether the overlay layer is still mounted.

It must not own or wait on:

- authentication;
- Supabase;
- database initialization;
- sync;
- cloud restore;
- permission education;
- route selection;
- deep-link resolution;
- notification routing;
- startup theme loading;
- monetization initialization;
- network connectivity;
- app readiness flags.

The underlying application must start and continue working while covered.

---

## 2.3 Fixed timing

Unless product requirements are intentionally changed, preserve the existing contract:

- visible display: approximately **3.2 seconds**;
- fade-out: approximately **250 ms**;
- total overlay lifetime: approximately **3.45 seconds** from the initial Flutter splash mount.

The timer starts exactly once.

If the app is ready earlier, the splash still finishes its configured presentation duration.

If the app is not ready when the splash finishes, the splash must leave anyway and reveal the legitimate startup/auth/hydration state underneath.

Never restart the timer because startup progressed.

---

## 2.4 Continuous native → Flutter handoff

The startup path should visually behave as:

```text
Android native launch splash
        ↓
first usable Flutter frame containing animated splash
        ↓
animated splash continues while app initializes underneath
        ↓
fixed fade-out
        ↓
whatever application state is actually current
```

Avoid this sequence:

```text
native splash
  ↓
plain Flutter background
  ↓
theme/bootstrap placeholder
  ↓
animated splash
```

The launch background and Flutter splash background should use the same canonical visual color.

Current splash target color:

```text
#F9FCF8
```

Do not accidentally substitute the general application background (`HkColors.appBackground`, currently a different color) during the native-to-Flutter transition.

---

# 3. Scope

## In scope

- Splash ownership/lifecycle.
- Root startup topology needed to preserve one overlay state.
- Earliest Flutter splash mounting.
- Native-to-Flutter color continuity.
- Startup placeholder behavior exposed after the splash.
- Removal of stale splash timing/bootstrap contracts.
- Widget/integration tests.
- Android resource validation.
- Reduced-motion behavior.
- System-bar transition verification.
- Changelog/documentation corrections.
- CI/release verification relevant to splash behavior.

## Out of scope unless required for correctness

- Redesigning the splash artwork.
- Rebranding.
- Changing application navigation destinations.
- Rewriting authentication.
- Rewriting Supabase startup.
- Rewriting cloud sync/hydration.
- Changing permission education behavior.
- Broad `main.dart` cleanup unrelated to startup ownership.
- Changing splash duration as a product decision.
- Adding readiness-dependent splash delays.

If a broader refactor becomes necessary, keep it narrowly constrained to enabling one stable application/splash root.

---

# 4. Current architecture problems the agent must verify before editing

Before making changes, inspect current `main` and confirm the exact current topology. Do not rely only on this plan if the repository has moved forward.

At the time this plan was written, the relevant facts were:

- `lib/homepilot_animated_splash_screen.dart` defines `HomePilotSplashOverlay`.
- `HomePilotSplashOverlay` is substantially presentation-only.
- `HomePilotApp` has different root branches for pre-auth/startup and `authenticatedReady`.
- Both branches create a splash overlay.
- One branch uses a regular `MaterialApp`.
- The authenticated branch uses `MaterialApp.router`.
- Transitioning between those branches can create a new overlay state.
- `_DeferredHomePilotBootstrap` intentionally waits until after an initial frame to begin part of initialization.
- Before it is ready, it can return a plain `ColoredBox`.
- Startup theme loading can also return a plain background placeholder.
- Those placeholders use `HkColors.appBackground`, which is not identical to the splash background.
- Legacy timing symbols such as `minimumNativeSplashDuration`, `minimumSplashDuration`, or `remainingNativeSplashDuration(...)` may still exist even though the new overlay has independent fixed timing.

If any of these facts have changed, adapt the implementation while preserving the invariants in this document.

---

# 5. Preferred target architecture

The preferred architecture is:

```text
runApp
  └── stable process/startup root
      └── stable application inherited-widget boundary
          └── one stable splash overlay host
              ├── current HomePilot application content
              │    ├── startup/auth/hydration state
              │    └── authenticated router state
              └── animated splash layer
```

There must be **one state object that owns the splash lifetime**, and that state object must not be replaced when startup changes to the authenticated application.

The root application/inherited-widget structure must also remain valid for:

- `Directionality`;
- `MediaQuery`;
- Material widgets;
- localization;
- theme;
- router;
- navigator;
- provider scopes.

---

# 6. Critical design rule: do not move the overlay blindly above MaterialApp

The current overlay is hosted within a Material application context for a reason: the splash UI may depend on inherited widgets such as `Directionality`, `MediaQuery`, Material defaults, localization, text scale, or theme.

Therefore:

**Do not simply wrap two existing `MaterialApp` branches with `HomePilotSplashOverlay` outside both apps unless the overlay is explicitly made self-sufficient and verified.**

A naive structure like this may introduce runtime failures:

```dart
HomePilotSplashOverlay(
  child: startupReady
      ? MaterialApp.router(...)
      : MaterialApp(...),
)
```

if the overlay itself renders `Text`, Material components, or direction-sensitive layout without the required inherited context.

The agent must either:

1. create a single stable Material application boundary and host the overlay inside its `builder`; **preferred**, or
2. explicitly provide all required inherited context in a dedicated root splash host and prove it with tests; **fallback only**.

Do not create nested `MaterialApp` instances merely to give the splash context.

---

# 7. Phase 0 — Baseline and inventory

Before editing:

1. Record the current branch/commit.
2. Inspect:
   - `lib/main.dart`
   - `lib/homepilot_animated_splash_screen.dart`
   - `test/homepilot_splash_overlay_test.dart`
   - `test/startup_resources_test.dart`
   - `test/startup_benchmark_test.dart`
   - `flutter_native_splash.yaml`
   - Android `values*`, `drawable*`, and launch-theme resources
   - `CHANGELOG.md`
   - `HomePilot_pure_splash_ai_agent_plan.md`
3. Search the entire repository for:
   - `HomePilotSplashOverlay`
   - `HomePilotAnimatedSplashScreen`
   - `minimumNativeSplashDuration`
   - `minimumSplashDuration`
   - `remainingNativeSplashDuration`
   - `nextRoute`
   - `navigateAutomatically`
   - `pushReplacementNamed`
   - `splash_background`
   - `F9FCF8`
   - `flutter_native_splash`
4. Count every splash overlay construction site.
5. Identify the earliest Flutter widget currently mounted by `runApp`.
6. Identify every placeholder that can render before `HomePilotApp`.
7. Identify the state transition that swaps `MaterialApp` → `MaterialApp.router`.
8. Run current focused tests before refactoring, if the environment supports them:
   - splash overlay tests;
   - startup resource tests;
   - startup benchmark tests.
9. Record existing failures separately. Do not silently attribute pre-existing failures to the splash change.

---

# 8. Phase 1 — Establish a single stable application root

## Objective

Eliminate the root-tree swap that creates a second splash owner.

## Preferred implementation

Refactor the root so the same Material application boundary survives all startup states.

The agent should inspect why the code currently needs both `MaterialApp` and `MaterialApp.router`, then choose the smallest correct unification strategy.

### Preferred strategy A — one stable `MaterialApp.router`

Use one `MaterialApp.router` from the relevant startup root if the router can safely exist before authentication is ready.

Under this model:

- startup/auth/hydration views become router-visible application states, redirects, or root content;
- `HomePilotSplashOverlay` is installed once in the stable app's `builder`;
- when startup becomes authenticated, only routed content changes;
- the `MaterialApp.router` and splash `State` survive.

Use this only if router/provider creation does not require authenticated data that is unavailable during startup.

### Preferred strategy B — one stable `MaterialApp` containing a Router when ready

If `MaterialApp.router` cannot safely exist before authentication, preserve one stable `MaterialApp` and switch only its `home`/body content:

```text
MaterialApp
  builder: one HomePilotSplashOverlay
  home:
    startup/auth/hydration UI
      OR
    authenticated Router widget
```

The authenticated routing layer should be embedded as a `Router`/routing widget, not as a second nested `MaterialApp.router`, if the router package supports this cleanly.

Preserve:

- theme behavior;
- locale delegates;
- navigator semantics;
- route observers;
- back button behavior;
- deep links;
- notification navigation;
- Sentry navigation integration;
- monetization wrappers.

### Fallback strategy C — explicit stable splash host with its own context

Use only if A/B would cause a disproportionate navigation rewrite.

A dedicated process-scoped host may sit above application branch replacement, but it must explicitly supply every inherited dependency the splash requires and must not create nested apps.

If this route is chosen:

- make the splash visual layer independent from application Material context;
- supply `Directionality`;
- use root `MediaQuery`/`View` safely;
- avoid relying on `Theme.of(context)` unless a local splash theme is provided;
- keep system UI styling local;
- add tests that render the host as the direct `runApp` root.

Document why this fallback was necessary.

---

# 9. Phase 2 — Guarantee exactly one splash construction site

After root refactoring:

- There should be one production construction site for `HomePilotSplashOverlay`.
- That construction site should belong to a stable startup/application owner.
- The splash overlay state must survive startup-state branch changes.

Add a code comment at the ownership point explaining the invariant:

```text
Splash is process-scoped presentation.
Do not duplicate it inside auth/startup/router branches.
```

Avoid a global mutable boolean unless absolutely necessary.

The preferred correctness mechanism is **stable widget ownership**, not a global `hasShownSplash` flag.

A global flag can hide symptoms while still creating/removing incorrect widget trees. Use state topology as the primary guarantee.

---

# 10. Phase 3 — Mount the Flutter splash at the earliest viable frame

## Objective

The first meaningful Flutter presentation after the Android launch screen should already contain the animated splash.

Currently deferred bootstrap/theme placeholders may appear before the splash-owning app exists.

Restructure startup so deferred work runs **under** the splash owner.

Conceptually:

```text
Stable launch root mounts immediately
  ↓
Splash state starts timer immediately
  ↓
Deferred Supabase/theme/bootstrap tasks execute
  ↓
Underlying child updates as those tasks resolve
  ↓
Splash does not care
```

Do not delay mounting the splash until:

- Supabase is available;
- startup theme is loaded;
- stored session is checked;
- database work finishes;
- hydration starts/finishes.

### Implementation guidance

Move only the minimum startup work required for Flutter engine/widget construction before the splash owner.

Work that can safely happen after the first frame should remain deferred, but the splash owner must already be mounted while it occurs.

If the startup theme is not yet loaded:

- render the splash with a fixed splash-specific visual style independent of user theme;
- allow the underlying app placeholder to update when theme loading completes.

The splash should not need the user-selected theme to render.

---

# 11. Phase 4 — Canonical splash visual tokens

Create or retain one Flutter constant for the splash background:

```dart
const homePilotSplashBackground = Color(0xFFF9FCF8);
```

Place it in the most appropriate splash-specific location. Do not put it into unrelated general design tokens merely to avoid duplication.

Use it for:

- Flutter animated splash background;
- any Flutter launch bridge surface that can be exposed before/during the overlay;
- splash-specific system bar styling where appropriate.

Keep Android native resources at the same canonical value:

```text
#F9FCF8
```

Add static tests that verify:

- `flutter_native_splash.yaml` uses the expected color;
- Android `splash_background` uses the expected color;
- night splash resources intentionally match if light splash is the product requirement.

Do not require general app surfaces to use this color.

---

# 12. Phase 5 — Improve the underlying startup surface

Because the splash is fixed-duration, slow startup must remain understandable after the overlay disappears.

Audit all states that can be revealed after ~3.45 seconds.

Avoid revealing a visually dead blank screen for long-running startup.

Preferred hierarchy after splash removal:

1. authenticated routed application, if ready;
2. existing cloud hydration/restore UI, if active;
3. authentication/session-resolution UI, if needed;
4. a minimal startup placeholder only for very short unresolved bootstrap gaps.

If `_DeferredHomePilotBootstrap` can remain unresolved for several seconds, consider replacing a bare `ColoredBox` with a small dedicated startup surface that:

- uses normal app styling;
- does not imitate or restart the splash;
- does not pretend to know progress;
- is accessible;
- does not block startup work;
- does not add navigation logic.

Do not create a second branded splash masquerading as a loading screen.

---

# 13. Phase 6 — Clean up obsolete splash timing/bootstrap APIs

Search for legacy native-splash timing concepts.

Likely candidates include:

- `minimumNativeSplashDuration`
- `minimumSplashDuration`
- `remainingNativeSplashDuration(...)`

If they no longer have real behavioral meaning:

- delete them;
- delete dead constructor parameters;
- delete tests that only preserve obsolete contracts;
- update comments and names.

Do not retain a function returning `Duration.zero` merely to preserve an old architecture unless an external API requires it.

There should be one timing model:

```text
HomePilotSplashOverlay fixed presentation duration
```

Do not maintain a second unused “minimum native splash duration” concept.

---

# 14. Phase 7 — Keep the splash presentation component narrow

Audit `lib/homepilot_animated_splash_screen.dart` after the ownership refactor.

It should continue to have no dependency on:

- router providers;
- auth providers;
- startup providers;
- sync providers;
- database services;
- Supabase;
- permission education.

Keep the public API small.

A reasonable API remains conceptually:

```dart
HomePilotSplashOverlay(
  child: ...,
  displayDuration: ...,
  fadeOutDuration: ...,
)
```

Avoid adding:

```dart
isReady
authState
startupStatus
nextRoute
onNavigate
hydrationComplete
minimumDurationFromNativeLaunch
```

The overlay's job is to cover, animate, block input, and remove itself.

---

# 15. Phase 8 — Timer and lifecycle hardening

Review timer/controller behavior for:

- disposal;
- hot rebuilds;
- dependency changes;
- app lifecycle events;
- test pumping.

Requirements:

- display timer starts once in `initState`;
- it is not restarted from `didUpdateWidget`;
- it is not restarted from `didChangeDependencies`;
- fade begins once;
- final overlay removal occurs once;
- timers/controllers are canceled/disposed;
- no `setState` executes after dispose;
- child stays mounted for the entire overlay lifetime;
- child state is preserved after overlay removal.

Do not tie timer progression to an auth/startup provider.

---

# 16. Phase 9 — Reduced motion

Audit whether the current animation already respects reduced-motion settings.

Required behavior:

- `MediaQuery.disableAnimations == true` or the repo's equivalent reduced-motion policy should reduce/disable continuous decorative motion;
- accessibility should not require watching movement;
- splash lifetime may remain deterministic unless product requirements state otherwise;
- interaction blocking remains intact;
- fade may be shortened or replaced with immediate removal only if that matches the app's established reduced-motion policy.

Add a dedicated test if none exists.

The splash must not become semantically noisy merely because animation is disabled.

---

# 17. Phase 10 — Semantics and input behavior

Preserve/improve:

- `AbsorbPointer` or equivalent complete input blocking while splash is visible;
- no taps leaking through to the app;
- cosmetic progress excluded from semantics;
- no fake progress percentages announced;
- no repeated live-region announcements;
- splash artwork should not create unnecessary accessibility focus stops.

When the splash disappears:

- underlying controls become tappable immediately;
- focus should not be trapped in removed splash nodes.

Add regression coverage.

---

# 18. Phase 11 — Deep links and notification routing

The pure splash must not delay route processing artificially.

Verify:

1. application receives/queues the deep link or notification using existing logic;
2. underlying router may resolve/navigate while covered;
3. splash remains visually on top for its fixed duration;
4. when splash disappears, the correct destination is visible.

Do not make splash completion call `go`, `push`, `pushReplacement`, or similar navigation APIs.

Test at least one supported deep-link/notification startup path if a practical test seam already exists.

---

# 19. Phase 12 — Sign-in/sign-out regression

This is essential because the existing root topology is auth-sensitive.

Add tests proving:

### Case A — auth resolves before splash finishes

Timeline:

```text
t=0       splash mounts
t<3.2s    startup becomes authenticatedReady
t=3.2s    fade starts
t≈3.45s   splash gone
```

Assertions:

- only one splash state/lifetime;
- no animation restart;
- no second 3.2s period;
- authenticated app can update underneath.

### Case B — auth resolves after splash finishes

Timeline:

```text
t=0       splash mounts
t≈3.45s   splash gone
t>3.45s   authenticatedReady becomes true
```

Assertions:

- splash remains absent;
- switching to authenticated routing does not recreate it.

### Case C — sign out after application is running

Assertions:

- auth/startup content changes as designed;
- splash does not reappear.

### Case D — sign in again without process restart

Assertions:

- splash does not reappear.

---

# 20. Phase 13 — Theme and locale regression

Add or extend tests proving:

- theme changes while splash is visible do not restart the splash;
- theme changes after splash removal do not reinsert it;
- locale/RTL changes do not recreate it;
- splash layout remains valid in Arabic/RTL if direction affects layout;
- splash remains branded consistently regardless of dark/light user theme if the product intentionally uses a fixed light splash.

The splash may remain visually light in dark mode if this is intentional, but the transition should not flash through an unrelated surface.

---

# 21. Phase 14 — Widget test architecture

Keep existing isolated component tests, but add an app-level harness.

Create a focused test file such as:

```text
test/homepilot_splash_lifecycle_test.dart
```

or extend an appropriate existing startup test if that yields clearer ownership.

The harness should model the **real root branch transition**, not simply repump the same `HomePilotSplashOverlay`.

Recommended test controls:

- fake startup state notifier/provider;
- controllable authenticated-ready transition;
- controllable startup theme future;
- controllable deferred bootstrap future;
- short configurable splash durations for deterministic tests.

Do not use real 3.2-second waits for every widget test. Inject test durations while preserving production defaults.

---

# 22. Minimum required splash lifecycle tests

The final test suite should include at least:

1. Child is mounted immediately underneath splash.
2. Child state survives splash removal.
3. Splash blocks child input while visible.
4. Child receives input after removal.
5. Overlay disappears after configured display + fade.
6. Underlying child rebuild does not restart timer.
7. Startup state transition before fade does not restart timer.
8. Startup state transition after removal does not reinsert splash.
9. Pre-auth → authenticated router transition does not reinsert splash.
10. Sign-out does not reinsert splash.
11. Sign-in again does not reinsert splash.
12. Theme change does not reinsert splash.
13. Locale/RTL change does not reinsert splash.
14. Reduced-motion mode remains correct.
15. Narrow screen renders without overflow.
16. Short screen renders without overflow.
17. Large text scale renders without overflow.
18. Landscape or unusual aspect ratio renders without overflow, if Android orientation policy allows the test environment.
19. Deep-link/notification destination can resolve underneath splash without splash-owned navigation.
20. Slow underlying initialization does not prevent splash timer completion.

---

# 23. First-Flutter-frame regression tests

A pure widget test cannot prove Android-native frame timing, but it can prove the Flutter side of the contract.

Add test seams around the direct Flutter launch root.

### Test: delayed deferred initialization

Configure bootstrap initialization to remain unresolved longer than splash duration.

Immediately after pumping the root:

- splash must already be present;
- a plain startup background must not be the only visible launch content.

After splash duration:

- splash disappears;
- unresolved startup surface remains.

### Test: delayed startup theme

Delay the startup theme future.

Immediately:

- splash visible.

Before theme resolves:

- splash lifetime continues normally.

When theme resolves:

- underlying app updates;
- splash state does not restart.

This directly guards the “animated splash created too late” regression.

---

# 24. Golden/screenshot coverage

Optional but recommended if the current test environment supports stable rendering.

Create splash goldens for:

- typical phone;
- narrow phone;
- short phone;
- large text;
- RTL;
- reduced motion static state.

Do not overuse golden tests for timing/lifecycle logic. Lifecycle behavior belongs in widget tests.

---

# 25. Android native resource validation

Review:

```text
flutter_native_splash.yaml
assets/splash/*
android/app/src/main/res/drawable*
android/app/src/main/res/values*
android/app/src/main/res/values-night*
android/app/src/main/res/values-v31*
android/app/src/main/res/values-night-v31*
```

Requirements:

- legacy launch background references the correct generated splash resource;
- Android 12+ uses the intended Android 12 asset;
- background is `#F9FCF8`;
- night-mode behavior is intentional and tested;
- density-specific generated assets are present for all expected buckets;
- no stale old splash asset remains referenced;
- launch theme and normal theme handoff remains valid.

If splash generator configuration changes, regenerate using the repository's installed `flutter_native_splash` tooling rather than manually editing every generated bitmap.

Do not regenerate unrelated launcher icons.

---

# 26. Improve `startup_resources_test.dart`

Extend static validation to catch generated-resource drift.

Recommended assertions:

- expected splash density directories exist;
- expected `splash.png`/`android12splash.png` files exist where appropriate;
- night Android-12 variants exist if intentionally configured;
- source asset paths in YAML exist;
- generated launch XML references are valid;
- Android 12 style resource names match generated files;
- native splash color equals canonical expected hex;
- dark/night splash color intentionally equals expected hex;
- obsolete resource names are not referenced.

Where feasible, compare image dimensions/aspect assumptions rather than binary hashes so intentional regeneration does not create brittle tests.

---

# 27. System UI / edge-to-edge verification

`MainActivity` has its own full-canvas/system-bar policy. Splash code also applies system UI styling.

Static code alone is insufficient to prove a clean transition.

Manually/emulator-test at minimum:

- Android 10;
- Android 11;
- Android 12;
- one current Android API level supported by the project.

Check:

- status bar visibility;
- navigation bar visibility;
- light/dark icon appearance;
- background color;
- no vertical jump when Flutter takes over;
- no content shift caused by cutout/insets;
- no one-frame system-bar flash;
- splash logo does not jump significantly between native and Flutter phases.

Do not make broad `MainActivity` changes unless a reproducible splash transition defect is observed.

If changes are required, keep them API-specific and add comments explaining why.

---

# 28. Native → Flutter visual continuity verification

Use cold starts, not hot reload.

For each representative API level:

1. Force-stop the app.
2. Launch from launcher.
3. Record video or frame sequence.
4. Inspect:
   - native background;
   - native icon position/scale;
   - first Flutter frame;
   - animated icon position;
   - system bars;
   - fade into current application state.
5. Repeat in light/dark system mode.
6. Repeat with:
   - authenticated session;
   - signed-out session;
   - slow/offline network;
   - cloud restore/hydration if reproducible.

Acceptance:

- no blank app-background flash;
- no splash restart;
- no splash reappearance;
- no obvious background-color discontinuity;
- no duplicate branded splash sequence.

---

# 29. Startup performance

The fix should not make startup work serial.

Do not move deferred network/database work in front of the first Flutter frame merely to simplify ownership.

The correct approach is:

```text
mount stable splash owner early
+
run initialization underneath
```

not:

```text
finish initialization
+
mount splash
```

Measure/retain existing startup benchmarks.

If the root refactor increases first-frame latency materially, investigate before merging.

---

# 30. Monetization/provider ownership

Because the authenticated branch currently includes monetization bootstrap/provider behavior, verify the root refactor does not:

- initialize monetization twice;
- dispose/recreate monetization state unexpectedly;
- move ad initialization ahead of required consent/state;
- recreate ProviderScope/Riverpod containers;
- duplicate listeners;
- duplicate Sentry navigation observers.

Stable splash ownership must not be achieved by moving unrelated long-lived providers into incorrect lifecycle positions.

Preserve existing provider ownership unless a move is necessary and tested.

---

# 31. Router and navigator safety

After unifying the app root, test:

- back button;
- root navigator key;
- router provider identity;
- deep links;
- notification payload navigation;
- route observers;
- auth redirects;
- onboarding;
- restore flow;
- permission education overlay;
- modal routes/dialogs.

Pay special attention to any code using:

```dart
_rootNavigatorKey
Navigator.of(...)
context.go(...)
context.push(...)
routerProvider
```

Do not accidentally create two independent navigator stacks when embedding routing under a stable `MaterialApp`.

---

# 32. Permission education overlay ordering

HomePilot also has a permission education overlay.

Verify z-order intentionally.

Expected launch order should be conceptually:

```text
application content
  ↑
permission education overlay when eligible
  ↑
startup splash while splash is active
```

During the initial splash lifetime:

- splash should remain the top interaction blocker;
- permission education may initialize underneath but should not be tappable through splash;
- when splash disappears, permission education may appear normally if eligible.

Do not make permission education wait on splash unless necessary for presentation ordering; simple stacking should be sufficient.

Add one regression test if the two overlays can be active during the same launch.

---

# 33. Error behavior

If startup encounters an error while splash is visible:

- error state may prepare underneath;
- splash should still finish its fixed duration;
- after removal, user sees the real recoverable error UI.

Do not keep splash on screen indefinitely to hide startup errors.

Do not make splash own retry actions.

Test a fake startup error if an existing error-state harness exists.

---

# 34. Changelog and documentation repair

Audit `CHANGELOG.md` against actual commit history.

The previous review found that a 1.4.7 entry described the pure overlay behavior even though the route-driving splash still existed before the later isolation refactor.

Handle this carefully:

1. Check GitHub releases/tags if available.
2. Respect the repository's policy that Git history/releases are authoritative.
3. Do not fabricate historical release behavior.
4. If project policy allows correcting historical wording, update the 1.4.7 note so it does not claim behavior that did not exist.
5. Record the actual lifecycle fix under the correct current/next release.
6. If 1.4.8 is already shipped, put the new fix in the next release rather than silently pretending it shipped earlier.

Also update `HomePilot_pure_splash_ai_agent_plan.md` if it is intended to remain an architectural reference:

- mark which acceptance criteria are now implemented;
- document the single-owner rule;
- explicitly forbid splash duplication in root branches;
- document first-Flutter-frame ownership.

---

# 35. Code comments/documentation to add

At the stable splash owner, add concise architectural documentation similar to:

```text
The startup splash is presentation-only and process-scoped.
Its State must survive authentication/startup/root-content transitions.
Do not place additional HomePilotSplashOverlay instances in child branches.
```

At deferred bootstrap:

```text
Initialization is intentionally allowed to continue underneath the splash.
Do not delay splash mounting on this future.
```

Avoid large comments restating implementation details.

---

# 36. Suggested file-level change map

The exact patch depends on the current branch, but expected areas are:

## `lib/main.dart`

Likely changes:

- create one stable root application boundary;
- remove duplicate `HomePilotSplashOverlay` calls;
- place one overlay in the stable app builder/host;
- restructure startup/authenticated content switching so the splash state survives;
- move deferred bootstrap/theme resolution underneath the stable launch owner;
- remove obsolete splash timing parameters/functions;
- preserve router/navigation/provider ownership;
- optionally replace long-lived blank startup placeholder.

This is the most important file.

## `lib/homepilot_animated_splash_screen.dart`

Likely small changes only:

- centralize splash color;
- improve reduced motion if needed;
- add documentation;
- possibly make dependencies more explicit if hosting location changes;
- do not reintroduce startup/navigation coupling.

## `test/homepilot_splash_overlay_test.dart`

Retain component tests and add any missing component-level coverage.

## New/expanded lifecycle startup test

Recommended:

```text
test/homepilot_splash_lifecycle_test.dart
```

Test actual branch changes and timer non-restart.

## `test/startup_benchmark_test.dart`

Update only if the root seam changes or a benchmark would otherwise stop exercising real startup.

## `test/startup_resources_test.dart`

Expand Android generated-resource and canonical-color validation.

## `flutter_native_splash.yaml`

Change only if needed for resource consistency.

## Android resource files

Prefer generator output over manual bitmap edits.

## `CHANGELOG.md`

Correct release attribution and document the real fix under the appropriate version.

## `HomePilot_pure_splash_ai_agent_plan.md`

Update architectural status/acceptance notes if this document remains active.

---

# 37. Implementation sequence

Apply in this order.

## Step 1 — Write regression tests for current lifecycle defect

Before changing production topology, create a test that demonstrates:

- first splash is visible;
- app changes from startup root to authenticated root;
- current implementation creates/restarts splash.

The test should fail on current code and pass after refactor.

This proves the fix addresses the actual bug.

## Step 2 — Create stable splash ownership

Unify the application/splash root.

Do not yet clean unrelated code.

Make the failing lifecycle test pass.

## Step 3 — Move ownership earlier than deferred bootstrap/theme placeholders

Add delayed-bootstrap tests.

Refactor until the splash is mounted immediately on the Flutter launch path.

## Step 4 — Normalize splash color bridge

Introduce/use canonical Flutter splash color and update static resource tests.

## Step 5 — Remove stale timing architecture

Delete obsolete minimum-native-splash remnants.

## Step 6 — Add remaining lifecycle/accessibility/layout tests

Cover auth, theme, locale, input, slow startup, reduced motion.

## Step 7 — Run broad regression suite

Fix root/navigation/provider regressions.

## Step 8 — Android manual verification

Cold-start representative API levels.

## Step 9 — Documentation/changelog

Update only after code behavior is verified.

---

# 38. Acceptance criteria

The work is complete only when all applicable criteria pass.

## Architecture

- [ ] Exactly one production `HomePilotSplashOverlay` owner exists.
- [ ] Splash state survives pre-auth/startup → authenticated routing transition.
- [ ] Splash is mounted before deferred startup work that can extend past first Flutter frame.
- [ ] Splash owns no routing/auth/sync/bootstrap logic.
- [ ] No duplicate `MaterialApp` is introduced merely for splash context.
- [ ] Provider/router lifecycle remains correct.

## Behavior

- [ ] Splash displays once per process.
- [ ] Timer starts once.
- [ ] Startup transition before timeout does not restart timer.
- [ ] Startup transition after removal does not reinsert splash.
- [ ] Sign-in does not reinsert splash.
- [ ] Sign-out does not reinsert splash.
- [ ] Theme change does not reinsert splash.
- [ ] Locale change does not reinsert splash.
- [ ] Background/resume does not reinsert splash.
- [ ] Underlying app runs while covered.
- [ ] Splash leaves after fixed duration even if startup is slow.
- [ ] Startup errors become visible after splash leaves.

## Visual

- [ ] Native splash background is `#F9FCF8`.
- [ ] Flutter animated splash background matches.
- [ ] No visible app-background flash between native and animated splash.
- [ ] No duplicate branded splash sequence.
- [ ] No obvious system-bar flash.
- [ ] Layout does not overflow on supported constrained sizes.
- [ ] Reduced-motion behavior is acceptable.

## Interaction/accessibility

- [ ] Input cannot leak through splash.
- [ ] Input works immediately after splash removal.
- [ ] Decorative progress is not misleading to screen readers.
- [ ] Removed splash does not trap focus.
- [ ] Large text remains safe.

## Tests

- [ ] Existing splash component tests pass.
- [ ] New root-lifecycle regression tests pass.
- [ ] Startup resource tests pass.
- [ ] Startup benchmark tests pass or are intentionally updated.
- [ ] Full Flutter test suite passes.
- [ ] Static analysis passes.
- [ ] Formatting passes.

## Android

- [ ] Android 10 cold start verified.
- [ ] Android 11 cold start verified.
- [ ] Android 12 cold start verified.
- [ ] Current Android cold start verified.
- [ ] Light system mode verified.
- [ ] Dark system mode verified.
- [ ] Offline/slow startup verified on at least one API level.

## Documentation

- [ ] Changelog does not misattribute pure-overlay behavior.
- [ ] Splash architecture document states single-owner invariant.
- [ ] No stale route-driven splash documentation remains.

---

# 39. Validation commands

Use the repository's documented toolchain and scripts first.

At minimum, run equivalents of:

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test test/homepilot_splash_overlay_test.dart
flutter test test/homepilot_splash_lifecycle_test.dart
flutter test test/startup_resources_test.dart
flutter test test/startup_benchmark_test.dart
flutter test
git diff --check
```

If the new lifecycle test is given another filename, use that path.

For Android build verification, prefer the repository's existing production/build scripts and documented configuration rather than inventing credentials or `dart-define` values.

If generator configuration changes, run the repo-appropriate `flutter_native_splash` generation command and inspect the complete generated diff.

---

# 40. Review checklist for the final patch

Before declaring success, perform a code-review pass specifically looking for these failure patterns.

## Reject if any of these appear

- `HomePilotSplashOverlay` in more than one startup/auth branch.
- `Navigator.push*` inside splash code.
- `context.go(...)` inside splash code.
- splash timer restarted from `didUpdateWidget`.
- splash visibility bound to `authenticatedReady`.
- splash visibility bound to hydration completion.
- splash waits for network.
- splash waits for Supabase.
- splash waits for database initialization.
- a new global `bool splashShown` used as the only fix for incorrect ownership.
- nested `MaterialApp` introduced just to supply splash context.
- first Flutter frame still renders only `HkColors.appBackground` before splash construction.
- duplicate startup loaders that visually resemble a second splash.
- removal of error/startup UI merely to keep splash visible longer.

---

# 41. Preferred final state example

The exact code will differ, but the structural idea should resemble:

```text
HomePilot launch root
  └── stable Material application
      └── builder
          └── HomePilotSplashOverlay   ← one instance only
              └── startup content host
                  ├── deferred bootstrap state
                  ├── signed-out/auth state
                  ├── hydration state
                  └── authenticated routed app
```

The important feature is **identity**:

`HomePilotSplashOverlay` stays in the same location in the widget tree while only its child content evolves.

---

# 42. Optional improvement — isolate launch orchestration into a small class

`lib/main.dart` is very large. If the root refactor would otherwise make startup logic harder to maintain, extracting a small dedicated launch shell is reasonable.

Example conceptual names:

```text
HomePilotLaunchShell
HomePilotStartupRoot
HomePilotProcessRoot
```

Responsibilities may include:

- stable splash ownership;
- stable app inherited-widget boundary;
- selecting underlying startup/authenticated content.

It must not become a new business-state controller.

Do not extract unrelated startup services merely to create a “clean architecture” project during this fix.

---

# 43. Optional improvement — explicit splash lifecycle instrumentation

If HomePilot already has startup observability, add minimal events such as:

```text
startup_flutter_splash_mounted
startup_flutter_splash_fade_started
startup_flutter_splash_removed
```

Useful fields:

- elapsed milliseconds since process/startup stopwatch;
- build/version;
- platform/API level if already available through observability.

Do not log user identifiers or sensitive auth data.

This can help prove in production that the splash is not living for 6–7 seconds because of accidental restarts.

If adding instrumentation requires significant observability work, skip it.

---

# 44. Optional improvement — development assertion against duplicate owners

A debug-only guard can be considered after topology is corrected.

For example, a lightweight debug assertion could detect simultaneous duplicate launch splash hosts in the same process.

Do not rely on this as the fix.

The production design must remain correct without it.

---

# 45. Edge cases the AI agent must consider

- App launched while previously authenticated.
- App launched signed out.
- Stored session check slow.
- Supabase unavailable.
- Network offline.
- Cloud restore slow.
- Theme setting load slow.
- Theme setting corrupted/defaulted.
- Arabic/RTL.
- Large font scale.
- Reduced motion.
- Notification startup route.
- Deep link startup route.
- App backgrounded during splash.
- App resumed before splash finishes.
- App backgrounded after splash finishes.
- Auth state changes during splash.
- Auth state changes after splash.
- Startup exception during splash.
- Android 12 system splash behavior.
- Android 10/11 force-dark/fullscreen behavior.
- Edge-to-edge/cutout devices.

---

# 46. What success should look like to a user

### Fast authenticated startup

```text
Tap icon
→ native HomePilot splash
→ animated HomePilot splash continues seamlessly
→ fade
→ dashboard
```

### Slow authenticated startup

```text
Tap icon
→ native splash
→ animated splash
→ fade after fixed time
→ legitimate restore/hydration/startup UI
→ dashboard later
```

No second splash.

### Signed-out startup

```text
Tap icon
→ native splash
→ animated splash
→ fade
→ auth/welcome state
```

Signing in afterward must not show the launch splash again.

### Offline startup

```text
Tap icon
→ native splash
→ animated splash
→ fade
→ offline-capable/startup state
```

The splash must not wait for connectivity.

---

# 47. Final instruction to implementing agent

Treat the splash as a **visual layer with one process-scoped owner**, not as a startup phase.

The core bug is not that the animation is wrong. The core bug is that its state is attached to application branches whose identity changes during startup, and that the splash-owning tree is mounted after some deferred bootstrap placeholders.

Fix ownership first.

Preserve startup concurrency.

Preserve navigation behavior.

Prove the fix with tests that model the real `HomePilotApp` root transition.

Do not declare completion based only on isolated `HomePilotSplashOverlay` widget tests.

The final patch should make it structurally difficult for authentication, hydration, theme, routing, or provider rebuilds to cause a second splash lifetime.

<!-- END VERBATIM SOURCE: HomePilot_splash_full_fix_improvement_plan(1).md -->

---

# APPENDIX D — Original Unified Transient Feedback AI Agent Prompt

<!-- BEGIN VERBATIM SOURCE: homepilot_unified_feedback_ai_agent_prompt(1).md -->

# HomePilot Unified Transient Feedback System — AI Coding Agent Prompt

## Mission

Redesign and implement HomePilot's entire in-app transient feedback system so that **Done / completion, Move to Trash, Undo, save/update success, warnings, errors, progress/pending states, restore, and permanent-delete confirmations/results all use one polished, consistent Flutter-native feedback design language**.

This prompt is for the **HomePilot Flutter app only**.

**Do not modify or audit VersionDeck / `download-site/` as part of this task.**

Use the repository:

- `zuhak5/HomePilot`
- default branch: `main`
- audit baseline checked for this plan: commit `075cd6ff5c36bb9c05b03f10a20598310ecf000d`
- app version at that baseline: `1.4.8+34`

Before implementing, re-check the current `main` branch because it may have advanced beyond the baseline above. Preserve unrelated newer changes.

---

# Non-negotiable product decisions

1. **Keep Flutter-native feedback.**
   - Continue using Flutter `ScaffoldMessenger` / `SnackBar` as the transport unless a very small Flutter-native helper layer is needed.
   - Do **not** use Android native `Toast.makeText`.
   - Do **not** add `fluttertoast` or any third-party toast package.
   - Do **not** add a new feedback dependency unless there is an unavoidable technical reason, and if so stop and explain before adding it.

2. **One app-wide feedback design system.**
   - Every transient feedback state should feel like the same component family.
   - Different actions may use different semantic variants and behaviors; do not make every message literally identical.

3. **Every Move to Trash action must have Undo.**
   - Task -> Trash: Undo.
   - Asset/item -> Trash: Undo.
   - Room -> Trash: Undo.
   - Area -> Trash: Undo.
   - Do not leave the current Task-only Undo behavior.

4. **Permanent deletion is different from Move to Trash.**
   - "Delete forever" / permanent deletion must retain explicit confirmation.
   - After permanent deletion succeeds, show a non-undoable destructive result message.
   - Never display an Undo control for an operation that cannot be reliably reversed.

5. **Task completion / Done remains undoable.**
   - A completed task should use the unified actionable feedback bar with Undo.

6. **Do not move the FAB or bottom navigation when feedback appears.**
   - The approved placement concept keeps the existing Add task FAB exactly where it normally lives.
   - The feedback bar floats above existing bottom UI with a small deliberate gap.
   - The snackbar/feedback bar must not cause visible reflow or vertical jumping of the FAB or bottom navigation.

7. **Never stack multiple feedback bars vertically.**
   - Only one bar is visible at a time.
   - Rapid repeated actions should be batched/coalesced when their semantics are compatible.
   - Noncritical messages should not create a long visual queue.

8. **An active Undo bar is protected.**
   - A normal success/info/warning message must never call `hideCurrentSnackBar()` and destroy the user's remaining Undo opportunity.
   - Errors normally wait until the active Undo bar closes unless the error is caused by the Undo action itself or requires a blocking dialog.
   - Blocking/critical conditions should use the appropriate dialog/banner/screen state rather than forcibly replacing an Undo snackbar.

---

# Current repository findings to account for

The following was verified against the baseline commit and should be re-verified before editing.

## Existing core implementation

Current transient-feedback code is concentrated in:

- `lib/src/ui/components.dart`
- `lib/src/ui/app_theme.dart`
- `lib/src/core/services/feedback_messenger.dart`
- many call sites in `lib/main.dart`
- auth/account call sites in `lib/src/features/auth/presentation/account_screen.dart`
- tests in `test/widget_test.dart`

`lib/src/core/services/feedback_messenger.dart` currently defines:

- `hkRootScaffoldMessengerKey`

`MaterialApp.router` in `lib/main.dart` is wired with:

- `scaffoldMessengerKey: hkRootScaffoldMessengerKey`

Preserve the root-messenger capability because feedback is app-wide and can outlive local route contexts.

## Current generic toast API

`lib/src/ui/components.dart` currently has:

- `kToastDuration = 2s`
- `kActionToastDuration = 3s`
- `kErrorToastDuration = 4s`
- `enum HkToastSeverity { normal, error }`
- `showToast(...)`
- `showUndoToast(...)`
- `showTaskMovedToTrashSnackBar(...)`
- `_showUndoSnackBar(...)`
- `TaskDeletionSnackBarContent`
- `_UndoCountdownBar`

Important current behavior:

- `showToast()` calls `messenger.hideCurrentSnackBar()` before showing a new snackbar.
- Therefore a generic toast can interrupt an active Undo snackbar.
- `HkToastSeverity.error` currently changes duration but does not provide a distinct error-specific visual design.
- `showUndoToast()` / task-delete Undo snackbars are queued by `ScaffoldMessenger` rather than deliberately managed by a HomePilot feedback policy.
- The task-delete snackbar currently has a countdown/progress implementation ticking roughly every 250 ms.

## Current theme support

`lib/src/ui/app_theme.dart` already contains useful semantic tokens:

- primary green
- danger/error
- warning
- info
- light/dark `ColorScheme`
- `HkSnackBarColors`
- SnackBar theme with floating behavior

Reuse and extend the existing theme system rather than introducing unrelated hardcoded colors.

`HkSnackBarColors` currently exposes roughly:

- surface
- foreground
- action
- progressTrack
- progressFill

The redesigned system should evolve this into a complete semantic feedback palette or otherwise map semantic variants to existing `ColorScheme` / HomePilot theme tokens.

## Current destructive-action inconsistency

Current `lib/main.dart` behavior:

- Task -> Trash uses `showTaskMovedToTrashSnackBar(...)` with Undo.
- Asset/item -> Trash uses generic `showToast(...)` only.
- Room -> Trash uses generic `showToast(...)` only.
- Area -> Trash uses generic `showToast(...)` only.

Current repository APIs already provide restore operations:

- task: `restorePlan(...)`
- asset/item: `restoreAsset(...)`
- room: `restoreRoom(...)`
- area: `restoreArea(...)`

The data layer also already implements Trash/restore cascading behavior for area/room/asset relationships. Reuse these repository APIs rather than inventing UI-only fake Undo.

## Current task completion behavior

Task completion already uses an Undo snackbar and currently shows:

- `Task completed.`
- Undo action
- on Undo: repository undo + reminder refresh
- then `Completion undone.`

Preserve functional correctness while moving it to the unified feedback design.

## Current permanent-delete behavior

The Trash screen already distinguishes restore and "delete forever" flows for:

- areas
- rooms
- assets/items
- tasks

Permanent deletion uses confirmation, then repository delete calls. Preserve confirmation and migrate the post-operation feedback to the new visual system.

## Current feedback call-site inventory

Re-audit all call sites, not just this list. At the baseline, generic feedback spans at least:

- theme/settings updates
- search index rebuild
- missing/no-longer-available task errors
- permission state messages
- language update failures
- device/weather location feedback
- approximate reminder timing warning
- notification settings/test reminder feedback
- backup create/restore/export/inspection errors
- photo saved / photo save failure
- snooze
- skip current cycle
- postpone
- enable/disable task
- reminder scheduling errors
- task completion / completion Undo
- task Trash / restore
- asset/item Trash
- room Trash
- area Trash
- reward/ad states
- offline draft messages
- editor save failures
- task creation
- account/auth success/failure
- nickname update
- Trash-screen restore/permanent-delete results

Search at minimum for:

- `hk_ui.showToast(`
- `showToast(`
- `showUndoToast(`
- `showTaskMovedToTrashSnackBar(`
- `showSnackBar(`
- `SnackBar(`
- `HkToastSeverity`
- `ScaffoldMessenger`

After migration, production code should not contain ad-hoc transient SnackBars outside the unified feedback layer.

## Existing tests

`test/widget_test.dart` currently tests:

- normal/action/error durations
- generic toast replacement
- task-deletion semantic colors
- task-deletion countdown
- task-deletion snackbar queue behavior
- narrow screen / large text behavior
- task completion Undo timing/disappearance

These tests must be updated to reflect the new contract.

In particular, the existing "task deletion snackbars queue undo callbacks" expectation should be replaced by deliberate batching/coalescing behavior.

## Existing tactile/audio action feedback

`lib/src/core/services/action_feedback_service.dart` already provides:

- `playCreated()`
- `playCompleted()`
- `playDeleted()`
- haptic + sound behavior

Keep it. Integrate it cleanly with the new visual feedback rules. Do not duplicate haptics or sounds accidentally when batching.

## Localization

The app currently has English and Arabic ARB localization, including keys such as:

- `undo`
- `taskCompleted`
- `completionUndone`
- `taskMovedToTrash`
- `nameMovedToTrash(...)`
- `nameRestored(...)`
- `nameDeletedForever(...)`

Any new user-facing strings must be localized in both English and Arabic and generated through the existing localization workflow. No hardcoded English in production feedback components.

---

# Target UX / visual design

Use the approved feedback-bar concept as the visual direction.

## Overall composition

The feedback bar should be a polished floating surface with:

- rounded HomePilot-style corners
- subtle elevation/shadow
- semantic leading icon in a compact circular/tinted container
- primary message with strong readable hierarchy
- optional secondary/supporting text
- optional trailing action, such as `Undo` or `Retry`
- bottom progress/timer line for timed feedback
- for Undo feedback, an optional compact numeric countdown indicator
- theme-aware colors in both light and dark modes
- RTL-safe directional layout
- no visual collision with FAB, bottom navigation, bottom action bars, safe areas, or keyboard

Do not blindly hardcode the generated mockup's exact pixels/colors. Use HomePilot design tokens and semantic theme colors.

## Placement

### Mobile screens with bottom navigation and/or FAB

- Keep the FAB in its normal position.
- Keep the bottom navigation in its normal position.
- Place the feedback bar **above the highest bottom obstruction**.
- Target approximately `12–16dp` visual gap between the feedback bar and the FAB/bottom action surface.
- Maintain normal horizontal HomePilot gutter margins.
- Do not resize or translate the FAB in response to feedback.

### Task screens

The code currently has task-route-specific bottom offset logic such as:

- bottom nav clearance
- task FAB clearance
- task detail action bar clearance
- safe area

Consolidate this behavior into the unified placement logic instead of maintaining one-off task-delete positioning.

### Keyboard

If the keyboard is visible, feedback must remain above `viewInsets.bottom` and remain usable.

### Wider layouts

Preserve the existing intent of reserving horizontal space when a wide-layout FAB would otherwise collide with the feedback bar. Prefer directional margins and RTL-safe calculations.

---

# Feedback taxonomy

Implement a small explicit model instead of the current `normal/error` distinction.

Recommended conceptual split:

## Semantic tone

Use something equivalent to:

- `neutral`
- `info`
- `success`
- `warning`
- `error`
- `destructive`

## Behavior/mode

Use something equivalent to:

- `passive`
- `actionable`
- `undoable`
- `progress`

The exact Dart names may differ, but keep semantic meaning separate from interaction behavior.

Do not overload one enum so badly that `error`, `undo`, `progress`, and `success` become mutually exclusive concepts.

---

# Required variants

## 1. Undoable completion / Done

Example:

- icon: completion/check
- title: `Task completed.`
- optional secondary line only when useful
- `Undo`
- 5-second default Undo window
- countdown/progress
- completion tone should use HomePilot success semantics

If several tasks are completed rapidly and the inverse operation is safe to batch:

- one visible bar
- e.g. `3 tasks completed.`
- one Undo restores/undoes the whole current completion batch
- timer resets when another compatible completion joins the batch

Do not batch if the underlying completion controller cannot reliably undo multiple completions. If necessary, first make the undo model explicitly support multiple completion tokens/results rather than pretending one callback can undo arbitrary history.

## 2. Move to Trash

All of these must use the same Undo behavior:

- task
- asset/item
- room
- area

Single-item examples:

- `Task moved to Trash.`
- `Item moved to Trash.`
- `Room moved to Trash.`
- `Area moved to Trash.`

Use the approved visual hierarchy:

- Trash icon
- message
- optional supporting text such as `You can undo this action.`
- Undo
- countdown
- progress line

Default Undo window: **5 seconds**.

### Rapid Trash batching

Do not show or vertically stack several Trash bars.

When several compatible Trash actions occur during the same active Undo window:

- keep one visible Trash feedback bar
- add each operation to a current Trash batch
- reset the Undo deadline to 5 seconds after the newest operation
- update count/message in place or with minimal non-disruptive animation
- Undo restores all operations in the current batch exactly once

Copy rules:

- same entity type: use a type-aware plural when possible, e.g. `3 tasks moved to Trash.`
- mixed entity types: use `3 items moved to Trash.` or a better localized generic equivalent
- do not put long individual object names into the primary batch message
- if one item only, generic entity type wording is preferred over a long dynamic name for layout stability

Undo callbacks should execute in a dependency-safe order. Prefer reverse operation order (LIFO) unless repository semantics require a different explicit ordering.

If one undo in a batch fails:

- do not silently claim the whole batch was restored
- complete the operations that can safely complete
- surface one clear error result
- log sufficient diagnostic context without leaking sensitive data
- avoid calling the same undo callback twice

## 3. Passive success

Examples:

- Task created.
- Photo saved.
- Backup created.
- Backup restored.
- Weather location updated.
- Notification settings updated.
- Nickname updated.
- Signed out.

Behavior:

- consistent compact feedback surface
- success/info semantic icon
- no Undo unless a reliable inverse is explicitly implemented
- around 2–3 seconds
- may use a subtle timer line
- numeric countdown is not necessary for passive messages

## 4. Warning

Examples:

- approximate reminder timing
- degraded-but-continued behavior
- nonfatal configuration limitations

Behavior:

- warning icon/tone
- concise message
- optional action only when meaningful
- approximately 4 seconds or context-dependent
- do not style warnings as errors

## 5. Error

Examples:

- save failure
- restore failure
- reminder setup failure
- undo failure
- location failure

Behavior:

- visually distinct error treatment
- error icon/tone
- longer duration, approximately 4–6 seconds
- optional `Retry` only when retry is safe and idempotent
- no fake Undo
- should replace stale passive info when no protected Undo is active
- should not interrupt an unrelated active Undo window

Current `HkToastSeverity.error` is insufficient because it mainly changes duration. Replace this with true semantic styling.

## 6. Progress / pending

Examples that may benefit:

- backup restore
- backup export when there is an actual meaningful wait
- rewarded-ad loading/verifying
- sync/reconciliation states where transient progress is appropriate

Behavior:

- persistent or explicitly controlled lifetime
- indeterminate progress/spinner when duration is unknown
- no countdown
- update the existing bar in place when possible
- transition into success/warning/error instead of hiding one bar and immediately flashing a different unrelated bar

Do not use transient progress feedback when an existing screen-level progress indicator already communicates the operation better.

## 7. Permanent destructive result

After a confirmed permanent delete:

- show a non-undoable destructive result such as `Deleted permanently.`
- no Undo
- concise duration
- retain confirmation before the destructive operation

---

# Queue, priority, batching, and replacement policy

Build a deliberate coordinator instead of relying accidentally on `ScaffoldMessenger`'s default queue.

Only one visual feedback bar should be visible.

## Priority contract

Use a policy equivalent to:

1. blocking UI (dialogs/screens) — outside this coordinator
2. active Undo/actionable feedback — protected
3. errors
4. warnings
5. success/info
6. low-value status noise

## While Undo is active

- compatible new Undo action -> merge into the active batch where safe
- incompatible Undo action -> do not visually stack; queue as a separate actionable batch or use another well-defined policy
- passive success/info -> keep only the latest useful pending passive message; do not pile up
- warning -> queue latest meaningful warning
- unrelated error -> queue immediately after protected Undo
- Undo callback failure -> close/resolve the active action state and show the error promptly

## Passive-message coalescing

Avoid long queues.

Examples:

- several rapid settings confirmations can collapse to the latest useful message
- loading -> verifying -> success should update/replace the same logical feedback flow rather than creating three queued snackbars
- duplicate identical messages within a short debounce window should be dropped or refreshed rather than duplicated

## Batching scope

Batch only when the semantics are clearly compatible.

Required:

- rapid Move-to-Trash operations -> Trash batch

Recommended if underlying undo support is robust:

- rapid task completions -> completion batch

Do not blindly batch unrelated operations into a confusing `5 changes made` Undo unless the exact inverse semantics are reliable and understandable.

---

# Architecture requirements

Do not keep expanding `components.dart` into an even larger monolith.

Prefer a small dedicated feedback module, for example:

```text
lib/src/ui/feedback/
  feedback_model.dart
  feedback_coordinator.dart
  feedback_bar.dart
  feedback_placement.dart
```

Names may differ.

Keep the root messenger key where appropriate, but centralize behavior.

## Suggested model

Create a request/event type carrying concepts similar to:

```dart
HkFeedbackRequest(
  id: ...,
  tone: ...,
  mode: ...,
  message: ...,
  supportingText: ...,
  icon: ...,
  duration: ...,
  actionLabel: ...,
  onAction: ...,
  aggregationKey: ...,
  dedupeKey: ...,
)
```

Undoable events should carry explicit undo metadata rather than pretending every generic `SnackBarAction` is equivalent.

## Coordinator responsibilities

The coordinator should own:

- active feedback
- active Undo batch
- batching rules
- pending error/warning/passive state
- timer/deadline
- timer reset
- dismiss reason
- lifecycle safety
- exactly-once action callbacks
- root `ScaffoldMessenger` interaction
- deduplication
- progress-state updates
- protected Undo policy

The widget should render state; it should not own business operations beyond invoking provided callbacks.

## SnackBar transport

Prefer retaining Flutter `SnackBar` / `ScaffoldMessenger`.

The visual content can be a custom HomePilot widget inside the SnackBar to get full control over:

- icon
- two-line copy
- pill-style action
- countdown ring
- progress line

Do not depend on the default `SnackBarAction` layout if it prevents matching the approved design.

If the standard SnackBar duration mechanism makes timer reset/batching impossible without flicker, implement lifetime control in the coordinator while still using a Flutter-native SnackBar surface. Do not jump to a third-party overlay library.

Any manual lifetime implementation must be tested for route changes, disposal, root messenger behavior, and accessibility.

---

# Accessibility requirements

This is mandatory, not polish.

1. Screen reader should announce the important state once, e.g.:
   - `Task moved to Trash. Undo available.`
   - `Task completed. Undo available.`
   - `Could not save task.`

2. Do **not** announce countdown updates every 250 ms / every second.
   - Exclude visual timer text/progress from repeated live-region announcements.

3. Action targets:
   - at least 48x48 logical-pixel usable tap target where practical
   - clear focus state
   - keyboard/switch-access usable

4. Do not rely on color alone.
   - semantic icon + copy + color

5. Large text:
   - support at least the app's current tested large-text scale and ideally 200%
   - no RenderFlex overflow at ~320dp width
   - allow wrapping before shrinking critical text

6. RTL:
   - use `EdgeInsetsDirectional`
   - trailing/leading behavior must mirror correctly
   - countdown/action grouping must remain readable in Arabic

7. Accessible navigation / timeout:
   - review `MediaQuery.accessibleNavigation`
   - actionable Undo feedback must not become impossible to use because of a short forced timeout
   - when accessible navigation is enabled, prefer a substantially extended or non-auto-expiring actionable bar with an explicit dismiss path
   - document and test the exact policy

8. Reduced motion:
   - use the existing HomePilot reduced-motion conventions
   - avoid decorative entrance/count animations when reduced motion is requested

---

# Animation / interaction polish

Keep motion subtle.

Recommended:

- floating bar entrance/exit using standard Snackbar motion or a restrained fade/slide
- count/message updates should not re-run a large entrance animation
- countdown line animates smoothly enough to read but does not trigger rebuilds across the whole screen
- optional numeric seconds may update once per second visually
- internal progress can tick more frequently if needed, but isolate rebuilds to the feedback component
- no glowing/pulsing attention effects
- no layout jump of surrounding screen UI

---

# Haptic/audio policy

Preserve `HkActionFeedbackService`.

Suggested mapping:

- create -> existing light feedback
- complete -> existing completion haptic/sound
- Trash -> existing delete haptic/sound

For batches:

- play action feedback when the user performs each underlying action, not repeatedly just because the batch UI count redraws
- do not replay delete/complete sound on timer reset
- Undo may use light haptic if consistent with app behavior, but do not add noisy audio without an existing convention

---

# Localization plan

Add localized feedback strings as needed to both:

- `lib/l10n/app_en.arb`
- `lib/l10n/app_ar.arb`

Prefer ICU plurals for counts.

Needed concepts may include:

- `{count} tasks moved to Trash.`
- `{count} rooms moved to Trash.`
- `{count} items moved to Trash.`
- `{count} areas moved to Trash.`
- `{count} items moved to Trash.` for mixed types
- `{count} tasks completed.`
- `You can undo this action.`
- generic progress/result copy only where existing strings are inadequate

Do not manually edit generated localization Dart files unless the repository's normal localization generation workflow requires it. Use the normal generator.

Check Arabic plural behavior, grammar, and RTL layout rather than assuming English plural logic.

---

# Migration plan

## Phase 0 — re-audit current main

Before changes:

1. read current `main`
2. record current commit SHA
3. search all feedback APIs/call sites
4. confirm no newer feedback refactor already landed
5. confirm exact Flutter version in `pubspec.yaml`
6. confirm all current Trash/restore repository methods
7. confirm current task-completion undo contract
8. confirm current tests

Do not overwrite unrelated recent work.

## Phase 1 — build the feedback foundation

Implement:

- semantic feedback model
- unified renderer
- coordinator
- placement resolver
- theme tokens/extensions
- timer/deadline ownership
- protected Undo behavior
- batching framework
- dedupe/coalescing

Keep compatibility wrappers temporarily if that allows smaller safe commits.

## Phase 2 — implement the approved visual design

Build the polished HomePilot feedback bar.

Test:

- light
- dark
- narrow
- large text
- Arabic RTL
- with/without action
- with countdown
- with progress
- with keyboard
- with bottom nav
- with Add task FAB
- task detail bottom action bar

Critical visual acceptance:

**The Add task FAB's position before and after showing feedback must be unchanged.**

## Phase 3 — unify all Move-to-Trash flows

Migrate:

- task
- asset/item
- room
- area

Each must:

1. perform the current repository Trash operation
2. preserve reminder/search/index side effects
3. emit delete haptic/audio exactly as intended
4. register its real restore callback in the Undo batch
5. show the unified Trash bar
6. restore correctly on Undo
7. refresh reminders/search/index as required by that entity
8. not show a redundant generic `moved to trash` toast

Implement rapid Trash batching.

## Phase 4 — migrate task completion

Replace the existing completion snackbar with the unified completion bar.

Preserve:

- completion result validation
- streak refresh behavior
- reminder refresh
- current task feedback animation/haptics
- actual completion Undo semantics
- reward flow

Ensure reward/passive messages cannot interrupt the completion Undo window.

Evaluate whether multiple task completions can safely batch. Implement only if the controller/repository provides deterministic multi-Undo support.

## Phase 5 — permanent deletion / restore results

Migrate Trash-screen operations:

- restore area/room/item/task
- delete forever area/room/item/task

Keep confirmation dialogs for permanent deletion.

Use:

- success feedback for restore
- non-undoable destructive result feedback for permanent delete
- error feedback when operations fail

## Phase 6 — migrate the rest of the app

Replace all old transient call sites with explicit semantic variants.

Classify each call, do not mechanically map everything to `success`.

Examples:

### info/success
- search rebuilt
- location updated
- notification settings updated
- backup created/restored
- photo saved
- task created
- nickname updated
- signed out

### warning
- approximate reminder timing
- degraded-but-continued states

### error
- theme/language/location errors
- backup errors
- photo error
- task update errors
- reminder errors
- save/editor errors
- Undo failure

### progress
- only operations where transient progress is actually useful

### actionable
- only when there is a real action such as Retry/Undo

Also review whether any existing message is redundant because the screen itself already gives clear persistent feedback. Remove low-value toast spam where appropriate.

## Phase 7 — remove/deprecate obsolete API

Once migration is complete:

- remove or deprecate `HkToastSeverity`
- remove task-specific snackbar rendering
- remove generic `hideCurrentSnackBar()` replacement behavior
- remove one-off queue assumptions
- keep only thin compatibility wrappers if still required by tests/legacy code, with explicit TODO or deprecation plan

Do not leave two competing feedback systems.

## Phase 8 — documentation

Add a short developer document describing:

- when to use each feedback variant
- duration defaults
- Undo policy
- batching policy
- queue/priority policy
- placement
- accessibility
- examples
- permanent delete vs Trash
- how to add a new feedback message safely

Suggested path:

- `docs/development/transient-feedback.md`

---

# Required tests

Add focused unit/widget tests. Avoid relying only on screenshots/goldens.

## Core coordinator tests

1. passive -> passive replacement/coalescing
2. error replaces stale passive when no Undo is active
3. passive does not interrupt active Undo
4. unrelated error does not destroy active Undo
5. Undo callback executes once
6. double-tap Undo does not execute twice
7. expiration executes finalize only when applicable
8. action tap prevents finalize
9. duplicate event dedupe
10. progress update changes in place
11. timer reset on compatible batch append
12. stale timers cannot close a newer feedback entry

## Trash batching tests

1. one task Trash -> one Undo bar
2. asset Trash -> Undo restores asset
3. room Trash -> Undo restores room
4. area Trash -> Undo restores area
5. two rapid task Trash events -> one visible bar, count 2
6. mixed Trash types -> one generic mixed-count message
7. newest Trash event resets the 5-second deadline
8. Undo restores all batch members once
9. batch Undo callbacks run in defined order
10. a failed restore produces error feedback and does not claim total success

## Task completion tests

1. completion -> completion bar + Undo
2. passive reward/result message cannot interrupt completion Undo
3. Undo restores completion
4. Undo failure -> error bar
5. if completion batching is implemented, test multiple completion tokens explicitly

## Placement tests

Measure widget positions.

1. Add task FAB Y-position before feedback
2. Add task FAB Y-position while feedback is visible
3. values must be equal within normal test precision
4. bottom navigation also does not move
5. feedback does not overlap FAB
6. feedback does not overlap bottom nav
7. task-detail bottom action bar is respected
8. keyboard is respected
9. safe-area inset is respected
10. wide-layout trailing FAB is respected

## Visual/semantic tests

1. correct semantic tone colors in light theme
2. correct semantic tone colors in dark theme
3. error is visually distinct from success
4. warning is visually distinct from error
5. no color-only state communication
6. Arabic RTL
7. 320px-ish narrow width
8. 1.8x+ text scale
9. no overflow
10. action remains reachable
11. countdown is not repeatedly exposed to semantics
12. accessible-navigation timeout policy

## Regression searches

After implementation, verify:

- no Android native Toast usage
- no third-party Flutter toast package
- no production direct `showSnackBar` outside the unified feedback layer unless explicitly justified
- no remaining `showTaskMovedToTrashSnackBar`
- no remaining Task-only Trash Undo logic
- no old generic `hideCurrentSnackBar()` policy that can kill Undo

---

# Acceptance criteria

The task is complete only when all of the following are true.

## Functional

- [ ] Task -> Trash has Undo.
- [ ] Asset/item -> Trash has Undo.
- [ ] Room -> Trash has Undo.
- [ ] Area -> Trash has Undo.
- [ ] Task Done/completion has Undo.
- [ ] Permanent delete still requires confirmation and has no fake Undo.
- [ ] Real restore callbacks are used.
- [ ] Reminder/search/index side effects remain correct after Trash and Undo.
- [ ] Undo callbacks are exactly-once.
- [ ] Rapid Trash actions batch into one visible feedback bar.
- [ ] Batch timer resets correctly.
- [ ] Normal messages cannot interrupt active Undo.
- [ ] No vertical snackbar stacking.

## UI

- [ ] All transient feedback uses one design family.
- [ ] Completion, Trash, success, warning, error, progress, and permanent-delete result are visually distinguishable.
- [ ] Approved dark floating-surface style is represented through theme-aware HomePilot tokens.
- [ ] Semantic leading icon is present where useful.
- [ ] Undo/action treatment is polished and clear.
- [ ] Timed actionable feedback includes progress/countdown.
- [ ] Add task FAB does not move.
- [ ] Bottom navigation does not move.
- [ ] Feedback placement is compact and deliberate, roughly 12–16dp from the nearest bottom obstruction.
- [ ] Light/dark/RTL/large-text layouts work.

## Architecture

- [ ] No Android native Toast.
- [ ] No third-party toast package.
- [ ] Root ScaffoldMessenger remains supported.
- [ ] One coordinator owns queue/batch/priority behavior.
- [ ] `components.dart` is not made substantially more monolithic; feedback is split into dedicated files where practical.
- [ ] Old `normal/error` severity architecture is replaced or clearly deprecated.
- [ ] No duplicate transient-feedback systems remain.

## Accessibility

- [ ] Screen readers get concise announcements.
- [ ] Countdown does not chatter every tick.
- [ ] Action target is accessible.
- [ ] Color is not the only state signal.
- [ ] Accessible-navigation timeout behavior is safe.
- [ ] Reduced motion is respected.

## Quality

- [ ] `dart format` passes.
- [ ] `flutter analyze` passes.
- [ ] targeted widget/unit tests pass.
- [ ] full relevant test suite passes.
- [ ] localization generation is clean.
- [ ] no unrelated product behavior changed.

---

# Implementation constraints

- Favor small cohesive commits or logical patches.
- Do not rewrite large unrelated sections of `main.dart`.
- Preserve current business logic and repository semantics.
- Do not silently change Trash into delayed deletion; current operations can remain immediate soft-delete with a temporary Undo opportunity.
- Do not delay permanent deletion behind a snackbar timer.
- Do not introduce global mutable state without a testable lifecycle.
- Be careful with route changes while an Undo batch is active.
- Be careful with a context becoming unmounted; prefer root messenger/coordinator state for presentation, but execute business callbacks safely.
- Be careful with stale timers and asynchronous callbacks.
- Do not let a previous snackbar's close callback finalize a newer batch.
- Do not log object names/user content unnecessarily in diagnostics.
- Preserve Sentry/error handling conventions already used by HomePilot.

---

# Suggested API direction

The exact API can differ, but aim for calls that communicate intent clearly.

Example conceptual calls:

```dart
HkFeedback.showSuccess(
  context,
  message: context.l10n.taskCreated,
);

HkFeedback.showWarning(
  context,
  message: context.l10n.approximateReminderTimingWarning,
);

HkFeedback.showError(
  context,
  message: failureMessage,
  retry: safeRetryCallback,
);

HkFeedback.showUndoable(
  context,
  aggregationKey: 'task-complete',
  tone: HkFeedbackTone.success,
  message: context.l10n.taskCompleted,
  onUndo: undoCompletion,
);

HkFeedback.addTrashUndo(
  context,
  entityType: HkTrashEntityType.room,
  onUndo: restoreRoom,
);
```

Prefer a clear semantic API over hundreds of ad-hoc `showToast(content: Text(...))` calls.

---

# Agent workflow

1. Re-audit current GitHub/main.
2. Summarize current implementation and any differences from this baseline.
3. Implement the feedback foundation.
4. Add/adjust tests for foundation before broad migration.
5. Migrate all Trash flows and verify Undo.
6. Migrate task completion.
7. Migrate remaining feedback call sites by semantic category.
8. Add localization.
9. Add placement/accessibility tests.
10. Remove obsolete API.
11. Add developer docs.
12. Run formatting, analysis, localization generation, targeted tests, and the full relevant Flutter test suite.
13. Provide a final implementation report containing:
    - files changed
    - architecture summary
    - migration count / remaining old call sites (must be zero unless justified)
    - tests run and results
    - any deliberate deviations from this prompt
    - screenshots or widget-tree evidence for key layouts if available

Do not stop after building only the component. The goal is an **app-wide migration and behavior policy**, not a one-off prettier Task snackbar.

<!-- END VERBATIM SOURCE: homepilot_unified_feedback_ai_agent_prompt(1).md -->


---

# END OF MASTER PROMPT

Implement the normalized master program and use the full verbatim appendices for detail.

Do not stop after planning.

Do not knowingly preserve a defect because an old test encodes it.

Do not sacrifice HomePilot's privacy, offline-first behavior, reward security, account-deletion security, release controls, accessibility, or localization in order to reduce implementation scope.

The desired end state is a HomePilot build in which startup is deterministic, capabilities are truthful, feedback is coherent, monetization is lifecycle/consent-safe, Google account handling is privacy-correct, the Play release path is production-ready, and every change is backed by evidence.
