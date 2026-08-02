param(
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $workspace 'config\prod.json'

if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Missing config\prod.json. Copy config\prod.example.json and configure the production Supabase project.'
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.APP_ENV -ne 'prod') {
    throw 'config\prod.json must set APP_ENV=prod.'
}
if ([string]::IsNullOrWhiteSpace($config.SUPABASE_URL) -or
    [string]::IsNullOrWhiteSpace($config.SUPABASE_PUBLISHABLE_KEY) -or
    [string]::IsNullOrWhiteSpace($config.GOOGLE_WEB_CLIENT_ID)) {
    throw 'config\prod.json must contain Supabase settings and GOOGLE_WEB_CLIENT_ID.'
}
$productionDefines = @(
    "--dart-define-from-file=$configPath"
)

function Invoke-Flutter {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        & flutter @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "flutter $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Invoke-Dart {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        & dart @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "dart $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Assert-NoIntegrationTestRegistrant {
    $workspacePrefix = [System.IO.Path]::GetFullPath($workspace) +
        [System.IO.Path]::DirectorySeparatorChar
    $searchRoots = @(
        (Join-Path $workspace 'android'),
        (Join-Path $workspace 'build')
    )
    $registrants = foreach ($searchRoot in $searchRoots) {
        if (Test-Path -LiteralPath $searchRoot) {
            Get-ChildItem `
                -LiteralPath $searchRoot `
                -Recurse `
                -File `
                -Filter 'GeneratedPluginRegistrant.*'
        }
    }

    foreach ($registrant in $registrants) {
        $registrantPath = [System.IO.Path]::GetFullPath($registrant.FullName)
        $relativePath = if ($registrantPath.StartsWith(
                $workspacePrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            $registrantPath.Substring($workspacePrefix.Length)
        }
        else {
            $registrantPath
        }
        if ($relativePath -match '(?i)(^|[\\/])(debug|profile)([\\/]|$)') {
            continue
        }

        if (Select-String `
                -LiteralPath $registrant.FullName `
                -SimpleMatch `
                -Quiet `
                -Pattern 'IntegrationTestPlugin') {
            throw "Release plugin registrant contains integration_test: $($registrant.FullName)"
        }
    }
}

function Remove-GeneratedAndroidRegistrants {
    $workspacePrefix = [System.IO.Path]::GetFullPath($workspace) +
        [System.IO.Path]::DirectorySeparatorChar
    $registrantPaths = @(
        'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
    )

    foreach ($relativeRegistrantPath in $registrantPaths) {
        $registrantPath = [System.IO.Path]::GetFullPath(
            (Join-Path $workspace $relativeRegistrantPath)
        )
        if (-not $registrantPath.StartsWith(
                $workspacePrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to remove a generated registrant outside the workspace: $registrantPath"
        }

        if (Test-Path -LiteralPath $registrantPath) {
            Remove-Item -LiteralPath $registrantPath -Force
        }
    }
}

function Initialize-BuildWorkspace {
    Invoke-Flutter -Arguments @('clean')
    Invoke-Flutter -Arguments @('pub', 'get')
    Invoke-Flutter -Arguments @('gen-l10n')
    Invoke-Dart -Arguments @('run', 'build_runner', 'build')
}

Push-Location $workspace
try {
    Initialize-BuildWorkspace
    Invoke-Flutter -Arguments @('analyze', '--no-pub')
    if (-not $SkipTests) {
        Invoke-Flutter -Arguments @(
            'test',
            '--no-pub',
            '--concurrency=1',
            '--timeout',
            '2m',
            '--exclude-tags',
            'production-config'
        )
        Invoke-Flutter -Arguments (@(
            'test',
            '--no-pub',
            'test/prod_build_config_test.dart'
        ) + $productionDefines + @('--dart-define=VERIFY_PRODUCTION_CONFIG=true'))
    }

    # Flutter commands generate a main-source Android plugin registrant that
    # includes the dev-only integration_test plugin. Release compilation does
    # not reliably overwrite that stale file. Remove only that ignored
    # generated source so the release command recreates it in release mode.
    Remove-GeneratedAndroidRegistrants
    Assert-NoIntegrationTestRegistrant
    Invoke-Flutter -Arguments (@('build', 'apk', '--flavor', 'prod', '--release') + $productionDefines)
    Assert-NoIntegrationTestRegistrant
    Copy-Item `
        (Join-Path $workspace 'build\app\outputs\flutter-apk\app-prod-release.apk') `
        (Join-Path $workspace 'build\app\outputs\flutter-apk\app-release.apk') `
        -Force
}
finally {
    Pop-Location
}
