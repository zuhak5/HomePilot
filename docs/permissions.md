# HomePilot Permission Capability & Education Architecture

## Overview

HomePilot uses a **capability-based permission model** rather than an unconditional permission wizard.

Principles:
1. **Educate before asking**: OS permission requests are prompted only after explicit user selection.
2. **Capability options**: Features like weather support manual city selection without requiring device location permissions.
3. **Least privilege**: Special access permissions (such as Android exact alarms) are requested contextually when specific features are enabled, not during first-run onboarding.
4. **Device-local state**: Permission education completion state (`permission_education_device_state_v3`) is stored locally on the device, avoiding false-positive suppression from account settings synced across devices.
5. **Location privacy**: Device coordinates are quantized to 2 decimal places prior to persistence, Open-Meteo queries, and account synchronization. Raw device coordinates are never stored or logged.

---

## Capabilities & Platform Mapping

| Capability | Platform API | Requirement | Fallback |
|---|---|---|---|
| **Weather Area** | Geolocator (`LocationPermission.whileInUse`) | Optional | Manual city selection or static location label |
| **Notifications** | `permission_handler` (`Permission.notification`) | Optional | In-app reminders and status badges |
| **Exact Reminder Timing** | `Permission.scheduleExactAlarm` (Android 12+) | Contextual | Approximate reminder alarm timing |

---

## Setup Sequences

### First-Run Dashboard Onboarding
Default sequence:
1. **Set your weather area** (Use current location / Choose city / Not now)
2. **Get maintenance reminders** (Enable notifications / Not now)

*Note: Exact alarms are excluded from first-run onboarding.*

### Contextual Exact Timing Prompt
Invoked when user enables "Precise reminder alarms" in Reminder Settings or task scheduling:
1. Explains Android special access requirement
2. Actions: Allow precise timing / Use approximate timing

Android does not expose exact alarms through the same runtime-permission dialog
used for location or notifications. It is special app access, so HomePilot's
explanation is followed by the system **Alarms & reminders** settings surface;
its appearance and whether it is a page or app list vary by Android/OEM. This is
why HomePilot does not request it automatically at startup.

---

## Privacy Boundary

- Device position requested with `LocationAccuracy.low`.
- Coordinates rounded to 2 decimal places (~1.1 km precision) before:
  - Saving home weather location
  - Synchronizing `user_settings`
  - Fetching Open-Meteo weather forecasts
  - Reverse-geocoding area names via Nominatim
- Raw GPS coordinates are discarded immediately after quantization.

---

## Data Model & Local Storage

- Local state key: `permission_education_device_state_v3` (stored in Drift `settings` table, explicitly excluded from `allowedRemoteSettingKeys`).
- Deferral cooldowns:
  - 1st defer: 7 days
  - 2nd+ defer: 30 days
- Legacy compatibility: Old clients reading `permission_education_seen_v2` remain supported, but new clients evaluate `v3` device state.
