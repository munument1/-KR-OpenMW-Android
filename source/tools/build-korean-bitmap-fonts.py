#!/usr/bin/env python3
"""Build collision-free OpenMW Korean CP949-layout FNT/TEX fonts.

No font binary is bundled or downloaded. The builder reads the user's original
Morrowind FNT/TEX files plus a user-supplied Korean TTF and emits three KR_*
font pairs for the OPENMW_ANDROID_051_KOREAN_CP949_BITMAP FontLoader patch.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ATLAS_W = ATLAS_H = 2048
GRID_Y = 512
CELL_W, CELL_H = 8, 11
LEADS = range(0x81, 0xFE)
TRAILS = tuple(range(0x41, 0x5B)) + tuple(range(0x61, 0x7B)) + tuple(range(0x81, 0xFF))
FNT_HEADER = 12 + 284
FNT_TEX_NAME_BYTES = 284
GLYPH_SIZE = 14 * 4
EXPECTED_FNT_SIZE = FNT_HEADER + 256 * GLYPH_SIZE

# Original source FNT -> collision-free runtime basename.
FONT_JOBS = (
    ("Magic_Cards_Regular.fnt", "KR_magic_cards_regular"),
    ("century_gothic_font_regular.fnt", "KR_century_gothic_font_regular"),
    ("daedric_font.fnt", "KR_daedric_font"),
)

SELECTION_ALIASES = {
    "magic_cards_regular": "KR_magic_cards_regular",
    "MysticCards": "KR_magic_cards_regular",
    "century_gothic_font_regular": "KR_century_gothic_font_regular",
    "daedric_font": "KR_daedric_font",
    "DemonicLetters": "KR_daedric_font",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def find_ci(directory: Path, name: str) -> Path | None:
    exact = directory / name
    if exact.is_file():
        return exact
    folded = name.casefold()
    for p in directory.iterdir():
        if p.is_file() and p.name.casefold() == folded:
            return p
    return None


def internal_tex_name(fnt: bytes) -> str:
    if len(fnt) != EXPECTED_FNT_SIZE:
        raise ValueError(f"unexpected FNT size: {len(fnt)}")
    _, a, b = struct.unpack_from("<fii", fnt, 0)
    if (a, b) != (1, 1):
        raise ValueError(f"unexpected FNT markers: {a}, {b}")
    return fnt[12:296].split(b"\0", 1)[0].decode("ascii")


def read_tex(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if len(data) < 8:
        raise ValueError(f"TEX too small: {path}")
    w, h = struct.unpack_from("<ii", data, 0)
    if len(data) != 8 + w * h * 4:
        raise ValueError(f"bad TEX size: {path}")
    return w, h, data[8:]


def patch_fnt(fnt: bytes, old_w: int, old_h: int, new_tex_name: str) -> bytes:
    encoded_name = new_tex_name.encode("ascii")
    if len(encoded_name) >= FNT_TEX_NAME_BYTES:
        raise ValueError(f"FNT TEX name is too long: {new_tex_name}")

    out = bytearray(fnt)
    out[12:296] = encoded_name + b"\0" * (FNT_TEX_NAME_BYTES - len(encoded_name))

    sx, sy = old_w / ATLAS_W, old_h / ATLAS_H
    for glyph in range(256):
        off = FNT_HEADER + glyph * GLYPH_SIZE
        values = list(struct.unpack_from("<14f", out, off))
        for i in (1, 3, 5, 7):
            values[i] *= sx
        for i in (2, 4, 6, 8):
            values[i] *= sy
        struct.pack_into("<14f", out, off, *values)

    # Slot 0xFF identifies the Korean compatibility atlas to the patched OpenMW loader.
    template = (
        0.0,
        0.0, GRID_Y / ATLAS_H,
        CELL_W / ATLAS_W, GRID_Y / ATLAS_H,
        0.0, (GRID_Y + CELL_H) / ATLAS_H,
        CELL_W / ATLAS_W, (GRID_Y + CELL_H) / ATLAS_H,
        float(CELL_W), float(CELL_H), 0.0, 0.0, float(CELL_H),
    )
    struct.pack_into("<14f", out, FNT_HEADER + 0xFF * GLYPH_SIZE, *template)
    return bytes(out)


def cmap_codepoints(ttf: Path) -> set[int]:
    font = TTFont(str(ttf), lazy=True)
    try:
        out: set[int] = set()
        for table in font["cmap"].tables:
            if table.isUnicode():
                out.update(table.cmap.keys())
        return out
    finally:
        font.close()


def build_cp949_layer(ttf: Path, size: int) -> tuple[Image.Image, dict]:
    font = ImageFont.truetype(str(ttf), size)
    cmap = cmap_codepoints(ttf)
    layer = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
    stats = {"rendered": 0, "hangul": 0, "other": 0, "codec_invalid": 0, "missing_in_ttf": 0}

    for row, lead in enumerate(LEADS):
        y = GRID_Y + row * CELL_H
        for col, trail in enumerate(TRAILS):
            try:
                ch = bytes((lead, trail)).decode("cp949")
            except UnicodeDecodeError:
                stats["codec_invalid"] += 1
                continue
            if len(ch) != 1 or ord(ch) not in cmap:
                stats["missing_in_ttf"] += 1
                continue
            cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            ImageDraw.Draw(cell).text((0, 0), ch, font=font, fill=(255, 255, 255, 255))
            layer.alpha_composite(cell, (col * CELL_W, y))
            stats["rendered"] += 1
            if 0xAC00 <= ord(ch) <= 0xD7A3:
                stats["hangul"] += 1
            else:
                stats["other"] += 1
    return layer, stats


def sample_check(layer: Image.Image) -> dict:
    alpha = layer.getchannel("A")
    checks = {}
    for ch, lead, trail in (("가", 0xB0, 0xA1), ("한", 0xC7, 0xD1), ("힝", 0xC8, 0xFE)):
        row = lead - 0x81
        col = TRAILS.index(trail)
        x, y = col * CELL_W, GRID_Y + row * CELL_H
        checks[ch] = {"x": x, "y": y, "nonempty": alpha.crop((x, y, x + CELL_W, y + CELL_H)).getbbox() is not None}
    return checks


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the complete Korean CP949-layout OpenMW bitmap-font set.")
    ap.add_argument("--vanilla-fonts", type=Path, required=True, help="Original Morrowind Data Files/Fonts directory")
    ap.add_argument("--ttf", type=Path, required=True, help="User-supplied Korean TTF (for example Galmuri11.ttf)")
    ap.add_argument("--output", type=Path, required=True, help="Output root; fonts/ will be created below it")
    ap.add_argument("--font-size", type=int, default=11)
    ap.add_argument("--overwrite", action="store_true")
    args = ap.parse_args()

    src = args.vanilla_fonts.resolve()
    ttf = args.ttf.resolve()
    root = args.output.resolve()
    out_dir = root / "fonts"
    if not src.is_dir():
        raise SystemExit(f"font directory not found: {src}")
    if not ttf.is_file():
        raise SystemExit(f"TTF not found: {ttf}")
    if root.exists():
        if not args.overwrite:
            raise SystemExit(f"output exists; add --overwrite: {root}")
        shutil.rmtree(root)
    out_dir.mkdir(parents=True)

    layer, stats = build_cp949_layer(ttf, args.font_size)
    samples = sample_check(layer)
    if stats["hangul"] != 11172 or not all(v["nonempty"] for v in samples.values()):
        raise SystemExit(f"TTF does not provide/render complete modern Hangul: hangul={stats['hangul']} samples={samples}")

    manifest = {
        "format": "OPENMW_ANDROID_051_KOREAN_CP949_BITMAP",
        "atlas": {"size": [ATLAS_W, ATLAS_H], "grid_y": GRID_Y, "cell": [CELL_W, CELL_H]},
        "ttf": {"filename": ttf.name, "sha256": sha256(ttf), "font_size": args.font_size},
        "render": stats,
        "samples": samples,
        "selection_aliases": SELECTION_ALIASES,
        "files": {},
    }

    for source_fnt_name, target_base in FONT_JOBS:
        src_fnt = find_ci(src, source_fnt_name)
        if src_fnt is None:
            raise SystemExit(f"missing vanilla FNT: {source_fnt_name}")
        raw_fnt = src_fnt.read_bytes()
        source_tex_base = internal_tex_name(raw_fnt)
        src_tex = find_ci(src, source_tex_base + ".tex")
        if src_tex is None:
            raise SystemExit(f"missing TEX referenced by {source_fnt_name}: {source_tex_base}.tex")
        old_w, old_h, old_pixels = read_tex(src_tex)
        if old_w > ATLAS_W or old_h > GRID_Y:
            raise SystemExit(f"unsupported source atlas size {old_w}x{old_h}: {src_tex.name}")

        atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
        atlas.alpha_composite(Image.frombytes("RGBA", (old_w, old_h), old_pixels), (0, 0))
        atlas.alpha_composite(layer, (0, 0))

        patched_fnt = patch_fnt(raw_fnt, old_w, old_h, target_base)
        if internal_tex_name(patched_fnt) != target_base:
            raise SystemExit(f"failed to rewrite FNT internal TEX name: {target_base}")

        out_fnt = out_dir / (target_base + ".fnt")
        out_fnt.write_bytes(patched_fnt)
        manifest["files"][str(out_fnt.relative_to(root))] = {
            "sha256": sha256(out_fnt),
            "size": out_fnt.stat().st_size,
            "source": src_fnt.name,
            "source_tex": src_tex.name,
            "internal_tex": target_base,
        }

        out_tex = out_dir / (target_base + ".tex")
        out_tex.write_bytes(struct.pack("<ii", ATLAS_W, ATLAS_H) + atlas.tobytes())
        manifest["files"][str(out_tex.relative_to(root))] = {
            "sha256": sha256(out_tex),
            "size": out_tex.stat().st_size,
            "source": src_tex.name,
        }

    expected_files = {
        "fonts/KR_magic_cards_regular.fnt",
        "fonts/KR_magic_cards_regular.tex",
        "fonts/KR_century_gothic_font_regular.fnt",
        "fonts/KR_century_gothic_font_regular.tex",
        "fonts/KR_daedric_font.fnt",
        "fonts/KR_daedric_font.tex",
    }
    actual_files = set(manifest["files"])
    if actual_files != expected_files:
        raise SystemExit(
            f"complete collision-free font set mismatch: missing={sorted(expected_files - actual_files)} "
            f"unexpected={sorted(actual_files - expected_files)}"
        )

    manifest_path = root / "korean_bitmap_font_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("PASS OPENMW_ANDROID_051_KOREAN_CP949_BITMAP font build")
    print("PASS collision-free KR_* FNT/TEX names")
    print(f"Modern Hangul cells: {stats['hangul']}")
    print(f"Output: {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
