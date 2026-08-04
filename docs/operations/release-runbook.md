# Android Production Release Runbook

## Scope

This runbook describes the protected GitHub Actions release path. It does not authorize local production signing or release publication.

The authoritative implementation is `.github/workflows/build-production-android.yml`, `.github/workflows/deploy-download-site.yml`, `tool/build_prod.ps1`, `tool/publish_sentry_release.ps1`, Gradle flavor/signing configuration, and `config/prod.example.json`.

## Preconditions

- The intended source is merged into `main`.
- Flutter validation passes.
- Required Supabase migrations and functions have been reviewed and deployed through the approved backend process.
- User-visible changes have release notes and privacy/store disclosures where required.
- Production configuration and signing secrets exist in the protected GitHub environment.
- The expected application ID, signer certificate, version, build number, Sentry project, and release target are confirmed.
- No unresolved security, data-migration, synchronization, account-deletion, monetization, backup, or permission risk remains.

## Workflow protections

The production workflow should retain:

- Manual invocation.
- A guard requiring `main` as the source.
- A protected production environment.
- Minimal permissions.
- Controlled signing-material restoration.
- Concurrency protection.
- Artifact and provenance retention.

Do not convert the production workflow into an automatic release on every push. The downstream VersionDeck workflow may start automatically only after the protected production workflow completes successfully.

## Build sequence

The workflow performs the following classes of work:

1. Check out the exact source commit.
2. Install the pinned Flutter toolchain.
3. Restore Android signing material from protected secrets.
4. Construct or validate production configuration.
5. Run the production PowerShell build script.
6. Resolve dependencies and regenerate localization/Drift output.
7. Run formatting, analysis, and tests required by the script/workflow.
8. Build the production release APK.
9. Verify the APK package name, version name, build number, release/non-debuggable state, signer identity, and checksum.
10. Publish or finalize the matching Sentry release.
11. Upload the verified artifact.
12. Generate build provenance/attestation.
13. Publish the GitHub Release and release notes.
14. After the production workflow concludes successfully, trigger `Deploy VersionDeck` through `workflow_run`.
15. VersionDeck independently rediscovers and verifies the published APK before updating GitHub Pages.

The scripts and workflows are authoritative for exact command arguments.

## Downstream VersionDeck handoff

The downstream workflow runs only when all of these conditions are true:

- The completed upstream workflow is named `Build Production APK`.
- It was manually dispatched.
- Its source branch is `main`.
- Its conclusion is `success`.
- Its source commit remains in the current `main` history.

A failed, cancelled, or skipped production run must not start an automatic Pages deployment. VersionDeck release-event and manual triggers remain available for release edits, deletions, recovery, and explicitly requested rebuilds.

A successful upstream result is only permission to begin independent verification. It is not evidence that VersionDeck should expose the APK. VersionDeck must still verify release identity, package, version, build, signer, checksum, ancestry, and available provenance before publishing a trusted manifest entry.

## Verification checklist

Before treating the release as successful, confirm:

- Source commit equals the intended `main` commit.
- Production configuration validation passed.
- No secret appeared in logs or artifacts.
- Flutter tests and analysis passed.
- APK application ID matches the production ID.
- Version and build match `pubspec.yaml` and workflow inputs.
- APK is not debuggable.
- APK signer fingerprint matches the protected expected value.
- SHA-256 checksum was produced from the released artifact.
- Sentry release identifier matches the application release.
- Provenance was generated for the artifact.
- GitHub Release contains the intended APK and metadata.
- The production run concluded successfully and started the downstream VersionDeck run.
- VersionDeck subsequently accepts the release through independent verification.
- The public VersionDeck manifest matches the deployment source commit.

## Failure handling

- Do not publish an artifact when any identity, signer, checksum, test, or provenance check fails.
- Rotate exposed credentials immediately if a secret reaches logs or artifacts.
- If a release is published with a defective APK, mark it clearly, remove or supersede download enablement, publish a corrected build with a new build number, and document impact.
- Do not replace an existing artifact silently under the same release identity.
- Preserve diagnostics needed to explain a failed protected run without exporting signing material.
- If the production run succeeds but VersionDeck fails, keep the previous verified site live, inspect the downstream diagnostics, and rerun VersionDeck only after confirming release integrity.
- Do not weaken VersionDeck verification merely to make the chained deployment pass.

## Backend coordination

A mobile release that depends on a migration, RPC, Edge Function, RLS policy, Storage policy, points configuration, or account-deletion change must define deployment order and backward compatibility. The previous mobile version must fail safely during a staged rollout.

## Post-release checks

- Confirm the downstream VersionDeck run was created from the successful production run.
- Install the released APK on a clean device.
- Verify launch, sign-in, local data, sync, notifications, backup, ads/consent, and account surfaces appropriate to the release.
- Confirm Sentry associates events with the correct release without user data.
- Confirm VersionDeck exposes only the independently verified artifact.
- Monitor crash, authentication, synchronization, deletion, reward, and backend error signals.

## Evidence

Record the source commit, production workflow run, APK checksum, signer verification, release URL, provenance result, Sentry release, downstream VersionDeck workflow run, VersionDeck verification result, Pages deployment URL, and any deferred device validation in the release record.
