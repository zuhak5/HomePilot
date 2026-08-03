import {
  createRelativeTimeElement,
  formatExactDateTime,
  updateRelativeTimeElements,
} from "./relative-time.js";

const MANIFEST_URL = "./releases.json";
const CACHE_KEY = "versiondeck-release-manifest-v3";
const CACHE_FRESH_MS = 6 * 60 * 60 * 1000;
const CACHE_MAX_MS = 24 * 60 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 12_000;
const EXPECTED_SCHEMA_VERSION = 1;
const EXPECTED_REPOSITORY = "zuhak5/HomePilot";
const ALLOWED_DOWNLOAD_HOSTS = new Set([
  "github.com",
  "objects.githubusercontent.com",
  "release-assets.githubusercontent.com",
]);

const numberFormat = new Intl.NumberFormat();

const latestCard = document.querySelector("#latest-card");
const releaseList = document.querySelector("#release-list");
const releaseCount = document.querySelector("#release-count");
const releaseTemplate = document.querySelector("#release-template");
const refreshButton = document.querySelector("#refresh-button");
const stickyDownload = document.querySelector("#sticky-download");
const stickyVersion = document.querySelector("#sticky-version");
const stickyDownloadLink = document.querySelector("#sticky-download-link");
const installButtons = document.querySelectorAll(".install-button");
const toast = document.querySelector("#toast");
const releaseStatus = document.querySelector("#release-status");
const staleBanner = document.querySelector("#stale-banner");
const staleBannerText = document.querySelector("#stale-banner-text");
const updateNotice = document.querySelector("#update-notice");
const updateButton = document.querySelector("#update-button");

let deferredInstallPrompt = null;
let toastTimer = null;
let relativeTimeTimer = null;
let activeRequestController = null;
let waitingServiceWorker = null;
let requestGeneration = 0;

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "Unknown size";
  const units = ["B", "KB", "MB", "GB"];
  const index = Math.min(
    Math.floor(Math.log(bytes) / Math.log(1024)),
    units.length - 1,
  );
  return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("visible");
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove("visible"), 2600);
}

function announce(message) {
  releaseStatus.textContent = "";
  window.requestAnimationFrame(() => {
    releaseStatus.textContent = message;
  });
}

function safeUrl(value, allowedHosts = ALLOWED_DOWNLOAD_HOSTS) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || !allowedHosts.has(url.hostname)) return "";
    return url.href;
  } catch {
    return "";
  }
}

function validateSha256(value) {
  return typeof value === "string" && /^[a-f\d]{64}$/i.test(value);
}

function validateManifest(manifest) {
  const errors = [];
  if (!manifest || typeof manifest !== "object") return ["Manifest is not an object."];
  if (manifest.schemaVersion !== EXPECTED_SCHEMA_VERSION) {
    errors.push("Unsupported release manifest schema.");
  }
  if (manifest.repository !== EXPECTED_REPOSITORY) {
    errors.push("Unexpected release repository.");
  }
  if (!Number.isFinite(Date.parse(manifest.generatedAt))) {
    errors.push("Manifest generation time is invalid.");
  }
  if (!Array.isArray(manifest.releases)) errors.push("Release list is missing.");
  if (manifest.productionSigner?.packageName !== "com.homepilot.app") {
    errors.push("Unexpected production package identity.");
  }
  if (!/^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/i.test(
    manifest.productionSigner?.certificateSha256 || "",
  )) {
    errors.push("Production signer fingerprint is invalid.");
  }

  const ids = new Set();
  for (const release of manifest.releases || []) {
    if (!Number.isInteger(release.id) || ids.has(release.id)) {
      errors.push("Release IDs are missing or duplicated.");
      continue;
    }
    ids.add(release.id);
    if (!/^\d+\.\d+\.\d+$/.test(release.version || "")) {
      errors.push(`Release ${release.id} has an invalid version.`);
    }
    if (!Number.isInteger(release.build) || release.build < 1) {
      errors.push(`Release ${release.id} has an invalid build number.`);
    }
    if (!Number.isFinite(Date.parse(release.publishedAt))) {
      errors.push(`Release ${release.id} has an invalid publication time.`);
    }
    if (
      !safeUrl(release.apk?.url) ||
      !safeUrl(release.checksum?.url) ||
      !safeUrl(release.releaseUrl, new Set(["github.com"]))
    ) {
      errors.push(`Release ${release.id} has an invalid URL.`);
    }
    if (!validateSha256(release.apk?.sha256)) {
      errors.push(`Release ${release.id} has an invalid SHA-256.`);
    }
  }

  if (
    manifest.latestStableReleaseId !== null &&
    !manifest.releases?.some(
      (release) =>
        release.id === manifest.latestStableReleaseId && !release.prerelease,
    )
  ) {
    errors.push("Latest stable release does not reference an eligible stable release.");
  }

  return errors;
}

