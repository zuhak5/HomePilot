from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8", newline="\n")


def replace_exact(path: str, old: str, new: str, *, expected: int = 1) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected} occurrences, found {count}: {old!r}")
    write(path, text.replace(old, new))


def replace_regex(path: str, pattern: str, replacement: str, *, expected: int = 1) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, flags=re.S | re.M)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected} regex replacements, found {count}: {pattern}")
    write(path, updated)


# File Picker 12 returns List<PlatformFile> and exposes the platform interface
# through its public library. Keep restore selection single-file and nullable at
# the app boundary without importing package internals.
replace_exact(
    "lib/main.dart",
    """    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = result?.files.single.path;
""",
    """    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = files.isEmpty ? null : files.single.path;
""",
)

path = "test/widget_test.dart"
text = read(path)
text = text.replace(
    "import 'package:file_picker/src/platform/file_picker_platform_interface.dart';\n",
    "",
    1,
)
old_fake = """class FakeFilePicker extends FilePickerPlatform {
  FakeFilePicker(this.path);

  final String? path;
  var pickCount = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    dynamic androidSafOptions,
  }) async {
    pickCount++;
    if (path == null) {
      return null;
    }
    return FilePickerResult([
      PlatformFile(name: 'selected.zip', path: path, size: 2048),
    ]);
  }
}
"""
new_fake = """base class FakePickedPlatformFile extends PlatformFile {
  FakePickedPlatformFile(this.selectedPath);

  final String selectedPath;

  @override
  String get name => 'selected.zip';

  @override
  Uri get uri => Uri(path: selectedPath);

  @override
  String? get path => selectedPath;

  @override
  Never get xFile => throw UnsupportedError('Fake picker does not expose XFile');

  @override
  Future<int> length() async => 2048;

  @override
  Future<Never> readAsBytes() async =>
      throw UnsupportedError('Fake picker bytes are not used');

  @override
  Stream<Never> readAsByteStream() => const Stream<Never>.empty();
}

class FakeFilePicker extends FilePickerPlatform {
  FakeFilePicker(this.path);

  final String? path;
  var pickCount = 0;

  @override
  Future<List<PlatformFile>> pickFiles({
    List<String>? allowedExtensions,
    AndroidOptions androidOptions = const AndroidOptions(),
    int compressionQuality = 0,
    String? dialogTitle,
    String? initialDirectory,
    LinuxOptions linuxOptions = const LinuxOptions(),
    void Function(FilePickerStatus)? onFileLoading,
    FileType type = FileType.any,
    WebOptions webOptions = const WebOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
  }) async {
    pickCount++;
    final selectedPath = path;
    if (selectedPath == null) {
      return const <PlatformFile>[];
    }
    return <PlatformFile>[FakePickedPlatformFile(selectedPath)];
  }
}
"""
if old_fake not in text:
    raise RuntimeError("widget_test.dart: File Picker 11 fake changed unexpectedly")
text = text.replace(old_fake, new_fake, 1)
text = text.replace("  schemaVersion: 12,", "  schemaVersion: 25,", 1)
write(path, text)

# Plugins upgraded by Pub require Android API 37 for compilation. Keep targetSdk
# at 36 so this dependency modernization does not silently change runtime target
# behavior or permission policy.
replace_exact("android/app/build.gradle.kts", "    compileSdk = 36\n", "    compileSdk = 37\n")

# File Picker 12 no longer needs the project-owned KGP compatibility workaround.
replace_regex(
    "android/build.gradle.kts",
    r"\n// file_picker 11\.0\.2 assumes AGP 9 built-in Kotlin, while other current\n"
    r"// plugins still require the temporary legacy-KGP compatibility mode\. Apply\n"
    r"// KGP only to file_picker until the remaining plugins support built-in Kotlin\.\n"
    r"subprojects \{\n"
    r"    if \(name == \"file_picker\"\) \{.*?\n"
    r"    \}\n"
    r"\}\n",
    "\n",
)

