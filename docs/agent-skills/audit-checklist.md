# Agent Skill Audit Checklist

Use this checklist before activating any downloaded or adapted skill.

## Identity and licensing

- [ ] Repository owner and publisher are verified.
- [ ] Source repository, path, and immutable commit are recorded.
- [ ] License permits vendoring and modification.
- [ ] Attribution and license files are retained.
- [ ] Maintenance and recent security history are reviewed.

## Scope and compatibility

- [ ] Skill targets the same language, framework, platform, and SDK generation.
- [ ] It supports an existing project rather than assuming greenfield setup.
- [ ] It does not introduce a competing state manager, router, backend, database, or build system.
- [ ] Commands match HomePilot's operating systems and tools.
- [ ] It does not assume Firebase where HomePilot uses Supabase.
- [ ] Native Android guidance cannot trigger for ordinary Flutter implementation.
- [ ] Sentry guidance matches `sentry_flutter` and HomePilot privacy controls.
- [ ] AdMob guidance preserves Flutter plugin usage and server-side verification.

## Instruction security

Reject or rewrite instructions that ask the agent to:

- [ ] Ignore the user, `AGENTS.md`, tests, or security controls.
- [ ] Read unrelated personal files or home-directory credentials.
- [ ] Collect or transmit environment variables unnecessarily.
- [ ] Upload repository content to an external service.
- [ ] Disable RLS, authentication, verification, signing, provenance, or scrubbing.
- [ ] Run destructive Git or database commands.
- [ ] Force-push or overwrite unrelated changes.
- [ ] Auto-publish releases, deployments, or remote configuration.
- [ ] Install additional code without review.
- [ ] Weaken tests merely to produce a passing result.

## Script review

Inspect every shell, PowerShell, Python, JavaScript, executable, package file, and referenced downloader.

- [ ] File-system access is bounded to the repository or documented staging path.
- [ ] Network access is necessary and restricted.
- [ ] Arguments are validated.
- [ ] Writes require explicit intent.
- [ ] Remote writes require explicit authorization.
- [ ] No credentials or configuration are printed.
- [ ] No `eval`, uncontrolled `exec`, unsafe shell interpolation, or arbitrary code download is present.
- [ ] No destructive reset/clean/delete command is hidden in helper scripts.
- [ ] Dependencies are pinned or otherwise reviewed.
- [ ] Deterministic tests exist for nontrivial scripts.

## HomePilot invariants

- [ ] Offline outbox intent and account binding are preserved.
- [ ] Drift migrations, backup compatibility, and generated files are handled correctly.
- [ ] RLS and cross-user denial remain intact.
- [ ] Account deletion retains recent same-identity reauthentication.
- [ ] Point and reward state remains server-authoritative and idempotent.
- [ ] Sentry remains free of user content and prohibited capture.
- [ ] No new permission or background behavior appears without review.
- [ ] VersionDeck remains independently verified and fail-closed.
- [ ] Production signing and release operations remain protected.

## Trigger quality

- [ ] Description states both what the skill does and when it applies.
- [ ] Positive trigger cases select it.
- [ ] Near-miss cases do not select it.
- [ ] Overlapping HomePilot skills have clear primary/supplementary precedence.
- [ ] Source-only skills are outside `.agents/skills/`.
- [ ] Renamed adaptations do not retain a confusing upstream name.

## Output and validation

- [ ] Skill requires scope, changed files, invariants, tests, unexecuted checks, and residual risk in the closeout.
- [ ] Local, local-service, CI-only, device-only, hosted, and protected validation are distinguished.
- [ ] It does not claim success for operations it cannot observe.
- [ ] All referenced paths and commands exist.
- [ ] Content checksum and review result are recorded in the lock file.

## Approval

Record reviewer, date, disposition (`active`, `source-only`, `adapted`, or `rejected`), required patches, and the next review trigger.