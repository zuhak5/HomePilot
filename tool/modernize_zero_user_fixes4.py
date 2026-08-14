from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "test/widget_test.dart"
text = path.read_text(encoding="utf-8")
old = "    void Function(FilePickerStatus)? onFileLoading,"
new = "    Function(FilePickerStatus)? onFileLoading,"
if text.count(old) != 1:
    raise RuntimeError(f"expected one File Picker callback signature, found {text.count(old)}")
path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")
print("File Picker 12 fake callback signature aligned.")
