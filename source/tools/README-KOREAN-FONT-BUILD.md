# OpenMW 0.51 Android Korean bitmap-font build

This build path packages Korean bitmap fonts into the Android APK runtime without requiring end users to edit `openmw.cfg` or `user.cfg`.

## What it changes

The normal OpenMW 0.51 bitmap loader exposes only the 256 legacy FNT slots as Unicode glyphs. `apply-korean-cp949-bitmap-font.py` keeps those slots intact and detects the Korean compatibility atlas layout used by the project:

- texture: 2048 x 2048 RGBA
- Korean grid starts at y=512
- cell: 8 x 11
- CP949 lead bytes: 0x81..0xFD
- CP949 trail bytes: 0x41..0x5A, 0x61..0x7A, 0x81..0xFE
- FNT slot 0xFF identifies the compatibility layout

At OpenMW build time the patcher generates a 11,172-entry Unicode Hangul mapping header and registers those atlas cells with MyGUI. Game-data encoding is not changed by this patch.

## Complete font set

`build-korean-bitmap-fonts.py` builds all three vanilla Morrowind font sources and the two OpenMW fallback aliases:

- `magic_cards_regular.fnt`
- `MysticCards.fnt`
- `century_gothic_font_regular.fnt`
- `daedric_font.fnt`
- `DemonicLetters.fnt`
- the three TEX files referenced internally by the source FNTs

No font binary is stored in this repository. The builder requires your local original Morrowind `Data Files\Fonts` directory and a local Korean TTF such as the project's Galmuri11 source font.

## Build

From `source\tools` in PowerShell:

```powershell
.\build-openmw-051-korean.ps1 `
  -VanillaFontsDir 'D:\Games\Morrowind\Data Files\Fonts' `
  -KoreanTtf 'D:\Morrowind-KR\Galmuri11.ttf' `
  -Jobs 6
```

Requirements for the build machine:

- the existing WSL/Android OpenMW build environment used by `build-openmw-051-runtime.ps1`
- Python 3
- Pillow
- fonttools
- original Morrowind FNT/TEX files
- a local Korean TTF

The wrapper performs these steps in order:

1. generates the complete Korean FNT/TEX set and validates all 11,172 modern Hangul syllables;
2. runs the existing OpenMW 0.51 Android runtime prepare step;
3. appends the Korean FontLoader patch to `OPENMW_PATCH`;
4. rebuilds the OpenMW 0.51 Android runtime;
5. verifies the generated 11,172-entry Unicode mapping;
6. copies the generated FNT/TEX set into `app\src\main\assets\libopenmw\resources\vfs\fonts`;
7. leaves the runtime ready for normal Gradle APK assembly.

Then build the APK normally:

```powershell
cd ..
.\gradlew.bat assembleDebug
```

The `assets` and build-output directories are already ignored by this repository, so generated font binaries do not need to be committed.

## Runtime selection

The APK provides both selection paths used by Morrowind/OpenMW:

- imported `Morrowind.ini`: `magic_cards_regular` / `daedric_font`
- OpenMW defaults/fallback: `MysticCards` / `DemonicLetters`

That makes the standard font-name paths resolve to the same Korean-compatible atlases without a user-side font override.

## First runtime checks

Check these screens before broader gameplay regression testing:

1. main menu and settings
2. inventory/item names
3. NPC dialogue body and topics
4. journal/books
5. save/load UI

The log should include:

```text
OPENMW_ANDROID_051_KOREAN_CP949_BITMAP: mapped 11172 Hangul glyphs from fonts/<name>.tex
```
