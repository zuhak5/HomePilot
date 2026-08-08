#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def apply() -> None:
    setup_path = "lib/src/features/permissions/presentation/permission_setup_screen.dart"
    setup = _read(setup_path)
    setup = setup.replace(
        "onOpenSettings: () => notifier.openSettingsForCurrent(),",
        "onOpenSettings: () => notifier.openSettingsFor(cap),",
    )
    setup = setup.replace(
        "    final isGranted = permState == AppPermissionState.granted;\n    final isBlocked =\n        permState == AppPermissionState.permanentlyDenied ||\n        permState == AppPermissionState.serviceDisabled;",
        "    final effectiveState = status?.effectiveState;\n    final isGranted = effectiveState == EffectiveCapabilityState.active;\n    final isBlocked =\n        effectiveState == EffectiveCapabilityState.blocked ||\n        permState == AppPermissionState.permanentlyDenied ||\n        permState == AppPermissionState.restricted ||\n        permState == AppPermissionState.serviceDisabled;",
    )
    setup = setup.replace(
        "                    isGranted ? 'Allowed' : (isBlocked ? 'Blocked' : 'Not set'),",
        "                    _statusLabel(context, capability, status),",
    )
    setup = setup.replace(
        "                      icon: const Icon(Symbols.check_rounded, size: 18),\n                      label: Text(switch (capability) {",
        "                      icon: Icon(switch (capability) {\n                        PermissionCapability.deviceLocation => Symbols.my_location_rounded,\n                        PermissionCapability.notifications => Symbols.notifications_active_rounded,\n                        PermissionCapability.exactReminderTiming => Symbols.alarm_on_rounded,\n                      }, size: 18),\n                      label: Text(switch (capability) {",
    )
    if "String _statusLabel(" not in setup:
        setup += r'''

String _statusLabel(
  BuildContext context,
  PermissionCapability capability,
  CapabilityStatus? status,
) {
  if (capability == PermissionCapability.deviceLocation &&
      status?.outcome == PermissionEducationOutcome.configuredManually) {
    return context.l10n.capabilityStatusConfiguredManually;
  }
  return switch (status?.effectiveState) {
    EffectiveCapabilityState.active => context.l10n.capabilityStatusActive,
    EffectiveCapabilityState.degraded => context.l10n.capabilityStatusDegraded,
    EffectiveCapabilityState.blocked => context.l10n.capabilityStatusBlocked,
    EffectiveCapabilityState.disabledByUser => context.l10n.capabilityStatusDisabled,
    EffectiveCapabilityState.notConfigured =>
      context.l10n.capabilityStatusNotConfigured,
    EffectiveCapabilityState.unavailable => context.l10n.capabilityStatusUnavailable,
    null => switch (status?.permissionState) {
      AppPermissionState.granted => context.l10n.capabilityStatusActive,
      AppPermissionState.permanentlyDenied ||
      AppPermissionState.restricted ||
      AppPermissionState.serviceDisabled => context.l10n.capabilityStatusBlocked,
      AppPermissionState.unavailable => context.l10n.capabilityStatusUnavailable,
      _ => context.l10n.capabilityStatusNotConfigured,
    },
  };
}
'''
    _write(setup_path, setup)

    main_path = "lib/main.dart"
    main = _read(main_path)
    pattern = re.compile(
        r"  Future<void> _saveNotificationPreferences\(.*?\n  Future<void> _sendTestNotification\(",
        re.S,
    )
    replacement = r'''  Future<void> _saveNotificationPreferences(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences,
  ) async {
    final repository = ref.read(settingsRepositoryProvider);
    final current = await repository.notificationPreferences();
    if (preferences.allowsLocalReminders && !current.allowsLocalReminders) {
      await _enableNotifications(context, ref, preferences);
      return;
    }
    if (preferences.preferExactReminders && !current.preferExactReminders) {
      await _enableExactReminderPreference(context, ref, preferences);
      return;
    }
    await _persistNotificationPreferences(context, ref, preferences);
  }

  Future<void> _persistNotificationPreferences(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences,
  ) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setNotificationPreferences(preferences);
      ref.invalidate(notificationPreferencesProvider);
      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      await scheduler.refreshSchedules();
      ref.invalidate(notificationPermissionStateProvider);
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(context.l10n.notificationSettingsUpdated),
      );
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(
            context,
            error,
            fallback: AppFailureCode.notificationSetup,
          ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _enableNotifications(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences,
  ) async {
    if (preferences.allowsLocalReminders) {
      final allowed = await _ensurePermission(
        context,
        ref,
        kind: AppPermissionKind.notifications,
        title: context.l10n.allowHomePilotReminders,
        message: context.l10n.notificationsPermissionBody,
      );
      if (!allowed || !context.mounted) return;
    }
    await _persistNotificationPreferences(context, ref, preferences);
  }

  Future<void> _enableExactReminderPreference(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences,
  ) async {
    final coordinator = ref.read(permissionCoordinatorProvider);
    final notifications = await coordinator.check(AppPermissionKind.notifications);
    if (notifications == AppPermissionState.granted) {
      final exactAllowed = await _ensurePermission(
        context,
        ref,
        kind: AppPermissionKind.exactAlarms,
        title: context.l10n.allowPreciseReminderTiming,
        message: context.l10n.preciseAlarmsPermissionBody,
      );
      if (!exactAllowed && context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.approximateReminderTimingWarning),
        );
      }
    }
    // Exact timing is a user preference, not a claim that Android special
    // access is granted. The scheduler will use the inexact fallback whenever
    // canScheduleExactNotifications() is false.
    if (context.mounted) {
      await _persistNotificationPreferences(context, ref, preferences);
    }
  }

  Future<void> _sendTestNotification('''
    main, count = pattern.subn(replacement, main, count=1)
    if count != 1:
        raise RuntimeError(f"notification settings block changed: {count}")

    setup_open = re.compile(
        r"  Future<void> _openPermissionSetup\(BuildContext context, WidgetRef ref\) async \{.*?\n  \}\n\n  Future<void> _setAppLanguage\(",
        re.S,
    )
    main, count = setup_open.subn(
        "  Future<void> _openPermissionSetup(BuildContext context, WidgetRef ref) async {\n"
        "    context.go('/permissions/setup');\n"
        "  }\n\n"
        "  Future<void> _setAppLanguage(",
        main,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"permission setup opener changed: {count}")

    main = main.replace(
        "      if (open) await coordinator.openAppPermissionSettings();\n      return false;\n    }\n    if (state == AppPermissionState.unavailable) return false;",
        "      if (open) {\n        if (kind == AppPermissionKind.exactAlarms) {\n          await coordinator.openExactAlarmSettings();\n        } else {\n          await coordinator.openAppPermissionSettings();\n        }\n      }\n      return false;\n    }\n    if (state == AppPermissionState.unavailable) return false;",
        1,
    )
    main = main.replace(
        "      if (open) await coordinator.openAppPermissionSettings();\n    }\n    return false;",
        "      if (open) {\n        if (kind == AppPermissionKind.exactAlarms) {\n          await coordinator.openExactAlarmSettings();\n        } else {\n          await coordinator.openAppPermissionSettings();\n        }\n      }\n    }\n    return false;",
        1,
    )
    _write(main_path, main)

    en_path = ROOT / "lib/l10n/app_en.arb"
    ar_path = ROOT / "lib/l10n/app_ar.arb"
    en = json.loads(en_path.read_text(encoding="utf-8"))
    ar = json.loads(ar_path.read_text(encoding="utf-8"))
    en.update({
        "permissionSetup": "Permissions & setup",
        "permissionSetupSubtitle": "Set up weather location, notifications, and reminder timing.",
        "capabilityStatusActive": "Active",
        "capabilityStatusConfiguredManually": "Configured manually",
        "capabilityStatusDegraded": "Limited",
        "capabilityStatusBlocked": "Blocked",
        "capabilityStatusDisabled": "Off",
        "capabilityStatusNotConfigured": "Not configured",
        "capabilityStatusUnavailable": "Unavailable",
    })
    ar.update({
        "permissionSetup": "الأذونات والإعداد",
        "permissionSetupSubtitle": "اضبط موقع الطقس والإشعارات وتوقيت التذكيرات.",
        "capabilityStatusActive": "نشط",
        "capabilityStatusConfiguredManually": "تم الإعداد يدوياً",
        "capabilityStatusDegraded": "محدود",
        "capabilityStatusBlocked": "محظور",
        "capabilityStatusDisabled": "متوقف",
        "capabilityStatusNotConfigured": "غير مُعد",
        "capabilityStatusUnavailable": "غير متاح",
    })
    en_path.write_text(json.dumps(en, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    ar_path.write_text(json.dumps(ar, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    apply()
