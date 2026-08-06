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

## Workflow triggers and release handoff

VersionDeck retains separate triggers for distinct operational needs:

- Pull requests validate VersionDeck source changes without deploying.
- Relevant pushes to `main` rebuild the site after VersionDeck source or runbook changes.
- Release lifecycle events rebuild the manifest after a release is edited, deleted, unpublished, promoted, or otherwise changed.
- Manual dispatch supports an explicitly requested rebuild.
- A `workflow_run` handoff starts VersionDeck after the protected **Build Production APK** workflow completes successfully on `main`.

The automated production handoff is deliberately fail-closed:

1. The upstream workflow name must be `Build Production APK`.
2. The upstream event must be `workflow_dispatch`.
3. The upstream branch must be `main`.
4. The upstream conclusion must be `success`.
5. The upstream build commit must remain an ancestor of the current `main`.
6. VersionDeck then discovers and independently verifies the published release; it does not trust the upstream conclusion as artifact evidence.

Failed, cancelled, skipped, or non-production upstream runs do not deploy VersionDeck. Release lifecycle triggers remain necessary because operators can edit or remove releases independently of a new APK build. Shared Pages concurrency serializes production deployment runs without cancelling an active publish; GitHub may replace an older pending run with a newer pending revision.

The upstream production workflow is manual and protected. Do not broaden the `workflow_run` source to an untrusted pull-request workflow because downstream workflows can receive repository permissions unavailable to the upstream run.

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

1. Validates the trigger and, for `workflow_run`, confirms the successful protected production-build handoff.
2. Checks out the current `main` source and verifies it matches `origin/main`.
3. Confirms a chained production-build commit remains in the current `main` history.
4. Confirms required GitHub and Android verification tools.
5. Runs syntax checks and tests.
6. Discovers releases and independently verifies candidate APKs.
7. Generates the release manifest and diagnostics.
8. Builds revisioned static assets.
9. Validates the site.
10. Uploads diagnostics and the Pages artifact.
11. Deploys GitHub Pages with protected permissions. The Pages action may poll for up to 20 minutes before declaring a deployment timeout, while the deployment job allows additional time for the public-manifest check.
12. Verifies the public manifest after deployment.

The Pages workflow uses the current Node.js 24-compatible major versions of `actions/configure-pages`, `actions/upload-pages-artifact`, and `actions/deploy-pages`. Upgrade these actions together when GitHub publishes a new supported major so the artifact and deployment contracts remain aligned.

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
- If the production build fails or is cancelled, do not manually represent it as a verified release.
- If the chained VersionDeck run fails after a successful APK release, keep the existing verified site live, inspect diagnostics, and rerun VersionDeck manually only after confirming the release evidence.
- If `actions/deploy-pages` remains `deployment_in_progress` until its timeout, confirm that no Pages deployment is still active or queued, retain the existing live site, and rerun the VersionDeck workflow. Do not rebuild or republish the APK solely because Pages timed out.
- If Pages deploys bad static behavior, correct source and redeploy; do not change verified release metadata independently.

## Post-deployment checks

- Confirm the successful production workflow has a corresponding VersionDeck workflow run.
- Load the public site in a fresh browser session.
- Confirm the manifest schema and latest stable/prerelease selection.
- Confirm the download link points to the expected verified GitHub artifact.
- Compare displayed version/build/checksum with release evidence.
- Verify stale/offline/error states.
- Verify service-worker update behavior.
- Verify live build status does not replace stable download identity.

## Evidence

Record the production workflow run, production source commit, VersionDeck workflow run, VersionDeck source commit, generated manifest summary, verified release IDs, static validation result, Pages deployment URL, and public smoke-test result.
