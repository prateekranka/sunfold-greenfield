#!/usr/bin/env python3
"""composite.py — dark-composite the raw turnaround renders over (18,18,24).

Reads Docs/QA/ThreeJS/pathfinder-v2/raw-<view>.png (transparent RGBA) and
writes pathfinder-<view>.png composited over the dark kit background.
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "..", "..", "Docs", "QA", "ThreeJS", "pathfinder-v2")
OUT_DIR = os.path.normpath(OUT_DIR)

BG = (18, 18, 24)

VIEWS = ["front", "side_e", "rear", "three_q", "top"]

for view in VIEWS:
    raw = os.path.join(OUT_DIR, f"raw-{view}.png")
    final = os.path.join(OUT_DIR, f"pathfinder-{view}.png")
    if not os.path.exists(raw):
        print(f"MISSING {raw}")
        continue
    img = Image.open(raw).convert("RGBA")
    bg = Image.new("RGBA", img.size, (*BG, 255))
    out = Image.alpha_composite(bg, img)
    out.convert("RGB").save(final)
    print(f"composited {final}  {out.size}")

print("COMPOSITE_DONE")
