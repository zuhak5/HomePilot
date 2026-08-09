export const VERSIONDECK_SCHEMA_VERSION = 2;
export const VERSIONDECK_REPOSITORY = "zuhak5/HomePilot";
export const VERSIONDECK_PACKAGE_NAME = "com.homepilot.app";
export const VERSIONDECK_SIGNER_SHA256 =
  "3E:98:0E:B5:BB:68:A5:19:90:E7:70:56:D4:E1:09:95:B2:E0:4F:B3:88:A7:34:42:B7:9A:46:C8:53:36:1E:51";

const MAX_RELEASES = 200;
const MAX_SUMMARY_LENGTH = 240;
const MAX_CHANGELOG_ITEMS = 50;
const MAX_CHANGELOG_ITEM_LENGTH = 500;
const MAX_APK_SIZE_BYTES = 1024 * 1024 * 1024;
const FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;
const SHA256_PATTERN = /^[a-f\d]{64}$/i;
const COMMIT_PATTERN = /^[a-f\d]{40}$/i;
const VERSION_PATTERN = /^\d+\.\d+\.\d+$/;
const SIGNER_PATTERN = /^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/;
const DOWNLOAD_HOSTS = new Set([
  "github.com",
  "objects.githubusercontent.com",
  "release-assets.githubusercontent.com",
]);

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isValidDate(value, now) {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed <= now + FUTURE_CLOCK_SKEW_MS;
}

function validateUrl(value, allowedHosts, requiredPathPrefix = "") {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      allowedHosts.has(url.hostname) &&
      (!requiredPathPrefix || url.pathname.startsWith(requiredPathPrefix))
    );
  } catch {
    return false;
  }
}

function compareVersionBuild(left, right) {
  if (right.build !== left.build) return right.build - left.build;
  const leftParts = left.version.split(".").map(Number);
  const rightParts = right.version.split(".").map(Number);
  for (let index = 0; index < 3; index += 1) {
    if (rightParts[index] !== leftParts[index]) {
      return rightParts[index] - leftParts[index];
    }
  }
  return Date.parse(right.publishedAt) - Date.parse(left.publishedAt);
}

