#!/usr/bin/env python3
"""Assemble preview atlases from a baked sunwoven-villager frame tree.

Runtime still loads individual PNGs via the manifest. These sheets are for
human QA only: walk-atlas (clean 8×4), full labeled sprite-sheet, and a
¼-size preview.

Usage:
    python3 assemble_atlases.py \\
        --sprites ../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BG = (22, 26, 34, 255)
GUTTER = 72
PAD = 16
LABEL_COLOR = (180, 190, 205, 255)
TITLE_COLOR = (230, 235, 245, 255)


def font(size: int) -> ImageFont.ImageFont:
    for name in (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        try:
            return ImageFont.truetype(name, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def assemble_walk_atlas(root: Path, facings: list[str], frame_w: int, frame_h: int,
                        frames: int) -> Image.Image:
    sheet = Image.new("RGBA", (frames * frame_w, len(facings) * frame_h), (0, 0, 0, 0))
    for fi, _ in enumerate(facings):
        for fr in range(frames):
            cell = Image.open(root / "walk" / str(fi) / f"{fr}.png").convert("RGBA")
            sheet.alpha_composite(cell, (fr * frame_w, fi * frame_h))
    return sheet


def assemble_contact(root: Path, facings: list[str], frame_w: int, frame_h: int,
                     frames: int) -> Image.Image:
    label_font = font(18)
    sheet = Image.new(
        "RGBA",
        (GUTTER + frames * frame_w + PAD, len(facings) * frame_h + PAD),
        BG,
    )
    draw = ImageDraw.Draw(sheet)
    for fi, name in enumerate(facings):
        y = fi * frame_h
        draw.text((10, y + frame_h // 2 - 8), f"{fi} {name}", fill=LABEL_COLOR, font=label_font)
        for fr in range(frames):
            cell = Image.open(root / "walk" / str(fi) / f"{fr}.png").convert("RGBA")
            sheet.alpha_composite(cell, (GUTTER + fr * frame_w, y))
    return sheet


def assemble_full_sheet(root: Path, manifest: dict) -> Image.Image:
    frame_w = manifest["frameWidth"]
    frame_h = manifest["frameHeight"]
    facings = manifest["facings"]
    clips = list(manifest["clips"].items())
    # 2×2 clip grid
    max_frames = max(c["frames"] for _, c in clips)
    cell_w = GUTTER + max_frames * frame_w
    cell_h = 36 + len(facings) * frame_h
    cols, rows = 2, 2
    sheet = Image.new(
        "RGBA",
        (PAD + cols * cell_w + PAD, PAD + rows * cell_h + PAD),
        BG,
    )
    draw = ImageDraw.Draw(sheet)
    title_font = font(22)
    label_font = font(16)
    header = font(28)
    draw.text((PAD, 4), "sunwoven-villager — AoE2 sprite sheet", fill=TITLE_COLOR, font=header)

    for i, (clip_name, clip) in enumerate(clips):
        col, row = i % 2, i // 2
        ox = PAD + col * cell_w
        oy = PAD + 32 + row * cell_h
        n = clip["frames"]
        fps = clip.get("fps", manifest.get("fps", 10))
        draw.text(
            (ox + GUTTER, oy),
            f"{clip_name}  ·  {n} frames @ {fps} fps",
            fill=TITLE_COLOR,
            font=title_font,
        )
        body_y = oy + 28
        for fi, name in enumerate(facings):
            y = body_y + fi * frame_h
            draw.text((ox + 8, y + frame_h // 2 - 7), f"{fi} {name}",
                      fill=LABEL_COLOR, font=label_font)
            for fr in range(n):
                cell = Image.open(root / clip_name / str(fi) / f"{fr}.png").convert("RGBA")
                sheet.alpha_composite(cell, (ox + GUTTER + fr * frame_w, y))
    return sheet


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--sprites",
        default="../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager",
    )
    args = ap.parse_args()
    tool_root = Path(__file__).parent
    root = (tool_root / args.sprites).resolve()
    manifest = json.loads((root / "manifest.json").read_text())
    facings = manifest["facings"]
    fw, fh = manifest["frameWidth"], manifest["frameHeight"]
    walk_frames = manifest["clips"]["walk"]["frames"]

    walk = assemble_walk_atlas(root, facings, fw, fh, walk_frames)
    walk_path = root / "walk-atlas.png"
    walk.save(walk_path)
    print(f"walk atlas -> {walk_path} ({walk.size[0]}×{walk.size[1]})")

    full = assemble_full_sheet(root, manifest)
    full_path = root / "sprite-sheet.png"
    full.save(full_path)
    print(f"sprite sheet -> {full_path} ({full.size[0]}×{full.size[1]})")

    contact = assemble_contact(root, facings, fw, fh, walk_frames)
    contact_path = tool_root / "build" / "contact-sheet.png"
    contact_path.parent.mkdir(parents=True, exist_ok=True)
    contact.save(contact_path)
    print(f"contact sheet -> {contact_path}")

    preview = full.resize((full.width // 4, full.height // 4), Image.LANCZOS)
    preview_path = tool_root / "build" / "sprite-sheet-preview.png"
    preview.save(preview_path)
    print(f"preview -> {preview_path}")


if __name__ == "__main__":
    main()
