from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8", newline="\n")


def replace_exact(path: str, old: str, new: str, expected: int = 1) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected}, found {count}: {old!r}")
    write(path, text.replace(old, new))


# File Picker 12 split single- and multi-selection. Restore must remain a
# single archive choice, so use the new single-file API rather than relying on
# the changed pickFiles behavior.
replace_exact(
    "lib/main.dart",
    """    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = files.isEmpty ? null : files.single.path;
""",
    """    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = file?.path;
""",
)

path = "test/widget_test.dart"
text = read(path)
old = """  @override
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
"""
new = """  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickCount++;
    final selectedPath = path;
    return selectedPath == null ? null : FakePickedPlatformFile(selectedPath);
  }
"""
if old not in text:
    raise RuntimeError("widget_test.dart: first File Picker 12 adaptation not found")
write(path, text.replace(old, new, 1))

# Make every cached-weather fallback inside the async refresh await the future.
# This keeps Dart 3.13's try-block lint satisfied and ensures exceptions remain
# in the intended fallback boundary.
path = "lib/src/core/services/weather_service.dart"
text = read(path)
text = text.replace("return cachedWeather();", "return await cachedWeather();")
write(path, text)

# Align the declared Dart floor with Flutter 3.47.0's Dart 3.13 toolchain so the
# package metadata no longer advertises an unvalidated pre-modernization SDK.
replace_exact("pubspec.yaml", "  sdk: ^3.12.2\n", "  sdk: ^3.13.0\n")

path = "CHANGELOG.md"
text = read(path)
text = text.replace(
    "Raised the supported Flutter toolchain to 3.47.0 and Deno to 2.9.5",
    "Raised the supported Flutter toolchain to 3.47.0 / Dart 3.13 and Deno to 2.9.5",
    1,
)
write(path, text)

print("Single-file restore and Dart 3.13 floor adaptations staged successfully.")
