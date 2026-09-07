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

function Replace-Once([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $Count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "${Label}: expected exactly one anchor, found $Count"
    }
    return $Text.Replace($Old, $New)
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
    if (-not (Test-Path $Required)) {
        throw "Missing required file: $Required"
    }
}

$Vertex = Read-Lf $AssetVertex
$Fragment = Read-Lf $AssetFragment

if (-not $Vertex.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1') -or
    -not $Vertex.Contains('varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;') -or
    -not $Vertex.Contains('openmwAndroidReceiverPlaneSlope')) {
    throw 'Bundled shadows_vertex.glsl is not the expected grazing-angle receiver-plane shader.'
}

if (-not $Fragment.Contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1') -or
    -not $Fragment.Contains('varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;') -or
    -not $Fragment.Contains('openmwAndroidReceiverDepthForOffset') -or
    -not $Fragment.Contains('float receiverDepth = max(shadowXYZ.z - 0.00005, 0.0);') -or
    -not $Fragment.Contains('OPENMW_ANDROID_051_GLES2_TENT_PCF')) {
    throw 'Bundled shadows_fragment.glsl is not the expected grazing-angle receiver-plane shader.'
}

$BeforeSha = $null
if (Test-Path $JniLib) {
    $BeforeSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Keep an already materialized OpenMW source tree consistent. This changes only
# GLSL resources; libopenmw.so is intentionally not rebuilt.
if (Test-Path $NativeShaderDir) {
    Copy-Item $AssetVertex $NativeVertex -Force
    Copy-Item $AssetFragment $NativeFragment -Force
    Write-Host 'Updated materialized OpenMW 0.51 shadow resource sources.'
}

# ---------------------------------------------------------------------------
# V2 runtime repair: refresh BOTH halves of the shared shadow include pair.
# V1 refreshed shadows_fragment.glsl but MainActivity did not refresh
# shadows_vertex.glsl, so the runtime mirror could link a new fragment input
# against an old vertex output. That is exactly the Adreno linker failure:
#   input shadowReceiverPlaneSlope0 not declared in output from previous stage
# ---------------------------------------------------------------------------
$Main = Read-Lf $MainActivity
$VertexSyncLine = '            "shaders/compatibility/shadows_vertex.glsl",'
if (-not $Main.Contains($VertexSyncLine)) {
    $Old = @'
            "shaders/compatibility/shadowcasting.vert",
            "shaders/compatibility/shadows_fragment.glsl",
'@
    $Old = $Old.TrimEnd([char[]]"`r`n")
    $New = @'
            "shaders/compatibility/shadowcasting.vert",
            "shaders/compatibility/shadows_vertex.glsl",
            "shaders/compatibility/shadows_fragment.glsl",
'@
    $New = $New.TrimEnd([char[]]"`r`n")
    $Main = Replace-Once $Main $Old $New 'MainActivity shadow include-pair runtime sync'
    Write-Host 'Added shadows_vertex.glsl to the per-launch runtime resource refresh.'
} else {
    Write-Host 'MainActivity already refreshes shadows_vertex.glsl.'
}

$ShadowVertexReadMarker = '        val shadowVertexText = File('
if (-not $Main.Contains($ShadowVertexReadMarker)) {
    $Old = @'
        val shadowCastingText = File(
            Constants.USER_FILE_STORAGE + "/resources/shaders/compatibility/shadowcasting.vert"
        ).readText()
        val shadowReceiverText = File(
'@
    $Old = $Old.TrimEnd([char[]]"`r`n")
    $New = @'
        val shadowCastingText = File(
            Constants.USER_FILE_STORAGE + "/resources/shaders/compatibility/shadowcasting.vert"
        ).readText()
        val shadowVertexText = File(
            Constants.USER_FILE_STORAGE + "/resources/shaders/compatibility/shadows_vertex.glsl"
        ).readText()
        val shadowReceiverText = File(
'@
    $New = $New.TrimEnd([char[]]"`r`n")
    $Main = Replace-Once $Main $Old $New 'MainActivity runtime shadow vertex verification source'
    Write-Host 'Added runtime readback for shadows_vertex.glsl.'
}

$PairGateMarker = 'OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_SYNC_V2'
if (-not $Main.Contains($PairGateMarker)) {
    $Old = @'
            throw IOException("Runtime OpenMW 0.51 compatibility shaders still contain GL4ES-hostile uniform initializers")
        }

        val shadowQualityProfile = selectedAndroidShadowQualityProfile()
'@
    $Old = $Old.TrimEnd([char[]]"`r`n")
    $New = @'
            throw IOException("Runtime OpenMW 0.51 compatibility shaders still contain GL4ES-hostile uniform initializers")
        }

        // OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_SYNC_V2
        // Both shared shadow includes must come from the same APK payload. A
        // fragment-only refresh produces valid shaders individually but an
        // invalid program interface and can make terrain/water disappear.
        if (!shadowVertexText.contains("OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1") ||
            !shadowReceiverText.contains("OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1") ||
            !shadowVertexText.contains("varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;") ||
            !shadowReceiverText.contains("varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;")) {
            throw IOException("Runtime OpenMW 0.51 grazing-angle shadow vertex/fragment pair is mismatched")
        }

        val shadowQualityProfile = selectedAndroidShadowQualityProfile()
'@
    $New = $New.TrimEnd([char[]]"`r`n")
    $Main = Replace-Once $Main $Old $New 'MainActivity grazing shadow pair gate'
    Write-Host 'Added fail-fast runtime gate for the shadow vertex/fragment pair.'
}
Write-Utf8Lf $MainActivity $Main

# ---------------------------------------------------------------------------
# Build-time gate: require the vertex include in the APK and verify that both
# shared include files carry the receiver-plane interface before installation.
# ---------------------------------------------------------------------------
$Gradle = Read-Lf $BuildGradle
$RequiredVertexLine = "        file('src/main/assets/libopenmw/resources/shaders/compatibility/shadows_vertex.glsl'),"
if (-not $Gradle.Contains($RequiredVertexLine)) {
    $Old = @'
        file('src/main/assets/libopenmw/resources/shaders/compatibility/shadowcasting.vert'),
        file('src/main/assets/libopenmw/resources/shaders/compatibility/shadows_fragment.glsl'),
'@
    $Old = $Old.TrimEnd([char[]]"`r`n")
    $New = @'
        file('src/main/assets/libopenmw/resources/shaders/compatibility/shadowcasting.vert'),
        file('src/main/assets/libopenmw/resources/shaders/compatibility/shadows_vertex.glsl'),
        file('src/main/assets/libopenmw/resources/shaders/compatibility/shadows_fragment.glsl'),
'@
    $New = $New.TrimEnd([char[]]"`r`n")
    $Gradle = Replace-Once $Gradle $Old $New 'build.gradle required grazing shadow vertex asset'
    Write-Host 'Added shadows_vertex.glsl to requiredOpenMwPayload.'
}

$GradleVertexVariable = "        def shadowVertexShader = file('src/main/assets/libopenmw/resources/shaders/compatibility/shadows_vertex.glsl').getText('UTF-8')"
if (-not $Gradle.Contains($GradleVertexVariable)) {
    $Old = "        def shadowFragmentShader = file('src/main/assets/libopenmw/resources/shaders/compatibility/shadows_fragment.glsl').getText('UTF-8')"
    $New = $GradleVertexVariable + "`n" + $Old
    $Gradle = Replace-Once $Gradle $Old $New 'build.gradle shadow vertex shader load'
    Write-Host 'Added build-time shadows_vertex.glsl inspection.'
}

$BuildPairGateMarker = 'OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_BUILD_GATE_V2'
if (-not $Gradle.Contains($BuildPairGateMarker)) {
    $Old = '        if (fullscreenShader.contains(''uniform vec2 scaling ='') ||'
    $New = @'
        // OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_BUILD_GATE_V2
        if (!shadowVertexShader.contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1') ||
                !shadowFragmentShader.contains('OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1') ||
                !shadowVertexShader.contains('varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;') ||
                !shadowFragmentShader.contains('varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;')) {
            throw new GradleException(
                    'OpenMW Android grazing-angle shadow include pair is incomplete or mismatched.'
            )
        }

        if (fullscreenShader.contains('uniform vec2 scaling =') ||
'@
    $New = $New.TrimEnd([char[]]"`r`n")
    $Gradle = Replace-Once $Gradle $Old $New 'build.gradle grazing shadow include-pair build gate'
    Write-Host 'Added build-time shadow include-pair compatibility gate.'
}

$LauncherSyncBuildGateMarker = 'OPENMW_ANDROID_051_GRAZING_SHADOW_LAUNCHER_SYNC_BUILD_GATE_V2'
if (-not $Gradle.Contains($LauncherSyncBuildGateMarker)) {
    $Old = "        def launcherMainActivity = file('src/main/java/ui/activity/MainActivity.kt').getText('UTF-8')"
    $New = @'
        def launcherMainActivity = file('src/main/java/ui/activity/MainActivity.kt').getText('UTF-8')
        // OPENMW_ANDROID_051_GRAZING_SHADOW_LAUNCHER_SYNC_BUILD_GATE_V2
        if (!launcherMainActivity.contains('"shaders/compatibility/shadows_vertex.glsl"') ||
                !launcherMainActivity.contains('OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_SYNC_V2')) {
            throw new GradleException(
                    'OpenMW launcher must refresh and verify both grazing-angle shadow include files.'
            )
        }
'@
    $New = $New.TrimEnd([char[]]"`r`n")
    $Gradle = Replace-Once $Gradle $Old $New 'build.gradle launcher shadow-pair sync gate'
    Write-Host 'Added build-time launcher runtime-sync gate.'
}
Write-Utf8Lf $BuildGradle $Gradle

# Keep future clean OpenMW 0.51 native/resource rebuilds reproducing the same
# receiver-plane shaders. V1 already adds this block; V2 adds it when missing.
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
    Write-Host 'Permanent OpenMW 0.51 runtime baseline already contains receiver-plane shaders.'
}

# Final source-level verification.
$MainVerify = Read-Lf $MainActivity
$GradleVerify = Read-Lf $BuildGradle
$PatcherVerify = Read-Lf $BaselinePatcher

foreach ($Need in @(
    '"shaders/compatibility/shadows_vertex.glsl"',
    'OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_SYNC_V2',
    'val shadowVertexText = File('
)) {
    if (-not $MainVerify.Contains($Need)) {
        throw "MainActivity V2 verification failed: missing $Need"
    }
}

foreach ($Need in @(
    'src/main/assets/libopenmw/resources/shaders/compatibility/shadows_vertex.glsl',
    'OPENMW_ANDROID_051_GRAZING_SHADOW_PAIR_BUILD_GATE_V2',
    'OPENMW_ANDROID_051_GRAZING_SHADOW_LAUNCHER_SYNC_BUILD_GATE_V2'
)) {
    if (-not $GradleVerify.Contains($Need)) {
        throw "build.gradle V2 verification failed: missing $Need"
    }
}

if (-not $PatcherVerify.Contains($PersistentMarker)) {
    throw 'Permanent OpenMW 0.51 baseline verification failed: receiver-plane shader marker missing.'
}

if ($BeforeSha -ne $null) {
    $AfterSha = (Get-FileHash $JniLib -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($AfterSha -ne $BeforeSha) {
        throw "This repair must not modify libopenmw.so. Before=$BeforeSha After=$AfterSha"
    }
    Write-Host "libopenmw.so unchanged SHA-256: $AfterSha" -ForegroundColor Green
}

Write-Host ''
Write-Host 'OpenMW 0.51 grazing-angle shadow fix V2 runtime-pair repair: SUCCESS' -ForegroundColor Green
Write-Host 'The launcher now refreshes BOTH shadows_vertex.glsl and shadows_fragment.glsl.' -ForegroundColor Green
Write-Host 'No native rebuild is required. Rebuild/reinstall the APK normally.' -ForegroundColor Green
