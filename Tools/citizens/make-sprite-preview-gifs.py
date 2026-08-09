#!/usr/bin/env python3
"""Large transparent preview animations from baked sprite clips.

Defaults: SE facing, tight crop, native HD frames (1024² canvas when sources
support it). Uses LANCZOS only when downscaling — never nearest-neighbor
upscale from tiny sources.

Usage:
  python3 Tools/citizens/make-sprite-preview-gifs.py
  python3 Tools/citizens/make-sprite-preview-gifs.py --size 1024 --format webp
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
DEFAULT_SPRITES = REPO / "ThreeRuntime/assets/citizens/sprites/sunwoven-weaver"
DEFAULT_OUT = REPO / "Tools/citizens/build/sprite-lab-proof"

CLIP_FPS = {"walk": 10, "gather": 5, "build": 5}


def union_alpha_bbox(frames: list[Image.Image]) -> tuple[int, int, int, int]:
    bbox = None
    for im in frames:
        b = im.split()[3].getbbox()
        if b:
            bbox = b if bbox is None else (
                min(bbox[0], b[0]),
                min(bbox[1], b[1]),
                max(bbox[2], b[2]),
                max(bbox[3], b[3]),
            )
    if bbox is None:
        w, h = frames[0].size
        return (0, 0, w, h)
    return bbox


def padded_bbox(
    bbox: tuple[int, int, int, int],
    frame_size: tuple[int, int],
    pad: int,
) -> tuple[int, int, int, int]:
    w, h = frame_size
    x0, y0, x1, y1 = bbox
    return (
        max(0, x0 - pad),
        max(0, y0 - pad),
        min(w, x1 + pad),
        min(h, y1 + pad),
    )


def crop_upscale_frame(
    img: Image.Image,
    crop: tuple[int, int, int, int],
    out_size: int,
) -> Image.Image:
    cropped = img.crop(crop)
    cw, ch = cropped.size
    scale = min(out_size / cw, out_size / ch)
    if scale >= 1.0:
        # Source is already HD — center on canvas without blocky upscale.
        nw, nh = cw, ch
        resample = Image.Resampling.LANCZOS
    else:
        nw = max(1, int(round(cw * scale)))
        nh = max(1, int(round(ch * scale)))
        resample = Image.Resampling.LANCZOS
    scaled = cropped if (nw, nh) == (cw, ch) else cropped.resize((nw, nh), resample)
    canvas = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
    ox = (out_size - nw) // 2
    oy = (out_size - nh) // 2
    canvas.paste(scaled, (ox, oy), scaled)
    return canvas


def load_clip_frames(sprites: Path, clip: str, facing: int) -> list[Image.Image]:
    d = sprites / clip / str(facing)
    paths = sorted(d.glob("*.png"), key=lambda p: int(p.stem))
    if not paths:
        raise FileNotFoundError(f"No frames in {d}")
    return [Image.open(p).convert("RGBA") for p in paths]


def process_clip(
    sprites: Path,
    clip: str,
    facing: int,
    out_size: int,
    pad: int,
) -> list[Image.Image]:
    raw = load_clip_frames(sprites, clip, facing)
    bbox = padded_bbox(union_alpha_bbox(raw), raw[0].size, pad)
    return [crop_upscale_frame(f, bbox, out_size) for f in raw]


def save_webp(frames: list[Image.Image], path: Path, fps: float) -> None:
    duration_ms = int(round(1000 / fps))
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=duration_ms,
        loop=0,
        lossless=True,
        quality=100,
        method=6,
    )


def save_gif(frames: list[Image.Image], path: Path, fps: float) -> None:
    """1-bit alpha GIF with disposal for clean loops."""
    duration_ms = int(round(1000 / fps))
    paletted: list[Image.Image] = []
    for fr in frames:
        p = fr.convert("RGBA").convert("P", palette=Image.Palette.ADAPTIVE, colors=255)
        p.info["transparency"] = 255
        paletted.append(p)
    paletted[0].save(
        path,
        save_all=True,
        append_images=paletted[1:],
        duration=duration_ms,
        loop=0,
        disposal=2,
        transparency=255,
        optimize=False,
    )


def save_animation(
    frames: list[Image.Image],
    path: Path,
    fps: float,
    fmt: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fmt == "webp":
        save_webp(frames, path, fps)
    elif fmt == "gif":
        save_gif(frames, path, fps)
    else:
        raise ValueError(f"Unknown format: {fmt}")


def build_combined(
    clips: dict[str, list[Image.Image]],
    out_size: int,
    pad: int,
) -> list[Image.Image]:
    """Side-by-side walk · gather · build, 12 ticks @ 100 ms (1.2 s loop)."""
    cell = out_size
    w = pad + cell * 3 + pad * 2
    h = pad + cell + pad
    names = ["walk", "gather", "build"]
    combined: list[Image.Image] = []
    for tick in range(12):
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        walk_idx = tick % 4
        slow_idx = (tick // 2) % 6
        for col, name in enumerate(names):
            idx = walk_idx if name == "walk" else slow_idx
            frame = clips[name][idx]
            x = pad + col * (cell + pad)
            canvas.paste(frame, (x, pad), frame)
        combined.append(canvas)
    return combined


def build_sheet(clips: dict[str, tuple[list[Image.Image], float]], cell: int, pad: int) -> Image.Image:
    rows: list[Image.Image] = []
    for name, (frames, _fps) in clips.items():
        row_w = len(frames) * cell + pad * (len(frames) + 1)
        row = Image.new("RGBA", (row_w, cell + pad * 2), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            row.paste(fr, (pad + i * (cell + pad), pad), fr)
        rows.append(row)
    sheet_w = max(r.width for r in rows)
    sheet_h = sum(r.height for r in rows)
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    y = 0
    for row in rows:
        sheet.paste(row, (0, y), row)
        y += row.height
    return sheet


def ext_for(fmt: str) -> str:
    return ".webp" if fmt == "webp" else ".gif"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sprites", type=Path, default=DEFAULT_SPRITES)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--unit", default="sunwoven-weaver")
    parser.add_argument("--facing", type=int, default=1, help="Facing index (1 = SE)")
    parser.add_argument("--size", type=int, default=1024, help="Output canvas edge (px)")
    parser.add_argument("--pad", type=int, default=4, help="Source-space padding around tight crop")
    parser.add_argument(
        "--format",
        choices=("webp", "gif"),
        default="webp",
        help="webp = full alpha (default); gif = 1-bit alpha",
    )
    args = parser.parse_args()

    if not args.sprites.is_dir():
        print(f"Sprites not found: {args.sprites}", file=sys.stderr)
        return 1

    ext = ext_for(args.format)
    args.out.mkdir(parents=True, exist_ok=True)

    processed: dict[str, list[Image.Image]] = {}
    meta_clips: dict[str, dict] = {}

    for clip, fps in CLIP_FPS.items():
        frames = process_clip(args.sprites, clip, args.facing, args.size, args.pad)
        out_path = args.out / f"{args.unit}-{clip}{ext}"
        save_animation(frames, out_path, fps, args.format)
        processed[clip] = frames
        meta_clips[clip] = {
            "frames": len(frames),
            "fps": fps,
            "path": str(out_path.relative_to(REPO)),
            "bytes": out_path.stat().st_size,
        }
        print(f"{clip}: {len(frames)} frames @ {fps} fps → {out_path} ({meta_clips[clip]['bytes'] // 1024} KB)")

    combined = build_combined(processed, args.size, pad=8)
    combined_path = args.out / f"{args.unit}-actions-combined{ext}"
    save_animation(combined, combined_path, fps=10.0, fmt=args.format)
    print(f"combined: {len(combined)} frames @ 10 fps tick → {combined_path} ({combined_path.stat().st_size // 1024} KB)")

    sheet = build_sheet({k: (v, CLIP_FPS[k]) for k, v in processed.items()}, args.size, pad=8)
    sheet_path = args.out / f"{args.unit}-actions-sheet.png"
    sheet.save(sheet_path)
    print(f"sheet: {sheet_path} ({sheet_path.stat().st_size // 1024} KB)")

    meta = {
        "unit": args.unit,
        "facing": args.facing,
        "size": args.size,
        "format": args.format,
        "background": "transparent",
        "pad": args.pad,
        "clips": meta_clips,
        "combined": str(combined_path.relative_to(REPO)),
        "sheet": str(sheet_path.relative_to(REPO)),
    }
    meta_path = args.out / f"{args.unit}-preview-meta.json"
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    print(f"meta: {meta_path}")
    return 0


if __name__ == "__main__":
    os.chdir(REPO)
    raise SystemExit(main())
