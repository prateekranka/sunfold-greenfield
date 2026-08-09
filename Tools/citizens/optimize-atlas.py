#!/usr/bin/env python3
"""Quantize a sprite atlas PNG to 256 colors for web delivery.

The authored atlas stays bit-exact in the repo; the deploy-site copy is
quantized to ~3.5MB (from ~16MB) with imperceptible visual change at game
scale (verified via grok vision 2026-08-09: no banding, hue shift or edge
fringing; alpha RMS 2.3, opaque-RGB RMS 5.3/255).

Usage:
    python3 Tools/citizens/optimize-atlas.py <input.png> <output.png>
"""

from __future__ import annotations

import sys

from PIL import Image


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    im = Image.open(src)
    q = im.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.FLOYDSTEINBERG)
    q.save(dst, optimize=True)
    print(f"optimized {src} -> {dst} ({q.size[0]}x{q.size[1]}, 256 colors)")


if __name__ == "__main__":
    main()