export function validateVersionDeckManifest(manifest, { now = Date.now() } = {}) {
  const errors = [];
  if (!isPlainObject(manifest)) return ["Manifest is not an object."];

  if (manifest.schemaVersion !== VERSIONDECK_SCHEMA_VERSION) {
    errors.push("Unsupported release manifest schema.");
  }
  if (manifest.repository !== VERSIONDECK_REPOSITORY) {
    errors.push("Unexpected release repository.");
  }
  if (!isValidDate(manifest.generatedAt, now)) {
    errors.push("Manifest generation time is invalid.");
  }
  if (!COMMIT_PATTERN.test(manifest.generatorCommit || "")) {
    errors.push("Manifest generator commit is invalid.");
  }
  if (manifest.package?.name !== VERSIONDECK_PACKAGE_NAME) {
    errors.push("Unexpected production package identity.");
  }
  if (manifest.package?.signerCertificateSha256 !== VERSIONDECK_SIGNER_SHA256) {
    errors.push("Unexpected production signer fingerprint.");
  }
  if (!SIGNER_PATTERN.test(manifest.package?.signerCertificateSha256 || "")) {
    errors.push("Production signer fingerprint has invalid formatting.");
  }
  if (!Array.isArray(manifest.releases)) {
    errors.push("Release list is missing.");
    return errors;
  }
  if (manifest.releases.length > MAX_RELEASES) {
    errors.push(`Release list exceeds ${MAX_RELEASES} entries.`);
  }

  const ids = new Set();
  for (const release of manifest.releases) {
    if (!isPlainObject(release)) {
      errors.push("Release entry is not an object.");
      continue;
    }
    const releaseLabel = Number.isInteger(release.id) ? `Release ${release.id}` : "Release";
    if (!Number.isInteger(release.id) || release.id < 1 || ids.has(release.id)) {
      errors.push(`${releaseLabel} has a missing or duplicated ID.`);
    } else {
      ids.add(release.id);
    }
    if (!VERSION_PATTERN.test(release.version || "")) {
      errors.push(`${releaseLabel} has an invalid version.`);
    }
    if (!Number.isInteger(release.build) || release.build < 1) {
      errors.push(`${releaseLabel} has an invalid build number.`);
    }
    if (release.tag !== `v${release.version}-build.${release.build}`) {
      errors.push(`${releaseLabel} tag does not match version and build.`);
    }
    if (typeof release.prerelease !== "boolean") {
      errors.push(`${releaseLabel} prerelease flag is invalid.`);
    }
    if (!isValidDate(release.publishedAt, now)) {
      errors.push(`${releaseLabel} has an invalid publication time.`);
    }
    if (!validateUrl(
      release.releaseUrl,
      new Set(["github.com"]),
      `/${VERSIONDECK_REPOSITORY}/releases/`,
    )) {
      errors.push(`${releaseLabel} has an invalid release URL.`);
    }
    if (!COMMIT_PATTERN.test(release.commitSha || "")) {
      errors.push(`${releaseLabel} has an invalid release commit.`);
    }
    if (typeof release.summary !== "string" || release.summary.length > MAX_SUMMARY_LENGTH) {
      errors.push(`${releaseLabel} has an invalid summary.`);
    }
    if (
      !Array.isArray(release.changelog) ||
      release.changelog.length > MAX_CHANGELOG_ITEMS ||
      release.changelog.some(
        (item) => typeof item !== "string" || item.length > MAX_CHANGELOG_ITEM_LENGTH,
      )
    ) {
      errors.push(`${releaseLabel} has an invalid changelog.`);
    }

    const expectedApkName = `HomePilot-${release.version}-build-${release.build}.apk`;
    if (release.apk?.name !== expectedApkName) {
      errors.push(`${releaseLabel} APK name does not match release metadata.`);
    }
    if (!validateUrl(release.apk?.url, DOWNLOAD_HOSTS)) {
      errors.push(`${releaseLabel} has an invalid APK URL.`);
    }
    if (
      !Number.isInteger(release.apk?.size) ||
      release.apk.size < 1 ||
      release.apk.size > MAX_APK_SIZE_BYTES
    ) {
      errors.push(`${releaseLabel} has an invalid APK size.`);
    }
    if (!Number.isInteger(release.apk?.downloadCount) || release.apk.downloadCount < 0) {
      errors.push(`${releaseLabel} has an invalid download count.`);
    }
    if (!SHA256_PATTERN.test(release.apk?.sha256 || "")) {
      errors.push(`${releaseLabel} has an invalid APK SHA-256.`);
    }

    if (release.checksum?.name !== `${expectedApkName}.sha256`) {
      errors.push(`${releaseLabel} checksum name does not match the APK.`);
    }
    if (!validateUrl(release.checksum?.url, DOWNLOAD_HOSTS)) {
      errors.push(`${releaseLabel} has an invalid checksum URL.`);
    }

    const verification = release.verification;
    if (!isPlainObject(verification) || verification.status !== "verified") {
      errors.push(`${releaseLabel} is not verified.`);
    } else {
      if (!isValidDate(verification.verifiedAt, now)) {
        errors.push(`${releaseLabel} verification time is invalid.`);
      }
      if (verification.signerCertificateSha256 !== VERSIONDECK_SIGNER_SHA256) {
        errors.push(`${releaseLabel} signer verification does not match policy.`);
      }
      if (verification.attestationRepository !== VERSIONDECK_REPOSITORY) {
        errors.push(`${releaseLabel} attestation repository is invalid.`);
      }
      for (const property of [
        "apkSha256Verified",
        "checksumAssetVerified",
        "githubDigestVerified",
        "packageNameVerified",
        "versionVerified",
        "buildVerified",
        "signerVerified",
        "commitVerified",
        "attestationVerified",
      ]) {
        if (verification[property] !== true) {
          errors.push(`${releaseLabel} verification flag ${property} is not true.`);
        }
      }
    }
  }

  for (let index = 1; index < manifest.releases.length; index += 1) {
    if (compareVersionBuild(manifest.releases[index - 1], manifest.releases[index]) > 0) {
      errors.push("Release list is not sorted by descending build and version.");
      break;
    }
  }

  const stable = manifest.latestStableReleaseId;
  if (
    stable !== null &&
    !manifest.releases.some((release) => release.id === stable && !release.prerelease)
  ) {
    errors.push("Latest stable release does not reference a stable release.");
  }
  const prerelease = manifest.latestPrereleaseReleaseId;
  if (
    prerelease !== null &&
    !manifest.releases.some((release) => release.id === prerelease && release.prerelease)
  ) {
    errors.push("Latest prerelease does not reference a prerelease.");
  }

  return errors;
}
