import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

export const releaseAttemptSchemaVersion = 1;

export const releaseAttemptStates = Object.freeze([
  'created',
  'prerequisites_verified',
  'mutation_started',
  'artifact_verified',
  'published',
  'externally_verified',
  'failed',
  'superseded',
  'reconciled',
]);

const terminalStates = new Set([
  'reconciled',
]);

const transitions = Object.freeze({
  created: new Set(['prerequisites_verified', 'failed', 'superseded']),
  prerequisites_verified: new Set([
    'mutation_started',
    'artifact_verified',
    'failed',
    'superseded',
  ]),
  mutation_started: new Set(['artifact_verified', 'published', 'failed', 'reconciled']),
  artifact_verified: new Set(['published', 'failed', 'reconciled']),
  published: new Set(['externally_verified', 'reconciled']),
  externally_verified: new Set(['reconciled']),
  failed: new Set(['reconciled']),
  superseded: new Set(['reconciled']),
  reconciled: new Set([]),
});

const evidenceKeyPattern = /^[a-z][a-z0-9_]*$/;

export const requiredBackendJobs = Object.freeze([
  'Deno SSV tests',
  'Google contract/static checks',
  'Supabase database tests',
  'Require current main Advisor source',
  'Hosted Supabase Advisors',
]);

const fullShaPattern = /^[0-9a-f]{40}$/;
const attemptIdPattern = /^hpra_[0-9a-f]{32}$/;

const canonicalJson = (value) => {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
};

const sha256 = (value) =>
  crypto.createHash('sha256').update(value, 'utf8').digest('hex');

export const isReleaseAttemptId = (value) =>
  typeof value === 'string' && attemptIdPattern.test(value);

const assertFullSha = (value, label) => {
  if (!fullShaPattern.test(value)) {
    throw new Error(`${label} must be a full 40-character lowercase SHA.`);
  }
};

const workflowDigest = async (workflowPath) => {
  const normalizedPath = workflowPath.replaceAll('\\', '/');
  const absolutePath = path.resolve(repositoryRoot, normalizedPath);
  const relative = path.relative(repositoryRoot, absolutePath);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`Workflow path escapes the repository: ${workflowPath}`);
  }
  const source = await fs.readFile(absolutePath, 'utf8');
  return sha256(source.replaceAll('\r\n', '\n'));
};

export const createReleaseAttempt = async ({
  repository,
  runId,
  runAttempt = '1',
  sourceSha,
  sourceRef,
  event,
  workflowPath,
  targetKind,
  targetEnvironment,
  targetProject = null,
  versionName = null,
  versionCode = null,
  releaseTag = null,
  state = 'created',
  createdAt = new Date().toISOString(),
}) => {
  assertFullSha(sourceSha, 'sourceSha');
  if (!releaseAttemptStates.includes(state)) {
    throw new Error(`Unsupported release attempt state: ${state}`);
  }
  if (!repository || !sourceRef || !event || !workflowPath || !targetKind) {
    throw new Error('repository, sourceRef, event, workflowPath, and targetKind are required.');
  }
  const digest = await workflowDigest(workflowPath);
  const identity = {
    schema_version: releaseAttemptSchemaVersion,
    repository,
    source_sha: sourceSha,
    source_ref: sourceRef,
    event,
    workflow_path: workflowPath.replaceAll('\\', '/'),
    workflow_sha256: digest,
    run_id: String(runId ?? ''),
    run_attempt: String(runAttempt ?? ''),
    target_kind: targetKind,
    target_environment: targetEnvironment,
    target_project: targetProject,
    version_name: versionName,
    version_code: versionCode,
    release_tag: releaseTag,
  };
  const attemptId = `hpra_${sha256(canonicalJson(identity)).slice(0, 32)}`;
  return {
    schema_version: releaseAttemptSchemaVersion,
    attempt_id: attemptId,
    state,
    created_at: createdAt,
    updated_at: createdAt,
    identity,
    transitions: [
      {
        from: null,
        to: state,
        at: createdAt,
        reason: 'attempt-created',
      },
    ],
    evidence: {},
  };
};

