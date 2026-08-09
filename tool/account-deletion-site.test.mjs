import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  createGoogleAuthorizationUrl,
  createPkcePair,
  exchangeAuthorizationCode,
  fetchAuthenticatedUser,
  requestAccountDeletion,
  signOutLocally,
  validatePublicConfig,
} from "../download-site/account-deletion.js";
import {
  ACCOUNT_DELETION_SITE_URL,
  ACCOUNT_DELETION_SUPABASE_URL,
  accountDeletionConfigFromEnvironment,
  INERT_ACCOUNT_DELETION_CONFIG,
  renderAccountDeletionConfig,
  validateAccountDeletionPublicConfig,
} from "./build_account_deletion_site.mjs";
import { buildVersionDeckSite } from "./build_versiondeck_site.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const publishableKey = `sb_publishable_${"a".repeat(32)}`;
const productionConfig = Object.freeze({
  enabled: true,
  supabaseUrl: ACCOUNT_DELETION_SUPABASE_URL,
  supabasePublishableKey: publishableKey,
  accountDeletionSiteUrl: ACCOUNT_DELETION_SITE_URL,
});
const browserConfig = validatePublicConfig(productionConfig);

test("production public configuration is exact and fails closed", () => {
  assert.throws(
    () => accountDeletionConfigFromEnvironment({}),
    /PUBLIC_SUPABASE_URL.*PUBLIC_SUPABASE_PUBLISHABLE_KEY.*ACCOUNT_DELETION_SITE_URL/,
  );
  assert.deepEqual(
    accountDeletionConfigFromEnvironment({
      PUBLIC_SUPABASE_URL: ACCOUNT_DELETION_SUPABASE_URL,
      PUBLIC_SUPABASE_PUBLISHABLE_KEY: publishableKey,
      ACCOUNT_DELETION_SITE_URL,
    }),
    productionConfig,
  );
  assert.throws(
    () => validateAccountDeletionPublicConfig({
      ...productionConfig,
      supabaseUrl: "https://other-project.supabase.co",
    }),
    /allowlisted Supabase project URL/,
  );
  assert.throws(
    () => validateAccountDeletionPublicConfig({
      ...productionConfig,
      supabasePublishableKey: "not-a-public-supabase-key",
    }),
    /public anon\/publishable key/,
  );
});

test("inert configuration requires an explicit build mode", () => {
  assert.throws(
    () => validateAccountDeletionPublicConfig(INERT_ACCOUNT_DELETION_CONFIG),
    /explicit test mode/,
  );
  assert.deepEqual(
    accountDeletionConfigFromEnvironment({}, { allowInert: true }),
    INERT_ACCOUNT_DELETION_CONFIG,
  );
  const source = renderAccountDeletionConfig(INERT_ACCOUNT_DELETION_CONFIG, {
    allowInert: true,
  });
  assert.match(source, /enabled": false/);
});

test("PKCE authorization uses the fixed Google callback contract", async () => {
  const pair = await createPkcePair(webcrypto);
  assert.match(pair.verifier, /^[A-Za-z0-9_-]{86}$/);
  assert.match(pair.challenge, /^[A-Za-z0-9_-]{43}$/);
  const authorization = new URL(
    createGoogleAuthorizationUrl(browserConfig, pair.challenge),
  );
  assert.equal(
    `${authorization.origin}${authorization.pathname}`,
    `${ACCOUNT_DELETION_SUPABASE_URL}/auth/v1/authorize`,
  );
  assert.equal(authorization.searchParams.get("provider"), "google");
  assert.equal(
    authorization.searchParams.get("redirect_to"),
    ACCOUNT_DELETION_SITE_URL,
  );
  assert.equal(authorization.searchParams.get("code_challenge"), pair.challenge);
  assert.equal(authorization.searchParams.get("code_challenge_method"), "s256");
});

test("OAuth code exchange and identity lookup use public authenticated requests", async () => {
  const calls = [];
  const fetchApi = async (url, options) => {
    calls.push({ url, options });
    if (String(url).endsWith("/auth/v1/user")) {
      return jsonResponse(200, { id: "verified-user", email: "owner@example.com" });
    }
    return jsonResponse(200, { access_token: "memory-only-token" });
  };

  const accessToken = await exchangeAuthorizationCode(
    browserConfig,
    "oauth-code",
    "pkce-verifier",
    fetchApi,
  );
  const user = await fetchAuthenticatedUser(browserConfig, accessToken, fetchApi);

  assert.equal(accessToken, "memory-only-token");
  assert.equal(user.id, "verified-user");
  assert.equal(
    calls[0].url,
    `${ACCOUNT_DELETION_SUPABASE_URL}/auth/v1/token?grant_type=pkce`,
  );
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    auth_code: "oauth-code",
    code_verifier: "pkce-verifier",
  });
  assert.equal(calls[0].options.headers.apikey, publishableKey);
  assert.equal(calls[1].options.headers.Authorization, "Bearer memory-only-token");
  assert.equal(calls[1].options.credentials, "omit");
});