function resetReleaseUi() {
  stickyDownload.hidden = true;
  stickyDownloadLink.removeAttribute("href");
  stickyVersion.textContent = "HomePilot";
  document.body.classList.remove("has-sticky-download");
  staleBanner.hidden = true;
  latestCard.classList.remove("loading-card");
  latestCard.setAttribute("aria-busy", "false");
  latestCard.replaceChildren();
  releaseList.replaceChildren();
  releaseCount.textContent = "";
}

function createTextElement(tagName, text, className = "") {
  const element = document.createElement(tagName);
  element.textContent = text;
  if (className) element.className = className;
  return element;
}

function createExternalLink(label, href, className = "") {
  const link = document.createElement("a");
  link.textContent = label;
  link.href = href;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  if (className) link.className = className;
  return link;
}

async function copyText(text, successMessage) {
  try {
    await navigator.clipboard.writeText(text);
    showToast(successMessage);
  } catch {
    showToast("Copy failed. Open the verification details to select the value.");
  }
}

function createCopyRow(label, value) {
  const row = document.createElement("div");
  row.className = "verification-row";
  const content = document.createElement("div");
  content.append(
    createTextElement("span", label, "verification-label"),
    createTextElement("code", value, "verification-value"),
  );
  const button = createTextElement("button", "Copy", "copy-button");
  button.type = "button";
  button.addEventListener("click", () => copyText(value, `${label} copied`));
  row.append(content, button);
  return row;
}

function renderVerificationPanel(container, release, signer) {
  const details = document.createElement("details");
  details.className = "verification-details";
  const summary = createTextElement("summary", "Verify this download");
  const explanation = createTextElement(
    "p",
    "SHA-256 verifies file integrity. The Android signer certificate verifies continuity with the expected HomePilot production signing key.",
    "verification-explanation",
  );
  details.append(summary, explanation);
  details.append(
    createCopyRow("APK SHA-256", release.apk.sha256),
    createCopyRow("Signer certificate SHA-256", signer.certificateSha256),
  );
  if (release.commitSha) details.append(createCopyRow("Release commit", release.commitSha));

  const commands = document.createElement("div");
  commands.className = "verification-commands";
  commands.append(createTextElement("strong", "Verification commands"));
  const commandList = [
    `Get-FileHash .\\${release.apk.name} -Algorithm SHA256`,
    `sha256sum ${release.apk.name}`,
    `shasum -a 256 ${release.apk.name}`,
  ];
  if (release.attestation?.available) {
    commandList.push(
      `gh attestation verify ${release.apk.name} --repo ${release.attestation.verificationRepository || EXPECTED_REPOSITORY}`,
    );
  }
  for (const command of commandList) {
    const pre = document.createElement("pre");
    pre.textContent = command;
    commands.append(pre);
  }
  details.append(commands);
  container.append(details);
}

function addFact(list, label, value) {
  const wrapper = document.createElement("div");
  wrapper.append(
    createTextElement("dt", label),
    createTextElement("dd", value),
  );
  list.append(wrapper);
}

function renderLatest(release, signer) {
  const layout = document.createElement("div");
  layout.className = "latest-layout";
  const content = document.createElement("div");
  const status = document.createElement("div");
  status.className = "latest-status";
  status.append(
    createTextElement(
      "span",
      release.prerelease ? "Pre-release" : "Latest stable",
      `status-pill ${release.prerelease ? "status-prerelease" : "status-stable"}`,
    ),
    createRelativeTimeElement(release.publishedAt, {
      prefix: "Published ",
      className: "latest-date",
    }),
  );

  const title = createTextElement("h3", `HomePilot ${release.version}`, "latest-title");
  const summary = createTextElement("p", release.summary, "latest-summary");
  const facts = document.createElement("dl");
  facts.className = "fact-list";
  addFact(facts, "Build", numberFormat.format(release.build));
  addFact(facts, "APK size", formatBytes(release.apk.size));
  addFact(facts, "Downloads", numberFormat.format(release.apk.downloadCount || 0));

  const checksum = document.createElement("div");
  checksum.className = "checksum";
  const checksumCode = createTextElement("code", `SHA-256 ${release.apk.sha256}`);
  checksumCode.title = release.apk.sha256;
  const checksumCopy = createTextElement("button", "Copy", "copy-button");
  checksumCopy.type = "button";
  checksumCopy.addEventListener("click", () => copyText(release.apk.sha256, "APK SHA-256 copied"));
  checksum.append(checksumCode, checksumCopy);

  const exactDate = createTextElement(
    "p",
    `Exact publication time: ${formatExactDateTime(release.publishedAt)}`,
    "exact-date",
  );

  content.append(status, title, summary, facts, checksum, exactDate);
  renderVerificationPanel(content, release, signer);

  const actions = document.createElement("div");
  actions.className = "latest-actions";
  const download = createExternalLink("Download latest APK", release.apk.url, "button button-primary");
  download.removeAttribute("target");
  download.removeAttribute("rel");
  actions.append(
    download,
    createExternalLink("Release notes", release.releaseUrl, "button button-secondary"),
    createExternalLink("Checksum file", release.checksum.url, "button button-secondary"),
  );

  layout.append(content, actions);
  latestCard.append(layout);

  stickyVersion.textContent = `HomePilot ${release.version}`;
  stickyDownloadLink.href = release.apk.url;
  stickyDownload.hidden = false;
  document.body.classList.add("has-sticky-download");
}

