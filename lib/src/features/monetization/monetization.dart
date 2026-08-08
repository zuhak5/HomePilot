import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_localizations_ext.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/redacting_logger.dart';
import '../../ui/app_theme.dart';
import '../auth/presentation/auth_providers.dart';

const _nativeFactoryId = 'homepilotNative';
const _firstSessionStorageKey = 'monetization_has_completed_session_v1';

enum RewardAdType { rewardedAd, rewardedInterstitial }

enum RewardShowResult {
  shownAwaitingServerVerification,
  unavailable,
  rejected,
  dismissed,
}

@visibleForTesting
Duration adRetryDelayForFailure(int failureCount) {
  const seconds = [2, 4, 8, 16, 32, 60];
  final index = (failureCount - 1).clamp(0, seconds.length - 1);
  return Duration(seconds: seconds[index]);
}

@visibleForTesting
bool nativeAdPlacementEnabled({
  required bool routeIsCurrent,
  required bool configEnabled,
  required bool consentGranted,
  required bool adsInitialized,
  required bool platformSupported,
  bool presentationSuppressed = false,
  bool? enabledOverride,
}) =>
    routeIsCurrent &&
    !presentationSuppressed &&
    (enabledOverride ??
        (configEnabled &&
            consentGranted &&
            adsInitialized &&
            platformSupported));

final nativeAdPresentationDepthProvider =
    NotifierProvider<NativeAdPresentationDepth, int>(
      NativeAdPresentationDepth.new,
    );

class NativeAdPresentationDepth extends Notifier<int> {
  @override
  int build() => 0;

  void push() => state++;

  void pop() => state = (state - 1).clamp(0, 1 << 20);
}

Future<T> runWithNativeAdsSuspended<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final presentationDepth = ProviderScope.containerOf(
    context,
  ).read(nativeAdPresentationDepthProvider.notifier);
  presentationDepth.push();
  try {
    if (Platform.isAndroid) {
      // Android platform views are torn down at the end of the frame. Waiting
      // before pushing an overlay prevents the disposed native view from
      // receiving the overlay's first gesture. Other platforms do not need
      // this delay, which also keeps host-side widget interactions immediate.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return await action();
  } finally {
    presentationDepth.pop();
  }
}

const _systemUiChannel = MethodChannel('homepilot/system_ui');

Future<String?> resolveSystemRewardTimeZone(String? fallback) async {
  if (!_supportsMobileAds || !Platform.isAndroid) return fallback;
  try {
    final value = await _systemUiChannel.invokeMethod<String>('getTimeZoneId');
    final timeZone = value?.trim();
    return timeZone == null || timeZone.isEmpty ? fallback : timeZone;
  } on Object catch (error) {
    AppLogger.warning('reward_time_zone_lookup', error: error);
    return fallback;
  }
}

class OfflineCreationDraftStore {
  const OfflineCreationDraftStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  Future<void> save(String key, Map<String, dynamic> value) async {
    try {
      await _storage.write(key: _storageKey(key), value: jsonEncode(value));
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_save', error: error);
    }
  }

  Future<Map<String, dynamic>?> load(String key) async {
    try {
      final encoded = await _storage.read(key: _storageKey(key));
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_load', error: error);
      return null;
    }
  }

  Future<void> clear(String key) async {
    try {
      await _storage.delete(key: _storageKey(key));
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_clear', error: error);
    }
  }

  String _storageKey(String key) => 'homepilot_creation_draft_v1_$key';
}

final offlineCreationDraftStoreProvider = Provider<OfflineCreationDraftStore>(
  (_) => const OfflineCreationDraftStore(),
);

class PointWallet {
  const PointWallet({
    required this.balance,
    required this.timeZone,
    required this.updatedAt,
  });

