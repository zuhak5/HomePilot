(() => {
  "use strict";

  const REPOSITORY = "zuhak5/HomePilot";
  const RELEASES_ENDPOINT = `https://api.github.com/repos/${REPOSITORY}/releases?per_page=100`;
  const CACHE_KEY = "homepilot-release-cache-v1";
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
    const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const value = bytes / 1024 ** index;
    return `${value.toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
  }

  function formatDate(value) {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "Unknown date" : dateFormat.format(date);
  }

  function selectApk(release) {
    return release.assets?.find((asset) => asset.name.toLowerCase().endsWith(".apk")) ?? null;
  }

  function selectChecksum(release) {
    return release.assets?.find((asset) => asset.name.toLowerCase().endsWith(".sha256")) ?? null;
  }

  function extractVersion(release) {
    const fromName = release.name?.match(/HomePilot\s+([^\s(]+)/i)?.[1];
    if (fromName) return fromName;
    return release.tag_name?.replace(/^v/i, "").replace(/-build\.\d+$/i, "") || "Unknown";
  }

  function extractBuild(release) {
    return release.tag_name?.match(/build[.-](\d+)/i)?.[1] || "—";
  }

  function extractSha(release) {
    const body = release.body || "";
    return body.match(/SHA-256:\s*`?([a-f\d]{64})`?/i)?.[1]?.toLowerCase() || "";
  }

  function releaseSummary(release) {
    const body = (release.body || "").replace(/##\s*Build details[\s\S]*/i, "").replace(/##\s*What's changed/i, "").trim();
    if (!body) return "A signed production build of HomePilot for Android.";
    return body
      .split(/\r?\n/)
      .map((line) => line.replace(/^[-*#\s]+/, "").trim())
      .filter(Boolean)
      .slice(0, 2)
      .join(" ")
      .slice(0, 240);
  }

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add("visible");
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toast.classList.remove("visible"), 2400);
  }

  async function copyText(text, successMessage) {
    try {
      await navigator.clipboard.writeText(text);
      showToast(successMessage);
    } catch {
      showToast("Copy failed. Select the value manually.");
    }
  }

  function createButton(label, href, className = "button button-small button-ghost") {
    const link = document.createElement("a");
    link.className = className;
    link.textContent = label;
    link.href = href;
    link.target = href.startsWith("http") ? "_blank" : "_self";
    if (link.target === "_blank") link.rel = "noreferrer";
    return link;
  }

  function renderMarkdown(container, markdown) {
    container.replaceChildren();
    const source = (markdown || "No changelog was supplied for this release.")
      .replace(/##\s*Build details[\s\S]*/i, "")
      .replace(/##\s*What's changed/i, "")
      .trim();

    const lines = source.split(/\r?\n/);
    let list = null;

    const appendInlineText = (element, value) => {
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
    };

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
        appendInlineText(item, bullet[1]);
        list.append(item);
        continue;
      }

      const paragraph = document.createElement("p");
      appendInlineText(paragraph, line);
      container.append(paragraph);
      list = null;
    }
  }

  function renderLatest(release) {
    const apk = selectApk(release);
    const checksum = selectChecksum(release);
    const version = extractVersion(release);
    const build = extractBuild(release);
    const sha = extractSha(release);
    const latestLabel = release.prerelease ? "Pre-release" : "Latest stable";

    latestCard.classList.remove("loading-card");
    latestCard.setAttribute("aria-busy", "false");
    latestCard.replaceChildren();

    const layout = document.createElement("div");
    layout.className = "latest-layout";

    const details = document.createElement("div");
    const versionRow = document.createElement("div");
    versionRow.className = "latest-version-row";
    const versionPill = document.createElement("span");
    versionPill.className = "version-pill";
    versionPill.textContent = latestLabel;
    const published = document.createElement("span");
    published.className = "release-meta";
    published.textContent = `Published ${formatDate(release.published_at)}`;
    versionRow.append(versionPill, published);

    const title = document.createElement("h3");
    title.className = "latest-title";
    title.textContent = `HomePilot ${version}`;

    const summary = document.createElement("p");
    summary.className = "latest-copy";
    summary.textContent = releaseSummary(release);

    const facts = document.createElement("ul");
    facts.className = "release-facts";
    const factValues = [
      ["Build", build],
      ["APK size", apk ? formatBytes(apk.size) : "Not attached"],
      ["Downloads", apk ? numberFormat.format(apk.download_count || 0) : "—"],
    ];
    for (const [label, value] of factValues) {
      const item = document.createElement("li");
      const small = document.createElement("small");
      const strong = document.createElement("strong");
      small.textContent = label;
      strong.textContent = value;
      item.append(small, strong);
      facts.append(item);
    }

    details.append(versionRow, title, summary, facts);

    if (sha) {
      const checksumRow = document.createElement("div");
      checksumRow.className = "checksum-row";
      const code = document.createElement("code");
      code.textContent = `SHA-256 ${sha}`;
      code.title = sha;
      const copyButton = document.createElement("button");
      copyButton.className = "copy-button";
      copyButton.type = "button";
      copyButton.textContent = "Copy";
      copyButton.addEventListener("click", () => copyText(sha, "SHA-256 copied"));
      checksumRow.append(code, copyButton);
      details.append(checksumRow);
    }

    const actions = document.createElement("div");
    actions.className = "latest-actions";
    if (apk) {
      const download = createButton("Download signed APK", apk.browser_download_url, "button button-primary");
      download.removeAttribute("target");
      download.removeAttribute("rel");
      actions.append(download);
    } else {
      const unavailable = document.createElement("button");
      unavailable.className = "button button-primary";
      unavailable.disabled = true;
      unavailable.textContent = "APK unavailable";
      actions.append(unavailable);
    }
    actions.append(createButton("Release notes", release.html_url));
    if (checksum) actions.append(createButton("Checksum file", checksum.browser_download_url));

    layout.append(details, actions);
    latestCard.append(layout);

    if (apk) {
      stickyVersion.textContent = `HomePilot ${version}`;
      stickyDownloadLink.href = apk.browser_download_url;
      stickyDownloadLink.removeAttribute("target");
      stickyDownload.hidden = false;
      document.body.classList.add("has-sticky-download");
    }
  }

  function renderReleaseList(releases) {
    releaseList.replaceChildren();
    releaseCount.textContent = `${numberFormat.format(releases.length)} published ${releases.length === 1 ? "release" : "releases"}`;

    releases.forEach((release, index) => {
      const fragment = releaseTemplate.content.cloneNode(true);
      const card = fragment.querySelector(".release-card");
      const title = fragment.querySelector(".release-title");
      const label = fragment.querySelector(".release-label");
      const meta = fragment.querySelector(".release-meta");
      const toggle = fragment.querySelector(".details-toggle");
      const details = fragment.querySelector(".release-details");
      const changelog = fragment.querySelector(".changelog");
      const actions = fragment.querySelector(".release-actions");

      const apk = selectApk(release);
      const checksum = selectChecksum(release);
      const version = extractVersion(release);
      const build = extractBuild(release);
      const sha = extractSha(release);

      title.textContent = `HomePilot ${version}`;
      if (index === 0) {
        label.textContent = "Latest";
      } else if (release.prerelease) {
        label.textContent = "Pre-release";
      } else {
        label.remove();
      }

      const metaParts = [`Build ${build}`, formatDate(release.published_at)];
      if (apk) metaParts.push(formatBytes(apk.size), `${numberFormat.format(apk.download_count || 0)} downloads`);
      meta.textContent = metaParts.join(" · ");
      renderMarkdown(changelog, release.body);

      if (apk) {
        const download = createButton("Download APK", apk.browser_download_url, "button button-small button-primary");
        download.removeAttribute("target");
        download.removeAttribute("rel");
        actions.append(download);
      }
      actions.append(createButton("GitHub release", release.html_url));
      if (checksum) actions.append(createButton("Checksum file", checksum.browser_download_url));
      if (sha) {
        const copy = document.createElement("button");
        copy.type = "button";
        copy.className = "button button-small button-ghost";
        copy.textContent = "Copy SHA-256";
        copy.addEventListener("click", () => copyText(sha, "SHA-256 copied"));
        actions.append(copy);
      }

      toggle.addEventListener("click", () => {
        const isOpen = toggle.getAttribute("aria-expanded") === "true";
        toggle.setAttribute("aria-expanded", String(!isOpen));
        toggle.textContent = isOpen ? "View changes" : "Hide changes";
        details.hidden = isOpen;
      });

      releaseList.append(card);
    });
  }

  function renderEmpty(message, detail = "") {
    latestCard.classList.remove("loading-card");
    latestCard.setAttribute("aria-busy", "false");
    latestCard.innerHTML = '<div class="empty-state"><h3>No APK release is available yet</h3><p></p><div class="error-note"></div></div>';
    latestCard.querySelector("p").textContent = message;
    latestCard.querySelector(".error-note").textContent = detail;

    releaseList.innerHTML = '<div class="empty-state"><h3>Release history will appear here</h3><p>Publish the first signed APK through the production workflow.</p></div>';
    releaseCount.textContent = "No published releases";
  }

  function saveReleaseCache(releases) {
    try {
      localStorage.setItem(CACHE_KEY, JSON.stringify({ savedAt: Date.now(), releases }));
    } catch {
      // Storage can be disabled; the live release feed still works.
    }
  }

  function readReleaseCache() {
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
      if (!response.ok) throw new Error(`GitHub returned ${response.status}`);

      const releases = (await response.json()).filter((release) => !release.draft);
      saveReleaseCache(releases);

      if (!releases.length) {
        renderEmpty("The release archive is connected and waiting for its first published APK.");
        return;
      }

      renderLatest(releases[0]);
      renderReleaseList(releases);
    } catch (error) {
      const cached = readReleaseCache();
      if (cached?.length) {
        renderLatest(cached[0]);
        renderReleaseList(cached);
        showToast("Showing cached release information");
      } else {
        renderEmpty("Release information could not be loaded.", error.message);
      }
    } finally {
      refreshButton.classList.remove("is-spinning");
      refreshButton.disabled = false;
    }
  }

  refreshButton.addEventListener("click", () => loadReleases({ force: true }));

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

  window.addEventListener("appinstalled", () => showToast("HomePilot release hub installed"));

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("sw.js").catch(() => {
        // The site remains fully functional without offline support.
      });
    });
  }

  loadReleases();
})();
