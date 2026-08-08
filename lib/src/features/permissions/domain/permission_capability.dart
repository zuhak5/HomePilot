import 'package:flutter/foundation.dart';
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

@immutable
class CapabilityStatus {
  const CapabilityStatus({
    required this.capability,
    required this.permissionState,
    required this.outcome,
    required this.nextAction,
    this.userPreferenceEnabled = true,
  });

  final PermissionCapability capability;
  final AppPermissionState permissionState;
  final PermissionEducationOutcome outcome;
  final PermissionNextAction nextAction;
  final bool userPreferenceEnabled;

  CapabilityStatus copyWith({
    PermissionCapability? capability,
    AppPermissionState? permissionState,
    PermissionEducationOutcome? outcome,
    PermissionNextAction? nextAction,
    bool? userPreferenceEnabled,
  }) {
    return CapabilityStatus(
      capability: capability ?? this.capability,
      permissionState: permissionState ?? this.permissionState,
      outcome: outcome ?? this.outcome,
      nextAction: nextAction ?? this.nextAction,
      userPreferenceEnabled:
          userPreferenceEnabled ?? this.userPreferenceEnabled,
    );
  }
}
