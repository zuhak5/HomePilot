# VersionDeck live-build mobile UI hardening plan

## Objective

Make the live production-build card readable and reliable on narrow mobile screens without changing the polling, release verification, speech, or notification trust model.

## Problems confirmed from production screenshots

1. The technical workflow overflows horizontally and clips long step names.
2. The disclosure label can extend beyond the card edge.
3. The technical list uses a nested scroll region that conflicts with normal page scrolling and the sticky download bar.
4. Every technical-step marker appears active because the existing CSS selector matches the active parent section rather than the individual step.
5. The first workflow step is shown as `0%`, which reads as contradictory while work is actively starting.
6. The phase label `Processing the release` is too generic and can be wrong for source checkout and build setup.
7. Elapsed time is repeated in both header metadata and a separate green-dot row.
8. Progress and ETA occupy separate large cards, increasing vertical length.
9. Alert controls are clear but taller than necessary.
10. The card does not identify the target app version and build number.

## Implementation workstreams

### 1. Overflow and wrapping

- Apply `min-width: 0` and `max-width: 100%` to every grid and flex descendant that can contain workflow text.
- Allow technical-step labels and disclosure text to wrap with `overflow-wrap: anywhere`.
- Remove horizontal overflow and the technical list's internal `max-height` scrolling.
- Let the document perform normal vertical scrolling so the browser and sticky download bar behave predictably.

### 2. Correct state markers

- Scope completed, active, failed, and pending marker styles to each `.build-step-item` or `.build-preview-item`.
- Prevent the active state on the parent build section from styling every descendant marker.
- Use green for completed, animated blue for current, outlined neutral for pending, and red for failed.

### 3. User-readable phases

Group the exact GitHub Actions steps into these phases:

1. Preparing source
2. Configuring production build
3. Building and testing APK
4. Verifying APK and release
5. Publishing release
6. Finalizing securely

The current exact task remains visible below the phase name.

### 4. Technical workflow disclosure

- Replace the flat 18-step list with phase groups.
- Show a completed/total counter for each phase.
- Automatically expand the active or failed phase.
- Keep completed and future phases collapsed until the user opens them.
- Use the shorter disclosure labels `Show technical workflow` and `Hide technical workflow`.

### 5. Progress and ETA semantics

- Present `Starting` instead of `0%` during the first active step.
- Use an indeterminate progress animation during that initial state while keeping accurate progressbar text for assistive technology.
- Combine progress and ETA into one shared information surface.
- Preserve the historically calculated ETA range and confidence information.
- Remove the duplicated elapsed-time row; the header metadata remains authoritative.

### 6. Target release context

- Read the current `pubspec.yaml` version from the public GitHub Contents API once per browser session.
- Display `Building HomePilot <version>` and `Build <number> · Production APK`.
- Clarify the sticky action with `Current stable APK · <target version> building` while an active production run exists.
- Fail softly when the public metadata lookup is unavailable.

### 7. Alert-control compression

- Add a compact `Build alerts` heading and browser-lifetime note.
- Reduce control height and padding while retaining full-width hit targets.
- Keep spoken updates and desktop notifications separate.
- Preserve `aria-pressed`, disabled, unavailable, and blocked states.

### 8. Cache and deployment integration

- Load the UI correction CSS and JavaScript as versioned static assets.
- Include both assets in the revisioned service-worker application shell.
- Expand static validation to require the files, versioned references, and service-worker entries.

## Test coverage

Automated tests cover:

- Exact-step-to-phase mapping.
- Stable phase grouping without reordering steps.
- `pubspec.yaml` version/build parsing.
- The first-step `Starting` state.
- Existing VersionDeck syntax, unit, static-build, Flutter, and production-schema gates.

## Acceptance criteria

- No technical step or disclosure label is clipped at 320 px viewport width.
- No horizontal scrollbar appears inside the build card.
- The technical workflow uses normal page scrolling.
- Only the actual current step has the active marker.
- The current or failed phase expands automatically.
- The initial active step displays `Starting`, not `0%`.
- The card identifies the target version and build when public metadata is available.
- Alert controls remain keyboard accessible and at least 44 px tall.
- Existing speech, desktop notification, transition announcement, polling, and ETA behavior remains operational.
