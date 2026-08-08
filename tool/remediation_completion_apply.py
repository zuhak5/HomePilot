#!/usr/bin/env python3
from __future__ import annotations

import json
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


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def replace_all(path: str, old: str, new: str, *, minimum: int = 1) -> None:
    text = read(path)
    count = text.count(old)
    if count < minimum:
        raise RuntimeError(f"{path}: expected at least {minimum} matches, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new))


def regex_once(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{path}: regex expected one match, found {count}: {pattern[:100]!r}")
    write(path, updated)


def splash() -> None:
    path = "lib/homepilot_animated_splash_screen.dart"
    text = read(path)
    marker = "import 'package:flutter/services.dart';\n\n"
    if "const homePilotSplashBackground" not in text:
        host = r'''const homePilotSplashBackground = Color(0xFFF9FCF8);

/// Stable process-level owner for the branded Flutter splash.
///
/// This host is intentionally independent from the app's startup theme,
/// authentication, providers, Supabase initialization, and router. It supplies
/// only the inherited context needed by the presentation layer so deferred work
/// can run underneath the splash from the first usable Flutter frame.
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
        if marker not in text:
            raise RuntimeError("splash import marker not found")
        text = text.replace(marker, marker + host, 1)
    text = text.replace(
        "  static const Color _background = Color(0xFFF9FCF8);",
        "  static const Color _background = homePilotSplashBackground;",
    )
    write(path, text)

    main = "lib/main.dart"
    text = read(main)
    text = text.replace(
        "const minimumNativeSplashDuration = Duration(milliseconds: 3200);\n",
        "",
        1,
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
        1,
    )
    text = text.replace("  final Duration minimumSplashDuration;\n", "", 1)
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
    if old_owner not in text:
        raise RuntimeError("HomePilotApp splash owner shape changed")
    text = text.replace(old_owner, new_owner, 1)
    write(main, text)

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

  testWidgets('process splash leaves after fixed lifetime without replacing child', (
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

    # The old title asserted a blank *application startup*. The internal theme
    # gate may still be unit-tested, but it is now always covered by the process
    # splash in production. Remove the stale defect wording so future reviews do
    # not mistake the isolated gate for the real launch topology.
    for test_file in (ROOT / "test").rglob("*.dart"):
        data = test_file.read_text(encoding="utf-8")
        data = data.replace(
            "startup bootstrap stays blank until theme load completes",
            "startup theme gate stays inert while theme load completes",
        )
        test_file.write_text(data, encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: remediation_completion_apply.py <splash>")
    mode = sys.argv[1]
    if mode == "splash":
        splash()
    else:
        raise SystemExit(f"unknown mode: {mode}")


if __name__ == "__main__":
    main()
