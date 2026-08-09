import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const read = (path) => fs.readFile(new URL(`../${path}`, import.meta.url), 'utf8');

test('Play AAB rail uses protected production names and verifiable evidence', async () => {
  const workflow = await read('.github/workflows/build-play-android.yml');
  assert.match(workflow, /name: Require current main release source/);
  assert.match(workflow, /Reject a non-main dispatch/);
  assert.match(workflow, /source_sha" != "\$remote_sha/);
  assert.match(workflow, /needs: validate-release-source/);
  assert.doesNotMatch(workflow, /if: github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /SUPABASE_URL: \$\{\{ vars\.SUPABASE_URL \}\}/);
  assert.match(
    workflow,
    /ANDROID_STORE_PASSWORD: \$\{\{ secrets\.ANDROID_STORE_PASSWORD \}\}/,
  );
  assert.doesNotMatch(workflow, /PROD_SUPABASE_URL|ANDROID_KEYSTORE_PASSWORD/);
  assert.match(workflow, /contents: read/);
  assert.match(workflow, /actions: read/);
  assert.match(workflow, /jarsigner -verify/);
  assert.match(workflow, /keytool -printcert -jarfile/);
  assert.match(workflow, /collect_android_release_evidence\.ps1/);
  assert.match(workflow, /attest-build-provenance@v3/);
  assert.match(workflow, /validate-google-backend\.yml\/runs\?head_sha=/);
  assert.match(workflow, /\.path -eq "\.github\/workflows\/validate-google-backend\.yml"/);
  assert.match(workflow, /\.head_branch -eq "main"/);
  assert.match(workflow, /backend_gate_run_url = "\$\{\{ steps\.backend_gate\.outputs\.run_url \}\}"/);
  assert.match(workflow, /name: Upload AAB evidence\n\s+if: always\(\)/);
  assert.match(workflow, /path: release\/aab-evidence/);
  assert.ok(
    workflow.indexOf('Initialize AAB diagnostics') <
      workflow.indexOf('Build and test production AAB'),
    'AAB diagnostics must exist before the build can fail',
  );
  assert.doesNotMatch(workflow, /play.*upload|publish.*play/i);
});

test('APK rail archives merged manifest and dependency evidence', async () => {
  const workflow = await read('.github/workflows/build-production-android.yml');
  assert.match(workflow, /name: Require current main release source/);
  assert.match(workflow, /Reject a non-main dispatch/);
  assert.match(workflow, /source_sha" != "\$remote_sha/);
  assert.match(workflow, /needs: validate-release-source/);
  assert.doesNotMatch(workflow, /if: github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /collect_android_release_evidence\.ps1/);
  assert.match(workflow, /production-apk-evidence/);
  assert.match(workflow, /name: Upload APK diagnostics\n\s+if: always\(\)/);
  assert.match(workflow, /apk-signature-verification\.txt/);
  assert.match(workflow, /apk-badging\.txt/);
  assert.ok(
    workflow.indexOf('Initialize APK diagnostics') <
      workflow.indexOf('Reject an existing release tag before mutation'),
    'APK diagnostics must exist before the first release-identity failure',
  );
  assert.match(workflow, /validate_google_release_contracts\.mjs/);
  assert.match(workflow, /validate-google-backend\.yml\/runs\?head_sha=/);
  assert.match(workflow, /\.path -eq "\.github\/workflows\/validate-google-backend\.yml"/);
  assert.match(workflow, /\.head_branch -eq "main"/);
  assert.match(workflow, /backend_gate_run_url = "\$\{\{ steps\.backend_gate\.outputs\.run_url \}\}"/);
  assert.match(workflow, /git ls-remote --exit-code --refs origin "refs\/tags\/\$env:RELEASE_TAG"/);
  assert.ok(
    workflow.indexOf('Collect APK manifest and dependency evidence') <
      workflow.indexOf('Publish and verify Sentry release'),
    'artifact evidence must fail before Sentry release mutation',
  );
  assert.ok(
    workflow.indexOf('Reject an existing release tag before mutation') <
      workflow.indexOf('Publish and verify Sentry release'),
    'existing tags must fail before Sentry release mutation',
  );
  assert.ok(
    workflow.indexOf('Recheck release tag before Sentry mutation') <
      workflow.indexOf('Publish and verify Sentry release'),
    'the remote tag must be rechecked immediately before Sentry mutation',
  );
});

