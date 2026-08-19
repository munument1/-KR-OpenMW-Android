param(
    [Parameter(Mandatory = $true)]
    [string]$VanillaFontsDir,

    [Parameter(Mandatory = $true)]
    [string]$KoreanTtf,

    [ValidateRange(8, 32)]
    [int]$FontSize = 11,

    [ValidateRange(1, 64)]
    [int]$Jobs = 6,

    [switch]$NoLto
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$FontBuilder = Join-Path $PSScriptRoot 'build-korean-bitmap-fonts.py'
$KoreanPrepare = Join-Path $PSScriptRoot 'prepare-openmw-051-korean.ps1'
$RuntimeBuilder = Join-Path $PSScriptRoot 'build-openmw-051-runtime.ps1'
$GeneratedRoot = Join-Path $ProjectRoot 'build\korean-bitmap-fonts'
$GeneratedFonts = Join-Path $GeneratedRoot 'fonts'
$Manifest = Join-Path $GeneratedRoot 'korean_bitmap_font_manifest.json'
$AssetFonts = Join-Path $ProjectRoot 'app\src\main\assets\libopenmw\resources\vfs\fonts'
$OpenMwSource = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix\src\openmw'

foreach ($Required in @($FontBuilder, $KoreanPrepare, $RuntimeBuilder)) {
    if (-not (Test-Path $Required)) {
        throw "Missing Korean OpenMW 0.51 build tool: $Required"
    }
}

$VanillaFontsDir = (Resolve-Path $VanillaFontsDir).Path
$KoreanTtf = (Resolve-Path $KoreanTtf).Path

$Python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $Python) {
    throw 'Python 3 is required to build the Korean bitmap font atlas.'
}

& $Python.Source -c 'import PIL, fontTools'
if ($LASTEXITCODE -ne 0) {
    throw 'Python packages Pillow and fonttools are required. Install them for the build environment, then rerun.'
}

if (Test-Path $GeneratedRoot) {
    Remove-Item $GeneratedRoot -Recurse -Force
}

Write-Host ''
Write-Host 'Building complete Korean bitmap font set (Font 0/1/2 + OpenMW aliases)...' -ForegroundColor Cyan
& $Python.Source $FontBuilder `
    --vanilla-fonts $VanillaFontsDir `
    --ttf $KoreanTtf `
    --output $GeneratedRoot `
    --font-size $FontSize `
    --overwrite
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path $Manifest)) {
    throw "Korean font builder did not produce its manifest: $Manifest"
}
$ManifestData = Get-Content $Manifest -Raw | ConvertFrom-Json
if ($ManifestData.format -ne 'OPENMW_ANDROID_051_KOREAN_CP949_BITMAP' -or $ManifestData.render.hangul -ne 11172) {
    throw "Korean font manifest validation failed: format=$($ManifestData.format), hangul=$($ManifestData.render.hangul)"
}

& $KoreanPrepare
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host 'Building OpenMW 0.51 Android runtime with Korean bitmap FontLoader support...' -ForegroundColor Cyan
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
$GeneratedHeader = Join-Path $OpenMwSource 'components\fontloader\koreancp949bitmap.hpp'
if (-not (Test-Path $GeneratedHeader)) {
    throw 'Korean CP949-to-Unicode generated mapping header is missing from the built OpenMW source.'
}
$HeaderText = [IO.File]::ReadAllText($GeneratedHeader)
if (-not $HeaderText.Contains('std::array<Glyph, 11172>')) {
    throw 'Korean mapping header does not contain exactly 11,172 modern Hangul entries.'
}

New-Item -ItemType Directory -Force -Path $AssetFonts | Out-Null
Get-ChildItem $GeneratedFonts -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $AssetFonts $_.Name) -Force
}
Copy-Item $Manifest (Join-Path $AssetFonts 'korean_bitmap_font_manifest.json') -Force

$ExpectedFnt = @(
    'magic_cards_regular.fnt',
    'MysticCards.fnt',
    'century_gothic_font_regular.fnt',
    'daedric_font.fnt',
    'DemonicLetters.fnt'
)
foreach ($Name in $ExpectedFnt) {
    $Path = Join-Path $AssetFonts $Name
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -le 0) {
        throw "APK Korean font asset is missing/empty: $Path"
    }
}

$TexCount = @(Get-ChildItem $AssetFonts -File -Filter '*.tex').Count
if ($TexCount -lt 3) {
    throw "Expected at least three Korean bitmap TEX assets, found $TexCount in $AssetFonts"
}

Write-Host ''
Write-Host 'OpenMW 0.51 Korean APK runtime payload: READY' -ForegroundColor Green
Write-Host 'Engine: Unicode Hangul -> CP949-layout bitmap atlas mapping (11,172 syllables)'
Write-Host 'Font 0: magic_cards_regular + MysticCards alias'
Write-Host 'Font 1: century_gothic_font_regular'
Write-Host 'Font 2: daedric_font + DemonicLetters alias'
Write-Host "APK font assets: $AssetFonts"
Write-Host 'No openmw.cfg/user.cfg font override is required for these standard font names.'
Write-Host ''
Write-Host 'Next APK step:'
Write-Host '  .\gradlew.bat assembleDebug'
