import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart';
import '../../../../src/core/domain/contracts.dart';
import '../../../../src/core/domain/models.dart';
import '../../../../src/core/services/app_permission_coordinator.dart';
import '../data/device_permission_gateway.dart';
import '../data/permission_education_repository.dart';
import '../domain/permission_capability.dart';
import '../domain/permission_education_state.dart';

@immutable
class PermissionEducationControllerState {
  const PermissionEducationControllerState({
    this.deviceState = const PermissionEducationDeviceState(),
    this.relevantCapabilities = const [],
    this.activeCapability,
    this.capabilityStatuses = const {},
    this.setupSnapshot,
    this.isBusy = false,
    this.isVisible = false,
    this.source = PermissionEducationSource.firstDashboardVisit,
    this.awaitingSettingsReturn = false,
  });

  final PermissionEducationDeviceState deviceState;
  final List<PermissionCapability> relevantCapabilities;
  final PermissionCapability? activeCapability;
  final Map<PermissionCapability, CapabilityStatus> capabilityStatuses;
  final CapabilitySetupSnapshot? setupSnapshot;
  final bool isBusy;
  final bool isVisible;
  final PermissionEducationSource source;
  final bool awaitingSettingsReturn;

  PermissionEducationControllerState copyWith({
    PermissionEducationDeviceState? deviceState,
    List<PermissionCapability>? relevantCapabilities,
    PermissionCapability? activeCapability,
    bool clearActiveCapability = false,
    Map<PermissionCapability, CapabilityStatus>? capabilityStatuses,
    CapabilitySetupSnapshot? setupSnapshot,
    bool? isBusy,
    bool? isVisible,
    PermissionEducationSource? source,
    bool? awaitingSettingsReturn,
  }) {
    return PermissionEducationControllerState(
      deviceState: deviceState ?? this.deviceState,
      relevantCapabilities: relevantCapabilities ?? this.relevantCapabilities,
      activeCapability: clearActiveCapability
          ? null
          : activeCapability ?? this.activeCapability,
      capabilityStatuses: capabilityStatuses ?? this.capabilityStatuses,
      setupSnapshot: setupSnapshot ?? this.setupSnapshot,
      isBusy: isBusy ?? this.isBusy,
      isVisible: isVisible ?? this.isVisible,
      source: source ?? this.source,
      awaitingSettingsReturn:
          awaitingSettingsReturn ?? this.awaitingSettingsReturn,
    );
  }
}

final devicePermissionGatewayProvider = Provider<DevicePermissionGateway>((ref) {
  return FlutterDevicePermissionGateway(
    AppPermissionCoordinator(ref.watch(databaseProvider)),
  );
});

final permissionEducationRepositoryProvider =
    Provider<PermissionEducationRepository>((ref) {
      final database = ref.watch(databaseProvider);
      return DriftPermissionEducationRepository(database);
    });

final permissionEducationControllerProvider =
    NotifierProvider<
      PermissionEducationController,
      PermissionEducationControllerState
    >(PermissionEducationController.new);

