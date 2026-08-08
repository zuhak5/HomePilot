import 'dart:io';

import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database/app_database.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum AppPermissionKind { notifications, location, exactAlarms }

enum AppPermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  serviceDisabled,
  unavailable,
}

abstract interface class AppPermissionGateway {
  Future<AppPermissionState> check(AppPermissionKind kind);
  Future<AppPermissionState> request(AppPermissionKind kind);
  Future<bool> wasPrompted(AppPermissionKind kind);
  Future<void> markPrompted(AppPermissionKind kind);
  Future<bool> openAppPermissionSettings();
  Future<bool> openLocationServiceSettings();
}

class AppPermissionCoordinator implements AppPermissionGateway {
  AppPermissionCoordinator(this._database);

  final AppDatabase _database;

  @override
  Future<AppPermissionState> check(AppPermissionKind kind) async {
    try {
      if (!Platform.isAndroid && kind == AppPermissionKind.exactAlarms) {
        return AppPermissionState.unavailable;
      }
      if (kind == AppPermissionKind.exactAlarms && Platform.isAndroid) {
        try {
          final plugin = FlutterLocalNotificationsPlugin()
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          final canExact = await plugin?.canScheduleExactNotifications();
          if (canExact != null) {
            return canExact
                ? AppPermissionState.granted
                : AppPermissionState.denied;
          }
        } catch (_) {}
      }
      if (kind == AppPermissionKind.location &&
          !await Geolocator.isLocationServiceEnabled()) {
        return AppPermissionState.serviceDisabled;
      }
      return _mapStatus(await _permission(kind).status);
    } on MissingPluginException {
      return AppPermissionState.unavailable;
    }
  }

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async {
    final current = await check(kind);
    if (current == AppPermissionState.granted ||
        current == AppPermissionState.permanentlyDenied ||
        current == AppPermissionState.restricted ||
        current == AppPermissionState.serviceDisabled ||
        current == AppPermissionState.unavailable) {
      return current;
    }
    await markPrompted(kind);
    try {
      if (kind == AppPermissionKind.exactAlarms && Platform.isAndroid) {
        try {
          final plugin = FlutterLocalNotificationsPlugin()
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          final granted = await plugin?.requestExactAlarmsPermission();
          if (granted != null) {
            return granted
                ? AppPermissionState.granted
                : AppPermissionState.denied;
          }
        } catch (_) {}
      }
      return _mapStatus(await _permission(kind).request());
    } on MissingPluginException {
      return AppPermissionState.unavailable;
    }
  }

  @override
  Future<bool> wasPrompted(AppPermissionKind kind) async {
    final row =
        await (_database.select(_database.settings)
              ..where((setting) => setting.key.equals(_historyKey(kind))))
            .getSingleOrNull();
    return row?.value == 'true';
  }

  @override
  Future<void> markPrompted(AppPermissionKind kind) async {
    await _database
        .into(_database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: _historyKey(kind),
            value: 'true',
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<bool> openAppPermissionSettings() => openAppSettings();

  @override
  Future<bool> openLocationServiceSettings() =>
      Geolocator.openLocationSettings();

  Permission _permission(AppPermissionKind kind) => switch (kind) {
    AppPermissionKind.notifications => Permission.notification,
    AppPermissionKind.location => Permission.locationWhenInUse,
    AppPermissionKind.exactAlarms => Permission.scheduleExactAlarm,
  };

  AppPermissionState _mapStatus(PermissionStatus status) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited => AppPermissionState.granted,
    PermissionStatus.permanentlyDenied => AppPermissionState.permanentlyDenied,
    PermissionStatus.restricted => AppPermissionState.restricted,
    PermissionStatus.denied ||
    PermissionStatus.provisional => AppPermissionState.denied,
  };

  String _historyKey(AppPermissionKind kind) =>
      'permission_prompted_${kind.name}';
}
