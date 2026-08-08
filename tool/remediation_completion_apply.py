#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def splash() -> None:
    splash_path = "lib/homepilot_animated_splash_screen.dart"
    splash_text = read(splash_path)
    marker = "import 'package:flutter/services.dart';\n\n"
    if "class HomePilotProcessSplashHost" not in splash_text:
        host = r'''const homePilotSplashBackground = Color(0xFFF9FCF8);

/// Stable process-level owner for the branded Flutter splash.
///
/// This host is deliberately independent from startup theme, authentication,
/// Supabase, database hydration and routing. Deferred work renders underneath
/// one process-scoped presentation lifetime from the first usable Flutter frame.
class HomePilotProcessSplashHost extends StatelessWidget {
  const HomePilotProcessSplashHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final media = views.isEmpty
        ? const MediaQueryData()
        : MediaQueryData.fromView(views.first);
    final splashTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: homePilotSplashBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF159A3B),
        brightness: Brightness.light,
      ),
    );
    return MediaQuery(
      data: media,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: splashTheme,
          child: HomePilotSplashOverlay(child: child),
        ),
      ),
    );
  }
}

'''
        if marker not in splash_text:
            raise RuntimeError("splash import marker not found")
        splash_text = splash_text.replace(marker, marker + host, 1)
    elif "const homePilotSplashBackground" not in splash_text:
        raise RuntimeError("process splash host exists without canonical background")
    splash_text = splash_text.replace(
        "  static const Color _background = Color(0xFFF9FCF8);",
        "  static const Color _background = homePilotSplashBackground;",
    )
    write(splash_path, splash_text)

    main_path = "lib/main.dart"
    text = read(main_path)
    text = text.replace(
        "const minimumNativeSplashDuration = Duration(milliseconds: 3200);\n",
        "",
    )
    text = re.sub(
        r"\n@visibleForTesting\nDuration remainingNativeSplashDuration\(Duration _\) \{\n  return Duration\.zero;\n\}\n",
        "\n",
        text,
        count=1,
    )
    text = text.replace(
        "    this.minimumSplashDuration = minimumNativeSplashDuration,\n",
        "",
    )
    text = text.replace("  final Duration minimumSplashDuration;\n", "")
    text = text.replace(
        "        color: HkColors.appBackground,\n",
        "        color: homePilotSplashBackground,\n",
        1,
    )
    text = text.replace(
        "      return const ColoredBox(color: HkColors.appBackground);",
        "      return const ColoredBox(color: homePilotSplashBackground);",
        1,
    )

    old_run = '''    runApp(
      _DeferredHomePilotBootstrap(
        database: database,
        config: config,
        elapsedBeforeFirstFrame: startupClock.elapsed,
      ),
    );'''
    new_run = '''    runApp(
      HomePilotProcessSplashHost(
        child: _DeferredHomePilotBootstrap(
          database: database,
          config: config,
          elapsedBeforeFirstFrame: startupClock.elapsed,
        ),
      ),
    );'''
    if "HomePilotProcessSplashHost(" not in text:
        if old_run not in text:
            raise RuntimeError("runHomePilot root shape changed")
        text = text.replace(old_run, new_run, 1)

    old_owner = '''        // Splash is process-scoped presentation. Do not duplicate inside auth/startup/router branches.
        return HomePilotSplashOverlay(
          child: ValueListenableBuilder<StartupBootstrapState>('''
    new_owner = '''        // Splash lifetime is owned by HomePilotProcessSplashHost above deferred
        // bootstrap/theme/auth work. Keep this MaterialApp stable underneath it.
        return Builder(
          builder: (_) => ValueListenableBuilder<StartupBootstrapState>('''
    if old_owner in text:
        text = text.replace(old_owner, new_owner, 1)
    elif "Splash lifetime is owned by HomePilotProcessSplashHost" not in text:
        raise RuntimeError("HomePilotApp splash owner shape changed")
    write(main_path, text)

    write(
        "test/process_splash_host_test.dart",
        r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/homepilot_animated_splash_screen.dart';

void main() {
  testWidgets('process splash owns the first usable Flutter presentation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const HomePilotProcessSplashHost(
        child: ColoredBox(
          key: ValueKey('deferred-bootstrap-placeholder'),
          color: Colors.pink,
        ),
      ),
    );
    expect(find.byType(HomePilotAnimatedSplashScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('deferred-bootstrap-placeholder')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('process splash leaves without replacing underlying child', (
    tester,
  ) async {
    const childKey = ValueKey('stable-underlying-child');
    await tester.pumpWidget(
      const HomePilotProcessSplashHost(
        child: ColoredBox(key: childKey, color: homePilotSplashBackground),
      ),
    );
    final before = tester.element(find.byKey(childKey));
    await tester.pump(const Duration(milliseconds: 3500));
    final after = tester.element(find.byKey(childKey));
    expect(find.byType(HomePilotAnimatedSplashScreen), findsNothing);
    expect(identical(before, after), isTrue);
  });
}
''',
    )

    resources_path = "test/startup_resources_test.dart"
    resources = read(resources_path)
    resources = re.sub(
        r"\n  test\('in-app startup uses no artificial fixed splash wait', \(\) \{.*?\n  \}\);\n",
        "\n",
        resources,
        count=1,
        flags=re.S,
    )
    if "minimumNativeSplashDuration" not in resources and "remainingNativeSplashDuration" not in resources:
        resources = resources.replace("import 'package:homepilot/main.dart';\n", "")
    write(resources_path, resources)

    widget_path = "test/widget_test.dart"
    widget = read(widget_path)
    widget = widget.replace(
        "elapsedBeforeFirstFrame: minimumNativeSplashDuration,",
        "elapsedBeforeFirstFrame: Duration.zero,",
    )
    widget = widget.replace(
        "startup bootstrap stays blank until theme load completes",
        "startup theme gate stays inert while theme load completes",
    )
    write(widget_path, widget)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: remediation_completion_apply.py <phase>")
    mode = sys.argv[1]
    if mode == "splash":
        splash()
    elif mode == "permissions":
        from remediation_permissions_apply import apply
        apply()
    elif mode == "feedback":
        from remediation_feedback_apply import apply
        apply()
    elif mode == "monetization":
        from remediation_monetization_apply import apply
        apply()
    else:
        raise SystemExit(f"unknown mode: {mode}")


if __name__ == "__main__":
    main()
