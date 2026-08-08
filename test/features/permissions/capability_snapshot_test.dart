import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/core/domain/models.dart';
import 'package:homepilot/src/features/permissions/domain/permission_capability.dart';

void main() {
  const manual = HomeLocation(
    label: 'Baghdad',
    latitude: 33.31,
    longitude: 44.36,
    source: 'manual',
  );
  const device = HomeLocation(
    label: 'Baghdad',
    latitude: 33.31,
    longitude: 44.36,
    source: 'device',
  );

  test('manual weather area is active without faking location permission', () {
    final snapshot = deriveWeatherAreaCapability(
      selectedArea: manual,
      permission: AppPermissionState.denied,
    );
    expect(snapshot.mode, WeatherAreaMode.manual);
    expect(snapshot.deviceLocationPermission, AppPermissionState.denied);
    expect(snapshot.effectiveState, EffectiveCapabilityState.active);
    expect(snapshot.nextAction, PermissionNextAction.none);
  });

  test('saved device area becomes degraded after location revocation', () {
    final snapshot = deriveWeatherAreaCapability(
      selectedArea: device,
      permission: AppPermissionState.permanentlyDenied,
    );
    expect(snapshot.isConfigured, isTrue);
    expect(snapshot.effectiveState, EffectiveCapabilityState.degraded);
    expect(snapshot.nextAction, PermissionNextAction.openAppSettings);
  });

  test('location services off retains selected area but offers service recovery', () {
    final snapshot = deriveWeatherAreaCapability(
      selectedArea: device,
      permission: AppPermissionState.serviceDisabled,
    );
    expect(snapshot.isConfigured, isTrue);
    expect(snapshot.locationServiceEnabled, isFalse);
    expect(snapshot.effectiveState, EffectiveCapabilityState.degraded);
    expect(snapshot.nextAction, PermissionNextAction.openLocationSettings);
  });

  test('notification preference is distinct from blocked OS delivery', () {
    const preferences = NotificationPreferences(
      enabled: true,
      localReminders: true,
      preferExactReminders: true,
    );
    final snapshot = deriveNotificationCapability(
      preferences: preferences,
      notificationPermission: AppPermissionState.permanentlyDenied,
      exactAlarmPermission: AppPermissionState.denied,
    );
    expect(snapshot.preferences.allowsLocalReminders, isTrue);
    expect(snapshot.notificationsActuallyEnabled, isFalse);
    expect(snapshot.deviceReminderState, EffectiveCapabilityState.blocked);
    expect(snapshot.exactTimingState, EffectiveCapabilityState.blocked);
  });

  test('exact preference degrades to approximate when special access is missing', () {
    const preferences = NotificationPreferences(
      enabled: true,
      localReminders: true,
      preferExactReminders: true,
    );
    final snapshot = deriveNotificationCapability(
      preferences: preferences,
      notificationPermission: AppPermissionState.granted,
      exactAlarmPermission: AppPermissionState.denied,
    );
    expect(snapshot.deviceReminderState, EffectiveCapabilityState.active);
    expect(snapshot.canActuallyScheduleExact, isFalse);
    expect(snapshot.exactTimingState, EffectiveCapabilityState.degraded);
  });

  test('exact timing remains off by default for a new preference model', () {
    const preferences = NotificationPreferences();
    expect(preferences.preferExactReminders, isFalse);
  });
}
