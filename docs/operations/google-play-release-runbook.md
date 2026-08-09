# Google Play AAB Release Runbook

## Purpose and authority

This runbook governs the handoff from HomePilot's verified AAB build artifact to a manually controlled Google Play release. It does not authorize a Play upload or rollout by itself.

The executable AAB sources are:

- [`.github/workflows/build-play-android.yml`](../../.github/workflows/build-play-android.yml)
- [`tool/build_play_prod.ps1`](../../tool/build_play_prod.ps1)
- [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1)
- [`tool/validate_google_release_contracts.mjs`](../../tool/validate_google_release_contracts.mjs)
- [`tool/release-workflows.test.mjs`](../../tool/release-workflows.test.mjs)
- [`pubspec.yaml`](../../pubspec.yaml)

The cross-rail order, APK publication, and VersionDeck handoff are defined in the [Android production release runbook](release-runbook.md).

## No automatic Play upload

`Build Play Store AAB` is a manually dispatched, signed build-and-evidence workflow. It uploads GitHub Actions artifacts and creates a GitHub build-provenance attestation. It contains no Google Play API call, service-account credential, edit/track operation, staged rollout, or publish step.

The optional `release_notes` dispatch input is not currently consumed by a Play upload or stored in an AAB evidence file. It must not be treated as Console release-note evidence. Release notes are entered and captured during the separately authorized Play Console operation.

Do not claim that an AAB workflow run uploaded, validated, or released anything in Google Play. Do not add or infer a Play service-account secret; automated upload would require a separately reviewed workflow and documentation change.

## Preconditions

Before dispatching the AAB workflow:

1. Select the full commit SHA that exactly equals the current `origin/main` tip and freeze it for all release rails. A historical ancestor is not eligible.
2. Confirm `pubspec.yaml` uses `x.y.z+N` and that `N` is greater than every version code ever accepted by Google Play for `com.homepilot.app`.
3. Obtain a successful `Validate Google Backend and Release Contracts` run on `main` whose `head_sha` equals the final SHA. Require its exact check names—`Deno SSV tests`, `Google contract/static checks`, and `Supabase database tests`—in branch protection and verify that hosted setting separately. The validation run uses a local stack and is not hosted deployment evidence.
4. Review user-visible release notes, privacy impact, permissions, ads, account deletion, data retention, and store declarations.
5. Verify the declared GitHub `production` environment configuration and approvals externally. Workflow source alone does not prove required reviewers or correct values.
6. Confirm the expected Play application/package is `com.homepilot.app`, the intended initial target is identified, and no conflicting Play edit or rollout is active.

The current AAB workflow requires these exact `production` environment names:

| Kind | Names |
| --- | --- |
| Variables | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `GOOGLE_WEB_CLIENT_ID`, `SENTRY_DSN` |
| Signing secrets | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD` |

Do not record their values in the release record.

## Version and artifact identity

The workflow parses `pubspec.yaml` and rejects values outside `x.y.z+N`. It expects one `prodRelease` bundle and renames it to `HomePilot-x.y.z-build-N.aab`. Its checksum file is `HomePilot-x.y.z-build-N.aab.sha256` and contains the lowercase SHA-256, two spaces, and that exact filename.

The GitHub workflow does not query Play Console for version-code uniqueness. Play may reject a duplicate even when all repository checks pass. Once Play accepts `N`, it remains consumed; a corrected bundle must use a higher build number/version code.

## Upload key versus Play App Signing

Keep these identities separate in evidence:

1. **Upload key certificate.** The AAB is signed with the keystore restored from the `ANDROID_*` secrets. The workflow runs `jarsigner`, reads the AAB certificate with `keytool -printcert -jarfile`, reads the restored keystore certificate, and requires those SHA-256 digests to match. This proves internal consistency with the supplied upload keystore only.
2. **Play-enrolled upload certificate.** Google Play Console shows the certificate it accepts for bundle uploads. Compare its SHA-256 fingerprint with `aab-signature-verification.txt`. The workflow does not query Console and cannot make this comparison.
3. **Play App Signing certificate.** When Play App Signing is enabled, Google signs generated/delivered APKs with the app signing key shown in Console. That certificate can differ from the upload certificate and from the signer on HomePilot's standalone GitHub APK. Record it separately and verify a Play-delivered APK against it.

Never upload or archive either private key as evidence. A certificate fingerprint is evidence; a private keystore, password, base64 secret, or signing export is prohibited. Do not rotate an upload key or request an app-signing-key change merely to fix a workflow mismatch; follow an explicitly approved Play Console recovery process.

## Build workflow and gates

After manual dispatch at the final SHA, require the run to complete all of the following:

1. Explicit non-`main` rejection, exact-current-`origin/main` checks before and after the protected-environment wait, and workflow-pinned toolchain setup.
2. `npm ci`, Google/Android static contract validation, and locked AdMob SSV/account-deletion Deno checks/tests.
3. Successful lookup of the exact `.github/workflows/validate-google-backend.yml` identity for the same `main` SHA, with the gate run ID/URL recorded in the workflow summary and safe evidence context.
4. Production configuration creation and upload-keystore restoration.
5. Flutter clean/dependency resolution, localization and Drift generation, analysis, tests, and production-configuration validation.
6. Release registrant checks and `flutter build appbundle --flavor prod --release` through `tool/build_play_prod.ps1`.
7. Exactly one bundle, SHA-256/checksum creation, JAR signature verification, and AAB-to-upload-keystore certificate comparison.
8. Manifest/dependency evidence collection.
9. Upload of the AAB/checksum artifact and evidence artifact, each with 30-day retention. The fixed-path evidence upload runs even after failure so safe partial diagnostics are retained, but a partial artifact never qualifies as release evidence.
10. `actions/attest-build-provenance` for the exact AAB path.
11. Always-run cleanup of Gradle daemons and temporary signing/configuration files.

No step in that list is Play Console acceptance evidence.

## Exact AAB evidence package

Retain the workflow URL, run ID/attempt, final SHA, and both Actions artifacts:

### `HomePilot-production-aab-<run_number>`

- `HomePilot-x.y.z-build-N.aab`
- `HomePilot-x.y.z-build-N.aab.sha256`

Recompute SHA-256 after downloading and require it to equal both the checksum file and `artifact_sha256` in the evidence summary. Verify GitHub attestation against the downloaded AAB and the expected repository; a workflow success badge alone is insufficient provenance evidence.

### `HomePilot-production-aab-evidence-<run_number>`

- `release-evidence-summary.json`
- `prod-release-runtime-classpath.txt`
- `AndroidManifest-prodRelease.xml`
- `output-metadata-aab.json`, when Android generated matching output metadata
- `aab-signature-verification.txt`
- `workflow-context.json`, containing only workflow/run/source/backend-gate and release identity (never credentials)

The summary must agree with the AAB on artifact filename/hash, parsed `com.homepilot.app` package, version name/code, parsed target SDK 36, parsed `allowBackup: false`, the exactly-one parsed production AdMob application ID, and `prodReleaseRuntimeClasspath`. The dependency report must be retained in full and contain no direct Firebase Analytics dependency. The merged manifest must contain the required coarse-location, notification, and exact-alarm declarations; it must not contain fine/background location, a Google demo AdMob identifier, or a debuggable production flag.

`aab-signature-verification.txt` must show successful JAR verification and the upload-certificate SHA-256 emitted by the workflow. Compare that fingerprint with Play Console rather than assuming the protected secret is current.

Safe independent inspection after downloading includes:

```powershell
Get-FileHash -LiteralPath .\HomePilot-x.y.z-build-N.aab -Algorithm SHA256
jarsigner -verify -verbose -certs .\HomePilot-x.y.z-build-N.aab
keytool -printcert -jarfile .\HomePilot-x.y.z-build-N.aab
gh attestation verify .\HomePilot-x.y.z-build-N.aab --repo zuhak5/HomePilot
```

Replace the illustrative version/build filename with the exact artifact name. These commands do not upload or publish the bundle.

## Manual Play Console handoff

The Console operation is an externally authorized state change. Use an internal testing track first unless the approved release plan explicitly requires another target.

1. Open the intended HomePilot application in Play Console and record the application identity and current highest accepted version code.
2. Review **App integrity** before upload. Record the enrolled upload-certificate and Play App Signing certificate SHA-256 fingerprints; compare the upload fingerprint with the AAB evidence.
3. Create or select the approved track release and upload the verified AAB. Confirm Play reports the expected package, version name, version code, target SDK, and no unexpected blocking error.
4. Review Bundle Explorer/generated APK details, manifest permissions/features, supported devices, native-code/debug-symbol notices, and Play's automated checks. Do not dismiss warnings without a recorded decision.
5. Enter the approved release notes manually. The workflow's optional `release_notes` input is not proof that Console received them.
6. Review countries/testers, rollout percentage, managed-publishing state, availability, and start time. Capture the review screen before the final rollout action.
7. Obtain the required human approval immediately before submitting the Console action that creates, publishes, or advances a release.
8. Record the resulting release/track status and Console timestamps. Do not describe a draft, processing bundle, or pending review as released.

Do not upload a locally rebuilt AAB. Upload the exact downloaded and re-verified Actions artifact whose hash and attestation are in the release record.

## App-content and data-safety evidence

Use the [Google Play data-safety evidence worksheet](google-play-data-safety-evidence.md) for the exact release. It is an engineering starting point, not a Play Console export or proof of submitted declarations. Close its operator-owned items before claiming the Play release record is complete; do not replace them with assumptions in this runbook.

At minimum, reconcile Play Console App content against the reviewed build and current privacy policy:

- Data safety collection, sharing, purpose, security, and deletion answers.
- Privacy-policy URL and public account-deletion URL.
- Ads declaration and families/target-audience status where applicable.
- App access instructions for review accounts if required.
- Coarse location, notification, and exact-alarm declarations and justifications.
- Absence of fine/background location in the merged production manifest.
- Google sign-in, Supabase, AdMob, Sentry, backup/export, retention, and deletion behavior.

Record Console section status, reviewer, timestamp, supporting code/evidence revision, and any unresolved warning. Do not copy tokens, user data, advertising identifiers, or private screenshots into public artifacts.

## Play-delivered device evidence

An AAB cannot be installed directly, and a locally generated APK set cannot prove Play signing or Play delivery. After the internal-track release is available, install/update through Google Play on a controlled physical device and record:

- Tester account/track eligibility without exposing the account address.
- Device model, Android/API version, locale, and clean-install versus update path.
- Installed package `com.homepilot.app`, expected version name/code, and release/non-debuggable behavior.
- Play-delivered base APK certificate SHA-256 matching the Play App Signing certificate recorded from Console.
- Cold start and first-run behavior; Google sign-in and account binding; sync and private media.
- Notification permission, scheduling, exact-alarm behavior, reboot/update restoration, and graceful denial states.
- Coarse-location-dependent behavior with fine/background location absent.
- Consent, ads, reward verification/pending recovery, and core behavior when ads are unavailable.
- Backup/export and restore checks appropriate to the release.
- In-app and public-web account-deletion entry points, using disposable data when destructive verification is approved.
- Sentry release association and privacy-safe diagnostics without user content.

Useful read-only device identity commands include:

```powershell
adb shell dumpsys package com.homepilot.app
adb shell pm path com.homepilot.app
```

To verify the Play-delivered certificate, pull the reported base APK into a protected evidence workspace and run `apksigner verify --verbose --print-certs`; compare the certificate SHA-256 with Play Console. Do not publish the pulled APK or tester data. Record the exact command/tool version and redacted result.

## Failure and rollback boundaries

- **Workflow or evidence failure before upload:** stop; Play state is unchanged. Correct the source/configuration and produce a new accepted AAB rail before Console work.
- **Upload certificate mismatch:** do not bypass signature checks or upload a differently signed local bundle. Verify the selected application and protected keystore, then use Play's approved upload-key recovery process only when authorized.
- **Play rejects version code:** choose a higher build number in `pubspec.yaml`, create a new final SHA, and restart the complete backend/AAB/APK sequence.
- **Bundle accepted but release still draft:** the version code is consumed even if the draft is later discarded. Preserve Console evidence and use a higher code for a replacement.
- **Internal/device validation fails:** halt promotion. Record affected versions/devices, fix with a higher version code, and repeat all final-SHA evidence.
- **Staged rollout regression:** halt the rollout through Play Console and assess whether an existing safe release can continue serving users. Android upgrades still require a higher version code for the correction; do not attempt a downgrade artifact.
- **Play-only failure:** does not automatically withdraw the standalone GitHub APK or VersionDeck. Evaluate and act on those rails separately.
- **GitHub/VersionDeck-only failure:** does not halt an active Play rollout. Execute both controls when the defect affects both channels.

Never delete or overwrite evidence to make a later run appear continuous with an earlier SHA or version code.

## Required Play release record

Record:

- Final SHA, `pubspec.yaml` version/build, exact-SHA backend gate, and hosted backend deployment dependency.
- AAB workflow URL/run attempt, artifact names, recomputed/checksum/summary hashes, attestation verification, upload certificate, manifest/dependency review, and exceptions.
- Play application, App integrity fingerprints, uploaded bundle version, Bundle Explorer result, automated checks/warnings, track, testers/countries, rollout/managed-publishing settings, approvals, and timestamps.
- Data-safety/app-content evidence at the reserved canonical path.
- Physical-device install/update results, Play-delivered signer, functional/privacy checks, and deferred cases.
- Rollback/halt decisions and the independent status of Play, GitHub Release, Sentry, and VersionDeck.

Do not claim successful upload, review, rollout, signing protection, or device behavior without the corresponding hosted or physical evidence.
