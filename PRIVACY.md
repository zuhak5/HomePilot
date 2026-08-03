# HomePilot Privacy

HomePilot requires Google sign-in in production builds. Supabase is the primary system of record for profiles, rooms, categories, home assets, asset details, tags, maintenance plans, completion history, notification inbox, app and notification preferences, home location, streak state, and uploaded profile or asset images.

## Account And Cloud Data

Supabase Auth provides Google authentication. Email/password, magic-link, anonymous, guest, and local-only account flows are not offered in production. Cloud records are associated with the authenticated user and protected by database Row Level Security. Media is stored in the private `user-media` bucket with owner-only access.

The app stores its Supabase session through Android secure storage. It does not manually store Google access or refresh tokens.

## Local Cache And Offline Queue

HomePilot stores an authenticated snapshot cache and offline mutation queue on the device so signed-in users can keep working during temporary network loss. The local cache is not an independent backend and is not intended for device-independent local operation. Offline changes are retried automatically when connectivity and authentication return.

Signing out removes the active session and blocks the app shell until Google sign-in succeeds again. Account deletion requires a fresh Google authentication and removes the Supabase Auth account, associated cloud and archived rows, private media, the local application database, downloaded media, avatar caches, and backups stored in HomePilot's app-private backup folder.

## Data Stored On Device

HomePilot may temporarily store the following data locally for the signed-in account:

- Rooms, categories, assets, notes, and photo file paths
- Maintenance plans, due dates, priorities, recurrence rules, and completion records
- Pending offline mutations and retry state
- Notification schedule metadata
- Theme, language, home location, weather cache, and app settings
- Notification inbox and preferences
- Streak state
- Whether the current install has completed its first app session, used only to suppress an early interstitial ad

## Advertising, Consent, And Points

HomePilot uses the Google Mobile Ads SDK to display clearly labeled native, interstitial, rewarded, and rewarded-interstitial ads. Google and its advertising partners may process device identifiers, IP address, diagnostic information, ad interactions, and approximate location inferred from the network, subject to the user's consent choices and Google's policies. HomePilot requests consent information before requesting ads. Where required, the app presents Google's consent form and exposes **Settings → Privacy choices** so the user can review or change those choices. Core HomePilot features remain available when personalized advertising is not permitted.

Rewarded ads are optional. Before an ad is shown, HomePilot creates an opaque reward claim associated with the signed-in account. Google sends a signed server-to-server callback containing the claim identifier, user identifier, ad unit, reward amount, and transaction identifier. HomePilot verifies Google's ECDSA signature and expected reward details before adding points. The app never credits a reward based only on a client callback.

The Supabase account stores a points wallet, immutable points transaction history, reward claims, and creation-operation identifiers. A new account starts with 7 points, the wallet is capped at 20 points, and creating an ordinary item or task costs 1 point. Safety-category creations and all completion, editing, deletion, and emergency operations are free. Only the signed-in user can read their wallet and transaction history.

## Monetization Analytics

HomePilot records a limited set of account-scoped monetization events in Supabase: native-ad impression or click, interstitial display, rewarded-ad completion pending server verification, points shortage, and successful points debit. Event properties are restricted to operational fields such as screen placement, ad unit, reward amount, entity type, cooldown state, and resulting balance. These events do not contain maintenance notes, item names, room names, or ad-server signatures.

## Crash And Performance Diagnostics

HomePilot uses Sentry in its European Union data region to receive crash reports and sampled performance diagnostics. These diagnostics are used to identify application defects, failed background or restore operations, startup regressions, and unusually slow application operations.

Sentry events may include the HomePilot version and build, application environment, operating-system and device model information, anonymous application-run identifier, normalized screen or operation name, error type, stack trace, timing measurements, retry state, and coarse operational counts. The application does not attach a Sentry user identity or send the Supabase user ID, email address, Google identity, authentication tokens, request or response bodies, maintenance notes, room or asset names, precise location, local file paths, notification payloads, screenshots, view hierarchy, session replay, profiling data, or exported diagnostic ZIP files.

HomePilot applies an allowlist and redaction pass before Sentry events, transactions, and breadcrumbs are submitted. Expected conditions such as cancellation, offline state, authentication expiry, permission denial, and synchronization conflicts are normally suppressed rather than reported as defects. Sentry-side data scrubbing and prevention of IP-address storage are also enabled. Diagnostic transmission is isolated from application behavior: failure to initialize or contact Sentry does not block HomePilot startup, authentication, local data access, synchronization recovery, or account deletion.

## Backups And Photos

HomePilot can create local backup ZIP files when the user enables or requests backups. Backup files remain in app-private storage unless the user explicitly shares one, and app-private copies are removed during account deletion. Copies previously shared or exported outside HomePilot are outside the app's control and must be deleted by the user. Restores happen only from a user-selected backup file and require an authenticated account import path. Asset photos and profile images are selected by the user from the device and uploaded to private Supabase Storage when attached to cloud records.

## Notifications

Maintenance reminders use Android notification permissions and local scheduling. Notification metadata is used to remind the user about due, overdue, and critical maintenance tasks.

## Weather And Location

Weather is optional. Searching for a place sends the search text to Open-Meteo's geocoding service. Refreshing weather sends the selected coordinates to Open-Meteo. If the user chooses device location, Android supplies an approximate location and the app sends those coordinates to OpenStreetMap Nominatim to derive a readable area label. HomePilot does not collect location in the background.

## Network Access

The app uses network access for Google authentication, Supabase data access, Realtime refreshes, private media upload/download, Google Mobile Ads and consent messaging, Sentry crash and performance diagnostics, weather, and location labels. During temporary network loss, authenticated edits are cached locally and synchronized after reconnect. Point-gated item and task creation requires an online atomic server transaction; the editor remains open as a draft when that transaction cannot be completed.
