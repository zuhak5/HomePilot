# HomePilot Dependency and Toolchain Audit

Audit date: 2026-07-26

## Resolved toolchain

- Flutter 3.44.7 stable
- Dart 3.12.2
- Android Gradle Plugin 9.3.0
- Gradle 9.6.1
- Kotlin Gradle Plugin 2.4.10
- Java 21.0.9 as selected by Flutter from Android Studio's bundled JBR
- Java and Kotlin bytecode target 17
- Android compile/target SDK 36
- Application version 1.3.0+15
- Deno 2.9.3
- `@supabase/supabase-js` 2.110.8 in both Deno configurations

`flutter doctor -v` reports no issues, all Android licenses accepted, Android
SDK 36.1.0, build-tools 36.1.0, and emulator 36.4.9.

## Resolution and supply-chain checks

The lockfile contains 236 packages including the application: 227 hosted
packages, eight Flutter SDK packages, and the root package. There are no Git
dependencies, dependency overrides, or prerelease package versions.

Commands:

```text
flutter pub get
flutter pub outdated --json
flutter pub upgrade --major-versions --dry-run
dart pub deps --json
npm audit
npm audit signatures
deno task check
```

Results:

- `npm audit`: zero vulnerabilities.
- npm registry verification: eight signatures and eight attestations.
- All 229 non-SDK/root resolved packages contain a package license. The six
  Flutter component packages without a package-local license are covered by the
  Flutter SDK root license.
- `file_picker` is pinned to the required stable 11.0.2 and
  `flutter_foreground_task` resolves to 10.0.0.

## Retained compatibility exceptions

`share_plus` 13.3.0 and `package_info_plus` 10.2.1 cannot be selected while
retaining stable `file_picker` 11.0.2. Pub's full major-version dry run resolves
those versions only by replacing it with prerelease `file_picker`
12.0.0-beta.7. The release therefore retains `share_plus` 12.0.2 and
`package_info_plus` 9.0.1.

`geolocator` 14.0.3 requires `geolocator_linux` 0.2.6, which in turn requires
`package_info_plus` 10. That graph is incompatible with `file_picker` 11.0.2
because the former requires `win32` 6 while the latter requires `win32` 5.
`geolocator` therefore remains at the newest stable version compatible with the
required stable file-picker graph, 14.0.2.

Flutter pins `intl` 0.20.2. The current analyzer/build graph retains
`build_runner` 2.15.1 and `drift_dev` 2.34.0 because their newer patch releases
are not simultaneously resolvable in this graph.

AGP 9 built-in Kotlin was attempted in two clean configurations:

1. With the new DSL enabled, Flutter's Gradle plugin failed by casting AGP 9's
   `ApplicationExtensionImpl` to the removed legacy `AbstractAppExtension`.
2. With the new DSL compatibility switch disabled, `app_links` 7.2.1 failed
   because it still applies `org.jetbrains.kotlin.android`, which AGP 9
   built-in Kotlin rejects.

The documented Flutter compatibility switches remain disabled for built-in
Kotlin/new DSL. Stable plugins are not vendored. `file_picker` 11.0.2 expects
AGP 9 built-in Kotlin and otherwise omits the Kotlin plugin, so the root Android
build applies Kotlin 2.4.10 only to that subproject and keeps its JVM target at
17. Release warnings identify remaining legacy KGP use in `file_picker`,
`flutter_foreground_task`, `package_info_plus`, `share_plus`, and
`workmanager_android`; these should be removed once all stable upstream plugins
support AGP 9 built-in Kotlin.
