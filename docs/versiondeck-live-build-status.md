# VersionDeck live production-build status

## Purpose

VersionDeck shows a live production-build card only while the `Build Production APK` workflow has an active run on `main`. The card occupies the space between the download hero and the latest-release section. It reports the current job step, completed and remaining steps, an estimated remaining duration, and a link to the public GitHub Actions run.

The feature is observational. It never starts, cancels, approves, or mutates a workflow run and never receives a GitHub token.

## User experience

When a production run is `queued`, `requested`, `waiting`, `pending`, or `in_progress`, VersionDeck displays:

- the workflow run number and a link to GitHub Actions;
- the current step, with a reduced-motion-aware activity indicator;
- an animated progress track;
- completed, total, and remaining step counts;
- estimated remaining time and estimation confidence;
- an expandable step list;
- an opt-in spoken-alert control.

The section remains hidden when no production run is active. On completion, VersionDeck announces the result and removes the card. In-page visual and ARIA live-region announcements are enabled by default. Speech and desktop notifications require an explicit user action and are persisted locally.

## Data source and security boundary

The browser reads only public workflow metadata from GitHub's REST API:

- workflow runs for `.github/workflows/build-production-android.yml`;
- jobs and step timestamps for the selected run;
- jobs and step timestamps for recent successful runs used for timing history.

No token or private repository data is embedded in the page. The Content Security Policy allows connections only to the site origin and `https://api.github.com`. API strings are treated as untrusted text, rendered with `textContent`, and run links are restricted to HTTPS `github.com` URLs.

## Active-run selection

VersionDeck filters workflow runs to:

- `head_branch === "main"`;
- `event === "workflow_dispatch"`;
- an active status of `queued`, `in_progress`, `requested`, `waiting`, or `pending`.

A running job takes precedence over a newer queued job. This ensures the card reports the build that is currently consuming the production concurrency group.

## Step model

The job endpoint exposes current and historical step states and timestamps. VersionDeck excludes GitHub-generated housekeeping entries:

- `Set up job`;
- `Complete job`;
- names beginning with `Post `.

Explicit cleanup steps in the production workflow remain visible because the workflow is not complete until they finish.

## ETA model

The estimate is calculated locally from the five most recent successful production jobs available in the initial workflow-run response.

For each successful job VersionDeck calculates:

1. duration of each visible step from `started_at` and `completed_at`;
2. the median duration for each step name;
3. median total visible-step duration;
4. lower and upper quartiles for future confidence-band support.

For an active build:

- the current step contributes its historical median minus elapsed time, with a conservative minimum remaining buffer;
- future steps contribute their historical median duration;
- the step-based estimate is blended with the total-build median when a job start time is available;
- missing step history falls back to the median duration across all known steps;
- queued or approval-waiting runs use the median total duration.

Confidence is reported as high, medium, or low based on sample count and historical coverage of unfinished steps. The timing model is cached for 24 hours and refreshed when the set of sampled successful run IDs changes.

## Polling and rate limits

VersionDeck uses unauthenticated public GitHub API requests. To remain within the IP-based limit:

- idle discovery: every 5 minutes while visible and every 10 minutes while hidden;
- active job refresh: every 90 seconds while visible and every 150 seconds while hidden;
- timing history: at most five additional job requests per 24-hour cache period;
- historical job requests are serialized;
- `403` and `429` responses honor `x-ratelimit-reset` when exposed and otherwise back off for 15 minutes;
- repeated failures hide the panel rather than showing stale active-build claims.

The browser pauses and restarts requests around offline, online, page visibility, and page lifecycle events.

## Alerts

Every meaningful transition produces:

- an ARIA `role=status` announcement;
- a temporary visible toast;
- spoken text when the user has enabled spoken alerts;
- a desktop notification when permission is granted and the document is hidden.

Transitions are deduplicated with a persisted snapshot containing the run ID, current step, and completed-step names. If multiple steps complete between polls, VersionDeck issues one concise summary rather than replaying each stale event.

Speech uses the browser's default `SpeechSynthesis` voice and is cancelled before a new transition is spoken. This prevents overlapping announcements.

## Accessibility and motion

- The card uses semantic headings, a real progress summary, and an ordered step list.
- Step changes are announced without moving keyboard focus.
- Alert controls expose `aria-pressed`.
- All motion stops under `prefers-reduced-motion: reduce`.
- The card and controls preserve the existing focus-ring and color-token system.
- The card is fully removed from layout with the native `hidden` attribute when inactive.

## Failure behavior

- Invalid or unavailable API data never enables a download or changes release verification.
- Three consecutive status failures hide the card.
- Rate-limit failures back off rather than retrying aggressively.
- Missing timing history shows `Calculating…` while live step counts remain available.
- Unsupported speech or notification APIs do not affect visual and screen-reader alerts.
- The production workflow remains authoritative; the card is informational and links to GitHub for exact logs.

## Test coverage

Unit tests cover:

- median calculations and outlier resistance;
- filtering generated housekeeping steps;
- historical per-step and total timing models;
- active-run selection when another run is queued;
- step counts, progress, ETA, and confidence;
- completed-step and next-step transition messages;
- concise duration formatting.

Static validation requires the build-status JavaScript and CSS, required DOM targets, the GitHub API CSP allowance, and both assets in the revisioned service-worker app shell.

## Acceptance criteria

- No card is visible without an active production workflow run.
- A queued, approval-waiting, or running production job displays within one discovery request.
- The current visible step matches the GitHub Actions job response.
- Completed and remaining counts exclude GitHub-generated post/setup entries.
- ETA is derived from previous successful jobs and identifies its sample count and confidence.
- A step transition creates one visible and screen-reader alert.
- Spoken alerts occur only after explicit opt-in.
- A completed run is announced and the card is hidden.
- API rate-limit responses suspend polling until a safe retry time.
- Existing release verification, bounded release caching, and offline behavior remain unchanged.

## Further improvements

These are intentionally outside the static-site implementation:

1. **Webhook-backed status feed and Web Push.** A small GitHub App or edge function could receive workflow webhooks, publish a compact signed status document, and deliver notifications when VersionDeck is closed. This would eliminate browser polling and provide near-instant transitions.
2. **Cross-device alert preferences.** Signed-in preference synchronization could preserve speech and notification choices across installations.
3. **Confidence interval visualization.** The stored quartiles can support a typical-duration range after enough successful runs exist.
4. **Queue visibility.** The card could show additional queued production runs without confusing them with the currently executing run.
5. **Build-health trends.** A separate historical view could show median duration and failure-rate trends without expanding the primary download page.