function renderChangelog(container, release) {
  if (!release.changelog?.length) {
    container.append(createTextElement("p", "No changelog was supplied."));
    return;
  }
  const list = document.createElement("ul");
  for (const item of release.changelog) list.append(createTextElement("li", item));
  container.append(list);
}

function appendMetadataPart(meta, node) {
  if (meta.childNodes.length) meta.append(document.createTextNode(" · "));
  meta.append(node);
}

function renderArchive(releases, signer, latestStableId) {
  releaseCount.textContent = `${numberFormat.format(releases.length)} ${
    releases.length === 1 ? "version" : "versions"
  }`;

  releases.forEach((release) => {
    const fragment = releaseTemplate.content.cloneNode(true);
    const card = fragment.querySelector(".release-card");
    const title = fragment.querySelector(".release-title");
    const label = fragment.querySelector(".release-label");
    const meta = fragment.querySelector(".release-meta");
    const download = fragment.querySelector(".archive-download");
    const toggle = fragment.querySelector(".details-toggle");
    const details = fragment.querySelector(".release-details");
    const changelog = fragment.querySelector(".changelog");
    const links = fragment.querySelector(".release-links");
    const exactDate = fragment.querySelector(".archive-exact-date");
    const verification = fragment.querySelector(".archive-verification");

    const detailId = `release-details-${release.id}`;
    details.id = detailId;
    toggle.setAttribute("aria-controls", detailId);
    title.textContent = `HomePilot ${release.version}`;

    if (release.id === latestStableId) {
      label.textContent = "Latest stable";
      label.classList.add("status-stable");
    } else if (release.prerelease) {
      label.textContent = "Pre-release";
      label.classList.add("status-prerelease");
    }

    appendMetadataPart(meta, document.createTextNode(`Build ${numberFormat.format(release.build)}`));
    appendMetadataPart(meta, createRelativeTimeElement(release.publishedAt));
    appendMetadataPart(meta, document.createTextNode(formatBytes(release.apk.size)));
    appendMetadataPart(
      meta,
      document.createTextNode(`${numberFormat.format(release.apk.downloadCount || 0)} downloads`),
    );

    download.href = release.apk.url;
    exactDate.textContent = `Published ${formatExactDateTime(release.publishedAt)}`;
    renderChangelog(changelog, release);
    links.append(
      createExternalLink("GitHub release", release.releaseUrl),
      createExternalLink("Checksum file", release.checksum.url),
    );
    const copy = createTextElement("button", "Copy SHA-256");
    copy.type = "button";
    copy.addEventListener("click", () => copyText(release.apk.sha256, "APK SHA-256 copied"));
    links.append(copy);
    renderVerificationPanel(verification, release, signer);

    toggle.addEventListener("click", () => {
      const isOpen = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!isOpen));
      toggle.textContent = isOpen ? "Changes" : "Close";
      details.hidden = isOpen;
    });

    releaseList.append(card);
  });
}

function renderEmpty(title, message, detail = "") {
  const latestEmpty = document.createElement("div");
  latestEmpty.className = "empty-state";
  latestEmpty.append(createTextElement("h3", title), createTextElement("p", message));
  if (detail) latestEmpty.append(createTextElement("div", detail, "error-note"));
  latestCard.append(latestEmpty);

  const archiveEmpty = document.createElement("div");
  archiveEmpty.className = "empty-state";
  archiveEmpty.append(
    createTextElement("h3", "The version archive is unavailable"),
    createTextElement("p", "No verified downloadable releases can be displayed."),
  );
  releaseList.append(archiveEmpty);
  releaseCount.textContent = "No verified versions";
}

