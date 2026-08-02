import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/features/monetization/monetization.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('InterstitialEligibilityPolicy', () {
    late DateTime now;
    late InterstitialEligibilityPolicy policy;
    const config = MonetizationConfig(
      adsEnabled: true,
      nativeAdsEnabled: true,
      interstitialAdsEnabled: true,
      rewardedAdsEnabled: true,
      rewardedInterstitialEnabled: true,
      pointsEnabled: true,
      emergencyFreeCreationMode: false,
      walletCap: 20,
      interstitialCooldownSeconds: 180,
      rapidCompletionWindowSeconds: 60,
      interstitialSessionCap: 2,
    );

    setUp(() {
      now = DateTime.utc(2026, 8, 1, 10);
      policy = InterstitialEligibilityPolicy(now: () => now)
        ..firstEverSession = false;
    });

    test('allows an eligible completion and enforces cooldown', () {
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
      policy.markShown();
      now = now.add(const Duration(seconds: 181));
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
    });

    test(
      'suppresses rapid completions, keyboard, modal, and first session',
      () {
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: false,
          ),
          isTrue,
        );
        now = now.add(const Duration(seconds: 30));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: false,
          ),
          isFalse,
        );
        now = now.add(const Duration(seconds: 61));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: true,
            modalActive: false,
          ),
          isFalse,
        );
        now = now.add(const Duration(seconds: 61));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: true,
          ),
          isFalse,
        );
        policy.firstEverSession = true;
        now = now.add(const Duration(seconds: 61));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: false,
          ),
          isFalse,
        );
      },
    );

    test('honors the remote session cap and kill switch', () {
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
      policy.markShown();
      now = now.add(const Duration(seconds: 181));
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
      policy.markShown();
      now = now.add(const Duration(seconds: 181));
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isFalse,
      );
      const disabled = MonetizationConfig.failClosed();
      expect(
        InterstitialEligibilityPolicy(now: () => now)..firstEverSession = false,
        isNotNull,
      );
      expect(
        policy.registerCompletionAndCanShow(
          config: disabled,
          keyboardVisible: false,
          modalActive: false,
        ),
        isFalse,
      );
    });
  });

  test('production and non-production builds use separate ad units', () {
    const production = HomePilotAdUnits(production: true);
    const testUnits = HomePilotAdUnits(production: false);
    expect(production.rewarded, contains('5274007212820203'));
    expect(testUnits.rewarded, contains('3940256099942544'));
    expect(production.native('home'), isNot(production.native('more')));
  });

  test('remote configuration controls wallet capacity', () {
    final config = MonetizationConfig.fromJson({
      'ads_enabled': true,
      'native_ads_enabled': true,
      'interstitial_ads_enabled': true,
      'rewarded_ads_enabled': true,
      'rewarded_interstitial_enabled': true,
      'points_enabled': true,
      'emergency_free_creation_mode': false,
      'wallet_cap': 25,
      'interstitial_cooldown_seconds': 180,
      'rapid_completion_window_seconds': 60,
      'interstitial_session_cap': 3,
    });

    expect(config.walletCap, 25);
    expect(config.creationIsFree, isFalse);
  });

  test('ad preloader retry delay backs off and caps at one minute', () {
    expect(adRetryDelayForFailure(1), const Duration(seconds: 2));
    expect(adRetryDelayForFailure(2), const Duration(seconds: 4));
    expect(adRetryDelayForFailure(6), const Duration(seconds: 60));
    expect(adRetryDelayForFailure(99), const Duration(seconds: 60));
  });

  test('native ads unmount whenever a modal route obscures the page', () {
    expect(
      nativeAdPlacementEnabled(
        routeIsCurrent: false,
        configEnabled: true,
        consentGranted: true,
        adsInitialized: true,
        platformSupported: true,
        enabledOverride: true,
      ),
      isFalse,
    );
    expect(
      nativeAdPlacementEnabled(
        routeIsCurrent: true,
        presentationSuppressed: true,
        configEnabled: true,
        consentGranted: true,
        adsInitialized: true,
        platformSupported: true,
        enabledOverride: true,
      ),
      isFalse,
    );
    expect(
      nativeAdPlacementEnabled(
        routeIsCurrent: true,
        configEnabled: true,
        consentGranted: true,
        adsInitialized: true,
        platformSupported: true,
      ),
      isTrue,
    );
  });

  test('pending reward claim preserves recovery metadata', () {
    final claim = PendingRewardClaim.fromJson({
      'claim_id': 'claim-1',
      'reward_amount': 2,
      'expires_at': '2026-08-02T12:00:00Z',
    });

    expect(claim.claimId, 'claim-1');
    expect(claim.rewardAmount, 2);
    expect(claim.expiresAt, DateTime.utc(2026, 8, 2, 12));
  });

  test(
    'offline creation drafts persist, restore, and clear securely',
    () async {
      final secureStorage = _MockSecureStorage();
      String? encoded;
      when(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        encoded = invocation.namedArguments[#value] as String?;
      });
      when(
        () => secureStorage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => encoded);
      when(
        () => secureStorage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});
      final store = OfflineCreationDraftStore(secureStorage);

      await store.save('task_user_asset', {
        'operation_id': 'operation-1',
        'title': 'Inspect seals',
        'dependencies': ['a', 'b'],
      });

      expect(await store.load('task_user_asset'), {
        'operation_id': 'operation-1',
        'title': 'Inspect seals',
        'dependencies': ['a', 'b'],
      });
      await store.clear('task_user_asset');
      verify(
        () => secureStorage.delete(
          key: 'homepilot_creation_draft_v1_task_user_asset',
        ),
      ).called(1);
    },
  );

  testWidgets('native slot reserves 112dp then collapses after no-fill', (
    tester,
  ) async {
    Future<void> pumpSlot(bool collapsed) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HkNativeAdSlotFrame(
              collapsed: collapsed,
              child: const ColoredBox(color: Colors.green),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpSlot(false);
    expect(tester.getSize(find.byType(HkNativeAdSlotFrame)).height, 112);
    await pumpSlot(true);
    expect(tester.getSize(find.byType(HkNativeAdSlotFrame)).height, 0);
  });

  testWidgets('native loading state renders a labeled skeleton surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 112, child: HkNativeAdLoadingSkeleton()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('native-ad-loading-skeleton')), findsOne);
    expect(find.byType(HkNativeAdLoadingSkeleton), findsOne);
  });
}
