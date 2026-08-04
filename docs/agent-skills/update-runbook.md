# Agent Skill Update Runbook

## Goal

Update external Agent Skills without allowing a moving upstream branch or automated installer to change active repository instructions silently.

## Preconditions

- The current active skill and lock entry are known.
- The upstream source, license, and intended target revision are identified.
- The update is performed on a dedicated branch.
- No automatic updater writes directly into `.agents/skills/`.

## Procedure

1. Resolve the new upstream full commit SHA and release/tag.
2. Download the candidate into a temporary or ignored staging directory.
3. Compare every changed `SKILL.md`, reference, script, asset, package file, and license.
4. Review upstream release notes and security advisories.
5. Re-run the complete audit checklist.
6. Verify platform and SDK compatibility with current HomePilot dependencies.
7. Apply local patches deliberately; do not overwrite HomePilot adaptations wholesale.
8. Recompute content checksums and update provenance metadata.
9. Run structural validation and script tests.
10. Run positive, near-miss, prohibited-action, and composition trigger cases.
11. Exercise the skill on a representative repository task without production access.
12. Update documentation when commands, triggers, or invariants change.
13. Open a dedicated pull request showing source revision, diff summary, audit result, tests, and residual risk.
14. Require subsystem-owner approval before merge.

## Review focus by source

### Flutter and Dart

Check minimum SDK versions, generated-code guidance, architecture assumptions, test commands, and whether a setup skill would overwrite existing configuration.

### Supabase and Postgres

Check CLI commands, migration policy, RLS guidance, service-role handling, destructive/linked operations, Edge Function runtime assumptions, and compatibility with HomePilot synchronization.

### Google Mobile Ads

Confirm whether guidance targets native Android or Flutter. Preserve current Flutter plugin APIs, consent, test units, SSV, opaque claims, replay protection, and server authority.

### Sentry

Confirm `sentry_flutter` compatibility and preserve HomePilot's disabled screenshots, replay, view hierarchy, raw HTTP capture, and strict scrubbing. Treat remote alert/project mutation as an explicit write.

### Android

Install only task-relevant skills. Check AGP/Gradle and Android-version assumptions and prevent Compose/native architecture guidance from replacing Flutter behavior.

### GitHub workflows

Preserve minimal permissions, protected environments, branch guards, signing verification, provenance, and no automatic production execution.

## Rollback

If an update causes incorrect selection or unsafe behavior:

1. Disable or remove the new active skill.
2. Restore the previous pinned content and lock entry.
3. Record the failed trigger or workflow case.
4. Add a regression case before attempting another update.
5. Review whether the skill should be forked, split, or replaced with a HomePilot-authored skill.

## Cadence

Check for updates monthly, before major framework/backend/SDK upgrades, after relevant security advisories, before major HomePilot releases, and after an agent-related near miss.

Do not update solely because upstream `main` changed.