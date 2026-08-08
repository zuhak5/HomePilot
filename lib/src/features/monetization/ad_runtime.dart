import 'dart:math' as math;

enum AdFormat { native, interstitial, rewarded, rewardedInterstitial }

enum AdFailureClass { invalidRequest, network, noFill, internal, unknown }

const Duration kAdCacheMaxAge = Duration(minutes: 55);

class AdRuntimeEligibility {
  const AdRuntimeEligibility({
    required this.platformSupported,
    required this.appForeground,
    required this.consentUpdated,
    required this.canRequestAds,
    required this.adsEnabled,
    required this.nativeEnabled,
    required this.interstitialEnabled,
    required this.rewardedEnabled,
    required this.rewardedInterstitialEnabled,
  });

  const AdRuntimeEligibility.blocked()
    : platformSupported = false,
      appForeground = false,
      consentUpdated = false,
      canRequestAds = false,
      adsEnabled = false,
      nativeEnabled = false,
      interstitialEnabled = false,
      rewardedEnabled = false,
      rewardedInterstitialEnabled = false;

  final bool platformSupported;
  final bool appForeground;
  final bool consentUpdated;
  final bool canRequestAds;
  final bool adsEnabled;
  final bool nativeEnabled;
  final bool interstitialEnabled;
  final bool rewardedEnabled;
  final bool rewardedInterstitialEnabled;

  bool canLoad(AdFormat format) {
    if (!platformSupported ||
        !appForeground ||
        !consentUpdated ||
        !canRequestAds ||
        !adsEnabled) {
      return false;
    }
    return switch (format) {
      AdFormat.native => nativeEnabled,
      AdFormat.interstitial => interstitialEnabled,
      AdFormat.rewarded => rewardedEnabled,
      AdFormat.rewardedInterstitial => rewardedInterstitialEnabled,
    };
  }

  bool canShow(AdFormat format) => canLoad(format);

  @override
  bool operator ==(Object other) =>
      other is AdRuntimeEligibility &&
      other.platformSupported == platformSupported &&
      other.appForeground == appForeground &&
      other.consentUpdated == consentUpdated &&
      other.canRequestAds == canRequestAds &&
      other.adsEnabled == adsEnabled &&
      other.nativeEnabled == nativeEnabled &&
      other.interstitialEnabled == interstitialEnabled &&
      other.rewardedEnabled == rewardedEnabled &&
      other.rewardedInterstitialEnabled == rewardedInterstitialEnabled;

  @override
  int get hashCode => Object.hash(
    platformSupported,
    appForeground,
    consentUpdated,
    canRequestAds,
    adsEnabled,
    nativeEnabled,
    interstitialEnabled,
    rewardedEnabled,
    rewardedInterstitialEnabled,
  );
}

class AdRuntimeController {
  AdRuntimeController([
    AdRuntimeEligibility initial = const AdRuntimeEligibility.blocked(),
  ]) : _eligibility = initial;

  AdRuntimeEligibility _eligibility;
  int _generation = 0;

  AdRuntimeEligibility get eligibility => _eligibility;
  int get generation => _generation;

  bool update(AdRuntimeEligibility next) {
    if (next == _eligibility) return false;
    _eligibility = next;
    _generation++;
    return true;
  }

  void invalidate() {
    _generation++;
  }

  bool isCurrent(int capturedGeneration) => capturedGeneration == _generation;
}

class CachedAd<T> {
  const CachedAd({required this.ad, required this.loadedAt});

  final T ad;
  final DateTime loadedAt;

  bool isFresh(
    DateTime now, {
    Duration maxAge = kAdCacheMaxAge,
  }) => now.difference(loadedAt) < maxAge;
}

class AdRetryDecision {
  const AdRetryDecision.retry(this.delay) : shouldRetry = true;
  const AdRetryDecision.stop() : shouldRetry = false, delay = Duration.zero;

  final bool shouldRetry;
  final Duration delay;
}

class AdRetryPolicy {
  const AdRetryPolicy({this.maxNetworkAttempts = 4, this.jitterFraction = 0.20});

  final int maxNetworkAttempts;
  final double jitterFraction;

  AdFailureClass classify({required int code, required String domain}) {
    // Google Mobile Ads documents these stable numeric Android error codes:
    // 0 internal, 1 invalid request, 2 network, 3 no fill. Unknown SDK/domain
    // values deliberately receive the conservative unknown policy.
    return switch (code) {
      0 => AdFailureClass.internal,
      1 => AdFailureClass.invalidRequest,
      2 => AdFailureClass.network,
      3 => AdFailureClass.noFill,
      _ => AdFailureClass.unknown,
    };
  }

  AdRetryDecision decision({
    required AdFailureClass failure,
    required int attempt,
    double jitterUnit = 0.5,
  }) {
    if (attempt <= 0) return const AdRetryDecision.stop();
    final base = switch (failure) {
      AdFailureClass.invalidRequest || AdFailureClass.noFill => null,
      AdFailureClass.network => attempt > maxNetworkAttempts
          ? null
          : const [2, 8, 30, 60][attempt - 1],
      AdFailureClass.internal || AdFailureClass.unknown => attempt > 2
          ? null
          : const [8, 30][attempt - 1],
    };
    if (base == null) return const AdRetryDecision.stop();

    final clamped = jitterUnit.clamp(0.0, 1.0);
    final multiplier = 1 - jitterFraction + (2 * jitterFraction * clamped);
    final milliseconds = math.max(1, (base * 1000 * multiplier).round());
    return AdRetryDecision.retry(Duration(milliseconds: milliseconds));
  }
}
