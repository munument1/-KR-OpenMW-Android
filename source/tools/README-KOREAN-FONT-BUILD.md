# OpenMW 0.51 Android Korean bitmap-font build

This build path packages Korean bitmap fonts into the Android APK runtime without requiring end users to edit `openmw.cfg`, `user.cfg`, or overwrite the original game fonts.

## What it changes

The normal OpenMW 0.51 bitmap loader exposes only the 256 legacy FNT slots as Unicode glyphs. `apply-korean-cp949-bitmap-font.py` keeps those slots intact and detects the Korean compatibility atlas layout used by the project:

- texture: 2048 x 2048 RGBA
- Korean grid starts at y=512
- cell: 8 x 11
- CP949 lead bytes: 0x81..0xFD
- CP949 trail bytes: 0x41..0x5A, 0x61..0x7A, 0x81..0xFE
- FNT slot 0xFF identifies the compatibility layout

At OpenMW build time the patcher generates a 11,172-entry Unicode Hangul mapping header and registers those atlas cells with MyGUI. Game-data encoding is not changed by this patch.

## Why the APK uses `KR_*` names

OpenMW inserts `resources/vfs` before configured game/mod data directories, and later data directories have higher VFS priority. Therefore a Korean font stored in `resources/vfs/fonts` under the same filename as the original `Data Files/Fonts` file can be hidden by the original game font.

The Korean runtime avoids that collision instead of changing data-directory priority globally. The FontLoader first redirects the standard Morrowind/OpenMW selection names to collision-free engine-owned names when those files exist:

- `magic_cards_regular` / `MysticCards` -> `KR_magic_cards_regular`
- `century_gothic_font_regular` -> `KR_century_gothic_font_regular`
- `daedric_font` / `DemonicLetters` -> `KR_daedric_font`

If a `KR_*` asset is absent, FontLoader falls back to the originally requested name. This keeps the patch safe for source builds that do not package the Korean assets.

The FNT internal TEX names are rewritten to the same `KR_*` basenames, so the associated texture files cannot collide with vanilla TEX files either.

## Complete font set

`build-korean-bitmap-fonts.py` reads all three vanilla Morrowind font sources and emits exactly six collision-free runtime files:

- `KR_magic_cards_regular.fnt`
- `KR_magic_cards_regular.tex`
- `KR_century_gothic_font_regular.fnt`
- `KR_century_gothic_font_regular.tex`
- `KR_daedric_font.fnt`
- `KR_daedric_font.tex`

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

1. generates the complete `KR_*` Korean FNT/TEX set and validates all 11,172 modern Hangul syllables;
2. rewrites each FNT internal TEX name to its collision-free `KR_*` name;
3. runs the existing OpenMW 0.51 Android runtime prepare step;
4. appends the Korean FontLoader patch to `OPENMW_PATCH`;
5. rebuilds the OpenMW 0.51 Android runtime;
6. verifies the 11,172-entry Unicode mapping and the runtime font-name redirect marker;
7. copies the six generated FNT/TEX files into `app\src\main\assets\libopenmw\resources\vfs\fonts`;
8. leaves the runtime ready for normal Gradle APK assembly.

Then build the APK normally:

```powershell
cd ..
.\gradlew.bat assembleDebug
```

The `assets` and build-output directories are already ignored by this repository, so generated font binaries do not need to be committed.

## Runtime selection

The APK handles both normal selection paths without a user-side font override:

- imported `Morrowind.ini`: `magic_cards_regular` / `daedric_font`
- OpenMW defaults/fallback: `MysticCards` / `DemonicLetters`

Those names are redirected internally to the matching `KR_*` FNT/TEX pair. No global VFS priority change is made, so ordinary mods keep their normal data-directory override behavior.

## First runtime checks

Check these screens before broader gameplay regression testing:

1. main menu and settings
2. inventory/item names
3. NPC dialogue body and topics
4. journal/books
5. save/load UI

The log should include:

```text
OPENMW_ANDROID_051_KOREAN_CP949_BITMAP: mapped 11172 Hangul glyphs from fonts/KR_<name>.tex
```
