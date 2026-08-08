import 'package:flutter/foundation.dart';
import 'package:homepilot/src/core/domain/models.dart';
import 'package:homepilot/src/core/services/app_permission_coordinator.dart'
    show AppPermissionState;

export 'package:homepilot/src/core/services/app_permission_coordinator.dart'
    show AppPermissionState;

enum PermissionCapability { deviceLocation, notifications, exactReminderTiming }

enum PermissionEducationSource {
  firstDashboardVisit,
  settings,
  weatherCard,
  reminderSettings,
  taskScheduling,
}

enum PermissionEducationOutcome {
  granted,
  configuredManually,
  deferred,
  blocked,
  unavailable,
  failed,
}

enum PermissionNextAction {
  request,
  openAppSettings,
  openLocationSettings,
  openExactAlarmSettings,
  chooseManualLocation,
  none,
}

enum WeatherAreaMode { none, manual, device }

@immutable
class WeatherAreaCapabilitySnapshot {
  const WeatherAreaCapabilitySnapshot({
    required this.selectedArea,
    required this.mode,
    required this.deviceLocationPermission,
    required this.locationServiceEnabled,
    required this.effectiveState,
    required this.nextAction,
  });

  final HomeLocation? selectedArea;
  final WeatherAreaMode mode;
  final AppPermissionState deviceLocationPermission;
  final bool locationServiceEnabled;
  final EffectiveCapabilityState effectiveState;
  final PermissionNextAction nextAction;

  bool get isConfigured => selectedArea != null;
}

@immutable
class NotificationCapabilitySnapshot {
  const NotificationCapabilitySnapshot({
    required this.preferences,
    required this.notificationPermission,
    required this.notificationsActuallyEnabled,
    required this.exactAlarmPermission,
    required this.canActuallyScheduleExact,
    required this.deviceReminderState,
    required this.exactTimingState,
    required this.inboxState,
    required this.weatherAlertState,
  });

  final NotificationPreferences preferences;
  final AppPermissionState notificationPermission;
  final bool notificationsActuallyEnabled;
  final AppPermissionState exactAlarmPermission;
  final bool canActuallyScheduleExact;
  final EffectiveCapabilityState deviceReminderState;
  final EffectiveCapabilityState exactTimingState;
  final EffectiveCapabilityState inboxState;
  final EffectiveCapabilityState weatherAlertState;
}

@immutable
class CapabilitySetupSnapshot {
  const CapabilitySetupSnapshot({required this.weather, required this.notifications});

  final WeatherAreaCapabilitySnapshot weather;
  final NotificationCapabilitySnapshot notifications;
}

WeatherAreaCapabilitySnapshot deriveWeatherAreaCapability({
  required HomeLocation? selectedArea,
  required AppPermissionState permission,
}) {
  final mode = selectedArea == null
      ? WeatherAreaMode.none
      : selectedArea.source == 'manual'
      ? WeatherAreaMode.manual
      : WeatherAreaMode.device;
  final serviceEnabled = permission != AppPermissionState.serviceDisabled;

  if (selectedArea == null) {
    return WeatherAreaCapabilitySnapshot(
      selectedArea: null,
      mode: WeatherAreaMode.none,
      deviceLocationPermission: permission,
      locationServiceEnabled: serviceEnabled,
      effectiveState: permission == AppPermissionState.unavailable
          ? EffectiveCapabilityState.unavailable
          : EffectiveCapabilityState.notConfigured,
      nextAction: permission == AppPermissionState.serviceDisabled
          ? PermissionNextAction.openLocationSettings
          : PermissionNextAction.chooseManualLocation,
    );
  }

  if (mode == WeatherAreaMode.manual) {
    return WeatherAreaCapabilitySnapshot(
      selectedArea: selectedArea,
      mode: mode,
      deviceLocationPermission: permission,
      locationServiceEnabled: serviceEnabled,
      effectiveState: EffectiveCapabilityState.active,
      nextAction: PermissionNextAction.none,
    );
  }

  final effective = switch (permission) {
    AppPermissionState.granted => EffectiveCapabilityState.active,
    AppPermissionState.unavailable => EffectiveCapabilityState.unavailable,
    AppPermissionState.denied ||
    AppPermissionState.permanentlyDenied ||
    AppPermissionState.restricted ||
    AppPermissionState.serviceDisabled => EffectiveCapabilityState.degraded,
  };
  final next = switch (permission) {
    AppPermissionState.granted => PermissionNextAction.none,
    AppPermissionState.denied => PermissionNextAction.request,
    AppPermissionState.permanentlyDenied || AppPermissionState.restricted =>
      PermissionNextAction.openAppSettings,
    AppPermissionState.serviceDisabled => PermissionNextAction.openLocationSettings,
    AppPermissionState.unavailable => PermissionNextAction.chooseManualLocation,
  };
  return WeatherAreaCapabilitySnapshot(
    selectedArea: selectedArea,
    mode: mode,
    deviceLocationPermission: permission,
    locationServiceEnabled: serviceEnabled,
    effectiveState: effective,
    nextAction: next,
  );
}

