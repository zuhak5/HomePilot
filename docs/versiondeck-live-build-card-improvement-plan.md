# VersionDeck live-build card improvement plan

## Objective

Make the production-build status useful at a glance on mobile without hiding the exact GitHub Actions data. The compact card should answer four questions immediately:

1. What phase is running?
2. Which exact task is active?
3. How far through the workflow is it?
4. What is the realistic remaining-time range?

Technical steps remain available as an optional drill-down.

## Problems identified from the current screens

- The full 18-step list can consume most of the viewport.
- Raw workflow-step names are given more visual weight than user-readable progress.
- `8 of 18 complete · 10 left` includes the active step and is harder to interpret than a current step number.
- A single ETA such as `About 11 minutes` communicates more precision than four historical samples justify.
- The spoken-alert button looks like a one-time action instead of a persistent preference.
- Speech and desktop notifications share one control even though they have different permissions and behavior.
- The notification toast is narrow, overlaps content, and is difficult to scan on mobile.
- The sticky download label does not explicitly distinguish the current stable APK from the build in progress.
- Existing service workers can retain the prior build-card assets under stable URLs.

## Implementation workstreams

### 1. Compact information hierarchy

- Rename the heading to `Building HomePilot APK`.
- Move the run link into a compact button in the header.
- Show elapsed time and freshness beside the run.
- Present a user-readable phase as the primary live state.
- Present the exact GitHub Actions task as secondary text.
- Use a slightly taller progress track and a visible percentage.

### 2. Phase-based progress

Group production steps into these phases:

1. Preparing the build
2. Building and testing the APK
3. Verifying the release
4. Publishing diagnostics
5. Publishing the release
6. Finishing securely

Unknown future steps fall back to `Processing the release` and remain visible in the technical list.

### 3. Honest progress and ETA

- Display `Step N of M`.
- Display the number of steps after the current step rather than counting the active step as unfinished.
- Calculate an ETA range from the lower and upper quartiles of recent successful build durations.
- Retain the median estimate as the center point.
- Show historical sample count and confidence separately.
- Show elapsed runtime.
- Preserve conservative fallback behavior when history is missing.

### 4. Bounded step disclosure

- Always show a three-item preview: previous, current, and next.
- Keep the exact technical list collapsed by default.
- Label the disclosure with the actual step count.
- Limit the expanded list height and make it internally scrollable on small screens.
- Preserve status markers for completed, active, queued, and failed steps.

### 5. Alert preferences

- Replace the old alert button with a full-width switch-style control.
- Give the control a clear label, behavioral description, state text, and switch indicator.
- Separate spoken updates from desktop notifications.
- Request notification permission only from the desktop-notification control.
- Migrate the previous combined preference to spoken updates only.
- Keep visual and screen-reader announcements always enabled.

### 6. Full-width toast

- Replace the floating narrow toast with a full-width status bar above the sticky download control.
- Add state-specific indicators for informational, successful, and failed events.
- Add a visible dismiss control.
- Keep automatic dismissal after eight seconds.
- Use safe-area padding and reduced-motion behavior.
- Prevent the toast from obscuring the sticky download action.

### 7. Terminal states

- Retain a successful or failed state for 60 seconds after the workflow finishes.
- On success, show `Release published`.
- On failure, retain the failed phase and exact failed task.
- Keep the workflow-run link available.
- Announce completion once, then return to idle discovery.

### 8. Cache and deployment behavior

- Load build-status JavaScript and CSS through versioned URLs.
- Keep stable asset paths in the revisioned service-worker app shell.
- Ensure an older worker misses the versioned request and fetches the new assets.
- Extend static validation to require the versioned assets and new accessible controls.

## Test coverage

Unit tests cover phase assignment, three-step previews, step-number semantics, ETA bounds, elapsed-time formatting, terminal snapshots, transition announcements, run selection, median calculation, and hidden-step behavior.

Static validation covers all required live-build DOM targets, separate speech and notification controls, full-width toast targets, versioned JavaScript and CSS URLs, and continued service-worker precaching.

## Acceptance criteria

- The collapsed card fits within one normal mobile viewport in common mid-build states.
- The primary status uses a readable phase and the exact workflow task remains visible.
- Progress reads `Step N of M` and does not ambiguously count the active step as complete.
- ETA is displayed as a range whenever historical variance is meaningful.
- Only three step-context rows are visible before expansion.
- Spoken updates and desktop notifications can be controlled independently.
- The spoken-update control occupies the full card width and exposes `aria-pressed`.
- Toasts occupy the full viewport width above the sticky download bar and can be dismissed.
- Reduced-motion users receive no spinning, pulsing, shimmer, sliding, or switch animation.
- Existing release verification and download behavior remain unchanged.
