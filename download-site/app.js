import {
  createRelativeTimeElement,
  formatExactDateTime,
  updateRelativeTimeElements,
} from "./relative-time.js";
import {
  VERSIONDECK_REPOSITORY,
  validateVersionDeckManifest,
} from "./manifest-schema.js";
import {
  RELEASE_CACHE_SCHEMA_VERSION,
  ReleaseCacheState,
  classifyReleaseCache,
} from "./cache-policy.js";

const MANIFEST_URL = "./releases.json";
const CACHE_KEY = "versiondeck-release-manifest-v4";
const LEGACY_CACHE_KEYS = [1, 2, 3].map((version) =>
  `versiondeck-release-manifest-v${version}`);
const REQUEST_TIMEOUT_MS = 12_000;
const numberFormat = new Intl.NumberFormat();

function q(selector) {
  const node = document.querySelector(selector);
  if (!node) throw new Error(`Missing VersionDeck element: ${selector}`);
  return node;
}

function el(tag, text = "", className = "") {
  const node = document.createElement(tag);
  node.textContent = text;
  if (className) node.className = className;
  return node;
}

const ui = {
  latest: q("#latest-card"),
  list: q("#release-list"),
  count: q("#release-count"),
  template: q("#release-template"),
  refresh: q("#refresh-button"),
  sticky: q("#sticky-download"),
  stickyVersion: q("#sticky-version"),
  stickyLink: q("#sticky-download-link"),
  toast: q("#toast"),
  status: q("#release-status"),
  cacheBanner: q("#stale-banner"),
  cacheText: q("#stale-banner-text"),
  updateNotice: q("#update-notice"),
  updateButton: q("#update-button"),
};

let deferredInstallPrompt = null;
let waitingWorker = null;
let activeController = null;
let generation = 0;
let toastTimer = null;
let relativeTimer = null;
let controllerReloaded = false;

function announce(message) {
  ui.status.textContent = "";
  requestAnimationFrame(() => { ui.status.textContent = message; });
}

function toast(message) {
  ui.toast.textContent = message;
  ui.toast.classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => ui.toast.classList.remove("visible"), 2600);
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 1) return "Unknown size";
  const units = ["B", "KB", "MB", "GB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), 3);
  return `${(bytes / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`;
}

function controlledLink(label, href, className = "", external = false) {
  const link = el("a", label, className);
  link.dataset.downloadLink = "true";
  link.dataset.downloadHref = href;
  link.href = href;
  if (external) {
    link.target = "_blank";
    link.rel = "noopener noreferrer";
  }
  return link;
}

function externalLink(label, href, className = "") {
  const link = el("a", label, className);
  link.href = href;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  return link;
}

function setDownloadsEnabled(enabled) {
  document.querySelectorAll("[data-download-link]").forEach((link) => {
    if (enabled && link.dataset.downloadHref) {
      link.href = link.dataset.downloadHref;
      link.removeAttribute("aria-disabled");
      link.removeAttribute("tabindex");
      link.removeAttribute("title");
    } else {
      link.removeAttribute("href");
      link.setAttribute("aria-disabled", "true");
      link.setAttribute("tabindex", "-1");
      link.title = "Reconnect and refresh verified release data before downloading.";
    }
  });
  if (!enabled) {
    ui.sticky.hidden = true;
    document.body.classList.remove("has-sticky-download");
  }
}

async function copyValue(button, value, message) {
  try {
    await navigator.clipboard.writeText(value);
    const original = button.textContent;
    button.textContent = "Copied";
    setTimeout(() => { button.textContent = original; }, 1400);
    toast(message);
  } catch {
    toast("Copy failed. Select the value from the verification details.");
  }
}

function copyRow(label, value, context) {
  const row = el("div", "", "verification-row");
  const content = el("div");
  content.append(
    el("span", label, "verification-label"),
    el("code", value, "verification-value"),
  );
  const button = el("button", "Copy", "copy-button");
  button.type = "button";
  button.setAttribute("aria-label", `Copy ${label} for ${context}`);
  button.addEventListener("click", () => copyValue(button, value, `${label} copied`));
  row.append(content, button);
  return row;
}