  factory PointWallet.fromJson(Map<String, dynamic> json) => PointWallet(
    balance: json['balance'] as int? ?? 0,
    timeZone: json['reward_time_zone'] as String? ?? 'UTC',
    updatedAt:
        DateTime.tryParse(json['updated_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final int balance;
  final String timeZone;
  final DateTime updatedAt;
}

class MonetizationConfig {
  const MonetizationConfig({
    required this.adsEnabled,
    required this.nativeAdsEnabled,
    required this.interstitialAdsEnabled,
    required this.rewardedAdsEnabled,
    required this.rewardedInterstitialEnabled,
    required this.pointsEnabled,
    required this.emergencyFreeCreationMode,
    required this.walletCap,
    required this.interstitialCooldownSeconds,
    required this.rapidCompletionWindowSeconds,
    required this.interstitialSessionCap,
  });

  const MonetizationConfig.failClosed()
    : adsEnabled = false,
      nativeAdsEnabled = false,
      interstitialAdsEnabled = false,
      rewardedAdsEnabled = false,
      rewardedInterstitialEnabled = false,
      pointsEnabled = true,
      emergencyFreeCreationMode = false,
      walletCap = 20,
      interstitialCooldownSeconds = 180,
      rapidCompletionWindowSeconds = 60,
      interstitialSessionCap = 3;

  factory MonetizationConfig.fromJson(Map<String, dynamic> json) =>
      MonetizationConfig(
        adsEnabled: json['ads_enabled'] as bool? ?? false,
        nativeAdsEnabled: json['native_ads_enabled'] as bool? ?? false,
        interstitialAdsEnabled:
            json['interstitial_ads_enabled'] as bool? ?? false,
        rewardedAdsEnabled: json['rewarded_ads_enabled'] as bool? ?? false,
        rewardedInterstitialEnabled:
            json['rewarded_interstitial_enabled'] as bool? ?? false,
        pointsEnabled: json['points_enabled'] as bool? ?? true,
        emergencyFreeCreationMode:
            json['emergency_free_creation_mode'] as bool? ?? false,
        walletCap: json['wallet_cap'] as int? ?? 20,
        interstitialCooldownSeconds:
            json['interstitial_cooldown_seconds'] as int? ?? 180,
        rapidCompletionWindowSeconds:
            json['rapid_completion_window_seconds'] as int? ?? 60,
        interstitialSessionCap: json['interstitial_session_cap'] as int? ?? 3,
      );

  final bool adsEnabled;
  final bool nativeAdsEnabled;
  final bool interstitialAdsEnabled;
  final bool rewardedAdsEnabled;
  final bool rewardedInterstitialEnabled;
  final bool pointsEnabled;
  final bool emergencyFreeCreationMode;
  final int walletCap;
  final int interstitialCooldownSeconds;
  final int rapidCompletionWindowSeconds;
  final int interstitialSessionCap;

  bool get creationIsFree => !pointsEnabled || emergencyFreeCreationMode;
}

class RewardClaimRequest {
  const RewardClaimRequest({
    required this.claimId,
    required this.userId,
    required this.rewardAmount,
  });

  factory RewardClaimRequest.fromJson(Map<String, dynamic> json) =>
      RewardClaimRequest(
        claimId: json['claim_id'] as String,
        userId: json['user_id'] as String,
        rewardAmount: json['reward_amount'] as int,
      );

  final String claimId;
  final String userId;
  final int rewardAmount;
}

class PendingRewardClaim {
  const PendingRewardClaim({
    required this.claimId,
    required this.rewardAmount,
    required this.expiresAt,
  });

  factory PendingRewardClaim.fromJson(Map<String, dynamic> json) =>
      PendingRewardClaim(
        claimId: json['claim_id'] as String,
        rewardAmount: json['reward_amount'] as int? ?? 0,
        expiresAt:
            DateTime.tryParse(json['expires_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  final String claimId;
  final int rewardAmount;
  final DateTime expiresAt;
}

class PointDebitResult {
  const PointDebitResult({
    required this.balance,
    required this.charged,
    required this.alreadyProcessed,
    this.plan,
    this.metadata,
  });

  factory PointDebitResult.fromJson(Map<String, dynamic> json) =>
      PointDebitResult(
        balance: json['balance'] as int? ?? 0,
        charged: json['charged'] as int? ?? 0,
        alreadyProcessed: json['already_processed'] as bool? ?? false,
        plan: json['plan'] is Map
            ? Map<String, dynamic>.from(json['plan'] as Map)
            : null,
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null,
      );

  final int balance;
  final int charged;
  final bool alreadyProcessed;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? metadata;
}

abstract class MonetizationRepository {
  const MonetizationRepository();

  String? get currentUserId => null;

  Stream<PointWallet?> watchWallet(String userId) => Stream.value(null);

  Stream<MonetizationConfig> watchConfig() =>
      Stream.value(const MonetizationConfig.failClosed());

  Future<List<PendingRewardClaim>> fetchPendingRewardClaims(String userId) =>
      Future.value(const []);

  Future<PointDebitResult> createAsset(Map<String, dynamic> operation) =>
      Future.error(UnsupportedError('Asset point debit is unavailable.'));

  Future<PointDebitResult> createTask(Map<String, dynamic> operation) =>
      Future.error(UnsupportedError('Task point debit is unavailable.'));

  Future<List<Map<String, dynamic>>> listTransactions() async => const [];

  Future<RewardClaimRequest> createRewardClaim(
    RewardAdType type, {
    String? timeZone,
  }) => Future.error(UnsupportedError('Reward claims are unavailable.'));

  Future<void> recordEvent(
    String name, [
    Map<String, dynamic> properties = const {},
  ]) async {}
}

class SupabaseMonetizationRepository extends MonetizationRepository {
  const SupabaseMonetizationRepository(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  Stream<PointWallet?> watchWallet(String userId) {
    return client
        .from('point_wallets')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map((rows) => rows.isEmpty ? null : PointWallet.fromJson(rows.single));
  }

  @override
  Stream<MonetizationConfig> watchConfig() {
    return client
        .from('monetization_config')
        .stream(primaryKey: ['singleton'])
        .eq('singleton', true)
        .map(
          (rows) => rows.isEmpty
              ? const MonetizationConfig.failClosed()
              : MonetizationConfig.fromJson(rows.single),
        );
  }

  @override
  Future<List<PendingRewardClaim>> fetchPendingRewardClaims(
    String userId,
  ) async {
    final rows = await client
        .from('reward_claim_requests')
        .select(
          'claim_id,user_id,reward_type,ad_unit_id,reward_amount,status,'
          'reward_day,expires_at,created_at,processed_at,rejection_reason',
        )
        .eq('user_id', userId)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(10);
    return [
      for (final row in rows)
        PendingRewardClaim.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<PointDebitResult> createAsset(Map<String, dynamic> operation) async {
    final data = await client.rpc<Map<String, dynamic>>(
      'create_asset_with_point_debit',
      params: {'p_operation': operation},
    );
    return PointDebitResult.fromJson(data);
  }

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    final data = await client.rpc<Map<String, dynamic>>(
      'create_task_with_point_debit',
      params: {'p_operation': operation},
    );
    return PointDebitResult.fromJson(data);
  }

  @override
  Future<List<Map<String, dynamic>>> listTransactions() async {
    final rows = await client
        .from('point_transactions')
        .select('amount,balance_after,transaction_type,reference_id,created_at')
        .order('created_at', ascending: false)
        .limit(50);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  @override
  Future<RewardClaimRequest> createRewardClaim(
    RewardAdType type, {
    String? timeZone,
  }) async {
    final data = await client.rpc<Map<String, dynamic>>(
      'create_reward_claim_request',
      params: {
        'p_reward_type': switch (type) {
          RewardAdType.rewardedAd => 'rewarded_ad',
          RewardAdType.rewardedInterstitial => 'rewarded_interstitial',
        },
        'p_time_zone': timeZone,
      },
    );
    return RewardClaimRequest.fromJson(data);
  }

  @override
  Future<void> recordEvent(
    String name, [
    Map<String, dynamic> properties = const {},
  ]) async {
    try {
      await client.rpc<void>(
        'record_monetization_event',
        params: {'p_event_name': name, 'p_properties': properties},
      );
    } on Object catch (error) {
      AppLogger.warning('monetization_event_failed', error: error);
    }
  }
}

final monetizationRepositoryProvider = Provider<MonetizationRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseMonetizationRepository(client);
});

final pointWalletProvider = StreamProvider<PointWallet?>((ref) {
  ref.watch(authSessionProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final userId = repository?.currentUserId;
  if (repository == null || userId == null) return Stream.value(null);
  return repository.watchWallet(userId);
});

final monetizationConfigProvider = StreamProvider<MonetizationConfig>((ref) {
  final repository = ref.watch(monetizationRepositoryProvider);
  if (repository == null) {
    return Stream.value(const MonetizationConfig.failClosed());
  }
  return repository.watchConfig();
});

final pendingRewardClaimsProvider = FutureProvider<List<PendingRewardClaim>>((
  ref,
) async {
  ref.watch(authSessionProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final userId = repository?.currentUserId;
  if (repository == null || userId == null) return const [];
  return repository.fetchPendingRewardClaims(userId);
});

class ConsentSnapshot {
  const ConsentSnapshot({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
    required this.updated,
  });

  const ConsentSnapshot.initial()
    : canRequestAds = false,
      privacyOptionsRequired = false,
      updated = false;

  final bool canRequestAds;
  final bool privacyOptionsRequired;
  final bool updated;
}

class HomePilotConsentService {
  HomePilotConsentService(this.ads);

  final HomePilotAdsService ads;
  final _states = StreamController<ConsentSnapshot>.broadcast();
  ConsentSnapshot _current = const ConsentSnapshot.initial();
  bool _started = false;

  Stream<ConsentSnapshot> get states async* {
    yield _current;
    yield* _states.stream;
  }

  Future<void> initialize() async {
    if (_started || !_supportsMobileAds) return;
    _started = true;
    final completion = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) {
            AppLogger.warning('ad_consent_form', error: error);
          }
        });
        await _refreshAndInitializeAds();
        if (!completion.isCompleted) completion.complete();
      },
      (error) async {
        AppLogger.warning('ad_consent_update', error: error);
        await _refreshAndInitializeAds();
        if (!completion.isCompleted) completion.complete();
      },
    );
    await completion.future;
  }

  Future<void> showPrivacyOptions() async {
    if (!_supportsMobileAds) return;
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) AppLogger.warning('ad_privacy_options', error: error);
    });
    await _refreshAndInitializeAds();
  }

  Future<void> _refreshAndInitializeAds() async {
    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    final privacyStatus = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    _current = ConsentSnapshot(
      canRequestAds: canRequestAds,
      privacyOptionsRequired:
          privacyStatus == PrivacyOptionsRequirementStatus.required,
      updated: true,
    );
    _states.add(_current);
    if (canRequestAds) await ads.initialize();
  }

  void dispose() => _states.close();
}

final homePilotAdsProvider = Provider<HomePilotAdsService>((ref) {
  final config = ref.watch(appConfigProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final service = HomePilotAdsService(
    useProductionUnits: config.environment == AppEnvironment.prod,
    repository: repository,
  );
  ref.onDispose(service.dispose);
  return service;
});

final consentServiceProvider = Provider<HomePilotConsentService>((ref) {
  final service = HomePilotConsentService(ref.watch(homePilotAdsProvider));
  ref.onDispose(service.dispose);
  return service;
});

final consentSnapshotProvider = StreamProvider<ConsentSnapshot>((ref) {
  return ref.watch(consentServiceProvider).states;
});

class MonetizationBootstrap extends ConsumerStatefulWidget {
  const MonetizationBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MonetizationBootstrap> createState() =>
      _MonetizationBootstrapState();
}

class _MonetizationBootstrapState extends ConsumerState<MonetizationBootstrap> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      await ref.read(completionAdCoordinatorProvider).initializeSession();
      await ref.read(consentServiceProvider).initialize();
      final config = ref.read(monetizationConfigProvider).value;
      if (config?.adsEnabled ?? false) {
        await ref.read(homePilotAdsProvider).preloadFullScreenAds();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(monetizationConfigProvider).value;
    final consent = ref.watch(consentSnapshotProvider).value;
    if ((config?.adsEnabled ?? false) && (consent?.canRequestAds ?? false)) {
      scheduleMicrotask(
        () => ref.read(homePilotAdsProvider).preloadFullScreenAds(),
      );
    }
    return widget.child;
  }
}

class HomePilotAdUnits {
  const HomePilotAdUnits({required this.production});

