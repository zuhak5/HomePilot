param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('apk', 'aab')]
    [string]$ArtifactType,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedBuild
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workspacePrefix = $workspace + [System.IO.Path]::DirectorySeparatorChar
$resolvedArtifact = [System.IO.Path]::GetFullPath($ArtifactPath)
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)

foreach ($target in @($resolvedArtifact, $resolvedOutput)) {
    if (-not $target.StartsWith(
            $workspacePrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Release evidence target is outside the workspace: $target"
    }
}
if (-not (Test-Path -LiteralPath $resolvedArtifact -PathType Leaf)) {
    throw "Release artifact was not found: $resolvedArtifact"
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

$dependencyReport = Join-Path $resolvedOutput 'prod-release-runtime-classpath.txt'
Push-Location (Join-Path $workspace 'android')
try {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & '.\gradlew.bat' ':app:dependencies' '--configuration' 'prodReleaseRuntimeClasspath' `
        2>&1 | Set-Content -LiteralPath $dependencyReport -Encoding utf8NoBOM
    $gradleExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($gradleExitCode -ne 0) {
        throw "Gradle dependency evidence failed with exit code $gradleExitCode."
    }
}
finally {
    Pop-Location
}

$dependencies = Get-Content -LiteralPath $dependencyReport -Raw
if ($dependencies -match '(?i)firebase-analytics|firebase-analytics-ktx') {
    throw 'Production dependencies contain direct Firebase Analytics.'
}

$intermediatesRoot = Join-Path $workspace 'build\app\intermediates'
$manifestCandidates = @(Get-ChildItem `
    -LiteralPath $intermediatesRoot `
    -Recurse `
    -File `
    -Filter 'AndroidManifest.xml' |
    Where-Object {
        $relativePath = ($_.FullName.Substring($intermediatesRoot.Length)).Replace(
            [System.IO.Path]::DirectorySeparatorChar,
            '/'
        )
        $relativePath -match '(?i)^/merged_manifests?/prodRelease/'
    } |
    Sort-Object LastWriteTimeUtc -Descending)
if ($manifestCandidates.Count -eq 0) {
    throw 'A merged prodRelease AndroidManifest.xml was not found.'
}
$mergedManifestPath = Join-Path $resolvedOutput 'AndroidManifest-prodRelease.xml'
Copy-Item -LiteralPath $manifestCandidates[0].FullName -Destination $mergedManifestPath -Force
$manifestDocument = New-Object System.Xml.XmlDocument
$manifestDocument.PreserveWhitespace = $true
$manifestDocument.Load($mergedManifestPath)
$androidNamespace = 'http://schemas.android.com/apk/res/android'
$namespaceManager = New-Object System.Xml.XmlNamespaceManager($manifestDocument.NameTable)
$namespaceManager.AddNamespace('android', $androidNamespace)
$manifestNode = $manifestDocument.DocumentElement
if (-not $manifestNode -or $manifestNode.LocalName -ne 'manifest') {
    throw 'Merged production manifest does not have a manifest root element.'
}

$actualPackage = $manifestNode.GetAttribute('package')
if ($actualPackage -ne 'com.homepilot.app') {
    throw "Unexpected merged-manifest package: $actualPackage"
}

$usesSdkNode = $manifestNode.SelectSingleNode('uses-sdk')
if (-not $usesSdkNode) {
    throw 'Merged production manifest has no uses-sdk declaration.'
}
$actualTargetSdk = $usesSdkNode.GetAttribute('targetSdkVersion', $androidNamespace)
if ($actualTargetSdk -ne '36') {
    throw "Unexpected merged-manifest targetSdkVersion: $actualTargetSdk"
}

$applicationNode = $manifestNode.SelectSingleNode('application')
if (-not $applicationNode) {
    throw 'Merged production manifest has no application declaration.'
}
$actualAllowBackup = $applicationNode.GetAttribute('allowBackup', $androidNamespace)
if ($actualAllowBackup -ne 'false') {
    throw "Production android:allowBackup must be exactly false, got: $actualAllowBackup"
}
$actualDebuggable = $applicationNode.GetAttribute('debuggable', $androidNamespace)
if ($actualDebuggable -eq 'true') {
    throw 'Merged production manifest is debuggable.'
}

$permissionNames = @($manifestNode.SelectNodes('uses-permission') | ForEach-Object {
        $_.GetAttribute('name', $androidNamespace)
    })
foreach ($requiredPermission in @(
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.SCHEDULE_EXACT_ALARM'
)) {
    if ($permissionNames -notcontains $requiredPermission) {
        throw "Merged manifest is missing required permission: $requiredPermission"
    }
}
foreach ($forbiddenPermission in @(
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_BACKGROUND_LOCATION'
    )) {
    if ($permissionNames -contains $forbiddenPermission) {
        throw "Merged manifest contains forbidden permission: $forbiddenPermission"
    }
}

$adMobMetadata = @($applicationNode.SelectNodes('meta-data') | Where-Object {
        $_.GetAttribute('name', $androidNamespace) -eq
            'com.google.android.gms.ads.APPLICATION_ID'
    })
if ($adMobMetadata.Count -ne 1) {
    throw "Expected exactly one AdMob application metadata entry, found $($adMobMetadata.Count)."
}
$actualAdMobApplicationId = $adMobMetadata[0].GetAttribute('value', $androidNamespace)
if ($actualAdMobApplicationId -ne 'ca-app-pub-5274007212820203~4912255757') {
    throw "Unexpected production AdMob application ID: $actualAdMobApplicationId"
}
$mergedManifest = Get-Content -LiteralPath $mergedManifestPath -Raw
if ($mergedManifest -match [regex]::Escape('ca-app-pub-3940256099942544')) {
    throw 'Merged production manifest contains a Google demo AdMob identifier.'
}

$outputsRoot = Join-Path $workspace 'build\app\outputs'
$metadataCandidates = @(Get-ChildItem `
    -LiteralPath $outputsRoot `
    -Recurse `
    -File `
    -Filter 'output-metadata.json' |
    Where-Object {
        $relativePath = ($_.FullName.Substring($outputsRoot.Length)).Replace(
            [System.IO.Path]::DirectorySeparatorChar,
            '/'
        )
        if ($ArtifactType -eq 'apk') {
            $relativePath -match '(?i)^/apk/prod/release/output-metadata\.json$'
        }
        else {
            $relativePath -match '(?i)^/bundle/prodRelease/output-metadata\.json$'
        }
    } |
    Sort-Object LastWriteTimeUtc -Descending)
if ($metadataCandidates.Count -gt 1) {
    throw "Expected at most one $ArtifactType prod release output-metadata.json, found $($metadataCandidates.Count)."
}
$metadataSource = $null
if ($metadataCandidates.Count -eq 1) {
    $metadataPath = Join-Path $resolvedOutput "output-metadata-$ArtifactType.json"
    Copy-Item -LiteralPath $metadataCandidates[0].FullName -Destination $metadataPath -Force
    $metadataSource = $metadataCandidates[0].FullName.Substring($workspacePrefix.Length)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.applicationId -ne 'com.homepilot.app') {
        throw "Unexpected metadata applicationId: $($metadata.applicationId)"
    }
    $elements = @($metadata.elements)
    if ($elements.Count -ne 1) {
        throw "Release output metadata must have exactly one artifact element, found $($elements.Count)."
    }
    $element = $elements[0]
    if ([string]$element.versionCode -ne $ExpectedBuild) {
        throw "Unexpected metadata versionCode: $($element.versionCode)"
    }
    if ([string]$element.versionName -ne $ExpectedVersion) {
        throw "Unexpected metadata versionName: $($element.versionName)"
    }
}
else {
    $manifestVersionCode = $manifestNode.GetAttribute('versionCode', $androidNamespace)
    if ($manifestVersionCode -ne $ExpectedBuild) {
        throw 'Merged manifest versionCode does not match the requested build.'
    }
    $manifestVersionName = $manifestNode.GetAttribute('versionName', $androidNamespace)
    if ($manifestVersionName -ne $ExpectedVersion) {
        throw 'Merged manifest versionName does not match the requested version.'
    }
}

$hash = (Get-FileHash -LiteralPath $resolvedArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
$summary = [ordered]@{
    artifact_type = $ArtifactType
    artifact_file = [System.IO.Path]::GetFileName($resolvedArtifact)
    artifact_sha256 = $hash
    package = $actualPackage
    version_name = $ExpectedVersion
    version_code = $ExpectedBuild
    target_sdk = [int]$actualTargetSdk
    allow_backup = [System.Convert]::ToBoolean($actualAllowBackup)
    admob_application_id = $actualAdMobApplicationId
    manifest_source = $manifestCandidates[0].FullName.Substring($workspacePrefix.Length)
    output_metadata_source = $metadataSource
    dependency_configuration = 'prodReleaseRuntimeClasspath'
    firebase_analytics_present = $false
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json
[System.IO.File]::WriteAllText(
    (Join-Path $resolvedOutput 'release-evidence-summary.json'),
    $summary,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Collected $ArtifactType evidence for HomePilot $ExpectedVersion ($ExpectedBuild)."
