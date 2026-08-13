param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string] $Version
)

$ErrorActionPreference = "Stop"

if (-not $env:RUNNER_TEMP) {
  throw "RUNNER_TEMP is required."
}
if (-not $env:GITHUB_PATH) {
  throw "GITHUB_PATH is required."
}

$InstallRoot = Join-Path $env:RUNNER_TEMP "homepilot-flutter-$Version"
if (Test-Path -LiteralPath $InstallRoot) {
  Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}

git clone `
  --depth 1 `
  --branch $Version `
  https://github.com/flutter/flutter.git `
  $InstallRoot

$FlutterBin = Join-Path $InstallRoot "bin"
$Flutter = Join-Path $FlutterBin "flutter.bat"

Add-Content -LiteralPath $env:GITHUB_PATH -Value $FlutterBin

& $Flutter --version
& $Flutter config --no-analytics
