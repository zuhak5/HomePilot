import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { validateVersionDeckManifest } from "../download-site/manifest-schema.js";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const site = path.resolve(root, process.argv[2] || "download-site");
const requiredFiles = [
  "index.html",
  "styles.css",
  "enhancements.css",
  "security.css",
  "app.js",
  "manifest-schema.js",
  "cache-policy.js",
  "relative-time.js",
  "manifest.webmanifest",
  "sw.js",
  "releases.json",
  "asset-manifest.json",
  "build-info.json",
  ".nojekyll",
  "assets/versiondeck-mark.svg",
  "assets/versiondeck-192.png",
  "assets/versiondeck-512.png",
];

for (const file of requiredFiles) await fs.access(path.join(site, file));

const html = await fs.readFile(path.join(site, "index.html"), "utf8");
const requiredHtml = [
  'id="release-status"',
  'id="stale-banner"',
  'id="latest-card"',
  'id="release-template"',
  'type="module" src="app.js"',
  "Content-Security-Policy",
];
for (const marker of requiredHtml) {
  if (!html.includes(marker)) throw new Error(`index.html is missing ${marker}`);
}
if (/<script(?![^>]*\bsrc=)/i.test(html)) throw new Error("Inline scripts are not allowed.");
if (/<style\b/i.test(html)) throw new Error("Inline styles are not allowed.");
if (/\son[a-z]+\s*=/i.test(html)) throw new Error("Inline event handlers are not allowed.");
if (/href="#"/.test(html.replace('href="#latest-heading"', ""))) {
  throw new Error("index.html contains a placeholder href.");
}
for (const directive of [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
]) {
  if (!html.includes(directive)) throw new Error(`Content Security Policy is missing ${directive}`);
}

const webManifest = JSON.parse(await fs.readFile(path.join(site, "manifest.webmanifest"), "utf8"));
if (webManifest.orientation) throw new Error("PWA orientation must not be forced.");
if (webManifest.display !== "standalone") throw new Error("PWA display must remain standalone.");
if (webManifest.start_url !== "./" || webManifest.scope !== "./") {
  throw new Error("PWA start_url and scope must remain relative to VersionDeck.");
}
for (const icon of webManifest.icons || []) await fs.access(path.join(site, icon.src));
for (const shortcut of webManifest.shortcuts || []) {
  if (!/^\.\/#(?:latest-heading|releases)$/.test(shortcut.url || "")) {
    throw new Error(`Unexpected PWA shortcut URL: ${shortcut.url}`);
  }
}

const releaseManifest = JSON.parse(await fs.readFile(path.join(site, "releases.json"), "utf8"));
const releaseErrors = validateVersionDeckManifest(releaseManifest);
if (releaseErrors.length) {
  throw new Error(`Release manifest validation failed: ${releaseErrors.join(" ")}`);
}

const serviceWorker = await fs.readFile(path.join(site, "sw.js"), "utf8");
if (serviceWorker.includes("__VERSIONDECK_CACHE_REVISION__")) {
  throw new Error("Service-worker cache revision was not replaced.");
}
if (!/shell-[a-f\d]{40}/i.test(serviceWorker)) {
  throw new Error("Service-worker cache name does not contain the source revision.");
}
const appShellMatch = serviceWorker.match(/const APP_SHELL = \[([\s\S]*?)\];/);
if (!appShellMatch) throw new Error("Service-worker app shell is missing.");
if (appShellMatch[1].includes("releases.json")) {
  throw new Error("releases.json must not be included in the service-worker app shell.");
}
if (!serviceWorker.includes('fetch(request, { cache: "no-store" })')) {
  throw new Error("Service worker must fetch releases.json without storage caching.");
}

const buildInfo = JSON.parse(await fs.readFile(path.join(site, "build-info.json"), "utf8"));
if (!/^[a-f\d]{40}$/i.test(buildInfo.sourceRevision || "")) {
  throw new Error("Build information does not contain a full source revision.");
}
if (buildInfo.sourceRevision !== releaseManifest.generatorCommit) {
  throw new Error("Build source revision and manifest generator commit disagree.");
}

const inventory = JSON.parse(await fs.readFile(path.join(site, "asset-manifest.json"), "utf8"));
if (inventory.revision !== buildInfo.sourceRevision) {
  throw new Error("Asset inventory revision and build source revision disagree.");
}
for (const [relativePath, expectedHash] of Object.entries(inventory.files || {})) {
  const content = await fs.readFile(path.join(site, relativePath));
  const actualHash = crypto.createHash("sha256").update(content).digest("hex");
  if (actualHash !== expectedHash) throw new Error(`Asset hash mismatch: ${relativePath}`);
}
if (inventory.files["release-diagnostics.json"]) {
  throw new Error("Release diagnostics must not be deployed with the public site.");
}

console.log(`VersionDeck static validation passed for ${site}.`);