test('backend gate covers formatting, type safety, functions, and database', async () => {
  const workflow = await read('.github/workflows/validate-google-backend.yml');
  const triggers = workflow.slice(
    workflow.indexOf('on:'),
    workflow.indexOf('concurrency:'),
  );
  assert.match(triggers, /pull_request:\n\s+branches: \[main\]/);
  assert.match(triggers, /push:\n\s+branches: \[main\]/);
  assert.doesNotMatch(triggers, /paths:/);
  assert.match(workflow, /name: Deno SSV tests/);
  assert.match(workflow, /name: Google contract\/static checks/);
  assert.match(workflow, /name: Supabase database tests/);
  assert.match(workflow, /deno fmt --check/);
  assert.match(workflow, /deno check --frozen/);
  assert.match(workflow, /deno test --frozen/);
  assert.match(workflow, /admob-ssv-handler\/index_test\.ts/);
  assert.match(workflow, /delete-account\/index_test\.ts/);
  assert.match(workflow, /npx supabase start/);
  assert.match(workflow, /npm run supabase:lint/);
  assert.match(workflow, /npm run supabase:test/);
  assert.match(workflow, /if: always\(\)/);
});

test('release evidence collector rejects analytics and unsafe manifests', async () => {
  const collector = await read('tool/collect_android_release_evidence.ps1');
  assert.match(collector, /prodReleaseRuntimeClasspath/);
  assert.match(collector, /firebase-analytics/);
  assert.match(collector, /ACCESS_FINE_LOCATION/);
  assert.match(collector, /ACCESS_BACKGROUND_LOCATION/);
  assert.match(collector, /GetAttribute\('package'\)/);
  assert.match(collector, /GetAttribute\('targetSdkVersion', \$androidNamespace\)/);
  assert.match(collector, /GetAttribute\('allowBackup', \$androidNamespace\)/);
  assert.match(collector, /GetAttribute\('debuggable', \$androidNamespace\)/);
  assert.match(collector, /\$adMobMetadata\.Count -ne 1/);
  assert.match(collector, /\/apk\/prod\/release\/output-metadata/);
  assert.match(collector, /\$elements\.Count -ne 1/);
  assert.match(collector, /allow_backup =/);
  assert.match(collector, /admob_application_id =/);
  assert.match(collector, /output_metadata_source =/);
  assert.doesNotMatch(collector, /ANDROID_(?:STORE|KEY)_PASSWORD/);
});

test('Google static validator scans all distributable sources and exact ad mappings', async () => {
  const validator = await read('tool/validate_google_release_contracts.mjs');
  assert.match(validator, /execFileSync\('git', \['ls-files', '--'\]/);
  assert.match(validator, /google-services\\\.json\$\/i/);
  assert.match(validator, /\.\.\.filesUnder\('lib'/);
  assert.match(validator, /'android\/app\/src'/);
  assert.match(validator, /\.\.\.filesUnder\('download-site'/);
  assert.match(validator, /payload\.role !== 'service_role'/);
  assert.match(validator, /configuredDemoIds\.length === approvedDemoIds\.length/);
  assert.match(validator, /String\\\\s\+get/);
});

test('release runbook names every required backend check exactly', async () => {
  const runbook = await read('docs/operations/release-runbook.md');
  assert.match(runbook, /`Deno SSV tests`/);
  assert.match(runbook, /`Google contract\/static checks`/);
  assert.match(runbook, /`Supabase database tests`/);
});

test('VersionDeck production deployment is gated by a successful exact-SHA APK run', async () => {
  const workflow = await read('.github/workflows/deploy-download-site.yml');
  assert.doesNotMatch(workflow, /^  push:/m);
  assert.doesNotMatch(workflow, /^  release:/m);
  assert.match(workflow, /production_run_id:/);
  assert.match(workflow, /required: true/);
  assert.match(workflow, /github\.event\.workflow_run\.conclusion == 'success'/);
  assert.match(workflow, /test "\$upstream_sha" = "\$source_sha"/);
  assert.match(workflow, /test "\$run_name" = "Build Production APK"/);
  assert.match(workflow, /test "\$run_conclusion" = "success"/);
  assert.match(workflow, /test "\$run_sha" = "\$source_sha"/);
});
