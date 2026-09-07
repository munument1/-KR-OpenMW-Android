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
$BaselinePatcher = Join-Path $ProjectRoot 'buildscripts\patches\openmw051-final\apply-android-runtime-baseline.py'
$JniLib = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a\libopenmw.so'
$NativeShaderDir = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw\files\shaders\compatibility'
$NativeVertex = Join-Path $NativeShaderDir 'shadows_vertex.glsl'
$NativeFragment = Join-Path $NativeShaderDir 'shadows_fragment.glsl'

foreach ($Required in @($AssetVertex, $AssetFragment, $BaselinePatcher)) {
    if (-not (Test-Path $Required)) {
        throw "Missing required file: $Required"
    }
}

$Vertex = Read-Lf $AssetVertex
$Fragment = Read-Lf $AssetFragment

if (-not $Vertex.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1') -or
    -not $Vertex.Contains('shadowReceiverPlaneSlope@shadow_texture_unit_index') -or
    -not $Vertex.Contains('openmwAndroidReceiverPlaneSlope')) {
    throw 'Bundled shadows_vertex.glsl is not the grazing-angle V1 shader.'
}

if (-not $Fragment.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1') -or
    -not $Fragment.Contains('openmwAndroidReceiverDepthForOffset') -or
    -not $Fragment.Contains('float receiverDepth = max(shadowXYZ.z - 0.00005, 0.0);') -or
    -not $Fragment.Contains('OPENMW_ANDROID_051_GLES2_TENT_PCF')) {
    throw 'Bundled shadows_fragment.glsl is not the grazing-angle V1 shader.'
}

$BeforeSha = $null
if (Test-Path $JniLib) {
    $BeforeSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Keep an already-materialized native OpenMW source tree consistent too. This
# changes only GLSL resource text; libopenmw.so is intentionally not rebuilt.
if (Test-Path $NativeShaderDir) {
    Copy-Item $AssetVertex $NativeVertex -Force
    Copy-Item $AssetFragment $NativeFragment -Force
    Write-Host 'Updated materialized OpenMW 0.51 shader source tree.'
}

# Make future clean OpenMW 0.51 runtime rebuilds reproduce the same shaders.
$PatcherText = Read-Lf $BaselinePatcher
$PersistentMarker = '# OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1'
if (-not $PatcherText.Contains($PersistentMarker)) {
    if ($Vertex.Contains("'''" ) -or $Fragment.Contains("'''")) {
        throw 'Shader contains Python triple-single-quote delimiter; cannot embed safely.'
    }

    $PersistentBlock = @"

# ---------------------------------------------------------------------------
# Android grazing-angle receiver-plane shadow fix.
# Keep this after the baseline GLES2 shadow transformations so a clean native
# rebuild emits exactly the same Android resource shaders as the APK payload.
# ---------------------------------------------------------------------------
$PersistentMarker
shadow_vertex_grazing = root / 'files' / 'shaders' / 'compatibility' / 'shadows_vertex.glsl'
shadow_fragment_grazing = root / 'files' / 'shaders' / 'compatibility' / 'shadows_fragment.glsl'

shadow_vertex_grazing.write_text(r'''$Vertex''', encoding='utf-8', newline='\n')
shadow_fragment_grazing.write_text(r'''$Fragment''', encoding='utf-8', newline='\n')
print('Applied Android GLES2 receiver-plane grazing-angle shadow fix V1.')
"@

    Write-Utf8Lf $BaselinePatcher ($PatcherText.TrimEnd() + $PersistentBlock + "`n")
    Write-Host 'Updated permanent OpenMW 0.51 runtime baseline patcher.'
} else {
    Write-Host 'Permanent OpenMW 0.51 runtime baseline patcher already contains grazing-angle V1.'
}

if ($BeforeSha -ne $null) {
    $AfterSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($AfterSha -ne $BeforeSha) {
        throw "This patch must not modify libopenmw.so. Before=$BeforeSha After=$AfterSha"
    }
    Write-Host "libopenmw.so unchanged SHA-256: $AfterSha" -ForegroundColor Green
}

Write-Host ''
Write-Host 'OpenMW 0.51 grazing-angle shadow fix V1: SUCCESS' -ForegroundColor Green
Write-Host 'No native rebuild is required for the immediate APK test.' -ForegroundColor Green
Write-Host 'Rebuild/reinstall the APK normally and test sunrise/sunset on flat terrain and small hills.'
