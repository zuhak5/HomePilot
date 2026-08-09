# HomePilot Pure Splash Screen Implementation Plan

> **Historical plan:** This document records an earlier splash proposal and is retained for traceability. It is not a current startup runbook or completion claim; current behavior is defined by `lib/main.dart`, `lib/homepilot_animated_splash_screen.dart`, and their lifecycle/overlay tests.

## Objective

Activate the existing HomePilot animated splash design as a **purely visual, fixed-duration startup overlay**.

The splash must:

- Appear after the native Android splash.
- Display for a fixed duration.
- Use only its own animation timer and bundled image asset.
- Disappear automatically.
- Never read from app state.
- Never write to app state.
- Never control navigation.
- Never wait for loading, authentication, sync, database, network, or services.
- Never delay construction or initialization of the real app.
- Never change the destination screen or startup route.
- Leave all existing application behavior unchanged behind the overlay.

Target startup sequence:

```text
Native Android splash
        ↓
HomePilot app starts normally
        +
Animated splash overlay is shown above it
        ↓ fixed timer only
Overlay fades out and is removed
        ↓
Already-running app becomes visible
```

---

## Non-goals

Do not connect the splash to:

- Authentication state
- Onboarding state
- Database initialization
- Preferences
- Supabase
- Synchronization
- Connectivity
- Notifications
- Ads
- Startup progress
- Deep links
- Router state
- Localization state
- Theme state
- Error handling
- Analytics or telemetry
- Any provider, stream, notifier, repository, service, or controller

Do not use the splash to decide where the user goes next.

Do not add a new route for the splash.

Do not delay creation of `HomePilotApp`.

Do not replace the app root after a timer.

Do not call `Navigator.push`, `pushReplacement`, `pushNamed`, or any equivalent navigation API from the splash.

---

## Relevant Existing Files

Primary implementation:

```text
lib/homepilot_animated_splash_screen.dart
```

Application entry point and root app:

```text
lib/main.dart
```

Existing splash assets:

```text
assets/splash/homepilot_splash_icon_3d.png
assets/splash/homepilot_splash_android12.png
```

Native Android splash configuration:

```text
flutter_native_splash.yaml
android/app/src/main/res/
```

Existing startup tests that must continue to pass:

```text
test/startup_resources_test.dart
test/startup_benchmark_test.dart
test/initial_hydration_progress_test.dart
```

---

## Required Architecture

Use an **overlay inside the existing Flutter application root**.

The real app must be created and run exactly as it is now. The splash is placed visually above the app using a `Stack`.

Conceptual structure:

```dart
MaterialApp(
  builder: (context, child) {
    return HomePilotSplashOverlay(
      child: child ?? const SizedBox.shrink(),
    );
  },
)
```

The overlay owns only local UI state:

```text
visible = true
start local timer
timer completes
run fade-out animation
visible = false
remove overlay
```

The app beneath the overlay must remain mounted throughout the entire process.

This design is required because it avoids:

- Delaying app initialization
- Rebuilding the app root
- Resetting router state
- Losing initial route information
- Interfering with deep links
- Re-running providers or services
- Coupling splash completion to application readiness

---

## Phase 1 — Refactor the Existing Splash Widget

### File

```text
lib/homepilot_animated_splash_screen.dart
```

### Goal

Convert `HomePilotAnimatedSplashScreen` into a presentation-only widget.

### Remove from the public API

Remove these fields and constructor parameters:

```dart
nextRoute
navigateAutomatically
onFinished
progressValue
statusText
footerText
```

Remove all navigation logic.

Remove the delayed callback that calls:

```dart
Navigator.maybeOf(...)
navigator.pushReplacementNamed(...)
```

Remove any callback that signals completion to the app.

### Replace external values with fixed visual values

Use static display text matching the approved screen:

```text
Starting HomePilot
Works online and offline
```

Keep the existing tagline:

```text
Your tasks, routines, and reminders
all in sync.
```

The progress bar must remain cosmetic.

It must use only the widget's local intro animation:

```dart
_progressValue.value
```

It must not accept external progress.

### Keep

Preserve the existing:

- 3D splash asset
- Background painter
- Intro animation
- Loop animation
- Floating and tilting icon behavior
- Rotating synchronization graphics
- Wordmark
- Tagline
- Cosmetic progress bar
- Status text
- Footer text
- Responsive sizing logic, subject to fixes below

### System UI behavior

Do not call:

```dart
SystemChrome.setSystemUIOverlayStyle(...)
```

from `initState`.

That call changes global application UI state and violates the isolation requirement.

Instead, wrap the splash visual with:

```dart
AnnotatedRegion<SystemUiOverlayStyle>
```

using the desired light status/navigation bar appearance.

This limits the style to the splash layer and allows the underlying app to regain control after the overlay is removed.

### Interaction behavior

The splash must block accidental taps while visible.

Wrap the splash layer with:

```dart
AbsorbPointer(absorbing: true)
```

or equivalent.

Do not pass events through to the app while the overlay is visible.

### Accessibility behavior

Wrap the splash in a semantics container:

```dart
Semantics(
  container: true,
  label: 'Starting HomePilot',
  value: 'Works online and offline',
)
```

Mark decorative custom-painted elements and the illustration as excluded from duplicate semantics where appropriate.

The cosmetic progress bar must not claim to represent real loading progress.

Use one of these approaches:

1. Exclude the bar from semantics; or
2. Label it clearly as a startup animation rather than app loading progress.

Preferred:

```dart
ExcludeSemantics(
  child: progressBar,
)
```

### Responsive layout fixes

The current progress bar uses a fixed width of 310 logical pixels. Replace it with a constrained width:

```dart
width: min(310, availableWidth)
```

Recommended implementation:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final progressWidth = math.min(310.0, constraints.maxWidth);
    ...
  },
)
```

Ensure the splash does not overflow at:

- 320 px width
- Large text scale
- Short screens
- Landscape orientation

Keep the design visually close to the supplied screenshot.

---

## Phase 2 — Add an Isolated Overlay Controller

### File

Prefer placing the controller in:

```text
lib/homepilot_animated_splash_screen.dart
```

Add a new widget:

```dart
class HomePilotSplashOverlay extends StatefulWidget
```

### Public API

Keep the API minimal:

```dart
const HomePilotSplashOverlay({
  required this.child,
  this.displayDuration = const Duration(milliseconds: 3200),
  this.fadeOutDuration = const Duration(milliseconds: 250),
  super.key,
});
```

Fields:

```dart
final Widget child;
final Duration displayDuration;
final Duration fadeOutDuration;
```

Do not add:

- Completion callbacks
- Progress input
- App-state input
- Route input
- Provider input
- Loading state
- Error state
- Authentication state

### Behavior

Build the child immediately.

Place the splash above it:

```dart
Stack(
  fit: StackFit.expand,
  children: [
    child,
    if (_showSplash)
      Positioned.fill(
        child: AnimatedOpacity(
          opacity: _isFadingOut ? 0 : 1,
          duration: widget.fadeOutDuration,
          child: const HomePilotAnimatedSplashScreen(),
        ),
      ),
  ],
)
```

### Timer sequence

In `initState`:

1. Schedule a timer for `displayDuration`.
2. When it fires, start fade-out.
3. After `fadeOutDuration`, remove the splash from the tree.

Use cancelable `Timer` instances, not uncancelable delayed futures.

Example state:

```dart
Timer? _displayTimer;
Timer? _removalTimer;
bool _showSplash = true;
bool _isFadingOut = false;
```

Dispose both timers:

```dart
@override
void dispose() {
  _displayTimer?.cancel();
  _removalTimer?.cancel();
  super.dispose();
}
```

Check `mounted` before `setState`.

### Important invariant

The overlay must never replace, recreate, or navigate away from `child`.

The same child subtree must remain mounted before, during, and after the splash.

---

## Phase 3 — Integrate the Overlay at the App Root

### File

```text
lib/main.dart
```

### Locate

Find the primary `MaterialApp`, `MaterialApp.router`, or equivalent root widget inside `HomePilotApp`.

### Integration rule

Use the app-level `builder` parameter to wrap the existing rendered child.

If a builder already exists, preserve its behavior and compose the splash wrapper around its result.

Example when there is no existing builder:

```dart
MaterialApp(
  ...
  builder: (context, child) {
    return HomePilotSplashOverlay(
      child: child ?? const SizedBox.shrink(),
    );
  },
)
```

Example when a builder already exists:

```dart
builder: (context, child) {
  final existingBuiltChild = existingBuilderLogic(
    context,
    child ?? const SizedBox.shrink(),
  );

  return HomePilotSplashOverlay(
    child: existingBuiltChild,
  );
},
```

### Do not change

Do not alter:

- `runApp(...)`
- Startup resource creation
- `HomePilotApp` constructor parameters
- Provider scopes
- Router configuration
- Authentication gate
- Initial route
- Navigation observers
- Sentry integration
- Deep-link handling
- Theme selection
- Locale selection
- App lifecycle handling
- Startup service scheduling

The only integration change should be the visual wrapper around the already-running app.

### One-time display behavior

The splash should display once per Flutter process launch.

It should not reappear when:

- Navigating between screens
- Signing in or out
- Returning from the background
- Changing theme
- Changing language
- Syncing
- Rebuilding providers
- Rebuilding individual routes

Placing the stateful overlay at the stable application root should satisfy this requirement.

Confirm that the parent key and root widget are not recreated during routine app-state changes.

---

## Phase 4 — Preserve the Native Splash

Do not remove or modify the native Android splash.

Keep:

```text
flutter_native_splash.yaml
android/app/src/main/res/
```

The native splash covers the period before Flutter produces its first frame.

The new in-app overlay begins when Flutter renders.

Expected visual chain:

```text
Native splash with HomePilot artwork
        ↓
