import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/main.dart'
    show
        weatherRepositoryProvider,
        settingsRepositoryProvider,
        notificationSchedulerProvider;
import 'package:homepilot/src/core/domain/contracts.dart';
import 'package:homepilot/src/core/domain/models.dart';
import 'package:homepilot/src/features/permissions/application/permission_education_controller.dart';
import 'package:homepilot/src/features/permissions/data/device_permission_gateway.dart';
import 'package:homepilot/src/features/permissions/data/permission_education_repository.dart';
import 'package:homepilot/src/features/permissions/domain/permission_capability.dart';
import 'package:homepilot/src/features/permissions/domain/permission_education_state.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeDevicePermissionGateway implements DevicePermissionGateway {
  FakeDevicePermissionGateway({
    Map<PermissionCapability, AppPermissionState>? states,
    Map<PermissionCapability, AppPermissionState>? requestResults,
  }) : states = states ?? {},
       requestResults = requestResults ?? {};

  final Map<PermissionCapability, AppPermissionState> states;
  final Map<PermissionCapability, AppPermissionState> requestResults;
  final List<PermissionCapability> requests = [];
  final List<PermissionCapability> settingsOpens = [];

  @override
  Future<AppPermissionState> check(PermissionCapability capability) async {
    return states[capability] ?? AppPermissionState.denied;
  }

  @override
  Future<AppPermissionState> request(PermissionCapability capability) async {
    requests.add(capability);
    final result = requestResults[capability] ?? AppPermissionState.granted;
    states[capability] = result;
    return result;
  }

  @override
  Future<bool> openSettings(PermissionCapability capability) async {
    settingsOpens.add(capability);
    return true;
  }
}

class FakePermissionEducationRepository
    implements PermissionEducationRepository {
  PermissionEducationDeviceState deviceState =
      const PermissionEducationDeviceState();

  @override
  Future<PermissionEducationDeviceState> loadDeviceState() async {
    return deviceState;
  }

  @override
  Future<void> saveDeviceState(PermissionEducationDeviceState state) async {
    deviceState = state;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  HomeLocation? _location;

  @override
  Future<HomeLocation?> homeLocation() async => _location;

  @override
  Future<void> setHomeLocation(HomeLocation? location) async {
    _location = location;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotificationScheduler implements NotificationScheduler {
  int refreshCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshSchedules() async {
    refreshCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWeatherRepository implements WeatherRepository {
  int useCurrentLocationCount = 0;
  int refreshWeatherCount = 0;

  @override
  Future<HomeLocation?> useCurrentLocationHomeArea() async {
    useCurrentLocationCount++;
    return const HomeLocation(
      label: 'Baghdad',
      latitude: 33.31,
      longitude: 44.36,
      source: 'device',
    );
  }

  @override
  Future<WeatherSnapshot?> refreshWeather() async {
    refreshWeatherCount++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [ProviderContainer] with fakes overriding all external providers
/// that [PermissionEducationController] depends on.
ProviderContainer _makeContainer({
  required FakeDevicePermissionGateway gateway,
  required FakePermissionEducationRepository repository,
  required FakeWeatherRepository weatherRepo,
  required FakeSettingsRepository settingsRepo,
  required FakeNotificationScheduler scheduler,
}) {
  return ProviderContainer(
    overrides: [
      devicePermissionGatewayProvider.overrideWithValue(gateway),
      permissionEducationRepositoryProvider.overrideWithValue(repository),
      weatherRepositoryProvider.overrideWithValue(weatherRepo),
      settingsRepositoryProvider.overrideWithValue(settingsRepo),
      notificationSchedulerProvider.overrideWithValue(scheduler),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeDevicePermissionGateway gateway;
  late FakePermissionEducationRepository repository;
  late FakeSettingsRepository settingsRepo;
  late FakeNotificationScheduler scheduler;
  late FakeWeatherRepository weatherService;
  late ProviderContainer container;

  setUp(() {
    gateway = FakeDevicePermissionGateway(
      states: {
        PermissionCapability.deviceLocation: AppPermissionState.denied,
        PermissionCapability.notifications: AppPermissionState.denied,
        PermissionCapability.exactReminderTiming: AppPermissionState.denied,
      },
    );
    repository = FakePermissionEducationRepository();
    settingsRepo = FakeSettingsRepository();
    scheduler = FakeNotificationScheduler();
    weatherService = FakeWeatherRepository();

    container = _makeContainer(
      gateway: gateway,
      repository: repository,
      weatherRepo: weatherService,
      settingsRepo: settingsRepo,
      scheduler: scheduler,
    );
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'Initialization populates default relevant capabilities without exact alarms',
    () async {
      final notifier = container.read(
        permissionEducationControllerProvider.notifier,
      );
      await notifier.initialize();
      final state = container.read(permissionEducationControllerProvider);

      expect(state.relevantCapabilities, [
        PermissionCapability.deviceLocation,
        PermissionCapability.notifications,
      ]);
      expect(state.activeCapability, PermissionCapability.deviceLocation);
      expect(state.isVisible, isTrue);
    },
  );

  test(
    'Use current location triggers gateway request and advances step',
    () async {
      final notifier = container.read(
        permissionEducationControllerProvider.notifier,
      );
      await notifier.initialize();
      await notifier.useCurrentLocation();

      expect(gateway.requests, [PermissionCapability.deviceLocation]);
      expect(weatherService.useCurrentLocationCount, 1);
      final state = container.read(permissionEducationControllerProvider);
      expect(state.activeCapability, PermissionCapability.notifications);
    },
  );

  test(
    'Choose location manually sets location without OS permission request',
    () async {
      final notifier = container.read(
        permissionEducationControllerProvider.notifier,
      );
      await notifier.initialize();
      const location = HomeLocation(
        label: 'Basra',
        latitude: 30.50,
        longitude: 47.81,
        source: 'manual',
      );
      await notifier.chooseLocationManually(location);

      expect(gateway.requests, isEmpty);
      expect(await settingsRepo.homeLocation(), equals(location));
      final state = container.read(permissionEducationControllerProvider);
      expect(state.activeCapability, PermissionCapability.notifications);
    },
  );

  test(
    'Defer current step saves deferral cooldown in local v3 state',
    () async {
      final notifier = container.read(
        permissionEducationControllerProvider.notifier,
      );
      await notifier.initialize();
      await notifier.deferCurrentStep();

      final savedState = repository.deviceState;
      final step = savedState.steps[PermissionCapability.deviceLocation];

      expect(step?.educationSeen, isTrue);
      expect(step?.deferCount, equals(1));
      final state = container.read(permissionEducationControllerProvider);
      expect(state.activeCapability, PermissionCapability.notifications);
    },
  );

  test(
    'Finish later closes overlay without marking all capabilities completed',
    () async {
      final notifier = container.read(
        permissionEducationControllerProvider.notifier,
      );
      await notifier.initialize();
      notifier.finishLater();

      final state = container.read(permissionEducationControllerProvider);
      expect(state.isVisible, isFalse);
      expect(repository.deviceState.completedAt, isNull);
    },
  );
}
