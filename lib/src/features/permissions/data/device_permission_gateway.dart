import 'package:homepilot/src/core/services/app_permission_coordinator.dart';

import '../domain/permission_capability.dart';

abstract interface class DevicePermissionGateway {
  Future<AppPermissionState> check(PermissionCapability capability);
  Future<AppPermissionState> request(PermissionCapability capability);
  Future<bool> openSettings(PermissionCapability capability);
}

class FlutterDevicePermissionGateway implements DevicePermissionGateway {
  const FlutterDevicePermissionGateway(this._delegate);

  final AppPermissionGateway _delegate;

  AppPermissionKind _kind(PermissionCapability capability) => switch (capability) {
    PermissionCapability.deviceLocation => AppPermissionKind.location,
    PermissionCapability.notifications => AppPermissionKind.notifications,
    PermissionCapability.exactReminderTiming => AppPermissionKind.exactAlarms,
  };

  @override
  Future<AppPermissionState> check(PermissionCapability capability) =>
      _delegate.check(_kind(capability));

  @override
  Future<AppPermissionState> request(PermissionCapability capability) =>
      _delegate.request(_kind(capability));

  @override
  Future<bool> openSettings(PermissionCapability capability) async {
    switch (capability) {
      case PermissionCapability.deviceLocation:
        final state = await _delegate.check(AppPermissionKind.location);
        return state == AppPermissionState.serviceDisabled
            ? _delegate.openLocationServiceSettings()
            : _delegate.openAppPermissionSettings();
      case PermissionCapability.notifications:
        return _delegate.openAppPermissionSettings();
      case PermissionCapability.exactReminderTiming:
        // The canonical request uses flutter_local_notifications' exact-alarm
        // special-access API. If a platform implementation cannot open it,
        // retain the generic settings fallback rather than inventing a second
        // feature-layer native implementation.
        final state = await _delegate.request(AppPermissionKind.exactAlarms);
        if (state == AppPermissionState.granted) return true;
        return _delegate.openAppPermissionSettings();
    }
  }
}
