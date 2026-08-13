import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createReleaseAttempt,
  isReleaseAttemptId,
  requiredBackendJobs,
  transitionReleaseAttempt,
  validateBackendAggregate,
} from './release_attempt_ledger.mjs';

const sourceSha = '1d7e59c18d3ca69f91cc1cd7a17ad03801f22e41';

const backendRun = (overrides = {}) => ({
  id: 123,
  run_attempt: 1,
  name: 'Validate Google Backend and Release Contracts',
  path: '.github/workflows/validate-google-backend.yml',
  event: 'workflow_dispatch',
  head_branch: 'main',
  head_sha: sourceSha,
  status: 'completed',
  conclusion: 'success',
  html_url: 'https://github.com/zuhak5/HomePilot/actions/runs/123',
  repository: { full_name: 'zuhak5/HomePilot' },
  ...overrides,
});

const backendJobs = (overrides = {}) =>
  requiredBackendJobs.map((name, index) => ({
    id: 1000 + index,
    name,
    status: 'completed',
    conclusion: 'success',
    started_at: '2026-08-13T12:00:00Z',
    completed_at: '2026-08-13T12:01:00Z',
    html_url: `https://github.com/zuhak5/HomePilot/actions/runs/123/job/${1000 + index}`,
    ...(overrides[name] ?? {}),
  }));

test('release attempt IDs are stable opaque identifiers', async () => {
  const attempt = await createReleaseAttempt({
    repository: 'zuhak5/HomePilot',
    runId: '456',
    runAttempt: '1',
    sourceSha,
    sourceRef: 'refs/heads/main',
    event: 'workflow_dispatch',
    workflowPath: '.github/workflows/build-production-android.yml',
    targetKind: 'apk',
    targetEnvironment: 'production-android-signing',
    versionName: '1.5.0',
    versionCode: '44',
    releaseTag: 'v1.5.0-build.44',
  });

  assert.equal(attempt.schema_version, 1);
  assert.equal(attempt.state, 'created');
  assert.equal(isReleaseAttemptId(attempt.attempt_id), true);
  assert.equal(attempt.identity.source_sha, sourceSha);
  assert.match(attempt.identity.workflow_sha256, /^[0-9a-f]{64}$/);
});

test('release attempt transitions are idempotent and terminal-safe', async () => {
  const attempt = await createReleaseAttempt({
    repository: 'zuhak5/HomePilot',
    runId: '456',
    sourceSha,
    sourceRef: 'refs/heads/main',
    event: 'workflow_dispatch',
    workflowPath: '.github/workflows/build-production-android.yml',
    targetKind: 'apk',
    targetEnvironment: 'production-android-signing',
  });
  const verified = transitionReleaseAttempt(attempt, 'prerequisites_verified');
  assert.equal(verified.state, 'prerequisites_verified');
  assert.equal(
    transitionReleaseAttempt(verified, 'prerequisites_verified').state,
    'prerequisites_verified',
  );
  const failed = transitionReleaseAttempt(verified, 'failed');
  assert.throws(
    () => transitionReleaseAttempt(failed, 'published'),
    /Invalid release attempt transition/,
  );
  assert.equal(transitionReleaseAttempt(failed, 'reconciled').state, 'reconciled');
});

test('backend aggregate accepts only exact successful named job set', () => {
  const aggregate = validateBackendAggregate({
    run: backendRun(),
    jobs: backendJobs(),
    repository: 'zuhak5/HomePilot',
    sourceSha,
  });
  assert.equal(aggregate.run_id, '123');
  assert.deepEqual(
    aggregate.required_jobs.map((job) => job.name),
    requiredBackendJobs,
  );
});

test('backend aggregate rejects skipped neutral missing duplicate and mismatched runs', () => {
  assert.throws(
    () =>
      validateBackendAggregate({
        run: backendRun({ event: 'push' }),
        jobs: backendJobs(),
        repository: 'zuhak5/HomePilot',
        sourceSha,
      }),
    /workflow event mismatch/,
  );
  assert.throws(
    () =>
      validateBackendAggregate({
        run: backendRun(),
        jobs: backendJobs({
          'Hosted Supabase Advisors': { conclusion: 'skipped' },
        }),
        repository: 'zuhak5/HomePilot',
        sourceSha,
      }),
    /Hosted Supabase Advisors conclusion mismatch/,
  );
  assert.throws(
    () =>
      validateBackendAggregate({
        run: backendRun(),
        jobs: backendJobs({
          'Hosted Supabase Advisors': { conclusion: 'neutral' },
        }),
        repository: 'zuhak5/HomePilot',
        sourceSha,
      }),
    /Hosted Supabase Advisors conclusion mismatch/,
  );
  assert.throws(
    () =>
      validateBackendAggregate({
        run: backendRun(),
        jobs: backendJobs().filter((job) => job.name !== 'Supabase database tests'),
        repository: 'zuhak5/HomePilot',
        sourceSha,
      }),
    /Missing backend validation job/,
  );
  assert.throws(
    () =>
      validateBackendAggregate({
        run: backendRun(),
        jobs: [...backendJobs(), backendJobs()[0]],
        repository: 'zuhak5/HomePilot',
        sourceSha,
      }),
    /Duplicate backend validation job/,
  );
  assert.throws(
    () =>
      validateBackendAggregate({
        run: backendRun({ head_sha: '0'.repeat(40) }),
        jobs: backendJobs(),
        repository: 'zuhak5/HomePilot',
        sourceSha,
      }),
    /workflow source SHA mismatch/,
  );
});
