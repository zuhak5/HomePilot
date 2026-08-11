# VersionDeck Release Runbook

> **Containment status:** GitHub Pages and all public VersionDeck paths were
> unpublished on 2026-08-11. The root, release manifest, and public browser
> account-deletion page are intentionally unavailable, and the deployment
> workflow object is disabled. Cached release records containing the last live
> manifest are beyond the executable 24-hour cache limit and disable downloads.
> Do not republish or manually re-enable the workflow; see the
> [TASK-001 containment record](operations/production-containment.md).

## Purpose

VersionDeck is the public static site for verified HomePilot APK releases and HomePilot's external account-deletion page. The release area is not the build system and does not trust release notes alone; it independently verifies release artifacts before enabling downloads. The account-deletion area is a separate authenticated client of the protected Supabase deletion backend and must not affect release trust.

The authoritative implementation is:

- `download-site/`
- `tool/generate_versiondeck_manifest.mjs`
- `tool/versiondeck_apk_verifier.mjs`
- `tool/build_account_deletion_site.mjs`
- `tool/build_versiondeck_site.mjs`
- `tool/validate_versiondeck.mjs`
- current `tool/*.test.mjs` VersionDeck tests
- `.github/workflows/deploy-download-site.yml`

The deletion backend authority is [`supabase/functions/delete-account/index.ts`](../supabase/functions/delete-account/index.ts). Pages contains only public configuration and browser code; it never contains service-role credentials.

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

## Account-deletion surface

The canonical page is `https://zuhak5.github.io/HomePilot/account-deletion.html`. Its browser flow uses Google OAuth with PKCE, consumes the callback verifier from `sessionStorage`, and keeps the resulting access token only in the current page's JavaScript memory. A page reload requires a new sign-in, but an unresolved deletion can resume status recovery from the 32-byte recovery key and expected user ID stored for that operation in `sessionStorage`. Destructive controls remain hidden until identity lookup; the page then shows a masked account identity and keeps the delete button disabled until the user selects an explicit permanent-deletion confirmation.

The page creates one 43-character unpadded base64url recovery key with Web Crypto and sends it with the confirmation to `POST /functions/v1/delete-account`. It reports success only after that response or `POST /functions/v1/account-deletion-status` returns `deleted: true`, `status: "deleted"`, and the authenticated/expected user's exact `user_id`. Ambiguous, pending, temporary, malformed, or mismatched results do not become success, and recovery reuses the same key. Redirect completion, Google sign-in, or a generic successful HTTP status is not deletion evidence. The browser page performs remote deletion only; it cannot erase installed-device databases, media, notifications, caches, secure storage, or user-exported backups.

