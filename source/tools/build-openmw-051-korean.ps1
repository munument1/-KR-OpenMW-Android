param(
    [ValidateRange(1, 64)]
    [int]$Jobs = 6,

    [switch]$NoLto
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$KoreanPrepare = Join-Path $PSScriptRoot 'prepare-openmw-051-korean.ps1'
$RuntimeBuilder = Join-Path $PSScriptRoot 'build-openmw-051-runtime.ps1'
$OpenMwSource = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw'

foreach ($Required in @($KoreanPrepare, $RuntimeBuilder)) {
    if (-not (Test-Path $Required)) {
        throw "Missing Korean OpenMW 0.51 build tool: $Required"
    }
}

& $KoreanPrepare
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host 'Building OpenMW 0.51 Android runtime with Korean CP949-layout bitmap FontLoader support...' -ForegroundColor Cyan
& $RuntimeBuilder -SkipPrepare -NoLto:$NoLto -Jobs $Jobs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$PatchedFontLoader = Join-Path $OpenMwSource 'components\fontloader\fontloader.cpp'
if (-not (Test-Path $PatchedFontLoader)) {
    throw "Built OpenMW source tree is missing: $PatchedFontLoader"
}
$FontLoaderText = [IO.File]::ReadAllText($PatchedFontLoader)
if (-not $FontLoaderText.Contains('OPENMW_ANDROID_051_KOREAN_CP949_BITMAP')) {
    throw 'Built OpenMW source does not contain the Korean bitmap FontLoader marker.'
}
if ($FontLoaderText.Contains('OPENMW_ANDROID_051_KOREAN_FONT_ALIAS')) {
    throw 'Stale KR_* APK font-alias patch is still present. Re-run the Korean prepare step from a clean OpenMW prefix.'
}

$GeneratedHeader = Join-Path $OpenMwSource 'components\fontloader\koreancp949bitmap.hpp'
if (-not (Test-Path $GeneratedHeader)) {
    throw 'Korean CP949-to-Unicode generated mapping header is missing from the built OpenMW source.'
}
$HeaderText = [IO.File]::ReadAllText($GeneratedHeader)
if (-not $HeaderText.Contains('std::array<Glyph, 11172>')) {
    throw 'Korean mapping header does not contain exactly 11,172 modern Hangul entries.'
}

Write-Host ''
Write-Host 'OpenMW 0.51 Korean Android runtime: READY' -ForegroundColor Green
Write-Host 'Engine change only: Unicode Hangul -> CP949-layout FNT/TEX atlas mapping (11,172 syllables).'
Write-Host 'No font binary is embedded in the APK.'
Write-Host 'The Korean ReTranslation mod must provide its Fonts/ directory at higher VFS priority than Data Files.'
Write-Host 'No openmw.cfg/user.cfg font override is required when the mod includes both OpenMW default and imported-INI FNT aliases.'
Write-Host ''
Write-Host 'Next APK step:'
Write-Host '  cd ..'
Write-Host '  .\gradlew.bat assembleDebug'
