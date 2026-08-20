#!/usr/bin/env python3
"""Build the Android OpenMW Korean translation mod from an existing KR1 full ZIP.

The script does not ship or download any font binary. It reuses Galmuri11.ttf
already present in the caller-supplied KR1 package and places it next to a
unique OpenMW .omwfont descriptor inside the ReTranslation data directory.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from pathlib import Path

MOD_PREFIX = "mods/Morrowind_Korean_ReTranslation/"
FONT_DIR = MOD_PREFIX + "Fonts/"
SOURCE_TTF = "OpenMW/resources/vfs/fonts/Galmuri11.ttf"
TARGET_TTF = FONT_DIR + "Galmuri11.ttf"
TARGET_OMWFONT = FONT_DIR + "KR_OpenMW_Korean.omwfont"
README_ENTRY = "README-ANDROID-KR-OMWFONT.txt"

OMWFONT_XML = """<MyGUI type=\"Resource\" version=\"1.1\">\n    <Resource type=\"ResourceTrueTypeFont\">\n        <Property key=\"Source\" value=\"Galmuri11.ttf\"/>\n        <Property key=\"Antialias\" value=\"false\"/>\n        <Property key=\"SubstituteCode\" value=\"95\"/>\n        <Property key=\"TabWidth\" value=\"8\"/>\n        <Property key=\"OffsetHeight\" value=\"0\"/>\n        <Property key=\"Resolution\" value=\"68\"/>\n        <Codes>\n            <Code range=\"33 65535\"/>\n        </Codes>\n    </Resource>\n</MyGUI>\n"""

README_TEXT = """Morrowind Korean ReTranslation - Android OpenMW font test\n\nThis package is intended for the KR OpenMW Android build that selects:\n  fallback=Fonts_Font_0,KR_OpenMW_Korean\n  fallback=Fonts_Font_2,KR_OpenMW_Korean\n\nTranslation data remains UTF-8. The font is loaded through OpenMW's native\n.omwfont + TrueType path; no CP949 conversion of ESP/MRK/TOP/CEL is required.\n\nEnable this data directory after the base Morrowind Data Files directory.\n"""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-zip", required=True, type=Path,
                        help="Existing Morrowind-Korean-OpenMW-*-Full.zip")
    parser.add_argument("--output", required=True, type=Path,
                        help="Output Android ReTranslation ZIP")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.base_zip.is_file():
        print(f"ERROR: base ZIP not found: {args.base_zip}", file=sys.stderr)
        return 2

    with zipfile.ZipFile(args.base_zip, "r") as src:
        names = src.namelist()
        mod_entries = [n for n in names if n.startswith(MOD_PREFIX) and not n.endswith("/")]
        if not mod_entries:
            print(f"ERROR: no {MOD_PREFIX} files found in {args.base_zip}", file=sys.stderr)
            return 3
        if SOURCE_TTF not in names:
            print(f"ERROR: source TTF is missing from base ZIP: {SOURCE_TTF}", file=sys.stderr)
            return 4

        ttf_data = src.read(SOURCE_TTF)
        if len(ttf_data) < 1024:
            print("ERROR: source TTF is unexpectedly small", file=sys.stderr)
            return 5

        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            args.output.unlink()

        copied = 0
        with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst:
            for name in mod_entries:
                # Replace only our dedicated font payload if rebuilding a package.
                if name in {TARGET_TTF, TARGET_OMWFONT}:
                    continue
                dst.writestr(name, src.read(name))
                copied += 1

            dst.writestr(TARGET_TTF, ttf_data)
            dst.writestr(TARGET_OMWFONT, OMWFONT_XML.encode("utf-8"))
            dst.writestr(README_ENTRY, README_TEXT.encode("utf-8"))

    with zipfile.ZipFile(args.output, "r") as check:
        required = {
            TARGET_TTF,
            TARGET_OMWFONT,
            MOD_PREFIX + "Morrowind_Korean_ReTranslation.esp",
        }
        missing = sorted(required.difference(check.namelist()))
        if missing:
            print("ERROR: output validation failed; missing:", file=sys.stderr)
            for name in missing:
                print(f"  {name}", file=sys.stderr)
            return 6

        output_ttf = check.read(TARGET_TTF)
        if output_ttf != ttf_data:
            print("ERROR: TTF changed during packaging", file=sys.stderr)
            return 7

    print(f"OK: {args.output}")
    print(f"  copied mod files: {copied}")
    print(f"  font: {TARGET_OMWFONT} -> Galmuri11.ttf")
    print(f"  TTF SHA-256: {sha256(ttf_data)}")
    print("  text encoding: unchanged UTF-8 translation payload")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
