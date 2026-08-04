# VersionDeck Live Build Status

## Purpose

VersionDeck may display the status of an active HomePilot production build while continuing to offer the most recently verified stable APK. Build status is informational and must not be confused with release verification.

## Data domains

### Verified release data

Generated from independently inspected release artifacts. It controls download availability and includes verified identity such as version, build, checksum, signer, and release references.

### Live build data

Derived from GitHub Actions workflow and job state. It can describe queued, running, completed, cancelled, or failed work and may be incomplete, delayed, unavailable, or rate-limited.

These domains must remain separate in code, cache policy, and UI.

## State model

Recommended build-card states:

- Hidden: no relevant active or recent build context.
- Loading: status request in progress.
- Queued: workflow accepted but execution has not started.
- Active: one or more build steps are running.
- Succeeded: workflow completed; release verification may still be pending.
- Failed: workflow or required job failed.
- Cancelled: workflow was cancelled or superseded.
- Stale: cached state exceeds freshness policy.
- Unavailable: status cannot be fetched or interpreted safely.

A succeeded build is not automatically a downloadable release.

## Timeline model

The timeline should present meaningful phases rather than every low-level log line. Completed, active, waiting, failed, and cancelled states require both visual and textual indicators.

- Completed markers must be distinguishable without relying only on color.
- The active step should be announced and visually emphasized.
- Waiting steps should not imply failure.
- Failed/cancelled context should explain that the current stable APK remains separate.
- Estimated progress must be clearly approximate.

## Sticky download context

When a new build is active, the sticky download area may show compact build context, but its primary identity remains the current verified stable APK. The UI must not replace the stable version label with an unverified target version.

## Freshness and cache policy

- Build status should use a short freshness window appropriate to operational data.
- Verified release metadata can use a different cache policy because it is artifact-derived.
- Stale build data should be labeled or hidden, not represented as live.
- A cached successful build must not enable a download.
- Service-worker changes must revision assets and preserve recovery from old caches.

## Failure and privacy

The public site must not require a private GitHub token. Error messages should avoid exposing workflow internals, repository secrets, actor emails, or raw API payloads. Rate-limit or network failure should degrade to a safe informational state.

## Accessibility and motion

- Use semantic status text.
- Ensure keyboard and screen-reader access.
- Announce material state transitions without excessive repetition.
- Preserve contrast in all states.
- Disable nonessential animation when `prefers-reduced-motion` is set.
- Avoid continuous motion that obscures the current step.

## Testing

Cover target-version parsing, phase mapping, completed/active/waiting/failed states, missing jobs, reordered steps, cancelled runs, stale timestamps, unavailable APIs, cache fallback, reduced motion, small screens, sticky stable identity, and success-before-release-verification.

Whenever a new module or test file is added, update the service-worker app shell, syntax checks, test command, and deployment workflow together.