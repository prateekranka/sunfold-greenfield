#!/usr/bin/env python3
"""Key the flat navy studio backdrop out of a Codex turnaround PNG.

The reference sheets are lit against a single near-uniform dark navy card. The
img2threejs admission gate needs an isolable silhouette, so this replaces the
backdrop with transparency using a flood fill from the frame border in RGB
distance space (not a global colour threshold, which would eat the figure's own
dark hair and boots).

Usage:
    python3 isolate_backdrop.py <in.png> <out.png> [--tolerance 34] [--feather 1]
"""

from __future__ import annotations

import argparse
from collections import deque

import numpy as np
from PIL import Image, ImageFilter


def backdrop_colour(rgb: np.ndarray, margin: int = 6) -> np.ndarray:
    """Median colour of the frame border — the backdrop, by construction."""
    border = np.concatenate(
        [
            rgb[:margin, :, :].reshape(-1, 3),
            rgb[-margin:, :, :].reshape(-1, 3),
            rgb[:, :margin, :].reshape(-1, 3),
            rgb[:, -margin:, :].reshape(-1, 3),
        ]
    )
    return np.median(border, axis=0)


def flood_backdrop(rgb: np.ndarray, key: np.ndarray, tolerance: float) -> np.ndarray:
    """Border-seeded flood fill over pixels within `tolerance` of the key colour."""
    h, w, _ = rgb.shape
    near = np.linalg.norm(rgb.astype(np.float32) - key, axis=2) <= tolerance

    is_bg = np.zeros((h, w), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    for x in range(w):
        for y in (0, h - 1):
            if near[y, x] and not is_bg[y, x]:
                is_bg[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near[y, x] and not is_bg[y, x]:
                is_bg[y, x] = True
                queue.append((y, x))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not is_bg[ny, nx]:
                is_bg[ny, nx] = True
                queue.append((ny, nx))

    return is_bg


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("out")
    ap.add_argument("--tolerance", type=float, default=34.0)
    ap.add_argument("--feather", type=float, default=1.0)
    args = ap.parse_args()

    image = Image.open(args.source).convert("RGB")
    rgb = np.asarray(image)

    key = backdrop_colour(rgb)
    is_bg = flood_backdrop(rgb, key, args.tolerance)

    alpha = np.where(is_bg, 0, 255).astype(np.uint8)
    alpha_img = Image.fromarray(alpha, mode="L")
    if args.feather > 0:
        alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(args.feather))

    out = Image.merge("RGBA", (*image.split(), alpha_img))
    out.save(args.out)

    coverage = 1.0 - float(is_bg.mean())
    print(
        f"{args.out}  key=rgb({int(key[0])},{int(key[1])},{int(key[2])})  "
        f"foreground={coverage:.4f}"
    )


if __name__ == "__main__":
    main()
