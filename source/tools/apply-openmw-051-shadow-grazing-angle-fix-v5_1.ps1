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

function Count-Literal([string]$Text, [string]$Needle) {
    if ([string]::IsNullOrEmpty($Needle)) {
        throw 'Count-Literal: empty needle'
    }
    return [regex]::Matches($Text, [regex]::Escape($Needle)).Count
}

function Remove-GeneratedPatchBlock(
    [string]$Text,
    [string]$UniqueTitle,
    [string]$EndLine
) {
    # Remove ALL matching generated blocks. This deliberately tolerates a
    # partially completed previous V5/V5.1 run and makes this installer idempotent.
    while ($true) {
        $TitleIndex = $Text.IndexOf($UniqueTitle, [StringComparison]::Ordinal)
        if ($TitleIndex -lt 0) {
            break
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

        $Text = $Text.Remove($Start, $End - $Start)
    }

    return $Text.TrimEnd() + "`n"
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

# Runtime pair-sync and V3.1 build gate must still be present.
if (-not $Main.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_SYNC_V2') -or
    -not $Main.Contains('"shaders/compatibility/shadows_vertex.glsl"')) {
    throw 'V5.1 requires the V2 runtime shadow-pair sync.'
}
if (-not $Gradle.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3_BUILD_GATE')) {
    throw 'V5.1 requires the V3.1 anchorReceiverDepth build gate.'
}

# Verify that the project-root overlay really contains the conservative V5 shader,
# and explicitly reject the failed V4 primary geometric-plane implementation.
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
        throw "V5.1 fragment shader incomplete: missing $Need"
    }
}

if ($Fragment.Contains('vec2 receiverPlaneSlope = openmwAndroidGeometricReceiverPlaneSlope(')) {
    throw 'V5.1 safety check failed: failed V4 primary geometric slope is still present.'
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

# A previous V5 run may already have written the final block before its broken
# verification failed. Remove every experimental persistence block first, then
# append exactly one authoritative V5 block.
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

# Correct verification: count the complete literal header via Regex.Escape.
# Do NOT use String.Split(string) here; PowerShell/.NET overload resolution can
# treat the argument as a delimiter character set rather than a literal substring.
$Verify = Read-Lf $BaselinePatcher
$V5Header = '# Android grazing-angle shadow fix V5.'
$V5HeaderCount = Count-Literal $Verify $V5Header
if ($V5HeaderCount -ne 1) {
    throw "V5.1 baseline consolidation failed: expected exactly one V5 header, found $V5HeaderCount."
}

$V5Print = "print('Applied Android GLES2 conservative grazing-angle shadow fix V5.')"
$V5PrintCount = Count-Literal $Verify $V5Print
if ($V5PrintCount -ne 1) {
    throw "V5.1 baseline consolidation failed: expected exactly one V5 terminal line, found $V5PrintCount."
}

foreach ($Obsolete in @(
    '# Android grazing-angle receiver-plane shadow fix.',
    '# Android grazing-angle shadow fix V3.',
    '# Android grazing-angle shadow fix V4.'
)) {
    $Count = Count-Literal $Verify $Obsolete
    if ($Count -ne 0) {
        throw "Obsolete grazing-angle persistence block remains ($Count): $Obsolete"
    }
}

if (-not $Verify.Contains('shadow_fragment_grazing_v5.write_text(') -or
    -not $Verify.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V5')) {
    throw 'V5.1 final baseline block is structurally incomplete.'
}

if ($BeforeSha -ne $null) {
    $AfterSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($AfterSha -ne $BeforeSha) {
        throw "V5.1 must not modify libopenmw.so. Before=$BeforeSha After=$AfterSha"
    }
    Write-Host "libopenmw.so unchanged SHA-256: $AfterSha" -ForegroundColor Green
}

Write-Host ''
Write-Host 'OpenMW 0.51 grazing-angle shadow fix V5.1: SUCCESS' -ForegroundColor Green
Write-Host "Authoritative V5 baseline blocks: $V5HeaderCount" -ForegroundColor Green
Write-Host 'V4 primary geometric-plane implementation is absent.' -ForegroundColor Green
Write-Host 'V3 texel-centre correction is retained.' -ForegroundColor Green
Write-Host 'One-sided geometric relief remains capped at 0.00010 depth.' -ForegroundColor Green
Write-Host 'No native rebuild is required. Rebuild/reinstall the APK normally.' -ForegroundColor Green
