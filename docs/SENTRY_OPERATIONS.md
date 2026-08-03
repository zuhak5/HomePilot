# HomePilot Sentry Operations

## Production configuration

HomePilot uses one Sentry project:

- Organization slug: `homepilot-qt`
- Project slug: `homepilot`
- Data region: European Union
- Flutter environment: `prod`
- Release format: `com.homepilot.app@<version>+<build>`
- Dist: Android build number

The GitHub `production` environment must provide these variables:

- `SENTRY_ORG`
- `SENTRY_PROJECT`
- `SENTRY_DSN`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `GOOGLE_WEB_CLIENT_ID`

It must provide these secrets:

- `SENTRY_AUTH_TOKEN`
- Android signing secrets already required by the release workflow

Never commit the authentication token, production JSON configuration, signing properties, or keystore.

## Build and release policy

The signed production APK is built only by `.github/workflows/build-production-android.yml` on GitHub Actions. The workflow refuses non-`main` refs and verifies that the selected commit belongs to `origin/main`.

Do not run any of these locally as part of the Sentry implementation or release process:

```text
flutter build apk
flutter build appbundle
gradlew assemble*
gradlew bundle*
tool/build_prod.ps1
```

Local validation is limited to dependency resolution, code generation, formatting, analysis, tests, and static review of scripts and workflow YAML.

## Release sequence

The production workflow performs these operations in order:

1. Verify the release commit belongs to `main`.
2. Parse the version and build from `pubspec.yaml`.
3. Derive `SENTRY_RELEASE` and `SENTRY_DIST`.
4. Create `config/prod.json` from protected GitHub environment values.
5. Restore Android signing credentials.
6. Run analysis and tests, then build the signed prod release APK.
7. Verify package name, version, build, checksum, signer, and non-debuggable status.
8. Create or reuse the matching Sentry release.
9. Associate Git commits with the Sentry release.
10. Upload available debug files through `sentry_dart_plugin`.
11. Finalize the Sentry release and record a `prod` deploy.
12. Verify the Sentry release can be read back.
13. Upload and attest the APK.
14. Publish the GitHub Release.

A Sentry failure stops the release before GitHub Release publication. The Sentry network operations receive one bounded retry; failures are not silently ignored.

## Triggering a production release

After the implementation has been reviewed and merged into `main`, use the GitHub Actions interface to run **Build Production APK** and provide a non-empty release changelog.

CLI equivalent for an authorized operator:

```powershell
gh workflow run build-production-android.yml `
  --ref main `
  -f changelog="Describe the production changes"

gh run watch
```

Do not change `--ref main` or weaken the workflow branch guard.

## Post-release verification

Confirm all of the following:

- GitHub Actions completed successfully.
- The workflow produced exactly one signed prod release APK.
- Package is `com.homepilot.app`.
- APK version and build match `pubspec.yaml`.
- Checksum, signer verification, and provenance attestation passed.
- Sentry contains the matching release and `prod` deploy.
- Events and transactions use the same release and dist.
- Stack traces show application frames rather than unresolved native addresses.
- No event contains email, Supabase user ID, token, precise location, user content, local path, request body, screenshot, view hierarchy, or replay data.

## Expected telemetry

Useful issue categories include:

- unhandled Dart or native crashes
- Android application-not-responding events
- violated application invariants
- repeated restore-worker failures
- non-retryable synchronization or account-deletion defects
- startup and synchronization performance regressions

The implementation suppresses expected or recoverable conditions such as cancellation, temporary offline state, expired authentication, permission denial, and synchronization conflict.

## Privacy review

For every newly added tag, extra, breadcrumb, span attribute, or exception boundary:

1. Add only bounded operational values.
2. Do not add identifiers or free-form user content.
3. Update the allowlist in `sentry_event_scrubber.dart` only after review.
4. Add a scrubber test proving sensitive values are removed.
5. Confirm `sendDefaultPii`, screenshots, view hierarchy, replay, logs, profiling, and broad trace propagation remain disabled.
6. Confirm Sentry-side default scrubbing and prevention of IP-address storage remain enabled.

The local diagnostic ZIP remains user-exported only and is never attached to Sentry.

## Triage procedure

For a new issue:

1. Confirm environment, release, dist, and operation.
2. Check whether the event should have been classified as expected or recoverable.
3. Inspect stack frames and bounded breadcrumbs; do not request user content unless required through a separate support process.
4. Compare the first-seen release with the associated commit range.
5. Reproduce using a controlled account and non-production data where possible.
6. Link the fix to the Sentry issue and verify it in the next release.

For a performance regression:

1. Compare the same transaction across releases.
2. Check sample count before drawing conclusions.
3. Inspect operation-level spans rather than enabling unrestricted HTTP instrumentation.
4. Change sample rates only through reviewed production configuration changes.

## Rollback

Application telemetry can be disabled in development through configuration. Production configuration intentionally fails closed when Sentry is missing or disabled.

If Sentry blocks an urgent production release because of a service incident:

1. Do not expose or remove the authentication token.
2. Preserve the application-side privacy configuration.
3. Record the incident and exact failed command.
4. Retry the failed workflow once after Sentry recovers.
5. Use a reviewed emergency change only when the release owner explicitly accepts shipping without release association or symbol upload.

Do not bypass the workflow by producing a local APK.
