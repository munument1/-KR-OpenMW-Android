param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BasePrepare = Join-Path $PSScriptRoot 'prepare-openmw-051-runtime.ps1'
$CMakeFile = Join-Path $ProjectRoot 'buildscripts\CMakeLists.txt'
$PatchDir = Join-Path $ProjectRoot 'buildscripts\patches\openmw051-final'
$KoreanPatcher = Join-Path $PatchDir 'apply-korean-cp949-bitmap-font.py'
$OpenMwPrefix = Join-Path $ProjectRoot 'buildscripts\build\arm64\openmw-prefix'

foreach ($Required in @($BasePrepare, $CMakeFile, $KoreanPatcher)) {
    if (-not (Test-Path $Required)) {
        throw "Missing Korean OpenMW 0.51 build input: $Required"
    }
}

& $BasePrepare
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

function Read-Lf([string]$Path) {
    return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}

function Write-Utf8Lf([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
}

$Text = Read-Lf $CMakeFile
$PatcherLine = '        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-korean-cp949-bitmap-font.py <SOURCE_DIR>'
$AnchorLine = '        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-android-gl4es-core-inline.py <SOURCE_DIR>'

if (-not $Text.Contains($PatcherLine)) {
    $Wanted = $AnchorLine + ' &&' + "`n" + $PatcherLine
    $Count = ([regex]::Matches($Text, [regex]::Escape($AnchorLine))).Count
    if ($Count -ne 1) {
        throw "Expected exactly one OpenMW 0.51 GL4ES patch-chain anchor, found $Count."
    }
    $Text = $Text.Replace($AnchorLine, $Wanted)
    Write-Utf8Lf $CMakeFile $Text
    Write-Host 'OpenMW 0.51 Korean bitmap FontLoader patch added to OPENMW_PATCH.' -ForegroundColor Cyan
}

# The base runtime prepare script only knows its own runtime markers. If an
# already-extracted OpenMW tree predates either Korean patch stage, force just
# the OpenMW ExternalProject to be recreated while retaining third-party builds.
if (Test-Path $OpenMwPrefix) {
    $FontLoader = Join-Path $OpenMwPrefix 'src\openmw\components\fontloader\fontloader.cpp'
    $HasKoreanBitmap = $false
    $HasKoreanAlias = $false
    if (Test-Path $FontLoader) {
        $FontLoaderText = Read-Lf $FontLoader
        $HasKoreanBitmap = $FontLoaderText.Contains('OPENMW_ANDROID_051_KOREAN_CP949_BITMAP')
        $HasKoreanAlias = $FontLoaderText.Contains('OPENMW_ANDROID_051_KOREAN_FONT_ALIAS')
    }
    if (-not $HasKoreanBitmap -or -not $HasKoreanAlias) {
        Remove-Item $OpenMwPrefix -Recurse -Force
        Write-Host 'Removed stale OpenMW source tree so the complete Korean bitmap/alias patch applies cleanly.' -ForegroundColor Yellow
    }
}

$Verify = Read-Lf $CMakeFile
foreach ($Token in @(
    'patches/openmw051-final/apply-android-gl4es-core-inline.py',
    'patches/openmw051-final/apply-korean-cp949-bitmap-font.py'
)) {
    if (-not $Verify.Contains($Token)) {
        throw "Korean OpenMW 0.51 prepare verification failed: missing $Token"
    }
}

Write-Host ''
Write-Host 'OpenMW 0.51 Korean bitmap runtime setup: READY' -ForegroundColor Green
Write-Host 'Game-data encoding remains win1252/UTF-8 handling from the existing KR runtime.'
Write-Host 'The added patch maps Unicode Hangul to the compatibility atlas and prefers collision-free KR_* font names.'