  final bool production;

  String native(String placement) {
    if (!production) return 'ca-app-pub-3940256099942544/2247696110';
    return placement == 'home'
        ? 'ca-app-pub-5274007212820203/1685903136'
        : 'ca-app-pub-5274007212820203/5230396474';
  }

  String get interstitial => production
      ? 'ca-app-pub-5274007212820203/5857348361'
      : 'ca-app-pub-3940256099942544/1033173712';

  String get rewarded => production
      ? 'ca-app-pub-5274007212820203/3342599731'
      : 'ca-app-pub-3940256099942544/5224354917';

  String get rewardedInterstitial => production
      ? 'ca-app-pub-5274007212820203/2197039025'
      : 'ca-app-pub-3940256099942544/5354046379';
}

class HomePilotAdsService {
  HomePilotAdsService({
    required this.useProductionUnits,
    required this.repository,
    this.timeZoneResolver = resolveSystemRewardTimeZone,
  }) : units = HomePilotAdUnits(production: useProductionUnits);

  final bool useProductionUnits;
  final MonetizationRepository? repository;
  final Future<String?> Function(String? fallback) timeZoneResolver;
  final HomePilotAdUnits units;
  bool _initialized = false;
  bool _preloading = false;
  bool _disposed = false;
  bool _interstitialLoading = false;
  bool _rewardedLoading = false;
  bool _rewardedInterstitialLoading = false;
  int _interstitialFailures = 0;
  int _rewardedFailures = 0;
  int _rewardedInterstitialFailures = 0;
  Timer? _interstitialRetry;
  Timer? _rewardedRetry;
  Timer? _rewardedInterstitialRetry;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  RewardedInterstitialAd? _rewardedInterstitial;

  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized || _disposed || !_supportsMobileAds) return;
    final testDeviceIds = const String.fromEnvironment(
      'ADMOB_TEST_DEVICE_IDS',
    ).split(',').map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.pg,
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
        tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.unspecified,
        testDeviceIds: testDeviceIds,
      ),
    );
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  Future<void> preloadFullScreenAds() async {
    if (!_initialized || _preloading || _disposed) return;
    _preloading = true;
    try {
      await Future.wait([
        if (_interstitial == null) _loadInterstitial(),
        if (_rewarded == null) _loadRewarded(),
        if (_rewardedInterstitial == null) _loadRewardedInterstitial(),
      ]);
    } finally {
      _preloading = false;
    }
  }

  Future<bool> showInterstitial({
    Map<String, dynamic> analyticsProperties = const {},
  }) async {
    final ad = _interstitial;
    if (!_initialized || ad == null) {
      unawaited(_loadInterstitial());
      return false;
    }
    _interstitial = null;
    final completion = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) {
        AppLogger.info('ad_impression', fields: {'ad_type': 'interstitial'});
        unawaited(
          repository?.recordEvent('ad_interstitial_shown', analyticsProperties),
        );
      },
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        if (!completion.isCompleted) completion.complete(true);
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        AppLogger.warning('interstitial_show', error: error);
        failedAd.dispose();
        if (!completion.isCompleted) completion.complete(false);
        unawaited(_loadInterstitial());
      },
    );
    await ad.show();
    return completion.future;
  }

  Future<RewardShowResult> showReward(
    RewardAdType type, {
    required String? timeZone,
    required String entryPoint,
  }) async {
    if (!_initialized || repository == null) {
      return RewardShowResult.unavailable;
    }
    final adAvailable = switch (type) {
      RewardAdType.rewardedAd => _rewarded != null,
      RewardAdType.rewardedInterstitial => _rewardedInterstitial != null,
    };
    if (!adAvailable) {
      if (type == RewardAdType.rewardedAd) {
        unawaited(_loadRewarded());
      } else {
        unawaited(_loadRewardedInterstitial());
      }
      return RewardShowResult.unavailable;
    }
    RewardClaimRequest claim;
    try {
      final resolvedTimeZone = await timeZoneResolver(timeZone);
      claim = await repository!.createRewardClaim(
        type,
        timeZone: resolvedTimeZone,
      );
    } on Object {
      return RewardShowResult.rejected;
    }
    final earned = Completer<bool>();
    final dismissed = Completer<void>();
    var failedToShow = false;
    if (type == RewardAdType.rewardedAd) {
      final ad = _rewarded;
      if (ad == null) {
        unawaited(_loadRewarded());
        return RewardShowResult.unavailable;
      }
      _rewarded = null;
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(
          userId: claim.userId,
          customData: claim.claimId,
        ),
      );
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdDismissedFullScreenContent: (shownAd) {
          shownAd.dispose();
          if (!dismissed.isCompleted) dismissed.complete();
          unawaited(_loadRewarded());
        },
        onAdFailedToShowFullScreenContent: (failedAd, error) {
          AppLogger.warning('rewarded_show', error: error);
          failedToShow = true;
          failedAd.dispose();
          if (!earned.isCompleted) earned.complete(false);
          if (!dismissed.isCompleted) dismissed.complete();
          unawaited(_loadRewarded());
        },
      );
      await ad.show(
        onUserEarnedReward: (_, reward) {
          AppLogger.info(
            'ad_rewarded',
            fields: {'ad_type': 'rewarded', 'reward_amount': reward.amount},
          );
          if (!earned.isCompleted) earned.complete(true);
        },
      );
    } else {
      final ad = _rewardedInterstitial;
      if (ad == null) {
        unawaited(_loadRewardedInterstitial());
        return RewardShowResult.unavailable;
      }
      _rewardedInterstitial = null;
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(
          userId: claim.userId,
          customData: claim.claimId,
        ),
      );
      ad.fullScreenContentCallback =
          FullScreenContentCallback<RewardedInterstitialAd>(
            onAdDismissedFullScreenContent: (shownAd) {
              shownAd.dispose();
              if (!dismissed.isCompleted) dismissed.complete();
              unawaited(_loadRewardedInterstitial());
            },
            onAdFailedToShowFullScreenContent: (failedAd, error) {
              AppLogger.warning('rewarded_interstitial_show', error: error);
              failedToShow = true;
              failedAd.dispose();
              if (!earned.isCompleted) earned.complete(false);
              if (!dismissed.isCompleted) dismissed.complete();
              unawaited(_loadRewardedInterstitial());
            },
          );
      await ad.show(
        onUserEarnedReward: (_, reward) {
          AppLogger.info(
            'ad_rewarded',
            fields: {
              'ad_type': 'rewarded_interstitial',
              'reward_amount': reward.amount,
            },
          );
          if (!earned.isCompleted) earned.complete(true);
        },
      );
    }
    await dismissed.future;
    final wasEarned = earned.isCompleted ? await earned.future : false;
    if (!wasEarned) {
      return failedToShow
          ? RewardShowResult.unavailable
          : RewardShowResult.dismissed;
    }
    unawaited(
      repository!.recordEvent('ad_rewarded_watched', {
        'reward_amount': claim.rewardAmount,
        'entry_point': entryPoint,
        'verification': 'server_pending',
      }),
    );
    AppLogger.info(
      'ad_show_completed',
      fields: {
        'ad_type': type.name,
        'entry_point': entryPoint,
        'verification': 'server_pending',
      },
    );
    return RewardShowResult.shownAwaitingServerVerification;
  }

  Future<void> _loadInterstitial({bool retry = false}) async {
    if (!_initialized ||
        _disposed ||
        _interstitial != null ||
        _interstitialLoading ||
        (!retry && _interstitialRetry?.isActive == true)) {
      return;
    }
    _interstitialRetry?.cancel();
    _interstitialRetry = null;
    AppLogger.info('ad_load_requested', fields: {'ad_type': 'interstitial'});
    _interstitialLoading = true;
    final completion = Completer<void>();
    try {
      await InterstitialAd.load(
        adUnitId: units.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialLoading = false;
            _interstitialFailures = 0;
            AppLogger.info('ad_loaded', fields: {'ad_type': 'interstitial'});
            if (_disposed) {
              ad.dispose();
            } else {
              _interstitial = ad;
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            _interstitialLoading = false;
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'interstitial'},
            );
            _scheduleInterstitialRetry();
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      _interstitialLoading = false;
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'interstitial'},
      );
      _scheduleInterstitialRetry();
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewarded({bool retry = false}) async {
    if (!_initialized ||
        _disposed ||
        _rewarded != null ||
        _rewardedLoading ||
        (!retry && _rewardedRetry?.isActive == true)) {
      return;
    }
    _rewardedRetry?.cancel();
    _rewardedRetry = null;
    AppLogger.info('ad_load_requested', fields: {'ad_type': 'rewarded'});
    _rewardedLoading = true;
    final completion = Completer<void>();
    try {
      await RewardedAd.load(
        adUnitId: units.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedLoading = false;
            _rewardedFailures = 0;
            AppLogger.info('ad_loaded', fields: {'ad_type': 'rewarded'});
            if (_disposed) {
              ad.dispose();
            } else {
              _rewarded = ad;
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            _rewardedLoading = false;
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'rewarded'},
            );
            _scheduleRewardedRetry();
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      _rewardedLoading = false;
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'rewarded'},
      );
      _scheduleRewardedRetry();
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewardedInterstitial({bool retry = false}) async {
    if (!_initialized ||
        _disposed ||
        _rewardedInterstitial != null ||
        _rewardedInterstitialLoading ||
        (!retry && _rewardedInterstitialRetry?.isActive == true)) {
      return;
    }
    _rewardedInterstitialRetry?.cancel();
    _rewardedInterstitialRetry = null;
    AppLogger.info(
      'ad_load_requested',
      fields: {'ad_type': 'rewarded_interstitial'},
    );
    _rewardedInterstitialLoading = true;
    final completion = Completer<void>();
    try {
      await RewardedInterstitialAd.load(
        adUnitId: units.rewardedInterstitial,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedInterstitialLoading = false;
            _rewardedInterstitialFailures = 0;
            AppLogger.info(
              'ad_loaded',
              fields: {'ad_type': 'rewarded_interstitial'},
            );
            if (_disposed) {
              ad.dispose();
            } else {
              _rewardedInterstitial = ad;
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            _rewardedInterstitialLoading = false;
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'rewarded_interstitial'},
            );
            _scheduleRewardedInterstitialRetry();
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      _rewardedInterstitialLoading = false;
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'rewarded_interstitial'},
      );
      _scheduleRewardedInterstitialRetry();
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  void _scheduleInterstitialRetry() {
    if (_disposed || _interstitialRetry?.isActive == true) return;
    _interstitialFailures++;
    _interstitialRetry = Timer(
      adRetryDelayForFailure(_interstitialFailures),
      () {
        _interstitialRetry = null;
        unawaited(_loadInterstitial(retry: true));
      },
    );
  }

  void _scheduleRewardedRetry() {
    if (_disposed || _rewardedRetry?.isActive == true) return;
    _rewardedFailures++;
    _rewardedRetry = Timer(adRetryDelayForFailure(_rewardedFailures), () {
      _rewardedRetry = null;
      unawaited(_loadRewarded(retry: true));
    });
  }

  void _scheduleRewardedInterstitialRetry() {
    if (_disposed || _rewardedInterstitialRetry?.isActive == true) return;
    _rewardedInterstitialFailures++;
    _rewardedInterstitialRetry = Timer(
      adRetryDelayForFailure(_rewardedInterstitialFailures),
      () {
        _rewardedInterstitialRetry = null;
        unawaited(_loadRewardedInterstitial(retry: true));
      },
    );
  }

  void dispose() {
    _disposed = true;
    _interstitialRetry?.cancel();
    _rewardedRetry?.cancel();
    _rewardedInterstitialRetry?.cancel();
    _interstitial?.dispose();
    _rewarded?.dispose();
    _rewardedInterstitial?.dispose();
    _interstitial = null;
    _rewarded = null;
    _rewardedInterstitial = null;
  }
}

