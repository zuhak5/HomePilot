import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

import {
  approvedActionReleases,
  hostedAllowedActionPatterns,
  validateActionSource,
  validateRepositoryActionReferences,
} from './github-actions-policy.mjs';

const read = async (path) =>
  (await fs.readFile(new URL(`../${path}`, import.meta.url), 'utf8')).replaceAll(
    '\r\n',
    '\n',
  );

test('GitHub Actions use only reviewed immutable references', async () => {
  const result = await validateRepositoryActionReferences();
  assert.deepEqual(result.errors, []);
  assert.equal(result.externalReferences, 59);
  assert.equal(result.localReferences, 0);
  assert.equal(result.files.length, 8);
});

test('hosted Actions policy allowlist matches reviewed action owners', () => {
  assert.deepEqual(
    hostedAllowedActionPatterns,
    Object.keys(approvedActionReleases)
      .map((action) => `${action}@*`)
      .sort(),
  );
  assert.deepEqual(hostedAllowedActionPatterns, [
    'actions/attest-build-provenance@*',
    'actions/checkout@*',
    'actions/configure-pages@*',
    'actions/deploy-pages@*',
    'actions/setup-java@*',
    'actions/setup-node@*',
    'actions/upload-artifact@*',
    'actions/upload-pages-artifact@*',
    'denoland/setup-deno@*',
  ]);
});

test('GitHub Actions policy rejects mutable, shortened, and unowned references', () => {
  const fullSha = 'd23441a48e516b6c34aea4fa41551a30e30af803';
  const fixtures = [
    ['major tag', 'uses: actions/checkout@v6', /full 40-character/],
    ['branch', 'uses: actions/checkout@main', /full 40-character/],
    ['short SHA', 'uses: actions/checkout@d23441a', /full 40-character/],
    [
      'unknown owner',
      `uses: example/checkout@${fullSha} # v6.1.0`,
      /not an owned, reviewed action/,
    ],
    [
      'unowned action',
      `uses: actions/cache@${fullSha} # v6.1.0`,
      /not an owned, reviewed action/,
    ],
    [
      'YAML anchor',
      `uses: &checkout actions/checkout@${fullSha} # v6.1.0`,
      /YAML anchors/,
    ],
    [
      'YAML alias key',
      `*uses: actions/checkout@${fullSha} # v6.1.0`,
      /invalid YAML|YAML aliases/,
    ],
    [
      'escaped uses key',
      '"u\\u0073es": actions/checkout@main',
      /full 40-character/,
    ],
    [
      'unreviewed digest',
      'uses: actions/checkout@0000000000000000000000000000000000000000 # v6.1.0',
      /not a reviewed release/,
    ],
    [
      'missing release comment',
      `uses: actions/checkout@${fullSha}`,
      /exact comment # v6.1.0/,
    ],
    [
      'local path escape',
      'uses: ./tool/unowned-action',
      /owned under \.\/\.github\/actions/,
    ],
  ];

  for (const [name, source, expected] of fixtures) {
    const result = validateActionSource(`steps:\n  - ${source}\n`, `${name}.yml`);
    assert.match(result.errors.join('\n'), expected, name);
  }

  const explicitKey = validateActionSource(
    'steps:\n  - ? uses\n    : actions/checkout@main\n',
    'explicit-key.yml',
  );
  assert.match(explicitKey.errors.join('\n'), /full 40-character/);

  const aliasedKey = validateActionSource(
    `usesKey: &usesKey uses\nsteps:\n  - ? *usesKey\n    : actions/checkout@${fullSha}\n`,
    'aliased-key.yml',
  );
  assert.match(aliasedKey.errors.join('\n'), /YAML anchors|YAML aliases/);

  const multilineEscapedKey = validateActionSource(
    'steps:\n  - ? "u' +
      '\\' +
      '\n      ses"\n    : actions/checkout@main\n',
    'multiline-escaped-key.yml',
  );
  assert.match(multilineEscapedKey.errors.join('\n'), /full 40-character/);

  const taggedKey = validateActionSource(
    `steps:\n  - !homepilot/key uses: actions/checkout@${fullSha} # v6.1.0\n`,
    'tagged-key.yml',
  );
  assert.match(taggedKey.errors.join('\n'), /invalid YAML|YAML tags/);

  const punctuatedAlias = validateActionSource(
    `key: &homepilot.key uses\nsteps:\n  - ? *homepilot.key\n    : actions/checkout@${fullSha}\n`,
    'punctuated-alias.yml',
  );
  assert.match(
    punctuatedAlias.errors.join('\n'),
    /invalid YAML|YAML anchors|YAML aliases/,
  );

  const unusualButOwned = validateActionSource(
    `steps:\n  - { uses: actions/checkout@${fullSha} } # v6.1.0\n  - run: |\n      echo "uses: actions/checkout@v6"\n`,
    'flow-and-block.yml',
  );
  assert.deepEqual(unusualButOwned.errors, []);
  assert.equal(unusualButOwned.externalReferences, 1);
});