Animated Flutter splash with matching background
        ↓
Fade to the app
```

No native splash regeneration is required unless unrelated asset changes are made.

---

## Phase 5 — Testing

Create:

```text
test/homepilot_splash_overlay_test.dart
```

### Test 1 — App child is built immediately

Create a child widget that increments a counter in `initState`.

Pump `HomePilotSplashOverlay`.

Assert:

- Child exists immediately.
- Splash exists immediately.
- Child was initialized exactly once.

Purpose: prove the splash does not delay app construction.

### Test 2 — Splash disappears after fixed time

Pump the overlay.

Advance time to just before `displayDuration`.

Assert splash is still visible.

Advance through:

```text
displayDuration + fadeOutDuration
```

Assert splash is removed.

### Test 3 — Child remains mounted

Use a stateful test child with a stable state identifier.

Record the state instance before splash removal.

Advance time until the splash disappears.

Assert the same state instance remains.

Purpose: prove the splash does not rebuild or replace the app.

### Test 4 — No navigation occurs

Wrap the test in a `MaterialApp` with a `NavigatorObserver` spy.

Advance through the entire splash duration.

Assert:

- No push
- No replacement
- No pop
- No route change

Any route generated by initial test setup should be excluded from the post-start assertion window.

### Test 5 — No callback or app-state dependency

This should mostly be enforced structurally:

- No callback exists in the public API.
- No provider or state argument exists.
- No progress input exists.
- No route input exists.

Add a source-level or API-level assertion only if the repository already uses such tests.

### Test 6 — Small-screen layout

Pump at:

```text
320 × 568
```

Assert:

- No overflow exceptions
- Progress bar fits
- Main splash content is visible

### Test 7 — Large text scale

Pump with text scale around:

```text
1.5
```

Assert no overflow.

### Test 8 — Interaction blocking

Place a tappable child under the splash.

Tap while splash is visible.

Assert the child callback is not triggered.

Advance until the splash is removed.

Tap again.

Assert the child callback is triggered.

### Test 9 — Splash does not reappear on child rebuild

Trigger a rebuild of the underlying child while the splash is visible and after it is removed.

Assert:

- The original timer continues.
- The splash does not restart.
- After removal, it remains removed.

### Existing tests

Run and preserve:

```bash
flutter test test/startup_resources_test.dart
flutter test test/startup_benchmark_test.dart
flutter test test/initial_hydration_progress_test.dart
```

Then run the full suite:

```bash
flutter analyze
flutter test --concurrency=1
```

---

## Optional Golden Test

Recommended but not mandatory.

Create a golden test for:

```text
test/goldens/homepilot_splash_mobile.png
```

Suggested viewport:

```text
390 × 844
```

Freeze animation at a representative point, such as approximately 70% progress, to compare against the supplied visual reference.

Do not make the golden dependent on live app data, current time, locale, theme, or network state.

---

## Implementation Guardrails

The AI agent must reject any implementation that does one or more of the following:

```dart
Navigator.push(...)
Navigator.pushReplacement(...)
Navigator.pushNamed(...)
Navigator.pushReplacementNamed(...)
```

from splash code.

It must also reject:

- Reading providers from splash code
- Listening to streams
- Using app initialization futures
- Accepting a progress value
- Accepting an authentication state
- Accepting a route name
- Calling repositories or services
- Updating preferences
- Logging the user in or out
- Starting synchronization
- Triggering notifications
- Requesting permissions
- Initializing ads
- Changing app configuration
- Replacing `HomePilotApp` after a timer
- Delaying `runApp`
- Delaying the existing app builder
- Using global `SystemChrome.setSystemUIOverlayStyle` without restoration

---

## Suggested Final Class Responsibilities

### `HomePilotAnimatedSplashScreen`

Responsibility:

```text
Render the fixed HomePilot splash visuals and local animations.
```

Dependencies:

```text
Flutter UI primitives
Bundled splash image
Local animation controllers
```

No application dependencies.

### `HomePilotSplashOverlay`

Responsibility:

```text
Place the splash above an already-running child for a fixed time,
fade it out, and remove it.
```

Dependencies:

```text
Local timers
Local widget state
```

No application dependencies.

### `HomePilotApp`

Responsibility remains unchanged.

The only addition is using the overlay wrapper in its app-level builder.

---

## Acceptance Criteria

The task is complete only when all statements below are true.

### Visual

- The animated splash appears after the native Android splash.
- It closely matches the supplied screenshot.
- It displays the HomePilot image, wordmark, tagline, progress animation, status, and footer.
- It fades away smoothly.
- It has no visible white or dark flash between native splash, Flutter splash, and app.

### Isolation

- The real app is constructed immediately.
- The real app stays mounted behind the splash.
- The splash reads no app state.
- The splash writes no app state.
- The splash calls no app service.
- The splash performs no navigation.
- The splash receives no loading progress.
- The splash does not determine readiness.
- The splash is controlled only by a local fixed timer.

### Behavioral stability

- Existing authentication behavior is unchanged.
- Existing onboarding behavior is unchanged.
- Existing routing is unchanged.
- Existing deep-link behavior is unchanged.
- Existing startup resources are unchanged.
- Existing synchronization behavior is unchanged.
- Existing notification behavior is unchanged.
- Existing ad behavior is unchanged.
- Existing theme and localization behavior after the splash are unchanged.
- The splash appears only once per process launch.

### Quality

- No analyzer errors.
- No test regressions.
- No overflow at 320 px width.
- Timers are canceled in `dispose`.
- No uncaught animation or disposal exceptions.
- No global system UI style remains stuck after splash removal.
- Underlying controls cannot be tapped while the splash is visible.
- Underlying controls work normally after removal.

---

## Manual Verification Procedure

Build and install a debug APK:

```bash
flutter clean
flutter pub get
flutter gen-l10n
flutter run
```

Verify:

1. Kill the app completely.
2. Launch from the home screen.
3. Confirm the native splash appears first.
4. Confirm the animated splash appears next.
5. Confirm the app is not visible or tappable through the splash.
6. Wait for the fixed duration.
7. Confirm the splash fades out.
8. Confirm the correct existing app screen is revealed.
9. Navigate through the app.
10. Confirm the splash does not reappear.
11. Background and resume the app.
12. Confirm the splash does not reappear.
13. Sign in or sign out.
14. Confirm behavior is unchanged.
15. Launch using any supported deep link.
16. Confirm the same destination opens after the splash disappears.
17. Test offline.
18. Confirm the splash duration and behavior are identical.
19. Test on a narrow device or emulator.
20. Confirm there is no overflow.

---

## Deliverables

The AI agent should produce:

```text
Modified:
- lib/homepilot_animated_splash_screen.dart
- lib/main.dart

Added:
- test/homepilot_splash_overlay_test.dart

Optional:
- test/goldens/homepilot_splash_mobile.png
- golden test file or test case
```

The final implementation report should state:

- Exact files changed
- Fixed display duration used
- Fade-out duration used
- Confirmation that app initialization is not delayed
- Confirmation that no navigation occurs
- Confirmation that no app state is read or written
- Test commands run
- Test results
- Any visual deviations from the supplied screenshot

---

## Recommended Defaults

Use:

```text
Display duration: 3200 ms
Fade-out duration: 250 ms
Total visible lifecycle: approximately 3450 ms
```

These values preserve the current animation timing while keeping the behavior completely independent from the app.

---

## Rollback

Rollback is simple:

1. Remove the `HomePilotSplashOverlay` wrapper from the app-level builder.
2. Leave native Android splash configuration unchanged.
3. Optionally retain the presentation widget for future use or delete it if no longer needed.

No database, configuration, migration, route, or service rollback should be necessary.
