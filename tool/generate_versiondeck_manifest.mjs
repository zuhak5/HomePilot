import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  VERSIONDECK_PACKAGE_NAME,
  VERSIONDECK_REPOSITORY,
  VERSIONDECK_SCHEMA_VERSION,
  VERSIONDECK_SIGNER_SHA256,
  validateVersionDeckManifest,
} from "../download-site/manifest-schema.js";
import {
  assertExpectedRepository,
  fetchAllReleases,
  prepareVerificationRepository,
  readChecksumAsset,
  verifyReleaseArtifact,
} from "./versiondeck_apk_verifier.mjs";

const RELEASE_NAME_PATTERN = /^HomePilot\s+(\d+\.\d+\.\d+)\s+\(Build\s+(\d+)\)$/i;
const TAG_PATTERN = /^v(\d+\.\d+\.\d+)-build\.(\d+)$/i;
const APK_PATTERN = /^HomePilot-(\d+\.\d+\.\d+)-build-(\d+)\.apk$/i;
const SHA256_PATTERN = /^[a-f\d]{64}$/i;
const COMMIT_PATTERN = /^[a-f\d]{40}$/i;
const MAX_APK_SIZE_BYTES = 1024 * 1024 * 1024;

function normalizedSha(value) {
  const normalized = String(value || "")
    .replace(/^sha256:/i, "")
    .replace(/[^a-f\d]/gi, "")
    .toLowerCase();
  return SHA256_PATTERN.test(normalized) ? normalized : "";
}

function normalizedSigner(value) {
  const normalized = String(value || "").replace(/[^a-f\d]/gi, "").toUpperCase();
  return normalized.length === 64 ? normalized.match(/.{2}/g).join(":") : "";
}

export function parseVersion(value) {
  const parts = String(value || "").split(".").map(Number);
  return parts.length === 3 && parts.every((part) => Number.isInteger(part) && part >= 0)
    ? parts
    : null;
}

export function compareVersionBuild(left, right) {
  if (right.build !== left.build) return right.build - left.build;
  const leftParts = parseVersion(left.version) ?? [0, 0, 0];
  const rightParts = parseVersion(right.version) ?? [0, 0, 0];
  for (let index = 0; index < 3; index += 1) {
    if (rightParts[index] !== leftParts[index]) return rightParts[index] - leftParts[index];
  }
  const dateDifference = Date.parse(right.publishedAt) - Date.parse(left.publishedAt);
  return dateDifference || Number(right.id) - Number(left.id);
}

export function extractBodySha(body) {
  return normalizedSha(String(body || "").match(/SHA-256:\s*`?([a-f\d]{64})`?/i)?.[1]);
}

export function parseChecksumText(value, expectedFileName) {
  const line = String(value || "")
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/)
    .map((item) => item.trim())
    .find(Boolean);
  const match = line?.match(/^([a-f\d]{64})\s+\*?(.+)$/i);
  if (!match || match[2].trim() !== expectedFileName) return null;
  const sha256 = normalizedSha(match[1]);
  return sha256 ? { sha256, fileName: expectedFileName } : null;
}

