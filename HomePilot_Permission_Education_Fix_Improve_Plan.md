# HomePilot Permission Education / Permission Onboarding — Full Fix & Improvement Plan

> **Historical plan:** This baseline-specific proposal is retained for traceability. It is not the current permission contract or evidence of implementation. Current behavior is defined by the permission domain/controller/gateway sources, their tests, `docs/reference/routes-and-permissions.md`, and `PRIVACY.md`.

**Repository:** `zuhak5/HomePilot`  
**Baseline reviewed:** `main`  
**Application baseline:** `1.4.3+28`  
**Plan status:** Implementation-ready engineering plan  
**Scope:** Everything directly or materially related to the Permission Education / permission onboarding flow, including location, weather, notifications, exact alarms/reminders, Settings re-entry, persistence/sync, routing, privacy, accessibility, localization, testing, observability, migrations, rollout, and documentation.

---

## 1. Executive summary

HomePilot currently has a real, integrated three-step permission education flow:

1. Location
2. Notifications
3. Exact alarms/reminders

The flow is presented as a root `OverlayEntry` over the Dashboard and is coordinated mainly from `lib/main.dart`, while the visual implementation lives in `lib/src/ui/permission_education.dart`.

The existing implementation is functional and already covers important cases: first-visit education, OS permission checks, permanently denied states, opening system Settings, lifecycle refresh after returning from Settings, skipping granted/unavailable permissions, reduced-motion support, English/Arabic localization, and widget tests.

The next iteration should not be treated as a visual polish pass. The most important work is architectural, privacy-related, device-scope correctness, contextual permission design, failure isolation, and clarity of user intent.

### Highest-priority issues to fix

1. **Permission education completion is account-synced even though OS permissions are device-specific.**  
   `permission_education_seen_v2` is in the synchronized `user_setting` allowlist. A user can complete education on one device and then sign in on another device where the OS permissions are still missing, but the synced education flag can suppress the first-visit education there.

2. **`Not now` and the close/X behavior effectively suppress future automatic education too aggressively.**  
   The current final completion path persists the education as seen. A user who skips all permissions can therefore permanently lose contextual help unless they manually reopen the setup from Settings.

3. **Exact-alarm permission is requested as part of the default onboarding sequence even when the user may not need precise alarms.**  
   Exact-alarm access is special Android access and should follow least-privilege design. It should be requested only when exact timing is actually enabled or required.

4. **Location permission is framed as necessary for local weather, but HomePilot already supports manual location selection.**  
   Manual city/location selection should be a first-class onboarding choice, allowing weather without device-location permission.

5. **The location privacy copy says “approximate coordinates,” while the implementation sends coordinates formatted to five decimal places.**  
   Low-accuracy acquisition helps, but five decimal places do not meaningfully quantize the coordinate. The product should either reduce precision before persistence/transmission or update the disclosure.

6. **Permission orchestration is embedded in the Dashboard.**  
   This creates coupling between navigation, overlay lifecycle, OS permissions, weather side effects, notification side effects, and UI state. A dedicated controller/service layer is needed.

7. **Post-grant network work can delay onboarding progression.**  
   Location grant can trigger position retrieval, reverse geocoding, weather refresh, and notification rescheduling. Permission progression should not be blocked by external network latency.

8. **The Step 1 copy promises seasonal task recommendations, but the audited implementation does not currently expose a connected seasonal-task recommendation engine.**  
   Either implement that capability or change the copy so it describes only functionality that exists.

---

# 2. Current implementation map

## 2.1 Primary files

| Area | Current location |
|---|---|
| Permission education UI | `lib/src/ui/permission_education.dart` |
| Dashboard orchestration | `lib/main.dart` |
| OS permission gateway | `lib/src/core/services/app_permission_coordinator.dart` |
| Weather/device location | `lib/src/core/services/weather_service.dart` |
| Notification scheduling | `lib/src/core/services/notification_service.dart` |
| Settings persistence | `lib/src/core/data/repositories.dart` |
| Sync allowlist/spec | `lib/src/core/sync/sync_dtos.dart` |
| Local DB/seeds/sync handling | `lib/src/core/database/app_database.dart`, `lib/src/core/sync/local_sync_store.dart` |
| Android permissions | `android/app/src/main/AndroidManifest.xml` |
| English localization | `lib/l10n/app_en.arb` |
| Arabic localization | `lib/l10n/app_ar.arb` |
| Main widget coverage | `test/widget_test.dart` |
| Supabase setting constraints | `supabase/migrations/20260803120000_add_permission_education_setting.sql`, `supabase/migrations/20260806150000_align_user_settings_keys_and_extend_task_rpc.sql` |

## 2.2 Relevant history

Important implementation history includes:

- PR #5: `Redesign dashboard and add permission onboarding`
- Commit `9826a6e13209980321bb559265cbda362b974872`: `fix: refresh permission education release key`
- Commit `8d512001aae6f11eb3fec4fb3225f2db67e4b6ad`: `fix: refine home UI and permission onboarding`

The flow evolved from location/notification education into the current three-step location/notification/exact-alarm sequence.

---

# 3. Target product behavior

The improved system should be a **capability setup flow**, not a generic “ask for every permission” wizard.

The user should understand the benefit first, choose whether they want the capability, and only then see an OS permission request.

## 3.1 Target capability model

### Local weather

Offer three options:

- **Use current location**
- **Choose city/location manually**
- **Not now**

Only “Use current location” should request device-location permission.

### Notifications

Offer:

- **Enable reminders**
- **Not now**

Request OS notification permission only after the explicit enable action.

### Precise reminder timing

Do **not** request exact-alarm access by default.

Offer exact timing when one of these conditions is true:

- User enables `preferExactReminders`
- User schedules a reminder whose selected experience explicitly promises exact timing
- User enters reminder settings and enables “Precise reminder alarms”
- A contextual education surface explains that precise timing requires Android special access

If approximate timing is acceptable, HomePilot should continue functioning without exact-alarm permission.

---

# 4. Priority roadmap

## P0 — correctness, privacy, and device-scope fixes

These should ship before further visual redesign.

- Separate device-specific education state from account-synced settings.
- Stop using the account-synced `permission_education_seen_v2` as the sole “should this device show education?” gate.
- Make manual location selection available directly from Step 1.
- Stop requesting exact-alarm access during unconditional first-run permission education.
- Quantize or otherwise minimize location coordinates before external transmission and account sync.
- Decouple permission success from network/weather/notification refresh latency.
- Move permission-flow state out of Dashboard widget state into a dedicated controller.
- Fix dismissal semantics so `Not now` means defer, not permanent completion.
- Ensure settings-route cleanup preserves unrelated route/query state.