Public configuration is generated during the static build. See [`reference/configuration.md`](reference/configuration.md#public-browser-account-deletion) for the three required repository variables and their validation rules.

## Workflow triggers and release handoff

VersionDeck keeps validation and production publication deliberately separate:

- Pull requests validate VersionDeck source changes without deploying.
- A `workflow_run` handoff starts VersionDeck after the protected **Build Production APK** workflow completes successfully on `main`.
- Manual dispatch is a recovery path and requires the run ID of a successful **Build Production APK** run for the current `main` SHA.

Push and GitHub Release events do not deploy Pages. This prevents a source push or the APK workflow's intermediate Release publication step from racing the required backend, APK, and final VersionDeck sequence. The Play AAB remains an independent exact-SHA evidence rail.

The automated production handoff is deliberately fail-closed:

1. The upstream workflow name must be `Build Production APK`.
2. The upstream event must be `workflow_dispatch`.
3. The upstream branch must be `main`.
4. The upstream conclusion must be `success`.
5. The upstream build commit must exactly equal the current `main` SHA and the checked-out VersionDeck source.
6. VersionDeck then discovers and independently verifies the published release; it does not trust the upstream conclusion as artifact evidence.

Failed, cancelled, skipped, stale-SHA, or non-production upstream runs do not deploy VersionDeck. Release edits or removals require a reviewed recovery dispatch tied to the successful current-SHA APK run; they do not bypass artifact provenance. Shared Pages concurrency serializes production deployment runs without cancelling an active publish; GitHub may replace an older pending run with a newer pending revision.

The upstream production workflow is manual and protected. Do not broaden the `workflow_run` source to an untrusted pull-request workflow because downstream workflows can receive repository permissions unavailable to the upstream run.

## Pull-request validation

For changes affecting VersionDeck:

1. Check JavaScript syntax for all site modules, tools, and test files.
2. Run all current focused VersionDeck Node tests.
3. Build a revisioned static artifact into a temporary directory.
4. Run `tool/validate_versiondeck.mjs` on the generated artifact.
5. Review accessibility, reduced motion, responsive behavior, stale/error/offline states, and service-worker changes.

Pull-request builds must pass `--allow-inert-account-deletion-config true` explicitly to `tool/build_versiondeck_site.mjs`. This creates a disabled, non-production configuration only for static validation. Browser sign-in must remain disabled in that artifact, and the flag must never appear in the production build step.

The workflow currently enumerates test files explicitly. When a new focused test file is added, update the canonical test command and workflow together so it cannot be skipped.

## Main/release deployment

This section is the post-containment deployment contract. Its steps must not be
run until the containment record's VersionDeck/Pages prerequisites are met.

The deployment workflow:

1. Validates the trigger and confirms the successful protected production-build handoff (or the explicitly supplied recovery run ID).
2. Checks out the APK run's source and verifies it exactly matches `origin/main`.
3. Confirms the APK run, checked-out source, and deployment source are the same SHA.
4. Confirms required GitHub and Android verification tools.
5. Runs syntax checks and tests.
6. Discovers releases and independently verifies candidate APKs.
7. Generates the release manifest and diagnostics.
8. Requires and validates the three public account-deletion variables, then builds revisioned static assets. Missing or mismatched production values fail before site output is replaced or emitted.
9. Validates the site.
10. Uploads diagnostics and the Pages artifact.
11. Deploys GitHub Pages with protected permissions. The Pages action may poll for up to 20 minutes before declaring a deployment timeout, while the deployment job allows additional time for the public-manifest check.
12. Verifies the public manifest after deployment.

The Pages workflow does not apply the deletion-recovery migration, deploy either `delete-account` or `account-deletion-status`, or perform a destructive hosted browser test. Apply and verify the compatible migration and both functions first. The Pages production build consumes only GitHub repository variables through the `vars` context; it has no inert or placeholder fallback.

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
- Treat `account-deletion.html` as a network-only navigation with `cache: "no-store"`. It must not overwrite the cached VersionDeck root and must never fall back to cached `index.html`.
- Keep account-deletion HTML, CSS, JavaScript, and generated public configuration out of the application-shell precache. The build adds a source-revision query to deletion CSS, JavaScript, and configuration URLs.
- When deletion navigation is offline under service-worker control, return the explicit network-required `503` response. Never render the cached release page as if it were the deletion flow.

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
- If the chained VersionDeck run fails after a successful APK release, keep the existing verified site live, inspect diagnostics, and rerun VersionDeck manually with that successful current-SHA APK run ID only after confirming the release evidence.
- If `actions/deploy-pages` remains `deployment_in_progress` until its timeout, confirm that no Pages deployment is still active or queued, retain the existing live site, and rerun the VersionDeck workflow. Do not rebuild or republish the APK solely because Pages timed out.
- If Pages deploys bad static behavior, correct source and redeploy; do not change verified release metadata independently.
- If any required public deletion-site variable is absent or rejected, leave the current live site untouched and correct repository configuration. Never enable the inert pull-request flag in production.
- If the hosted function, Google callback, CORS contract, or strict receipt check fails, do not describe browser deletion as operational. Retain the in-app method, correct the backend/configuration, and rerun hosted smoke validation.

## Post-deployment checks

- Confirm the successful production workflow has a corresponding VersionDeck workflow run.
- Load the public site in a fresh browser session.
- Confirm the manifest schema and latest stable/prerelease selection.
- Confirm the download link points to the expected verified GitHub artifact.
- Compare displayed version/build/checksum with release evidence.
- Verify stale/offline/error states.
- Verify service-worker update behavior.
- Verify live build status does not replace stable download identity.

### Account-deletion hosted smoke

Use a disposable Google/Supabase account with non-sensitive test rows and private test media. Do not use a personal account, and do not put an access token, OAuth code, email address, user ID, or raw deletion response in logs, screenshots, workflow summaries, or retained artifacts.

1. Confirm the deletion-recovery migration and reviewed `delete-account` and `account-deletion-status` function versions are deployed to the intended Supabase project, and that the canonical deletion URL is allowlisted in Supabase Auth redirect configuration.
2. Confirm the repository variables documented in [`reference/configuration.md`](reference/configuration.md#public-browser-account-deletion) are set, then record the successful VersionDeck build and Pages deployment revisions.
3. In a fresh browser profile, load the canonical deletion page. It must not show the unavailable-configuration state, and browser developer tools must show revisioned same-origin deletion assets with no service-role value.
4. Verify the production preflight independently:

   ```powershell
   curl.exe --silent --show-error --dump-header - --output NUL --request OPTIONS `
     --header "Origin: https://zuhak5.github.io" `
     --header "Access-Control-Request-Method: POST" `
     --header "Access-Control-Request-Headers: authorization,apikey,content-type" `
     "https://iajvkvvvhwjdiuaufymh.supabase.co/functions/v1/delete-account"
   ```

   Expect HTTP `204`, `Access-Control-Allow-Origin: https://zuhak5.github.io`, `Vary: Origin`, and the documented methods and headers. Repeat for `/functions/v1/account-deletion-status` with `Access-Control-Request-Headers: apikey,content-type`, then repeat both with an unapproved origin and expect rejection with no allow-origin header. Do not use wildcard expectations.
5. Start Google sign-in and verify the browser returns to the exact canonical callback, removes OAuth parameters from the address bar, shows a generic verified-identity state without displaying an email address, and leaves deletion disabled until the confirmation checkbox is selected.
6. Submit deletion once. Exercise an ambiguous-response/reload recovery where controlled tooling permits, confirm status lookup reuses the original logical-operation key, and confirm the browser reports success only after the strict receipt check. In protected backend tooling, verify the disposable Auth user, owned Postgres rows, and private `user-media` objects are removed. Redact the matching `user_id` and never retain the recovery key.
7. Confirm an installed test client for that deleted account observes a revoked/deleted session and follows local cleanup or recovery. Record this separately: the browser receipt alone cannot prove device-local cleanup.
8. With a VersionDeck service worker already controlling the site, switch the browser offline and reload the deletion URL. Expect the explicit network-required response, never cached release content or a deletion-success state.

If any hosted check fails, the external flow is not release-ready even when local Node, Deno, and static-site validation pass.

## Evidence

Record the production workflow run, production source commit, VersionDeck workflow run, VersionDeck source commit, generated manifest summary, verified release IDs, static validation result, Pages deployment URL, and public smoke-test result.

For account deletion, additionally record the Edge Function project/version, Supabase Auth callback configuration review, public-config validation, allowed and denied preflight results, revisioned-asset observation, disposable-account OAuth result, strict receipt validation with identifiers redacted, Auth/Postgres/Storage cleanup checks, device-local limitation/result, offline network-only result, operator, and timestamp. Clearly label local automated evidence separately from hosted-service and device evidence.