export const transitionReleaseAttempt = (
  attempt,
  nextState,
  {
    at = new Date().toISOString(),
    reason = 'state-transition',
    evidenceKey = null,
    evidence = null,
  } = {},
) => {
  if (!isReleaseAttemptId(attempt?.attempt_id)) {
    throw new Error('Attempt has an invalid attempt_id.');
  }
  if (!releaseAttemptStates.includes(nextState)) {
    throw new Error(`Unsupported release attempt state: ${nextState}`);
  }
  if (attempt.state === nextState) {
    const unchanged = {
      ...attempt,
      updated_at: at,
    };
    if (evidenceKey !== null) {
      return attachEvidence(unchanged, evidenceKey, evidence);
    }
    return unchanged;
  }
  if (terminalStates.has(attempt.state)) {
    throw new Error(`Cannot move terminal attempt ${attempt.attempt_id} from ${attempt.state}.`);
  }
  if (!transitions[attempt.state]?.has(nextState)) {
    throw new Error(`Invalid release attempt transition: ${attempt.state} -> ${nextState}.`);
  }
  const transitioned = {
    ...attempt,
    state: nextState,
    updated_at: at,
    transitions: [
      ...(attempt.transitions ?? []),
      {
        from: attempt.state,
        to: nextState,
        at,
        reason,
      },
    ],
  };
  if (evidenceKey !== null) {
    return attachEvidence(transitioned, evidenceKey, evidence);
  }
  return transitioned;
};

export const attachEvidence = (attempt, evidenceKey, evidence) => {
  if (!evidenceKeyPattern.test(evidenceKey)) {
    throw new Error(`Invalid evidence key: ${evidenceKey}`);
  }
  if (attempt.evidence?.[evidenceKey] !== undefined) {
    throw new Error(`Evidence key already exists on ${attempt.attempt_id}: ${evidenceKey}`);
  }
  return {
    ...attempt,
    evidence: {
      ...(attempt.evidence ?? {}),
      [evidenceKey]: evidence,
    },
  };
};

const requireEqual = (actual, expected, label) => {
  if (actual !== expected) {
    throw new Error(`${label} mismatch. Expected ${expected}, got ${actual}.`);
  }
};

export const validateBackendAggregate = ({ run, jobs, repository, sourceSha }) => {
  assertFullSha(sourceSha, 'sourceSha');
  requireEqual(run.name, 'Validate Google Backend and Release Contracts', 'workflow name');
  requireEqual(run.path, '.github/workflows/validate-google-backend.yml', 'workflow path');
  requireEqual(run.event, 'workflow_dispatch', 'workflow event');
  requireEqual(run.head_branch, 'main', 'workflow branch');
  requireEqual(run.head_sha, sourceSha, 'workflow source SHA');
  requireEqual(run.status, 'completed', 'workflow status');
  requireEqual(run.conclusion, 'success', 'workflow conclusion');
  if (repository) {
    requireEqual(run.repository?.full_name, repository, 'workflow repository');
  }

  const byName = new Map();
  for (const job of jobs) {
    if (!requiredBackendJobs.includes(job.name)) {
      throw new Error(`Unexpected backend validation job: ${job.name}`);
    }
    if (byName.has(job.name)) {
      throw new Error(`Duplicate backend validation job: ${job.name}`);
    }
    byName.set(job.name, job);
  }
  for (const name of requiredBackendJobs) {
    const job = byName.get(name);
    if (!job) {
      throw new Error(`Missing backend validation job: ${name}`);
    }
    requireEqual(job.status, 'completed', `${name} status`);
    requireEqual(job.conclusion, 'success', `${name} conclusion`);
  }

  return {
    schema_version: releaseAttemptSchemaVersion,
    type: 'backend-validation-aggregate',
    repository: repository ?? run.repository?.full_name,
    run_id: String(run.id),
    run_attempt: String(run.run_attempt ?? ''),
    run_url: run.html_url,
    workflow_name: run.name,
    workflow_path: run.path,
    event: run.event,
    head_branch: run.head_branch,
    head_sha: run.head_sha,
    conclusion: run.conclusion,
    required_jobs: requiredBackendJobs.map((name) => {
      const job = byName.get(name);
      return {
        id: String(job.id),
        name: job.name,
        status: job.status,
        conclusion: job.conclusion,
        started_at: job.started_at,
        completed_at: job.completed_at,
        html_url: job.html_url,
      };
    }),
  };
};

const githubApi = async (apiPath) => {
  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  if (!token) {
    throw new Error('GH_TOKEN or GITHUB_TOKEN is required for GitHub API reads.');
  }
  const response = await fetch(`https://api.github.com/${apiPath}`, {
    headers: {
      accept: 'application/vnd.github+json',
      authorization: `Bearer ${token}`,
      'x-github-api-version': '2022-11-28',
    },
  });
  if (!response.ok) {
    throw new Error(`GitHub API ${apiPath} failed: ${response.status} ${await response.text()}`);
  }
  return response.json();
};

const fetchRun = async (repository, runId) =>
  githubApi(`repos/${repository}/actions/runs/${runId}`);