## P1 — UX, accessibility, reliability

- Introduce explicit per-step outcomes and clear recovery UI.
- Improve step progress when some capabilities are already configured.
- Add proper focus management and screen-reader isolation for the modal overlay.
- Improve target anchoring and orientation/layout-change handling.
- Add offline behavior and post-grant failure messaging.
- Add unified permission status handling across the app.
- Expand test matrix across Android permission behavior versions.

## P2 — maintainability and product maturity

- Add structured permission-flow observability without sensitive location data.
- Create dedicated permissions architecture documentation.
- Add contextual re-education triggers with cooldowns.
- Add a dedicated `/permissions/setup` route or sheet.
- Remove legacy `v2` behavior after an appropriate backwards-compatibility window.
- Implement actual weather/season-aware recommendations, or permanently remove unsupported claims from copy.

---

# 5. Replace the current persistence model

## 5.1 Problem

OS permission state is device-specific:

- Location permission differs by device.
- Notification permission differs by device.
- Exact-alarm access differs by Android installation/device.

However, the current `permission_education_seen_v2` value is part of shared account synchronization.

That conflates two different concepts:

1. “This account has seen this education copy.”
2. “This device has completed permission capability setup.”

Those must be separated.

## 5.2 Target data model

Create a **local/device-scoped permission education state**.

Recommended key:

```text
permission_education_device_state_v3
```

Suggested JSON structure:

```json
{
  "schema": 3,
  "lastShownAt": "2026-08-07T00:00:00Z",
  "completedAt": null,
  "dismissedUntil": null,
  "showCount": 1,
  "source": "first_dashboard_visit",
  "steps": {
    "location": {
      "educationSeen": true,
      "deferredAt": null,
      "lastOutcome": "granted"
    },
    "notifications": {
      "educationSeen": true,
      "deferredAt": "2026-08-07T00:00:00Z",
      "lastOutcome": "deferred"
    },
    "exactAlarms": {
      "educationSeen": false,
      "deferredAt": null,
      "lastOutcome": "not_applicable"
    }
  }
}
```

This state should be **local-only** unless HomePilot introduces a true device-scoped remote settings table keyed by device identity.

Do not add it to `allowedRemoteSettingKeys`.

## 5.3 Existing account-synced key

Keep:

```text
permission_education_seen_v2
```

temporarily for backward compatibility with old clients, but new code should not use it as the authoritative device gate.

Recommended migration behavior:

- If local `v3` state exists → use it.
- If local `v3` state does not exist:
  - Inspect real OS permission states.
  - Create the local `v3` state from the device's actual state.
  - Treat `v2=true` only as evidence that the user already understands the general concept, not as evidence that this device is configured.
- Old synced `v2=true` should reduce education aggressiveness, not suppress necessary device setup.

## 5.4 Prompt history

Keep prompt history device-local.

Current-style keys such as:

```text
permission_prompted_location
permission_prompted_notifications
permission_prompted_exactAlarms
```

should remain unsynced.

Improve them by storing more than a boolean if practical:

```json
{
  "attemptCount": 1,
  "lastRequestedAt": "2026-08-07T00:00:00Z",
  "lastResult": "denied"
}
```

This enables cooldowns and avoids repeated prompts.

---

# 6. Redesign dismissal and defer semantics

## 6.1 Current behavioral problem

“Not now” advances the flow.

Closing the entire flow persists completion.

This is too coarse because “I do not want this right now” is not the same as “never educate me again.”

## 6.2 Target semantics

### `Not now`

Meaning:

> Defer this capability.

Behavior:

- Do not request OS permission.
- Mark the current step as `deferred`.
- Continue to the next relevant capability if the user is already in the multi-step setup.
- Set a cooldown before automatic contextual re-education.

Suggested cooldown:

- First defer: 7 days
- Second defer: 30 days
- After repeated deferral: no automatic prompt; Settings remains available

Do not show a new modal every app launch.

### Close/X

Meaning should be explicit.

Preferred behavior:

- Tooltip/semantic label: **Finish later**
- Close the current education session.
- Preserve per-step states.
- Do not mark unresolved capabilities as permanently complete.
- Set a session-level cooldown.

Alternative if product wants permanent dismissal:

- Replace the ambiguous X with a clearly labeled action such as **Don't show automatically again**.
- Require explicit user intent.

### Completion

Mark the setup session complete only when:

- Every currently relevant step is either:
  - granted/configured,
  - explicitly deferred,
  - unavailable/not applicable,
  - or manually configured through an alternative path.

“Complete” should describe the session, not imply all OS permissions were granted.

---

# 7. Make location setup permission-optional

## 7.1 Problem

HomePilot already supports manual weather location selection, but Step 1 currently emphasizes `Enable location`.

This can create the impression that device-location permission is required for weather.

## 7.2 New Step 1 design

Title:

> Set your weather area

Body:

> HomePilot can use a city you choose or your current approximate location to show local weather for maintenance planning.

Actions:

- **Use current location**
- **Choose location manually**
- **Not now**

### Use current location

Flow:

```text
education
→ explicit user action
→ OS location request
→ permission outcome
→ acquire location
→ reduce precision
→ save home area
→ refresh weather asynchronously
```

### Choose manually

Flow:

```text
education
→ location picker
→ city/search result
→ save home area
→ refresh weather
→ no OS location permission
```

## 7.3 Existing manual location picker

Reuse the existing Settings location picker rather than implementing a second search system.

Refactor it into a shared capability service or reusable sheet accessible from:

- Settings
- permission onboarding
- weather card empty state

---

# 8. Fix location privacy and disclosure

## 8.1 Current concern

The copy states that approximate coordinates are sent to Open-Meteo and OpenStreetMap.

The current implementation formats coordinates to five decimal places for requests. Five decimal places are much more precise than the phrase “approximate coordinates” normally implies.

`LocationAccuracy.low` reduces acquisition precision, but the application should not rely on that alone as its privacy boundary.

## 8.2 Target privacy model

Create a single privacy function:

```dart
HomeLocation privacyReducedLocation(HomeLocation location)
```

Recommended default:

- Quantize device-derived latitude/longitude to **2 decimal places** before:
  - persistence as home weather location,
  - account synchronization,
  - Open-Meteo requests,
  - OpenStreetMap area-label requests.

This is roughly kilometer-scale latitude precision and is adequate for normal home-weather use.

