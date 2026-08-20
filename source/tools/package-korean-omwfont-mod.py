#!/usr/bin/env python3
"""Assemble the Android OpenMW Korean translation mod.

Internal release/CI tool. It accepts an existing Korean translation release ZIP,
finds the ReTranslation ESP regardless of the archive's outer directory layout,
keeps the UTF-8 translation payload, drops legacy bitmap fonts, and adds the
validated MysticCards OpenMW TrueType font payload supplied by CI.
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
CORE_SIDECARS = {
    "Morrowind_Korean_ReTranslation.esp",
    "Morrowind_Korean_ReTranslation.mrk",
    "Morrowind_Korean_ReTranslation.top",
    "Morrowind_Korean_ReTranslation.cel",
}
UTF8_BOM_SIDECARS = {".cel", ".mrk", ".top"}
TARGET_OMWFONT = FONT_PREFIX + "MysticCards.omwfont"
TARGET_TTF = FONT_PREFIX + "Galmuri11.ttf"
TARGET_LICENSE = FONT_PREFIX + "Galmuri11-OFL-1.1.md"
README_ENTRY = "README-ANDROID-KR-OMWFONT.txt"
EXPECTED_GALMURI11_SHA256 = "e24256f42e43713d2ea086a1e1669d78b968f5b3cc547e5c157f0606ffa5def1"

README_TEXT = """Morrowind Korean ReTranslation - Android OpenMW package

For the KR OpenMW Android build using the validated Korean font slot:
  fallback=Fonts_Font_0,MysticCards
  fallback=Fonts_Font_2,MysticCards

Fonts/MysticCards.omwfont uses Galmuri11.ttf through OpenMW's native TrueType
path. Translation ESP/MRK/TOP/CEL/l10n data remains UTF-8; do not convert the
translation payload to CP949.

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
        if name.endswith("/"):
            continue
        p = PurePosixPath(name)
        if p.name != ESP_NAME:
            continue
        parent = p.parent.as_posix()
        candidates.add("" if parent == "." else parent.rstrip("/") + "/")

    if not candidates:
        raise ValueError(f"could not locate {ESP_NAME} in release ZIP")

    if TARGET_PREFIX in candidates:
        return TARGET_PREFIX

    named = sorted(p for p in candidates if "Morrowind_Korean_ReTranslation" in p)
    if len(named) == 1:
        return named[0]
    if len(candidates) == 1:
        return next(iter(candidates))

    raise ValueError(f"multiple possible ReTranslation roots found: {sorted(candidates)}")


def should_copy_translation(relative: str) -> bool:
    p = PurePosixPath(relative)
    if not p.parts:
        return False
    if len(p.parts) == 1 and p.name in CORE_SIDECARS:
        return True
    if p.parts[0].lower() == "l10n":
        return True
    return False


def validate_translation_payload(relative: str, data: bytes) -> None:
    p = PurePosixPath(relative)
    if p.suffix.lower() in UTF8_BOM_SIDECARS:
        if not data.startswith(b"\xef\xbb\xbf"):
            raise ValueError(f"UTF-8 BOM is missing from sidecar: {relative}")
        try:
            data[3:].decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError(f"sidecar is not valid UTF-8: {relative}: {exc}") from exc
    elif p.parts and p.parts[0].lower() == "l10n":
        try:
            data.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise ValueError(f"l10n file is not valid UTF-8: {relative}: {exc}") from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-zip", required=True, type=Path,
                        help="Existing Korean translation release ZIP")
    parser.add_argument("--omwfont", required=True, type=Path,
                        help="Validated MysticCards.omwfont descriptor")
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

        required_source = {source_prefix + name for name in CORE_SIDECARS}
        missing_source = sorted(required_source.difference(names))
        if missing_source:
            print("ERROR: current translation payload is incomplete; missing:", file=sys.stderr)
            for name in missing_source:
                print(f"  {name}", file=sys.stderr)
            return 7

        translation_payload: list[tuple[str, bytes]] = []
        try:
            for name in names:
                if name.endswith("/") or not name.startswith(source_prefix):
                    continue
                relative = name[len(source_prefix):]
                if not should_copy_translation(relative):
                    continue
                data = src.read(name)
                validate_translation_payload(relative, data)
                translation_payload.append((relative, data))
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 8

        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            args.output.unlink()

        copied = 0
        copied_relatives: list[str] = []
        with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst:
            for relative, data in translation_payload:
                dst.writestr(TARGET_PREFIX + relative, data)
                copied += 1
                copied_relatives.append(relative)

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
            return 9

        if check.read(TARGET_OMWFONT) != omwfont_data:
            print("ERROR: omwfont changed during packaging", file=sys.stderr)
            return 10
        if sha256(check.read(TARGET_TTF)) != EXPECTED_GALMURI11_SHA256:
            print("ERROR: packaged TTF hash mismatch", file=sys.stderr)
            return 11

        legacy_fonts = [
            n for n in check.namelist()
            if n.lower().endswith((".fnt", ".tex"))
        ]
        if legacy_fonts:
            print(f"ERROR: legacy bitmap fonts leaked into package: {legacy_fonts}", file=sys.stderr)
            return 12

    print(f"OK: {args.output}")
    print(f"  source mod root: {source_prefix or '<zip-root>'}")
    print(f"  copied translation files: {copied}")
    print(f"  copied payload: {', '.join(copied_relatives)}")
    print(f"  Galmuri11.ttf SHA-256: {ttf_sha}")
    print("  OpenMW font slot: MysticCards")
    print("  legacy FNT/TEX payload: none")
    print("  translation encoding: unchanged UTF-8 payload")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
