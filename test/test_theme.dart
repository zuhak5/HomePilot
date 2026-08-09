import 'package:flutter/material.dart';
import 'package:homepilot/src/ui/app_theme.dart';

ThemeData testLightTheme() => _withoutInkSparkle(HomePilotTheme.light());

ThemeData testDarkTheme() => _withoutInkSparkle(HomePilotTheme.dark());

ThemeData testTheme(ThemeData theme) => _withoutInkSparkle(theme);

ThemeData _withoutInkSparkle(ThemeData theme) {
  return theme.copyWith(splashFactory: NoSplash.splashFactory);
}
