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

## Installable mod package

Users do not need to run the packaging script manually. GitHub Actions builds a ready-to-install artifact named:

```text
Morrowind_Korean_ReTranslation_Android_OMWFont
```

The ZIP contains:

```text
mods/Morrowind_Korean_ReTranslation/
  Morrowind_Korean_ReTranslation.esp
  ...
  Fonts/
    KR_OpenMW_Korean.omwfont
    Galmuri11.ttf
    Galmuri11-OFL-1.1.md
```

The package workflow:

1. finds the newest usable `Morrowind_Korean_ReTranslation` release ZIP from `munument1/OpenMW-korean`;
2. keeps the translation payload unchanged and normalizes the active mod directory name;
3. removes legacy `.fnt/.tex` font payload from the Android package;
4. downloads Galmuri v2.40.4 from the official `quiple/galmuri` release;
5. verifies `Galmuri11.ttf` SHA-256 is exactly `e24256f42e43713d2ea086a1e1669d78b968f5b3cc547e5c157f0606ffa5def1`;
6. includes the official SIL Open Font License 1.1 text;
7. adds `KR_OpenMW_Korean.omwfont`, which is the existing KR1 Korean OpenMW descriptor under a collision-free basename;
8. uploads the finished ZIP plus `SHA256SUMS.txt` as a GitHub Actions artifact.

The pinned Galmuri version matches the `Galmuri11.ttf` already used by the current KR1 package (font version 2.404).

Translation ESP/MRK/TOP/CEL/l10n data stays UTF-8. It must not be converted to CP949.

## Internal packager

`source/tools/package-korean-omwfont-mod.py` is an internal CI/release tool, not an end-user installation step. It accepts an existing translation release ZIP plus the validated descriptor/font/license inputs and builds the final Android mod ZIP.

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
2. Extract/enable the packaged `Morrowind_Korean_ReTranslation` data directory after base `Data Files`.
3. Start with no manual `openmw.cfg` / `user.cfg` font edits.
4. Check main menu/settings, inventory/tooltips, NPC dialogue/topics, journal/books and save/load.
5. In generated `openmw.cfg`, confirm the active entries are `KR_OpenMW_Korean` and no imported `Fonts_Font_0,magic_cards_regular` remains.
