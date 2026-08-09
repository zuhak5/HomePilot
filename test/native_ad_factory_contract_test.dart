import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _paletteKeys = <String>[
  'backgroundColor',
  'borderColor',
  'headlineColor',
  'bodyColor',
  'advertiserColor',
  'sponsoredColor',
  'adBadgeBackgroundColor',
  'adBadgeTextColor',
  'callToActionBackgroundColor',
  'callToActionTextColor',
];

void main() {
  test('Flutter and Android share the complete schema-v2 palette contract', () {
    final flutter = File(
      'lib/src/features/monetization/monetization.dart',
    ).readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/com/homepilot/app/'
      'HomePilotNativeAdFactory.kt',
    ).readAsStringSync();

    expect(flutter, contains("'schemaVersion': 2"));
    expect(kotlin, contains('private const val SCHEMA_VERSION = 2'));
    for (final key in _paletteKeys) {
      expect(flutter, contains("'$key'"), reason: 'Flutter must emit $key.');
      expect(kotlin, contains('"$key"'), reason: 'Android must consume $key.');
    }
    expect(kotlin, isNot(contains('customOptions?.get("textColor")')));
  });

  test('factory validates and applies one complete palette before binding', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/homepilot/app/'
      'HomePilotNativeAdFactory.kt',
    ).readAsStringSync();

    final validation = kotlin.indexOf(
      'NativeAdPalette.fromOptions(customOptions)',
    );
    final fallback = kotlin.indexOf(
      'NativeAdPalette.fromResources(context)',
      validation,
    );
    final application = kotlin.indexOf('applyPalette(', fallback);
    final binding = kotlin.indexOf('view.setNativeAd(nativeAd)', application);

    expect(validation, greaterThanOrEqualTo(0));
    expect(fallback, greaterThan(validation));
    expect(application, greaterThan(fallback));
    expect(binding, greaterThan(application));
    expect(kotlin, contains(r'Regex("^#[0-9A-Fa-f]{6}$"'));
    expect(kotlin, contains('Color.parseColor(encoded)'));
    expect(kotlin, contains('catch (_: IllegalArgumentException)'));
    expect(kotlin, contains('GradientDrawable'));
    expect(kotlin, contains('setStroke('));
    expect(kotlin, contains('cornerRadius = dp(cornerRadiusDp)'));
    expect(kotlin, isNot(contains('view.setBackgroundColor(')));
    expect(kotlin, isNot(contains('android.util.Log')));
    expect(kotlin, isNot(contains('println(')));
  });

  test(
    'factory preserves registered creative assets and hides absent data',
    () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/homepilot/app/'
        'HomePilotNativeAdFactory.kt',
      ).readAsStringSync();
      final layout = File(
        'android/app/src/main/res/layout/homepilot_native_ad.xml',
      ).readAsStringSync();

      for (final registration in const [
        'view.iconView = icon',
        'view.headlineView = headline',
        'view.bodyView = body',
        'view.advertiserView = advertiser',
        'view.callToActionView = callToAction',
        'view.adChoicesView = adChoices',
      ]) {
        expect(kotlin, contains(registration));
      }
      expect(kotlin, contains('body.bindOptional(nativeAd.body)'));
      expect(kotlin, contains('advertiser.bindOptional(nativeAd.advertiser)'));
      expect(
        kotlin,
        contains('callToAction.bindOptional(nativeAd.callToAction)'),
      );
      expect(kotlin, contains('icon.setImageDrawable(null)'));
      expect(kotlin, contains('View.GONE'));
      expect(layout, contains('@+id/homepilot_ad_badge'));
      expect(layout, contains('@+id/homepilot_ad_sponsored'));
      expect(layout, contains('@+id/homepilot_ad_choices'));
      expect(layout, contains('android:paddingStart="12dp"'));
      expect(layout, contains('android:paddingEnd="12dp"'));
    },
  );

  test('system fallback resources provide complete light and dark chrome', () {
    final light = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    final dark = File(
      'android/app/src/main/res/values-night/colors.xml',
    ).readAsStringSync();
    final background = File(
      'android/app/src/main/res/drawable/homepilot_native_ad_background.xml',
    ).readAsStringSync();
    final badge = File(
      'android/app/src/main/res/drawable/homepilot_native_ad_badge.xml',
    ).readAsStringSync();
    final cta = File(
      'android/app/src/main/res/drawable/homepilot_native_ad_cta.xml',
    ).readAsStringSync();

    for (final resource in const [
      'homepilot_ad_surface',
      'homepilot_ad_border',
      'homepilot_ad_text_primary',
      'homepilot_ad_text_secondary',
      'homepilot_ad_badge_background',
      'homepilot_ad_badge_text',
      'homepilot_ad_cta_background',
      'homepilot_ad_cta_text',
    ]) {
      expect(light, contains('name="$resource"'));
      expect(dark, contains('name="$resource"'));
    }
    expect(background, contains('@color/homepilot_ad_surface'));
    expect(background, contains('@color/homepilot_ad_border'));
    expect(background, contains('<stroke'));
    expect(background, contains('<corners'));
    expect(badge, contains('@color/homepilot_ad_badge_background'));
    expect(badge, contains('@color/homepilot_ad_badge_text'));
    expect(cta, contains('@color/homepilot_ad_cta_background'));
  });

  test('native ads are constructed only through the shared component', () {
    final constructorOwners = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (RegExp(r'\bNativeAd\s*\(').hasMatch(entity.readAsStringSync())) {
        constructorOwners.add(entity.path.replaceAll('\\', '/'));
      }
    }

    expect(constructorOwners, [
      'lib/src/features/monetization/monetization.dart',
    ]);
  });

  test('every routed content screen declares a native ad placement', () {
    final main = File('lib/main.dart').readAsStringSync();
    for (final placement in const [
      'home',
      'assets',
      'room_detail',
      'thing_detail',
      'task_detail',
      'maintenance',
      'calendar',
      'more',
      'search',
      'trash',
      'statistics',
      'account',
      'backup',
      'notifications',
      'settings',
      'permission_setup',
    ]) {
      expect(
        main,
        contains("placement: '$placement'"),
        reason: 'Missing native ad placement for $placement.',
      );
    }
  });

  test('mounted native ads enforce the shared cache expiry deadline', () {
    final flutter = File(
      'lib/src/features/monetization/monetization.dart',
    ).readAsStringSync();

    expect(flutter, contains('Timer? _expiryTimer;'));
    expect(flutter, contains('_expiryTimer = Timer(kAdCacheMaxAge'));
    expect(flutter, contains('!identical(_displayLease, lease)'));
    expect(flutter, contains('_displayLease = null;'));
    expect(flutter, contains('lease.release();'));
    expect(flutter, contains('if (shouldReload) _scheduleSynchronize();'));
    expect(
      RegExp(r'_expiryTimer\?\.cancel\(\);').allMatches(flutter).length,
      greaterThanOrEqualTo(3),
      reason: 'Expiry must be cancelled on dispose, replacement, and teardown.',
    );
  });

  test('permission education tears down native ads before overlays', () {
    final dashboard = File('lib/main.dart').readAsStringSync();

    expect(
      dashboard,
      contains('next.isVisible && next.activeCapability != null'),
    );
    expect(dashboard, contains('deferProviderUpdate: true'));
    expect(
      dashboard,
      contains('onChooseLocationManually: () => runWithNativeAdsSuspended('),
    );
  });
}
