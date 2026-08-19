# OpenMW 0.51 Android Korean FNT compatibility

The Android build and the Korean translation mod have separate jobs:

- **APK/runtime:** teach OpenMW 0.51 `FontLoader` how to expose the project's CP949-layout bitmap atlas as Unicode Hangul.
- **ReTranslation mod:** provide the already-built FNT/TEX files under `mods/Morrowind_Korean_ReTranslation/Fonts`.

Translation data remains UTF-8. Nothing in the ESP/MRK/TOP/CEL/l10n set is converted to CP949.

## Existing verified font source

The font payload is reused from the existing `munument1/Morrowind-CP949` release instead of being regenerated:

```text
tag:   v1.0.7-rc6-classic-cp949-pre1
asset: Morrowind_CP949_Classic_Fonts.zip
sha256: 3a7d2442d43d7ed9e0b42d6d8d75068340b00893e06bb2fa696d4ac440bbeee7
```

The release uses the Korean bitmap layout already expected by the runtime patch:

- texture: 2048 x 2048 RGBA
- Korean grid begins at y=512
- cell: 8 x 11
- FNT slot `0xFF` is the CP949 DBCS template
- modern Hangul coverage: 11,172 syllables

No font binary is committed to this Android repository and no font binary is embedded in the APK.

## Build the Korean APK runtime

From `source\tools` in PowerShell:

```powershell
.\build-openmw-051-korean.ps1 -Jobs 6
```

This wrapper:

1. runs the existing OpenMW 0.51 Android prepare path;
2. appends `apply-korean-cp949-bitmap-font.py` to the OpenMW patch chain;
3. rebuilds the Android OpenMW runtime;
4. verifies the `OPENMW_ANDROID_051_KOREAN_CP949_BITMAP` marker;
5. verifies the generated 11,172-entry Hangul mapping header.

Then assemble the APK normally:

```powershell
cd ..
.\gradlew.bat assembleDebug
```

## Build the Android ReTranslation mod ZIP

`package-korean-retranslation-android.py` takes the current KR1/full patch ZIP, keeps only the `mods/Morrowind_Korean_ReTranslation` data, downloads the verified font release, validates it, and adds a `Fonts/` directory.

Example:

```powershell
python .\package-korean-retranslation-android.py `
  --base-zip 'D:\Morrowind-Korean-OpenMW-0.51.0-KR1-Full.zip' `
  --output 'D:\Morrowind_Korean_ReTranslation_Android_FNT.zip'
```

If the font release ZIP is already downloaded, avoid a network download with:

```powershell
python .\package-korean-retranslation-android.py `
  --base-zip 'D:\Morrowind-Korean-OpenMW-0.51.0-KR1-Full.zip' `
  --font-pack 'D:\Morrowind_CP949_Classic_Fonts.zip' `
  --output 'D:\Morrowind_Korean_ReTranslation_Android_FNT.zip'
```

The packager verifies the release SHA-256, FNT structure, 2048x2048 TEX dimensions, and the slot `0xFF` Korean atlas signature before writing anything.

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

`MysticCards.fnt` is byte-identical to `magic_cards_regular.fnt`; `DemonicLetters.fnt` is byte-identical to `daedric_font.fnt`. This covers both OpenMW default font names and imported `Morrowind.ini` font names without requiring a user cfg override. The FNT internal TEX names remain unchanged, so duplicate TEX aliases are unnecessary.

## Runtime rule

The ReTranslation mod data directory must be active after the base `Data Files` directory so its `Fonts/` files have higher VFS priority. The Android launcher already emits active additional data directories in order, so this stays a normal mod-install concern rather than an APK resource hack.

Expected runtime log when a Korean FNT is loaded:

```text
OPENMW_ANDROID_051_KOREAN_CP949_BITMAP: mapped 11172 Hangul glyphs from fonts/<internal-name>.tex
```

First checks: main menu/settings, inventory, NPC dialogue/topics, journal/books, and save/load UI.
