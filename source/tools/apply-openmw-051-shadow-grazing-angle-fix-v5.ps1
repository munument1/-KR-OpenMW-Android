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

function Remove-GeneratedPatchBlock(
    [string]$Text,
    [string]$UniqueTitle,
    [string]$EndLine
) {
    $TitleIndex = $Text.IndexOf($UniqueTitle, [StringComparison]::Ordinal)
    if ($TitleIndex -lt 0) {
        return $Text
    }

    $Separator = '# ---------------------------------------------------------------------------'
    $Start = $Text.LastIndexOf($Separator, $TitleIndex, [StringComparison]::Ordinal)
    if ($Start -lt 0) {
        throw "Could not find start of generated block: $UniqueTitle"
    }

    $EndIndex = $Text.IndexOf($EndLine, $TitleIndex, [StringComparison]::Ordinal)
    if ($EndIndex -lt 0) {
        throw "Could not find end of generated block: $UniqueTitle"
    }

    $End = $EndIndex + $EndLine.Length
    while ($End -lt $Text.Length -and ($Text[$End] -eq "`r" -or $Text[$End] -eq "`n")) {
        $End++
    }

    return $Text.Remove($Start, $End - $Start).TrimEnd() + "`n"
}

$AssetDir = Join-Path $ProjectRoot 'app\src\main\assets\libopenmw\resources\shaders\compatibility'
$AssetVertex = Join-Path $AssetDir 'shadows_vertex.glsl'
$AssetFragment = Join-Path $AssetDir 'shadows_fragment.glsl'
$BuildGradle = Join-Path $ProjectRoot 'app\build.gradle'
$MainActivity = Join-Path $ProjectRoot 'app\src\main\java\ui\activity\MainActivity.kt'
$BaselinePatcher = Join-Path $ProjectRoot 'buildscripts\patches\openmw051-final\apply-android-runtime-baseline.py'
$JniLib = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a\libopenmw.so'
$NativeShaderDir = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw\files\shaders\compatibility'
$NativeVertex = Join-Path $NativeShaderDir 'shadows_vertex.glsl'
$NativeFragment = Join-Path $NativeShaderDir 'shadows_fragment.glsl'

foreach ($Required in @($AssetVertex, $AssetFragment, $BuildGradle, $MainActivity, $BaselinePatcher)) {
    if (-not (Test-Path $Required)) {
        throw "Missing required file: $Required"
    }
}

$Vertex = Read-Lf $AssetVertex
$Fragment = Read-Lf $AssetFragment
$Gradle = Read-Lf $BuildGradle
$Main = Read-Lf $MainActivity

if (-not $Main.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_SYNC_V2') -or
    -not $Main.Contains('"shaders/compatibility/shadows_vertex.glsl"')) {
    throw 'V5 requires the V2 runtime shadow-pair sync.'
}
if (-not $Gradle.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3_BUILD_GATE')) {
    throw 'V5 requires the V3.1 anchorReceiverDepth build gate.'
}

foreach ($Need in @(
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3',
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V5',
    'openmwAndroidGeometricReceiverPlaneSlopeV5',
    'openmwAndroidConservativeReceiverDepthV5',
    'vec2 receiverPlaneSlope = stableReceiverPlaneSlope;',
    'float oneSidedRelief = clamp(stableDepth - geometricDepth, 0.0, 0.00010);',
    'anchorReceiverDepth',
    'pcfShadow * 0.25',
    'pcfShadow * (1.0 / 9.0)',
    'pcfShadow * (1.0 / 64.0)'
)) {
    if (-not $Fragment.Contains($Need)) {
        throw "V5 fragment shader incomplete: missing $Need"
    }
}

if ($Fragment.Contains('vec2 receiverPlaneSlope = openmwAndroidGeometricReceiverPlaneSlope(')) {
    throw 'V5 safety check failed: V4 geometric slope replacement is still present.'
}

