#!/usr/bin/env python3
"""Build the Android OpenMW Korean translation mod from an existing KR1 full ZIP.

The script does not create or download a new font descriptor. It reuses the
existing KR1 MysticCards.omwfont and Galmuri11.ttf verbatim, renaming only the
.omwfont basename in the output to avoid collisions with legacy .fnt files.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

MOD_PREFIX = "mods/Morrowind_Korean_ReTranslation/"
FONT_DIR = MOD_PREFIX + "Fonts/"
SOURCE_OMWFONT = "OpenMW/resources/vfs/fonts/MysticCards.omwfont"
SOURCE_TTF = "OpenMW/resources/vfs/fonts/Galmuri11.ttf"
TARGET_OMWFONT = FONT_DIR + "KR_OpenMW_Korean.omwfont"
TARGET_TTF = FONT_DIR + "Galmuri11.ttf"
README_ENTRY = "README-ANDROID-KR-OMWFONT.txt"

README_TEXT = """Morrowind Korean ReTranslation - Android OpenMW font test

This package is intended for the KR OpenMW Android build that selects:
  fallback=Fonts_Font_0,KR_OpenMW_Korean
  fallback=Fonts_Font_2,KR_OpenMW_Korean

KR_OpenMW_Korean.omwfont is the existing KR1 MysticCards.omwfont copied
verbatim under a unique basename so a same-name legacy .fnt cannot win OpenMW's
font lookup. Galmuri11.ttf is also copied verbatim from the same KR1 package.

Translation data remains UTF-8. No CP949 conversion of ESP/MRK/TOP/CEL is
required. Enable this data directory after the base Morrowind Data Files.
"""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_existing_descriptor(data: bytes) -> None:
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise ValueError(f"invalid existing omwfont XML: {exc}") from exc

    source_values = {
        p.attrib.get("value")
        for p in root.findall(".//Property")
        if p.attrib.get("key") == "Source"
    }
    if "Galmuri11.ttf" not in source_values:
        raise ValueError("existing omwfont does not reference Galmuri11.ttf")

    ranges = {code.attrib.get("range") for code in root.findall(".//Code")}
    if "33 65535" not in ranges:
        raise ValueError("existing omwfont does not expose the expected 33..65535 range")


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

        for required_source in (SOURCE_OMWFONT, SOURCE_TTF):
            if required_source not in names:
                print(f"ERROR: source font file is missing: {required_source}", file=sys.stderr)
                return 4

        omwfont_data = src.read(SOURCE_OMWFONT)
        ttf_data = src.read(SOURCE_TTF)
        try:
            validate_existing_descriptor(omwfont_data)
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 5
        if len(ttf_data) < 1024:
            print("ERROR: source TTF is unexpectedly small", file=sys.stderr)
            return 6

        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            args.output.unlink()

        copied = 0
        with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst:
            for name in mod_entries:
                if name in {TARGET_TTF, TARGET_OMWFONT}:
                    continue
                dst.writestr(name, src.read(name))
                copied += 1

            dst.writestr(TARGET_TTF, ttf_data)
            dst.writestr(TARGET_OMWFONT, omwfont_data)
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
            return 7

        if check.read(TARGET_TTF) != ttf_data:
            print("ERROR: TTF changed during packaging", file=sys.stderr)
            return 8
        if check.read(TARGET_OMWFONT) != omwfont_data:
            print("ERROR: existing omwfont changed during packaging", file=sys.stderr)
            return 9

    print(f"OK: {args.output}")
    print(f"  copied mod files: {copied}")
    print(f"  reused descriptor: {SOURCE_OMWFONT} -> {TARGET_OMWFONT}")
    print(f"  OMWFONT SHA-256: {sha256(omwfont_data)}")
    print(f"  TTF SHA-256: {sha256(ttf_data)}")
    print("  text encoding: unchanged UTF-8 translation payload")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