# Dart 3.13's unawaited_return_in_try_block lint is useful here: awaiting keeps
# plugin failures inside the existing fail-safe catch paths.
for path, replacements in {
    "lib/src/core/services/app_permission_coordinator.dart": [
        ("      return Geolocator.isLocationServiceEnabled();", "      return await Geolocator.isLocationServiceEnabled();"),
        ("          return openAppPermissionSettings();", "          return await openAppPermissionSettings();"),
        ("            return openLocationServiceSettings();", "            return await openLocationServiceSettings();"),
        ("          return openAppPermissionSettings();", "          return await openAppPermissionSettings();"),
        ("          return openAppPermissionSettings();", "          return await openAppPermissionSettings();"),
    ],
    "lib/src/core/services/notification_service.dart": [
        ("        return runCloudSyncInBackground(leaseScope: 'work-manager');", "        return await runCloudSyncInBackground(leaseScope: 'work-manager');"),
    ],
    "lib/src/core/services/weather_service.dart": [
        ("        return cachedWeather();", "        return await cachedWeather();"),
        ("        return cachedWeather();", "        return await cachedWeather();"),
    ],
    "lib/src/core/sync/supabase_sync_gateway.dart": [
        ("          return write(\n", "          return await write(\n"),
    ],
    "lib/src/features/auth/data/native_google_sign_in.dart": [
        ("      return _tokensFor(account);", "      return await _tokensFor(account);"),
        ("      return account == null ? null : _tokensFor(account);", "      return account == null ? null : await _tokensFor(account);"),
    ],
}.items():
    text = read(path)
    for old, new in replacements:
        if old not in text:
            raise RuntimeError(f"{path}: async lint target changed unexpectedly: {old!r}")
        text = text.replace(old, new, 1)
    write(path, text)

# Google Mobile Ads 9.1 deprecates the separate child/under-age integer tags in
# favor of a single age-treatment signal. The existing app did not request
# child or teen treatment, so preserve that by sending the new unspecified
# restricted-treatment value.
replace_exact(
    "lib/src/features/monetization/monetization.dart",
    """        maxAdContentRating: MaxAdContentRating.pg,
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
        tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.unspecified,
        testDeviceIds: testDeviceIds,
""",
    """        maxAdContentRating: MaxAdContentRating.pg,
        ageRestrictedTreatment: AgeRestrictedTreatment.unspecified,
        testDeviceIds: testDeviceIds,
""",
)

# Build Runner 2.16 no longer needs/accepts the historical conflict-deletion
# switch. Remove it everywhere from executable/docs sources.
for file in ROOT.rglob("*"):
    if not file.is_file() or ".git" in file.parts:
        continue
    if file.suffix.lower() not in {".md", ".yml", ".yaml", ".ps1", ".sh", ".txt"}:
        continue
    try:
        text = file.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    updated = text.replace(" --delete-conflicting-outputs", "")
    if updated != text:
        file.write_text(updated, encoding="utf-8", newline="\n")

# Prelaunch schema fixtures now prove rejection rather than migration.
path = "test/home_structure_repository_test.dart"
text = read(path)
pattern = r"  test\('migrates schema 1 rooms and infers thing types', \(\) async \{.*?^  \}\);"
replacement = """  test('rejects schema 1 prelaunch home databases', () async {
    final legacyDb = AppDatabase(
      executor: NativeDatabase.memory(setup: _createV1),
    );
    addTearDown(() async {
      try {
        await legacyDb.close();
      } catch (_) {
        // Opening is intentionally rejected before normal database startup.
      }
    });
    final legacyRepo = DriftAssetRepository(legacyDb);

    await expectLater(
      legacyRepo.listRooms(),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('predates the first-production'),
        ),
      ),
    );
  });"""
text, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
if count != 1:
    raise RuntimeError("home_structure_repository_test.dart: historical migration test not found")
write(path, text)

# Permission education v3 is device-local. The old SettingsRepository helper
# can remain temporarily source-compatible for unrelated fakes, but it must not
# be part of the remote user-setting protocol or produce a synchronization
# contract expectation.
path = "test/sync_store_test.dart"
text = read(path)
pattern = r"  test\('permission education setting defaults, watches, and syncs', \(\) async \{.*?^  \}\);"
replacement = """  test('permission education state is excluded from user-setting sync', () {
    final spec = syncSpecByEntity['user_setting']!;
    for (final key in const <String>[
      'permission_education_seen',
      'permission_education_seen_v2',
      'permission_education_device_state_v3',
    ]) {
      expect(allowedRemoteSettingKeys.contains(key), isFalse);
      expect(spec.localWhere, isNot(contains(key)));
    }
  });"""
text, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
if count != 1:
    raise RuntimeError("sync_store_test.dart: historical permission sync test not found")
write(path, text)

print("Upgraded API and validation adaptations staged successfully.")