function renderManifest(manifest, { staleAgeMs = 0 } = {}) {
  resetReleaseUi();
  const errors = validateManifest(manifest);
  if (errors.length) {
    renderEmpty(
      "Release information failed validation",
      "Downloads are disabled because VersionDeck could not verify its release manifest.",
      errors.join(" "),
    );
    announce("Release information failed validation. Downloads are disabled.");
    return false;
  }

  const latest = manifest.releases.find(
    (release) => release.id === manifest.latestStableReleaseId,
  );
  if (!latest) {
    renderEmpty(
      "No stable APK release is available yet",
      "VersionDeck is connected and waiting for a verified stable HomePilot release.",
    );
    announce("No verified stable release is available.");
    return true;
  }

  renderLatest(latest, manifest.productionSigner);
  renderArchive(manifest.releases, manifest.productionSigner, latest.id);

  if (staleAgeMs >= CACHE_FRESH_MS) {
    staleBanner.hidden = false;
    staleBannerText.textContent = `Release information could not be refreshed. Showing data saved ${
      Math.max(1, Math.round(staleAgeMs / 3_600_000))
    } hour(s) ago.`;
  }

  updateRelativeTimeElements();
  announce(staleAgeMs ? "Showing cached release information." : "Release information updated.");
  return true;
}

function saveCache(manifest) {
  try {
    localStorage.setItem(
      CACHE_KEY,
      JSON.stringify({ cachedAt: new Date().toISOString(), manifest }),
    );
  } catch {
    // Live data remains usable when storage is unavailable.
  }
}

function readCache() {
  try {
    const cached = JSON.parse(localStorage.getItem(CACHE_KEY));
    const cachedAt = Date.parse(cached?.cachedAt);
    if (!Number.isFinite(cachedAt) || !cached?.manifest) return null;
    return { manifest: cached.manifest, ageMs: Date.now() - cachedAt };
  } catch {
    return null;
  }
}

async function fetchManifest({ force = false } = {}) {
  activeRequestController?.abort();
  const controller = new AbortController();
  activeRequestController = controller;
  const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(`${MANIFEST_URL}${force ? `?refresh=${Date.now()}` : ""}`, {
      cache: force ? "reload" : "no-cache",
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`VersionDeck returned ${response.status}`);
    return await response.json();
  } finally {
    window.clearTimeout(timeout);
    if (activeRequestController === controller) activeRequestController = null;
  }
}

async function loadReleases({ force = false } = {}) {
  const generation = ++requestGeneration;
  refreshButton.classList.add("is-spinning");
  refreshButton.disabled = true;
  announce(force ? "Refreshing release information." : "Loading release information.");

  try {
    const manifest = await fetchManifest({ force });
    const errors = validateManifest(manifest);
    if (errors.length) throw new Error(errors.join(" "));
    saveCache(manifest);
    renderManifest(manifest);
  } catch (error) {
    if (generation !== requestGeneration) return;
    const cached = readCache();
    if (cached && cached.ageMs <= CACHE_MAX_MS) {
      renderManifest(cached.manifest, { staleAgeMs: cached.ageMs });
      showToast("Showing bounded cached release information");
    } else {
      resetReleaseUi();
      renderEmpty(
        "Release information is unavailable",
        "VersionDeck could not load verified release data. Try refreshing when your connection is available.",
        error.message,
      );
      announce("Release information is unavailable. Downloads are disabled.");
    }
  } finally {
    if (generation === requestGeneration) {
      refreshButton.classList.remove("is-spinning");
      refreshButton.disabled = false;
    }
  }
}

function startRelativeTimeTicker() {
  window.clearInterval(relativeTimeTimer);
  if (document.hidden) return;
  updateRelativeTimeElements();
  relativeTimeTimer = window.setInterval(() => updateRelativeTimeElements(), 60_000);
}

refreshButton.addEventListener("click", () => loadReleases({ force: true }));
document.addEventListener("visibilitychange", startRelativeTimeTicker);
window.addEventListener("pageshow", startRelativeTimeTicker);

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  installButtons.forEach((button) => { button.hidden = false; });
});

installButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    if (!deferredInstallPrompt) return;
    deferredInstallPrompt.prompt();
    await deferredInstallPrompt.userChoice;
    deferredInstallPrompt = null;
    installButtons.forEach((item) => { item.hidden = true; });
  });
});

window.addEventListener("appinstalled", () => showToast("VersionDeck installed"));

if ("serviceWorker" in navigator) {
  window.addEventListener("load", async () => {
    try {
      const registration = await navigator.serviceWorker.register("sw.js");
      const showUpdate = (worker) => {
        waitingServiceWorker = worker;
        updateNotice.hidden = false;
      };
      if (registration.waiting) showUpdate(registration.waiting);
      registration.addEventListener("updatefound", () => {
        const worker = registration.installing;
        worker?.addEventListener("statechange", () => {
          if (worker.state === "installed" && navigator.serviceWorker.controller) {
            showUpdate(worker);
          }
        });
      });
      navigator.serviceWorker.addEventListener("controllerchange", () => window.location.reload());
    } catch {
      // VersionDeck remains functional without offline shell support.
    }
  });
}

updateButton.addEventListener("click", () => {
  waitingServiceWorker?.postMessage({ type: "SKIP_WAITING" });
});

startRelativeTimeTicker();
loadReleases();
