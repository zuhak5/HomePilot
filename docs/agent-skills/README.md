# HomePilot Agent Skills

## Purpose

Agent Skills provide task-specific reusable workflows. They complement, but do not replace, the always-active repository rules in `AGENTS.md` or detailed architecture in `docs/`.

The intended active project location is `.agents/skills/`. That directory is currently ignored and should not be activated until the source, audit, lock, and validation tooling described here is implemented.

## Skill layers

1. **Official exact-match skills**: maintained by the relevant technology project and directly compatible with HomePilot.
2. **Official source-only skills**: trustworthy upstream guidance that targets another platform or SDK generation and must be adapted.
3. **Audited community skills**: used only when no official source exists and after full review.
4. **HomePilot-specific skills**: encode repository architecture, invariants, validation, and protected operations.

## External sources to evaluate

- Flutter official Agent Skills.
- Dart official skills.
- Supabase general and Postgres best-practice skills.
- Selected GitHub CI/review skills.
- Android R8 analysis skill.
- Selected Sentry issue-triage skills.
- Google Mobile Ads Android skills as source-only material for a Flutter adaptation.

Do not install every skill from a repository. Select only workflows that match HomePilot.

## HomePilot-specific catalog

Priority skills:

- `homepilot-sync-change`
- `homepilot-persistence-migration`
- `homepilot-supabase-change`
- `homepilot-auth-lifecycle`
- `homepilot-monetization-change`
- `homepilot-backup-restore`
- `homepilot-versiondeck-change`
- `homepilot-release-pipeline`
- `homepilot-privacy-review`
- `homepilot-flutter-feature`
- `homepilot-ci-triage`
- `homepilot-documentation`

Additional technology-focused adaptations may cover Riverpod, routing, localization/RTL, Google authentication, Sentry Flutter, Android notifications/background work, and location/weather.

## Required skill structure

```text
.agents/skills/<skill-name>/
  SKILL.md
  references/      optional
  scripts/         optional
  assets/          optional
  SOURCE.json      required for vendored or adapted external skills
```

`SKILL.md` frontmatter should contain a unique lowercase hyphenated `name` and a description that states both the workflow and concrete triggering conditions.

## Design rules

- Prefer narrow, composable workflows.
- Keep global safety rules in `AGENTS.md`.
- Keep detailed architecture in `docs/`.
- Use references for large tables and checklists.
- Add scripts only when they provide deterministic value.
- Require an evidence-based closeout report.
- Default production, hosted, signing, release, and destructive operations to planning or local validation only.

## Installation sequence

1. Implement source policy and lock-file format.
2. Add download-to-staging and audit tooling.
3. Evaluate official Flutter, Dart, Supabase, Postgres, GitHub, Android, Sentry, and Google Ads sources.
4. Vendor only approved skills at immutable commits.
5. Create HomePilot adaptations under new names.
6. Add trigger test cases and structural/security validation.
7. Enable `.agents/skills/` in Git only after validation is enforced.
8. Exercise every skill on a real repository task.

## Ownership

Each skill requires a reviewer responsible for its subsystem. Review skills after architecture, dependency, command, workflow, permission, privacy, release, or data-contract changes and at least before major releases.

See `source-policy.md`, `audit-checklist.md`, and `update-runbook.md`.