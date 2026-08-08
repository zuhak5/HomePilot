#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def apply() -> None:
    path = "lib/src/features/monetization/monetization.dart"
    text = read(path)
    if "import 'ad_runtime.dart';" not in text:
        text = text.replace(
            "import '../auth/presentation/auth_providers.dart';\n",
            "import '../auth/presentation/auth_providers.dart';\n\nimport 'ad_runtime.dart';\n",
            1,
        )

    # Keep the compatibility helper for older focused tests, but make it expose
    # the bounded network policy rather than the old unbounded capped-delay loop.
    text = re.sub(
        r"@visibleForTesting\nDuration adRetryDelayForFailure\(int failureCount\) \{.*?\n\}\n",
        "@visibleForTesting\n"
        "Duration adRetryDelayForFailure(int failureCount) {\n"
        "  final decision = const AdRetryPolicy().decision(\n"
        "    failure: AdFailureClass.network,\n"
        "    attempt: failureCount,\n"
        "    jitterUnit: 0.5,\n"
        "  );\n"
        "  return decision.shouldRetry ? decision.delay : Duration.zero;\n"
        "}\n",
        text,
        count=1,
        flags=re.S,
    )

    bootstrap_pattern = re.compile(
        r"class _MonetizationBootstrapState extends ConsumerState<MonetizationBootstrap> \{.*?\n\}\n\nclass HomePilotAdUnits",
        re.S,
    )
    bootstrap = r'''class _MonetizationBootstrapState extends ConsumerState<MonetizationBootstrap>
    with WidgetsBindingObserver {
  AppLifecycleState _lifecycle =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(() async {
      await ref.read(completionAdCoordinatorProvider).initializeSession();
      await ref.read(consentServiceProvider).initialize();
      _syncRuntime();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncRuntime();
  }

  void _syncRuntime() {
    if (!mounted) return;
    final config =
        ref.read(monetizationConfigProvider).value ??
        const MonetizationConfig.failClosed();
    final consent =
        ref.read(consentSnapshotProvider).value ??
        const ConsentSnapshot.initial();
    ref.read(homePilotAdsProvider).updateRuntime(
      config: config,
      consent: consent,
      appForeground: _lifecycle == AppLifecycleState.resumed,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(monetizationConfigProvider, (_, _) => _syncRuntime());
    ref.listen(consentSnapshotProvider, (_, _) => _syncRuntime());
    return widget.child;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class HomePilotAdUnits'''
    text, count = bootstrap_pattern.subn(bootstrap, text, count=1)
    if count != 1:
        raise RuntimeError(f"monetization bootstrap shape changed: {count}")

    service_pattern = re.compile(
        r"class HomePilotAdsService \{.*?\n\}\n\nclass InterstitialEligibilityPolicy",
        re.S,
    )
    service = r'''class HomePilotAdsService {
  HomePilotAdsService({
    required this.useProductionUnits,
    required this.repository,
    this.timeZoneResolver = resolveSystemRewardTimeZone,
    DateTime Function()? now,
    double Function()? jitterUnit,
  }) : units = HomePilotAdUnits(production: useProductionUnits),
       _now = now ?? DateTime.now,
       _jitterUnit = jitterUnit ?? _defaultJitterUnit;

  final bool useProductionUnits;
  final MonetizationRepository? repository;
  final Future<String?> Function(String? fallback) timeZoneResolver;
  final HomePilotAdUnits units;
  final DateTime Function() _now;
  final double Function() _jitterUnit;
  final AdRuntimeController _runtime = AdRuntimeController();
  final AdRetryPolicy _retryPolicy = const AdRetryPolicy();

  bool _initialized = false;
  bool _preloading = false;
  bool _disposed = false;
  bool _interstitialLoading = false;
  bool _rewardedLoading = false;
  bool _rewardedInterstitialLoading = false;
  bool _fullScreenActive = false;
  int _interstitialFailures = 0;
  int _rewardedFailures = 0;
  int _rewardedInterstitialFailures = 0;
  Timer? _interstitialRetry;
  Timer? _rewardedRetry;
  Timer? _rewardedInterstitialRetry;
  CachedAd<InterstitialAd>? _interstitial;
  CachedAd<RewardedAd>? _rewarded;
  CachedAd<RewardedInterstitialAd>? _rewardedInterstitial;

  bool get initialized => _initialized;
  int get runtimeGeneration => _runtime.generation;
  AdRuntimeEligibility get runtimeEligibility => _runtime.eligibility;
  bool canLoad(AdFormat format) =>
      !_disposed && _initialized && _runtime.eligibility.canLoad(format);
  bool isGenerationCurrent(int generation) =>
      !_disposed && _runtime.isCurrent(generation);

  static double _defaultJitterUnit() =>
      (DateTime.now().microsecondsSinceEpoch % 1000) / 999.0;

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
    if (_disposed) return;
    _initialized = true;
    unawaited(preloadFullScreenAds());
  }

  void updateRuntime({
    required MonetizationConfig config,
    required ConsentSnapshot consent,
    required bool appForeground,
  }) {
    if (_disposed) return;
    final next = AdRuntimeEligibility(
      platformSupported: _supportsMobileAds,
      appForeground: appForeground,
      consentUpdated: consent.updated,
      canRequestAds: consent.canRequestAds,
      adsEnabled: config.adsEnabled,
      nativeEnabled: config.nativeAdsEnabled,
      interstitialEnabled: config.interstitialAdsEnabled,
      rewardedEnabled: config.rewardedAdsEnabled,
      rewardedInterstitialEnabled: config.rewardedInterstitialEnabled,
    );
    final changed = _runtime.update(next);
    if (!changed) {
      if (appForeground) _purgeStaleAds();
      return;
    }

    _cancelRetries();
    _interstitialFailures = 0;
    _rewardedFailures = 0;
    _rewardedInterstitialFailures = 0;
    _purgeStaleAds();

    // A background transition invalidates in-flight callbacks but retains a
    // fresh ready cache. Consent/config revocation destroys the affected cache.
    if (!consent.updated || !consent.canRequestAds || !config.adsEnabled) {
      _disposeAllReadyAds();
    } else {
      if (!config.interstitialAdsEnabled) _disposeInterstitial();
      if (!config.rewardedAdsEnabled) _disposeRewarded();
      if (!config.rewardedInterstitialEnabled) _disposeRewardedInterstitial();
    }

    if (appForeground && _initialized) {
      unawaited(preloadFullScreenAds());
    }
  }

  Future<void> preloadFullScreenAds() async {
    if (_preloading || _disposed || !_initialized) return;
    _purgeStaleAds();
    _preloading = true;
    try {
      await Future.wait([
        if (_interstitial == null && canLoad(AdFormat.interstitial))
          _loadInterstitial(),
        if (_rewarded == null && canLoad(AdFormat.rewarded)) _loadRewarded(),
        if (_rewardedInterstitial == null &&
            canLoad(AdFormat.rewardedInterstitial))
          _loadRewardedInterstitial(),
      ]);
    } finally {
      _preloading = false;
    }
  }

  Future<bool> showInterstitial({
    Map<String, dynamic> analyticsProperties = const {},
  }) async {
    if (_fullScreenActive || !canLoad(AdFormat.interstitial)) return false;
    final cached = _interstitial;
    if (cached == null || !cached.isFresh(_now())) {
      _disposeInterstitial();
      unawaited(_loadInterstitial());
      return false;
    }
    final ad = cached.ad;
    _interstitial = null;
    _fullScreenActive = true;
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
        _fullScreenActive = false;
        if (!completion.isCompleted) completion.complete(true);
        if (canLoad(AdFormat.interstitial)) unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        AppLogger.warning('interstitial_show', error: error);
        failedAd.dispose();
        _fullScreenActive = false;
        if (!completion.isCompleted) completion.complete(false);
        if (canLoad(AdFormat.interstitial)) unawaited(_loadInterstitial());
      },
    );
    try {
      await ad.show();
    } on Object catch (error) {
      AppLogger.warning('interstitial_show', error: error);
      ad.dispose();
      _fullScreenActive = false;
      if (!completion.isCompleted) completion.complete(false);
    }
    return completion.future;
  }

  Future<RewardShowResult> showReward(
    RewardAdType type, {
    required String? timeZone,
    required String entryPoint,
  }) async {
    final format = type == RewardAdType.rewardedAd
        ? AdFormat.rewarded
        : AdFormat.rewardedInterstitial;
    if (_fullScreenActive || repository == null || !canLoad(format)) {
      return RewardShowResult.unavailable;
    }
    _purgeStaleAds();
    final adAvailable = type == RewardAdType.rewardedAd
        ? _rewarded != null
        : _rewardedInterstitial != null;
    if (!adAvailable) {
      _resetRewardRetry(type);
      if (type == RewardAdType.rewardedAd) {
        unawaited(_loadRewarded());
      } else {
        unawaited(_loadRewardedInterstitial());
      }
      return RewardShowResult.unavailable;
    }

    // Reserve the single full-screen slot before the server claim request so
    // concurrent user actions cannot create competing claims/presentations.
    _fullScreenActive = true;
    final generation = _runtime.generation;
    RewardClaimRequest claim;
    try {
      final resolvedTimeZone = await timeZoneResolver(timeZone);
      claim = await repository!.createRewardClaim(
        type,
        timeZone: resolvedTimeZone,
      );
    } on Object {
      _fullScreenActive = false;
      return RewardShowResult.rejected;
    }
    if (!_runtime.isCurrent(generation) || !canLoad(format)) {
      _fullScreenActive = false;
      return RewardShowResult.unavailable;
    }

    final earned = Completer<bool>();
    final dismissed = Completer<void>();
    var failedToShow = false;
    if (type == RewardAdType.rewardedAd) {
      final cached = _rewarded;
      if (cached == null || !cached.isFresh(_now())) {
        _disposeRewarded();
        _fullScreenActive = false;
        return RewardShowResult.unavailable;
      }
      final ad = cached.ad;
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
          _fullScreenActive = false;
          if (!dismissed.isCompleted) dismissed.complete();
          if (canLoad(AdFormat.rewarded)) unawaited(_loadRewarded());
        },
        onAdFailedToShowFullScreenContent: (failedAd, error) {
          AppLogger.warning('rewarded_show', error: error);
          failedToShow = true;
          failedAd.dispose();
          _fullScreenActive = false;
          if (!earned.isCompleted) earned.complete(false);
          if (!dismissed.isCompleted) dismissed.complete();
          if (canLoad(AdFormat.rewarded)) unawaited(_loadRewarded());
        },
      );
      try {
        await ad.show(
          onUserEarnedReward: (_, reward) {
            // Reward callbacks are observation only. Wallet credit remains SSV
            // + database-authoritative and is never mutated from this callback.
            AppLogger.info(
              'ad_rewarded',
              fields: {'ad_type': 'rewarded', 'reward_amount': reward.amount},
            );
            if (!earned.isCompleted) earned.complete(true);
          },
        );
      } on Object catch (error) {
        AppLogger.warning('rewarded_show', error: error);
        ad.dispose();
        failedToShow = true;
        _fullScreenActive = false;
        if (!earned.isCompleted) earned.complete(false);
        if (!dismissed.isCompleted) dismissed.complete();
      }
    } else {
      final cached = _rewardedInterstitial;
      if (cached == null || !cached.isFresh(_now())) {
        _disposeRewardedInterstitial();
        _fullScreenActive = false;
        return RewardShowResult.unavailable;
      }
      final ad = cached.ad;
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
              _fullScreenActive = false;
              if (!dismissed.isCompleted) dismissed.complete();
              if (canLoad(AdFormat.rewardedInterstitial)) {
                unawaited(_loadRewardedInterstitial());
              }
            },
            onAdFailedToShowFullScreenContent: (failedAd, error) {
              AppLogger.warning('rewarded_interstitial_show', error: error);
              failedToShow = true;
              failedAd.dispose();
              _fullScreenActive = false;
              if (!earned.isCompleted) earned.complete(false);
              if (!dismissed.isCompleted) dismissed.complete();
              if (canLoad(AdFormat.rewardedInterstitial)) {
                unawaited(_loadRewardedInterstitial());
              }
            },
          );
      try {
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
      } on Object catch (error) {
        AppLogger.warning('rewarded_interstitial_show', error: error);
        ad.dispose();
        failedToShow = true;
        _fullScreenActive = false;
        if (!earned.isCompleted) earned.complete(false);
        if (!dismissed.isCompleted) dismissed.complete();
      }
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
    return RewardShowResult.shownAwaitingServerVerification;
  }

  Future<void> _loadInterstitial({bool retry = false}) async {
    if (!canLoad(AdFormat.interstitial) ||
        _interstitial != null ||
        _interstitialLoading ||
        (!retry && _interstitialRetry?.isActive == true)) {
      return;
    }
    _interstitialRetry?.cancel();
    _interstitialRetry = null;
    _interstitialLoading = true;
    final generation = _runtime.generation;
    final completion = Completer<void>();
    try {
      await InterstitialAd.load(
        adUnitId: units.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialLoading = false;
            if (!_acceptLoad(generation, AdFormat.interstitial)) {
              ad.dispose();
            } else {
              _interstitialFailures = 0;
              _interstitial = CachedAd(ad: ad, loadedAt: _now());
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            _interstitialLoading = false;
            _scheduleInterstitialRetry(error);
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      _interstitialLoading = false;
      _scheduleUnknownInterstitialRetry(error);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewarded({bool retry = false}) async {
    if (!canLoad(AdFormat.rewarded) ||
        _rewarded != null ||
        _rewardedLoading ||
        (!retry && _rewardedRetry?.isActive == true)) {
      return;
    }
    _rewardedRetry?.cancel();
    _rewardedRetry = null;
    _rewardedLoading = true;
    final generation = _runtime.generation;
    final completion = Completer<void>();
    try {
      await RewardedAd.load(
        adUnitId: units.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedLoading = false;
            if (!_acceptLoad(generation, AdFormat.rewarded)) {
              ad.dispose();
            } else {
              _rewardedFailures = 0;
              _rewarded = CachedAd(ad: ad, loadedAt: _now());
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            _rewardedLoading = false;
            _scheduleRewardedRetry(error);
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      _rewardedLoading = false;
      _scheduleUnknownRewardedRetry(error);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewardedInterstitial({bool retry = false}) async {
    if (!canLoad(AdFormat.rewardedInterstitial) ||
        _rewardedInterstitial != null ||
        _rewardedInterstitialLoading ||
        (!retry && _rewardedInterstitialRetry?.isActive == true)) {
      return;
    }
    _rewardedInterstitialRetry?.cancel();
    _rewardedInterstitialRetry = null;
    _rewardedInterstitialLoading = true;
    final generation = _runtime.generation;
    final completion = Completer<void>();
    try {
      await RewardedInterstitialAd.load(
        adUnitId: units.rewardedInterstitial,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedInterstitialLoading = false;
            if (!_acceptLoad(generation, AdFormat.rewardedInterstitial)) {
              ad.dispose();
            } else {
              _rewardedInterstitialFailures = 0;
              _rewardedInterstitial = CachedAd(ad: ad, loadedAt: _now());
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            _rewardedInterstitialLoading = false;
            _scheduleRewardedInterstitialRetry(error);
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      _rewardedInterstitialLoading = false;
      _scheduleUnknownRewardedInterstitialRetry(error);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  bool _acceptLoad(int generation, AdFormat format) =>
      !_disposed && _runtime.isCurrent(generation) && canLoad(format);

  void _scheduleInterstitialRetry(LoadAdError error) {
    _interstitialFailures++;
    _interstitialRetry = _scheduleRetry(
      format: AdFormat.interstitial,
      failure: _retryPolicy.classify(code: error.code, domain: error.domain),
      attempt: _interstitialFailures,
      retry: () => _loadInterstitial(retry: true),
    );
  }

  void _scheduleRewardedRetry(LoadAdError error) {
    _rewardedFailures++;
    _rewardedRetry = _scheduleRetry(
      format: AdFormat.rewarded,
      failure: _retryPolicy.classify(code: error.code, domain: error.domain),
      attempt: _rewardedFailures,
      retry: () => _loadRewarded(retry: true),
    );
  }

  void _scheduleRewardedInterstitialRetry(LoadAdError error) {
    _rewardedInterstitialFailures++;
    _rewardedInterstitialRetry = _scheduleRetry(
      format: AdFormat.rewardedInterstitial,
      failure: _retryPolicy.classify(code: error.code, domain: error.domain),
      attempt: _rewardedInterstitialFailures,
      retry: () => _loadRewardedInterstitial(retry: true),
    );
  }

  void _scheduleUnknownInterstitialRetry(Object error) {
    AppLogger.warning('ad_load_failed', error: error, fields: {'ad_type': 'interstitial'});
    _interstitialFailures++;
    _interstitialRetry = _scheduleRetry(
      format: AdFormat.interstitial,
      failure: AdFailureClass.unknown,
      attempt: _interstitialFailures,
      retry: () => _loadInterstitial(retry: true),
    );
  }

  void _scheduleUnknownRewardedRetry(Object error) {
    AppLogger.warning('ad_load_failed', error: error, fields: {'ad_type': 'rewarded'});
    _rewardedFailures++;
    _rewardedRetry = _scheduleRetry(
      format: AdFormat.rewarded,
      failure: AdFailureClass.unknown,
      attempt: _rewardedFailures,
      retry: () => _loadRewarded(retry: true),
    );
  }

  void _scheduleUnknownRewardedInterstitialRetry(Object error) {
    AppLogger.warning('ad_load_failed', error: error, fields: {'ad_type': 'rewarded_interstitial'});
    _rewardedInterstitialFailures++;
    _rewardedInterstitialRetry = _scheduleRetry(
      format: AdFormat.rewardedInterstitial,
      failure: AdFailureClass.unknown,
      attempt: _rewardedInterstitialFailures,
      retry: () => _loadRewardedInterstitial(retry: true),
    );
  }

  Timer? _scheduleRetry({
    required AdFormat format,
    required AdFailureClass failure,
    required int attempt,
    required Future<void> Function() retry,
  }) {
    if (!canLoad(format)) return null;
    final decision = _retryPolicy.decision(
      failure: failure,
      attempt: attempt,
      jitterUnit: _jitterUnit(),
    );
    if (!decision.shouldRetry) {
      AppLogger.info('ad_retry_exhausted', fields: {
        'ad_type': format.name,
        'failure_class': failure.name,
        'attempt': attempt,
      });
      return null;
    }
    final generation = _runtime.generation;
    return Timer(decision.delay, () {
      if (!_runtime.isCurrent(generation) || !canLoad(format)) return;
      unawaited(retry());
    });
  }

  void _resetRewardRetry(RewardAdType type) {
    if (type == RewardAdType.rewardedAd) {
      _rewardedRetry?.cancel();
      _rewardedRetry = null;
      _rewardedFailures = 0;
    } else {
      _rewardedInterstitialRetry?.cancel();
      _rewardedInterstitialRetry = null;
      _rewardedInterstitialFailures = 0;
    }
  }

  void _purgeStaleAds() {
    final now = _now();
    if (_interstitial != null && !_interstitial!.isFresh(now)) _disposeInterstitial();
    if (_rewarded != null && !_rewarded!.isFresh(now)) _disposeRewarded();
    if (_rewardedInterstitial != null && !_rewardedInterstitial!.isFresh(now)) {
      _disposeRewardedInterstitial();
    }
  }

  void _cancelRetries() {
    _interstitialRetry?.cancel();
    _rewardedRetry?.cancel();
    _rewardedInterstitialRetry?.cancel();
    _interstitialRetry = null;
    _rewardedRetry = null;
    _rewardedInterstitialRetry = null;
  }

  void _disposeInterstitial() {
    final cached = _interstitial;
    _interstitial = null;
    cached?.ad.dispose();
  }

  void _disposeRewarded() {
    final cached = _rewarded;
    _rewarded = null;
    cached?.ad.dispose();
  }

  void _disposeRewardedInterstitial() {
    final cached = _rewardedInterstitial;
    _rewardedInterstitial = null;
    cached?.ad.dispose();
  }

  void _disposeAllReadyAds() {
    _disposeInterstitial();
    _disposeRewarded();
    _disposeRewardedInterstitial();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runtime.invalidate();
    _cancelRetries();
    _disposeAllReadyAds();
  }
}

class InterstitialEligibilityPolicy'''
    text, count = service_pattern.subn(service, text, count=1)
    if count != 1:
        raise RuntimeError(f"HomePilotAdsService shape changed: {count}")

    # Runtime hard-gates native requests. Keep the pure placement helper for its
    # isolated geometry/route tests, but production no longer treats SDK init as
    # permission to request forever.
    text = text.replace(
        "      consentGranted: consent?.canRequestAds ?? false,\n      adsInitialized: ads.initialized,\n      platformSupported: _supportsMobileAds,",
        "      consentGranted: consent?.canRequestAds ?? false,\n      adsInitialized: ads.canLoad(AdFormat.native),\n      platformSupported: _supportsMobileAds,",
        1,
    )

    # Eliminate the second native-ad owner and bound retries. The one `_ad`
    # field owns the object from construction until success/failure/deactivation.
    text = text.replace("  NativeAd? _pendingAd;\n", "")
    text = text.replace("    _pendingAd?.dispose();\n", "")
    text = text.replace("          if (_pendingAd == loadedAd) _pendingAd = null;\n", "")
    text = text.replace(
        "          final isTracked = _ad == failedAd || _pendingAd == failedAd;\n          if (_pendingAd == failedAd) _pendingAd = null;\n",
        "          final isTracked = _ad == failedAd;\n",
    )
    text = text.replace("    _pendingAd = ad;\n", "")
    text = text.replace(
        "    final repository = ref.read(monetizationRepositoryProvider);\n    final isDark = Theme.of(context).brightness == Brightness.dark;",
        "    final repository = ref.read(monetizationRepositoryProvider);\n"
        "    final generation = ads.runtimeGeneration;\n"
        "    if (!ads.canLoad(AdFormat.native)) {\n"
        "      if (mounted) setState(() => _loadStarted = false);\n"
        "      return;\n"
        "    }\n"
        "    final isDark = Theme.of(context).brightness == Brightness.dark;",
        1,
    )
    text = text.replace(
        "          if (!mounted ||\n              _ad != loadedAd ||\n              !(ModalRoute.isCurrentOf(context) ?? true)) {",
        "          if (!mounted ||\n              _ad != loadedAd ||\n              !ads.isGenerationCurrent(generation) ||\n              !ads.canLoad(AdFormat.native) ||\n              !(ModalRoute.isCurrentOf(context) ?? true)) {",
        1,
    )
    text = text.replace(
        "        onAdFailedToLoad: (failedAd, _) {",
        "        onAdFailedToLoad: (failedAd, error) {",
        1,
    )
    text = text.replace("          _scheduleRetry();\n", "          _scheduleRetry(error);\n", 1)
    native_retry = re.compile(
        r"  void _scheduleRetry\(\) \{.*?\n  \}\n\n  void _deactivateForObscuredRoute\(\) \{",
        re.S,
    )
    native_retry_replacement = r'''  void _scheduleRetry(LoadAdError error) {
    if (_retryTimer?.isActive == true) return;
    _loadFailures++;
    final policy = const AdRetryPolicy();
    final decision = policy.decision(
      failure: policy.classify(code: error.code, domain: error.domain),
      attempt: _loadFailures,
      jitterUnit: (DateTime.now().microsecondsSinceEpoch % 1000) / 999.0,
    );
    if (!decision.shouldRetry) return;
    final ads = ref.read(homePilotAdsProvider);
    final generation = ads.runtimeGeneration;
    _retryTimer = Timer(decision.delay, () {
      _retryTimer = null;
      if (!mounted ||
          !ads.isGenerationCurrent(generation) ||
          !ads.canLoad(AdFormat.native)) {
        return;
      }
      setState(() {
        _failed = false;
        _loadStarted = false;
      });
    });
  }

  void _deactivateForObscuredRoute() {'''
    text, count = native_retry.subn(native_retry_replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"native retry shape changed: {count}")
    text = text.replace(
        "    final pending = _pendingAd;\n    _ad = null;\n    _pendingAd = null;\n",
        "    _ad = null;\n",
        1,
    )
    text = text.replace(
        "    ad?.dispose();\n    if (pending != null && pending != ad) pending.dispose();\n",
        "    ad?.dispose();\n",
        1,
    )
    write(path, text)

    test_path = "test/monetization_test.dart"
    tests = read(test_path)
    old = '''  test('ad preloader retry delay backs off and caps at one minute', () {
    expect(adRetryDelayForFailure(1), const Duration(seconds: 2));
    expect(adRetryDelayForFailure(2), const Duration(seconds: 4));
    expect(adRetryDelayForFailure(6), const Duration(seconds: 60));
    expect(adRetryDelayForFailure(99), const Duration(seconds: 60));
  });'''
    new = '''  test('compatibility retry helper exposes bounded network policy', () {
    expect(adRetryDelayForFailure(1), const Duration(seconds: 2));
    expect(adRetryDelayForFailure(2), const Duration(seconds: 8));
    expect(adRetryDelayForFailure(4), const Duration(seconds: 60));
    expect(adRetryDelayForFailure(5), Duration.zero);
    expect(adRetryDelayForFailure(99), Duration.zero);
  });'''
    if old not in tests:
        raise RuntimeError("legacy retry test shape changed")
    write(test_path, tests.replace(old, new, 1))


if __name__ == "__main__":
    apply()
