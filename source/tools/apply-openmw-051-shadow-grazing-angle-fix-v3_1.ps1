param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Read-Lf([string]$Path) {
    return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n" -replace "`r", "`n")
}

function Write-Utf8Lf([string]$Path, [string]$Text) {
    $Text = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

$BuildGradle = Join-Path $ProjectRoot 'app\build.gradle'
$VertexShader = Join-Path $ProjectRoot 'app\src\main\assets\libopenmw\resources\shaders\compatibility\shadows_vertex.glsl'
$FragmentShader = Join-Path $ProjectRoot 'app\src\main\assets\libopenmw\resources\shaders\compatibility\shadows_fragment.glsl'
$JniLib = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a\libopenmw.so'

foreach ($Required in @($BuildGradle, $VertexShader, $FragmentShader)) {
    if (-not (Test-Path $Required)) {
        throw "Missing required file: $Required"
    }
}

$Vertex = Read-Lf $VertexShader
$Fragment = Read-Lf $FragmentShader

# Do not weaken the release gate unless the actual V3 receiver implementation
# is present. These are structural requirements of the V3 texel-centre fix.
foreach ($Need in @(
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3',
    'float determinantScale = length(deltaA.xy) * length(deltaB.xy);',
    'float minimumDeterminant = determinantScale * 1e-5;'
)) {
    if (-not $Vertex.Contains($Need)) {
        throw "V3.1: shadows_vertex.glsl is not the expected V3 shader. Missing: $Need"
    }
}

foreach ($Need in @(
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3',
    'anchorReceiverDepth',
    'openmwAndroidReceiverDepthForOffset(anchorReceiverDepth',
    'floor(shadowXYZ.xy * OPENMW_ANDROID_SHADOW_MAP_RESOLUTION)',
    'pcfShadow * 0.25',
    'pcfShadow * (1.0 / 9.0)',
    'pcfShadow * (1.0 / 64.0)'
)) {
    if (-not $Fragment.Contains($Need)) {
        throw "V3.1: shadows_fragment.glsl is not the expected V3 shader. Missing: $Need"
    }
}

$BeforeSha = $null
if (Test-Path $JniLib) {
    $BeforeSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
}

$Gradle = Read-Lf $BuildGradle
$Marker = 'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3_BUILD_GATE'

if (-not $Gradle.Contains($Marker)) {
    $Old = "                !shadowFragmentShader.contains('step(receiverDepth, texture2D(') ||"
    $Count = ([regex]::Matches($Gradle, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "V3.1: expected exactly one legacy shadow-compare gate, found $Count"
    }

    $New = @'
                // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3_BUILD_GATE
                // V1/V2 compare directly against receiverDepth. V3 reconstructs
                // receiver depth at the actual shadow texel centre first, so
                // anchorReceiverDepth is the correct comparison variable.
                (!shadowFragmentShader.contains('step(receiverDepth, texture2D(') &&
                        !shadowFragmentShader.contains('step(anchorReceiverDepth, texture2D(')) ||
'@
    $New = $New.TrimEnd([char[]]"`r`n")
    $Gradle = $Gradle.Replace($Old, $New)
    Write-Utf8Lf $BuildGradle $Gradle
    Write-Host 'Updated verifyOpenMwPayload for the V3 texel-centre receiver.' -ForegroundColor Green
} else {
    Write-Host 'V3-compatible Gradle shadow gate already present.'
}

# Re-read and verify that the gate still enforces all final Android PCF profiles.
$GradleVerify = Read-Lf $BuildGradle
foreach ($Need in @(
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3_BUILD_GATE',
    "!shadowFragmentShader.contains('step(anchorReceiverDepth, texture2D(')",
    "!shadowFragmentShader.contains('pcfShadow * 0.25')",
    "!shadowFragmentShader.contains('pcfShadow * (1.0 / 9.0)')",
    "!shadowFragmentShader.contains('pcfShadow * (1.0 / 64.0)')",
    "!shadowFragmentShader.contains('OPENMW_ANDROID_051_GLES2_TENT_PCF')"
)) {
    if (-not $GradleVerify.Contains($Need)) {
        throw "V3.1: final build gate verification failed. Missing: $Need"
    }
}

if ($BeforeSha -ne $null) {
    $AfterSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($AfterSha -ne $BeforeSha) {
        throw "V3.1 must not modify libopenmw.so. Before=$BeforeSha After=$AfterSha"
    }
    Write-Host "libopenmw.so unchanged SHA-256: $AfterSha" -ForegroundColor Green
}

Write-Host ''
Write-Host 'OpenMW 0.51 grazing-angle shadow fix V3.1: SUCCESS' -ForegroundColor Green
Write-Host 'The release gate now accepts the V3 texel-centre comparison while still' -ForegroundColor Green
Write-Host 'requiring the 4/9/16-tap PCF payload and tent-PCF implementation.' -ForegroundColor Green
Write-Host 'No native rebuild is required. Build the APK normally.' -ForegroundColor Green
