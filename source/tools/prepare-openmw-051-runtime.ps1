param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$FinalCommit = 'f4bec41444214a7903bebd178389ca22ca13f646'

function Read-Lf([string]$Path) {
    return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}

function Write-Utf8Lf([string]$Path, [string]$Text) {
    $Text = $Text -replace "`r`n", "`n"
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

$CMakeFile = Join-Path $ProjectRoot 'buildscripts\CMakeLists.txt'
$VersionFile = Join-Path $ProjectRoot 'buildscripts\include\version.sh'
$PatchDir = Join-Path $ProjectRoot 'buildscripts\patches\openmw051-final'
$FormatPatcher = Join-Path $PatchDir 'apply-ndk-r26-format.py'
$RuntimePatcher = Join-Path $PatchDir 'apply-android-runtime-baseline.py'
$Gl4esCorePatcher = Join-Path $PatchDir 'apply-android-gl4es-core-inline.py'
$KoreanTopicPatch = Join-Path $PatchDir '0003-korean-cjk-topic-discovery.patch'
$KoreanSidecarPatch = Join-Path $PatchDir '0004-korean-utf8-bom-sidecars.patch'
$KoreanEsmPatch = Join-Path $PatchDir '0005-korean-mixed-utf8-esm-reader.patch'

foreach ($Required in @(
    $CMakeFile,
    $VersionFile,
    (Join-Path $PatchDir '0001-ndk-r26-stringstream-compat.patch'),
    (Join-Path $PatchDir '0002-static-osg-link.patch'),
    $KoreanTopicPatch,
    $KoreanSidecarPatch,
    $KoreanEsmPatch,
    $FormatPatcher,
    $RuntimePatcher,
    $Gl4esCorePatcher
)) {
    if (-not (Test-Path $Required)) {
        throw "Missing OpenMW 0.51 runtime migration file: $Required"
    }
}

$CMakeBefore = Read-Lf $CMakeFile
foreach ($Token in @(
    'set(GL4ES_VERSION 5ac069d82ad8ca2cc3c574484e4c5bad880db83e)',
    'set(OSG_VERSION 69cfecebfb6dc703b42e8de39eed750a84a87489)',
    '-DOPENMW_GL4ES_MANUAL_INIT=OFF',
    '-DCMAKE_CXX_STANDARD=20',
    '-DOSG_STATIC=TRUE'
)) {
    if (-not $CMakeBefore.Contains($Token)) {
        throw "0.51 runtime safety check failed: expected unchanged build token is missing: $Token"
    }
}

$VersionText = Read-Lf $VersionFile
if (-not $VersionText.Contains('NDK_VERSION="r26b"')) {
    throw '0.51 runtime safety check failed: Android NDK is no longer r26b.'
}

$CMake = $CMakeBefore
$VersionPattern = '(?m)^set\(OPENMW_VERSION\s+[^)]+\)$'
$VersionMatches = [regex]::Matches($CMake, $VersionPattern)
if ($VersionMatches.Count -ne 1) {
    throw "Expected exactly one OPENMW_VERSION definition, found $($VersionMatches.Count)."
}
$WantedVersion = "set(OPENMW_VERSION $FinalCommit)"
if ($VersionMatches[0].Value -ne $WantedVersion) {
    $CMake = $CMake.Replace($VersionMatches[0].Value, $WantedVersion)
}

$CommentPattern = '(?m)^# OpenMW 0\.(49|50|51).*?$'
if ([regex]::IsMatch($CMake, $CommentPattern)) {
    $CMake = [regex]::Replace(
        $CMake,
        $CommentPattern,
        '# OpenMW 0.51.0 Final Android runtime gate — immutable commit behind tag openmw-0.51.0',
        1
    )
}

$WantedPatchBlock = @'
set(OPENMW_PATCH
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/openmw051-final/0001-ndk-r26-stringstream-compat.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/openmw051-final/0002-static-osg-link.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/openmw051-final/0003-korean-cjk-topic-discovery.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/openmw051-final/0004-korean-utf8-bom-sidecars.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/openmw051-final/0005-korean-mixed-utf8-esm-reader.patch &&
        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-ndk-r26-format.py <SOURCE_DIR> &&
        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-android-runtime-baseline.py <SOURCE_DIR> &&
        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-android-gl4es-core-inline.py <SOURCE_DIR>
)
'@

$PatchPattern = '(?ms)^set\(OPENMW_PATCH\s*\n.*?^\)\s*$'
$PatchMatches = [regex]::Matches($CMake, $PatchPattern)
if ($PatchMatches.Count -ne 1) {
    throw "Expected exactly one OPENMW_PATCH block, found $($PatchMatches.Count)."
}
if ($PatchMatches[0].Value.Trim() -ne $WantedPatchBlock.Trim()) {
    $CMake = $CMake.Remove($PatchMatches[0].Index, $PatchMatches[0].Length).Insert(
        $PatchMatches[0].Index,
        $WantedPatchBlock.TrimEnd()
    )
    Write-Host 'OpenMW 0.51 runtime: installed Android + Korean runtime patch chain.' -ForegroundColor Cyan
}

Write-Utf8Lf $CMakeFile $CMake

# An existing ExternalProject tree may predate one or more Korean runtime patches.
# Refresh OpenMW only when required markers are absent; all third-party dependency
# prefixes remain reusable.
$OpenMwPrefix = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix'
if (Test-Path $OpenMwPrefix) {
    $SourceRoot = Join-Path $OpenMwPrefix 'src\openmw'
    $AndroidMainMarker = Join-Path $SourceRoot 'apps\openmw\androidmain.cpp'
    $KeywordMarker = Join-Path $SourceRoot 'apps\openmw\mwdialogue\keywordsearch.cpp'
    $TranslationMarker = Join-Path $SourceRoot 'components\translation\translation.cpp'
    $EsmMarker = Join-Path $SourceRoot 'components\esm3\esmreader.cpp'

    $HasAndroidRuntime = (Test-Path $AndroidMainMarker) -and (Read-Lf $AndroidMainMarker).Contains('OPENMW_ANDROID_051_RUNTIME_BASELINE')
    $HasKoreanTopic = (Test-Path $KeywordMarker) -and (Read-Lf $KeywordMarker).Contains('allow starts of 3/4-byte UTF-8 chars')
    $HasKoreanSidecars = (Test-Path $TranslationMarker) -and (Read-Lf $TranslationMarker).Contains('utf8BomMode')
    $HasKoreanEsm = (Test-Path $EsmMarker) -and (Read-Lf $EsmMarker).Contains('isValidUtf8WithHangul')

    if (-not ($HasAndroidRuntime -and $HasKoreanTopic -and $HasKoreanSidecars -and $HasKoreanEsm)) {
        Remove-Item $OpenMwPrefix -Recurse -Force
        Write-Host 'OpenMW 0.51 runtime: removed stale OpenMW tree so Android/Korean patches are applied cleanly.' -ForegroundColor Yellow
    }
}

$Verify = Read-Lf $CMakeFile
foreach ($Token in @(
    "set(OPENMW_VERSION $FinalCommit)",
    'patches/openmw051-final/0001-ndk-r26-stringstream-compat.patch',
    'patches/openmw051-final/0002-static-osg-link.patch',
    'patches/openmw051-final/0003-korean-cjk-topic-discovery.patch',
    'patches/openmw051-final/0004-korean-utf8-bom-sidecars.patch',
    'patches/openmw051-final/0005-korean-mixed-utf8-esm-reader.patch',
    'patches/openmw051-final/apply-ndk-r26-format.py',
    'patches/openmw051-final/apply-android-runtime-baseline.py',
    'patches/openmw051-final/apply-android-gl4es-core-inline.py'
)) {
    if (-not $Verify.Contains($Token)) {
        throw "OpenMW 0.51 runtime setup verification failed: missing $Token"
    }
}

foreach ($Forbidden in @(
    'patches/openmw050-final/0001-gl4es-shaders.patch',
    'patches/openmw050-final/0002-android-lifecycle.patch',
    'patches/openmw050-final/0003-android-ui.patch',
    'patches/openmw050-final/0005-gl4es-save-psa.patch',
    'patches/openmw050-final/0007-android-shadow-depth-clamp-fallback.patch',
    'apply-android-shadow-gles2-manual-compare.py',
    'apply-postprocessing-final.py'
)) {
    if ($Verify.Contains($Forbidden)) {
        throw "0.51 runtime accidentally still applies a deferred 0.50 engine patch: $Forbidden"
    }
}

if ($Verify.Contains('patches/osg/psa.patch')) {
    throw '0.51 runtime must not schedule the obsolete OSG GL4ES_SavePSA shim.'
}

$RuntimeText = Read-Lf $RuntimePatcher
foreach ($Token in @(
    'OPENMW_ANDROID_051_RUNTIME_BASELINE',
    'OPENMW_ANDROID_051_LOADINGSCREEN_NO_FB_COPY',
    'SDL_HINT_ANDROID_BLOCK_ON_PAUSE',
    'uniform vec2 scaling;',
    'uniform bool useAdvancedShader;'
)) {
    if (-not $RuntimeText.Contains($Token)) {
        throw "OpenMW 0.51 runtime patch verification failed: missing $Token"
    }
}

$Gl4esCoreText = Read-Lf $Gl4esCorePatcher
foreach ($Token in @(
    'OPENMW_ANDROID_051_GL4ES_CORE_INLINE',
    'vec4 modelToClip(vec4 pos)',
    'vec4 sampleReflectionMap(vec2 uv)',
    'uniform highp sampler2D opaqueDepthTex;'
)) {
    if (-not $Gl4esCoreText.Contains($Token)) {
        throw "OpenMW 0.51 GL4ES core patch verification failed: missing $Token"
    }
}

$KoreanPatchChecks = @(
    @($KoreanTopicPatch, 'parseHyperText(text, mTranslationDataStorage, true)'),
    @($KoreanTopicPatch, 'allow starts of 3/4-byte UTF-8 chars'),
    @($KoreanSidecarPatch, 'std::ios::binary'),
    @($KoreanSidecarPatch, 'utf8BomMode'),
    @($KoreanEsmPatch, 'isValidUtf8WithHangul'),
    @($KoreanEsmPatch, 'mEncoder->getUtf8(raw)')
)
foreach ($Check in $KoreanPatchChecks) {
    $PatchText = Read-Lf $Check[0]
    if (-not $PatchText.Contains($Check[1])) {
        throw "Korean runtime patch verification failed: $($Check[0]) missing $($Check[1])"
    }
}

Write-Host ''
Write-Host 'OpenMW 0.51 Android + Korean runtime setup: READY' -ForegroundColor Green
Write-Host "Pinned engine: OpenMW 0.51.0 Final / $FinalCommit"
Write-Host 'Active engine patches: NDK r26 compatibility + static OSG + Android lifecycle/GL4ES + Korean CJK topics + UTF-8 BOM sidecars + mixed UTF-8 Hangul ESM strings'
Write-Host 'Runtime config policy: keep win1252 for vanilla masters; Korean UTF-8 payload is detected selectively'
Write-Host 'Font policy: launcher selects MysticCards; translation package supplies MysticCards.omwfont + Galmuri11.ttf'