If product quality requires finer reverse-geocoding:

- allow at most 3 decimal places for the temporary reverse-geocoding request,
- do not store or sync that finer coordinate,
- document the exception.

## 8.3 Avoid retaining raw device coordinates

After obtaining the device position:

```text
raw device position
→ immediately derive reduced-precision home area
→ discard raw coordinate
→ persist only reduced precision
```

Do not log raw coordinates.

## 8.4 Copy must disclose account sync

If `home_location` remains account-synced, the privacy copy should say so.

Candidate copy:

> If you choose current location, HomePilot converts it to an approximate home area. That area can sync with your HomePilot account. HomePilot does not collect your location continuously in the background.

External services copy:

> HomePilot sends the approximate area to Open-Meteo for weather and OpenStreetMap for an area name.

Legal/privacy review should approve final wording.

---

# 9. Remove unsupported “seasonal task recommendations” claims unless implemented

## 9.1 Current mismatch

The current Step 1 copy says location is used to:

> recommend seasonal home tasks

The audited code clearly implements:

- home location
- Open-Meteo weather
- weather display
- weather-related notification alerts

But the current project audit did not identify a connected seasonal maintenance recommendation engine using this data.

## 9.2 Choose one path

### Option A — copy correction

Preferred short-term fix.

Replace claims with functionality that exists:

> Use your home area to show local weather and support weather-aware maintenance alerts.

### Option B — implement real seasonal recommendations

If product wants to preserve the claim, implement a deterministic recommendation layer:

```text
home area
+ local date/season
+ weather conditions
+ owned asset/category inventory
+ existing plans
→ recommendation candidates
→ dedupe against existing tasks
→ user chooses whether to create task
```

Requirements:

- Never create maintenance tasks automatically.
- Explain why each recommendation exists.
- Deduplicate by asset/category/task intent.
- Localize recommendation copy.
- Add tests for hemisphere/season logic if season is location-dependent.
- Avoid simplistic northern-hemisphere-only `month → season` logic if recommendations are location-based globally.

This is a separate feature project and should not block the permission-flow fixes.

---

# 10. Move orchestration out of Dashboard

## 10.1 Problem

`_DashboardScreenState` currently owns:

- permission flow state,
- permission status values,
- prompt history,
- busy state,
- settings persistence,
- route query handling,
- lifecycle resume handling,
- overlay insertion/removal,
- target selection,
- weather side effects,
- notification side effects.

This is too much responsibility for the Dashboard widget.

## 10.2 Target module structure

Recommended structure:

```text
lib/src/features/permissions/
├── domain/
│   ├── permission_capability.dart
│   ├── permission_education_state.dart
│   └── permission_outcome.dart
├── data/
│   ├── permission_education_repository.dart
│   └── device_permission_gateway.dart
├── application/
│   ├── permission_education_controller.dart
│   ├── permission_capability_service.dart
│   └── permission_post_grant_service.dart
└── presentation/
    ├── permission_education_overlay.dart
    ├── permission_setup_screen.dart
    └── permission_step_content.dart
```

The current `lib/src/ui/permission_education.dart` can be migrated into the feature module or remain temporarily as a compatibility export.

## 10.3 Controller

Use a Riverpod `Notifier`/`AsyncNotifier` style controller.

Example state:

```dart
class PermissionEducationState {
  final PermissionCapability? activeCapability;
  final List<PermissionCapability> relevantCapabilities;
  final Map<PermissionCapability, AppPermissionState> permissionStates;
  final Map<PermissionCapability, PermissionEducationOutcome> outcomes;
  final bool isBusy;
  final PermissionEducationSource source;
  final PermissionEducationPhase phase;
  final Object? lastError;
}
```

Controller responsibilities:

- load local education state
- check real device permission states
- decide which capabilities are relevant
- expose the next action
- request permission
- open Settings
- refresh after resume
- defer capability
- finish current session
- persist local state

Dashboard responsibilities:

- render Dashboard
- provide target links/keys if an anchored first-run overlay is used
- show/hide the presentation component based on controller state

---

# 11. Unify permission APIs

## 11.1 Problem

The project currently has overlapping permission mechanisms:

- `permission_handler`
- `geolocator`
- `flutter_local_notifications`

Different parts of the application can therefore disagree about the same permission.

## 11.2 Target gateway

Create one application-level gateway with capability-specific implementations.

```dart
abstract interface class DevicePermissionGateway {
  Future<AppPermissionState> check(PermissionCapability capability);
  Future<AppPermissionState> request(PermissionCapability capability);
  Future<bool> openSettings(PermissionCapability capability);
}
```

### Location

Use Geolocator as the source of truth for:

- location service enabled
- permission status
- permission request
- opening location settings

This avoids checking location with one plugin and consuming it with another.

### Notifications

Choose a single source of truth.

Prefer the notification plugin for notification-specific capability because scheduling also depends on that subsystem.

The gateway may internally call `flutter_local_notifications` and normalize the result into `AppPermissionState`.

### Exact alarms

Use one Android-specific implementation.

Do not simultaneously treat `Permission.scheduleExactAlarm` and `requestExactAlarmsPermission()` as separate paths.

Normalize special-access behavior into capability-specific states, for example:

```text
granted
denied
needsSystemSettings
unavailable
```

Avoid forcing exact-alarm behavior into a generic runtime-permission model when Android treats it differently.

---

# 12. Make exact alarms contextual

## 12.1 Default behavior

Remove exact alarms from unconditional first-run education.

Default first-visit setup:

1. Weather area
2. Notifications

Exact alarms appear later only when relevant.

## 12.2 Contextual trigger

When the user enables:

```text
Precise reminder alarms
```

show a short explanation:

> Android requires special access for reminders at the exact selected time. Without it, HomePilot will use approximate timing.

Actions:

- **Open Android settings**
- **Use approximate timing**

## 12.3 Preference consistency

If exact access is denied:

- Do not leave the UI appearing as though exact delivery is guaranteed.
- Either:
  - keep `preferExactReminders=true` but show a clear degraded-state badge, or
  - set it back to false after explicit user confirmation.

Recommended model:

```text
preference = prefers exact
capability = exact access available?
effective schedule mode = exact only when both are true
```

The UI should display all three states:

- Exact timing active
- Exact timing requested but access missing
- Approximate timing selected

---

# 13. Decouple post-grant side effects from permission progression

## 13.1 Problem

Location permission grant can currently be followed by multiple awaited operations:

- current position retrieval
- reverse geocoding
- weather refresh
- notification schedule refresh

