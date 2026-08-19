param(
    [ValidateRange(1, 32)]
    [int]$Jobs = 6,

    [switch]$NoLto,

    [switch]$SkipApk
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$KoreanPrepare = Join-Path $PSScriptRoot 'prepare-openmw-051-korean.ps1'
$KoreanPatcher = Join-Path $ProjectRoot 'buildscripts\patches\openmw051-final\apply-korean-cp949-bitmap-font.py'
$Patch40 = Join-Path $PSScriptRoot 'apply-openmw-051-patch40-direct-sun-glare.ps1'
$Patch41 = Join-Path $PSScriptRoot 'apply-openmw-051-patch41-final-release.ps1'
$OpenMwSource = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw'
$OpenMwBuild = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw-build'
$JniLib = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a\libopenmw.so'
$SymbolLib = Join-Path $ProjectRoot 'buildscripts\symbols\arm64-v8a\libopenmw.so'
$Patch39Sha = Join-Path $ProjectRoot 'buildscripts\openmw-051-patch39-libopenmw.sha256'
$Gradle = Join-Path $ProjectRoot 'gradlew.bat'

foreach ($Required in @($KoreanPrepare, $KoreanPatcher, $Patch40, $Patch41, $Gradle)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        throw "Missing Korean OpenMW 0.51 final-build input: $Required"
    }
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'WSL is required by the existing OpenMW Android native build environment.'
}

function Convert-WindowsPathToWsl([string]$WindowsPath) {
    if ($WindowsPath -notmatch '^([A-Za-z]):(?:\\(.*))?$') {
        throw "Unsupported project path for WSL: $WindowsPath"
    }
    $DriveLetter = $Matches[1].ToLowerInvariant()
    $RelativePart = $Matches[2]
    if ([string]::IsNullOrWhiteSpace($RelativePart)) {
        return "/mnt/$DriveLetter"
    }
    return "/mnt/$DriveLetter/" + (($RelativePart -replace '\\', '/').TrimStart('/'))
}