NotificationCapabilitySnapshot deriveNotificationCapability({
  required NotificationPreferences preferences,
  required AppPermissionState notificationPermission,
  required AppPermissionState exactAlarmPermission,
}) {
  final notificationAllowed = notificationPermission == AppPermissionState.granted;
  final exactAllowed = exactAlarmPermission == AppPermissionState.granted;
  final wantsDeviceReminders = preferences.allowsLocalReminders;

  final deviceState = !wantsDeviceReminders
      ? EffectiveCapabilityState.disabledByUser
      : notificationAllowed
      ? EffectiveCapabilityState.active
      : notificationPermission == AppPermissionState.unavailable
      ? EffectiveCapabilityState.unavailable
      : EffectiveCapabilityState.blocked;

  final exactState = !preferences.preferExactReminders
      ? EffectiveCapabilityState.disabledByUser
      : !wantsDeviceReminders
      ? EffectiveCapabilityState.disabledByUser
      : !notificationAllowed
      ? EffectiveCapabilityState.blocked
      : exactAllowed
      ? EffectiveCapabilityState.active
      : exactAlarmPermission == AppPermissionState.unavailable
      ? EffectiveCapabilityState.unavailable
      : EffectiveCapabilityState.degraded;

  return NotificationCapabilitySnapshot(
    preferences: preferences,
    notificationPermission: notificationPermission,
    notificationsActuallyEnabled: notificationAllowed,
    exactAlarmPermission: exactAlarmPermission,
    canActuallyScheduleExact: exactAllowed,
    deviceReminderState: deviceState,
    exactTimingState: exactState,
    inboxState: preferences.allowsInbox
        ? EffectiveCapabilityState.active
        : EffectiveCapabilityState.disabledByUser,
    weatherAlertState: preferences.allowsWeatherAlerts
        ? EffectiveCapabilityState.active
        : EffectiveCapabilityState.disabledByUser,
  );
}

@immutable
class CapabilityStatus {
  const CapabilityStatus({
    required this.capability,
    required this.permissionState,
    required this.outcome,
    required this.nextAction,
    this.userPreferenceEnabled = true,
    this.effectiveState,
  });

  final PermissionCapability capability;
  final AppPermissionState permissionState;
  final PermissionEducationOutcome outcome;
  final PermissionNextAction nextAction;
  final bool userPreferenceEnabled;
  final EffectiveCapabilityState? effectiveState;

  CapabilityStatus copyWith({
    PermissionCapability? capability,
    AppPermissionState? permissionState,
    PermissionEducationOutcome? outcome,
    PermissionNextAction? nextAction,
    bool? userPreferenceEnabled,
    EffectiveCapabilityState? effectiveState,
  }) {
    return CapabilityStatus(
      capability: capability ?? this.capability,
      permissionState: permissionState ?? this.permissionState,
      outcome: outcome ?? this.outcome,
      nextAction: nextAction ?? this.nextAction,
      userPreferenceEnabled:
          userPreferenceEnabled ?? this.userPreferenceEnabled,
      effectiveState: effectiveState ?? this.effectiveState,
    );
  }
}
