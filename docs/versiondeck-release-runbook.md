# VersionDeck release runbook

## Purpose

VersionDeck is the public distribution surface for signed HomePilot Android APKs. Release publication must prove both file integrity and continuity with the expected production signing certificate.

## Before publishing

1. Merge the intended release commit into protected `main`.
2. Increase both the semantic version and Android build number in `pubspec.yaml`.
3. Confirm Flutter analysis and tests pass.
4. Confirm the production GitHub environment is restricted to `main` and requires an independent reviewer.
5. Confirm the documented production signing-certificate SHA-256 has not changed.
6. Prepare a meaningful Markdown changelog.
7. Run the `Build Production APK` workflow from `main`.

## Workflow guarantees

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

## After publishing

1. Confirm the GitHub Release contains the APK and matching `.sha256` file.
2. Confirm the artifact attestation is available.
3. Confirm the VersionDeck Pages workflow regenerates `releases.json`.
4. Confirm the latest stable card identifies the expected release.
5. Confirm the relative timestamp and exact publication date are correct.
6. Download the APK and independently verify its SHA-256 and signer certificate.

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

1. Remove or mark the affected GitHub Release unavailable.
2. Manually run `Deploy VersionDeck` if the release event did not trigger it.
3. Confirm the release is absent from the generated manifest and public archive.
4. Publish a corrected APK with a new build number. Do not overwrite an existing APK asset.
5. Document the withdrawal reason and affected versions.

Cached VersionDeck data is bounded. Data older than 24 hours is not allowed to keep download actions active.

## Signing-key continuity

The production keystore must be securely backed up. Losing it prevents normal Android upgrade continuity. A signer change requires an explicitly reviewed migration and coordinated updates to:

- GitHub production secrets
- Production certificate fingerprint in the release workflow
- VersionDeck manifest generator
- README production OAuth certificate documentation
- User-facing migration communication

Never silently replace the expected signer fingerprint.

## Rollback

VersionDeck source rollback:

1. Revert the faulty commit on `main`.
2. Run `Deploy VersionDeck` manually.
3. Confirm the new service worker activates and obsolete VersionDeck caches are removed.
4. Verify the public `releases.json`, primary APK link, checksum, and signer fingerprint.

APK releases should normally be superseded with a higher build number rather than overwritten.
