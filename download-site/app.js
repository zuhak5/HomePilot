(() => {
  "use strict";

  const REPOSITORY = "zuhak5/HomePilot";
  const RELEASES_ENDPOINT =
    `https://api.github.com/repos/${REPOSITORY}/releases?per_page=100`;
  const CACHE_KEY = "versiondeck-release-cache-v2";

  const numberFormat = new Intl.NumberFormat();
  const dateFormat = new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });

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

  let deferredInstallPrompt = null;
  let toastTimer = null;

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "Unknown size";

    const units = ["B", "KB", "MB", "GB"];
    const index = Math.min(
      Math.floor(Math.log(bytes) / Math.log(1024)),
      units.length - 1,
    );
    const value = bytes / 1024 ** index;

    return `${value.toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
  }

  function formatDate(value) {
    const date = new Date(value);
    return Number.isNaN(date.getTime())
      ? "Unknown date"
      : dateFormat.format(date);
  }

  function selectApk(release) {
    return release.assets?.find(
      (asset) => asset.name.toLowerCase().endsWith(".apk"),
    ) ?? null;
  }

  function selectChecksum(release) {
    return release.assets?.find(
      (asset) => asset.name.toLowerCase().endsWith(".sha256"),
    ) ?? null;
  }

  function extractVersion(release) {
    const fromName = release.name?.match(/HomePilot\s+([^\s(]+)/i)?.[1];
    if (fromName) return fromName;

    return release.tag_name
      ?.replace(/^v/i, "")
      .replace(/-build\.\d+$/i, "") || "Unknown";
  }

  function extractBuild(release) {
    return release.tag_name?.match(/build[.-](\d+)/i)?.[1] || "—";
  }

  function extractSha(release) {
    return (release.body || "")
      .match(/SHA-256:\s*`?([a-f\d]{64})`?/i)?.[1]
      ?.toLowerCase() || "";
  }

  function changelogBody(release) {
    return (release.body || "")
      .replace(/##\s*Build details[\s\S]*/i, "")
      .replace(/##\s*What's changed/i, "")
      .trim();
  }

  function releaseSummary(release) {
    const body = changelogBody(release);

    if (!body) {
      return "Signed production build of HomePilot for Android.";
    }

    return body
      .split(/\r?\n/)
      .map((line) => line.replace(/^[-*#\s]+/, "").trim())
      .filter(Boolean)
      .slice(0, 2)
      .join(" ")
      .slice(0, 220);
  }

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add("visible");
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(
      () => toast.classList.remove("visible"),
      2400,
    );
  }

  async function copyText(text, successMessage) {
    try {
      await navigator.clipboard.writeText(text);
      showToast(successMessage);
    } catch {
      showToast("Copy failed. Select the value manually.");
    }
  }

  function createLink(label, href) {
    const link = document.createElement("a");
    link.textContent = label;
    link.href = href;
    link.target = "_blank";
    link.rel = "noreferrer";
    return link;
  }

  function renderMarkdown(container, markdown) {
    container.replaceChildren();

    const source = (markdown || "No changelog was supplied.")
      .replace(/##\s*Build details[\s\S]*/i, "")
      .replace(/##\s*What's changed/i, "")
      .trim();

    const lines = source.split(/\r?\n/);
    let list = null;

    function appendInline(element, value) {
      const chunks = value.split(/(`[^`]+`)/g).filter(Boolean);

      for (const chunk of chunks) {
        if (chunk.startsWith("`") && chunk.endsWith("`")) {
          const code = document.createElement("code");
          code.textContent = chunk.slice(1, -1);
          element.append(code);
        } else {
          element.append(document.createTextNode(chunk));
        }
      }
    }

    for (const rawLine of lines) {
      const line = rawLine.trim();

      if (!line) {
        list = null;
        continue;
      }

      const heading = line.match(/^#{1,4}\s+(.+)/);
      if (heading) {
        const element = document.createElement("h4");
        element.textContent = heading[1];
        container.append(element);
        list = null;
        continue;
      }

      const bullet = line.match(/^[-*]\s+(.+)/);
      if (bullet) {
        if (!list) {
          list = document.createElement("ul");
          container.append(list);
        }

        const item = document.createElement("li");
        appendInline(item, bullet[1]);
        list.append(item);
        continue;
      }

      const paragraph = document.createElement("p");
      appendInline(paragraph, line);
      container.append(paragraph);
      list = null;
    }
  }

  function addFact(list, label, value) {
    const wrapper = document.createElement("div");
    const term = document.createElement("dt");
    const detail = document.createElement("dd");

    term.textContent = label;
    detail.textContent = value;
    wrapper.append(term, detail);
    list.append(wrapper);
  }

  function renderLatest(release) {
    const apk = selectApk(release);
    const checksumAsset = selectChecksum(release);
    const version = extractVersion(release);
    const build = extractBuild(release);
    const sha = extractSha(release);

    latestCard.classList.remove("loading-card");
    latestCard.setAttribute("aria-busy", "false");
    latestCard.replaceChildren();

    const layout = document.createElement("div");
    layout.className = "latest-layout";

    const content = document.createElement("div");

    const status = document.createElement("div");
    status.className = "latest-status";

    const pill = document.createElement("span");
    pill.className = "status-pill";
    pill.textContent = release.prerelease ? "Pre-release" : "Latest stable";

    const date = document.createElement("span");
    date.className = "latest-date";
    date.textContent = `Published ${formatDate(release.published_at)}`;

    status.append(pill, date);

    const title = document.createElement("h3");
    title.className = "latest-title";
    title.textContent = `HomePilot ${version}`;

    const summary = document.createElement("p");
    summary.className = "latest-summary";
    summary.textContent = releaseSummary(release);

    const facts = document.createElement("dl");
    facts.className = "fact-list";
    addFact(facts, "Build", build);
    addFact(facts, "APK size", apk ? formatBytes(apk.size) : "Not attached");
    addFact(
      facts,
      "Downloads",
      apk ? numberFormat.format(apk.download_count || 0) : "—",
    );

    content.append(status, title, summary, facts);

    if (sha) {
      const checksum = document.createElement("div");
      checksum.className = "checksum";

      const code = document.createElement("code");
      code.textContent = `SHA-256 ${sha}`;
      code.title = sha;

      const copy = document.createElement("button");
      copy.className = "copy-button";
      copy.type = "button";
      copy.textContent = "Copy";
      copy.addEventListener(
        "click",
        () => copyText(sha, "SHA-256 copied"),
      );

      checksum.append(code, copy);
      content.append(checksum);
    }

    const actions = document.createElement("div");
    actions.className = "latest-actions";

    if (apk) {
      const download = document.createElement("a");
      download.className = "button button-primary";
      download.textContent = "Download latest APK";
      download.href = apk.browser_download_url;
      actions.append(download);
    } else {
      const unavailable = document.createElement("button");
      unavailable.className = "button button-primary";
      unavailable.type = "button";
      unavailable.disabled = true;
      unavailable.textContent = "APK unavailable";
      actions.append(unavailable);
    }

    const notes = document.createElement("a");
    notes.className = "button button-secondary";
    notes.textContent = "Release notes";
    notes.href = release.html_url;
    notes.target = "_blank";
    notes.rel = "noreferrer";
    actions.append(notes);

    if (checksumAsset) {
      const checksumLink = document.createElement("a");
      checksumLink.className = "button button-secondary";
      checksumLink.textContent = "Checksum file";
      checksumLink.href = checksumAsset.browser_download_url;
      checksumLink.target = "_blank";
      checksumLink.rel = "noreferrer";
      actions.append(checksumLink);
    }

    layout.append(content, actions);
    latestCard.append(layout);

    if (apk) {
      stickyVersion.textContent = `HomePilot ${version}`;
      stickyDownloadLink.href = apk.browser_download_url;
      stickyDownload.hidden = false;
      document.body.classList.add("has-sticky-download");
    }
  }

  function renderReleaseList(releases) {
    releaseList.replaceChildren();
    releaseCount.textContent =
      `${numberFormat.format(releases.length)} ${
        releases.length === 1 ? "version" : "versions"
      }`;

    releases.forEach((release, index) => {
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

      const apk = selectApk(release);
      const checksumAsset = selectChecksum(release);
      const version = extractVersion(release);
      const build = extractBuild(release);
      const sha = extractSha(release);

      title.textContent = `HomePilot ${version}`;

      if (index === 0) {
        label.textContent = "Latest";
      } else if (release.prerelease) {
        label.textContent = "Pre-release";
      }

      const metadata = [
        `Build ${build}`,
        formatDate(release.published_at),
      ];

      if (apk) {
        metadata.push(
          formatBytes(apk.size),
          `${numberFormat.format(apk.download_count || 0)} downloads`,
        );
      }

      meta.textContent = metadata.join(" · ");

      if (apk) {
        download.href = apk.browser_download_url;
      } else {
        download.remove();
      }

      renderMarkdown(changelog, release.body);
      links.append(createLink("GitHub release", release.html_url));

      if (checksumAsset) {
        links.append(
          createLink("Checksum file", checksumAsset.browser_download_url),
        );
      }

      if (sha) {
        const copy = document.createElement("button");
        copy.type = "button";
        copy.textContent = "Copy SHA-256";
        copy.addEventListener(
          "click",
          () => copyText(sha, "SHA-256 copied"),
        );
        links.append(copy);
      }

      toggle.addEventListener("click", () => {
        const isOpen = toggle.getAttribute("aria-expanded") === "true";
        toggle.setAttribute("aria-expanded", String(!isOpen));
        toggle.textContent = isOpen ? "Changes" : "Close";
        details.hidden = isOpen;
      });

      releaseList.append(card);
    });
  }

  function renderEmpty(message, detail = "") {
    latestCard.classList.remove("loading-card");
    latestCard.setAttribute("aria-busy", "false");
    latestCard.replaceChildren();

    const latestEmpty = document.createElement("div");
    latestEmpty.className = "empty-state";

    const latestTitle = document.createElement("h3");
    latestTitle.textContent = "No APK release is available yet";

    const latestMessage = document.createElement("p");
    latestMessage.textContent = message;

    latestEmpty.append(latestTitle, latestMessage);

    if (detail) {
      const error = document.createElement("div");
      error.className = "error-note";
      error.textContent = detail;
      latestEmpty.append(error);
    }

    latestCard.append(latestEmpty);

    releaseList.replaceChildren();
    const archiveEmpty = document.createElement("div");
    archiveEmpty.className = "empty-state";

    const archiveTitle = document.createElement("h3");
    archiveTitle.textContent = "The version archive is empty";

    const archiveMessage = document.createElement("p");
    archiveMessage.textContent =
      "Publish a signed APK through the production workflow.";

    archiveEmpty.append(archiveTitle, archiveMessage);
    releaseList.append(archiveEmpty);
    releaseCount.textContent = "No versions";
  }

  function saveCache(releases) {
    try {
      localStorage.setItem(
        CACHE_KEY,
        JSON.stringify({ savedAt: Date.now(), releases }),
      );
    } catch {
      // The live feed remains available when storage is disabled.
    }
  }

  function readCache() {
    try {
      const cached = JSON.parse(localStorage.getItem(CACHE_KEY));
      return Array.isArray(cached?.releases) ? cached.releases : null;
    } catch {
      return null;
    }
  }

  async function loadReleases({ force = false } = {}) {
    refreshButton.classList.add("is-spinning");
    refreshButton.disabled = true;

    try {
      const response = await fetch(RELEASES_ENDPOINT, {
        cache: force ? "reload" : "no-store",
        headers: { Accept: "application/vnd.github+json" },
      });

      if (!response.ok) {
        throw new Error(`GitHub returned ${response.status}`);
      }

      const releases = (await response.json())
        .filter((release) => !release.draft);

      saveCache(releases);

      if (!releases.length) {
        renderEmpty(
          "VersionDeck is connected and waiting for its first release.",
        );
        return;
      }

      renderLatest(releases[0]);
      renderReleaseList(releases);
    } catch (error) {
      const cached = readCache();

      if (cached?.length) {
        renderLatest(cached[0]);
        renderReleaseList(cached);
        showToast("Showing cached release information");
      } else {
        renderEmpty(
          "Release information could not be loaded.",
          error.message,
        );
      }
    } finally {
      refreshButton.classList.remove("is-spinning");
      refreshButton.disabled = false;
    }
  }

  refreshButton.addEventListener(
    "click",
    () => loadReleases({ force: true }),
  );

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    deferredInstallPrompt = event;
    installButtons.forEach((button) => {
      button.hidden = false;
    });
  });

  installButtons.forEach((button) => {
    button.addEventListener("click", async () => {
      if (!deferredInstallPrompt) return;

      deferredInstallPrompt.prompt();
      await deferredInstallPrompt.userChoice;
      deferredInstallPrompt = null;

      installButtons.forEach((item) => {
        item.hidden = true;
      });
    });
  });

  window.addEventListener(
    "appinstalled",
    () => showToast("VersionDeck installed"),
  );

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("sw.js").catch(() => {
        // The download page remains functional without offline support.
      });
    });
  }

  loadReleases();
})();
