# VersionDeck release runbook

## Purpose

VersionDeck is the public distribution surface for signed HomePilot Android APKs. A release is displayed only after the deployment pipeline independently verifies file integrity, Android package metadata, production signing continuity, release-commit ancestry, and GitHub build provenance.

## Trust boundaries

The GitHub Release title, body, asset names, and checksum text are inputs, not proof. The VersionDeck deployment job must independently download and inspect each eligible APK before it can enter `releases.json`.

The public browser validates the generated manifest again before enabling any download control. Release data cached by the browser is bounded and cannot renew its age without a successful network response.

## Before publishing

1. Merge the intended release commit into protected `main`.
2. Increase both the semantic version and Android build number in `pubspec.yaml`.
3. Confirm Flutter analysis and tests pass.
4. Confirm the production GitHub environment is restricted to `main` and requires an independent reviewer.
5. Confirm the documented production signing-certificate SHA-256 has not changed.
6. Prepare a meaningful Markdown changelog.
7. Run the `Build Production APK` workflow from `main`.

## Production workflow guarantees

The production workflow must stop before publication when any of the following is true:

- The selected commit is not part of `origin/main`.
- Production configuration or signing credentials are missing.
- Flutter analysis or tests fail.
- The APK is missing, debuggable, or not the production package.
- Package name, version name, or build number differs from release metadata.
- Android signature verification fails.
- The signer certificate differs from the pinned production certificate.
- The generated checksum cannot be read back or does not match the APK.
- The release tag already exists.

## VersionDeck deployment guarantees

For every displayed release, the Pages build must independently:

1. Download the APK from the GitHub release-asset API.
2. Calculate the APK SHA-256 locally.
3. Match that hash against GitHub's asset digest and the `.sha256` asset.
4. Reject a release-note hash when it disagrees with the verified file.
5. Run `apksigner verify --verbose --print-certs`.
6. Run `aapt2 dump badging` and verify package, version, build, and non-debuggable status.
7. Match the APK signer against the pinned HomePilot production certificate.
8. Resolve the release tag to an exact commit and verify that commit is contained in `origin/main`.
9. Run `gh attestation verify` against `zuhak5/HomePilot`.
10. Emit schema-v2 verification evidence into the manifest.

The newest stable release and newest prerelease fail closed: if either does not pass verification, VersionDeck deployment must fail rather than silently present an older release as current.

## Deployment-source integrity

Release events are regeneration signals only. The Pages workflow must always check out `refs/heads/main`, verify that `HEAD` equals `origin/main`, and build the site from that source. An old release tag must never determine which VersionDeck code is deployed.

Release activity triggers must include `unpublished` so converting a release back to draft removes it from the public manifest.

## Cache and offline policy

The service worker may cache only the VersionDeck application shell. It must never cache `releases.json`.

The browser owns the bounded release-data cache:

- Under 6 hours: cached data may retain download controls with an offline indicator.
- From 6 through 24 hours: cached data may retain download controls with a prominent stale warning.
- Older than 24 hours: metadata may remain visible, but every APK and checksum download control must be disabled.
- Reading cached data must never change `fetchedAt` or `generatedAt`.
- A successful network response is the only operation allowed to create a new cache timestamp.

## After publishing

1. Confirm the GitHub Release contains the APK and matching `.sha256` file.
2. Confirm the artifact attestation is available.
3. Confirm `Deploy VersionDeck` checks out current `main`.
4. Confirm the generated manifest uses schema 2 and names the deployment source SHA.
5. Confirm the latest stable card identifies the expected release.
6. Confirm the relative timestamp and exact publication date are correct.
7. Download the APK and independently verify its SHA-256 and signer certificate.
8. Review the retained `versiondeck-validation-*` artifact for exclusions or warnings.
9. Confirm the post-deployment smoke test reads the expected public manifest.

## Verification commands

```powershell
Get-FileHash .\HomePilot-X.Y.Z-build-N.apk -Algorithm SHA256
```

```bash
sha256sum HomePilot-X.Y.Z-build-N.apk
apksigner verify --verbose --print-certs HomePilot-X.Y.Z-build-N.apk
gh attestation verify HomePilot-X.Y.Z-build-N.apk --repo zuhak5/HomePilot
```

## Release withdrawal

When a release is invalid or compromised:

1. Unpublish, delete, or otherwise make the affected GitHub Release unavailable.
2. Confirm the `unpublished` or `deleted` event starts `Deploy VersionDeck`.
3. Manually run `Deploy VersionDeck` if the release event did not trigger it.
4. Confirm the release is absent from the generated manifest and public archive.
5. Publish a corrected APK with a new build number. Do not overwrite an existing APK asset.
6. Document the withdrawal reason and affected versions.

## Verification failure response

When VersionDeck excludes or blocks a release:

1. Download the `versiondeck-validation-*` artifact.
2. Locate the affected release ID and tag in `release-diagnostics.json`.
3. Identify the failed stage: metadata, checksum, APK hash, package, signer, commit, or attestation.
4. Do not weaken or bypass the failed gate.
5. Correct the production release or verifier defect and rerun the deployment.
6. Preserve diagnostics for incident review when signer, checksum, or provenance differs unexpectedly.

## Signing-key continuity

The production keystore must be securely backed up. Losing it prevents normal Android upgrade continuity. A signer change requires an explicitly reviewed migration and coordinated updates to:

- GitHub production secrets
- Production certificate fingerprint in the release workflow
- VersionDeck manifest policy
- README production OAuth certificate documentation
- User-facing migration communication

Never silently replace the expected signer fingerprint.

## Rollback

VersionDeck source rollback:

1. Revert the faulty commit on `main`.
2. Run `Deploy VersionDeck` manually.
3. Confirm the workflow reports the reverted `main` SHA as its deployment source.
4. Confirm the new service-worker cache revision activates and obsolete VersionDeck caches are removed.
5. Verify public `releases.json`, APK link state, checksum, signer fingerprint, release commit, and attestation evidence.

If verification tooling is unavailable, fail closed and publish an unavailable state. Do not roll back to a generator that republishes unverified releases.