export function summarizeReleaseBody(body) {
  const cleaned = String(body || "")
    .replace(/##\s*Build details[\s\S]*/i, "")
    .replace(/##\s*What's changed/i, "")
    .trim();
  const ignored = /^(included|notes|changes|what's changed|build details)$/i;
  const changelog = cleaned
    .split(/\r?\n/)
    .map((line) => line.replace(/^[-*#\s]+/, "").trim())
    .filter(Boolean)
    .filter((line) => !ignored.test(line) && !/^HomePilot\s+\d/i.test(line))
    .map((line) => line.slice(0, 500))
    .slice(0, 50);
  return {
    summary: (changelog.slice(0, 2).join(" ") ||
      "Signed production build of HomePilot for Android.").slice(0, 240),
    changelog,
  };
}

export function validateReleaseShape(release) {
  if (!release || typeof release !== "object") return ["Release is not an object."];
  const errors = [];
  if (!Number.isInteger(release.id)) errors.push("Release ID is missing or invalid.");
  if (release.draft) errors.push("Draft releases are not eligible.");
  const published = Date.parse(release.published_at);
  if (!Number.isFinite(published)) errors.push("published_at is missing or invalid.");
  if (published > Date.now() + 5 * 60_000) errors.push("published_at is in the future.");

  const nameMatch = String(release.name || "").match(RELEASE_NAME_PATTERN);
  const tagMatch = String(release.tag_name || "").match(TAG_PATTERN);
  if (!nameMatch) errors.push("Release title must match 'HomePilot X.Y.Z (Build N)'.");
  if (!tagMatch) errors.push("Release tag must match 'vX.Y.Z-build.N'.");
  if (nameMatch && tagMatch && (nameMatch[1] !== tagMatch[1] || nameMatch[2] !== tagMatch[2])) {
    errors.push("Release title and tag disagree.");
  }
  if (!String(release.html_url || "").startsWith(
    `https://github.com/${VERSIONDECK_REPOSITORY}/releases/`,
  )) errors.push("Release URL is outside the expected repository.");
  return errors;
}

export function selectProductionApk(release, version, build) {
  const expectedName = `HomePilot-${version}-build-${build}.apk`;
  const exact = (release.assets || []).filter((asset) => asset?.name === expectedName);
  if (exact.length !== 1) {
    return { asset: null, error: `Expected exactly one production APK named ${expectedName}; found ${exact.length}.` };
  }
  const asset = exact[0];
  const match = asset.name.match(APK_PATTERN);
  if (!match || match[1] !== version || match[2] !== String(build)) {
    return { asset: null, error: "APK filename does not match release metadata." };
  }
  if (asset.state !== "uploaded") return { asset: null, error: "APK is not uploaded." };
  if (!Number.isInteger(asset.size) || asset.size < 1 || asset.size > MAX_APK_SIZE_BYTES) {
    return { asset: null, error: "APK size is invalid." };
  }
  if (!String(asset.browser_download_url || "").startsWith("https://github.com/")) {
    return { asset: null, error: "APK URL is invalid." };
  }
  return { asset, error: null };
}

function selectChecksum(release, apkName) {
  const expectedName = `${apkName}.sha256`;
  const exact = (release.assets || []).filter((asset) => asset?.name === expectedName);
  if (exact.length !== 1) return { asset: null, error: `Expected exactly one checksum named ${expectedName}.` };
  const asset = exact[0];
  if (asset.state !== "uploaded") return { asset: null, error: "Checksum is not uploaded." };
  if (!String(asset.browser_download_url || "").startsWith("https://github.com/")) {
    return { asset: null, error: "Checksum URL is invalid." };
  }
  return { asset, error: null };
}

export async function normalizeRelease(release, options = {}) {
  const errors = validateReleaseShape(release);
  const tagMatch = String(release.tag_name || "").match(TAG_PATTERN);
  if (!tagMatch) return { release: null, errors };
  const version = tagMatch[1];
  const build = Number(tagMatch[2]);

  const apkResult = selectProductionApk(release, version, build);
  if (apkResult.error) errors.push(apkResult.error);
  if (!apkResult.asset) return { release: null, errors };
  const checksumResult = selectChecksum(release, apkResult.asset.name);
  if (checksumResult.error) errors.push(checksumResult.error);
  if (!checksumResult.asset) return { release: null, errors };

  let checksum = null;
  try {
    if (typeof options.readChecksumAsset !== "function") throw new Error("reader unavailable");
    checksum = parseChecksumText(
      await options.readChecksumAsset(checksumResult.asset),
      apkResult.asset.name,
    );
    if (!checksum) errors.push("Checksum asset contents are invalid.");
  } catch (error) {
    errors.push(`Checksum asset could not be read: ${error.message}`);
  }

  const githubDigest = normalizedSha(apkResult.asset.digest);
  const bodySha = extractBodySha(release.body);
  const asserted = [githubDigest, checksum?.sha256, bodySha].filter(Boolean);
  if (!githubDigest) errors.push("GitHub asset digest is missing.");
  if (!checksum?.sha256) errors.push("Checksum SHA-256 is missing.");
  if (new Set(asserted).size > 1) errors.push("Release SHA-256 sources disagree.");

  let evidence = null;
  try {
    if (typeof options.verifyReleaseArtifact !== "function") throw new Error("verifier unavailable");
    evidence = await options.verifyReleaseArtifact({
      release,
      apkAsset: apkResult.asset,
      version,
      build,
    });
  } catch (error) {
    errors.push(`Independent APK verification failed: ${error.message}`);
  }

  const localSha = normalizedSha(evidence?.sha256);
  if (!localSha) errors.push("Independent APK SHA-256 is missing.");
  if (localSha && asserted.some((sha) => sha !== localSha)) {
    errors.push("Independent APK SHA-256 disagrees with release metadata.");
  }
  if (evidence?.packageName !== VERSIONDECK_PACKAGE_NAME) errors.push("APK package is unexpected.");
  if (evidence?.version !== version) errors.push("APK version is unexpected.");
  if (Number(evidence?.build) !== build) errors.push("APK build is unexpected.");
  if (normalizedSigner(evidence?.signerCertificateSha256) !== VERSIONDECK_SIGNER_SHA256) {
    errors.push("APK signer does not match production policy.");
  }
  if (!COMMIT_PATTERN.test(evidence?.commitSha || "")) errors.push("Release commit is invalid.");
  if (evidence?.attestationVerified !== true) errors.push("Provenance attestation did not verify.");
  if (errors.length) return { release: null, errors };

  const text = summarizeReleaseBody(release.body);
  return {
    errors: [],
    release: {
      id: release.id,
      tag: release.tag_name,
      version,
      build,
      prerelease: Boolean(release.prerelease),
      publishedAt: new Date(release.published_at).toISOString(),
      releaseUrl: release.html_url,
      commitSha: evidence.commitSha.toLowerCase(),
      ...text,
      apk: {
        name: apkResult.asset.name,
        url: apkResult.asset.browser_download_url,
        size: apkResult.asset.size,
        downloadCount: Number(apkResult.asset.download_count) || 0,
        sha256: localSha,
      },
      checksum: {
        name: checksumResult.asset.name,
        url: checksumResult.asset.browser_download_url,
      },
      verification: {
        status: "verified",
        verifiedAt: new Date().toISOString(),
        signerCertificateSha256: VERSIONDECK_SIGNER_SHA256,
        attestationRepository: VERSIONDECK_REPOSITORY,
        apkSha256Verified: true,
        checksumAssetVerified: true,
        githubDigestVerified: true,
        packageNameVerified: true,
        versionVerified: true,
        buildVerified: true,
        signerVerified: true,
        commitVerified: true,
        attestationVerified: true,
      },
    },
  };
}

export async function buildManifest(rawReleases, options = {}) {
  const releases = [];
  const diagnostics = [];
  for (const raw of rawReleases) {
    if (raw?.draft) continue;
    const result = await normalizeRelease(raw, options);
    if (result.release) releases.push(result.release);
    else diagnostics.push({ id: raw?.id ?? null, tag: raw?.tag_name ?? "", errors: result.errors });
  }
  releases.sort(compareVersionBuild);
  const manifest = {
    schemaVersion: VERSIONDECK_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    generatorCommit: String(options.generatorCommit || process.env.VERSIONDECK_GENERATOR_COMMIT || ""),
    repository: VERSIONDECK_REPOSITORY,
    package: {
      name: VERSIONDECK_PACKAGE_NAME,
      signerCertificateSha256: VERSIONDECK_SIGNER_SHA256,
    },
    latestStableReleaseId: releases.find((item) => !item.prerelease)?.id ?? null,
    latestPrereleaseReleaseId: releases.find((item) => item.prerelease)?.id ?? null,
    releases,
  };
  const errors = validateVersionDeckManifest(manifest);
  if (errors.length) throw new Error(`Generated manifest is invalid: ${errors.join(" ")}`);
  return { manifest, diagnostics };
}

function newest(rawReleases, prerelease) {
  return rawReleases
    .filter((release) => !release.draft && Boolean(release.prerelease) === prerelease)
    .filter((release) => Number.isFinite(Date.parse(release.published_at)))
    .sort((left, right) => Date.parse(right.published_at) - Date.parse(left.published_at))[0] ?? null;
}

async function main() {
  const repository = process.env.GITHUB_REPOSITORY || VERSIONDECK_REPOSITORY;
  assertExpectedRepository(repository);
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN or GH_TOKEN is required.");
  const generatorCommit = process.env.VERSIONDECK_GENERATOR_COMMIT || "";
  if (!COMMIT_PATTERN.test(generatorCommit)) {
    throw new Error("VERSIONDECK_GENERATOR_COMMIT must be a full main commit SHA.");
  }
  const checkedOutCommit = await prepareVerificationRepository();
  if (checkedOutCommit !== generatorCommit.toLowerCase()) {
    throw new Error("Checked-out source does not match VERSIONDECK_GENERATOR_COMMIT.");
  }

  const rawReleases = await fetchAllReleases(repository, token);
  const result = await buildManifest(rawReleases, {
    generatorCommit,
    readChecksumAsset: (asset) => readChecksumAsset(asset, token),
    verifyReleaseArtifact: (context) => verifyReleaseArtifact(context, token),
  });
  for (const prerelease of [false, true]) {
    const latest = newest(rawReleases, prerelease);
    if (latest && !result.manifest.releases.some((release) => release.id === latest.id)) {
      throw new Error(`Newest ${prerelease ? "prerelease" : "stable release"} failed verification.`);
    }
  }
  if (rawReleases.some((release) => !release.draft) && !result.manifest.releases.length) {
    throw new Error("Published releases exist, but none passed VersionDeck verification.");
  }

  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const diagnosticsDirectory = path.join(root, ".versiondeck-diagnostics");
  await fs.mkdir(diagnosticsDirectory, { recursive: true });
  await fs.writeFile(
    path.join(root, "download-site", "releases.json"),
    `${JSON.stringify(result.manifest, null, 2)}\n`,
  );
  await fs.writeFile(
    path.join(diagnosticsDirectory, "release-diagnostics.json"),
    `${JSON.stringify({ generatedAt: result.manifest.generatedAt, diagnostics: result.diagnostics }, null, 2)}\n`,
  );
  console.log(
    `Generated VersionDeck schema ${result.manifest.schemaVersion} with ` +
    `${result.manifest.releases.length} verified release(s).`,
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
