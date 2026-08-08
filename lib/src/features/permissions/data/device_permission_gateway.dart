import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/permission_capability.dart';

abstract interface class DevicePermissionGateway {
  Future<AppPermissionState> check(PermissionCapability capability);
  Future<AppPermissionState> request(PermissionCapability capability);
  Future<bool> openSettings(PermissionCapability capability);
}

class FlutterDevicePermissionGateway implements DevicePermissionGateway {
  const FlutterDevicePermissionGateway();

  @override
  Future<AppPermissionState> check(PermissionCapability capability) async {
    try {
      switch (capability) {
        case PermissionCapability.deviceLocation:
          if (!await Geolocator.isLocationServiceEnabled()) {
            return AppPermissionState.serviceDisabled;
          }
          final status = await Geolocator.checkPermission();
          return _mapLocationPermission(status);

        case PermissionCapability.notifications:
          final status = await Permission.notification.status;
          return _mapPermissionStatus(status);

        case PermissionCapability.exactReminderTiming:
          if (!Platform.isAndroid) {
            return AppPermissionState.unavailable;
          }
          final status = await Permission.scheduleExactAlarm.status;
          return _mapPermissionStatus(status);
      }
    } on MissingPluginException {
      return AppPermissionState.unavailable;
    } on Exception {
      return AppPermissionState.unavailable;
    }
  }

  @override
  Future<AppPermissionState> request(PermissionCapability capability) async {
    try {
      switch (capability) {
        case PermissionCapability.deviceLocation:
          if (!await Geolocator.isLocationServiceEnabled()) {
            return AppPermissionState.serviceDisabled;
          }
          final status = await Geolocator.requestPermission();
          return _mapLocationPermission(status);

        case PermissionCapability.notifications:
          final status = await Permission.notification.request();
          return _mapPermissionStatus(status);

        case PermissionCapability.exactReminderTiming:
          if (!Platform.isAndroid) {
            return AppPermissionState.unavailable;
          }
          final status = await Permission.scheduleExactAlarm.request();
          return _mapPermissionStatus(status);
      }
    } on MissingPluginException {
      return AppPermissionState.unavailable;
    } on Exception {
      return AppPermissionState.unavailable;
    }
  }

  @override
  Future<bool> openSettings(PermissionCapability capability) async {
    try {
      switch (capability) {
        case PermissionCapability.deviceLocation:
          if (!await Geolocator.isLocationServiceEnabled()) {
            return await Geolocator.openLocationSettings();
          }
          return await openAppSettings();

        case PermissionCapability.notifications:
        case PermissionCapability.exactReminderTiming:
          return await openAppSettings();
      }
    } on MissingPluginException {
      return false;
    } on Exception {
      return false;
    }
  }

  AppPermissionState _mapLocationPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => AppPermissionState.granted,
      LocationPermission.denied => AppPermissionState.denied,
      LocationPermission.deniedForever => AppPermissionState.permanentlyDenied,
      LocationPermission.unableToDetermine => AppPermissionState.denied,
    };
  }

  AppPermissionState _mapPermissionStatus(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted ||
      PermissionStatus.limited => AppPermissionState.granted,
      PermissionStatus.permanentlyDenied =>
        AppPermissionState.permanentlyDenied,
      PermissionStatus.restricted => AppPermissionState.restricted,
      PermissionStatus.denied ||
      PermissionStatus.provisional => AppPermissionState.denied,
    };
  }
}
