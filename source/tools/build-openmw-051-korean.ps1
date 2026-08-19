param(
    [ValidateRange(1, 32)]
    [int]$Jobs = 6,
    [switch]$NoLto,
    [switch]$SkipApk
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Prepare = Join-Path $PSScriptRoot 'prepare-openmw-051-korean.ps1'
$Patcher = Join-Path $Root 'buildscripts\patches\openmw051-final\apply-korean-cp949-bitmap-font.py'
$Patch40 = Join-Path $PSScriptRoot 'apply-openmw-051-patch40-direct-sun-glare.ps1'
$Patch41 = Join-Path $PSScriptRoot 'apply-openmw-051-patch41-final-release.ps1'
$Source = Join-Path $Root 'buildscripts\build\arm64\openmw-prefix\src\openmw'
$Build = Join-Path $Root 'buildscripts\build\arm64\openmw-prefix\src\openmw-build'
$Jni = Join-Path $Root 'app\src\main\jniLibs\arm64-v8a\libopenmw.so'
$Symbols = Join-Path $Root 'buildscripts\symbols\arm64-v8a\libopenmw.so'
$NativeShaFile = Join-Path $Root 'buildscripts\openmw-051-patch39-libopenmw.sha256'
$Gradle = Join-Path $Root 'gradlew.bat'

foreach ($File in @($Prepare, $Patcher, $Patch40, $Patch41, $Gradle)) {
    if (-not (Test-Path -LiteralPath $File)) { throw "Missing required file: $File" }
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'WSL is required by the OpenMW Android native build environment.'
}

function To-WslPath([string]$WindowsPath) {
    if ($WindowsPath -notmatch '^([A-Za-z]):(?:\\(.*))?$') {
        throw "Unsupported WSL project path: $WindowsPath"
    }
    $Drive = $Matches[1].ToLowerInvariant()
    $Rest = $Matches[2]
    if ([string]::IsNullOrWhiteSpace($Rest)) { return "/mnt/$Drive" }
    return "/mnt/$Drive/" + (($Rest -replace '\\', '/').TrimStart('/'))
}

function Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$Incremental = $false
if ((Test-Path -LiteralPath (Join-Path $Build 'CMakeCache.txt')) -and
    (Test-Path -LiteralPath $Jni) -and
    (Test-Path -LiteralPath $NativeShaFile)) {
    $Expected = ((Get-Content -LiteralPath $NativeShaFile -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    $Incremental = $Expected -eq (Sha256 $Jni)
}

$Mode = if ($Incremental) { 'incremental' } else { 'clean' }
if ($Mode -eq 'clean') {
    Write-Host 'Preparing clean final OpenMW 0.51 + Korean FontLoader build...' -ForegroundColor Cyan
    & $Prepare
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host 'Verified final native base found; rebuilding only OpenMW with Korean FontLoader...' -ForegroundColor Cyan
}

$WslRoot = To-WslPath $Root
$HelperWin = Join-Path $PSScriptRoot '.openmw-051-korean-final-build.sh'
$HelperWsl = "$WslRoot/tools/.openmw-051-korean-final-build.sh"
$LtoArg = if ($NoLto) { '' } else { '--lto' }
$Helper = @'
#!/usr/bin/env bash
set -euo pipefail
ROOT="${OPENMW_KR_ROOT:?}"
MODE="${OPENMW_KR_MODE:?}"
JOBS="${OPENMW_KR_JOBS:?}"
LTO="${OPENMW_KR_LTO:-}"
SRC="$ROOT/buildscripts/build/arm64/openmw-prefix/src/openmw"
BLD="$ROOT/buildscripts/build/arm64/openmw-prefix/src/openmw-build"
PATCHER="$ROOT/buildscripts/patches/openmw051-final/apply-korean-cp949-bitmap-font.py"
JNI="$ROOT/app/src/main/jniLibs/arm64-v8a/libopenmw.so"
SYM="$ROOT/buildscripts/symbols/arm64-v8a/libopenmw.so"
STRIP="$ROOT/buildscripts/toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
READELF="$ROOT/buildscripts/toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"

if [[ "$MODE" == clean ]]; then
    cd "$ROOT/buildscripts"
    args=(--arch arm64 --jobs "$JOBS" --no-resources)
    [[ -n "$LTO" ]] && args+=("$LTO")
    ./build.sh "${args[@]}"
else
    python3 "$PATCHER" "$SRC"
    cmake --build "$BLD" --target openmw --parallel "$JOBS"
    mapfile -t libs < <(find "$BLD" -type f -name libopenmw.so -print)
    [[ ${#libs[@]} -eq 1 ]] || { echo "Expected one rebuilt libopenmw.so, found ${#libs[@]}" >&2; exit 61; }
    mkdir -p "$(dirname "$JNI")" "$(dirname "$SYM")"
    cp -f "${libs[0]}" "$SYM"
    cp -f "${libs[0]}" "$JNI"
    "$STRIP" --strip-unneeded "$JNI"
fi

grep -Fq 'OPENMW_ANDROID_051_KOREAN_CP949_BITMAP' "$SRC/components/fontloader/fontloader.cpp"
grep -Fq 'std::array<Glyph, 11172>' "$SRC/components/fontloader/koreancp949bitmap.hpp"
! grep -Fq 'OPENMW_ANDROID_051_KOREAN_FONT_ALIAS' "$SRC/components/fontloader/fontloader.cpp"
for lib in "$SYM" "$JNI"; do
    test -s "$lib"
    grep -aFq 'OPENMW_ANDROID_051_KOREAN_CP949_BITMAP: mapped ' "$lib"
done
test "$(stat -c %s "$JNI")" -lt "$(stat -c %s "$SYM")"
if [[ -x "$READELF" ]] && "$READELF" -S "$JNI" 2>/dev/null | grep -Eq '\.debug_(info|line|str|abbrev)'; then
    echo 'Packaged JNI still contains DWARF sections.' >&2
    exit 62
fi
echo 'PASS final OpenMW native build with Korean bitmap FontLoader'
'@
[IO.File]::WriteAllText($HelperWin, ($Helper -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
try {
    & wsl.exe env `
        "OPENMW_KR_ROOT=$WslRoot" `
        "OPENMW_KR_MODE=$Mode" `
        "OPENMW_KR_JOBS=$Jobs" `
        "OPENMW_KR_LTO=$LtoArg" `
        bash $HelperWsl
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Remove-Item -LiteralPath $HelperWin -Force -ErrorAction SilentlyContinue
}

foreach ($File in @(
    $Jni,
    $Symbols,
    (Join-Path $Source 'components\fontloader\fontloader.cpp'),
    (Join-Path $Source 'components\fontloader\koreancp949bitmap.hpp')
)) {
    if (-not (Test-Path -LiteralPath $File)) { throw "Missing Korean build output: $File" }
}

$NewSha = Sha256 $Jni
[IO.File]::WriteAllText($NativeShaFile, "$NewSha  $Jni`n", [Text.UTF8Encoding]::new($false))
Write-Host "Korean native SHA gate: $NewSha" -ForegroundColor Green

# Patch 40 and 41 are validators only; they must still pass unchanged.
& $Patch40
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Patch41
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $SkipApk) {
    Push-Location $Root
    try {
        & $Gradle assembleMainlineDebug
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Pop-Location
    }

    $Apk = Join-Path $Root 'app\build\outputs\apk\mainline\debug\app-mainline-debug.apk'
    if (-not (Test-Path -LiteralPath $Apk)) { throw "APK not found: $Apk" }
    Write-Host 'OpenMW 0.51 Korean Android test APK: READY' -ForegroundColor Green
    Write-Host "APK: $Apk"
    Write-Host "SHA-256: $(Sha256 $Apk)"
} else {
    Write-Host 'OpenMW 0.51 Korean native runtime: READY (APK assembly skipped)' -ForegroundColor Green
}

Write-Host 'Fonts remain in the ReTranslation mod; the APK contains engine support only.'
