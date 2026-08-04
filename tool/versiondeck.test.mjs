import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  buildManifest,
  compareVersionBuild,
  extractBodySha,
  normalizeRelease,
  parseChecksumText,
  selectProductionApk,
} from "./generate_versiondeck_manifest.mjs";
import { formatRelativeTime } from "../download-site/relative-time.js";
import {
  VERSIONDECK_PACKAGE_NAME,
  VERSIONDECK_REPOSITORY,
  VERSIONDECK_SIGNER_SHA256,
  validateVersionDeckManifest,
} from "../download-site/manifest-schema.js";
import {
  RELEASE_CACHE_SCHEMA_VERSION,
  ReleaseCacheState,
  classifyReleaseCache,
} from "../download-site/cache-policy.js";

const SHA = "a".repeat(64);
const COMMIT = "b".repeat(40);
const NOW = Date.parse("2026-08-04T13:00:00Z");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function releaseFixture(overrides = {}) {
  const version = overrides.version || "1.3.1";
  const build = overrides.build || 16;
  const apkName = `HomePilot-${version}-build-${build}.apk`;
  return {
    id: 1000 + build,
    draft: false,
    prerelease: false,
    name: `HomePilot ${version} (Build ${build})`,
    tag_name: `v${version}-build.${build}`,
    published_at: "2026-08-03T10:00:00Z",
    html_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/tag/example`,
    target_commitish: COMMIT,
    body: `## What's changed\n\n- Improved VersionDeck\n\n## Build details\n\n- SHA-256: \`${SHA}\``,
    assets: [
      {
        id: 1,
        name: apkName,
        state: "uploaded",
        size: 12_000_000,
        download_count: 43,
        digest: `sha256:${SHA}`,
        url: `https://api.github.com/repos/${VERSIONDECK_REPOSITORY}/releases/assets/1`,
        browser_download_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/download/example/${apkName}`,
      },
      {
        id: 2,
        name: `${apkName}.sha256`,
        state: "uploaded",
        size: 100,
        url: `https://api.github.com/repos/${VERSIONDECK_REPOSITORY}/releases/assets/2`,
        browser_download_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/download/example/${apkName}.sha256`,
      },
    ],
    ...overrides,
  };
}

function verifierFixture(overrides = {}) {
  return {
    sha256: SHA,
    packageName: VERSIONDECK_PACKAGE_NAME,
    version: "1.3.1",
    build: 16,
    signerCertificateSha256: VERSIONDECK_SIGNER_SHA256,
    commitSha: COMMIT,
    attestationVerified: true,
    ...overrides,
  };
}

function normalizationOptions(overrides = {}) {
  return {
    readChecksumAsset: async (asset) => `${SHA}  ${asset.name.replace(/\.sha256$/, "")}`,
    verifyReleaseArtifact: async ({ version, build }) => verifierFixture({ version, build }),
    ...overrides,
  };
}

test("selectProductionApk requires the exact production filename", () => {
  const fixture = releaseFixture();
  fixture.assets.unshift({
    name: "HomePilot-debug.apk",
    state: "uploaded",
    size: 100,
    browser_download_url: "https://github.com/example/debug.apk",
  });
  const result = selectProductionApk(fixture, "1.3.1", 16);
  assert.equal(result.asset.name, "HomePilot-1.3.1-build-16.apk");
});

test("selectProductionApk rejects duplicate exact assets", () => {
  const fixture = releaseFixture();
  fixture.assets.push({ ...fixture.assets[0], id: 99 });
  const result = selectProductionApk(fixture, "1.3.1", 16);
  assert.equal(result.asset, null);
  assert.match(result.error, /exactly one production APK/);
});

test("parseChecksumText validates hash and filename", () => {
  const fileName = "HomePilot-1.3.1-build-16.apk";
  assert.deepEqual(parseChecksumText(`\uFEFF${SHA}  ${fileName}\r\n`, fileName), {
    sha256: SHA,
    fileName,
  });
  assert.equal(parseChecksumText(`${SHA}  wrong.apk`, fileName), null);
});

test("extractBodySha reads a release-note SHA", () => {
  assert.equal(extractBodySha(`SHA-256: \`${SHA}\``), SHA);
});

test("normalizeRelease rejects mismatched independent hash", async () => {
  const result = await normalizeRelease(
    releaseFixture(),
    normalizationOptions({
      verifyReleaseArtifact: async () => verifierFixture({ sha256: "c".repeat(64) }),
    }),
  );
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("Independent APK SHA-256 disagrees")));
});

test("normalizeRelease rejects an unexpected signer", async () => {
  const result = await normalizeRelease(
    releaseFixture(),
    normalizationOptions({
      verifyReleaseArtifact: async () => verifierFixture({
        signerCertificateSha256: "AA:".repeat(31) + "AA",
      }),
    }),
  );
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("signer")));
});

