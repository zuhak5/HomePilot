# Routes and Android Permissions

## Application routes

GoRouter definitions in `lib/main.dart` are authoritative. Current route patterns include:

```text
/
/assets
/assets/room/:roomId
/assets/thing/:assetId
/maintenance
/maintenance/:planId
/calendar
/more
/search
/trash
/statistics
/settings
/account
/backup
/notifications
```

Route parameters are untrusted input. Screens must handle missing, deleted, unauthorized, malformed, or not-yet-hydrated entities without crashing or exposing another account's data.

Route changes should update navigation tests, deep-link behavior, authentication gates, analytics/diagnostic route naming, and this reference.

## Android permissions

The current main manifest declares:

| Permission | Purpose | Review requirement |
|---|---|---|
| `INTERNET` | Supabase, authentication, ads, weather/network features, Sentry | Keep network payloads privacy-safe |
| `ACCESS_COARSE_LOCATION` | Approximate location-dependent features | Request in context; no precise/background expansion |
| `POST_NOTIFICATIONS` | Local maintenance reminders on supported Android versions | Explain value and handle denial |
| `SCHEDULE_EXACT_ALARM` | Time-sensitive reminders | Use only where exact delivery is justified |
| `RECEIVE_BOOT_COMPLETED` | Restore scheduled reminders after reboot | Keep receiver work bounded |
| `WAKE_LOCK` | Reliable bounded notification/background work | Avoid long-running holds |
| `VIBRATE` | Notification behavior | Respect user/channel settings |
| `FOREGROUND_SERVICE` | Foreground task support | Show required user-visible notification |
| `FOREGROUND_SERVICE_DATA_SYNC` | Foreground data synchronization | Keep service type aligned with actual work |

The manifest does not currently request fine location or background location.

## Android components

The application registers:

- `MainActivity` as the exported launcher activity.
- Flutter foreground-task service with `dataSync` type.
- Scheduled notification receiver.
- Scheduled notification boot receiver for boot, application replacement, and supported vendor quick-boot actions.

Android platform backup is disabled through manifest/application backup settings. HomePilot's own backup feature is separate.

## Permission design rules

- Ask only when the user reaches a feature that requires the permission.
- Explain the product value before the system prompt where appropriate.
- Provide useful degraded behavior after denial.
- Do not repeatedly pressure the user after denial.
- Distinguish denied, permanently denied, unavailable, and restricted states.
- Link to system settings only when the user can act there.
- Update `PRIVACY.md`, store disclosures, tests, and operations docs for any new permission.

## Exact alarms and notifications

Test permission and scheduling behavior across Android versions, notification channels, disabled notifications, reboot, application replacement, time-zone changes, daylight-saving transitions, maintenance completion, recurrence changes, and duplicate scheduling.

## Foreground and background work

Foreground service and Workmanager jobs should be bounded, idempotent, account-aware, and safe to restart. They must not expose user content in persistent notifications beyond what the user expects. Background work must stop or rebind safely during sign-out and account deletion.

## Location

Use approximate location only for the current feature requirement. Do not retain or transmit location beyond the documented purpose. Handle no permission, unavailable services, timeout, stale cache, and network failure. Introducing precise or background location requires a separate product and privacy decision.