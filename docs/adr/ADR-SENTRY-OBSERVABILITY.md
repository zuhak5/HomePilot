# ADR: Privacy-Preserving Sentry Observability

- Status: Accepted
- Date: 2026-08-03
- Scope: Flutter application, Android background execution, and production release pipeline

## Context

HomePilot has local diagnostics, Supabase synchronization, authentication, a foreground restore worker, and a guarded signed-APK release workflow. Local diagnostics are useful when a user explicitly exports them, but they do not provide automatic crash grouping, native crash handling, release correlation, symbolication, or sampled performance visibility.

HomePilot processes account, home, maintenance, media, location, and authentication data. A conventional unrestricted telemetry integration could expose identifiers, free-form content, local paths, network payloads, or third-party trace headers. Observability must therefore be useful without becoming an additional user-data system.

## Decision

HomePilot will use `sentry_flutter` with the Sentry EU project `homepilot-qt/homepilot` and the following controls.

### Identity and data minimization

- Do not set a Sentry user.
- Do not send Supabase or Google identifiers, email, account metadata, location, content names, notes, tokens, request bodies, response bodies, notification payloads, or local paths.
- Use a per-process diagnostic run identifier only.
- Permit only reviewed bounded tags, extras, breadcrumbs, routes, and span attributes.
- Pass every event, transaction, and breadcrumb through the HomePilot scrubber.
- Suppress expected and recoverable operational failures.

### Disabled features

- session replay
- screenshots
- view hierarchy attachments
- user-interaction tracing and breadcrumbs
- automatic logs
- profiling
- default PII
- broad distributed trace propagation

### Error and performance model

- Preserve Sentry's automatic Flutter, Dart, native crash, ANR, lifecycle, frame, and session handling where compatible with the privacy controls.
- Bridge HomePilot's redacted structured logger into bounded breadcrumbs and deduplicated reportable exceptions.
- Trace selected startup, authentication, synchronization, and restore operations manually.
- Use operation-based production sampling rather than unrestricted high-rate tracing.
- Initialize the foreground restore engine independently and contain its failures.
- Bound Sentry initialization so an observability failure cannot indefinitely delay the application.

### Release model

- Release identifier: `com.homepilot.app@<version>+<build>`.
- Dist: Android build number.
- Build and upload only in the existing GitHub Actions production workflow from `main`.
- Associate commits, upload debug files, finalize the Sentry release, record a `prod` deploy, and verify the release before publishing the GitHub Release.
- Keep `SENTRY_AUTH_TOKEN` only in the GitHub `production` environment secret.

## Consequences

### Positive

- Dart, Flutter, native crash, and ANR reports are grouped by release.
- Release regressions can be traced to commits and deployments.
- Selected application operations have performance visibility.
- User identity and free-form domain content are excluded by design.
- Existing local diagnostic export remains independent and user-controlled.
- Sentry outages do not block runtime application behavior.

### Tradeoffs

- Strict scrubbing removes some data that could accelerate debugging.
- No raw HTTP spans or distributed third-party tracing are available.
- Sampling means not every successful transaction is retained.
- Background engines require separate initialization and testing.
- Production releases fail when required Sentry release processing fails.

## Alternatives considered

### Upload local diagnostic ZIP files automatically

Rejected. The ZIP is broader than the minimum data needed for automated issue grouping and is designed for explicit user export.

### Enable Sentry defaults including PII and automatic integrations

Rejected. Default integrations can capture identifiers, URLs, request data, UI interactions, or high-cardinality values that are inappropriate for HomePilot.

### Use only crash reporting without release or symbol upload

Rejected. Uncorrelated and unsymbolicated production crashes have materially lower diagnostic value.

### Add unrestricted HTTP instrumentation

Rejected for the initial implementation. Supabase, advertising, weather, and location traffic have different privacy characteristics. Manual operation spans provide useful timing without propagating traces or capturing URLs and payloads.

### Build or verify production APKs locally

Rejected. The existing GitHub Actions workflow provides protected signing material, a main-branch guard, deterministic verification, checksum generation, provenance attestation, and controlled publication.

## Review triggers

Revisit this decision before:

- enabling replay, screenshots, view hierarchy, logs, profiling, or HTTP instrumentation
- adding account identifiers or user content
- changing data region or Sentry project
- changing trace propagation targets
- changing release naming or obfuscation
- allowing a production build outside GitHub Actions
- attaching diagnostic exports or media