class PermissionEducationController
    extends Notifier<PermissionEducationControllerState> {
  PermissionEducationController({
    DevicePermissionGateway? gateway,
    PermissionEducationRepository? repository,
    WeatherRepository? weatherRepository,
    SettingsRepository? settingsRepository,
    NotificationScheduler? notificationScheduler,
  }) : _overrideGateway = gateway,
       _overrideRepository = repository,
       _overrideWeatherRepository = weatherRepository,
       _overrideSettingsRepository = settingsRepository,
       _overrideNotificationScheduler = notificationScheduler;

  final DevicePermissionGateway? _overrideGateway;
  final PermissionEducationRepository? _overrideRepository;
  final WeatherRepository? _overrideWeatherRepository;
  final SettingsRepository? _overrideSettingsRepository;
  final NotificationScheduler? _overrideNotificationScheduler;

  DevicePermissionGateway get _gateway =>
      _overrideGateway ?? ref.read(devicePermissionGatewayProvider);
  PermissionEducationRepository get _repository =>
      _overrideRepository ?? ref.read(permissionEducationRepositoryProvider);
  WeatherRepository get _weatherRepository =>
      _overrideWeatherRepository ?? ref.read(weatherRepositoryProvider);
  SettingsRepository get _settingsRepository =>
      _overrideSettingsRepository ?? ref.read(settingsRepositoryProvider);
  NotificationScheduler get _notificationScheduler =>
      _overrideNotificationScheduler ?? ref.read(notificationSchedulerProvider);

  @override
  PermissionEducationControllerState build() =>
      const PermissionEducationControllerState();

  PermissionEducationControllerState get currentState => state;

  Future<void> initialize({
    PermissionEducationSource source =
        PermissionEducationSource.firstDashboardVisit,
    bool forceShow = false,
  }) async {
    final deviceState = await _repository.loadDeviceState();
    final (snapshot, statuses) = await _readCapabilityState(deviceState);
    final now = DateTime.now();
    final relevant = _buildRelevantCapabilities(
      source,
      snapshot,
      statuses,
      deviceState,
      now,
      forceShow: forceShow,
    );
    final active = relevant.isNotEmpty ? relevant.first : null;
    final shouldShow = forceShow || active != null;

    state = state.copyWith(
      deviceState: deviceState,
      relevantCapabilities: relevant,
      activeCapability: active,
      clearActiveCapability: active == null,
      capabilityStatuses: statuses,
      setupSnapshot: snapshot,
      isVisible: shouldShow,
      source: source,
      awaitingSettingsReturn: false,
    );

    if (shouldShow) {
      final updatedDeviceState = deviceState.copyWith(
        lastShownAt: now,
        showCount: deviceState.showCount + 1,
        source: source,
      );
      await _repository.saveDeviceState(updatedDeviceState);
      state = state.copyWith(deviceState: updatedDeviceState);
    } else if (!forceShow) {
      await _settingsRepository.setPermissionEducationSeen(true);
    }
  }

  Future<(CapabilitySetupSnapshot, Map<PermissionCapability, CapabilityStatus>)>
  _readCapabilityState(PermissionEducationDeviceState deviceState) async {
    final locationPermission = await _gateway.check(
      PermissionCapability.deviceLocation,
    );
    final notificationPermission = await _gateway.check(
      PermissionCapability.notifications,
    );
    final exactPermission = await _gateway.check(
      PermissionCapability.exactReminderTiming,
    );
    final selectedArea = await _settingsRepository.homeLocation();
    final preferences = await _settingsRepository.notificationPreferences();

    final weather = deriveWeatherAreaCapability(
      selectedArea: selectedArea,
      permission: locationPermission,
    );
    final notifications = deriveNotificationCapability(
      preferences: preferences,
      notificationPermission: notificationPermission,
      exactAlarmPermission: exactPermission,
    );
    final snapshot = CapabilitySetupSnapshot(
      weather: weather,
      notifications: notifications,
    );

    final statuses = <PermissionCapability, CapabilityStatus>{
      PermissionCapability.deviceLocation: CapabilityStatus(
        capability: PermissionCapability.deviceLocation,
        permissionState: locationPermission,
        outcome: weather.mode == WeatherAreaMode.manual
            ? PermissionEducationOutcome.configuredManually
            : _determineOutcome(
                PermissionCapability.deviceLocation,
                locationPermission,
                deviceState,
              ),
        nextAction: weather.nextAction,
        effectiveState: weather.effectiveState,
      ),
      PermissionCapability.notifications: CapabilityStatus(
        capability: PermissionCapability.notifications,
        permissionState: notificationPermission,
        outcome: _determineOutcome(
          PermissionCapability.notifications,
          notificationPermission,
          deviceState,
        ),
        nextAction: _determineNextAction(
          PermissionCapability.notifications,
          notificationPermission,
        ),
        userPreferenceEnabled: preferences.allowsLocalReminders,
        effectiveState: notifications.deviceReminderState,
      ),
      PermissionCapability.exactReminderTiming: CapabilityStatus(
        capability: PermissionCapability.exactReminderTiming,
        permissionState: exactPermission,
        outcome: _determineOutcome(
          PermissionCapability.exactReminderTiming,
          exactPermission,
          deviceState,
        ),
        nextAction: _determineNextAction(
          PermissionCapability.exactReminderTiming,
          exactPermission,
        ),
        userPreferenceEnabled: preferences.preferExactReminders,
        effectiveState: notifications.exactTimingState,
      ),
    };
    return (snapshot, statuses);
  }

  List<PermissionCapability> _buildRelevantCapabilities(
    PermissionEducationSource source,
    CapabilitySetupSnapshot snapshot,
    Map<PermissionCapability, CapabilityStatus> statuses,
    PermissionEducationDeviceState deviceState,
    DateTime now, {
    bool forceShow = false,
  }) {
    if (forceShow || source == PermissionEducationSource.settings) {
      return [
        PermissionCapability.deviceLocation,
        PermissionCapability.notifications,
        if (Platform.isAndroid) PermissionCapability.exactReminderTiming,
      ];
    }

    final caps = <PermissionCapability>[];
    if (source == PermissionEducationSource.firstDashboardVisit) {
      if (!snapshot.weather.isConfigured &&
          !deviceState.isDeferredFor(PermissionCapability.deviceLocation, now)) {
        caps.add(PermissionCapability.deviceLocation);
      }
      if (snapshot.notifications.deviceReminderState ==
              EffectiveCapabilityState.blocked &&
          !deviceState.isDeferredFor(PermissionCapability.notifications, now)) {
        caps.add(PermissionCapability.notifications);
      }
    } else if (source == PermissionEducationSource.weatherCard) {
      if (!snapshot.weather.isConfigured ||
          (snapshot.weather.mode == WeatherAreaMode.device &&
              snapshot.weather.effectiveState ==
                  EffectiveCapabilityState.degraded)) {
        caps.add(PermissionCapability.deviceLocation);
      }
    } else if (source == PermissionEducationSource.reminderSettings ||
        source == PermissionEducationSource.taskScheduling) {
      if (Platform.isAndroid &&
          snapshot.notifications.preferences.preferExactReminders &&
          snapshot.notifications.exactTimingState !=
              EffectiveCapabilityState.active) {
        caps.add(PermissionCapability.exactReminderTiming);
      }
    }
    return caps;
  }

  Future<void> useCurrentLocation() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true);
    try {
      final currentStatus = state
          .capabilityStatuses[PermissionCapability.deviceLocation]
          ?.permissionState;
      if (currentStatus == AppPermissionState.permanentlyDenied ||
          currentStatus == AppPermissionState.restricted ||
          currentStatus == AppPermissionState.serviceDisabled) {
        await openSettingsFor(PermissionCapability.deviceLocation);
        return;
      }
      final result = await _gateway.request(PermissionCapability.deviceLocation);
      if (result == AppPermissionState.granted) {
        await _weatherRepository.useCurrentLocationHomeArea();
        await _recordOutcome(
          PermissionCapability.deviceLocation,
          PermissionEducationOutcome.granted,
        );
        await _refreshCapabilityState();
        await _advanceNextStep();
      } else {
        await _recordOutcome(
          PermissionCapability.deviceLocation,
          result == AppPermissionState.unavailable
              ? PermissionEducationOutcome.unavailable
              : PermissionEducationOutcome.blocked,
        );
        await _refreshCapabilityState();
      }
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> chooseLocationManually(HomeLocation chosenLocation) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true);
    try {
      await _settingsRepository.setHomeLocation(chosenLocation);
      await _weatherRepository.refreshWeather();
      await _recordOutcome(
        PermissionCapability.deviceLocation,
        PermissionEducationOutcome.configuredManually,
      );
      // Re-read the real Android location permission. Manual configuration
      // satisfies weather-area capability but never impersonates an OS grant.
      await _refreshCapabilityState();
      await _advanceNextStep();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> enableNotifications() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true);
    try {
      final current = state
          .capabilityStatuses[PermissionCapability.notifications]
          ?.permissionState;
      if (current == AppPermissionState.permanentlyDenied ||
          current == AppPermissionState.restricted) {
        await openSettingsFor(PermissionCapability.notifications);
        return;
      }
      final result = await _gateway.request(PermissionCapability.notifications);
      await _recordOutcome(
        PermissionCapability.notifications,
        result == AppPermissionState.granted
            ? PermissionEducationOutcome.granted
            : result == AppPermissionState.unavailable
            ? PermissionEducationOutcome.unavailable
            : PermissionEducationOutcome.blocked,
      );
      await _refreshCapabilityState();
      if (result == AppPermissionState.granted) {
        await _notificationScheduler.refreshSchedules();
        await _advanceNextStep();
      }
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> enableExactTiming() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true);
    try {
      final result = await _gateway.request(
        PermissionCapability.exactReminderTiming,
      );
      await _recordOutcome(
        PermissionCapability.exactReminderTiming,
        result == AppPermissionState.granted
            ? PermissionEducationOutcome.granted
            : result == AppPermissionState.unavailable
            ? PermissionEducationOutcome.unavailable
            : PermissionEducationOutcome.blocked,
      );
      await _refreshCapabilityState();
      await _notificationScheduler.refreshSchedules();
      if (result == AppPermissionState.granted) await _advanceNextStep();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> deferCurrentStep() async {
    final currentCap = state.activeCapability;
    if (currentCap == null) return;
    final now = DateTime.now();
    final steps = Map<PermissionCapability, StepEducationState>.from(
      state.deviceState.steps,
    );
    final existing = steps[currentCap] ?? const StepEducationState();
    steps[currentCap] = existing.copyWith(
      educationSeen: true,
      deferredAt: now,
      deferCount: existing.deferCount + 1,
      lastOutcome: PermissionEducationOutcome.deferred,
    );
    final updated = state.deviceState.copyWith(steps: steps);
    await _repository.saveDeviceState(updated);
    state = state.copyWith(deviceState: updated);
    await _advanceNextStep();
  }

  void finishLater() {
    state = state.copyWith(isVisible: false, awaitingSettingsReturn: false);
  }

  Future<void> openSettingsFor(PermissionCapability capability) async {
    state = state.copyWith(awaitingSettingsReturn: true);
    await _gateway.openSettings(capability);
  }

  Future<void> openSettingsForCurrent() async {
    final capability = state.activeCapability;
    if (capability != null) await openSettingsFor(capability);
  }

  Future<void> handleAppResume() async {
    if (!state.awaitingSettingsReturn && !state.isVisible) return;
    final (snapshot, statuses) = await _readCapabilityState(state.deviceState);
    final active = state.activeCapability;
    state = state.copyWith(
      awaitingSettingsReturn: false,
      setupSnapshot: snapshot,
      capabilityStatuses: statuses,
    );
    if (active != null &&
        statuses[active]?.effectiveState == EffectiveCapabilityState.active) {
      await _advanceNextStep();
    }
  }

  Future<void> _refreshCapabilityState() async {
    final (snapshot, statuses) = await _readCapabilityState(state.deviceState);
    state = state.copyWith(
      setupSnapshot: snapshot,
      capabilityStatuses: statuses,
    );
  }

  Future<void> _advanceNextStep() async {
    final caps = state.relevantCapabilities;
    final active = state.activeCapability;
    if (active == null || caps.isEmpty) {
      await _settingsRepository.setPermissionEducationSeen(true);
      finishLater();
      return;
    }
    final index = caps.indexOf(active);
    if (index >= 0 && index < caps.length - 1) {
      state = state.copyWith(activeCapability: caps[index + 1]);
      return;
    }
    final updated = state.deviceState.copyWith(completedAt: DateTime.now());
    await _repository.saveDeviceState(updated);
    await _settingsRepository.setPermissionEducationSeen(true);
    state = state.copyWith(deviceState: updated);
    finishLater();
  }

  Future<void> _recordOutcome(
    PermissionCapability capability,
    PermissionEducationOutcome outcome,
  ) async {
    final steps = Map<PermissionCapability, StepEducationState>.from(
      state.deviceState.steps,
    );
    final existing = steps[capability] ?? const StepEducationState();
    steps[capability] = existing.copyWith(
      educationSeen: true,
      lastOutcome: outcome,
    );
    final updated = state.deviceState.copyWith(steps: steps);
    await _repository.saveDeviceState(updated);
    state = state.copyWith(deviceState: updated);
  }

  PermissionEducationOutcome _determineOutcome(
    PermissionCapability capability,
    AppPermissionState permissionState,
    PermissionEducationDeviceState deviceState,
  ) {
    if (permissionState == AppPermissionState.granted) {
      return PermissionEducationOutcome.granted;
    }
    if (permissionState == AppPermissionState.unavailable) {
      return PermissionEducationOutcome.unavailable;
    }
    return deviceState.steps[capability]?.lastOutcome ??
        PermissionEducationOutcome.deferred;
  }

  PermissionNextAction _determineNextAction(
    PermissionCapability capability,
    AppPermissionState permissionState,
  ) {
    return switch (permissionState) {
      AppPermissionState.granted => PermissionNextAction.none,
      AppPermissionState.denied => capability ==
              PermissionCapability.exactReminderTiming
          ? PermissionNextAction.openExactAlarmSettings
          : PermissionNextAction.request,
      AppPermissionState.permanentlyDenied => switch (capability) {
        PermissionCapability.deviceLocation =>
          PermissionNextAction.openAppSettings,
        PermissionCapability.notifications => PermissionNextAction.openAppSettings,
        PermissionCapability.exactReminderTiming =>
          PermissionNextAction.openExactAlarmSettings,
      },
      AppPermissionState.restricted => PermissionNextAction.none,
      AppPermissionState.serviceDisabled =>
        PermissionNextAction.openLocationSettings,
      AppPermissionState.unavailable => PermissionNextAction.none,
    };
  }
}
