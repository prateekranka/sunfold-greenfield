#!/usr/bin/env python3
"""Report the alpha bounding box of a keyed reference and render a QA preview.

The preview composites the RGBA cutout over a mid-grey checkerboard so holes in
dark regions (hair, boots, the shaded basket underside) and matte halos are
visible at a glance.

Usage:
    python3 inspect_alpha.py <in.png> [--preview out.png] [--grid]
"""

from __future__ import annotations

import argparse
import json

import numpy as np
from PIL import Image, ImageDraw


def checkerboard(size: tuple[int, int], cell: int = 24) -> Image.Image:
    w, h = size
    board = Image.new("RGB", size, (208, 208, 208))
    draw = ImageDraw.Draw(board)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if ((x // cell) + (y // cell)) % 2:
                draw.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(168, 168, 168))
    return board


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--preview")
    ap.add_argument("--grid", action="store_true", help="overlay a tenths grid over the bbox")
    ap.add_argument("--cell", type=int, default=24)
    args = ap.parse_args()

    image = Image.open(args.source).convert("RGBA")
    alpha = np.asarray(image)[:, :, 3]

    rows = np.where(alpha.max(axis=1) > 8)[0]
    cols = np.where(alpha.max(axis=0) > 8)[0]
    box = {
        "width": image.width,
        "height": image.height,
        "x0": int(cols[0]),
        "y0": int(rows[0]),
        "x1": int(cols[-1]) + 1,
        "y1": int(rows[-1]) + 1,
    }
    box["boxWidth"] = box["x1"] - box["x0"]
    box["boxHeight"] = box["y1"] - box["y0"]
    box["holes"] = int((alpha[box["y0"] : box["y1"], box["x0"] : box["x1"]] < 8).sum())
    print(json.dumps(box, indent=2))

    if not args.preview:
        return

    board = checkerboard(image.size, args.cell)
    board.paste(image, (0, 0), image)

    draw = ImageDraw.Draw(board)
    draw.rectangle([box["x0"], box["y0"], box["x1"], box["y1"]], outline=(220, 40, 40), width=3)

    if args.grid:
        bw, bh = box["boxWidth"], box["boxHeight"]
        for frac in range(1, 10):
            x = box["x0"] + bw * frac / 10
            y = box["y0"] + bh * frac / 10
            colour = (40, 120, 220) if frac != 5 else (250, 140, 0)
            draw.line([x, box["y0"], x, box["y1"]], fill=colour, width=2)
            draw.line([box["x0"], y, box["x1"], y], fill=colour, width=2)
            draw.text((x + 4, box["y0"] + 6), f".{frac}", fill=(20, 20, 20))
            draw.text((box["x0"] + 6, y + 4), f".{frac}", fill=(20, 20, 20))

    board.save(args.preview)
    print(f"preview -> {args.preview}")


if __name__ == "__main__":
    main()