test("normalizeRelease requires attestation verification", async () => {
  const result = await normalizeRelease(
    releaseFixture(),
    normalizationOptions({
      verifyReleaseArtifact: async () => verifierFixture({ attestationVerified: false }),
    }),
  );
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("attestation")));
});

test("buildManifest keeps prerelease separate from latest stable", async () => {
  const stable = releaseFixture({ id: 1016, build: 16 });
  const prerelease = releaseFixture({
    id: 1017,
    build: 17,
    prerelease: true,
    name: "HomePilot 1.4.0 (Build 17)",
    tag_name: "v1.4.0-build.17",
    version: "1.4.0",
  });
  prerelease.assets = releaseFixture({ version: "1.4.0", build: 17 }).assets;

  const { manifest } = await buildManifest([stable, prerelease], {
    ...normalizationOptions(),
    generatorCommit: COMMIT,
  });

  assert.equal(manifest.latestStableReleaseId, stable.id);
  assert.equal(manifest.latestPrereleaseReleaseId, prerelease.id);
  assert.equal(manifest.releases[0].id, prerelease.id);
  assert.deepEqual(validateVersionDeckManifest(manifest), []);
});

test("manifest validation requires exact verification evidence", async () => {
  const { manifest } = await buildManifest([releaseFixture()], {
    ...normalizationOptions(),
    generatorCommit: COMMIT,
  });
  manifest.releases[0].verification.signerVerified = false;
  assert.ok(validateVersionDeckManifest(manifest).some((error) => error.includes("signerVerified")));
});

test("compareVersionBuild sorts highest build first", () => {
  const releases = [
    { id: 1, version: "2.0.0", build: 2, publishedAt: "2026-01-01T00:00:00Z" },
    { id: 2, version: "1.0.0", build: 3, publishedAt: "2026-01-01T00:00:00Z" },
  ];
  releases.sort(compareVersionBuild);
  assert.equal(releases[0].build, 3);
});

test("cache policy is conservative and expires after 24 hours", () => {
  const manifest = { generatedAt: new Date(NOW - 25 * 60 * 60 * 1000).toISOString() };
  const record = {
    schemaVersion: RELEASE_CACHE_SCHEMA_VERSION,
    fetchedAt: new Date(NOW - 1 * 60 * 60 * 1000).toISOString(),
    manifest,
  };
  const policy = classifyReleaseCache(record, { now: NOW });
  assert.equal(policy.state, ReleaseCacheState.EXPIRED);
  assert.equal(policy.ageMs, 25 * 60 * 60 * 1000);
});

test("cache policy does not mutate or renew timestamps", () => {
  const record = {
    schemaVersion: RELEASE_CACHE_SCHEMA_VERSION,
    fetchedAt: new Date(NOW - 7 * 60 * 60 * 1000).toISOString(),
    manifest: { generatedAt: new Date(NOW - 7 * 60 * 60 * 1000).toISOString() },
  };
  const before = JSON.stringify(record);
  assert.equal(classifyReleaseCache(record, { now: NOW }).state, ReleaseCacheState.CACHED_STALE);
  assert.equal(classifyReleaseCache(record, { now: NOW + 18 * 60 * 60 * 1000 }).state, ReleaseCacheState.EXPIRED);
  assert.equal(JSON.stringify(record), before);
});

test("relative time renders past and future values", () => {
  const now = Date.parse("2026-08-03T11:00:00Z");
  assert.equal(formatRelativeTime("2026-08-03T10:17:00Z", now, "en"), "43 minutes ago");
  assert.equal(formatRelativeTime("2026-08-03T11:02:00Z", now, "en"), "in 2 minutes");
});

test("service worker never caches releases.json", async () => {
  const serviceWorker = await fs.readFile(path.join(root, "download-site", "sw.js"), "utf8");
  const appShell = serviceWorker.match(/const APP_SHELL = \[([\s\S]*?)\];/)?.[1] || "";
  assert.doesNotMatch(appShell, /releases\.json/);
  assert.match(serviceWorker, /fetch\(request, \{ cache: "no-store" \}\)/);
});

test("deployment workflow always checks out main and handles withdrawal", async () => {
  const workflow = await fs.readFile(
    path.join(root, ".github", "workflows", "deploy-download-site.yml"),
    "utf8",
  );
  assert.match(workflow, /ref:\s*refs\/heads\/main/);
  assert.match(workflow, /- unpublished/);
  assert.match(workflow, /jobs:\s*\n\s*build:/);
  assert.match(workflow, /\n  deploy:[\s\S]*?\n    needs:\s*build/);
});
