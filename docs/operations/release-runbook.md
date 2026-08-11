# Android Production Release Rails

> **Production containment is active.** Since 2026-08-11, the Android signing,
> Sentry publication, GitHub Release, Supabase migration/advisor, Play AAB, and
> VersionDeck workflow objects are disabled and GitHub Pages is unpublished.
> Do not dispatch or re-enable a rail from this runbook. Follow the evidence and
> rail-specific prerequisites in the
> [TASK-001 containment record](production-containment.md).
> TASK-002 source/tag protection is complete: reviewed/current-check `main`
> entry and automation-only immutable production tags are enforced. See the
> [TASK-002 protection record](github-source-and-tag-protection.md). Production
> authorization remains blocked by containment and the later environment,
> credential, workflow, and release-evidence tasks.

## Scope

This runbook coordinates HomePilot's production Android evidence rails. It does not authorize local signing, backend deployment, Google Play upload, rollout, Sentry mutation, GitHub Release publication, or Pages deployment.

The executable sources are:

- [Google/backend/database validation](../../.github/workflows/validate-google-backend.yml)
- [Play AAB build](../../.github/workflows/build-play-android.yml)
- [Standalone APK release](../../.github/workflows/build-production-android.yml)
- [VersionDeck deployment](../../.github/workflows/deploy-download-site.yml)
- [`tool/build_play_prod.ps1`](../../tool/build_play_prod.ps1) and [`tool/build_prod.ps1`](../../tool/build_prod.ps1)
- [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1)
- [`tool/validate_google_release_contracts.mjs`](../../tool/validate_google_release_contracts.mjs)
- [`pubspec.yaml`](../../pubspec.yaml)

Use the dedicated [Google Play release runbook](google-play-release-runbook.md) for manual Play Console and Play-delivered device evidence. Use the [VersionDeck runbook](../versiondeck-release-runbook.md) for downstream APK verification and Pages evidence.

## Do not infer protected or successful state

The AAB and APK workflows declare `workflow_dispatch`, a separate unprotected preflight job that explicitly fails non-`main` dispatches, an exact-current-`origin/main` recheck inside the protected build job, `environment: production`, non-cancelling concurrency groups, and explicit permissions. Those declarations are source evidence only. They do not prove that the GitHub `production` environment currently has required reviewers, branch restrictions, correctly scoped secrets, or a successful run. Capture those settings and run results separately.

Likewise, the backend validation workflow proves local/static contracts only. It does not prove that migrations, RLS, RPCs, Storage policies, Auth configuration, or Edge Functions are deployed to the intended hosted Supabase project.

## Release identity and version uniqueness

The final source identity is one full Git commit SHA on `main`. Freeze that SHA for the entire sequence; do not combine backend, AAB, APK, Sentry, GitHub, Play, or VersionDeck evidence from different commits.

`pubspec.yaml` is the release identity source and must use `x.y.z+N`:

- `x.y.z` becomes Android `versionName`.
- `N` becomes Android `versionCode` and the Sentry distribution.
- The AAB filename is `HomePilot-x.y.z-build-N.aab`.
- The APK filename is `HomePilot-x.y.z-build-N.apk`.
- The GitHub tag is `vx.y.z-build.N`.
- The Sentry release is `com.homepilot.app@x.y.z+N`.

Both build workflows parse and reject any other version shape. The APK workflow rejects an existing GitHub tag. Neither workflow queries Google Play for previously used version codes, so an operator must confirm that `N` is greater than every version code already uploaded to Play before starting the final sequence. Once Play accepts a version code, never reuse it, even if the release is halted or deleted.

If source changes after any final-SHA evidence is collected, choose a new final SHA, update the build number when required, and restart the sequence. Do not carry evidence forward by ancestry alone.

## Strict final-SHA sequence

The sequence below describes the intended protected release contract after
containment is lifted. It is not currently executable authorization.