function verificationPanel(release) {
  const details = el("details", "", "verification-details");
  details.append(
    el("summary", "Verified release details"),
    el(
      "p",
      "VersionDeck independently checked the APK hash, package identity, production signer, release commit, and GitHub provenance attestation.",
      "verification-explanation",
    ),
  );
  const checks = el("ul", "", "verification-checks");
  [
    "APK hash matches GitHub and the checksum asset",
    "Package, version, and build match the release",
    "Production signing certificate matches",
    "Release commit is contained in main",
    "GitHub build-provenance attestation verifies",
  ].forEach((text) => checks.append(el("li", text)));
  details.append(checks);

  const context = `HomePilot ${release.version}`;
  details.append(
    copyRow("APK SHA-256", release.apk.sha256, context),
    copyRow("Signer certificate SHA-256", release.verification.signerCertificateSha256, context),
    copyRow("Release commit", release.commitSha, context),
  );
  const commands = el("div", "", "verification-commands");
  commands.append(el("strong", "Independent verification commands"));
  [
    `Get-FileHash .\\${release.apk.name} -Algorithm SHA256`,
    `sha256sum ${release.apk.name}`,
    `shasum -a 256 ${release.apk.name}`,
    `gh attestation verify ${release.apk.name} --repo ${VERSIONDECK_REPOSITORY}`,
  ].forEach((command) => commands.append(el("pre", command)));
  details.append(commands);
  return details;
}

function addFact(list, label, value) {
  const wrapper = el("div");
  wrapper.append(el("dt", label), el("dd", value));
  list.append(wrapper);
}

function renderLatest(release) {
  const layout = el("div", "", "latest-layout");
  const content = el("div");
  const status = el("div", "", "latest-status");
  status.append(
    el("span", "Latest stable", "status-pill status-stable"),
    createRelativeTimeElement(release.publishedAt, {
      prefix: "Published ",
      className: "latest-date",
    }),
  );
  const facts = el("dl", "", "fact-list");
  addFact(facts, "Build", numberFormat.format(release.build));
  addFact(facts, "APK size", formatBytes(release.apk.size));
  addFact(facts, "Downloads", numberFormat.format(release.apk.downloadCount));

  const checksum = el("div", "", "checksum");
  const code = el("code", `SHA-256 ${release.apk.sha256}`);
  code.title = release.apk.sha256;
  const copy = el("button", "Copy", "copy-button");
  copy.type = "button";
  copy.addEventListener("click", () => copyValue(copy, release.apk.sha256, "APK SHA-256 copied"));
  checksum.append(code, copy);

  content.append(
    status,
    el("h3", `HomePilot ${release.version}`, "latest-title"),
    el("p", release.summary, "latest-summary"),
    facts,
    checksum,
    el("p", `Exact publication time: ${formatExactDateTime(release.publishedAt)}`, "exact-date"),
    verificationPanel(release),
  );
  const actions = el("div", "", "latest-actions");
  actions.append(
    controlledLink("Download verified APK", release.apk.url, "button button-primary"),
    externalLink("Release notes", release.releaseUrl, "button button-secondary"),
    controlledLink("Checksum file", release.checksum.url, "button button-secondary", true),
  );
  layout.append(content, actions);
  ui.latest.append(layout);

  ui.stickyVersion.textContent = `HomePilot ${release.version}`;
  ui.stickyLink.dataset.downloadLink = "true";
  ui.stickyLink.dataset.downloadHref = release.apk.url;
  ui.stickyLink.href = release.apk.url;
  ui.sticky.hidden = false;
  document.body.classList.add("has-sticky-download");
}

function renderLatestEmpty(hasPrereleases) {
  const state = el("div", "", "empty-state");
  state.append(
    el("h3", "No verified stable release is available yet"),
    el("p", hasPrereleases
      ? "Verified prereleases are listed below, but VersionDeck does not present them as stable downloads."
      : "VersionDeck is waiting for the first verified stable HomePilot release."),
  );
  ui.latest.append(state);
}

