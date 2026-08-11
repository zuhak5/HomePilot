# GitHub Actions Supply-Chain Policy

## Contract

Every external `uses:` reference under `.github/workflows/` and every local
composite action must be reviewable from repository source:

- external actions use an approved 40-character commit SHA;
- the same line retains the reviewed upstream point release as a comment;
- only the exact owner/repository and commit pairs in
  [`tool/github-actions-policy.mjs`](../../tool/github-actions-policy.mjs) are
  accepted;
- local actions live under `./.github/actions/`, have an `action.yml` or
  `action.yaml`, and are scanned by the same contract;
- tags, branches, shortened SHAs, unknown owners/actions, and unreviewed
  replacement commits fail closed;
- the YAML syntax tree is inspected so escaped, multiline, flow, and explicit
  mapping keys cannot hide a `uses` entry;
- custom tags, anchors, and aliases are rejected rather than interpreted
  indirectly.

The validator uses the exact development-only YAML parser declared and locked
by [`package.json`](../../package.json) and `package-lock.json`; it adds no
application/runtime dependency. Run the contract and its negative fixtures
with:

```powershell
npm ci
npm run test:release-workflows
```

The active `Validate Flutter` job runs this contract in its required
`Format, analyze, and test` context. Source still does not prove a successful
run for a particular HomePilot commit or GitHub's hosted Actions allowlist and
require-full-SHA setting. Task 05 owns that hosted policy evidence.

## Reviewed action ledger

The repository used the movable refs in the **Prior ref** column before the
2026-08-12 review. The GitHub API for each official upstream repository was
used to resolve the ref, match its release tag, review its release notes, and
check its public repository-security-advisory list. No published
repository-level advisory was returned for these repositories at review time;
that observation is not a substitute for future update review or dependency
vulnerability scanning.

| Owner/action | Prior ref | Reviewed release | Pinned commit |
| --- | --- | --- | --- |
| `actions/checkout` | `v6` | [`v6.1.0`](https://github.com/actions/checkout/releases/tag/v6.1.0) | `d23441a48e516b6c34aea4fa41551a30e30af803` |
| `actions/setup-node` | `v6` | [`v6.5.0`](https://github.com/actions/setup-node/releases/tag/v6.5.0) | `249970729cb0ef3589644e2896645e5dc5ba9c38` |
| `actions/setup-java` | `v5` | [`v5.7.0`](https://github.com/actions/setup-java/releases/tag/v5.7.0) | `b6effb05e454b25005698d916606bdc6ffcbf961` |
| `actions/upload-artifact` | `v4` | [`v4.6.2`](https://github.com/actions/upload-artifact/releases/tag/v4.6.2) | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| `actions/upload-artifact` | `v6` | [`v6.0.0`](https://github.com/actions/upload-artifact/releases/tag/v6.0.0) | `b7c566a772e6b6bfb58ed0dc250532a479d7789f` |
| `actions/upload-artifact` | `v7` | [`v7.0.1`](https://github.com/actions/upload-artifact/releases/tag/v7.0.1) | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/attest-build-provenance` | `v3` | [`v3.0.0`](https://github.com/actions/attest-build-provenance/releases/tag/v3.0.0) | `977bb373ede98d70efdf65b84cb5f73e068dcc2a` |
| `actions/configure-pages` | `v6` | [`v6.0.0`](https://github.com/actions/configure-pages/releases/tag/v6.0.0) | `45bfe0192ca1faeb007ade9deae92b16b8254a0d` |
| `actions/upload-pages-artifact` | `v5` | [`v5.0.0`](https://github.com/actions/upload-pages-artifact/releases/tag/v5.0.0) | `fc324d3547104276b827a68afc52ff2a11cc49c9` |
| `actions/deploy-pages` | `v5` | [`v5.0.0`](https://github.com/actions/deploy-pages/releases/tag/v5.0.0) | `cd2ce8fcbc39b97be8ca5fce6e763baed58fa128` |
| `denoland/setup-deno` | `v2` branch | [`v2.0.5`](https://github.com/denoland/setup-deno/releases/tag/v2.0.5) | `22d081ff2d3a40755e97629de92e3bcbfa7cf2ed` |
| `subosito/flutter-action` | `v2` | [`v2.23.0`](https://github.com/subosito/flutter-action/releases/tag/v2.23.0) | `1a449444c387b1966244ae4d4f8c696479add0b2` |

`actions/attest-build-provenance@v3` is an annotated tag. The ledger and
workflow pin use its peeled release commit, not the tag-object SHA.

## Review notes

The release review found no reason to change the already selected major
versions. Relevant upstream notes that future reviewers must preserve include:

- `actions/checkout@v6.1.0` changes the safer `pull_request_target` checkout
  default. HomePilot does not use `pull_request_target`.
- `actions/setup-node@v6.5.0` and `actions/setup-java@v5.7.0` include upstream
  dependency/audit fixes; the Java release also deprecates legacy Adopt
  distributions, while HomePilot uses Temurin.
- `actions/upload-artifact@v6`, the Pages actions, `setup-deno@v2.0.5`, and
  `attest-build-provenance@v3.0.0` use Node 24. The artifact and attestation
  notes require runner `2.327.1` or newer; HomePilot currently uses GitHub-hosted
  runners, but an exact workflow run is still required as execution evidence.
- The Flutter action release adds optional FVM/pub-cache behavior, but the
  existing HomePilot inputs remain unchanged.

## Update ownership and procedure

[Dependabot](../../.github/dependabot.yml) checks GitHub Actions weekly and
requests review from `movinesta` and `sijelna`. It is discovery automation only:
HomePilot has no Actions auto-merge rule, and protected `main` still requires a
current independent approval.

For each update PR, repository owner `zuhak5` maintains the ledger and policy;
an independent reviewer approves or rejects the update. The PR must:

1. Confirm the exact official owner/repository and inspect ownership changes.
2. Review upstream release notes, security advisories, runtime/runner
   requirements, and any permission or input changes.
3. Resolve the release tag to its commit, peeling annotated tags, and compare
   that identity with Dependabot's proposed digest.
4. Update the workflow pin/comment, policy allowlist, and this ledger together.
5. Run `npm run test:release-workflows` and inspect the workflow diff for
   trigger, permission, environment, command, and gate changes.
6. Obtain independent review and required CI for the exact HomePilot commit.

Never merge a digest-only change because automation proposed it, never replace
an exact pin with a tag to clear a failure, and never enable auto-merge for
production Action updates.