1. **Backend database gate.** If the release contains pending database migrations, manually run `Deploy Supabase Migrations` on `main` with the exact current SHA, exact project ref, and `apply-pending-migrations`; inspect the remote list and dry-run evidence and require the post-apply dry run to succeed. Then manually dispatch `Validate Google Backend and Release Contracts` on the same `main` SHA and require success. Its jobs cover locked Deno formatting/type/tests for AdMob SSV, account deletion, and deletion-status recovery; deletion-site/release workflow static tests; Google/Android static contracts; a local Supabase database start, lint, and test cycle; and the protected read-only `Hosted Supabase Advisors` audit. Pull-request and push runs still exercise the local/static jobs without exposing production credentials.
2. **APK, Sentry, and GitHub Release.** Manually run `Build Production APK` at the same SHA with the required changelog. The APK evidence collector must pass before Sentry mutation. Then require successful Sentry publication, artifact upload, provenance attestation, and GitHub Release creation.
3. **VersionDeck.** A successful manually dispatched `Build Production APK` run can start `Deploy VersionDeck` through `workflow_run`. VersionDeck checks out that run's SHA, requires it to equal current `main`, rediscovers the GitHub Release, and independently verifies the APK before Pages deployment. A manual recovery dispatch requires the successful current-SHA APK run ID.
4. **Separate AAB evidence and attestation.** Manually run `Build Play Store AAB` at the same frozen SHA as an independent rail. Wait for the workflow, both retained artifacts, and build-provenance attestation to complete. Review the AAB checksum, upload-key signature evidence, merged manifest, output metadata when present, dependency report, and evidence summary. This workflow does not upload to Google Play.

The workflows intentionally do not encode AAB success as a prerequisite of the APK/VersionDeck rail, and their concurrency groups are distinct. Do not run the protected Android builds concurrently. Keep `main` unchanged until every intended exact-SHA rail and the VersionDeck handoff are complete; VersionDeck fails closed when the APK SHA is not the current `main` SHA. Google Play upload or rollout remains a separate explicitly authorized operator process.

During containment, the active `main` ruleset requires only the current
`Format, analyze, and test` context from the sole active workflow object,
`Validate Flutter`. It is strict and bound to the GitHub Actions integration.
Requiring checks from a disabled workflow would make the reviewed merge path
impossible and would not create valid evidence.

Before the backend and release rails can be re-enabled by their owning tasks,
the following exact pull-request check-run names from
`Validate Google Backend and Release Contracts` must also be active,
executable, and added to protected `main`:

- `Deno SSV tests`
- `Google contract/static checks`
- `Supabase database tests`

The manually dispatched final-SHA backend evidence additionally requires
`Hosted Supabase Advisors`. It is intentionally not a pull-request branch
protection context because it reads a protected production-environment token.

Verify all then-current contexts in hosted ruleset settings after their owning
workflow task merges. Workflow source cannot prove that hosted protection
requires them.

## Immutable GitHub Actions inputs

All current external `uses:` entries are pinned to reviewed 40-character
commits without changing their existing major versions. Production workflow
triggers, permissions, environments, gates, and commands remain unchanged; the
active read-only validation job adds the required pin-policy contract. The
authoritative allowlist and source validator are in
[`tool/github-actions-policy.mjs`](../../tool/github-actions-policy.mjs), and
the official owner/release/commit ledger plus review procedure is in the
[GitHub Actions supply-chain policy](../development/github-actions-supply-chain.md).
Run `npm run test:release-workflows` for the current inventory and negative
fixtures.

Dependabot is discovery automation only. Action-digest updates require release
and security-note review, synchronized workflow comments/allowlist/ledger,
independent approval, and exact-commit CI; they never auto-merge. The pins are
source evidence, not proof that a production workflow executed successfully or
that hosted Actions owner/require-SHA policy is enabled. Task 05 owns that
hosted policy. Production containment still prohibits dispatching a rail merely
to obtain execution evidence.

## Required GitHub configuration names

Do not invent aliases. The current workflows consume these existing names from the declared `production` environment.

| Scope | Variables | Secrets |
| --- | --- | --- |
| AAB and APK runtime configuration | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `GOOGLE_WEB_CLIENT_ID`, `SENTRY_DSN` | — |
| AAB and APK signing | — | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD` |
| APK Sentry publication | `SENTRY_ORG`, `SENTRY_PROJECT` | `SENTRY_AUTH_TOKEN` |

The workflows also use the ephemeral `${{ github.token }}` for exact-SHA run lookup and, on the APK rail, GitHub Release publication. The repository does not define or consume a Google Play upload API credential in these workflows. Do not add a Play service-account secret merely to follow this runbook; automated Play upload requires a separate reviewed implementation.

The downstream VersionDeck build separately consumes the public repository variables `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `ACCOUNT_DELETION_SITE_URL`. Missing values can fail Pages artifact generation after the APK GitHub Release already exists.

Before dispatch, record—not the values themselves—that every required item is present in the intended environment, that secret access is limited to the expected workflow, and that current environment reviewer/branch rules have been independently inspected.

## Shared build and security gates

Both Android workflows:

1. Explicitly fail a non-`main` dispatch, then require the selected SHA to equal the current `origin/main` tip. The protected build job repeats the exact equality check after any environment-approval wait.
2. Install the workflow-pinned Java, Flutter, Node, and Deno toolchains.
3. Run `npm ci`, `tool/validate_google_release_contracts.mjs`, locked Edge Function checks, and locked Edge Function tests.
4. Query completed runs of the exact `.github/workflows/validate-google-backend.yml` identity and require a successful `main` push or manual run with the exact current `GITHUB_SHA`; record its run ID and URL in the workflow summary and evidence context.
5. Derive version/build metadata from `pubspec.yaml`.
6. Validate required production variables, construct ignored `config/prod.json`, and restore the ignored signing files from secrets.
7. Clean, resolve Flutter dependencies, regenerate localization and Drift output, analyze, run the Flutter test suite, and run the production configuration test.
8. Remove the known generated integration-test registrant and reject `IntegrationTestPlugin` from release registrants before and after the release build.
9. Build the `prodRelease` artifact and remove temporary signing/configuration files in an `always()` cleanup step.

A successful repeated security-contract step does not replace the exact-SHA backend workflow gate; both are required by the executable workflows.

## AAB rail summary

The AAB workflow creates exactly one `prodRelease` bundle and verifies:

- SHA-256 plus a matching `.sha256` file.
- JAR signature validity.
- The AAB signing certificate matches the certificate in the restored upload keystore.
- Package, version name, and version code through generated metadata or the merged manifest.
- Merged production manifest and runtime-dependency evidence through the shared collector.
- Build provenance for the AAB subject.

It uploads, for 30 days:

- `HomePilot-production-aab-<run_number>` containing the AAB and checksum file.
- `HomePilot-production-aab-evidence-<run_number>` containing the collector output and `aab-signature-verification.txt`.

The evidence upload uses `always()` and a fixed safe path, so partial collector/signature/context diagnostics remain available when a later check fails. A successful rail still requires the complete evidence set; a warning-only partial diagnostic artifact is not release evidence.

The AAB is only a verified upload candidate. The workflow does not call Google Play APIs, select a track, create an edit, upload release notes, or roll out a release. See the [Google Play release runbook](google-play-release-runbook.md).

## APK, Sentry, and GitHub rail

The APK workflow additionally validates fixed Sentry organization/project expectations, then builds and verifies the standalone APK:

- Exactly `com.homepilot.app`, with the `pubspec.yaml` version/build.
- Non-debuggable package metadata.
- APK signature validity and the fixed standalone production signer declared by the workflow.
- SHA-256 stability and exact checksum-file contents.
- The same merged-manifest, output-metadata, and dependency evidence collected for the AAB rail.

The evidence collector runs before `tool/publish_sentry_release.ps1`, so manifest/dependency failures occur before Sentry mutation. Sentry publication then creates or reuses the release, associates commits, uploads debug information, finalizes the release, records a deploy, and verifies it. Later artifact, attestation, or GitHub failures can still leave a valid Sentry release behind; record and reconcile that partial state rather than claiming an Android release succeeded.

Before any Sentry mutation, the workflow rejects an existing remote Git tag or GitHub Release for the derived identity, then rechecks the tag immediately before publication. The workflow uploads the APK/checksum and APK evidence as separate 30-day Actions artifacts, attests the APK, and creates a GitHub Release containing the renamed APK and `.sha256` file. The APK diagnostic upload uses `always()` and retains its safe workflow context, signer output, `aapt2` badging, merged manifest, dependency report, and metadata produced before a failure. Release notes record version, build, package, filename, SHA-256, standalone signer, Sentry release, and the `gh attestation verify` command. VersionDeck trusts none of those prose claims without independently inspecting the release and artifact.

## Evidence collector contract

For both artifact types, `tool/collect_android_release_evidence.ps1` emits:

- `release-evidence-summary.json` with artifact type/name/SHA-256, parsed package, version name/code, parsed target SDK, parsed backup setting, the exactly-one parsed AdMob application ID, merged-manifest and output-metadata sources, dependency configuration, analytics result, and generation time.
- `prod-release-runtime-classpath.txt` from Gradle `:app:dependencies --configuration prodReleaseRuntimeClasspath`.
- `AndroidManifest-prodRelease.xml`, copied from the newest merged `prodRelease` manifest.
- `output-metadata-apk.json` or `output-metadata-aab.json` when matching generated output metadata exists. APK discovery recognizes the Android Gradle Plugin `outputs/apk/prod/release/output-metadata.json` path; AAB discovery is restricted to `outputs/bundle/prodRelease/output-metadata.json`.