class InterstitialEligibilityPolicy {
  InterstitialEligibilityPolicy({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _lastCompletion;
  DateTime? _lastShown;
  int _shownThisSession = 0;
  bool firstEverSession = true;

  bool registerCompletionAndCanShow({
    required MonetizationConfig config,
    required bool keyboardVisible,
    required bool modalActive,
  }) {
    final now = _now();
    final rapid =
        _lastCompletion != null &&
        now.difference(_lastCompletion!).inSeconds <
            config.rapidCompletionWindowSeconds;
    _lastCompletion = now;
    if (firstEverSession ||
        rapid ||
        keyboardVisible ||
        modalActive ||
        !config.adsEnabled ||
        !config.interstitialAdsEnabled ||
        _shownThisSession >= config.interstitialSessionCap) {
      return false;
    }
    if (_lastShown != null &&
        now.difference(_lastShown!).inSeconds <
            config.interstitialCooldownSeconds) {
      return false;
    }
    return true;
  }

  void markShown() {
    _lastShown = _now();
    _shownThisSession++;
  }

  int get nextSessionAdCount => _shownThisSession + 1;
}

class CompletionAdCoordinator {
  CompletionAdCoordinator(this.ads, this.policy);

  final HomePilotAdsService ads;
  final InterstitialEligibilityPolicy policy;

  Future<void> initializeSession() async {
    if (!_supportsMobileAds) return;
    const storage = FlutterSecureStorage();
    final prior = await storage.read(key: _firstSessionStorageKey);
    policy.firstEverSession = prior == null;
    if (prior == null) {
      await storage.write(key: _firstSessionStorageKey, value: 'true');
    }
  }

  Future<bool> onTaskCompleted({
    required MonetizationConfig config,
    required bool keyboardVisible,
    required bool modalActive,
  }) async {
    if (!policy.registerCompletionAndCanShow(
      config: config,
      keyboardVisible: keyboardVisible,
      modalActive: modalActive,
    )) {
      return false;
    }
    final shown = await ads.showInterstitial(
      analyticsProperties: {
        'cooldown_remaining_sec': 0,
        'session_ad_count': policy.nextSessionAdCount,
      },
    );
    if (shown) policy.markShown();
    return shown;
  }
}

final completionAdCoordinatorProvider = Provider<CompletionAdCoordinator>((
  ref,
) {
  return CompletionAdCoordinator(
    ref.watch(homePilotAdsProvider),
    InterstitialEligibilityPolicy(),
  );
});

class HkNativeAdCard extends ConsumerStatefulWidget {
  const HkNativeAdCard({
    required this.placement,
    this.enabledOverride,
    super.key,
  });

  final String placement;
  final bool? enabledOverride;

  @override
  ConsumerState<HkNativeAdCard> createState() => _HkNativeAdCardState();
}

class _HkNativeAdCardState extends ConsumerState<HkNativeAdCard> {
  NativeAd? _ad;
  NativeAd? _pendingAd;
  bool _loaded = false;
  bool _failed = false;
  bool _loadStarted = false;
  int _loadFailures = 0;
  Timer? _retryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!(ModalRoute.isCurrentOf(context) ?? true)) {
      _deactivateForObscuredRoute();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _ad?.dispose();
    _pendingAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(monetizationConfigProvider).value;
    final consent = ref.watch(consentSnapshotProvider).value;
    final ads = ref.watch(homePilotAdsProvider);
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final presentationSuppressed =
        ref.watch(nativeAdPresentationDepthProvider) > 0;
    final enabled = nativeAdPlacementEnabled(
      routeIsCurrent: routeIsCurrent,
      presentationSuppressed: presentationSuppressed,
      configEnabled:
          (config?.adsEnabled ?? false) && (config?.nativeAdsEnabled ?? false),
      consentGranted: consent?.canRequestAds ?? false,
      adsInitialized: ads.initialized,
      platformSupported: _supportsMobileAds,
      enabledOverride: widget.enabledOverride,
    );
    if (enabled && !_loadStarted) {
      _loadStarted = true;
      scheduleMicrotask(() => _load(ads));
    }
    return HkNativeAdSlotFrame(
      collapsed: !enabled || _failed,
      child: _loaded && _ad != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AdWidget(ad: _ad!),
            )
          : const HkNativeAdLoadingSkeleton(),
    );
  }

