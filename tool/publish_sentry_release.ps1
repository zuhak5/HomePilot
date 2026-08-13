param(
    [Parameter(Mandatory = $true)]
    [string]$Release,

    [Parameter(Mandatory = $true)]
    [string]$Dist,

    [string]$Environment = 'prod',

    [ValidateSet('publish', 'deploy')]
    [string]$Mode = 'publish',

    [string]$DeployName,

    [string]$DeployUrl
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

    # Normalize accidental surrounding whitespace from copied secrets and variables.
    [System.Environment]::SetEnvironmentVariable($name, $value.Trim())
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
$sentryBaseUrl = if ([string]::IsNullOrWhiteSpace($env:SENTRY_BASE_URL)) {
    'https://sentry.io'
}
else {
    $env:SENTRY_BASE_URL.TrimEnd('/')
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = (& $FilePath @Arguments 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    if (-not [string]::IsNullOrWhiteSpace($output)) {
        Write-Host $output.TrimEnd()
    }

    if ($exitCode -ne 0) {
        if ($output -match '(?i)(Invalid token|http status:\s*401|Unauthorized)') {
            throw [System.UnauthorizedAccessException]::new(
                'Sentry authentication failed. Replace the GitHub production environment secret SENTRY_AUTH_TOKEN with a valid token for organization homepilot-qt and project homepilot. The token must support sentry-cli release management and include org:read plus project:releases (or org:ci).'
            )
        }

        throw "$FilePath $($Arguments -join ' ') failed with exit code $exitCode."
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
        catch [System.UnauthorizedAccessException] {
            # Authentication failures are permanent until the protected secret is rotated.
            throw
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

# Match the sentry-cli version embedded by sentry_dart_plugin 3.4.0 so release
# management and debug-file upload use the same protocol implementation.
$sentryCli = @('--yes', '@sentry/cli@2.58.6')

# Authenticate before mutating release state so invalid credentials fail clearly.
Invoke-NativeCommand -FilePath 'npx' -Arguments ($sentryCli + @('info'))

function Invoke-SentryApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Get', 'Post')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [object]$Body = $null
    )

    $uri = "$sentryBaseUrl$Path"
    $headers = @{
        Authorization = "Bearer $env:SENTRY_AUTH_TOKEN"
    }
    if ($Method -eq 'Get') {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    }

    $jsonBody = if ($null -eq $Body) { '{}' } else { $Body | ConvertTo-Json -Depth 8 }
    return Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $jsonBody
}

function Get-DeterministicDeployName {
    if (-not [string]::IsNullOrWhiteSpace($DeployName)) {
        return $DeployName
    }
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) {
        throw 'Deploy mode requires DeployName when GITHUB_RUN_ID is unavailable.'
    }
    $attemptId = if ([string]::IsNullOrWhiteSpace($env:RELEASE_ATTEMPT_ID)) {
        'no-attempt'
    }
    else {
        $env:RELEASE_ATTEMPT_ID
    }
    return "github-actions-$env:GITHUB_RUN_ID-$attemptId"
}

if ($Mode -eq 'deploy') {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @('releases', 'info', $Release)
    )
    $encodedRelease = [System.Uri]::EscapeDataString($Release)
    $deployPath = "/api/0/organizations/$env:SENTRY_ORG/releases/$encodedRelease/deploys/"
    $resolvedDeployName = Get-DeterministicDeployName
    $existingDeploys = @(Invoke-SentryApi -Method Get -Path $deployPath)
    $matchingDeploys = @($existingDeploys | Where-Object {
        $_.name -eq $resolvedDeployName -and $_.environment -eq $Environment
    })
    if ($matchingDeploys.Count -gt 1) {
        throw "Multiple Sentry deploy markers already exist for $Release $Environment $resolvedDeployName."
    }
    if ($matchingDeploys.Count -eq 0) {
        $body = @{
            environment = $Environment
            name = $resolvedDeployName
            projects = @($env:SENTRY_PROJECT)
        }
        if (-not [string]::IsNullOrWhiteSpace($DeployUrl)) {
            $body.url = $DeployUrl
        }
        Invoke-WithRetry -Label 'Sentry deploy marker' -Operation {
            Invoke-SentryApi -Method Post -Path $deployPath -Body $body | Out-Null
        }
    }
    $verifiedDeploys = @(Invoke-SentryApi -Method Get -Path $deployPath | Where-Object {
        $_.name -eq $resolvedDeployName -and $_.environment -eq $Environment
    })
    if ($verifiedDeploys.Count -ne 1) {
        throw "Expected exactly one Sentry deploy marker for $Release $Environment $resolvedDeployName, found $($verifiedDeploys.Count)."
    }
    Write-Host "Verified Sentry deploy marker $resolvedDeployName for $Release in $Environment."
    exit 0
}

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

Invoke-NativeCommand -FilePath 'npx' -Arguments (
    $sentryCli + @('releases', 'info', $Release)
)
Write-Host "Verified Sentry release $Release with dist $Dist in $Environment without a deploy marker."
