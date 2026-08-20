#!/usr/bin/env python3
"""Assemble the Android OpenMW Korean translation mod.

This is an internal release/CI tool. It takes an existing Korean translation
release ZIP, strips any legacy Fonts payload, normalizes the active mod folder,
and adds the dedicated OpenMW TrueType font payload supplied by CI.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath

TARGET_PREFIX = "mods/Morrowind_Korean_ReTranslation/"
FONT_PREFIX = TARGET_PREFIX + "Fonts/"
ESP_NAME = "Morrowind_Korean_ReTranslation.esp"
TARGET_OMWFONT = FONT_PREFIX + "KR_OpenMW_Korean.omwfont"
TARGET_TTF = FONT_PREFIX + "Galmuri11.ttf"
TARGET_LICENSE = FONT_PREFIX + "Galmuri11-OFL-1.1.md"
README_ENTRY = "README-ANDROID-KR-OMWFONT.txt"
EXPECTED_GALMURI11_SHA256 = "e24256f42e43713d2ea086a1e1669d78b968f5b3cc547e5c157f0606ffa5def1"

README_TEXT = """Morrowind Korean ReTranslation - Android OpenMW package

For the KR OpenMW Android build using:
  fallback=Fonts_Font_0,KR_OpenMW_Korean
  fallback=Fonts_Font_2,KR_OpenMW_Korean

Fonts/KR_OpenMW_Korean.omwfont uses Galmuri11.ttf through OpenMW's native
TrueType path. Translation ESP/MRK/TOP/CEL/l10n data remains UTF-8; do not
convert the translation payload to CP949.

Galmuri11.ttf is redistributed under SIL Open Font License 1.1. The license
text is included next to the font as Galmuri11-OFL-1.1.md.
"""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_descriptor(data: bytes) -> None:
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise ValueError(f"invalid omwfont XML: {exc}") from exc

    source_values = {
        p.attrib.get("value")
        for p in root.findall(".//Property")
        if p.attrib.get("key") == "Source"
    }
    if "Galmuri11.ttf" not in source_values:
        raise ValueError("omwfont does not reference Galmuri11.ttf")

    ranges = {code.attrib.get("range") for code in root.findall(".//Code")}
    if "33 65535" not in ranges:
        raise ValueError("omwfont does not expose the expected 33..65535 range")


def find_mod_prefix(names: list[str]) -> str:
    candidates: set[str] = set()
    for name in names:
        p = PurePosixPath(name)
        parts = p.parts
        if len(parts) >= 3 and parts[0].lower() == "mods" and parts[-1] == ESP_NAME:
            candidates.add("/".join(parts[:-1]) + "/")

    exact = TARGET_PREFIX
    if exact in candidates:
        return exact

    named = sorted(p for p in candidates if "Morrowind_Korean_ReTranslation" in p)
    if len(named) == 1:
        return named[0]
    if not named:
        raise ValueError("could not locate a ReTranslation mod folder containing the ESP")
    raise ValueError(f"multiple ReTranslation mod folders found: {named}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-zip", required=True, type=Path,
                        help="Existing Korean translation release ZIP")
    parser.add_argument("--omwfont", required=True, type=Path,
                        help="Dedicated KR_OpenMW_Korean.omwfont descriptor")
    parser.add_argument("--ttf", required=True, type=Path,
                        help="Pinned Galmuri11.ttf")
    parser.add_argument("--font-license", required=True, type=Path,
                        help="Galmuri OFL-1.1 license text")
    parser.add_argument("--output", required=True, type=Path,
                        help="Output Android ReTranslation ZIP")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    for path in (args.base_zip, args.omwfont, args.ttf, args.font_license):
        if not path.is_file():
            print(f"ERROR: input file not found: {path}", file=sys.stderr)
            return 2

    omwfont_data = args.omwfont.read_bytes()
    ttf_data = args.ttf.read_bytes()
    license_data = args.font_license.read_bytes()

    try:
        validate_descriptor(omwfont_data)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 3

    ttf_sha = sha256(ttf_data)
    if ttf_sha != EXPECTED_GALMURI11_SHA256:
        print(
            f"ERROR: Galmuri11.ttf SHA-256 mismatch: {ttf_sha} != {EXPECTED_GALMURI11_SHA256}",
            file=sys.stderr,
        )
        return 4

    license_text = license_data.decode("utf-8", errors="replace").lower()
    if "sil open font license" not in license_text or "version 1.1" not in license_text:
        print("ERROR: supplied Galmuri license is not recognizable as OFL-1.1", file=sys.stderr)
        return 5

    with zipfile.ZipFile(args.base_zip, "r") as src:
        names = src.namelist()
        try:
            source_prefix = find_mod_prefix(names)
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 6

        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            args.output.unlink()

        copied = 0
        with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst:
            for name in names:
                if name.endswith("/") or not name.startswith(source_prefix):
                    continue
                relative = name[len(source_prefix):]
                if not relative or relative.lower().startswith("fonts/"):
                    continue
                dst.writestr(TARGET_PREFIX + relative, src.read(name))
                copied += 1

            dst.writestr(TARGET_OMWFONT, omwfont_data)
            dst.writestr(TARGET_TTF, ttf_data)
            dst.writestr(TARGET_LICENSE, license_data)
            dst.writestr(README_ENTRY, README_TEXT.encode("utf-8"))

    with zipfile.ZipFile(args.output, "r") as check:
        required = {
            TARGET_PREFIX + ESP_NAME,
            TARGET_OMWFONT,
            TARGET_TTF,
            TARGET_LICENSE,
        }
        missing = sorted(required.difference(check.namelist()))
        if missing:
            print("ERROR: output validation failed; missing:", file=sys.stderr)
            for name in missing:
                print(f"  {name}", file=sys.stderr)
            return 7

        if check.read(TARGET_OMWFONT) != omwfont_data:
            print("ERROR: omwfont changed during packaging", file=sys.stderr)
            return 8
        if sha256(check.read(TARGET_TTF)) != EXPECTED_GALMURI11_SHA256:
            print("ERROR: packaged TTF hash mismatch", file=sys.stderr)
            return 9

        legacy_fonts = [
            n for n in check.namelist()
            if n.startswith(FONT_PREFIX) and n.lower().endswith((".fnt", ".tex"))
        ]
        if legacy_fonts:
            print(f"ERROR: legacy bitmap fonts leaked into package: {legacy_fonts}", file=sys.stderr)
            return 10

    print(f"OK: {args.output}")
    print(f"  source mod folder: {source_prefix}")
    print(f"  copied translation files: {copied}")
    print(f"  Galmuri11.ttf SHA-256: {ttf_sha}")
    print("  legacy FNT/TEX payload: none")
    print("  translation encoding: unchanged UTF-8 payload")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
