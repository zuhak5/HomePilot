import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../src/core/domain/contracts.dart';
import '../../../../src/core/domain/models.dart';

import '../../../../main.dart';
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
    this.isBusy = false,
    this.isVisible = false,
    this.source = PermissionEducationSource.firstDashboardVisit,
    this.awaitingSettingsReturn = false,
  });

  final PermissionEducationDeviceState deviceState;
  final List<PermissionCapability> relevantCapabilities;
  final PermissionCapability? activeCapability;
  final Map<PermissionCapability, CapabilityStatus> capabilityStatuses;
  final bool isBusy;
  final bool isVisible;
  final PermissionEducationSource source;
  final bool awaitingSettingsReturn;

  PermissionEducationControllerState copyWith({
    PermissionEducationDeviceState? deviceState,
    List<PermissionCapability>? relevantCapabilities,
    PermissionCapability? activeCapability,
    Map<PermissionCapability, CapabilityStatus>? capabilityStatuses,
    bool? isBusy,
    bool? isVisible,
    PermissionEducationSource? source,
    bool? awaitingSettingsReturn,
  }) {
    return PermissionEducationControllerState(
      deviceState: deviceState ?? this.deviceState,
      relevantCapabilities: relevantCapabilities ?? this.relevantCapabilities,
      activeCapability: activeCapability ?? this.activeCapability,
      capabilityStatuses: capabilityStatuses ?? this.capabilityStatuses,
      isBusy: isBusy ?? this.isBusy,
      isVisible: isVisible ?? this.isVisible,
      source: source ?? this.source,
      awaitingSettingsReturn:
          awaitingSettingsReturn ?? this.awaitingSettingsReturn,
    );
  }
}

