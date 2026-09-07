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
$BuildGradle = Join-Path $ProjectRoot 'app\build.gradle'
$BaselinePatcher = Join-Path $ProjectRoot 'buildscripts\patches\openmw051-final\apply-android-runtime-baseline.py'
$JniLib = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a\libopenmw.so'
$NativeShaderDir = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw\files\shaders\compatibility'
$NativeVertex = Join-Path $NativeShaderDir 'shadows_vertex.glsl'
$NativeFragment = Join-Path $NativeShaderDir 'shadows_fragment.glsl'

foreach ($Required in @($AssetVertex, $AssetFragment, $BuildGradle, $BaselinePatcher)) {
    if (-not (Test-Path $Required)) { throw "Missing required file: $Required" }
}

$Vertex = Read-Lf $AssetVertex
$Fragment = Read-Lf $AssetFragment
$Gradle = Read-Lf $BuildGradle

if (-not $Gradle.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3_BUILD_GATE')) {
    throw 'V4 requires V3.1 first.'
}

foreach ($Need in @(
    'OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V4',
    'openmwAndroidGeometricReceiverPlaneSlope',
    'vec3 shadowDx = dFdx(shadowXYZ);',
    'vec3 shadowDy = dFdy(shadowXYZ);',
    'anchorReceiverDepth'
)) {
    if (-not $Fragment.Contains($Need)) { throw "V4 fragment shader incomplete: $Need" }
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
$Marker = '# OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V4'
if (-not $Patcher.Contains($Marker)) {
    if ($Vertex.Contains("'''") -or $Fragment.Contains("'''")) {
        throw 'Shader contains Python triple-single-quote delimiter.'
    }

    $Block = @"

# ---------------------------------------------------------------------------
# Android grazing-angle shadow fix V4.
# V3 texel-centre RPDB + geometric fragment-derivative receiver slope.
# ---------------------------------------------------------------------------
$Marker
shadow_vertex_grazing_v4 = root / 'files' / 'shaders' / 'compatibility' / 'shadows_vertex.glsl'
shadow_fragment_grazing_v4 = root / 'files' / 'shaders' / 'compatibility' / 'shadows_fragment.glsl'

shadow_vertex_grazing_v4.write_text(r'''__VERTEX__''', encoding='utf-8', newline='\n')
shadow_fragment_grazing_v4.write_text(r'''__FRAGMENT__''', encoding='utf-8', newline='\n')
print('Applied Android GLES2 grazing-angle shadow fix V4.')
"@

    $Block = $Block.Replace('__VERTEX__', $Vertex).Replace('__FRAGMENT__', $Fragment)
    Write-Utf8Lf $BaselinePatcher ($Patcher.TrimEnd() + $Block + "`n")
    Write-Host 'Updated permanent OpenMW 0.51 runtime baseline patcher with V4.'
} else {
    Write-Host 'Permanent OpenMW 0.51 runtime baseline already contains V4.'
}

if ($BeforeSha -ne $null) {
    $AfterSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($AfterSha -ne $BeforeSha) {
        throw "V4 must not modify libopenmw.so. Before=$BeforeSha After=$AfterSha"
    }
    Write-Host "libopenmw.so unchanged SHA-256: $AfterSha" -ForegroundColor Green
}

Write-Host ''
Write-Host 'OpenMW 0.51 grazing-angle shadow fix V4: SUCCESS' -ForegroundColor Green
Write-Host 'No native rebuild is required. Rebuild/reinstall the APK normally.' -ForegroundColor Green
