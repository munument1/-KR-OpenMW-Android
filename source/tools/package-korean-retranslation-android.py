#!/usr/bin/env python3
"""Build the OpenMW Android Korean ReTranslation mod with the existing CP949 FNT/TEX release.

The translation data stays UTF-8. The CP949 aspect is only the bitmap atlas layout.
No font binary is embedded in this script or in the Android APK source tree.
"""
from __future__ import annotations

import argparse
import hashlib
import shutil
import struct
import tempfile
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

FONT_RELEASE_TAG = "v1.0.7-rc6-classic-cp949-pre1"
FONT_ASSET_NAME = "Morrowind_CP949_Classic_Fonts.zip"
FONT_ASSET_SHA256 = "3a7d2442d43d7ed9e0b42d6d8d75068340b00893e06bb2fa696d4ac440bbeee7"
FONT_ASSET_URL = (
    "https://github.com/munument1/Morrowind-CP949/releases/download/"
    f"{FONT_RELEASE_TAG}/{FONT_ASSET_NAME}"
)

MOD_PREFIX = "mods/Morrowind_Korean_ReTranslation/"
FONT_DEST_PREFIX = MOD_PREFIX + "Fonts/"
FNT_HEADER = 12 + 284
GLYPH_SIZE = 14 * 4
EXPECTED_FNT_SIZE = FNT_HEADER + 256 * GLYPH_SIZE
EXPECTED_ATLAS = (2048, 2048)
GRID_Y = 512
CELL_W = 8
CELL_H = 11