The onboarding should not feel stuck because OpenStreetMap or Open-Meteo is slow.

## 13.2 New flow

### Phase 1 — permission

Finish OS permission handling.

### Phase 2 — local capability setup

For location:

- get current position
- reduce precision
- persist home area

### Phase 3 — background refresh

Trigger without blocking the next education step:

- weather refresh
- notification schedule reconciliation
- provider invalidation

If background refresh fails:

- keep permission state as granted
- keep the saved home area
- show a non-blocking message if the user is still in the app
- retry when connectivity returns / normal refresh runs

## 13.3 User-visible result

If permission was granted but location acquisition fails:

> Location access is enabled, but HomePilot couldn't get your current area. Choose a location manually.

Actions:

- Choose location
- Later

Do not label the permission itself as failed.

---

# 14. Offline behavior

The permission flow must remain usable offline.

## Location

If location permission is granted while offline:

- acquire local GPS/network location if available
- reduce precision
- persist it
- use fallback label such as “Device location” if reverse geocoding fails
- queue weather refresh for later
- do not block onboarding

## Manual search

Manual location search requires connectivity.

When offline:

- clearly disable/search with an offline explanation
- retain “Use current location” if device location can work
- allow “Not now”

## Notifications/exact alarms

These are local OS operations and should remain functional offline.

---

# 15. Improve step progression and progress UI

## 15.1 Problem

If Location is already granted and Notifications is not, the flow can begin at `Step 2 of 3`.

Technically accurate, but the user never saw Step 1 in the current session.

## 15.2 Preferred design

Show a capability checklist rather than a raw wizard index.

Example:

```text
Weather area        ✓
Notifications       current
Precise timing      optional
```

If a numeric step must remain, calculate it from the current session's relevant steps:

```text
Step 1 of 1
```

or:

```text
2 of 3 capabilities
```

The latter communicates overall setup status better than wizard position.

## 15.3 Exact alarm status

If exact alarms are no longer default onboarding, they should not appear as an incomplete third step in the first-run progress indicator.

---

# 16. Improve overlay semantics and accessibility

## 16.1 Focus management

When the overlay opens:

- create a dedicated `FocusScope`
- move focus into the education card
- prevent keyboard focus from escaping to Dashboard controls

When it closes:

- restore focus to the control that triggered the education flow when practical

## 16.2 Screen reader isolation

Ensure screen readers do not read Dashboard content behind the modal.

Use appropriate semantics exclusion or route/modal semantics.

The barrier should have meaningful modal behavior but should not be a dismiss target if dismiss is disabled.

## 16.3 Back button

Define Android back behavior explicitly with `PopScope`.

Recommended:

- Back closes the education session as “finish later”
- It does not silently mark every unresolved capability complete
- If the UI has an internal previous-step action, system back should not unexpectedly navigate the application route instead

## 16.4 Large text

Validate at:

- 100%
- 130%
- 160%
- 200% text scale

The card already scrolls, but test button wrapping, title height, privacy box, and small-screen available height.

## 16.5 Small devices

Test at minimum:

- 320×568
- 360×640
- 393×852
- landscape phone
- tablet

## 16.6 Reduced motion

Keep the current reduced-motion design principle.

Also ensure:

- no repeating animation controller continues while animations are disabled
- step transitions use zero duration
- decorative halo remains visible but static

## 16.7 RTL

Validate the complete Arabic flow:

- back arrow direction
- illustration positioning
- button order
- text wrapping
- target halo
- route transitions
- Settings status rows

---

# 17. Fix target anchoring

## 17.1 Current behavior

Location anchors to the weather card.

Notifications and exact alarms anchor to the notification control.

## 17.2 Improvements

### Location

Keep weather-card anchor when the card is on screen.

If the weather card is not laid out or is offscreen:

- do not render a misplaced halo
- fall back to a centered education card with no target

### Notifications

Bell anchor is reasonable for notifications.

### Exact alarms

Do not anchor exact-alarm education to the bell by default after the redesign.

Use:

- the “Precise reminder alarms” Settings row when invoked contextually from Settings, or
- no halo for an OS special-access explanation.

## 17.3 Geometry

Prefer `CompositedTransformFollower` over manually cached `Rect` values where possible.

If a manual `Rect` remains necessary:

- recompute on orientation/size changes
- recompute after header layout changes
- recompute after scrolling
- handle target disposal safely

---

# 18. Routing improvements

## 18.1 Current Settings re-entry

Settings routes to:

```text
/?permissionSetup=1
```

Dashboard then recognizes the query parameter and forces the education overlay.

## 18.2 Problems

- Permission setup is coupled to the home route.
- Completion currently replaces the route with `/`, potentially discarding unrelated query state.
- Deep-link behavior is less explicit.
- Testing navigation becomes more complicated.

## 18.3 Target route

Introduce:

```text
/permissions/setup
```

Optional query:

```text
/permissions/setup?source=settings
```

or route extra/state if preferred.

Possible presentation:

- full-screen lightweight setup route, or
- shell-level modal page

The same controller should be reusable by first-run Dashboard education.

## 18.4 Transitional fix

Before the dedicated route ships, change query cleanup to remove only `permissionSetup` while preserving:

- current path
- other query parameters
- fragment

Never hard-replace unrelated navigation state with `/`.

---

# 19. Permission state model improvements

## 19.1 Generic states are insufficient

Current generic states include:

```text
granted
denied
permanentlyDenied
restricted
serviceDisabled
unavailable
```

This is useful but exact alarms are not a normal runtime permission.

## 19.2 Add capability action state

Introduce a normalized UI action model:

```dart
enum PermissionNextAction {
  request,
  openAppSettings,
  openLocationSettings,
  openExactAlarmSettings,
  chooseManualLocation,
  none,
}
```

Then UI labels come from the action rather than from scattered state conditionals.

## 19.3 Avoid prompt-history false positives

Do not mark a permission as prompted before a request operation that may fail with a missing plugin.

Preferred:

1. invoke the request
2. if the platform request path was actually supported, record the prompt attempt/outcome
3. if plugin unavailable, store `unavailable`, not `prompted=true`

---

# 20. Settings screen improvements

The Settings permissions section should become the authoritative status/recovery surface.

Recommended rows:

```text
Weather area
Baghdad, IQ / Not set
[Change]

Location access
Allowed / Not allowed / Service off
[Manage]

Notifications
Allowed / Blocked
[Manage]

Reminder timing
Exact / Approximate / Access needed
[Manage]
```

The current generic “Location, notifications, and reminders setup” entry can remain as a guided setup entry, but the status rows should allow direct recovery.

