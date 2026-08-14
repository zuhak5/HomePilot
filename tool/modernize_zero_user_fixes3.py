from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "tool/validate_google_release_contracts.mjs"
text = path.read_text(encoding="utf-8")
old = "assertContract(/compileSdk\\s*=\\s*36/.test(appGradle), 'compileSdk must remain API 36.');"
new = "assertContract(/compileSdk\\s*=\\s*37/.test(appGradle), 'compileSdk must remain API 37.');"
if text.count(old) != 1:
    raise RuntimeError("compileSdk release contract changed unexpectedly")
path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")

print("Release contract now preserves targetSdk 36 while requiring compileSdk 37.")
