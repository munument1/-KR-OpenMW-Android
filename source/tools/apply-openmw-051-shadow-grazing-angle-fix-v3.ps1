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

$AssetDir = Join-Path $ProjectRoot 'app\src\main\assets\libopenmw\resources\shaders\compatibility'
$AssetVertex = Join-Path $AssetDir 'shadows_vertex.glsl'
$AssetFragment = Join-Path $AssetDir 'shadows_fragment.glsl'
$MainActivity = Join-Path $ProjectRoot 'app\src\main\java\ui\activity\MainActivity.kt'
$BuildGradle = Join-Path $ProjectRoot 'app\build.gradle'
$BaselinePatcher = Join-Path $ProjectRoot 'buildscripts\patches\openmw051-final\apply-android-runtime-baseline.py'
$JniLib = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a\libopenmw.so'
$NativeShaderDir = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw\files\shaders\compatibility'
$NativeVertex = Join-Path $NativeShaderDir 'shadows_vertex.glsl'
$NativeFragment = Join-Path $NativeShaderDir 'shadows_fragment.glsl'

foreach ($Required in @($AssetVertex, $AssetFragment, $MainActivity, $BuildGradle, $BaselinePatcher)) {
    if (-not (Test-Path $Required)) { throw "Missing required file: $Required" }
}

$Vertex = Read-Lf $AssetVertex
$Fragment = Read-Lf $AssetFragment
$Main = Read-Lf $MainActivity
$Gradle = Read-Lf $BuildGradle

if (-not $Main.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_SYNC_V2') -or
    -not $Main.Contains('"shaders/compatibility/shadows_vertex.glsl"')) {
    throw 'V3 requires the V2 runtime shadow-pair repair.'
}
if (-not $Gradle.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_BUILD_GATE_V2')) {
    throw 'V3 requires the V2 build-time shadow-pair gate.'
}

foreach ($Need in @(
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3',
    'float determinantScale = length(deltaA.xy) * length(deltaB.xy);',
    'float minimumDeterminant = determinantScale * 1e-5;',
    'return clamp(receiverSlope, vec2(-128.0), vec2(128.0));'
)) {
    if (-not $Vertex.Contains($Need)) { throw "V3 vertex shader incomplete: $Need" }
}

foreach ($Need in @(
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3',
    'float receiverSlopeFootprint =',
    'receiverSlopeFootprint * 0.35',
    'anchorReceiverDepth',
    'OPENMW_ANDROID_051_GLES2_TENT_PCF'
)) {
    if (-not $Fragment.Contains($Need)) { throw "V3 fragment shader incomplete: $Need" }
}

$BeforeSha = $null
if (Test-Path $JniLib) {
    $BeforeSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (Test-Path $NativeShaderDir) {
    Copy-Item $AssetVertex $NativeVertex -Force
    Copy-Item $AssetFragment $NativeFragment -Force
    Write-Host 'Updated materialized OpenMW 0.51 shadow resource sources.'
}

$Patcher = Read-Lf $BaselinePatcher
$Marker = '# OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3'
if (-not $Patcher.Contains($Marker)) {
    if ($Vertex.Contains("'''") -or $Fragment.Contains("'''")) {
        throw 'Shader contains Python triple-single-quote delimiter.'
    }

    $Block = @"

# ---------------------------------------------------------------------------
# Android grazing-angle shadow fix V3.
# Scale-aware receiver-plane solve + exact shadow texel-centre PCF correction.
# ---------------------------------------------------------------------------
$Marker
shadow_vertex_grazing_v3 = root / 'files' / 'shaders' / 'compatibility' / 'shadows_vertex.glsl'
shadow_fragment_grazing_v3 = root / 'files' / 'shaders' / 'compatibility' / 'shadows_fragment.glsl'

shadow_vertex_grazing_v3.write_text(r'''$Vertex''', encoding='utf-8', newline='\n')
shadow_fragment_grazing_v3.write_text(r'''$Fragment''', encoding='utf-8', newline='\n')
print('Applied Android GLES2 grazing-angle shadow fix V3.')
"@

    Write-Utf8Lf $BaselinePatcher ($Patcher.TrimEnd() + $Block + "`n")
    Write-Host 'Updated permanent OpenMW 0.51 runtime baseline patcher with V3.'
} else {
    Write-Host 'Permanent OpenMW 0.51 runtime baseline already contains V3.'
}

if ($BeforeSha -ne $null) {
    $AfterSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($AfterSha -ne $BeforeSha) {
        throw "V3 must not modify libopenmw.so. Before=$BeforeSha After=$AfterSha"
    }
    Write-Host "libopenmw.so unchanged SHA-256: $AfterSha" -ForegroundColor Green
}

Write-Host ''
Write-Host 'OpenMW 0.51 grazing-angle shadow fix V3: SUCCESS' -ForegroundColor Green
Write-Host 'No native rebuild is required. Rebuild/reinstall the APK normally.' -ForegroundColor Green