function Current-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$IncrementalBaseReady = $false
if ((Test-Path -LiteralPath $OpenMwSource) -and
    (Test-Path -LiteralPath (Join-Path $OpenMwBuild 'CMakeCache.txt')) -and
    (Test-Path -LiteralPath $JniLib) -and
    (Test-Path -LiteralPath $Patch39Sha)) {
    $ExpectedBaseSha = ((Get-Content -LiteralPath $Patch39Sha -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    $ActualBaseSha = Current-Sha256 $JniLib
    $IncrementalBaseReady = $ExpectedBaseSha -eq $ActualBaseSha
}

$WslProject = Convert-WindowsPathToWsl $ProjectRoot
$WindowsHelper = Join-Path $PSScriptRoot '.openmw-051-korean-final-build.sh'
$WslHelper = "$WslProject/tools/.openmw-051-korean-final-build.sh"
$Mode = if ($IncrementalBaseReady) { 'incremental' } else { 'clean' }
$LtoArg = if ($NoLto) { '' } else { '--lto' }

if ($Mode -eq 'clean') {
    Write-Host ''
    Write-Host 'No verified Patch-39 native/build-tree pair was found.' -ForegroundColor Yellow
    Write-Host 'Preparing a clean final OpenMW 0.51 native build with the Korean FontLoader patch...' -ForegroundColor Cyan
    & $KoreanPrepare
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host ''
    Write-Host 'Verified Patch-41/Patch-39 native base found.' -ForegroundColor Green
    Write-Host 'Applying the Korean FontLoader patch and rebuilding only the OpenMW target...' -ForegroundColor Cyan
}

$ShellScript = @'
#!/usr/bin/env bash
set -euo pipefail

PROJECT="${OPENMW_KR_PROJECT:?OPENMW_KR_PROJECT is required}"
MODE="${OPENMW_KR_MODE:?OPENMW_KR_MODE is required}"
JOBS="${OPENMW_KR_JOBS:?OPENMW_KR_JOBS is required}"
LTO_ARG="${OPENMW_KR_LTO_ARG:-}"
SOURCE="$PROJECT/buildscripts/build/arm64/openmw-prefix/src/openmw"
BUILD="$PROJECT/buildscripts/build/arm64/openmw-prefix/src/openmw-build"
PATCHER="$PROJECT/buildscripts/patches/openmw051-final/apply-korean-cp949-bitmap-font.py"
JNI="$PROJECT/app/src/main/jniLibs/arm64-v8a/libopenmw.so"
SYMBOLS="$PROJECT/buildscripts/symbols/arm64-v8a/libopenmw.so"
STRIP="$PROJECT/buildscripts/toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
READELF="$PROJECT/buildscripts/toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"

if [[ "$MODE" == clean ]]; then
    cd "$PROJECT/buildscripts"
    args=(--arch arm64 --jobs "$JOBS" --no-resources)
    if [[ -n "$LTO_ARG" ]]; then
        args+=("$LTO_ARG")
    fi
    ./build.sh "${args[@]}"
else
    [[ -f "$SOURCE/components/fontloader/fontloader.cpp" ]] || {
        echo "ERROR: final OpenMW source tree is missing: $SOURCE" >&2
        exit 61
    }
    [[ -f "$BUILD/CMakeCache.txt" ]] || {
        echo "ERROR: final OpenMW CMake build tree is missing: $BUILD" >&2
        exit 62
    }

    python3 "$PATCHER" "$SOURCE"
    cmake --build "$BUILD" --target openmw --parallel "$JOBS"

    mapfile -t built_libs < <(find "$BUILD" -type f -name 'libopenmw.so' -print)
    [[ ${#built_libs[@]} -eq 1 ]] || {
        echo "ERROR: expected exactly one rebuilt libopenmw.so, found ${#built_libs[@]}" >&2
        exit 63
    }
    [[ -x "$STRIP" ]] || { echo "ERROR: llvm-strip is missing: $STRIP" >&2; exit 64; }
    mkdir -p "$(dirname "$SYMBOLS")" "$(dirname "$JNI")"
    cp -f "${built_libs[0]}" "$SYMBOLS"
    cp -f "${built_libs[0]}" "$JNI"
    "$STRIP" --strip-unneeded "$JNI"
fi

# A clean ExternalProject build receives the patch through OPENMW_PATCH;
# an incremental build receives it directly above. Verify both routes identically.
grep -Fq 'OPENMW_ANDROID_051_KOREAN_CP949_BITMAP' "$SOURCE/components/fontloader/fontloader.cpp" || {
    echo 'ERROR: Korean FontLoader source marker is missing.' >&2
    exit 65
}
grep -Fq 'std::array<Glyph, 11172>' "$SOURCE/components/fontloader/koreancp949bitmap.hpp" || {
    echo 'ERROR: generated 11,172-entry Korean mapping header is missing.' >&2
    exit 66
}
! grep -Fq 'OPENMW_ANDROID_051_KOREAN_FONT_ALIAS' "$SOURCE/components/fontloader/fontloader.cpp" || {
    echo 'ERROR: obsolete APK-embedded KR_* alias experiment is present.' >&2
    exit 67
}

for lib in "$SYMBOLS" "$JNI"; do
    [[ -s "$lib" ]] || { echo "ERROR: rebuilt OpenMW library missing/empty: $lib" >&2; exit 68; }
    grep -aFq 'OPENMW_ANDROID_051_KOREAN_CP949_BITMAP: mapped ' "$lib" || {
        echo "ERROR: Korean runtime marker string is missing from $lib" >&2
        exit 69
    }
done

[[ $(stat -c %s "$JNI") -lt $(stat -c %s "$SYMBOLS") ]] || {
    echo 'ERROR: packaged JNI library was not stripped.' >&2
    exit 70
}
if [[ -x "$READELF" ]] && "$READELF" -S "$JNI" 2>/dev/null | grep -Eq '\.debug_(info|line|str|abbrev)'; then
    echo 'ERROR: packaged JNI library still contains DWARF debug sections.' >&2
    exit 71
fi

echo 'PASS OpenMW 0.51 final native build with Korean CP949-layout FontLoader support'
'@

[IO.File]::WriteAllText(
    $WindowsHelper,
    ($ShellScript -replace "`r`n", "`n"),
    [Text.UTF8Encoding]::new($false)
)

try {
    & wsl.exe env `
        "OPENMW_KR_PROJECT=$WslProject" `
        "OPENMW_KR_MODE=$Mode" `
        "OPENMW_KR_JOBS=$Jobs" `
        "OPENMW_KR_LTO_ARG=$LtoArg" `
        bash $WslHelper
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -LiteralPath $WindowsHelper -Force -ErrorAction SilentlyContinue
}

$PatchedFontLoader = Join-Path $OpenMwSource 'components\fontloader\fontloader.cpp'
$GeneratedHeader = Join-Path $OpenMwSource 'components\fontloader\koreancp949bitmap.hpp'
foreach ($Required in @($JniLib, $SymbolLib, $PatchedFontLoader, $GeneratedHeader)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        throw "Korean final native build output is missing: $Required"
    }
}

$FontLoaderText = [IO.File]::ReadAllText($PatchedFontLoader)
if (-not $FontLoaderText.Contains('OPENMW_ANDROID_051_KOREAN_CP949_BITMAP')) {
    throw 'Built OpenMW source does not contain the Korean bitmap FontLoader marker.'
}
if ($FontLoaderText.Contains('OPENMW_ANDROID_051_KOREAN_FONT_ALIAS')) {
    throw 'Obsolete KR_* APK font-alias patch is still present.'
}
$HeaderText = [IO.File]::ReadAllText($GeneratedHeader)
if (-not $HeaderText.Contains('std::array<Glyph, 11172>')) {
    throw 'Korean mapping header does not contain exactly 11,172 modern Hangul entries.'
}

$NewNativeSha = Current-Sha256 $JniLib
[IO.File]::WriteAllText(
    $Patch39Sha,
    "$NewNativeSha  $JniLib`n",
    [Text.UTF8Encoding]::new($false)
)
Write-Host "Updated Patch-39 native SHA gate for the Korean build: $NewNativeSha" -ForegroundColor Green

# Patch 40/41 are final-state validators and do not rebuild native code.
& $Patch40
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Patch41
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $SkipApk) {
    Write-Host ''
    Write-Host 'Assembling Android debug APK through the existing final-release Gradle gate...' -ForegroundColor Cyan
    Push-Location $ProjectRoot
    try {
        & $Gradle assembleDebug
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    finally {
        Pop-Location
    }

    $Apk = Join-Path $ProjectRoot 'app\build\outputs\apk\debug\app-debug.apk'
    if (-not (Test-Path -LiteralPath $Apk)) {
        throw "Gradle succeeded but debug APK was not found: $Apk"
    }
    $ApkSha = Current-Sha256 $Apk
    Write-Host ''
    Write-Host 'OpenMW 0.51 Korean Android test APK: READY' -ForegroundColor Green
    Write-Host "APK: $Apk"
    Write-Host "SHA-256: $ApkSha"
} else {
    Write-Host ''
    Write-Host 'OpenMW 0.51 Korean final native runtime: READY (APK assembly skipped)' -ForegroundColor Green
}

Write-Host 'Engine change: Unicode Hangul -> existing CP949-layout FNT/TEX atlas (11,172 syllables).'
Write-Host 'Font binaries remain in the ReTranslation mod, not in the APK.'