# Classic release source FNT -> OpenMW Android output FNT names.
# Do not emit Magic_Cards_Regular.fnt in addition to magic_cards_regular.fnt:
# they collide on case-insensitive filesystems and are byte-identical.
FNT_OUTPUTS = {
    "magic_cards_regular.fnt": ("magic_cards_regular.fnt", "MysticCards.fnt"),
    "century_gothic_big.fnt": ("century_gothic_big.fnt",),
    "century_gothic_font_regular.fnt": ("century_gothic_font_regular.fnt",),
    "daedric_font.fnt": ("daedric_font.fnt", "DemonicLetters.fnt"),
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def normalized_zip_name(name: str) -> str:
    return name.replace("\\", "/").lstrip("/")


def download_font_pack(dest: Path) -> None:
    print(f"Downloading verified font pack: {FONT_ASSET_URL}")
    req = urllib.request.Request(FONT_ASSET_URL, headers={"User-Agent": "KR-OpenMW-Android-font-packager/1"})
    with urllib.request.urlopen(req, timeout=120) as response, dest.open("wb") as out:
        shutil.copyfileobj(response, out)


def verify_font_pack_archive(path: Path) -> None:
    actual = sha256_file(path)
    if actual.lower() != FONT_ASSET_SHA256:
        raise RuntimeError(
            "font pack SHA-256 mismatch\n"
            f" expected: {FONT_ASSET_SHA256}\n"
            f" actual:   {actual}\n"
            f" file:     {path}"
        )


def find_fonts_in_archive(zf: zipfile.ZipFile) -> dict[str, bytes]:
    found: dict[str, bytes] = {}
    for info in zf.infolist():
        if info.is_dir():
            continue
        name = normalized_zip_name(info.filename)
        parts = PurePosixPath(name).parts
        lower = [p.casefold() for p in parts]
        try:
            idx = lower.index("fonts")
        except ValueError:
            continue
        if idx == 0:
            rel_parts = parts[1:]
        elif idx >= 1 and lower[idx - 1] == "data files":
            rel_parts = parts[idx + 1 :]
        else:
            continue
        if len(rel_parts) != 1:
            continue
        basename = rel_parts[0]
        if Path(basename).suffix.casefold() not in {".fnt", ".tex"}:
            continue
        key = basename.casefold()
        if key in found:
            raise RuntimeError(f"duplicate font basename in release archive: {basename}")
        found[key] = zf.read(info)
    return found


def parse_fnt_internal_tex(fnt: bytes) -> str:
    if len(fnt) != EXPECTED_FNT_SIZE:
        raise RuntimeError(f"unexpected FNT size: {len(fnt)} (expected {EXPECTED_FNT_SIZE})")
    _, a, b = struct.unpack_from("<fii", fnt, 0)
    if (a, b) != (1, 1):
        raise RuntimeError(f"unexpected FNT markers: {(a, b)}")
    raw = fnt[12:296].split(b"\0", 1)[0]
    try:
        return raw.decode("ascii")
    except UnicodeDecodeError as exc:
        raise RuntimeError("FNT internal TEX name is not ASCII") from exc


def validate_cp949_fnt(fnt: bytes, label: str) -> str:
    internal_tex = parse_fnt_internal_tex(fnt)
    off = FNT_HEADER + 0xFF * GLYPH_SIZE
    values = struct.unpack_from("<14f", fnt, off)
    expected = {
        "u0": 0.0,
        "v0": GRID_Y / EXPECTED_ATLAS[1],
        "width": float(CELL_W),
        "height": float(CELL_H),
    }
    actual = {
        "u0": values[1],
        "v0": values[2],
        "width": values[9],
        "height": values[10],
    }
    for key, wanted in expected.items():
        if abs(actual[key] - wanted) > 0.0005:
            raise RuntimeError(
                f"{label}: slot 0xFF is not the expected Korean CP949 bitmap template: "
                f"{key}={actual[key]} expected={wanted}"
            )
    return internal_tex


def validate_tex(tex: bytes, label: str) -> None:
    if len(tex) < 8:
        raise RuntimeError(f"{label}: TEX too small")
    width, height = struct.unpack_from("<ii", tex, 0)
    if (width, height) != EXPECTED_ATLAS:
        raise RuntimeError(f"{label}: expected 2048x2048 atlas, got {width}x{height}")
    expected_size = 8 + width * height * 4
    if len(tex) != expected_size:
        raise RuntimeError(f"{label}: bad TEX byte size {len(tex)} expected {expected_size}")


def build_font_payload(font_pack: Path) -> tuple[dict[str, bytes], list[str]]:
    with zipfile.ZipFile(font_pack) as zf:
        available = find_fonts_in_archive(zf)

    payload: dict[str, bytes] = {}
    report: list[str] = []
    for source_key, output_names in FNT_OUTPUTS.items():
        source = available.get(source_key)
        if source is None:
            raise RuntimeError(f"font release is missing required FNT: {source_key}")
        internal_tex = validate_cp949_fnt(source, source_key)
        tex_key = (internal_tex + ".tex").casefold()
        tex = available.get(tex_key)
        if tex is None:
            raise RuntimeError(
                f"font release is missing TEX referenced by {source_key}: {internal_tex}.tex"
            )
        validate_tex(tex, internal_tex + ".tex")

        for output_name in output_names:
            payload[output_name] = source
        tex_name = internal_tex + ".tex"
        if tex_name in payload and payload[tex_name] != tex:
            raise RuntimeError(f"conflicting TEX output name: {tex_name}")
        payload[tex_name] = tex
        report.append(f"{source_key} -> {', '.join(output_names)} -> {tex_name}")

    required_fnts = {
        "MysticCards.fnt",
        "magic_cards_regular.fnt",
        "DemonicLetters.fnt",
        "daedric_font.fnt",
        "century_gothic_font_regular.fnt",
        "century_gothic_big.fnt",
    }
    missing = sorted(required_fnts.difference(payload))
    if missing:
        raise RuntimeError(f"font payload missing runtime aliases: {missing}")
    if payload["MysticCards.fnt"] != payload["magic_cards_regular.fnt"]:
        raise RuntimeError("MysticCards and magic_cards_regular aliases are not byte-identical")
    if payload["DemonicLetters.fnt"] != payload["daedric_font.fnt"]:
        raise RuntimeError("DemonicLetters and daedric_font aliases are not byte-identical")
    return payload, report


def build_mod_zip(base_zip: Path, font_pack: Path, output: Path) -> None:
    verify_font_pack_archive(font_pack)
    font_payload, report = build_font_payload(font_pack)

    with zipfile.ZipFile(base_zip) as src:
        names = [normalized_zip_name(i.filename) for i in src.infolist()]
        if MOD_PREFIX + "Morrowind_Korean_ReTranslation.esp" not in names:
            raise RuntimeError(
                f"base patch ZIP does not contain {MOD_PREFIX}Morrowind_Korean_ReTranslation.esp"
            )

        output.parent.mkdir(parents=True, exist_ok=True)
        tmp_output = output.with_suffix(output.suffix + ".tmp")
        if tmp_output.exists():
            tmp_output.unlink()
        with zipfile.ZipFile(tmp_output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst:
            # Android mod-only package: copy the ReTranslation mod, not the Windows OpenMW runtime/cfg.
            for info in src.infolist():
                name = normalized_zip_name(info.filename)
                if not name.startswith(MOD_PREFIX):
                    continue
                if name.startswith(FONT_DEST_PREFIX):
                    continue
                if info.is_dir():
                    dst.writestr(name, b"")
                else:
                    dst.writestr(name, src.read(info))

            dst.writestr(FONT_DEST_PREFIX, b"")
            for basename in sorted(font_payload, key=str.casefold):
                dst.writestr(FONT_DEST_PREFIX + basename, font_payload[basename])

            manifest_lines = [
                "OpenMW Android Korean bitmap font payload",
                f"source-release-tag={FONT_RELEASE_TAG}",
                f"source-asset={FONT_ASSET_NAME}",
                f"source-asset-sha256={FONT_ASSET_SHA256}",
                "translation-encoding=UTF-8 (unchanged)",
                "font-atlas-layout=CP949 DBCS 2048x2048, grid y=512, cell 8x11",
                "required-apk-marker=OPENMW_ANDROID_051_KOREAN_CP949_BITMAP",
                "",
                "FNT routing:",
                *report,
                "",
                "Files:",
            ]
            for basename in sorted(font_payload, key=str.casefold):
                data = font_payload[basename]
                manifest_lines.append(f"{sha256_bytes(data)}  Fonts/{basename}  {len(data)} bytes")
            dst.writestr(
                MOD_PREFIX + "ANDROID-FNT-MANIFEST.txt",
                ("\n".join(manifest_lines) + "\n").encode("utf-8"),
            )

        tmp_output.replace(output)

    print("PASS OpenMW Android Korean ReTranslation mod package")
    print(f"Base patch: {base_zip}")
    print(f"Font asset: {font_pack} ({FONT_ASSET_SHA256})")
    print(f"Output: {output}")
    print(f"Output SHA-256: {sha256_file(output)}")
    print("Translation files remain UTF-8; only the bitmap atlas uses the CP949 layout.")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Merge the verified Morrowind-CP949 release fonts into the OpenMW Android ReTranslation mod."
    )
    ap.add_argument(
        "--base-zip",
        type=Path,
        required=True,
        help="KR1/full patch ZIP containing mods/Morrowind_Korean_ReTranslation",
    )
    ap.add_argument("--output", type=Path, required=True, help="Output Android mod ZIP")
    ap.add_argument(
        "--font-pack",
        type=Path,
        help="Optional local Morrowind_CP949_Classic_Fonts.zip; if omitted, download the verified release asset",
    )
    args = ap.parse_args()

    base_zip = args.base_zip.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not base_zip.is_file():
        raise SystemExit(f"base ZIP not found: {base_zip}")

    try:
        if args.font_pack:
            font_pack = args.font_pack.expanduser().resolve()
            if not font_pack.is_file():
                raise RuntimeError(f"font pack not found: {font_pack}")
            build_mod_zip(base_zip, font_pack, output)
        else:
            with tempfile.TemporaryDirectory(prefix="morrowind-cp949-fonts-") as td:
                font_pack = Path(td) / FONT_ASSET_NAME
                download_font_pack(font_pack)
                build_mod_zip(base_zip, font_pack, output)
    except Exception as exc:
        print(f"ERROR: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