function renderArchive(releases, latestStableId) {
  ui.count.textContent = `${numberFormat.format(releases.length)} ${
    releases.length === 1 ? "version" : "versions"}`;
  if (!releases.length) {
    const state = el("div", "", "empty-state");
    state.append(
      el("h3", "No verified versions are available"),
      el("p", "Published APKs appear here only after all verification gates pass."),
    );
    ui.list.append(state);
    return;
  }

  releases.forEach((release) => {
    const fragment = ui.template.content.cloneNode(true);
    const get = (selector) => {
      const node = fragment.querySelector(selector);
      if (!node) throw new Error(`Incomplete release template: ${selector}`);
      return node;
    };
    const card = get(".release-card");
    const title = get(".release-title");
    const label = get(".release-label");
    const meta = get(".release-meta");
    const download = get(".archive-download");
    const toggle = get(".details-toggle");
    const details = get(".release-details");
    const changelog = get(".changelog");
    const links = get(".release-links");
    const exactDate = get(".archive-exact-date");
    const verification = get(".archive-verification");

    details.id = `release-details-${release.id}`;
    toggle.setAttribute("aria-controls", details.id);
    title.textContent = `HomePilot ${release.version}`;
    if (release.id === latestStableId) {
      label.textContent = "Latest stable";
      label.classList.add("status-stable");
    } else if (release.prerelease) {
      label.textContent = "Pre-release";
      label.classList.add("status-prerelease");
    }

    const parts = [
      `Build ${numberFormat.format(release.build)}`,
      createRelativeTimeElement(release.publishedAt),
      formatBytes(release.apk.size),
      `${numberFormat.format(release.apk.downloadCount)} downloads`,
    ];
    parts.forEach((part, index) => {
      if (index) meta.append(document.createTextNode(" · "));
      meta.append(typeof part === "string" ? document.createTextNode(part) : part);
    });

    download.dataset.downloadLink = "true";
    download.dataset.downloadHref = release.apk.url;
    download.href = release.apk.url;
    download.textContent = release.prerelease ? "Download prerelease" : "Download";
    exactDate.textContent = `Published ${formatExactDateTime(release.publishedAt)}`;
    if (release.changelog.length) {
      const list = el("ul");
      release.changelog.forEach((item) => list.append(el("li", item)));
      changelog.append(list);
    } else {
      changelog.append(el("p", "No changelog was supplied."));
    }
    links.append(
      externalLink("GitHub release", release.releaseUrl),
      controlledLink("Checksum file", release.checksum.url, "", true),
    );
    const hashCopy = el("button", "Copy SHA-256");
    hashCopy.type = "button";
    hashCopy.addEventListener("click", () =>
      copyValue(hashCopy, release.apk.sha256, "APK SHA-256 copied"));
    links.append(hashCopy);
    verification.append(verificationPanel(release));

    toggle.addEventListener("click", () => {
      const open = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!open));
      toggle.textContent = open ? "Show changes" : "Hide changes";
      details.hidden = open;
    });
    ui.list.append(card);
  });
}

function resetUi() {
  ui.latest.classList.remove("loading-card");
  ui.latest.setAttribute("aria-busy", "false");
  ui.latest.replaceChildren();
  ui.list.replaceChildren();
  ui.count.textContent = "";
  ui.cacheBanner.hidden = true;
  ui.sticky.hidden = true;
  ui.stickyLink.removeAttribute("href");
  ui.stickyLink.removeAttribute("data-download-link");
  ui.stickyLink.removeAttribute("data-download-href");
  document.body.classList.remove("has-sticky-download");
}

function renderFailure(reference) {
  resetUi();
  const latest = el("div", "", "empty-state");
  latest.append(
    el("h3", "Release information is unavailable"),
    el("p", "VersionDeck could not load verified release data. Downloads are disabled."),
    el("div", `Reference: ${reference}`, "error-note"),
  );
  ui.latest.append(latest);
  const archive = el("div", "", "empty-state");
  archive.append(el("h3", "The verified version archive is unavailable"));
  ui.list.append(archive);
  ui.count.textContent = "Unavailable";
}

function cacheBanner(state, ageMs) {
  ui.cacheBanner.hidden = false;
  const hours = Math.max(1, Math.round(ageMs / 3_600_000));
  const age = `${numberFormat.format(hours)} hour${hours === 1 ? "" : "s"}`;
  ui.cacheText.textContent = state === ReleaseCacheState.EXPIRED
    ? `Saved data is ${age} old. Downloads are disabled until VersionDeck reconnects.`
    : `VersionDeck is offline. Showing verified data saved ${age} ago.`;
}

function renderManifest(manifest, source = { kind: "live" }) {
  const errors = validateVersionDeckManifest(manifest);
  if (errors.length) {
    console.error("VersionDeck manifest validation failed", errors);
    renderFailure("VD-MANIFEST-001");
    announce("Release validation failed. Downloads are disabled.");
    return false;
  }

  resetUi();
  const latest = manifest.releases.find((release) =>
    release.id === manifest.latestStableReleaseId);
  if (latest) renderLatest(latest);
  else renderLatestEmpty(manifest.releases.some((release) => release.prerelease));
  renderArchive(manifest.releases, manifest.latestStableReleaseId);

  const expired = source.state === ReleaseCacheState.EXPIRED;
  if (source.kind === "cache") cacheBanner(source.state, source.ageMs);
  setDownloadsEnabled(!expired);
  updateRelativeTimeElements();
  announce(expired
    ? "Cached release data expired. Downloads are disabled."
    : source.kind === "cache"
      ? "Showing bounded cached release data."
      : "Verified release information updated.");
  return true;
}

