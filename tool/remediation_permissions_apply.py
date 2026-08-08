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
    // Exact timing is user intent, not a claim that Android special access is
    // granted. The scheduler preserves the inexact fallback when it is missing.
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
        "      if (open) {\n        if (kind == AppPermissionKind.exactAlarms) {\n          await coordinator.request(kind);\n        } else {\n          await coordinator.openAppPermissionSettings();\n        }\n      }\n      return false;\n    }\n    if (state == AppPermissionState.unavailable) return false;",
        1,
    )
    main = main.replace(
        "      if (open) await coordinator.openAppPermissionSettings();\n    }\n    return false;",
        "      if (open) {\n        if (kind == AppPermissionKind.exactAlarms) {\n          await coordinator.request(kind);\n        } else {\n          await coordinator.openAppPermissionSettings();\n        }\n      }\n    }\n    return false;",
        1,
    )

    # Dashboard weather renders a real capability affordance independent from
    # the unrelated light/dark theme toggle.
    main = main.replace(
        "    final location =\n        ref.watch(homeLocationProvider).value ?? snapshot?.homeLocation;\n",
        "    final location =\n        ref.watch(homeLocationProvider).value ?? snapshot?.homeLocation;\n"
        "    final weatherCapability = ref\n        .watch(permissionEducationControllerProvider)\n        .setupSnapshot\n        ?.weather;\n",
        1,
    )
    main = main.replace(
        "              location: location,\n              localNow: themeNow,\n              isDark: brightness == Brightness.dark,",
        "              location: location,\n              capability: weatherCapability,\n              localNow: themeNow,\n              isDark: brightness == Brightness.dark,\n              onLocationAction: () => ref\n                  .read(permissionEducationControllerProvider.notifier)\n                  .initialize(source: PermissionEducationSource.weatherCard),",
        1,
    )
    main = main.replace(
        "    required this.location,\n    required this.localNow,",
        "    required this.location,\n    required this.capability,\n    required this.localNow,",
        1,
    )
    main = main.replace(
        "    required this.isDark,\n    required this.onToggleTheme,",
        "    required this.isDark,\n    required this.onLocationAction,\n    required this.onToggleTheme,",
        1,
    )
    main = main.replace(
        "  final HomeLocation? location;\n  final DateTime localNow;",
        "  final HomeLocation? location;\n  final WeatherAreaCapabilitySnapshot? capability;\n  final DateTime localNow;",
        1,
    )
    main = main.replace(
        "  final bool isDark;\n  final VoidCallback onToggleTheme;",
        "  final bool isDark;\n  final VoidCallback onLocationAction;\n  final VoidCallback onToggleTheme;",
        1,
    )
    # Both weather header layouts get an explicit location/configuration action.
    main = main.replace(
        "                      const SizedBox(width: HkSpacing.xs),\n                      _WeatherThemeButton(",
        "                      const SizedBox(width: HkSpacing.xs),\n"
        "                      _WeatherLocationButton(\n"
        "                        capability: capability,\n"
        "                        onPressed: onLocationAction,\n"
        "                      ),\n"
        "                      const SizedBox(width: HkSpacing.space4),\n"
        "                      _WeatherThemeButton(",
        1,
    )
    main = main.replace(
        "                              SizedBox(width: gap),\n                              _WeatherThemeButton(",
        "                              SizedBox(width: gap),\n"
        "                              _WeatherLocationButton(\n"
        "                                capability: capability,\n"
        "                                onPressed: onLocationAction,\n"
        "                              ),\n"
        "                              SizedBox(width: gap),\n"
        "                              _WeatherThemeButton(",
        1,
    )
    if "class _WeatherLocationButton" not in main:
        marker = "class _WeatherThemeButton extends StatelessWidget {"
        helper = r'''class _WeatherLocationButton extends StatelessWidget {
  const _WeatherLocationButton({required this.capability, required this.onPressed});

  final WeatherAreaCapabilitySnapshot? capability;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final degraded = capability?.effectiveState == EffectiveCapabilityState.degraded ||
        capability?.effectiveState == EffectiveCapabilityState.blocked ||
        capability?.effectiveState == EffectiveCapabilityState.notConfigured ||
        capability?.effectiveState == EffectiveCapabilityState.unavailable;
    final manual = capability?.mode == WeatherAreaMode.manual;
    final icon = manual
        ? Symbols.location_city_rounded
        : degraded
        ? Symbols.location_off_rounded
        : Symbols.my_location_rounded;
    final message = manual
        ? context.l10n.weatherLocationConfiguredManually
        : degraded
        ? context.l10n.weatherLocationNeedsAttention
        : context.l10n.weatherLocationSettings;
    return Tooltip(
      message: message,
      child: Semantics(
        button: true,
        label: message,
        child: SizedBox.square(
          dimension: 44,
          child: IconButton(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: 0.86),
              foregroundColor: degraded ? scheme.error : scheme.primary,
              shape: const CircleBorder(),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.12)),
            ),
            icon: Icon(icon, size: 22),
          ),
        ),
      ),
    );
  }
}

'''
        if marker not in main:
            raise RuntimeError("weather theme button marker changed")
        main = main.replace(marker, helper + marker, 1)

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
        "weatherLocationSettings": "Weather location settings",
        "weatherLocationNeedsAttention": "Weather location needs attention",
        "weatherLocationConfiguredManually": "Weather area is set manually",
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
        "weatherLocationSettings": "إعدادات موقع الطقس",
        "weatherLocationNeedsAttention": "موقع الطقس يحتاج إلى انتباه",
        "weatherLocationConfiguredManually": "تم تعيين منطقة الطقس يدوياً",
    })
    en_path.write_text(json.dumps(en, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    ar_path.write_text(json.dumps(ar, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    apply()
