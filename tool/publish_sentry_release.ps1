param(
    [Parameter(Mandatory = $true)]
    [string]$Release,

    [Parameter(Mandatory = $true)]
    [string]$Dist,

    [string]$Environment = 'prod'
)

$ErrorActionPreference = 'Stop'

$requiredEnvironment = @(
    'SENTRY_AUTH_TOKEN',
    'SENTRY_ORG',
    'SENTRY_PROJECT'
)
foreach ($name in $requiredEnvironment) {
    $value = [System.Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required Sentry environment value: $name"
    }
}
if ($env:SENTRY_ORG -ne 'homepilot-qt') {
    throw 'SENTRY_ORG must be homepilot-qt.'
}
if ($env:SENTRY_PROJECT -ne 'homepilot') {
    throw 'SENTRY_PROJECT must be homepilot.'
}
if ([string]::IsNullOrWhiteSpace($Release) -or
    $Release -notmatch '^com\.homepilot\.app@\d+\.\d+\.\d+\+\d+$') {
    throw "Unexpected Sentry release identifier: $Release"
}
if ([string]::IsNullOrWhiteSpace($Dist) -or $Dist -notmatch '^\d+$') {
    throw "Unexpected Sentry dist: $Dist"
}

$env:SENTRY_RELEASE = $Release
$env:SENTRY_DIST = $Dist

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation
    )

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            & $Operation
            return
        }
        catch {
            if ($attempt -eq 2) {
                throw
            }
            Write-Warning "$Label failed on attempt $attempt. Retrying once."
            Start-Sleep -Seconds 5
        }
    }
}

$sentryCli = @('--yes', '@sentry/cli@2.58.6')

# A previous failed workflow attempt may already have created the release.
& npx @sentryCli releases info $Release *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-WithRetry -Label 'Sentry release creation' -Operation {
        Invoke-NativeCommand -FilePath 'npx' -Arguments (
            $sentryCli + @('releases', 'new', $Release)
        )
    }
}

Invoke-WithRetry -Label 'Sentry commit association' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @(
            'releases',
            'set-commits',
            $Release,
            '--auto',
            '--ignore-missing'
        )
    )
}

Invoke-WithRetry -Label 'Sentry debug symbol upload' -Operation {
    Invoke-NativeCommand -FilePath 'dart' -Arguments @(
        'run',
        'sentry_dart_plugin'
    )
}

Invoke-WithRetry -Label 'Sentry release finalization' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @('releases', 'finalize', $Release)
    )
}

$deployName = if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) {
    "manual-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
}
else {
    "github-actions-$env:GITHUB_RUN_ID"
}
Invoke-WithRetry -Label 'Sentry deploy marker' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @(
            'releases',
            'deploys',
            $Release,
            'new',
            '-e',
            $Environment,
            '-n',
            $deployName
        )
    )
}

Invoke-NativeCommand -FilePath 'npx' -Arguments (
    $sentryCli + @('releases', 'info', $Release)
)
Write-Host "Verified Sentry release $Release with dist $Dist in $Environment."