  Future<void> _load(HomePilotAdsService ads) async {
    final repository = ref.read(monetizationRepositoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ad = NativeAd(
      adUnitId: ads.units.native(widget.placement),
      factoryId: _nativeFactoryId,
      customOptions: {
        'schemaVersion': 1,
        'isDark': isDark,
        'placement': widget.placement,
        'backgroundColor': isDark ? '#1C2632' : '#FFFFFF',
        'textColor': isDark ? '#E2E8F0' : '#0F172A',
      },
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (loadedAd) {
          if (_pendingAd == loadedAd) _pendingAd = null;
          if (!mounted ||
              _ad != loadedAd ||
              !(ModalRoute.isCurrentOf(context) ?? true)) {
            loadedAd.dispose();
            if (mounted && _ad == loadedAd) {
              _ad = null;
              _loaded = false;
              _loadStarted = false;
            }
            return;
          }
          setState(() {
            _ad = loadedAd as NativeAd;
            _loaded = true;
            _failed = false;
            _loadFailures = 0;
          });
          _retryTimer?.cancel();
          _retryTimer = null;
        },
        onAdFailedToLoad: (failedAd, _) {
          failedAd.dispose();
          final isTracked = _ad == failedAd || _pendingAd == failedAd;
          if (_pendingAd == failedAd) _pendingAd = null;
          if (_ad == failedAd) _ad = null;
          if (!mounted || !isTracked) return;
          setState(() {
            _loaded = false;
            _failed = true;
          });
          _scheduleRetry();
        },
        onAdImpression: (_) {
          unawaited(
            repository?.recordEvent('ad_native_impression', {
              'screen_name': widget.placement,
              'ad_unit_id': ads.units.native(widget.placement),
            }),
          );
        },
        onAdClicked: (_) {
          unawaited(
            repository?.recordEvent('ad_native_click', {
              'screen_name': widget.placement,
              'ad_unit_id': ads.units.native(widget.placement),
            }),
          );
        },
      ),
    );
    _ad = ad;
    _pendingAd = ad;
    await ad.load();
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive == true) return;
    _loadFailures++;
    _retryTimer = Timer(adRetryDelayForFailure(_loadFailures), () {
      _retryTimer = null;
      if (!mounted) return;
      setState(() {
        _failed = false;
        _loadStarted = false;
      });
    });
  }

  void _deactivateForObscuredRoute() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final ad = _ad;
    final pending = _pendingAd;
    _ad = null;
    _pendingAd = null;
    _loaded = false;
    _failed = false;
    _loadStarted = false;
    ad?.dispose();
    pending?.dispose();
  }
}