Do not require users to replay the entire onboarding just to fix one permission.

---

# 21. Notification preference consistency

Permission and preference are separate concepts.

Example:

```text
OS notifications allowed = true
HomePilot notification preference enabled = false
```

This should be represented clearly.

## Target model

For every capability show:

- **User preference**
- **OS capability**
- **Effective behavior**

Example:

```text
Notification preference: enabled
OS permission: blocked
Effective behavior: in-app only / no device alert
```

For exact reminders:

```text
Prefer exact: true
Exact alarm access: false
Effective schedule: approximate
```

This reduces state ambiguity.

---

# 22. Weather integration improvements

## 22.1 Weather refresh

After home location changes:

- invalidate/update location immediately
- refresh weather asynchronously
- cache the result
- show last known weather when network is unavailable

## 22.2 Location label

Keep reverse-geocoding failure non-fatal.

Use fallback hierarchy:

1. resolved city/region label
2. manually selected label
3. localized “Device location”

## 22.3 External service isolation

Create a location/weather boundary so permission onboarding does not know about:

- Open-Meteo URL construction
- Nominatim URL construction
- provider invalidation details

It should call something like:

```dart
await homeLocationService.useCurrentApproximateArea();
```

---

# 23. Do not request permissions before education

This remains a hard acceptance rule.

No OS permission dialog should appear merely because:

- the app launched,
- Dashboard rendered,
- a provider initialized,
- a scheduler initialized,
- weather card loaded.

OS permission requests must follow an explicit user action whose immediately preceding UI explains the purpose.

System Settings redirection must also follow explicit user intent.

---

# 24. Error handling and user messaging

Create typed errors/outcomes.

Examples:

```text
locationServiceDisabled
locationRequestDenied
locationRequestRestricted
locationUnavailable
weatherRefreshFailed
notificationPermissionDenied
exactAlarmAccessMissing
settingsOpenFailed
permissionPluginUnavailable
```

Do not expose raw exceptions.

## Suggested UI behavior

### Permission denied once

Do not immediately nag.

Show:

> Location wasn't enabled. You can choose a city instead.

### Permanently denied

Show:

> Location is blocked in Android settings.

Primary:

> Open settings

Secondary:

> Choose city instead

### Service disabled

Primary:

> Turn on location services

Secondary:

> Choose city instead

### Weather network failure

Show:

> Your home area was saved. Weather will update when you're online.

Do not keep the permission wizard spinning.

---

# 25. Observability

Add structured events through the existing application logging/observability system.

Recommended events:

```text
permission_education_session_started
permission_education_step_shown
permission_education_action
permission_request_result
permission_settings_opened
permission_state_refreshed_after_resume
permission_education_deferred
permission_education_session_closed
permission_post_grant_setup_result
permission_education_session_completed
```

Safe fields:

```text
capability
source
prior_state
result_state
action
platform
android_api_bucket
app_version
education_schema
duration_bucket
```

Never log:

- latitude
- longitude
- location label
- user-entered location query
- notification contents
- account identifiers in plain logs

Add explicit tests/guards if the project has DLP logging utilities.

---

# 26. Analytics/product metrics

Only collect product funnel analytics where allowed by the project's consent/privacy model.

Useful aggregate metrics:

- % of users choosing manual vs device location
- notification opt-in rate after education
- exact timing opt-in rate when contextually offered
- defer rate
- Settings recovery success rate
- time from education to capability activation
- post-grant weather setup failure rate

Do not optimize for permission opt-in at the expense of informed consent.

---

# 27. Localization plan

Update both:

```text
lib/l10n/app_en.arb
lib/l10n/app_ar.arb
```

and regenerate localization outputs.

## New/updated keys

Suggested keys:

```text
permissionSetupFinishLater
permissionSetupChooseLocation
permissionSetupUseCurrentLocation
permissionSetupWeatherTitle
permissionSetupWeatherBody
permissionSetupWeatherPrivacy
permissionSetupDeferred
permissionSetupExactOptionalTitle
permissionSetupExactOptionalBody
permissionSetupUseApproximateTiming
permissionSetupLocationSavedWeatherPending
permissionSetupLocationBlocked
permissionSetupLocationServiceOff
permissionSetupNotificationBlocked
permissionSetupManageInSettings
```

Avoid duplicate semantically identical strings.

## Copy review checklist

Every permission explanation must answer:

1. What benefit does this enable?
2. What data/system access is requested?
3. Is the permission optional?
4. What still works without it?
5. Where can the user change it later?

---

# 28. Suggested revised copy

Final copy should receive product/privacy/localization review.

## Weather/location

**Title:**  
Set your weather area

**Body:**  
Choose a city or use your current approximate location to show local weather for maintenance planning.

**Privacy:**  
If you use current location, HomePilot saves an approximate home area. It does not continuously collect your location in the background. Your saved home area may sync with your HomePilot account.

**Primary:**  
Use current location

**Secondary:**  
Choose location

**Tertiary:**  
Not now

## Notifications

**Title:**  
Get maintenance reminders

**Body:**  
Allow notifications for the task reminders and alerts you enable in HomePilot.

**Reassurance:**  
You can change reminder preferences or notification access at any time.

**Primary:**  
Enable notifications

## Exact timing — contextual only

**Title:**  
Use precise reminder timing

**Body:**  
Android requires special access for reminders at the exact selected time.

**Reassurance:**  
Without this access, HomePilot can still use approximate reminder timing.

**Primary:**  
Allow precise timing

**Secondary:**  
Use approximate timing

---

# 29. Android platform plan

## API behavior matrix

Test at least these behavioral groups:

### Android 11 and below

- No runtime `POST_NOTIFICATIONS`
- No Android 12 exact-alarm special access
- Location behavior

### Android 12 / 12L

- Approximate/precise location behavior
- Exact-alarm special access

### Android 13

- Runtime notification permission
- Exact alarms
- location behavior

### Android 14+

- Notification permission
- exact-alarm default restrictions/special access
- lifecycle return from system Settings

Use actual current project min/target SDK configuration to refine exact emulator versions.

## Manifest

Continue requesting only permissions the app actually uses.

If approximate location is sufficient, preserve the coarse-location principle.

Do not add fine or background location unless a separately reviewed feature genuinely requires it.

---

# 30. iOS and non-Android behavior

Exact alarms should remain not applicable outside Android.

The setup controller should build a platform-specific relevant-capability list.

Example:

```text
Android:
weather area
notifications
precise timing (contextual)

iOS:
weather area
notifications

desktop/web:
manual weather location
notification capability only if supported
```

Do not show `Step 3 of 3` when the platform can never support that step.

---

# 31. Lifecycle behavior

When the app resumes from system Settings:

1. Recheck only the capability currently awaiting settings recovery.
2. Update the controller.
3. If newly granted, apply local capability setup.
4. If still denied, keep the recovery UI visible.
5. Do not reopen system Settings automatically.
6. Do not advance silently if the user still needs to make an explicit choice.

Handle repeated lifecycle events idempotently.

---

# 32. Concurrency and race-condition controls

The new controller should serialize permission operations.

Use one active operation per capability/session.

Protect against:

- double taps
- repeated app-resume callbacks
- overlay rebuild during permission request
- route disposal during async work
- sign-out during setup
- Settings route changes during network refresh
- two providers triggering setup simultaneously

Post-grant refreshes should be idempotent.

---

# 33. Sign-in, sign-out, and account-switch behavior

## Sign-in

After authentication:

- load local device education state
- check actual OS permissions
- do not rely on the remote `v2` flag to infer device permission readiness

## Sign-out

- close active education UI
- cancel pending session work where possible
- retain installation-level OS prompt history as appropriate
- clear account-specific local education state if the local database/account model requires it

## Account switch

Do not assume permission state changed merely because account changed.

OS permissions are installation/device-level, while the user's preference and education context may be account-level.

The controller should explicitly model that distinction.

---

# 34. Tests — unit

Create dedicated tests for the controller/state machine.

Minimum cases:

- all permissions already available
- location missing, notifications granted
- notifications missing, location configured manually
- exact alarms not relevant
- exact alarms relevant and granted
- exact alarms relevant and unavailable
- first denial
- repeated denial
- permanently denied
- location service disabled
- open Settings then grant
- open Settings then remain denied
- `Not now`
- close/finish later
- cooldown active
- cooldown expired
- old `v2=true`, new device permissions missing
- cross-account state
- plugin unavailable
- offline weather refresh failure
- location granted but position unavailable
- route disposed mid-request

---

# 35. Tests — widget

Cover:

- overlay appears only when controller says it should
- no OS request before explicit button tap
- manual location option never requests location permission
- dynamic progress display
- Settings re-entry for one missing capability
- close/finish-later semantics
- no bottom-navigation interaction through modal
- focus stays inside modal
- Android back behavior
- 200% text scale
- 320px-wide device
- landscape
- dark theme
- light theme
- Arabic RTL
- reduced motion
- target unavailable fallback
- anchor stays correct after layout change
- busy state prevents duplicate requests

---

# 36. Tests — integration/platform

Widget fakes cannot validate Android permission semantics fully.

Add/manual-run integration coverage for:

- fresh install
- upgrade from old `permission_education_seen`
- upgrade from `permission_education_seen_v2`
- same account on a second device
- Android notification denial
- “Don't ask again” / permanently denied location where applicable
- location services disabled
- exact-alarm special access
- returning from Android Settings
- offline first launch
- process death while system Settings is open
- app restart after defer
- app restart after grant
- notification scheduling after grant
- exact → approximate fallback

---

# 37. Test fakes

Create a deterministic fake gateway:

```dart
class FakeDevicePermissionGateway implements DevicePermissionGateway {
  final Map<PermissionCapability, AppPermissionState> states;
  final List<PermissionCapability> requests;
  final List<PermissionCapability> settingsOpens;
}
```

Also separate fake post-grant services:

```text
FakeHomeLocationService
FakeWeatherRefreshService
FakeReminderRefreshService
```

This avoids giant Dashboard test fixtures.

---

# 38. Data/sync migration plan

## Phase 1

Add local `permission_education_device_state_v3`.

Do not sync it.

Read `v2` for compatibility.

## Phase 2

New clients stop writing `v2` as the device completion authority.

Keep the key accepted by Supabase because older clients may still write it.

## Phase 3

After minimum supported client version has moved beyond the old implementation:

- remove `permission_education_seen` legacy key from new client logic
- optionally retain backend acceptance for a longer safety window
- later remove obsolete remote key constraints through a dedicated migration

Do not remove backend keys while production clients can still send them.

---

# 39. Database/version compatibility

Any schema or settings change must preserve:

- existing local databases
- existing signed-in accounts
- pending sync mutations
- current Supabase rows
- downgrade safety where required by project policy

Prefer additive changes.

If the local state is stored as a new settings key, a Drift schema migration may not be required if the settings table already supports arbitrary local keys; nevertheless, seed/default handling and sync filters must be reviewed.

---

# 40. Refactor plan by file

## `lib/src/ui/permission_education.dart`

- Move toward feature module.
- Replace fixed 3-step assumptions.
- Accept capability descriptors rather than hard-coded enum mapping.
- Add FocusScope.
- Add PopScope behavior.
- Improve modal semantics.
- Make progress dynamic.
- Remove exact-alarm hard-coded third step from default flow.
- Add manual-location action.
- Make halo optional.
- Improve target fallback.
- Add stable keys for each actionable control.

## `lib/main.dart`

Remove most permission state-machine fields and methods.

Target removal/refactor candidates include responsibilities equivalent to:

```text
_permissionEducationSteps
_permissionEducationStep
_permissionEducationOverlayEntry
_permissionOverlaySyncScheduled
_locationPermissionState
_notificationPermissionState
_exactAlarmPermissionState
_permissionPrompted
_permissionEducationBusy
_permissionEducationLoadInFlight
_forcePermissionEducationHandled
_maybeStartPermissionEducation
_handlePermissionContinue
_advancePermissionEducation
_completePermissionEducation
_refreshPermissionEducationAfterSettings
```

Dashboard should subscribe to a controller instead.

## `lib/src/core/services/app_permission_coordinator.dart`

- Replace broad generic plugin calls with capability-specific sources of truth.
- Keep normalized app-level states.
- Improve prompt-attempt storage.
- Treat exact-alarm special access separately.

## `lib/src/core/services/weather_service.dart`

- Add coordinate precision reduction.
- Ensure raw current position is not persisted/logged.
- Split location acquisition from weather refresh.
- Reuse shared reduced-precision location model.
- Keep network failures non-fatal.

## `lib/src/core/services/notification_service.dart`

- Expose authoritative notification/exact capability checks through a reusable adapter.
- Keep scheduling independent from education UI.
- Make exact/approximate effective scheduling visible to Settings/controller.

## `lib/src/core/data/repositories.dart`

