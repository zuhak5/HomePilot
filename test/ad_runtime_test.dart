import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/features/monetization/ad_runtime.dart';

void main() {
  const eligible = AdRuntimeEligibility(
    platformSupported: true,
    appForeground: true,
    consentUpdated: true,
    canRequestAds: true,
    adsEnabled: true,
    nativeEnabled: true,
    interstitialEnabled: true,
    rewardedEnabled: true,
    rewardedInterstitialEnabled: true,
  );

  test('runtime requires every hard gate at load boundary', () {
    expect(eligible.canLoad(AdFormat.interstitial), isTrue);
    expect(
      const AdRuntimeEligibility(
        platformSupported: true,
        appForeground: false,
        consentUpdated: true,
        canRequestAds: true,
        adsEnabled: true,
        nativeEnabled: true,
        interstitialEnabled: true,
        rewardedEnabled: true,
        rewardedInterstitialEnabled: true,
      ).canLoad(AdFormat.interstitial),
      isFalse,
    );
    expect(
      const AdRuntimeEligibility(
        platformSupported: true,
        appForeground: true,
        consentUpdated: false,
        canRequestAds: true,
        adsEnabled: true,
        nativeEnabled: true,
        interstitialEnabled: true,
        rewardedEnabled: true,
        rewardedInterstitialEnabled: true,
      ).canLoad(AdFormat.interstitial),
      isFalse,
    );
    expect(
      const AdRuntimeEligibility(
        platformSupported: true,
        appForeground: true,
        consentUpdated: true,
        canRequestAds: true,
        adsEnabled: true,
        nativeEnabled: true,
        interstitialEnabled: false,
        rewardedEnabled: true,
        rewardedInterstitialEnabled: true,
      ).canLoad(AdFormat.interstitial),
      isFalse,
    );
  });

  test('eligibility transitions increment generation once', () {
    final runtime = AdRuntimeController();
    expect(runtime.generation, 0);
    expect(runtime.update(eligible), isTrue);
    final generation = runtime.generation;
    expect(generation, 1);
    expect(runtime.update(eligible), isFalse);
    expect(runtime.generation, generation);
    expect(runtime.isCurrent(generation), isTrue);
    runtime.invalidate();
    expect(runtime.isCurrent(generation), isFalse);
  });

  test('cache rejects ad at the 55 minute safety boundary', () {
    final loadedAt = DateTime.utc(2026, 8, 8, 12);
    final cached = CachedAd<String>(ad: 'ad', loadedAt: loadedAt);
    expect(
      cached.isFresh(loadedAt.add(const Duration(minutes: 54, seconds: 59))),
      isTrue,
    );
    expect(cached.isFresh(loadedAt.add(const Duration(minutes: 55))), isFalse);
  });

  test('retry policy classifies stable Google error codes', () {
    const policy = AdRetryPolicy();
    expect(
      policy.classify(code: 1, domain: 'com.google.android.gms.ads'),
      AdFailureClass.invalidRequest,
    );
    expect(
      policy.classify(code: 2, domain: 'com.google.android.gms.ads'),
      AdFailureClass.network,
    );
    expect(
      policy.classify(code: 3, domain: 'com.google.android.gms.ads'),
      AdFailureClass.noFill,
    );
  });

  test('network retries are bounded and jittered', () {
    const policy = AdRetryPolicy();
    expect(
      policy.decision(
        failure: AdFailureClass.network,
        attempt: 1,
        jitterUnit: 0.5,
      ).delay,
      const Duration(seconds: 2),
    );
    expect(
      policy.decision(
        failure: AdFailureClass.network,
        attempt: 4,
        jitterUnit: 0.5,
      ).delay,
      const Duration(seconds: 60),
    );
    expect(
      policy.decision(failure: AdFailureClass.network, attempt: 5).shouldRetry,
      isFalse,
    );
    expect(
      policy
          .decision(failure: AdFailureClass.invalidRequest, attempt: 1)
          .shouldRetry,
      isFalse,
    );
    expect(
      policy.decision(failure: AdFailureClass.noFill, attempt: 1).shouldRetry,
      isFalse,
    );
  });
}
