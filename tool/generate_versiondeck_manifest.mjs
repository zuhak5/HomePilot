import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const MANIFEST_SCHEMA_VERSION = 1;
export const PACKAGE_NAME = "com.homepilot.app";
export const PRODUCTION_CERTIFICATE_SHA256 =
  "3E:98:0E:B5:BB:68:A5:19:90:E7:70:56:D4:E1:09:95:B2:E0:4F:B3:88:A7:34:42:B7:9A:46:C8:53:36:1E:51";

const RELEASE_NAME_PATTERN = /^HomePilot\s+(\d+\.\d+\.\d+)\s+\(Build\s+(\d+)\)$/i;
const TAG_PATTERN = /^v(\d+\.\d+\.\d+)-build\.(\d+)$/i;
const APK_PATTERN = /^HomePilot-(\d+\.\d+\.\d+)-build-(\d+)\.apk$/i;
const SHA256_PATTERN = /^[a-f\d]{64}$/i;

function normalizedSha(value) {
  if (typeof value !== "string") return "";
  const withoutPrefix = value.replace(/^sha256:/i, "");
  const normalized = withoutPrefix.replace(/[^a-f\d]/gi, "").toLowerCase();
  return SHA256_PATTERN.test(normalized) ? normalized : "";
}

export function parseVersion(value) {
  const parts = String(value || "").split(".").map(Number);
  if (parts.length !== 3 || parts.some((part) => !Number.isInteger(part) || part < 0)) {
    return null;
  }
  return parts;
}

export function compareVersionBuild(left, right) {
  const buildDifference = Number(right.build) - Number(left.build);
  if (buildDifference !== 0) return buildDifference;

  const leftParts = parseVersion(left.version) ?? [0, 0, 0];
  const rightParts = parseVersion(right.version) ?? [0, 0, 0];
  for (let index = 0; index < 3; index += 1) {
    const difference = rightParts[index] - leftParts[index];
    if (difference !== 0) return difference;
  }

  const dateDifference = Date.parse(right.publishedAt) - Date.parse(left.publishedAt);
  if (Number.isFinite(dateDifference) && dateDifference !== 0) return dateDifference;
  return Number(right.id) - Number(left.id);
}

export function extractBodySha(body) {
  const match = String(body || "").match(/SHA-256:\s*`?([a-f\d]{64})`?/i);
  return normalizedSha(match?.[1] || "");
}

