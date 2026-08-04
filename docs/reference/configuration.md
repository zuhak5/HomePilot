# Configuration Reference

## Principles

- Commit examples and schemas, not real environment values.
- Keep secrets out of Flutter-distributed configuration whenever possible.
- Treat configuration validation as code and test it.
- Fail closed for production-only requirements.
- Link mutable values to their source instead of duplicating them across documents.

## Flutter configuration

The application reads compile-time values supplied with `--dart-define-from-file`. Committed examples live under `config/`; real `config/*.json` files are ignored.

Current example keys include:

- `APP_ENV`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `GOOGLE_WEB_CLIENT_ID`
- `SENTRY_ENABLED`
- `SENTRY_DSN`
- `SENTRY_TRACES_SAMPLE_RATE`

Additional production-only keys may be validated by `test/prod_build_config_test.dart` and build scripts. Those sources are authoritative.

A Supabase publishable/anonymous key can be distributed to the client only when RLS and backend authorization are correct. A service-role key must never be included.

## Local Supabase

`supabase/config.toml` defines the local service ports, enabled providers, Storage bucket, Deno function entrypoints, and database major version.

The local API port is `55321` in the committed configuration. Development examples must stay aligned. Android emulators may need a host alias rather than `127.0.0.1`, but the port remains the configured local API port.

Google provider values are read from environment variables by the local Supabase runtime. Keep those values in ignored environment files or the shell environment.

## Android and Gradle

Android application IDs, flavors, build types, signing configuration, and production guards are defined under `android/`. The production application ID is `com.homepilot.app`; non-production flavors may add suffixes.

Signing material includes keystores, aliases, passwords, expected fingerprints, and `android/key.properties`. It belongs only in protected local/CI secret storage and is ignored by Git.

## Sentry

Client runtime uses enabled state, DSN, environment, release/build, and sampling configuration. CI release publication additionally requires protected Sentry credentials. Do not put Sentry auth tokens in Flutter config.

## Google services and ads

Google sign-in uses OAuth client identifiers appropriate to Android and backend token exchange. Google Mobile Ads uses the Android application ID in the manifest and ad-unit/configuration values through the monetization implementation. Use test identifiers outside production.

## GitHub Actions

Protected workflows consume environment secrets and variables for production configuration, Android signing, expected signer identity, Sentry, and release publication. Workflow logs and artifacts must not print the source secret values.

## VersionDeck

VersionDeck static assets contain no private token. Its deployment workflow uses the ephemeral GitHub token server-side in Actions to discover and verify releases before generating public data.

## Validation

Safe production-shape validation:

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

This does not validate real credentials or signing identity.

## Change checklist

When adding a key:

1. Define its owner and environment scope.
2. Decide whether it is safe to distribute.
3. Add a committed placeholder example.
4. Add validation and a useful failure message.
5. Add CI/protected environment configuration.
6. Update privacy and operations docs if data or third-party behavior changes.
7. Remove obsolete keys after backward-compatible rollout.
8. Verify `.gitignore` still protects real values.