- Add local v3 education-state repository methods.
- Keep v3 out of remote sync.
- Retain v2 compatibility reader where needed.

## `lib/src/core/sync/sync_dtos.dart`

- Do not add v3 local device state to `allowedRemoteSettingKeys`.
- Document why permission education device state is deliberately unsynced.
- Preserve legacy remote keys until compatibility window ends.

## `android/app/src/main/AndroidManifest.xml`

- Verify coarse location remains sufficient.
- Verify notification/exact-alarm declarations match actual product behavior.
- Do not add background location.

## `lib/l10n/*.arb`

- Replace unsupported seasonal-task claim or implement the promised feature.
- Add manual location and finish-later copy.
- Add exact-alarm optional/degraded state copy.
- Keep English/Arabic parity.

## `test/widget_test.dart`

- Move large permission suites into dedicated test file(s), for example:

```text
test/features/permissions/permission_education_controller_test.dart
test/features/permissions/permission_education_overlay_test.dart
test/features/permissions/permission_setup_route_test.dart
```

Keep only integration-level shell tests in `widget_test.dart`.

---

# 41. Recommended new public interfaces

## Permission capability

```dart
enum PermissionCapability {
  deviceLocation,
  notifications,
  exactReminderTiming,
}
```

## Education source

```dart
enum PermissionEducationSource {
  firstDashboardVisit,
  settings,
  weatherCard,
  reminderSettings,
  taskScheduling,
}
```

## Education outcome

```dart
enum PermissionEducationOutcome {
  granted,
  configuredManually,
  deferred,
  blocked,
  unavailable,
  failed,
}
```

## Post-grant service

```dart
abstract interface class PermissionCapabilityActivator {
  Future<CapabilityActivationResult> activate(
    PermissionCapability capability,
  );
}
```

This keeps OS permission handling separate from application-side activation.

---

# 42. Recommended state transitions

## Location

```text
unknown
  ↓ check
granted ───────────────────→ configured/current
denied
  ├─ Use current location → request
  │      ├─ granted → acquire reduced location → configured
  │      ├─ denied → deferred/recovery
  │      └─ blocked → open settings option
  ├─ Choose location → manual picker → configuredManually
  └─ Not now → deferred
serviceDisabled
  ├─ Turn on service
  ├─ Choose location manually
  └─ Not now
```

## Notifications

```text
unknown
  ↓ check
granted → configured
denied
  ├─ Enable → request
  │    ├─ granted → refresh scheduler
  │    └─ denied → deferred/recovery
  └─ Not now → deferred
blocked
  ├─ Open settings
  └─ Not now
```

## Exact timing

```text
not relevant → do not show
relevant
  ↓
granted → exact mode
missing
  ├─ Allow precise timing → system special access
  └─ Use approximate timing → approximate mode
```

---

# 43. Security/privacy threat review

Before release, explicitly review:

- Can coordinates appear in logs?
- Can coordinates appear in crash metadata?
- Are raw positions ever persisted before quantization?
- Is home location account-synced?
- Do backups include home location?
- Does account deletion remove synced home location?
- Does reverse-geocoding request contain more precision than documented?
- Does background WorkManager ever request a fresh device position? It should not.
- Can a malicious deep link force an OS permission request? It must still require explicit user interaction.
- Can the education overlay obscure a security-critical OS state?
- Can a stale synced value suppress required device setup?

---

# 44. Documentation plan

Update or create project documentation covering:

## Permissions

Create/update a dedicated document, for example:

```text
docs/permissions.md
```

Document:

- capability → platform permission mapping
- when permission is requested
- alternative path without permission
- device-local vs account-synced state
- exact-alarm behavior
- lifecycle/Settings recovery
- Android version matrix
- testing requirements

## Privacy

Document:

- location precision reduction
- saved home-area behavior
- account sync behavior
- Open-Meteo
- OpenStreetMap/Nominatim
- no continuous background geolocation

## Architecture

Document the new permissions feature module and state machine.

## Changelog

Add a user-visible entry because this changes:

- permission behavior
- privacy behavior
- Settings behavior
- persistence/sync semantics

---

# 45. Release plan

## Release A — safety/correctness

Ship:

- v3 local device state
- exact alarm removed from unconditional onboarding
- manual location choice
- privacy precision reduction
- copy correction
- post-grant async decoupling
- route cleanup fix
- controller extraction foundation

## Release B — UX/accessibility

Ship:

- full capability setup UI
- dedicated permissions route
- dynamic progress
- focus/semantics improvements
- contextual exact timing education
- expanded Settings status/recovery

## Release C — cleanup

After old-client compatibility window:

- reduce legacy v1/v2 code paths
- remove obsolete tests
- simplify backend setting allowlist if safe
- document final architecture

---

# 46. Rollout safeguards

For the first release:

- Keep a feature flag or safe fallback path if the project has a feature-flag mechanism.
- Do not force-show the new flow to all existing users immediately unless required.
- Existing users with working permissions should not be interrupted.
- New-device users should receive capability setup based on actual device state.
- Track error rates for:
  - controller initialization
  - OS permission request
  - Settings round-trip
  - location activation
  - weather refresh
  - reminder refresh

Have a rollback plan that does not require database rollback.

---

# 47. Definition of done

The permission onboarding redesign is complete only when all of the following are true.

## Correctness

- [ ] Device permission education is not suppressed by a flag synced from another device.
- [ ] Every relevant OS permission state is checked from one authoritative gateway.
- [ ] Returning from system Settings refreshes state correctly.
- [ ] No permission is requested before explicit user action.
- [ ] Exact-alarm access is not part of unconditional first-run setup.
- [ ] Manual weather location works without device-location permission.
- [ ] Denial and permanent denial are recoverable from Settings.
- [ ] Permission operations are idempotent and protected from double taps/races.

## Privacy

- [ ] Raw device coordinates are not logged.
- [ ] Raw device coordinates are not stored when reduced precision is sufficient.
- [ ] External weather/geocoding requests use documented reduced precision.
- [ ] Copy accurately describes storage, account sync, external services, and background behavior.
- [ ] No background location permission is added.
- [ ] No background fresh-location polling is introduced.

## UX

- [ ] `Not now` defers rather than silently acting as permanent completion.
- [ ] Close/X has unambiguous “finish later” semantics.
- [ ] Already configured capabilities do not produce confusing wizard numbering.
- [ ] Exact timing clearly communicates approximate fallback.
- [ ] Network failure does not trap the user in the permission flow.
- [ ] The user can fix one capability without replaying the entire wizard.

## Accessibility

