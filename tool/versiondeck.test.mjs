import assert from "node:assert/strict";
import test from "node:test";
import {
  buildManifest,
  compareVersionBuild,
  extractBodySha,
  normalizeRelease,
  parseChecksumText,
  selectProductionApk,
} from "./generate_versiondeck_manifest.mjs";
import { formatRelativeTime } from "../download-site/relative-time.js";

const SHA = "a".repeat(64);

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
    html_url: "https://github.com/zuhak5/HomePilot/releases/tag/example",
    target_commitish: "8d512001aae6f11eb3fec4fb3225f2db67e4b6ad",
    body: `## What's changed\n\n- Improved VersionDeck\n\n## Build details\n\n- SHA-256: \`${SHA}\``,
    assets: [
      {
        id: 1,
        name: apkName,
        state: "uploaded",
        size: 12_000_000,
        download_count: 43,
        digest: `sha256:${SHA}`,
        url: "https://api.github.com/repos/zuhak5/HomePilot/releases/assets/1",
        browser_download_url: `https://github.com/zuhak5/HomePilot/releases/download/example/${apkName}`,
      },
      {
        id: 2,
        name: `${apkName}.sha256`,
        state: "uploaded",
        url: "https://api.github.com/repos/zuhak5/HomePilot/releases/assets/2",
        browser_download_url: `https://github.com/zuhak5/HomePilot/releases/download/example/${apkName}.sha256`,
      },
    ],
    ...overrides,
  };
}

test("selectProductionApk requires the exact production filename", () => {
  const fixture = releaseFixture();
  fixture.assets.unshift({
    name: "HomePilot-debug.apk",
    state: "uploaded",
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

test("parseChecksumText validates both hash and filename", () => {
  const fileName = "HomePilot-1.3.1-build-16.apk";
  assert.deepEqual(parseChecksumText(`${SHA}  ${fileName}\n`, fileName), {
    sha256: SHA,
    fileName,
  });
  assert.equal(parseChecksumText(`${SHA}  wrong.apk`, fileName), null);
});

test("extractBodySha reads a release-note SHA", () => {
  assert.equal(extractBodySha(`SHA-256: \`${SHA}\``), SHA);
});

test("normalizeRelease rejects mismatched hash sources", async () => {
  const fixture = releaseFixture();
  fixture.assets[0].digest = `sha256:${"b".repeat(64)}`;
  const result = await normalizeRelease(fixture, {
    readChecksumAsset: async () => `${SHA}  ${fixture.assets[0].name}`,
  });
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("disagree")));
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
    readChecksumAsset: async (asset) => {
      const apkName = asset.name.replace(/\.sha256$/, "");
      return `${SHA}  ${apkName}`;
    },
  });

  assert.equal(manifest.latestStableReleaseId, stable.id);
  assert.equal(manifest.latestPrereleaseReleaseId, prerelease.id);
  assert.equal(manifest.releases[0].id, prerelease.id);
});

test("compareVersionBuild sorts highest build first", () => {
  const releases = [
    { id: 1, version: "2.0.0", build: 2, publishedAt: "2026-01-01T00:00:00Z" },
    { id: 2, version: "1.0.0", build: 3, publishedAt: "2026-01-01T00:00:00Z" },
  ];
  releases.sort(compareVersionBuild);
  assert.equal(releases[0].build, 3);
});

test("relative time renders a 43-minute-old release", () => {
  const now = Date.parse("2026-08-03T11:00:00Z");
  assert.equal(formatRelativeTime("2026-08-03T10:17:00Z", now, "en"), "43 minutes ago");
});

test("relative time handles just now and future values", () => {
  const now = Date.parse("2026-08-03T11:00:00Z");
  assert.equal(formatRelativeTime("2026-08-03T10:59:55Z", now, "en"), "just now");
  assert.equal(formatRelativeTime("2026-08-03T11:02:00Z", now, "en"), "in 2 minutes");
});
