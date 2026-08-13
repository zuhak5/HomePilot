# ADR 0002: Independently Verify APK Releases Before Public Download

- Status: Accepted
- Date: August 4, 2026

## Context

A GitHub Release can contain an incorrectly named, unsigned, wrongly signed, debuggable, mismatched, or otherwise invalid APK. Release notes and filenames are assertions, not proof. HomePilot needs a public download surface that fails closed when artifact identity cannot be established.

The site also displays live build status, which is useful operational context but is not evidence that an artifact is safe to download.

## Decision

Use VersionDeck as a separately generated static site. Its deployment workflow independently downloads and inspects candidate APKs, verifies release identity and trusted artifact properties, generates a versioned manifest with an explicit publication state and absolute trust lease, builds revisioned static assets, validates the result, and publishes through GitHub Pages.

Download enablement is based on verified artifact data, not live build status or release prose.

Verification includes the applicable package name, version/build, digest, signer identity, release state, source ancestry or an explicit reviewed historical decision, non-debuggable status, and provenance/attestation evidence supported by the workflow. The Pages workflow must also be able to publish an explicit disabled manifest without successful artifact generation when operator action needs to revoke or contain downloads.

## Consequences

### Positive

- Public downloads fail closed when artifact identity is uncertain.
- Release metadata is derived from inspected artifacts.
- The site can remain static and token-free.
- Live build state can be shown without changing stable-download trust.
- Operators can publish a reviewed disabled state without manufacturing or
  mutating APK artifacts first.

### Negative

- Deployment requires Android verification tools and GitHub release access in CI.
- Manifest, service-worker, cache, and verifier changes require coordinated tests.
- A valid release may not appear until independent verification and deployment finish.
- Historical releases outside current source ancestry require an explicit policy
  decision before they can remain downloadable.

## Required invariants

- Never publish an unverified APK entry.
- Never use a public GitHub token in the site.
- Never let stale or malformed metadata enable downloads.
- Never let network-fetched or cached metadata stay trusted past its absolute
  lease deadline.
- Never replace stable verified identity with an in-progress target version.
- Never treat a non-ancestor historical release as trusted without an exact
  reviewed decision bound to its release ID, tag, and commit SHA.
- Never bypass signer, package, checksum, ancestry, or provenance checks to restore availability.
- Keep generated diagnostics separate from public secrets and credentials.

## Alternatives considered

### Link directly to the latest GitHub Release asset

Rejected because release naming and attachment alone do not prove APK identity.

### Generate download metadata inside the Android build job only

Rejected because independent verification provides an additional trust boundary and prevents build-job assertions from being the sole source.

### Client-side GitHub API calls with a token

Rejected because a public static site cannot safely hold a private token and client responses still require trustworthy artifact verification.

## References

- `docs/versiondeck-release-runbook.md`
- `docs/versiondeck-live-build-status.md`
- `.github/workflows/deploy-download-site.yml`
- `tool/versiondeck_apk_verifier.mjs`
- `tool/generate_versiondeck_manifest.mjs`
