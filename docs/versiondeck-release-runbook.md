# VersionDeck Release Runbook

## Purpose

VersionDeck is the public static download site for verified HomePilot APK releases. It is not the build system and does not trust release notes alone. It independently verifies release artifacts before enabling downloads.

The authoritative implementation is:

- `download-site/`
- `tool/generate_versiondeck_manifest.mjs`
- `tool/versiondeck_apk_verifier.mjs`
- `tool/build_versiondeck_site.mjs`
- `tool/validate_versiondeck.mjs`
- current `tool/*.test.mjs` VersionDeck tests
- `.github/workflows/deploy-download-site.yml`

## Trust model

A release is downloadable only when the pipeline can verify the expected properties from trusted source and artifact evidence, including:

- GitHub release identity and state.
- APK digest.
- Android package/application ID.
- Version name and build number.
- Release/non-debuggable status.
- Signing certificate identity.
- Source/release ancestry where required.
- Available provenance or attestation evidence.

Live workflow status is informational. It must not grant download trust to an in-progress artifact.

## Pull-request validation

For changes affecting VersionDeck:

1. Check JavaScript syntax for all site modules, tools, and test files.
2. Run all current focused VersionDeck Node tests.
3. Build a revisioned static artifact into a temporary directory.
4. Run `tool/validate_versiondeck.mjs` on the generated artifact.
5. Review accessibility, reduced motion, responsive behavior, stale/error/offline states, and service-worker changes.

The workflow currently enumerates test files explicitly. When a new focused test file is added, update the canonical test command and workflow together so it cannot be skipped.

## Main/release deployment

The deployment workflow:

1. Checks out the current `main` source and verifies it matches `origin/main`.
2. Confirms required GitHub and Android verification tools.
3. Runs syntax checks and tests.
4. Discovers releases and independently verifies candidate APKs.
5. Generates the release manifest and diagnostics.
6. Builds revisioned static assets.
7. Validates the site.
8. Uploads diagnostics and the Pages artifact.
9. Deploys GitHub Pages with protected permissions.
10. Verifies the public manifest/site after deployment where implemented.

## Manifest rules

- The manifest schema is versioned.
- Verified release entries must be deterministic.
- Stable and prerelease selection must be explicit.
- Unknown or invalid fields must not silently enable downloads.
- Failed verification should produce diagnostics without publishing a trusted entry.
- The newest unverified release must not silently cause an older artifact to be represented as that release.

## Service-worker and cache rules

- Revision all application-shell assets when behavior changes.
- Update the precache list when adding or removing modules or styles.
- Separate shell caching from release-manifest freshness.
- Expired, missing, malformed, or unverifiable release metadata must disable or clearly constrain downloads.
- Offline UI must distinguish cached verified release data from live build status.
- Do not cache secrets or GitHub tokens in static assets.

## Build-status rules

The live-build card and timeline may show workflow state, jobs, steps, timestamps, and estimated progress. This information is untrusted operational context and must stay visually and logically separate from the currently verified stable APK.

See `versiondeck-live-build-status.md`.

## Accessibility

Validate:

- Keyboard navigation and visible focus.
- Semantic headings and status announcements.
- Color contrast and non-color state indicators.
- Responsive layout across narrow screens.
- Reduced-motion preferences.
- Clear disabled-download explanations.
- Stable download identity while a new build is active.

## Failure handling

- Fail closed when APK verification is incomplete.
- Preserve diagnostics for operator review.
- Do not manually edit `releases.json` to force acceptance.
- Do not bypass package, signer, checksum, ancestry, or provenance checks.
- Do not expose a token in the public site to obtain richer live status.
- If Pages deploys bad static behavior, correct source and redeploy; do not change verified release metadata independently.

## Post-deployment checks

- Load the public site in a fresh browser session.
- Confirm the manifest schema and latest stable/prerelease selection.
- Confirm the download link points to the expected verified GitHub artifact.
- Compare displayed version/build/checksum with release evidence.
- Verify stale/offline/error states.
- Verify service-worker update behavior.
- Verify live build status does not replace stable download identity.

## Evidence

Record source commit, workflow run, generated manifest summary, verified release IDs, static validation result, Pages deployment URL, and public smoke-test result.