- [ ] Focus is trapped in the modal while visible.
- [ ] Screen readers do not interact with Dashboard content behind the modal.
- [ ] Android back behavior is defined.
- [ ] 200% text scale is usable.
- [ ] Arabic RTL is validated.
- [ ] Reduced motion has no continuous animation.
- [ ] Small phone and landscape layouts are validated.

## Engineering

- [ ] Permission state machine is removed from Dashboard widget state.
- [ ] Dedicated unit tests cover the controller.
- [ ] Dedicated widget tests cover the presentation.
- [ ] Android integration/manual permission matrix is complete.
- [ ] Sync compatibility tests cover legacy v2 behavior.
- [ ] Localization generation passes.
- [ ] Static analysis passes.
- [ ] Full Flutter test suite passes.
- [ ] Supabase migrations/lint/tests pass if backend constraints are changed.
- [ ] Documentation and changelog are updated in the same PR.

---

# 48. Suggested implementation sequence

## Phase 1 — extract and protect behavior

1. Introduce `PermissionCapability`.
2. Add a dedicated permission controller using existing behavior.
3. Keep current visual UI initially.
4. Move lifecycle refresh into controller.
5. Move OS permission calls behind one gateway.
6. Add controller tests.
7. Ensure no visible behavior regression.

## Phase 2 — persistence correctness

1. Add local `permission_education_device_state_v3`.
2. Implement v2 compatibility bootstrap.
3. Stop treating synced v2 as device completion.
4. Add cross-device simulation tests.
5. Add defer/cooldown state.

## Phase 3 — privacy/location

1. Add manual location action to onboarding.
2. Add coordinate precision reduction.
3. Stop storing raw device position.
4. Update copy.
5. Decouple weather refresh.
6. Add offline tests.

## Phase 4 — exact alarm redesign

1. Remove exact alarms from first-run relevant steps.
2. Add contextual exact-timing education in reminder settings.
3. Normalize exact-alarm effective schedule state.
4. Test Android API behavior.

## Phase 5 — presentation/accessibility

1. Dynamic capability progress.
2. Focus scope.
3. PopScope.
4. screen-reader isolation.
5. better target anchoring/fallback.
6. large text/RTL/small-screen fixes.

## Phase 6 — routing/settings

1. Add `/permissions/setup`.
2. Replace `/?permissionSetup=1`.
3. Add direct capability recovery rows.
4. Preserve navigation state.
5. Add route tests.

## Phase 7 — observability/docs/release

1. Add safe structured events.
2. Update privacy/permissions docs.
3. Update architecture docs.
4. Add changelog.
5. Execute emulator/manual matrix.
6. Ship with rollback-safe additive data changes.

---

# 49. PR decomposition

Avoid one giant PR.

Recommended sequence:

### PR 1 — Permission controller extraction

No intentional product behavior change.

### PR 2 — Device-scoped education state v3

Fix cross-device/sync correctness and defer semantics.

### PR 3 — Location privacy + manual location

Quantization, copy correction, manual path, network decoupling.

### PR 4 — Contextual exact alarms

Remove from first-run flow and integrate with reminder settings.

### PR 5 — Accessibility and overlay UX

Focus, semantics, progress, target handling, layout matrix.

### PR 6 — Dedicated permission setup route and Settings recovery

Remove Dashboard query coupling.

### PR 7 — Documentation, legacy cleanup, compatibility retirement

Only after old-client compatibility is verified.

Each PR should be independently testable and revertible.

---

# 50. Final target experience

A new user should experience the following:

```text
Home dashboard
     ↓
“Set your weather area”
     ├── Choose city ────────────────→ weather configured, no OS permission
     ├── Use current location
     │       ↓
     │    OS location prompt
     │       ↓
     │    approximate home area saved
     │       ↓
     │    weather refreshes in background
     └── Not now

     ↓

“Get maintenance reminders”
     ├── Enable
     │      ↓
     │   OS notification prompt
     └── Not now

     ↓
Finish
```

Later, only if the user selects exact reminder timing:

```text
Precise reminder alarms
     ↓
“Android requires special access for exact timing”
     ├── Allow precise timing
     └── Use approximate timing
```

This design is more accurate, less permission-aggressive, more privacy-preserving, easier to recover, and substantially simpler to reason about across multiple devices.

---

# Appendix A — current implementation evidence map

The plan above is based on the current HomePilot implementation and related project history, including:

- `lib/src/ui/permission_education.dart`
  - three hard-coded steps
  - root modal overlay
  - non-dismissible barrier
  - target halo
  - reduced-motion handling
  - step card and actions

- `lib/main.dart`
  - Dashboard-owned permission state machine
  - first-visit trigger
  - permission checking
  - prompt-history handling
  - Settings round-trip
  - post-grant weather/reminder side effects
  - Settings re-entry through `permissionSetup=1`

- `lib/src/core/services/app_permission_coordinator.dart`
  - `permission_handler` mapping
  - location/notification/exact-alarm kinds
  - prompted-history settings

- `lib/src/core/services/weather_service.dart`
  - Geolocator current position
  - low-accuracy location request
  - Open-Meteo forecast
  - OpenStreetMap/Nominatim reverse geocoding
  - coordinate formatting
  - cached weather fallback

- `lib/src/core/services/notification_service.dart`
  - Android notification permission
  - exact-alarm capability
  - reminder schedule reconciliation
  - WorkManager background refresh

- `lib/src/core/data/repositories.dart`
  - `permission_education_seen_v2`

- `lib/src/core/sync/sync_dtos.dart`
  - `permission_education_seen_v2` in shared user-setting sync allowlist
  - `home_location` in shared user-setting sync allowlist

- `android/app/src/main/AndroidManifest.xml`
  - coarse location
  - notification permission
  - exact-alarm permission
  - no background location permission

- `test/widget_test.dart`
  - permission request sequence
  - skip behavior
  - Settings behavior
  - denial handling
  - reduced motion
  - modal blocking

---

# Appendix B — non-goals

This plan does not require:

- adding background location tracking
- adding fine location permission
- auto-creating maintenance tasks from weather
- requiring every user to enable notifications
- requiring exact alarms
- removing approximate reminder fallback
- forcing existing configured users through onboarding again
- breaking old clients that still use `permission_education_seen_v2`

---

# Appendix C — engineering principle

The permission system should follow this invariant:

> **Educate → user chooses capability → request only the minimum OS access needed → apply the capability independently → preserve a usable fallback when access is declined.**

Every implementation decision in this plan should be evaluated against that invariant.
