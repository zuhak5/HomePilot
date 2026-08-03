import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const site = path.join(root, "download-site");
const requiredFiles = [
  "index.html",
  "styles.css",
  "enhancements.css",
  "app.js",
  "relative-time.js",
  "manifest.webmanifest",
  "sw.js",
  "releases.json",
  ".nojekyll",
];

for (const file of requiredFiles) {
  await fs.access(path.join(site, file));
}

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
if (/href="#"/.test(html.replace('href="#latest-heading"', ""))) {
  throw new Error("index.html contains a placeholder href.");
}

const webManifest = JSON.parse(
  await fs.readFile(path.join(site, "manifest.webmanifest"), "utf8"),
);
if (webManifest.orientation) throw new Error("PWA orientation must not be forced.");
if (webManifest.display !== "standalone") throw new Error("PWA display must remain standalone.");

const releaseManifest = JSON.parse(
  await fs.readFile(path.join(site, "releases.json"), "utf8"),
);
if (releaseManifest.schemaVersion !== 1) {
  throw new Error("Unexpected release manifest schema version.");
}
if (releaseManifest.repository !== "zuhak5/HomePilot") {
  throw new Error("Unexpected release manifest repository.");
}

console.log("VersionDeck static validation passed.");
