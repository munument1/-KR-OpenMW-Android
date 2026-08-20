# Korean OpenMW Android integration

This Android path follows the validated Korean runtime design from:

```text
munument1/-KR-openmw
branch: korean-support
```

The Android engine remains pinned to OpenMW 0.51.0 Final commit:

```text
f4bec41444214a7903bebd178389ca22ca13f646
```

## Engine-side behavior

The Android build applies the three validated Korean runtime patches ported from `-KR-openmw/korean-support`:

1. `0003-korean-cjk-topic-discovery.patch`
   - allows implicit Korean/CJK topic discovery on UTF-8 character boundaries;
   - keeps overlapping matches while dialogue topic-learning scans responses.
2. `0004-korean-utf8-bom-sidecars.patch`
   - opens `.cel/.top/.mrk` translation sidecars in binary mode;
   - a UTF-8 BOM opts the sidecar into direct UTF-8 handling.
3. `0005-korean-mixed-utf8-esm-reader.patch`
   - preserves validated UTF-8 Hangul strings from the Korean translation ESP;
   - keeps normal `win1252` conversion for vanilla Morrowind/Tribunal/Bloodmoon strings.

`source/tools/prepare-openmw-051-runtime.ps1` schedules these patches after the Android/NDK runtime patchers in the OpenMW ExternalProject chain and discards only a stale OpenMW source prefix when required markers are missing. Third-party dependency prefixes remain reusable.

A lightweight GitHub Actions guard downloads the exact `f4bec...` OpenMW source and verifies that all three patches apply cleanly, that the ExternalProject chain contains them in the expected order, and that the native-build wrapper rejects a source tree missing Korean markers.

## Font behavior

The validated Korean package uses OpenMW's normal `MysticCards` slot.

`source/app/openmw.base.cfg` selects:

```cfg
fallback=Fonts_Font_0,MysticCards
fallback=Fonts_Font_2,MysticCards
```

`IniConverter` skips only the `[Fonts]` section from imported `Morrowind.ini`, so vanilla import values such as `magic_cards_regular` and `daedric_font` cannot replace the Korean font selection. Other imported fallback values are preserved.

The active Korean translation data directory supplies:

```text
mods/Morrowind_Korean_ReTranslation/
  Morrowind_Korean_ReTranslation.esp
  Morrowind_Korean_ReTranslation.mrk
  Morrowind_Korean_ReTranslation.top
  Morrowind_Korean_ReTranslation.cel
  l10n/
  Fonts/
    MysticCards.omwfont
    Galmuri11.ttf
    Galmuri11-OFL-1.1.md
```

`MysticCards.omwfont` is the existing RC10l Korean descriptor and points to `Galmuri11.ttf` with code range `33 65535`.

Galmuri11 is pinned to v2.40.4 for the Android package. The expected SHA-256 is:

```text
e24256f42e43713d2ea086a1e1669d78b968f5b3cc547e5c157f0606ffa5def1
```

The SIL Open Font License 1.1 text is included next to the font in generated packages.

## Encoding policy

Do **not** convert the translation payload to CP949.

The intended split is:

```text
vanilla masters              -> normal OpenMW win1252 path
Korean ESP with Hangul UTF-8 -> selective mixed-UTF8 reader path
BOM sidecars                 -> direct UTF-8 sidecar path
font rendering               -> MysticCards.omwfont + Galmuri11.ttf
```

This keeps the original masters compatible while allowing the Korean translation ESP/sidecars to remain UTF-8.

## Package workflow

`source/tools/package-korean-omwfont-mod.py` is an internal CI/release tool. It normalizes the current Korean ReTranslation payload into the Android data-dir layout, drops legacy `.fnt/.tex` assets, and adds the validated OpenMW TrueType font payload.

`.github/workflows/package-korean-android-mod.yml` downloads the current KR1/RC10l payload from the `munument1/-KR-openmw` release `openmw-0.51.0-kr1`. The exact `Morrowind-Korean-OpenMW-0.51.0-KR1-Full.zip` asset is pinned by SHA-256, and the packager selects only its gameplay `ESP/CEL/MRK/TOP/l10n` tree. It also downloads Galmuri v2.40.4 from the official `quiple/galmuri` release, verifies the font SHA and OFL license, and uploads an installable ZIP artifact.

RC9 and public RC10j parser/closure diagnostic assets are not valid fallbacks. If the pinned current KR1/RC10l asset is unavailable or its hash changes, packaging fails rather than emit an older test package. The packager also requires all four core files and validates that `.cel/.mrk/.top` are BOM-prefixed UTF-8.

## Native build

Because the Korean UTF-8 runtime changes are engine changes, a Korean APK needs a rebuilt `libopenmw.so`.

Use the normal OpenMW 0.51 runtime wrapper so the prepare step installs the Korean patches before the native build:

```powershell
cd source\tools
.\build-openmw-051-runtime.ps1 -Jobs 6
```

Do not use `-SkipPrepare` when producing the Korean runtime from a stale workspace.

After the native payload is rebuilt, assemble the launcher APK using the repository's existing final release/gate workflow.

## Device test order

1. Install the rebuilt Korean APK.
2. Extract/enable `Morrowind_Korean_ReTranslation` after base `Data Files`.
3. Do not manually edit `openmw.cfg`, `user.cfg`, or `settings.cfg` for encoding/font selection.
4. Check menu/settings, inventory/tooltips, NPC dialogue/topics, journal/books and save/load.
5. Re-check the known dialogue regression paths: Hasphat Antabolis, Ranis Athrys, and Ajira/Galbedir.
6. Confirm generated config does not contain imported `Fonts_Font_0,magic_cards_regular` or `Fonts_Font_2,daedric_font` overrides.