function saveCache(manifest) {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify({
      schemaVersion: RELEASE_CACHE_SCHEMA_VERSION,
      fetchedAt: new Date().toISOString(),
      manifest,
    }));
    LEGACY_CACHE_KEYS.forEach((key) => localStorage.removeItem(key));
  } catch {
    // Live verified data remains usable when storage is blocked.
  }
}

function removeCache() {
  try { localStorage.removeItem(CACHE_KEY); } catch { /* Storage may be blocked. */ }
}

function readCache() {
  try {
    const record = JSON.parse(localStorage.getItem(CACHE_KEY));
    const policy = classifyReleaseCache(record);
    if (
      policy.state === ReleaseCacheState.INVALID ||
      validateVersionDeckManifest(record?.manifest).length
    ) {
      removeCache();
      return null;
    }
    return { record, policy };
  } catch {
    removeCache();
    return null;
  }
}

async function fetchManifest(force) {
  activeController?.abort();
  const controller = new AbortController();
  activeController = controller;
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(MANIFEST_URL, {
      cache: force ? "reload" : "no-cache",
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const manifest = await response.json();
    if (validateVersionDeckManifest(manifest).length) throw new Error("Manifest validation failed");
    return manifest;
  } finally {
    clearTimeout(timeout);
    if (activeController === controller) activeController = null;
  }
}

async function loadReleases(force = false) {
  const request = ++generation;
  ui.refresh.classList.add("is-spinning");
  ui.refresh.disabled = true;
  announce(force ? "Refreshing verified releases." : "Loading verified releases.");
  try {
    const manifest = await fetchManifest(force);
    if (request !== generation) return;
    saveCache(manifest);
    renderManifest(manifest);
  } catch (error) {
    if (request !== generation) return;
    console.error("VersionDeck release load failed", error);
    const cached = readCache();
    if (cached) {
      renderManifest(cached.record.manifest, {
        kind: "cache",
        state: cached.policy.state,
        ageMs: cached.policy.ageMs,
      });
      toast(cached.policy.state === ReleaseCacheState.EXPIRED
        ? "Cached release data expired"
        : "Showing bounded cached release data");
    } else {
      renderFailure("VD-NETWORK-001");
      announce("Release information is unavailable. Downloads are disabled.");
    }
  } finally {
    if (request === generation) {
      ui.refresh.classList.remove("is-spinning");
      ui.refresh.disabled = false;
    }
  }
}

function startRelativeTicker() {
  clearInterval(relativeTimer);
  if (document.hidden) return;
  updateRelativeTimeElements();
  relativeTimer = setInterval(updateRelativeTimeElements, 60_000);
}

ui.refresh.addEventListener("click", () => loadReleases(true));
document.addEventListener("visibilitychange", startRelativeTicker);
window.addEventListener("pageshow", startRelativeTicker);

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  document.querySelectorAll(".install-button").forEach((button) => { button.hidden = false; });
});
document.querySelectorAll(".install-button").forEach((button) => {
  button.addEventListener("click", async () => {
    if (!deferredInstallPrompt) return;
    deferredInstallPrompt.prompt();
    await deferredInstallPrompt.userChoice;
    deferredInstallPrompt = null;
    document.querySelectorAll(".install-button").forEach((item) => { item.hidden = true; });
  });
});
window.addEventListener("appinstalled", () => toast("VersionDeck installed"));

if ("serviceWorker" in navigator) {
  window.addEventListener("load", async () => {
    try {
      const registration = await navigator.serviceWorker.register("sw.js");
      const showUpdate = (worker) => {
        waitingWorker = worker;
        ui.updateNotice.hidden = false;
      };
      if (registration.waiting) showUpdate(registration.waiting);
      registration.addEventListener("updatefound", () => {
        const worker = registration.installing;
        worker?.addEventListener("statechange", () => {
          if (worker.state === "installed" && navigator.serviceWorker.controller) showUpdate(worker);
        });
      });
      navigator.serviceWorker.addEventListener("controllerchange", () => {
        if (controllerReloaded) return;
        controllerReloaded = true;
        location.reload();
      });
    } catch (error) {
      console.warn("VersionDeck service worker registration failed", error);
    }
  });
}
ui.updateButton.addEventListener("click", () => {
  if (!waitingWorker) return;
  ui.updateButton.disabled = true;
  ui.updateButton.textContent = "Updating…";
  waitingWorker.postMessage({ type: "SKIP_WAITING" });
});

startRelativeTicker();
loadReleases();