The collector parses the merged XML rather than accepting substring matches. It rejects direct Firebase Analytics, a debuggable production manifest, `android:allowBackup` other than exactly `false`, target SDK other than 36, fine/background location, the Google demo AdMob application ID, missing required coarse-location/notification/exact-alarm permissions, anything other than exactly one production AdMob metadata entry, package mismatch, multiple artifact metadata elements, or version/build mismatch. The separate static contract also checks target/compile SDK, every tracked Android path for forbidden `google-services.json`, exact demo/production ad-unit mapping, distributable client/site sources for service-role credential material, and Google Services/analytics source constraints. These files are build evidence; they do not prove Play Console declarations, a Play-generated split APK set, or behavior on a physical device.

## Upload key, standalone APK signer, and Play App Signing

The same restored `ANDROID_*` keystore is currently used to sign both build outputs, but its evidence has different meaning:

- For the AAB it is the **upload key**. The workflow proves the bundle matches the restored keystore, not that the key matches the upload certificate currently enrolled in Play Console.
- For the GitHub APK it is the **standalone distribution signer**. The APK workflow also compares it with the fixed signer identity in workflow source.
- Under Play App Signing, Google signs Play-delivered APKs with the separate **app signing key** shown in Play Console. The Play app-signing certificate must be recorded and verified against a Play-delivered APK. Do not substitute the upload certificate or standalone GitHub APK signer unless Play Console independently proves they are the same certificate.

Never export the Play app-signing private key. Store only certificate fingerprints and provenance needed for comparison. See the [Google Play release runbook](google-play-release-runbook.md) for the required Console and device checks.

## VersionDeck handoff

`Deploy VersionDeck` only chains automatically from a successful, manually dispatched workflow named `Build Production APK` on `main`. The upstream SHA, checked-out source, and current `main` SHA must match exactly. Push and Release events cannot deploy Pages. A manual recovery run must identify the successful current-SHA APK run ID. A successful upstream conclusion permits verification to begin; it does not make the APK downloadable.

VersionDeck verifies release state, exact filename, checksum, package, version/build, non-debuggable state, standalone signer, release target/ancestry, and GitHub attestation before generating its manifest. Its production build can still fail on public deletion-site configuration or static-site validation. Until Pages deployment and public-manifest verification succeed, retain the previous verified site as the public VersionDeck state.

## Failure and rollback boundaries

- **Backend gate failure:** stop. Do not start either signed artifact rail. A local database gate does not authorize hosted backend deployment.
- **Final SHA changes:** invalidate the release record and rerun the backend, AAB, APK, and downstream evidence for the new SHA.
- **AAB workflow failure before Play upload:** no Play release exists. Preserve diagnostics, discard the candidate, and rerun only after correction.
- **Play accepts the AAB:** the version code is consumed. Halt or remove the affected rollout through Play Console as appropriate, then publish a corrected build with a higher version code; never replace the accepted bundle under the old code.
- **APK evidence failure:** occurs before Sentry mutation; do not publish the APK.
- **Sentry succeeds but a later APK step fails:** record the partial Sentry release/deploy. The script tolerates an existing Sentry release on retry, but the operator must ensure the same release identity and SHA before retrying.
- **GitHub Release already exists:** the APK workflow fails closed. Do not overwrite assets or bypass the tag check. Inspect whether the release is valid, withdraw/supersede it when necessary, and use a new build number for corrected binaries.
- **APK succeeds but VersionDeck fails:** the GitHub Release can remain directly reachable while the previous verified Pages site stays live. Fix the downstream cause and rerun VersionDeck only after rechecking release integrity.
- **Play rollback versus GitHub rollback:** these are independent distribution rails. Halting a Play rollout does not remove the GitHub APK, and withdrawing a GitHub Release does not halt Play. Record and execute both actions when both channels are affected.

Never weaken signer, checksum, package, backend, provenance, or VersionDeck checks to recover a release.

## Required release record

Record at minimum:

- Final source SHA and `pubspec.yaml` version/build.
- Exact-SHA backend workflow URL, job conclusions, and separate hosted-backend deployment evidence.
- AAB workflow URL, both artifact names, artifact/checksum equality, upload-certificate fingerprint, evidence-summary fields, manifest/dependency review, and attestation verification.
- APK workflow URL, artifact/evidence names, checksum, standalone signer, Sentry release/deploy, attestation, GitHub tag/release URL, and partial-state notes if any.
- VersionDeck workflow/source SHA, independent verification result, Pages URL, and public manifest result.
- Google Play Console upload, Play App Signing, track/rollout, app-content, and device evidence from the dedicated runbook.
- Operator, reviewer/approval evidence, timestamps, exceptions, rollback decisions, and all checks deferred to hosted services or devices.

Do not put credentials, tokens, private signing material, direct user identifiers, or private test data in the release record.
