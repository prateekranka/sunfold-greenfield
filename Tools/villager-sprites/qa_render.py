#!/usr/bin/env python3
"""Render a cut rig for eyeballing, before it is ever baked.

Two checks, and both matter:

* `--rest` composites the rig with every angle at zero and diffs it against the
  original crop. A lossless cut leaves no holes and no colour drift, so a nonzero
  hole count means a cut orphaned pixels and a nonzero diff means a part is drawn
  in the wrong order.
* `--clips` lays every frame of every clip out in a strip, which is the only way
  to see a limb swinging the wrong way or a prop sliding off its hand.

Usage:
    python3 qa_render.py E --rest build/rest-E.png --clips build/qa-clips-E.png
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import cut_parts
import rigpose as rp
from bake_sprites import resolve_angles, resolve_root

PAD = 300


def checkerboard(size: tuple[int, int], step: int = 16) -> Image.Image:
    board = Image.new("RGBA", size, (208, 208, 212, 255))
    draw = ImageDraw.Draw(board)
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            if ((x // step) + (y // step)) % 2:
                draw.rectangle([x, y, x + step - 1, y + step - 1], fill=(168, 168, 174, 255))
    return board


def render_rest(rig: rp.Rig, root: Path, view: str, out: Path) -> None:
    canvas = (rig.width + 2 * PAD, rig.height + 2 * PAD)
    # Cancel every rest angle, so the rig returns to the pose that was painted.
    # Anything that differs now is the cut losing pixels, not the rig re-posing them.
    painted = {pid: -part.rest_angle for pid, part in rig.parts.items() if part.rest_angle}
    posed = rp.render_pose(rig, {"angles": painted, "root": [0, 0]}, canvas, (PAD, PAD))
    posed = posed.crop((PAD, PAD, PAD + rig.width, PAD + rig.height))

    manifest = json.loads((root / "parts" / view / "parts.json").read_text())
    rig_doc = json.loads((root / "rig" / f"rig-{view}.json").read_text())
    # Load the figure through the cutter itself, so the comparison sees exactly
    # what the cutter saw - same mirror, same backdrop key, same resample.
    original = cut_parts.load_figure(rig_doc, root)

    a, b = np.asarray(original).astype(int), np.asarray(posed).astype(int)
    solid = a[:, :, 3] > 8
    # A part placed by `propSource` is not carved out of the figure, so it adds
    # paint the original crop never had. Those pixels are excluded from the diff.
    props = {p["id"] for p in rig_doc["parts"] if p.get("propSource")}
    prop_mask = np.zeros_like(solid)
    for record in manifest["parts"]:
        if record["id"] not in props:
            continue
        layer = Image.open(root / "parts" / view / record["file"]).convert("RGBA")
        ox = int(round(record["offset"][0] * rig.width))
        oy = int(round(record["offset"][1] * rig.height))
        alpha = np.asarray(layer)[:, :, 3] > 8
        prop_mask[oy:oy + alpha.shape[0], ox:ox + alpha.shape[1]] |= alpha
    compare = solid & ~prop_mask

    holes = int((compare & (b[:, :, 3] <= 8)).sum())
    diff = np.abs(a[:, :, :3] - b[:, :, :3]).max(axis=2)
    drift = int(((diff > 16) & compare & (b[:, :, 3] > 8)).sum())
    mean = float(diff[compare].mean()) if compare.any() else 0.0
    print(f"{view} rest: holes {holes}  rgb diff>16 {drift}  mean diff {mean:.3f}  "
          f"prop pixels excluded {int(prop_mask.sum())}")

    sheet = checkerboard((rig.width * 2 + 24, rig.height))
    sheet.alpha_composite(original, (0, 0))
    sheet.alpha_composite(posed, (rig.width + 24, 0))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out)
    print(f"  rest -> {out}")


def render_clips(rig: rp.Rig, root: Path, view: str, gain_key: str, out: Path,
                 cell: int = 300) -> None:
    doc = json.loads((root / "clips.json").read_text())
    gains = doc["viewGain"][gain_key]
    clips = doc["clips"]

    canvas = (rig.width + 2 * PAD, rig.height + 2 * PAD)
    origin = (PAD, PAD)
    scale = cell / rig.height
    cols = max(len(clip["frames"]) for clip in clips.values())
    sheet = checkerboard((cols * cell, len(clips) * cell))
    draw = ImageDraw.Draw(sheet)

    for row, (name, clip) in enumerate(clips.items()):
        for col, frame in enumerate(clip["frames"]):
            image = rp.render_pose(
                rig,
                {"angles": resolve_angles(frame, gains, 0.0), "root": resolve_root(frame, gains)},
                canvas, origin,
            )
            box = (int(PAD - rig.width * 0.35), PAD - int(rig.height * 0.18),
                   int(PAD + rig.width * 1.35), PAD + rig.height + int(rig.height * 0.05))
            tile = image.crop(box)
            tile = tile.resize((max(1, int(tile.width * scale * 0.78)),
                                max(1, int(tile.height * scale * 0.78))), Image.LANCZOS)
            sheet.alpha_composite(tile, (col * cell + (cell - tile.width) // 2,
                                         row * cell + (cell - tile.height) // 2))
        draw.text((6, row * cell + 6), f"{name} ({gain_key})", fill=(20, 20, 20, 255))
        draw.line([(0, row * cell), (sheet.width, row * cell)], fill=(90, 90, 96, 255))

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out)
    print(f"  clips -> {out}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("view", choices=("S", "E", "N"))
    ap.add_argument("--rest")
    ap.add_argument("--clips")
    ap.add_argument("--gain", help="viewGain key for the clip strip (default: the view name)")
    args = ap.parse_args()

    root = Path(__file__).parent
    rig = rp.load_rig(root / "parts" / args.view)
    if args.rest:
        render_rest(rig, root, args.view, Path(args.rest))
    if args.clips:
        render_clips(rig, root, args.view, args.gain or args.view, Path(args.clips))


if __name__ == "__main__":
    main()