test('Play AAB rail uses protected production names and verifiable evidence', async () => {
  const workflow = await read('.github/workflows/build-play-android.yml');
  assert.match(workflow, /name: Require current main release source/);
  assert.match(workflow, /Reject a non-main dispatch/);
  assert.match(workflow, /source_sha" != "\$remote_sha/);
  assert.match(workflow, /needs: validate-release-source/);
  assert.match(workflow, /environment: production-play-signing/);
  assert.doesNotMatch(workflow, /if: github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /SUPABASE_URL: \$\{\{ vars\.SUPABASE_URL \}\}/);
  assert.match(
    workflow,
    /ANDROID_KEYSTORE_BASE64: \$\{\{ secrets\.PLAY_UPLOAD_KEYSTORE_BASE64 \}\}/,
  );
  assert.match(
    workflow,
    /ANDROID_STORE_PASSWORD: \$\{\{ secrets\.PLAY_UPLOAD_STORE_PASSWORD \}\}/,
  );
  assert.doesNotMatch(
    workflow,
    /PROD_SUPABASE_URL|ANDROID_KEYSTORE_PASSWORD|ANDROID_APK_|SENTRY_AUTH_TOKEN|SUPABASE_(?:ADVISOR|MIGRATION)_/,
  );
  assert.match(workflow, /contents: read/);
  assert.match(workflow, /actions: read/);
  assert.match(workflow, /jarsigner -verify/);
  assert.match(workflow, /keytool -printcert -jarfile/);
  assert.match(workflow, /collect_android_release_evidence\.ps1/);
  assert.match(
    workflow,
    /attest-build-provenance@977bb373ede98d70efdf65b84cb5f73e068dcc2a # v3\.0\.0/,
  );
  assert.match(workflow, /release_attempt_id: \$\{\{ steps\.attempt_guard\.outputs\.attempt_id \}\}/);
  assert.match(workflow, /release_attempt_run_id:/);
  assert.match(workflow, /HomePilot-release-attempt-dry-run-\$INPUT_RELEASE_ATTEMPT_ID/);
  assert.match(workflow, /node tool\/release_attempt_ledger\.mjs verify-attempt/);
  assert.match(workflow, /node tool\/release_attempt_ledger\.mjs find-backend/);
  assert.match(workflow, /required-evidence-keys backend_validation,aab_artifact/);
  assert.match(workflow, /name: Revalidate attempt before AAB artifact upload and attestation/);
  assert.match(workflow, /backend-validation\.json/);
  assert.doesNotMatch(workflow, /validate-google-backend\.yml\/runs\?head_sha=/);
  assert.doesNotMatch(workflow, /event -in @\("push", "workflow_dispatch"\)/);
  assert.match(workflow, /backend_gate_run_url = "\$\{\{ steps\.backend_gate\.outputs\.run_url \}\}"/);
  assert.match(workflow, /name: Upload AAB evidence\n\s+if: always\(\)/);
  assert.match(
    workflow,
    /path: \|\n\s+release\/aab-evidence\n\s+release-attempt/,
  );
  assert.ok(
    workflow.indexOf('Initialize AAB diagnostics') <
      workflow.indexOf('Build and test production AAB'),
    'AAB diagnostics must exist before the build can fail',
  );
  assert.doesNotMatch(
    workflow,
    /googleapis|service_account|supply|edits\.(?:insert|bundles|tracks)|publish.*play/i,
  );
});

