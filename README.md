# HomePilot

HomePilot is a Flutter app for tracking home assets and recurring maintenance with Supabase as the primary source of truth. Production builds require Google sign-in before the app shell is accessible. Durable user data lives in Supabase Auth, Postgres, Realtime, and private Storage; local Drift/SQLite storage is only used as an authenticated snapshot cache and offline mutation queue while the device is temporarily offline.

Email/password, magic-link, anonymous, guest, and local-only account flows are not supported in production. Existing local-only installations are expected to sign in with Google and complete the one-time authenticated import before legacy local data is retired.

## Synchronization

CRUD operations target Supabase first when the device is online. Authenticated offline edits are queued locally with stable record IDs and retried automatically after connectivity and session restoration. Supabase Realtime invalidates cached query results across devices so signed-in devices refresh after remote changes.

Conflicts must not silently overwrite remote data. When a pending edit was based on an older remote row version, HomePilot keeps the remote row current, preserves the pending local edit, and surfaces a resolve, discard, or retry path.

## Supabase Development

HomePilot uses the existing linked Supabase project `iajvkvvvhwjdiuaufymh`. Do not create or target another backend for this app. The Supabase project URL, publishable client key, and public Google Web OAuth client ID belong in Flutter configuration. Never add a secret key, `service_role` key, database password, Google client secret, or JWT secret to the app.

```powershell
npm ci
npx supabase start
flutter run --flavor dev --dart-define-from-file=config/dev.json
```

Google provider credentials for the local Supabase stack should be supplied through local environment variables. Hosted Google client secrets belong in the Supabase Auth provider configuration, not in Flutter config.

Schema, RLS, and Storage changes are versioned under `supabase/migrations`. Validate locally before linking any hosted project:

```powershell
npx supabase db lint --local --level error --fail-on error
npx supabase test db --local supabase/tests/database
npx supabase db push --dry-run
```

Pull and review the existing remote schema before adding migrations. Never use `db reset` on a linked project.

## Native Google Authentication

HomePilot uses `google_sign_in` 7.x on Android and passes the Google ID token to Supabase Auth. Google Auth Platform must contain:

- A Web application OAuth client. Put its client ID in `GOOGLE_WEB_CLIENT_ID` and configure the same client ID and secret in Supabase Authentication > Providers > Google.
- An Android OAuth client for every package/signing-certificate combination that is distributed or tested.

The production Android client values are:

```text
Package name: com.homepilot.app
Release SHA-1: 30:1A:59:03:D1:C6:33:44:BE:6A:4A:E5:15:51:F1:0B:0F:03:EE:53
Release SHA-256: 3E:98:0E:B5:BB:68:A5:19:90:E7:70:56:D4:E1:09:95:B2:E0:4F:B3:88:A7:34:42:B7:9A:46:C8:53:36:1E:51
```

Supabase's Google provider callback remains:

```text
https://iajvkvvvhwjdiuaufymh.supabase.co/auth/v1/callback
```

Native ID-token sign-in does not use `Additional Redirect URLs`.

## Release Build

Required local files:

- `android/key.properties`
- `android/app/homepilot-release.jks`

Both files are intentionally gitignored. Back them up somewhere secure; future app updates must be signed with the same keystore.

Build and verify:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --flavor prod --release `
  --dart-define-from-file=config/prod.json
```

Alternatively, use the guarded production build script:

```powershell
.\tool\build_prod.ps1
```

The production config must provide `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `GOOGLE_WEB_CLIENT_ID`. Builds fail fast when those values are missing.

## App Metadata

- App name: `HomePilot`
- Android application id: `com.homepilot.app`
- Current version: `1.3.0+15`
- Primary backend: Supabase Auth, Postgres, Realtime, and private Storage
- Local store: temporary authenticated Drift/SQLite cache and offline mutation queue

## Privacy

See [PRIVACY.md](PRIVACY.md) for account, cloud data, local cache, backup, weather, and notification behavior.