class HkNativeAdLoadingSkeleton extends StatelessWidget {
  const HkNativeAdLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = scheme.onSurfaceVariant.withValues(alpha: 0.14);
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('native-ad-loading-skeleton'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _NativeAdSkeletonBlock(
                width: 64,
                height: 64,
                color: placeholder,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NativeAdSkeletonBlock(
                      width: 132,
                      height: 12,
                      color: placeholder,
                    ),
                    const SizedBox(height: 8),
                    _NativeAdSkeletonBlock(
                      width: double.infinity,
                      height: 8,
                      color: placeholder,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _NativeAdSkeletonBlock(
                            width: double.infinity,
                            height: 8,
                            color: placeholder,
                          ),
                        ),
                        const SizedBox(width: 16),
                        _NativeAdSkeletonBlock(
                          width: 82,
                          height: 28,
                          color: placeholder,
                          radius: 8,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeAdSkeletonBlock extends StatelessWidget {
  const _NativeAdSkeletonBlock({
    required this.width,
    required this.height,
    required this.color,
    this.radius = 4,
  });

  final double width;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class HkNativeAdSlotFrame extends StatelessWidget {
  const HkNativeAdSlotFrame({
    required this.collapsed,
    required this.child,
    super.key,
  });

  final bool collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: SizedBox(
        height: collapsed ? 0 : 112,
        width: double.infinity,
        child: collapsed ? null : child,
      ),
    );
  }
}

class HkPointsPill extends ConsumerWidget {
  const HkPointsPill({required this.onTap, this.compact = false, super.key});

  static const width = 82.0;

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balance = ref.watch(pointWalletProvider).value?.balance;
    final pointsLabel = balance == null
        ? context.l10n.pointsUnavailable
        : context.l10n.pointsCount(balance);

    // Spec Component C: independent squircle tile (border-radius: 16px).
    // The solid filled star is enclosed in a circular tinted container.
    final height = compact ? 40.0 : 44.0;
    final starCircleSize = compact ? 28.0 : 32.0;
    final innerGap = compact ? 6.0 : HkSpacing.space6;
    final hPadStart = compact ? 6.0 : HkSpacing.xs;
    final hPadEnd = compact ? 10.0 : 14.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.lg),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
    );
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: pointsLabel,
      child: Tooltip(
        message: context.l10n.pointsWallet,
        excludeFromSemantics: true,
        child: SizedBox(
          height: height,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HkRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: HkColors.appTextPrimary.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: InkWell(
                customBorder: shape,
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: hPadStart,
                    end: hPadEnd,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: starCircleSize,
                        height: starCircleSize,
                        decoration: const BoxDecoration(
                          // spec: badge_green_bg #ECFDF5
                          color: HkColors.headerBadgeGreenBg,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Symbols.star_rounded,
                          size: 18,
                          // spec: badge_green_icon #10B981 solid filled
                          color: HkColors.headerBadgeGreenIcon,
                          fill: 1,
                        ),
                      ),
                      SizedBox(width: innerGap),
                      Text(
                        balance?.toString() ?? '-',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool get _supportsMobileAds =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