const fetchJobs = async (repository, runId) => {
  const result = await githubApi(
    `repos/${repository}/actions/runs/${runId}/jobs?filter=latest&per_page=100`,
  );
  return result.jobs ?? [];
};

const fetchCompletedBackendRuns = async (repository, sourceSha) => {
  const result = await githubApi(
    `repos/${repository}/actions/workflows/validate-google-backend.yml/runs?head_sha=${sourceSha}&status=completed&per_page=20`,
  );
  return result.workflow_runs ?? [];
};

const writeJson = async (file, value) => {
  await fs.mkdir(path.dirname(path.resolve(file)), { recursive: true });
  await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
};

const appendGithubOutputs = async (outputs) => {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) {
    return;
  }
  const lines = Object.entries(outputs).map(([key, value]) => `${key}=${value}`);
  await fs.appendFile(outputPath, `${lines.join('\n')}\n`, 'utf8');
};

const parseArgs = (argv) => {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item.startsWith('--')) {
      throw new Error(`Unexpected argument: ${item}`);
    }
    const key = item.slice(2).replaceAll('-', '_');
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) {
      throw new Error(`Missing value for ${item}`);
    }
    args[key] = value;
    index += 1;
  }
  return args;
};

const command = process.argv[2];

if (command === 'create') {
  const args = parseArgs(process.argv.slice(3));
  const attempt = await createReleaseAttempt({
    repository: args.repository,
    runId: args.run_id,
    runAttempt: args.run_attempt,
    sourceSha: args.source_sha,
    sourceRef: args.source_ref,
    event: args.event,
    workflowPath: args.workflow_path,
    targetKind: args.target_kind,
    targetEnvironment: args.target_environment,
    targetProject: args.target_project ?? null,
    versionName: args.version_name ?? null,
    versionCode: args.version_code ?? null,
    releaseTag: args.release_tag ?? null,
    state: args.state ?? 'created',
  });
  if (args.output) {
    await writeJson(args.output, attempt);
  }
  await appendGithubOutputs({ attempt_id: attempt.attempt_id });
  console.log(attempt.attempt_id);
} else if (command === 'advance') {
  const args = parseArgs(process.argv.slice(3));
  const attempt = JSON.parse(await fs.readFile(args.attempt_file, 'utf8'));
  const evidence =
    args.evidence_file === undefined
      ? null
      : JSON.parse(await fs.readFile(args.evidence_file, 'utf8'));
  const advanced = transitionReleaseAttempt(attempt, args.state, {
    reason: args.reason ?? 'state-transition',
    evidenceKey: args.evidence_key ?? null,
    evidence,
  });
  if (args.output) {
    await writeJson(args.output, advanced);
  }
  await appendGithubOutputs({
    attempt_id: advanced.attempt_id,
    state: advanced.state,
  });
  console.log(`${advanced.attempt_id} ${advanced.state}`);
} else if (command === 'find-backend') {
  const args = parseArgs(process.argv.slice(3));
  const runs = await fetchCompletedBackendRuns(args.repository, args.source_sha);
  const errors = [];
  for (const run of runs) {
    try {
      const jobs = await fetchJobs(args.repository, run.id);
      const aggregate = validateBackendAggregate({
        run,
        jobs,
        repository: args.repository,
        sourceSha: args.source_sha,
      });
      if (args.output) {
        await writeJson(args.output, aggregate);
      }
      await appendGithubOutputs({
        run_id: aggregate.run_id,
        run_url: aggregate.run_url,
      });
      console.log(`Validated backend aggregate ${aggregate.run_id}`);
      process.exit(0);
    } catch (error) {
      errors.push(`${run.id}: ${error.message}`);
    }
  }
  throw new Error(
    `No exact backend validation aggregate passed for ${args.source_sha}.\n${errors.join('\n')}`,
  );
} else if (command === 'validate-backend') {
  const args = parseArgs(process.argv.slice(3));
  const run = await fetchRun(args.repository, args.run_id);
  const jobs = await fetchJobs(args.repository, args.run_id);
  const aggregate = validateBackendAggregate({
    run,
    jobs,
    repository: args.repository,
    sourceSha: args.source_sha,
  });
  if (args.output) {
    await writeJson(args.output, aggregate);
  }
  await appendGithubOutputs({
    run_id: aggregate.run_id,
    run_url: aggregate.run_url,
  });
  console.log(`Validated backend aggregate ${aggregate.run_id}`);
} else if (command !== undefined) {
  throw new Error(`Unknown command: ${command}`);
}
