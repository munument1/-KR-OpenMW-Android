#!/usr/bin/env python3
"""Patch OpenMW 0.51 FontLoader to expose a Classic-style CP949 bitmap atlas as Unicode Hangul.

This does not change OpenMW's game-data encoding. It detects the special
2048x2048 / 8x11 / y=512 bitmap-font layout produced by the Korean FNT builder,
registers U+AC00..U+D7A3 MyGUI code points at the corresponding atlas cells,
and prefers collision-free KR_* font asset names for the vanilla/OpenMW font
selection names used by Morrowind.ini and OpenMW fallbacks.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "OPENMW_ANDROID_051_KOREAN_CP949_BITMAP"
ALIAS_MARKER = "OPENMW_ANDROID_051_KOREAN_FONT_ALIAS"
HEADER_NAME = "koreancp949bitmap.hpp"
ATLAS_W = 2048
ATLAS_H = 2048
GRID_Y = 512
CELL_W = 8
CELL_H = 11
LEADS = range(0x81, 0xFE)
TRAILS = tuple(range(0x41, 0x5B)) + tuple(range(0x61, 0x7B)) + tuple(range(0x81, 0xFF))
HANGUL_FIRST = 0xAC00
HANGUL_LAST = 0xD7A3
EXPECTED_HANGUL = 11172


def build_mapping() -> list[tuple[int, int, int]]:
    entries: list[tuple[int, int, int]] = []
    for row, lead in enumerate(LEADS):
        for column, trail in enumerate(TRAILS):
            try:
                ch = bytes((lead, trail)).decode("cp949")
            except UnicodeDecodeError:
                continue
            if len(ch) == 1 and HANGUL_FIRST <= ord(ch) <= HANGUL_LAST:
                entries.append((ord(ch), row, column))

    codepoints = {codepoint for codepoint, _, _ in entries}
    if len(entries) != EXPECTED_HANGUL or len(codepoints) != EXPECTED_HANGUL:
        raise RuntimeError(
            f"unexpected CP949 modern-Hangul mapping: entries={len(entries)} unique={len(codepoints)}"
        )
    if min(codepoints) != HANGUL_FIRST or max(codepoints) != HANGUL_LAST:
        raise RuntimeError("CP949 mapping does not cover the complete modern Hangul syllable range")

    samples = {
        "가": (0xB0, 0xA1),
        "한": (0xC7, 0xD1),
        "힝": (0xC8, 0xFE),
    }
    by_codepoint = {codepoint: (row, column) for codepoint, row, column in entries}
    for ch, (lead, trail) in samples.items():
        expected = (lead - 0x81, TRAILS.index(trail))
        actual = by_codepoint.get(ord(ch))
        if actual != expected:
            raise RuntimeError(f"CP949 sample mismatch for {ch}: expected={expected} actual={actual}")

    return sorted(entries)


def render_header(entries: list[tuple[int, int, int]]) -> str:
    lines = [
        "#ifndef OPENMW_COMPONENTS_FONTLOADER_KOREANCP949BITMAP_HPP",
        "#define OPENMW_COMPONENTS_FONTLOADER_KOREANCP949BITMAP_HPP",
        "",
        "#include <array>",
        "#include <cstdint>",
        "",
        "namespace KoreanCp949Bitmap",
        "{",
        "    struct Glyph",
        "    {",
        "        std::uint16_t codepoint;",
        "        std::uint8_t row;",
        "        std::uint8_t column;",
        "    };",
        "",
        f"    inline constexpr std::array<Glyph, {len(entries)}> glyphs{{{{",
    ]
    for codepoint, row, column in entries:
        lines.append(f"        {{ 0x{codepoint:04X}, {row}, {column} }},")
    lines.extend(
        [
            "    }};",
            "}",
            "",
            "#endif",
            "",
        ]
    )
    return "\n".join(lines)


KOREAN_ALIAS_BLOCK = r'''        // OPENMW_ANDROID_051_KOREAN_FONT_ALIAS
        // The engine-owned resources/vfs archive has the lowest data-directory priority,
        // so a vanilla Data Files/Fonts file with the same name would otherwise win.
        // Prefer collision-free KR_* names when present, then fall back to the requested
        // vanilla/OpenMW name if this runtime was built without the Korean assets.
        std::string_view koreanFileName = fileName;
        if (Misc::StringUtils::ciEqual(fileName, "magic_cards_regular")
            || Misc::StringUtils::ciEqual(fileName, "MysticCards"))
            koreanFileName = "KR_magic_cards_regular";
        else if (Misc::StringUtils::ciEqual(fileName, "century_gothic_font_regular"))
            koreanFileName = "KR_century_gothic_font_regular";
        else if (Misc::StringUtils::ciEqual(fileName, "daedric_font")
            || Misc::StringUtils::ciEqual(fileName, "DemonicLetters"))
            koreanFileName = "KR_daedric_font";

        if (!Misc::StringUtils::ciEqual(koreanFileName, fileName))
        {
            const VFS::Path::Normalized koreanFntPath = VFS::Path::join(fonts, koreanFileName, fnt);
            if (const Files::IStreamPtr stream = mVFS->find(koreanFntPath))
            {
                loadBitmapFont(fontId, koreanFntPath, *stream);
                return;
            }
        }

'''


KOREAN_BLOCK = r'''        // OPENMW_ANDROID_051_KOREAN_CP949_BITMAP
        // A Korean compatibility FNT keeps the normal 256 single-byte slots, but stores
        // the CP949 double-byte glyph atlas below y=512 in a 2048x2048 texture. Classic
        // Morrowind used slot 0xFF as a runtime DBCS template. OpenMW already receives
        // UTF-8/Unicode UI text, so expose those atlas cells directly as Unicode glyphs.
        {
            constexpr int koreanAtlasWidth = 2048;
            constexpr int koreanAtlasHeight = 2048;
            constexpr int koreanGridY = 512;
            constexpr int koreanCellWidth = 8;
            constexpr int koreanCellHeight = 11;

            const GlyphInfo& templateGlyph = data[0xff];
            const auto approximately = [](float actual, float expected) {
                return actual > expected - 0.5f && actual < expected + 0.5f;
            };

            const bool koreanCp949Atlas = width == koreanAtlasWidth && height == koreanAtlasHeight
                && approximately(templateGlyph.top_left.x * width, 0.f)
                && approximately(templateGlyph.top_left.y * height, static_cast<float>(koreanGridY))
                && approximately(templateGlyph.width, static_cast<float>(koreanCellWidth))
                && approximately(templateGlyph.height, static_cast<float>(koreanCellHeight));

            if (koreanCp949Atlas)
            {
                float advance = templateGlyph.width + templateGlyph.kerningRight;
                if (advance == 0.f && templateGlyph.width != 0.f)
                    advance = std::numeric_limits<float>::min();

                const std::string bearing = MyGUI::utility::toString(templateGlyph.kerningLeft) + ' '
                    + MyGUI::utility::toString(fontSize - templateGlyph.ascent);
                const MyGUI::IntSize size(koreanCellWidth, koreanCellHeight);

                for (const KoreanCp949Bitmap::Glyph& glyph : KoreanCp949Bitmap::glyphs)
                {
                    const int x = static_cast<int>(glyph.column) * koreanCellWidth;
                    const int y = koreanGridY + static_cast<int>(glyph.row) * koreanCellHeight;
                    const std::string coord = MyGUI::utility::toString(x) + " " + MyGUI::utility::toString(y) + " "
                        + MyGUI::utility::toString(koreanCellWidth) + " " + MyGUI::utility::toString(koreanCellHeight);

                    MyGUI::xml::ElementPtr code = codes->createChild("Code");
                    code->addAttribute("index", glyph.codepoint);
                    code->addAttribute("coord", coord);
                    code->addAttribute("advance", advance);
                    code->addAttribute("bearing", bearing);
                    code->addAttribute("size", size);
                }

                Log(Debug::Info) << "OPENMW_ANDROID_051_KOREAN_CP949_BITMAP: mapped "
                                 << KoreanCp949Bitmap::glyphs.size() << " Hangul glyphs from " << bitmapPath;
            }
        }

'''


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected exactly one {description} anchor, found {count}")
    return text.replace(old, new, 1)


def patch_source(source_root: Path) -> None:
    cpp = source_root / "components" / "fontloader" / "fontloader.cpp"
    if not cpp.is_file():
        raise RuntimeError(f"OpenMW fontloader.cpp not found: {cpp}")

    entries = build_mapping()
    header = cpp.parent / HEADER_NAME
    header.write_text(render_header(entries), encoding="utf-8", newline="\n")

    text = cpp.read_text(encoding="utf-8")
    include_line = f'#include "{HEADER_NAME}"\n'
    if include_line not in text:
        text = replace_once(
            text,
            '#include "fontloader.hpp"\n',
            '#include "fontloader.hpp"\n' + include_line,
            "fontloader include",
        )

    if '#include <limits>\n' not in text:
        text = replace_once(
            text,
            '#include <format>\n',
            '#include <format>\n#include <limits>\n',
            "limits include",
        )

    if ALIAS_MARKER not in text:
        alias_anchor = '        constexpr VFS::Path::ExtensionView fnt("fnt");\n'
        text = replace_once(
            text,
            alias_anchor,
            alias_anchor + "\n" + KOREAN_ALIAS_BLOCK,
            "Korean font alias insertion",
        )

    if MARKER not in text:
        insertion_anchor = "        // These are required as well, but the fonts don't provide them\n"
        text = replace_once(
            text,
            insertion_anchor,
            KOREAN_BLOCK + insertion_anchor,
            "bitmap-font code insertion",
        )

    if text.count(MARKER) != 2:
        # One source comment and one runtime log string are expected.
        raise RuntimeError(f"unexpected {MARKER} marker count in patched source: {text.count(MARKER)}")
    if text.count(ALIAS_MARKER) != 1:
        raise RuntimeError(f"unexpected {ALIAS_MARKER} marker count in patched source: {text.count(ALIAS_MARKER)}")
    if include_line not in text:
        raise RuntimeError("generated Korean bitmap header include is missing after patch")

    cpp.write_text(text, encoding="utf-8", newline="\n")
    print(f"PASS {MARKER}")
    print(f"PASS {ALIAS_MARKER}")
    print(f"OpenMW source: {source_root}")
    print(f"Generated mapping: {header} ({len(entries)} Hangul syllables)")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <OpenMW source root>", file=sys.stderr)
        return 2
    try:
        patch_source(Path(sys.argv[1]).resolve())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