export function parseChecksumText(value, expectedFileName) {
  const firstMeaningfulLine = String(value || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
  if (!firstMeaningfulLine) return null;

  const match = firstMeaningfulLine.match(/^([a-f\d]{64})\s+\*?(.+)$/i);
  if (!match) return null;

  const sha256 = normalizedSha(match[1]);
  const fileName = match[2].trim();
  if (!sha256 || fileName !== expectedFileName) return null;
  return { sha256, fileName };
}

export function summarizeReleaseBody(body) {
  const withoutBuildDetails = String(body || "")
    .replace(/##\s*Build details[\s\S]*/i, "")
    .replace(/##\s*What's changed/i, "")
    .trim();

  const ignored = /^(included|notes|changes|what's changed|build details)$/i;
  const changelog = withoutBuildDetails
    .split(/\r?\n/)
    .map((line) => line.replace(/^[-*#\s]+/, "").trim())
    .filter(Boolean)
    .filter((line) => !ignored.test(line))
    .filter((line) => !/^HomePilot\s+\d/i.test(line))
    .slice(0, 50);

  const summary = (changelog.slice(0, 2).join(" ") ||
    "Signed production build of HomePilot for Android.").slice(0, 240);

  return { summary, changelog };
}

export function validateReleaseShape(release) {
  const errors = [];
  if (!release || typeof release !== "object") return ["Release is not an object."];
  if (!Number.isInteger(release.id)) errors.push("Release ID is missing or invalid.");
  if (release.draft) errors.push("Draft releases are not eligible.");

  const publishedAt = Date.parse(release.published_at);
  if (!Number.isFinite(publishedAt)) errors.push("published_at is missing or invalid.");
  if (Number.isFinite(publishedAt) && publishedAt > Date.now() + 5 * 60_000) {
    errors.push("published_at is unexpectedly in the future.");
  }

  const nameMatch = String(release.name || "").match(RELEASE_NAME_PATTERN);
  const tagMatch = String(release.tag_name || "").match(TAG_PATTERN);
  if (!nameMatch) errors.push("Release title must match 'HomePilot X.Y.Z (Build N)'.");
  if (!tagMatch) errors.push("Release tag must match 'vX.Y.Z-build.N'.");

  if (nameMatch && tagMatch) {
    if (nameMatch[1] !== tagMatch[1]) errors.push("Release title and tag versions disagree.");
    if (nameMatch[2] !== tagMatch[2]) errors.push("Release title and tag build numbers disagree.");
  }

  return errors;
}

export function selectProductionApk(release, version, build) {
  const expectedName = `HomePilot-${version}-build-${build}.apk`;
  const candidates = (release.assets || []).filter((asset) =>
    String(asset?.name || "").toLowerCase().endsWith(".apk"),
  );
  const exactMatches = candidates.filter((asset) => asset.name === expectedName);

  if (exactMatches.length !== 1) {
    return {
      asset: null,
      error: `Expected exactly one production APK named ${expectedName}; found ${exactMatches.length}.`,
    };
  }

  const asset = exactMatches[0];
  const apkMatch = String(asset.name).match(APK_PATTERN);
  if (!apkMatch || apkMatch[1] !== version || apkMatch[2] !== String(build)) {
    return { asset: null, error: "APK filename does not match release metadata." };
  }
  if (asset.state && asset.state !== "uploaded") {
    return { asset: null, error: `APK asset state is ${asset.state}, not uploaded.` };
  }
  if (!String(asset.browser_download_url || "").startsWith("https://")) {
    return { asset: null, error: "APK download URL is missing or not HTTPS." };
  }

  return { asset, error: null };
}

export async function normalizeRelease(release, { readChecksumAsset } = {}) {
  const errors = validateReleaseShape(release);
  const tagMatch = String(release.tag_name || "").match(TAG_PATTERN);
  if (!tagMatch) return { release: null, errors };

  const version = tagMatch[1];
  const build = Number(tagMatch[2]);
  const apkSelection = selectProductionApk(release, version, build);
  if (apkSelection.error) errors.push(apkSelection.error);
  const apkAsset = apkSelection.asset;

  const expectedChecksumName = apkAsset ? `${apkAsset.name}.sha256` : "";
  const checksumAssets = (release.assets || []).filter(
    (asset) => asset?.name === expectedChecksumName,
  );
  if (apkAsset && checksumAssets.length !== 1) {
    errors.push(`Expected exactly one checksum asset named ${expectedChecksumName}.`);
  }
  const checksumAsset = checksumAssets[0] ?? null;

  let checksumFile = null;
  if (checksumAsset && readChecksumAsset) {
    try {
      checksumFile = parseChecksumText(
        await readChecksumAsset(checksumAsset),
        apkAsset.name,
      );
      if (!checksumFile) errors.push("Checksum asset contents are invalid.");
    } catch (error) {
      errors.push(`Checksum asset could not be read: ${error.message}`);
    }
  }

  const githubDigest = normalizedSha(apkAsset?.digest || "");
  const bodySha = extractBodySha(release.body);
  const checksumSha = checksumFile?.sha256 || "";
  const availableHashes = [githubDigest, checksumSha, bodySha].filter(Boolean);

  if (!availableHashes.length) errors.push("No valid SHA-256 value is available.");
  if (new Set(availableHashes).size > 1) {
    errors.push("GitHub asset digest, checksum file, and release-note SHA-256 disagree.");
  }

  if (errors.length) return { release: null, errors };

  const { summary, changelog } = summarizeReleaseBody(release.body);
  const sha256 = availableHashes[0];

  return {
    errors: [],
    release: {
      id: release.id,
      tag: release.tag_name,
      version,
      build,
      name: `HomePilot ${version}`,
      prerelease: Boolean(release.prerelease),
      publishedAt: new Date(release.published_at).toISOString(),
      releaseUrl: release.html_url,
      commitSha: String(release.target_commitish || ""),
      summary,
      changelog,
      apk: {
        name: apkAsset.name,
        url: apkAsset.browser_download_url,
        size: Number(apkAsset.size) || 0,
        downloadCount: Number(apkAsset.download_count) || 0,
        sha256,
        digestSource: githubDigest ? "github-release-asset" : "release-checksum",
      },
      checksum: {
        name: checksumAsset.name,
        url: checksumAsset.browser_download_url,
      },
      attestation: {
        available: /gh\s+attestation\s+verify/i.test(String(release.body || "")),
        verificationRepository: process.env.GITHUB_REPOSITORY || "zuhak5/HomePilot",
      },
    },
  };
}

export async function buildManifest(rawReleases, options = {}) {
  const validReleases = [];
  const diagnostics = [];

  for (const rawRelease of rawReleases) {
    if (rawRelease?.draft) continue;
    const result = await normalizeRelease(rawRelease, options);
    if (result.release) {
      validReleases.push(result.release);
    } else {
      diagnostics.push({
        id: rawRelease?.id ?? null,
        tag: rawRelease?.tag_name ?? "",
        errors: result.errors,
      });
    }
  }

  validReleases.sort(compareVersionBuild);
  const latestStable = validReleases.find((release) => !release.prerelease) ?? null;
  const latestPrerelease = validReleases.find((release) => release.prerelease) ?? null;

  return {
    manifest: {
      schemaVersion: MANIFEST_SCHEMA_VERSION,
      generatedAt: new Date().toISOString(),
      repository: process.env.GITHUB_REPOSITORY || "zuhak5/HomePilot",
      latestStableReleaseId: latestStable?.id ?? null,
      latestPrereleaseReleaseId: latestPrerelease?.id ?? null,
      productionSigner: {
        packageName: PACKAGE_NAME,
        certificateSha256: PRODUCTION_CERTIFICATE_SHA256,
      },
      releases: validReleases,
    },
    diagnostics,
  };
}

async function githubFetch(url, token, accept = "application/vnd.github+json") {
  const response = await fetch(url, {
    headers: {
      Accept: accept,
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "HomePilot-VersionDeck-Manifest",
    },
  });
  if (!response.ok) {
    throw new Error(`GitHub request failed (${response.status}): ${await response.text()}`);
  }
  return response;
}

async function fetchAllReleases(repository, token) {
  const releases = [];
  let url = `https://api.github.com/repos/${repository}/releases?per_page=100&page=1`;
  while (url) {
    const response = await githubFetch(url, token);
    releases.push(...(await response.json()));
    const link = response.headers.get("link") || "";
    const next = link
      .split(",")
      .map((part) => part.trim())
      .find((part) => part.endsWith('rel="next"'));
    url = next?.match(/<([^>]+)>/)?.[1] || "";
  }
  return releases;
}

async function readChecksumAsset(asset, token) {
  const response = await githubFetch(
    asset.url,
    token,
    "application/octet-stream",
  );
  return response.text();
}

async function main() {
  const repository = process.env.GITHUB_REPOSITORY || "zuhak5/HomePilot";
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN or GH_TOKEN is required.");

  const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
  const repositoryRoot = path.resolve(scriptDirectory, "..");
  const outputPath = path.join(repositoryRoot, "download-site", "releases.json");
  const diagnosticsPath = path.join(
    repositoryRoot,
    "download-site",
    "release-diagnostics.json",
  );

  const rawReleases = await fetchAllReleases(repository, token);
  const { manifest, diagnostics } = await buildManifest(rawReleases, {
    readChecksumAsset: (asset) => readChecksumAsset(asset, token),
  });

  if (rawReleases.some((release) => !release.draft) && !manifest.releases.length) {
    throw new Error(
      `Published releases exist, but none passed VersionDeck validation. Diagnostics: ${JSON.stringify(diagnostics)}`,
    );
  }

  await fs.writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  await fs.writeFile(
    diagnosticsPath,
    `${JSON.stringify({ generatedAt: manifest.generatedAt, diagnostics }, null, 2)}\n`,
    "utf8",
  );

  console.log(
    `Generated VersionDeck manifest with ${manifest.releases.length} valid release(s) and ${diagnostics.length} excluded release(s).`,
  );
}

const invokedAsScript = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedAsScript) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
