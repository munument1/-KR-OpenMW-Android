# Korean OpenMW font integration (minimal Android path)

This path intentionally leaves the OpenMW 0.51 native engine unchanged.

## APK-side behavior

`source/app/openmw.base.cfg` selects a unique font basename:

```cfg
fallback=Fonts_Font_0,KR_OpenMW_Korean
fallback=Fonts_Font_2,KR_OpenMW_Korean
```

`IniConverter` skips the `[Fonts]` section from imported `Morrowind.ini`, so vanilla values such as `magic_cards_regular` and `daedric_font` cannot replace the Korean selection.

OpenMW uses Font 0 for the normal UI and Font 2 for scroll text. Font 1 is not needed for this integration.

## Mod-side behavior

The active ReTranslation data directory supplies:

```text
mods/Morrowind_Korean_ReTranslation/
  Morrowind_Korean_ReTranslation.esp
  ...
  Fonts/
    KR_OpenMW_Korean.omwfont
    Galmuri11.ttf
```

The `.omwfont` basename is deliberately unique, so OpenMW will not collide with vanilla `magic_cards_regular.fnt` / `daedric_font.fnt`.

Translation ESP/MRK/TOP/CEL/l10n data stays UTF-8.

## Package the Android test mod

Use an existing KR1 Full ZIP as input. The packager reuses the Galmuri TTF already inside that ZIP; it does not download or embed a font in this repository.

```powershell
python source\tools\package-korean-omwfont-mod.py `
  --base-zip "Morrowind-Korean-OpenMW-0.51.0-KR1-Full.zip" `
  --output "Morrowind_Korean_ReTranslation_Android_OMWFont.zip"
```

## APK build

No C/C++/NDK rebuild is required for this change. Reuse the already-built Patch-41 Android native payload, then rebuild only the launcher APK:

```powershell
cd source
.\gradlew.bat :app:testDebugUnitTest
.\gradlew.bat :app:assembleMainlineDebug
```

Expected APK:

```text
source/app/build/outputs/apk/mainline/debug/app-mainline-debug.apk
```

If the checkout does not already contain the final Patch-41 generated assets/JNI payload, restore or build that payload first using the repository's existing final runtime workflow. Do not rebuild OpenMW merely for the Korean font selection.

## Device test order

1. Install the rebuilt APK.
2. Enable the packaged `Morrowind_Korean_ReTranslation` data directory after base `Data Files`.
3. Start with no manual `openmw.cfg` / `user.cfg` font edits.
4. Check main menu/settings, inventory/tooltips, NPC dialogue/topics, journal/books and save/load.
5. In generated `openmw.cfg`, confirm the active entries are `KR_OpenMW_Korean` and no imported `Fonts_Font_0,magic_cards_regular` remains.