$BeforeSha = $null
if (Test-Path $JniLib) {
    $BeforeSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (Test-Path $NativeShaderDir) {
    Copy-Item $AssetVertex $NativeVertex -Force
    Copy-Item $AssetFragment $NativeFragment -Force
    Write-Host 'Updated materialized OpenMW 0.51 shadow shader sources.'
}

$Patcher = Read-Lf $BaselinePatcher

$Patcher = Remove-GeneratedPatchBlock $Patcher `
    '# Android grazing-angle receiver-plane shadow fix.' `
    "print('Applied Android GLES2 receiver-plane grazing-angle shadow fix V1.')"
$Patcher = Remove-GeneratedPatchBlock $Patcher `
    '# Android grazing-angle shadow fix V3.' `
    "print('Applied Android GLES2 grazing-angle shadow fix V3.')"
$Patcher = Remove-GeneratedPatchBlock $Patcher `
    '# Android grazing-angle shadow fix V4.' `
    "print('Applied Android GLES2 grazing-angle shadow fix V4.')"
$Patcher = Remove-GeneratedPatchBlock $Patcher `
    '# Android grazing-angle shadow fix V5.' `
    "print('Applied Android GLES2 conservative grazing-angle shadow fix V5.')"

if ($Vertex.Contains("'''") -or $Fragment.Contains("'''")) {
    throw 'Shader contains Python triple-single-quote delimiter.'
}

$Block = @"

# ---------------------------------------------------------------------------
# Android grazing-angle shadow fix V5.
# V3 texel-centre RPDB remains authoritative. Rasterized triangle derivatives
# are used only for a one-sided, capped self-shadow relief and can never raise
# receiver depth or replace the stable V3 plane.
# ---------------------------------------------------------------------------
# OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V5
shadow_vertex_grazing_v5 = root / 'files' / 'shaders' / 'compatibility' / 'shadows_vertex.glsl'
shadow_fragment_grazing_v5 = root / 'files' / 'shaders' / 'compatibility' / 'shadows_fragment.glsl'

shadow_vertex_grazing_v5.write_text(r'''__VERTEX__''', encoding='utf-8', newline='\n')
shadow_fragment_grazing_v5.write_text(r'''__FRAGMENT__''', encoding='utf-8', newline='\n')
print('Applied Android GLES2 conservative grazing-angle shadow fix V5.')
"@

$Block = $Block.Replace('__VERTEX__', $Vertex).Replace('__FRAGMENT__', $Fragment)
Write-Utf8Lf $BaselinePatcher ($Patcher.TrimEnd() + $Block + "`n")

$Verify = Read-Lf $BaselinePatcher
if (($Verify.Split('# Android grazing-angle shadow fix V5.').Count - 1) -ne 1) {
    throw 'V5 baseline consolidation failed: expected exactly one V5 block.'
}
foreach ($Obsolete in @(
    '# Android grazing-angle receiver-plane shadow fix.',
    '# Android grazing-angle shadow fix V3.',
    '# Android grazing-angle shadow fix V4.'
)) {
    if ($Verify.Contains($Obsolete)) {
        throw "Obsolete grazing-angle persistence block remains: $Obsolete"
    }
}

if ($BeforeSha -ne $null) {
    $AfterSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($AfterSha -ne $BeforeSha) {
        throw "V5 must not modify libopenmw.so. Before=$BeforeSha After=$AfterSha"
    }
    Write-Host "libopenmw.so unchanged SHA-256: $AfterSha" -ForegroundColor Green
}

Write-Host ''
Write-Host 'OpenMW 0.51 grazing-angle shadow fix V5: SUCCESS' -ForegroundColor Green
Write-Host 'V4 geometric plane replacement removed.' -ForegroundColor Green
Write-Host 'V3 texel-centre correction retained.' -ForegroundColor Green
Write-Host 'Geometric receiver data is now one-sided and capped at 0.00010 depth.' -ForegroundColor Green
Write-Host 'Old V1/V3/V4 persistence blocks consolidated into one V5 block.' -ForegroundColor Green
Write-Host 'No native rebuild is required. Rebuild/reinstall the APK normally.' -ForegroundColor Green
