# OpenMW 0.51 Android Korean FNT compatibility

The Android build and the Korean translation mod have separate jobs:

- **APK/runtime:** teach OpenMW 0.51 `FontLoader` how to expose the project's CP949-layout bitmap atlas as Unicode Hangul.
- **ReTranslation mod:** provide the already-built FNT/TEX files under `mods/Morrowind_Korean_ReTranslation/Fonts`.

Translation data remains UTF-8. Nothing in the ESP/MRK/TOP/CEL/l10n set is converted to CP949.

## Verified font source

The font payload reuses the existing `munument1/Morrowind-CP949` CP949 bitmap-font build instead of regenerating it. The binary identity used by this integration is:

```text
sha256: 3a7d2442d43d7ed9e0b42d6d8d75068340b00893e06bb2fa696d4ac440bbeee7
```

The payload uses the layout expected by the runtime patch:

- texture: 2048 x 2048 RGBA
- Korean grid begins at y=512
- cell: 8 x 11
- FNT slot `0xFF` is the CP949 DBCS template
- modern Hangul coverage: 11,172 syllables

No font binary is committed to this Android repository and no font binary is embedded in the APK.

## Build the Korean APK

The Android repository is at the Patch-41 final-release state. Patch 39 is the last native-code rebuild; Patch 40 and Patch 41 are final-state validation/calibration steps and do not rebuild native code.

From `source\tools` in PowerShell:

```powershell
.\build-openmw-051-korean.ps1 -Jobs 6
```

The wrapper chooses the safest route automatically.

### Existing final build tree

If the current `libopenmw.so` matches `buildscripts\openmw-051-patch39-libopenmw.sha256` and the final OpenMW CMake build tree exists, the wrapper:

1. applies `apply-korean-cp949-bitmap-font.py` directly to that final OpenMW source tree;
2. rebuilds **only** the `openmw` target;
3. copies/strips the rebuilt ARM64 `libopenmw.so`;
4. verifies the 11,172-entry Unicode Hangul mapping and runtime marker;
5. rewrites the Patch-39 native SHA gate for the Korean binary;
6. runs the existing Patch-40 and Patch-41 final-state validators;
7. runs `gradlew.bat assembleMainlineDebug`.

This preserves the final renderer, shadows, OMWFX, launcher and release state instead of falling back to an early runtime build.

### Clean checkout / missing final build tree

If the verified final native/build-tree pair is unavailable, the wrapper performs a clean native build:

1. runs `prepare-openmw-051-korean.ps1`;
2. keeps the consolidated final Android runtime patcher and GL4ES patch chain;
3. appends the Korean FontLoader patch to `OPENMW_PATCH`;
4. runs the native `build.sh` for ARM64 with `--no-resources`, so the already-final Patch-41 APK resources are not replaced;
5. records the new Korean native SHA;
6. runs Patch 40/41 validation and `assembleMainlineDebug`.

Use `-SkipApk` when only the native runtime is wanted. `-NoLto` is available for a clean diagnostic build.

Expected output APK:

```text
source\app\build\outputs\apk\mainline\debug\app-mainline-debug.apk
```

## Build the Android ReTranslation mod ZIP

`package-korean-retranslation-android.py` takes the current KR1/full patch ZIP, keeps only `mods/Morrowind_Korean_ReTranslation`, validates the known CP949 font payload, and adds `Fonts/`.

If the font ZIP is already downloaded, this is the most deterministic form:

```powershell
python .\package-korean-retranslation-android.py `
  --base-zip 'D:\Morrowind-Korean-OpenMW-0.51.0-KR1-Full.zip' `
  --font-pack 'D:\Morrowind_CP949_Classic_Fonts.zip' `
  --output 'D:\Morrowind_Korean_ReTranslation_Android_FNT.zip'
```

The packager verifies SHA-256, FNT structure, 2048x2048 TEX dimensions, and the slot `0xFF` Korean atlas signature before writing the output. Translation files are copied byte-for-byte and remain UTF-8.

## Final mod layout

```text
mods/
  Morrowind_Korean_ReTranslation/
    Morrowind_Korean_ReTranslation.esp
    Morrowind_Korean_ReTranslation.mrk
    Morrowind_Korean_ReTranslation.top
    Morrowind_Korean_ReTranslation.cel
    l10n/
    Fonts/
      magic_cards_regular.fnt
      MysticCards.fnt
      Magic_Cards_Regular_0_Lod_A.tex
      century_gothic_big.fnt
      century_gothic_big_0_Lod_A.tex
      century_gothic_font_regular.fnt
      century_gothic_font_regular_0_Lod_A.tex
      daedric_font.fnt
      DemonicLetters.fnt
      Daedric_font_0_Lod_A.tex
    ANDROID-FNT-MANIFEST.txt
```

`MysticCards.fnt` is byte-identical to `magic_cards_regular.fnt`; `DemonicLetters.fnt` is byte-identical to `daedric_font.fnt`. This covers OpenMW default font names and imported `Morrowind.ini` font names without requiring a user cfg override. The FNT internal TEX names remain unchanged, so TEX aliases are unnecessary.

## Runtime rule

The ReTranslation mod data directory must be active after the base `Data Files` directory so its `Fonts/` files have higher VFS priority. This is normal OpenMW data-directory precedence; no APK resource-font hack is used.

Expected runtime log when a Korean FNT is loaded:

```text
OPENMW_ANDROID_051_KOREAN_CP949_BITMAP: mapped 11172 Hangul glyphs from fonts/<internal-name>.tex
```

First checks: main menu/settings, inventory, NPC dialogue/topics, journal/books, and save/load UI.