test("deletion requires an exact receipt for the authenticated user", async () => {
  const calls = [];
  const receipt = await requestAccountDeletion(
    browserConfig,
    "access-token",
    "verified-user",
    async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(200, {
        deleted: true,
        status: "deleted",
        user_id: "verified-user",
      });
    },
  );

  assert.deepEqual(receipt, {
    deleted: true,
    status: "deleted",
    user_id: "verified-user",
  });
  assert.equal(
    calls[0].url,
    `${ACCOUNT_DELETION_SUPABASE_URL}/functions/v1/delete-account`,
  );
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    confirmation: "delete-my-account",
  });
  assert.equal(calls[0].options.headers.Authorization, "Bearer access-token");

  for (const invalidReceipt of [
    { deleted: false, status: "deleted", user_id: "verified-user" },
    { deleted: true, status: "pending", user_id: "verified-user" },
    { deleted: true, status: "deleted", user_id: "different-user" },
    {},
  ]) {
    await assert.rejects(
      requestAccountDeletion(
        browserConfig,
        "access-token",
        "verified-user",
        async () => jsonResponse(200, invalidReceipt),
      ),
      /account_deletion_failed/,
    );
  }
});

test("local sign-out is best effort and does not surface a revoked-session failure", async () => {
  const calls = [];
  await signOutLocally(browserConfig, "access-token", async (url, options) => {
    calls.push({ url, options });
    throw new TypeError("network unavailable");
  });
  assert.equal(
    calls[0].url,
    `${ACCOUNT_DELETION_SUPABASE_URL}/auth/v1/logout?scope=local`,
  );
  assert.equal(calls[0].options.headers.Authorization, "Bearer access-token");
});

test("site assets expose confirmation and isolate deletion from offline navigation", async () => {
  const [html, script, serviceWorker, index] = await Promise.all([
    fs.readFile(path.join(root, "download-site/account-deletion.html"), "utf8"),
    fs.readFile(path.join(root, "download-site/account-deletion.js"), "utf8"),
    fs.readFile(path.join(root, "download-site/sw.js"), "utf8"),
    fs.readFile(path.join(root, "download-site/index.html"), "utf8"),
  ]);
  assert.match(html, /id="confirm-deletion"/);
  assert.match(html, /Content-Security-Policy/);
  assert.match(
    html,
    /connect-src https:\/\/iajvkvvvhwjdiuaufymh\.supabase\.co/,
  );
  assert.ok(
    html.indexOf("account-deletion-config.js") <
      html.indexOf("account-deletion.js"),
  );
  assert.match(html, /account-deletion\.css\?v=__ACCOUNT_DELETION_ASSET_REVISION__/);
  assert.doesNotMatch(script, /\blocalStorage\b|setTimeout\(|console\./);
  assert.match(serviceWorker, /networkOnlyAccountDeletionNavigation/);
  assert.match(serviceWorker, /relativePath === "account-deletion\.html"/);
  assert.match(index, /href="account-deletion\.html"/);
});

test("VersionDeck build writes the generated public config into its inventory", async (t) => {
  const temporaryRoot = await fs.mkdtemp(
    path.join(os.tmpdir(), "homepilot-account-deletion-"),
  );
  t.after(() => fs.rm(temporaryRoot, { recursive: true, force: true }));
  const releaseManifest = JSON.parse(
    await fs.readFile(path.join(root, "download-site/releases.json"), "utf8"),
  );
  const output = path.join(temporaryRoot, "site");
  await buildVersionDeckSite({
    source: path.join(root, "download-site"),
    output,
    revision: releaseManifest.generatorCommit,
    accountDeletionConfig: productionConfig,
  });

  const generatedConfig = await fs.readFile(
    path.join(output, "account-deletion-config.js"),
    "utf8",
  );
  const inventory = JSON.parse(
    await fs.readFile(path.join(output, "asset-manifest.json"), "utf8"),
  );
  assert.match(generatedConfig, /enabled": true/);
  assert.match(generatedConfig, /sb_publishable_/);
  const generatedHtml = await fs.readFile(
    path.join(output, "account-deletion.html"),
    "utf8",
  );
  assert.doesNotMatch(generatedHtml, /__ACCOUNT_DELETION_ASSET_REVISION__/);
  assert.match(
    generatedHtml,
    new RegExp(`account-deletion\\.js\\?v=${releaseManifest.generatorCommit}`),
  );
  assert.equal(
    typeof inventory.files["account-deletion-config.js"],
    "string",
  );
});

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
