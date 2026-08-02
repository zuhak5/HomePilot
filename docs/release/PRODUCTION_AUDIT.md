# HomePilot Production Audit

Audit date: 2026-07-26

## Configuration and repository safety

- The production configuration parses successfully and targets only Supabase
  project `iajvkvvvhwjdiuaufymh`.
- Production configuration, signing property files, JKS files, local
  environment files, build output, coverage output, and `dist/` are ignored.
- No configuration JSON, password, token, signing file, APK, build output, or
  production user data is committed.
- A candidate source scan found no JWT, Supabase secret key, Google client
  secret, or private-key material.
- Application ID, Google-only authentication model, signing certificate,
  version `1.3.0+15`, RLS ownership model, and minimum SDK were preserved.

## Application hardening

- Stable `AppFailureCode` values map diagnostics to localized user-facing
  messages. Raw backend diagnostics remain in sanitized logs.
- Direct `debugPrint` calls were replaced by a redacting logger that removes
  tokens, keys, PII, and backend payloads.
- Structured `NotificationMessageCode` and object arguments localize new and
  recognized legacy notification records in the active locale. Existing title
  and body snapshots remain for older clients; unknown controlled messages use
  a localized generic fallback.
- The centralized Supabase client, publishable-key validation, Google-only
  authentication, offline queue, optimistic-conflict handling, ownership
  enforcement, Realtime invalidation, and delete-account cleanup behavior are
  retained and covered by application and database tests.
- Weather and geocoding requests receive the selected locale where supported.
- The Drift schema is version 19 and includes the notification localization
  fields and language-preference migration path.

## Automated gates

| Gate | Result |
| --- | --- |
| Flutter formatting check | Passed |
| Strict analyzer | Passed, no issues |
| `dart fix --dry-run` | Nothing to fix |
| Serialized unit/widget/golden tests | 238 passed, one expected config skip |
| Production-config test with ignored config | Passed |
| Coverage | 64.96% excluding generated localization/Drift output |
| Local Supabase reset and seed | Passed |
| Local database lint | Passed |
| pgTAP | 107 passed |
| Local schema diff | Empty |
| Delete-account format/check/tests | Passed; three tests |
| npm audit/signatures | 0 vulnerabilities; 8 signatures; 8 attestations |
| Production migrations | Applied and histories match |
| Production database error lint | Clean |
| Production application-schema diff | Empty |
| Deployed Edge Function | Active, version 15, JWT verification enabled |

## Device validation exception

An Android API-36 Play Store emulator was prepared and reached an online,
provisioned launcher. The user then explicitly instructed the release process
to skip the emulator step. The emulator was shut down without installing the
application.

Consequently, this audit does **not** claim emulator installability, launch
behavior, Android Arabic glyph shaping, immediate language switching on device,
restart/sign-out persistence on device, CRUD/offline/background/deep-link smoke
results, notification delivery, or the two-disposable-account production
ownership/Realtime/delete-account isolation checks. Automated coverage for
these behaviors passed where present, but it is not a substitute for the
skipped production device checks.

Forward fix: run the signed artifact recorded in `RELEASE_REPORT.md` on an
API-36 Google Play emulator or physical disposable test device, execute the
English/Arabic smoke matrix, then perform the two-account isolation and
delete-account cleanup checks before treating every original production
completion criterion as closed.