test('APK rail archives merged manifest and dependency evidence', async () => {
  const workflow = await read('.github/workflows/build-production-android.yml');
  assert.match(workflow, /name: Require current main release source/);
  assert.match(workflow, /Reject a non-main dispatch/);
  assert.match(workflow, /source_sha" != "\$remote_sha/);
  assert.match(workflow, /needs: validate-release-source/);
  assert.match(workflow, /environment: production-android-signing/);
  assert.match(workflow, /environment: production-sentry/);
  assert.match(workflow, /environment: production-github-release/);
  assert.doesNotMatch(workflow, /if: github\.ref == 'refs\/heads\/main'/);
  assert.match(
    workflow,
    /ANDROID_KEYSTORE_BASE64: \$\{\{ secrets\.ANDROID_APK_KEYSTORE_BASE64 \}\}/,
  );
  assert.match(workflow, /collect_android_release_evidence\.ps1/);
  assert.match(workflow, /production-apk-evidence/);
  assert.match(workflow, /name: Upload APK diagnostics\n\s+if: always\(\)/);
  assert.match(workflow, /name: Upload production APK handoff/);
  assert.match(workflow, /HomePilot-production-apk-handoff-\$\{\{ github\.run_id \}\}/);
  assert.match(workflow, /apk-signature-verification\.txt/);
  assert.match(workflow, /apk-badging\.txt/);
  assert.ok(
    workflow.indexOf('Initialize APK diagnostics') <
      workflow.indexOf('Reject an existing release tag before mutation'),
    'APK diagnostics must exist before the first release-identity failure',
  );
  assert.match(workflow, /validate_google_release_contracts\.mjs/);
  assert.match(workflow, /release_attempt_run_id:/);
  assert.match(workflow, /HomePilot-release-attempt-dry-run-\$INPUT_RELEASE_ATTEMPT_ID/);
  assert.match(workflow, /release_attempt_id: \$\{\{ steps\.attempt_guard\.outputs\.attempt_id \}\}/);
  assert.match(workflow, /node tool\/release_attempt_ledger\.mjs verify-attempt/);
  assert.match(workflow, /node tool\/release_attempt_ledger\.mjs find-backend/);
  assert.match(workflow, /required-evidence-keys backend_validation,apk_artifact/);
  assert.match(workflow, /backend-validation\.json/);
  assert.doesNotMatch(workflow, /validate-google-backend\.yml\/runs\?head_sha=/);
  assert.doesNotMatch(workflow, /event -in @\("push", "workflow_dispatch"\)/);
  assert.match(workflow, /backend_gate_run_url = "\$\{\{ steps\.backend_gate\.outputs\.run_url \}\}"/);
  assert.match(workflow, /name: Require release attempt before Sentry mutation/);
  assert.match(workflow, /name: Require release attempt before GitHub mutation/);
  assert.match(workflow, /name: Revalidate artifact attempt before Sentry release publish/);
  assert.match(workflow, /name: Revalidate attempt before attestation/);
  assert.match(workflow, /name: Revalidate attempt before GitHub Release publication/);
  assert.match(workflow, /name: Create Sentry deploy marker/);
  assert.match(workflow, /Mode publish/);
  assert.match(workflow, /Mode deploy/);
  assert.match(workflow, /git ls-remote --exit-code --refs origin "refs\/tags\/\$env:RELEASE_TAG"/);
  assert.match(workflow, /name: Recheck release tag before Sentry mutation/);
  assert.match(workflow, /name: Recheck release tag before GitHub mutation/);
  assert.match(workflow, /needs:\n\s+- build-production-apk\n\s+- publish-sentry-release/);
  assert.ok(
    workflow.indexOf('Collect APK manifest and dependency evidence') <
      workflow.indexOf('Upload production APK handoff'),
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
  assert.ok(
    workflow.indexOf('Recheck release tag before Sentry mutation') <
      workflow.indexOf('Revalidate artifact attempt before Sentry release publish') &&
      workflow.indexOf('Revalidate artifact attempt before Sentry release publish') <
        workflow.indexOf('Publish and verify Sentry release'),
    'the artifact attempt must be revalidated immediately before Sentry release publication',
  );
  assert.ok(
    workflow.indexOf('Recheck release tag before GitHub mutation') <
      workflow.indexOf('Publish GitHub Release', workflow.indexOf('Recheck release tag before GitHub mutation')),
    'the remote tag must be rechecked before GitHub Release publication',
  );
  assert.ok(
    workflow.indexOf('Publish GitHub Release') <
      workflow.indexOf('Create Sentry deploy marker'),
    'Sentry deploy marker job must run after GitHub Release publication',
  );
  const tagRecheck = workflow.slice(
    workflow.indexOf('Recheck release tag before Sentry mutation'),
    workflow.indexOf('Publish and verify Sentry release'),
  );
  assert.match(tagRecheck, /if \(\$TagExitCode -ne 2\)/);
  assert.match(
    tagRecheck,
    /\n\s+exit 0\n/,
    'an accepted no-tag result must not leak git exit code 2 to the step',
  );
  const signingJob = workflow.slice(
    workflow.indexOf('build-production-apk:'),
    workflow.indexOf('publish-sentry-release:'),
  );
  assert.doesNotMatch(signingJob, /SENTRY_AUTH_TOKEN|contents: write|attestations: write/);
  const sentryJob = workflow.slice(
    workflow.indexOf('publish-sentry-release:'),
    workflow.indexOf('publish-github-release:'),
  );
  assert.match(sentryJob, /SENTRY_AUTH_TOKEN: \$\{\{ secrets\.SENTRY_AUTH_TOKEN \}\}/);
  assert.doesNotMatch(sentryJob, /ANDROID_APK_|PLAY_UPLOAD_|contents: write|attestations: write/);
  const githubReleaseJob = workflow.slice(
    workflow.indexOf('publish-github-release:'),
    workflow.indexOf('publish-sentry-deploy:'),
  );
  assert.match(githubReleaseJob, /contents: write/);
  assert.match(githubReleaseJob, /attestations: write/);
  assert.doesNotMatch(githubReleaseJob, /ANDROID_APK_|PLAY_UPLOAD_|SENTRY_AUTH_TOKEN/);
  const sentryDeployJob = workflow.slice(workflow.indexOf('publish-sentry-deploy:'));
  assert.match(sentryDeployJob, /SENTRY_AUTH_TOKEN: \$\{\{ secrets\.SENTRY_AUTH_TOKEN \}\}/);
  assert.match(sentryDeployJob, /HomePilot-release-publication-\$env:GITHUB_RUN_ID/);
  assert.match(
    sentryDeployJob,
    /node tool\/release_attempt_ledger\.mjs verify-attempt[\s\S]+--state published[\s\S]+& "\.\\tool\\publish_sentry_release\.ps1"/,
  );
  assert.doesNotMatch(sentryDeployJob, /ANDROID_APK_|PLAY_UPLOAD_|contents: write|attestations: write/);
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
  assert.match(workflow, /name: Hosted Supabase Advisors/);
  assert.match(workflow, /deno fmt --check/);
  assert.match(workflow, /deno check --frozen/);
  assert.match(workflow, /deno test --frozen/);
  assert.match(workflow, /admob-ssv-handler\/index_test\.ts/);
  assert.match(workflow, /delete-account\/index_test\.ts/);
  assert.match(workflow, /account-deletion-status\/index_test\.ts/);
  assert.match(workflow, /npx supabase start/);
  assert.match(workflow, /npm run supabase:lint/);
  assert.match(workflow, /npm run supabase:test/);
  assert.match(workflow, /node tool\/audit_supabase_advisors\.mjs/);
  assert.match(workflow, /environment: production-supabase-advisors/);
  assert.match(workflow, /needs: validate-advisor-source/);
  assert.match(workflow, /persist-credentials: false/);
  assert.match(
    workflow,
    /SUPABASE_ACCESS_TOKEN: \$\{\{ secrets\.SUPABASE_ADVISOR_ACCESS_TOKEN \}\}/,
  );
  assert.doesNotMatch(
    workflow,
    /SUPABASE_MIGRATION_|ANDROID_(?:APK_)?KEY|PLAY_UPLOAD_|SENTRY_AUTH_TOKEN/,
  );
  assert.match(workflow, /if: github\.event_name == 'workflow_dispatch'/);
  assert.match(workflow, /if: always\(\)/);
});

test('Supabase migration deployment requires exact main and explicit production confirmation', async () => {
  const workflow = await read(
    '.github/workflows/deploy-supabase-migrations.yml',
  );
  assert.match(workflow, /name: Deploy Supabase Migrations/);
  assert.match(workflow, /test "\$GITHUB_REF" = "refs\/heads\/main"/);
  assert.match(workflow, /test "\$source_sha" = "\$INPUT_SOURCE_SHA"/);
  assert.match(workflow, /test "\$source_sha" = "\$GITHUB_SHA"/);
  assert.match(workflow, /test "\$source_sha" = "\$remote_sha"/);
  assert.match(workflow, /release_attempt_id:/);
  assert.match(workflow, /release_attempt_run_id:/);
  assert.match(workflow, /INPUT_RELEASE_ATTEMPT_ID/);
  assert.match(workflow, /\^hpra_\[0-9a-f\]\{32\}\$/);
  assert.match(workflow, /name: Run semantic migration prerequisites/);
  assert.match(workflow, /deno fmt --check/);
  assert.match(workflow, /npm run supabase:lint/);
  assert.match(workflow, /npm run supabase:test/);
  assert.match(workflow, /apply-pending-migrations/);
  assert.match(workflow, /test "\$INPUT_PROJECT_REF" = "\$expected_ref"/);
  assert.match(workflow, /environment: production-supabase-migrations/);
  assert.match(workflow, /name: Confirm protected Supabase project/);
  assert.match(workflow, /SUPABASE_URL: \$\{\{ vars\.SUPABASE_URL \}\}/);
  const protectedEnvironment = workflow.indexOf(
    'environment: production-supabase-migrations',
  );
  const projectConfirmation = workflow.indexOf(
    'name: Confirm protected Supabase project',
  );
  const semanticGate = workflow.indexOf('name: Run semantic migration prerequisites');
  const projectLink = workflow.indexOf('name: Link the confirmed hosted project');
  assert.ok(
    protectedEnvironment >= 0 &&
      projectConfirmation > protectedEnvironment &&
      semanticGate >= 0 &&
      projectLink > projectConfirmation,
    'Project identity must be checked inside the protected job before linking.',
  );
  assert.match(
    workflow,
    /SUPABASE_ACCESS_TOKEN: \$\{\{ secrets\.SUPABASE_MIGRATION_ACCESS_TOKEN \}\}/,
  );
  assert.match(
    workflow,
    /SUPABASE_DB_PASSWORD: \$\{\{ secrets\.SUPABASE_MIGRATION_DB_PASSWORD \}\}/,
  );
  assert.doesNotMatch(
    workflow,
    /SUPABASE_ADVISOR_|ANDROID_(?:APK_)?KEY|PLAY_UPLOAD_|SENTRY_AUTH_TOKEN/,
  );
  const dryRun = workflow.indexOf('name: Dry-run pending migrations');
  const revalidateApply = workflow.indexOf(
    'name: Revalidate attempt immediately before migration apply',
  );
  const apply = workflow.indexOf('name: Apply pending migrations');
  assert.ok(dryRun >= 0 && revalidateApply > dryRun && apply > revalidateApply);
  assert.match(workflow, /release-attempt\.migration-started\.json/);
  assert.match(workflow, /release-attempt\.migration-externally-verified\.json/);
  assert.doesNotMatch(workflow, /--include-all|migration repair|include-seed/);
});

test('Sentry publisher separates release publication from deploy marker', async () => {
  const script = await read('tool/publish_sentry_release.ps1');
  assert.match(script, /\[ValidateSet\('publish', 'deploy'\)\]/);
  assert.match(script, /if \(\$Mode -eq 'deploy'\)/);
  assert.match(script, /releases\/\$encodedRelease\/deploys\//);
  assert.match(script, /Multiple Sentry deploy markers already exist/);
  assert.match(script, /Expected exactly one Sentry deploy marker/);
  assert.match(script, /without a deploy marker/);
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
  assert.match(runbook, /`Require current main Advisor source`/);
  assert.match(runbook, /`Hosted Supabase Advisors`/);
});

test('VersionDeck production deployment is gated by a successful exact-SHA APK run', async () => {
  const workflow = await read('.github/workflows/deploy-download-site.yml');
  assert.doesNotMatch(workflow, /^  push:/m);
  assert.doesNotMatch(workflow, /^  release:/m);
  assert.match(workflow, /production_run_id:/);
  assert.match(workflow, /required: true/);
  assert.match(workflow, /release_attempt_id:/);
  assert.match(workflow, /HomePilot-release-attempt-\$\{release_attempt_id\}/);
  assert.match(workflow, /name: Revalidate source and attempt before Pages artifact upload/);
  assert.match(workflow, /name: Check out deployment source/);
  assert.match(workflow, /name: Require release attempt before Pages mutation/);
  assert.match(workflow, /github\.event\.workflow_run\.conclusion == 'success'/);
  assert.match(workflow, /test "\$upstream_sha" = "\$source_sha"/);
  assert.match(workflow, /test "\$run_name" = "Build Production APK"/);
  assert.match(workflow, /test "\$run_conclusion" = "success"/);
  assert.match(workflow, /test "\$run_sha" = "\$source_sha"/);
});

test('release attempt dry run validates named backend evidence without mutation', async () => {
  const workflow = await read('.github/workflows/release-attempt-dry-run.yml');
  assert.match(workflow, /name: Release Attempt Dry Run/);
  assert.match(workflow, /backend_run_id:/);
  assert.match(workflow, /environment: production-github-release/);
  assert.match(workflow, /node tool\/release_attempt_ledger\.mjs create/);
  assert.match(workflow, /node tool\/release_attempt_ledger\.mjs validate-backend/);
  assert.match(workflow, /node tool\/release_attempt_ledger\.mjs advance/);
  assert.match(workflow, /--state prerequisites_verified/);
  assert.match(workflow, /--evidence-key backend_validation/);
  assert.match(workflow, /name: Prove mutation-boundary negative fixtures/);
  assert.match(workflow, /missing required evidence: apk_artifact/);
  assert.match(workflow, /HomePilot-release-attempt-dry-run-/);
  assert.doesNotMatch(
    workflow,
    /ANDROID_(?:APK_)?KEY|PLAY_UPLOAD_|SENTRY_AUTH_TOKEN|SUPABASE_(?:ADVISOR|MIGRATION)_/,
  );
  assert.doesNotMatch(
    workflow,
    /gh release create|deploy-pages|supabase db push|publish_sentry_release|build_prod|build_play/i,
  );
});