final devicePermissionGatewayProvider = Provider<DevicePermissionGateway>((
  ref,
) {
  return const FlutterDevicePermissionGateway();
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
    final now = DateTime.now();

    final statuses = <PermissionCapability, CapabilityStatus>{};
    for (final cap in PermissionCapability.values) {
      final permState = await _gateway.check(cap);
      final outcome = _determineOutcome(cap, permState, deviceState);
      final nextAction = _determineNextAction(cap, permState);
      statuses[cap] = CapabilityStatus(
        capability: cap,
        permissionState: permState,
        outcome: outcome,
        nextAction: nextAction,
      );
    }

    final relevant = _buildRelevantCapabilities(
      source,
      statuses,
      deviceState,
      now,
      forceShow: forceShow,
    );

    final active = relevant.isNotEmpty ? relevant.first : null;
    final shouldShow = forceShow || (relevant.isNotEmpty && active != null);

    state = state.copyWith(
      deviceState: deviceState,
      relevantCapabilities: relevant,
      activeCapability: active,
      capabilityStatuses: statuses,
      isVisible: shouldShow,
      source: source,
    );

    if (shouldShow) {
      await _repository.saveDeviceState(
        deviceState.copyWith(
          lastShownAt: now,
          showCount: deviceState.showCount + 1,
          source: source,
        ),
      );
    } else if (!forceShow) {
      await _settingsRepository.setPermissionEducationSeen(true);
    }
  }

  List<PermissionCapability> _buildRelevantCapabilities(
    PermissionEducationSource source,
    Map<PermissionCapability, CapabilityStatus> statuses,
    PermissionEducationDeviceState deviceState,
    DateTime now, {
    bool forceShow = false,
  }) {
    final caps = <PermissionCapability>[];

    if (source == PermissionEducationSource.firstDashboardVisit) {
      for (final cap in [
        PermissionCapability.deviceLocation,
        PermissionCapability.notifications,
      ]) {
        final status = statuses[cap];
        if (status != null &&
            status.permissionState != AppPermissionState.granted) {
          if (forceShow || !deviceState.isDeferredFor(cap, now)) {
            caps.add(cap);
          }
        }
      }
    } else if (source == PermissionEducationSource.reminderSettings ||
        source == PermissionEducationSource.taskScheduling) {
      if (Platform.isAndroid) {
        final exactStatus = statuses[PermissionCapability.exactReminderTiming];
        if (exactStatus != null &&
            exactStatus.permissionState != AppPermissionState.granted) {
          caps.add(PermissionCapability.exactReminderTiming);
        }
      }
    } else if (source == PermissionEducationSource.settings) {
      for (final cap in PermissionCapability.values) {
        if (cap == PermissionCapability.exactReminderTiming &&
            !Platform.isAndroid) {
          continue;
        }
        final status = statuses[cap];
        if (status != null &&
            status.permissionState != AppPermissionState.granted) {
          caps.add(cap);
        }
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
      if (currentStatus == AppPermissionState.permanentlyDenied) {
        await openSettingsForCurrent();
        return;
      }

      final reqResult = await _gateway.request(
        PermissionCapability.deviceLocation,
      );

      if (reqResult == AppPermissionState.granted) {
        unawaited(_weatherRepository.useCurrentLocationHomeArea());
        await _updateCapabilityOutcome(
          PermissionCapability.deviceLocation,
          PermissionEducationOutcome.granted,
          reqResult,
        );
        await _advanceNextStep();
      } else if (reqResult == AppPermissionState.permanentlyDenied) {
        await openSettingsForCurrent();
      } else {
        await _updateCapabilityOutcome(
          PermissionCapability.deviceLocation,
          PermissionEducationOutcome.blocked,
          reqResult,
        );
      }
    } catch (_) {
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> chooseLocationManually(HomeLocation chosenLocation) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true);

    try {
      await _settingsRepository.setHomeLocation(chosenLocation);
      unawaited(_weatherRepository.refreshWeather());
      await _updateCapabilityOutcome(
        PermissionCapability.deviceLocation,
        PermissionEducationOutcome.configuredManually,
        AppPermissionState.granted,
      );
      await _advanceNextStep();
    } catch (_) {
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> enableNotifications() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true);

    try {
      final currentStatus = state
          .capabilityStatuses[PermissionCapability.notifications]
          ?.permissionState;
      if (currentStatus == AppPermissionState.permanentlyDenied) {
        await openSettingsForCurrent();
        return;
      }

      final reqResult = await _gateway.request(
        PermissionCapability.notifications,
      );

      if (reqResult == AppPermissionState.granted) {
        await _notificationScheduler.refreshSchedules();
        await _updateCapabilityOutcome(
          PermissionCapability.notifications,
          PermissionEducationOutcome.granted,
          reqResult,
        );
        await _advanceNextStep();
      } else if (reqResult == AppPermissionState.permanentlyDenied) {
        await openSettingsForCurrent();
      } else {
        await _updateCapabilityOutcome(
          PermissionCapability.notifications,
          PermissionEducationOutcome.blocked,
          reqResult,
        );
      }
    } catch (_) {
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> enableExactTiming() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true);

    try {
      final currentStatus = state
          .capabilityStatuses[PermissionCapability.exactReminderTiming]
          ?.permissionState;
      if (currentStatus == AppPermissionState.permanentlyDenied) {
        await openSettingsForCurrent();
        return;
      }

      final reqResult = await _gateway.request(
        PermissionCapability.exactReminderTiming,
      );

      if (reqResult == AppPermissionState.granted) {
        await _notificationScheduler.refreshSchedules();
        await _updateCapabilityOutcome(
          PermissionCapability.exactReminderTiming,
          PermissionEducationOutcome.granted,
          reqResult,
        );
        await _advanceNextStep();
      } else if (reqResult == AppPermissionState.permanentlyDenied) {
        await openSettingsForCurrent();
      } else {
        await _updateCapabilityOutcome(
          PermissionCapability.exactReminderTiming,
          PermissionEducationOutcome.blocked,
          reqResult,
        );
      }
    } catch (_) {
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> deferCurrentStep() async {
    final currentCap = state.activeCapability;
    if (currentCap == null) return;

    final now = DateTime.now();
    final stepsMap = Map<PermissionCapability, StepEducationState>.from(
      state.deviceState.steps,
    );
    final existingStep = stepsMap[currentCap] ?? const StepEducationState();

    stepsMap[currentCap] = existingStep.copyWith(
      educationSeen: true,
      deferredAt: now,
      deferCount: existingStep.deferCount + 1,
      lastOutcome: PermissionEducationOutcome.deferred,
    );

    final updatedDeviceState = state.deviceState.copyWith(steps: stepsMap);
    await _repository.saveDeviceState(updatedDeviceState);

    state = state.copyWith(deviceState: updatedDeviceState);
    await _advanceNextStep();
  }

  void finishLater() {
    state = state.copyWith(isVisible: false, awaitingSettingsReturn: false);
  }

  Future<void> openSettingsForCurrent() async {
    final cap = state.activeCapability;
    if (cap == null) return;
    state = state.copyWith(awaitingSettingsReturn: true);
    await _gateway.openSettings(cap);
  }

  Future<void> handleAppResume() async {
    if (!state.awaitingSettingsReturn && !state.isVisible) return;
    state = state.copyWith(awaitingSettingsReturn: false);

    final statuses = Map<PermissionCapability, CapabilityStatus>.from(
      state.capabilityStatuses,
    );
    for (final cap in state.relevantCapabilities) {
      final permState = await _gateway.check(cap);
      final outcome = _determineOutcome(cap, permState, state.deviceState);
      final nextAction = _determineNextAction(cap, permState);
      statuses[cap] = CapabilityStatus(
        capability: cap,
        permissionState: permState,
        outcome: outcome,
        nextAction: nextAction,
      );
    }

    final active = state.activeCapability;
    if (active != null &&
        statuses[active]?.permissionState == AppPermissionState.granted) {
      _advanceNextStep();
    }

    state = state.copyWith(capabilityStatuses: statuses);
  }

  Future<void> _advanceNextStep() async {
    final caps = state.relevantCapabilities;
    final active = state.activeCapability;
    if (active == null || caps.isEmpty) {
      await _settingsRepository.setPermissionEducationSeen(true);
      finishLater();
      return;
    }

    final currentIndex = caps.indexOf(active);
    if (currentIndex >= 0 && currentIndex < caps.length - 1) {
      state = state.copyWith(activeCapability: caps[currentIndex + 1]);
    } else {
      final now = DateTime.now();
      final updatedState = state.deviceState.copyWith(completedAt: now);
      await _repository.saveDeviceState(updatedState);
      await _settingsRepository.setPermissionEducationSeen(true);
      state = state.copyWith(deviceState: updatedState);
      finishLater();
    }
  }

  Future<void> _updateCapabilityOutcome(
    PermissionCapability cap,
    PermissionEducationOutcome outcome,
    AppPermissionState permState,
  ) async {
    final stepsMap = Map<PermissionCapability, StepEducationState>.from(
      state.deviceState.steps,
    );
    final existingStep = stepsMap[cap] ?? const StepEducationState();

    stepsMap[cap] = existingStep.copyWith(
      educationSeen: true,
      lastOutcome: outcome,
    );

    final updatedDeviceState = state.deviceState.copyWith(steps: stepsMap);
    await _repository.saveDeviceState(updatedDeviceState);

    final updatedStatuses = Map<PermissionCapability, CapabilityStatus>.from(
      state.capabilityStatuses,
    );
    updatedStatuses[cap] = CapabilityStatus(
      capability: cap,
      permissionState: permState,
      outcome: outcome,
      nextAction: _determineNextAction(cap, permState),
    );

    state = state.copyWith(
      deviceState: updatedDeviceState,
      capabilityStatuses: updatedStatuses,
    );
  }

  PermissionEducationOutcome _determineOutcome(
    PermissionCapability cap,
    AppPermissionState permState,
    PermissionEducationDeviceState deviceState,
  ) {
    if (permState == AppPermissionState.granted) {
      return PermissionEducationOutcome.granted;
    }
    return deviceState.steps[cap]?.lastOutcome ??
        PermissionEducationOutcome.deferred;
  }

  PermissionNextAction _determineNextAction(
    PermissionCapability cap,
    AppPermissionState permState,
  ) {
    return switch (permState) {
      AppPermissionState.granted => PermissionNextAction.none,
      AppPermissionState.denied => PermissionNextAction.request,
      AppPermissionState.permanentlyDenied =>
        cap == PermissionCapability.deviceLocation
            ? PermissionNextAction.openLocationSettings
            : PermissionNextAction.openAppSettings,
      AppPermissionState.restricted => PermissionNextAction.none,
      AppPermissionState.serviceDisabled =>
        PermissionNextAction.openLocationSettings,
      AppPermissionState.unavailable => PermissionNextAction.none,
    };
  }
}
