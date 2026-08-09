#!/usr/bin/env python3
"""framestat — the instrument behind Gauntlet bar B1b (frame composition).

Two jobs:

  measure   Report the composition statistics of one or more frames against
            concept 01, so "the frame lost its void" is a number instead of an
            opinion.

  pair      Emit a *blind* A/B pair: two crops of identical aspect ratio and
            identical pixel size, named `frame-1.png` / `frame-2.png` in a
            randomised order, plus a sealed `answer.txt`. A critic handed only
            the two frames cannot tell ours from the reference by letterboxing,
            resolution, or filename — which is the only way the A/B is honest.

Why these statistics and not others
-----------------------------------
`AGENTS.md` already records that local sigma is the wrong statistic for texture
work and that an absolute threshold is unusable across an exposure change. Both
warnings apply here, so every statistic below is either a *fraction of the
frame* or a *percentile of the frame's own distribution* — never an absolute
cut, never a variance.

  void_frac        Fraction of theatre pixels below 0.045 linear luma. This is
                   the single number that separates "an island in space" from
                   "a desert". Concept 01 = 0.530.
  luma_p05         The frame's black point. Concept 01 = 0.001; a frame with no
                   true blacks reads as washed out no matter how bright its
                   highlights are.
  dynamic_range    p95 - p05 in linear luma.
  dominant_hue_share
                   Share of coloured pixels falling in the single largest of 36
                   hue bins. Rises toward 1.0 as the frame becomes monochrome.
  sat_mean         Mean HSV saturation over the theatre.

Usage
-----
    python3 Docs/Gauntlet/tools/framestat.py measure FRAME [FRAME ...]
    python3 Docs/Gauntlet/tools/framestat.py measure --json FRAME [...]
    python3 Docs/Gauntlet/tools/framestat.py pair OURS REFERENCE OUTDIR [--seed N]
    python3 Docs/Gauntlet/tools/framestat.py pair OURS REFERENCE OUTDIR --region core

Requires: Pillow, numpy (both present on the project host).
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# --------------------------------------------------------------------------
# Theatre mask
# --------------------------------------------------------------------------
# The SwiftUI HUD composites *above* the RealityKit frame and is not graded by
# the post-process (AGENTS.md), so it must not be averaged into a statistic
# about the rendered world. These fractions cut the chrome out of a
# 2732x2048 landscape capture: top bar + alert strip, and the two bottom
# corners holding the minimap and the command grid.
HUD_TOP = 0.085
HUD_BOTTOM = 0.240
HUD_LEFT = 0.200
HUD_RIGHT = 0.200

# Concept 01, measured by this tool. The visual bar for a full-frame capture.
CONCEPT_01 = {
    "void_frac": 0.530,
    "softvoid_frac": 0.137,
    "luma_p05": 0.001,
    "luma_p50": 0.015,
    "luma_p95": 0.516,
    "dynamic_range": 0.515,
    "sat_mean": 0.484,
    "dominant_hue_share": 0.789,
}

# Named comparison regions, as fractions of (left, top, right, bottom).
# `core` is the settlement block a fidelity critic should judge; `void_ur` is
# the upper-right sky where the celestial body and nebula live.
REGIONS = {
    "full": (0.00, 0.00, 1.00, 1.00),
    "theatre": (0.00, 0.085, 1.00, 0.760),
    "core": (0.28, 0.14, 0.72, 0.62),
    "void_ur": (0.62, 0.02, 1.00, 0.34),
    "ground": (0.10, 0.55, 0.55, 0.78),
}


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def theatre_pixels(a: np.ndarray) -> np.ndarray:
    """Every pixel that is rendered world rather than HUD chrome."""
    h, w, _ = a.shape
    upper = a[int(h * HUD_TOP): int(h * (1 - HUD_BOTTOM)), :, :]
    lower = a[int(h * (1 - HUD_BOTTOM)):, int(w * HUD_LEFT): int(w * (1 - HUD_RIGHT)), :]
    return np.concatenate([upper.reshape(-1, 3), lower.reshape(-1, 3)], axis=0)


def hue_degrees(px: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    mx = px.max(axis=1)
    mn = px.min(axis=1)
    d = mx - mn
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    safe = np.maximum(d, 1e-6)
    hr = ((g - b) / safe) % 6
    hg = ((b - r) / safe) + 2
    hb = ((r - g) / safe) + 4
    hue = np.zeros(len(px))
    nz = d > 1e-6
    pick_r = nz & (mx == r)
    pick_g = nz & (mx == g) & ~pick_r
    pick_b = nz & (mx == b) & ~pick_r & ~pick_g
    hue[pick_r] = hr[pick_r]
    hue[pick_g] = hg[pick_g]
    hue[pick_b] = hb[pick_b]
    sat = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    return hue * 60.0, sat


def measure(path: Path, region: str = "hud-masked") -> dict:
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.float64)

    if region == "hud-masked":
        px = theatre_pixels(a)
    else:
        l, t, r, bo = REGIONS[region]
        h, w, _ = a.shape
        px = a[int(h * t): int(h * bo), int(w * l): int(w * r), :].reshape(-1, 3)

    lin = srgb_to_linear(px)
    luma = 0.2126 * lin[:, 0] + 0.7152 * lin[:, 1] + 0.0722 * lin[:, 2]

    mx, mn = px.max(axis=1), px.min(axis=1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)

    lit = px[luma > 0.10]
    if len(lit) > 200_000:
        lit = lit[np.linspace(0, len(lit) - 1, 200_000).astype(int)]
    dominant = 0.0
    if len(lit):
        hue, hsat = hue_degrees(lit)
        coloured = hue[hsat > 0.12]
        if len(coloured):
            histo, _ = np.histogram(coloured, bins=36, range=(0, 360))
            dominant = float(histo.max() / histo.sum())

    p05, p50, p95 = (float(v) for v in np.percentile(luma, [5, 50, 95]))
    return {
        "frame": path.name,
        "region": region,
        "void_frac": float((luma < 0.045).mean()),
        "softvoid_frac": float(((luma > 0.02) & (luma < 0.18)).mean()),
        "luma_p05": p05,
        "luma_p50": p50,
        "luma_p95": p95,
        "dynamic_range": p95 - p05,
        "sat_mean": float(sat.mean()),
        "dominant_hue_share": dominant,
    }


def cmd_measure(args) -> int:
    rows = [measure(Path(p), args.region) for p in args.frames]
    if args.json:
        print(json.dumps({"concept01": CONCEPT_01, "frames": rows}, indent=2))
        return 0

    cols = ["void_frac", "softvoid_frac", "luma_p05", "luma_p50", "luma_p95",
            "dynamic_range", "sat_mean", "dominant_hue_share"]
    head = f"{'frame':<40}" + "".join(f"{c:>19}" for c in cols)
    print(head)
    print("-" * len(head))
    print(f"{'CONCEPT 01 (the bar)':<40}" + "".join(f"{CONCEPT_01[c]:>19.3f}" for c in cols))
    print("-" * len(head))
    for row in rows:
        print(f"{row['frame']:<40}" + "".join(f"{row[c]:>19.3f}" for c in cols))
    return 0


def cmd_pair(args) -> int:
    """Normalise two frames into an indistinguishable A/B pair."""
    ours = Image.open(args.ours).convert("RGB")
    ref = Image.open(args.reference).convert("RGB")

    l, t, r, b = REGIONS[args.region]

    def crop_norm(im: Image.Image) -> Image.Image:
        w, h = im.size
        box = (int(w * l), int(h * t), int(w * r), int(h * b))
        c = im.crop(box)
        # Force a common aspect ratio by centre-cropping the taller/wider one,
        # then resample both to one width. Aspect ratio and resolution are the
        # two tells that break blindness: our captures are 2732x2048 (4:3) and
        # the concepts are 1536x1024 (3:2).
        target_ar = args.aspect
        cw, ch = c.size
        if cw / ch > target_ar:
            new_w = int(ch * target_ar)
            off = (cw - new_w) // 2
            c = c.crop((off, 0, off + new_w, ch))
        else:
            new_h = int(cw / target_ar)
            off = (ch - new_h) // 2
            c = c.crop((0, off, cw, off + new_h))
        return c.resize((args.width, int(args.width / target_ar)), Image.LANCZOS)

    a, bimg = crop_norm(ours), crop_norm(ref)

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(args.seed)
    ours_is_first = rng.random() < 0.5
    first, second = (a, bimg) if ours_is_first else (bimg, a)
    first.save(outdir / "frame-1.png")
    second.save(outdir / "frame-2.png")

    (outdir / "answer.txt").write_text(
        "DO NOT OPEN UNTIL THE CRITIC HAS ANSWERED.\n\n"
        f"frame-1 = {'OURS' if ours_is_first else 'REFERENCE'}\n"
        f"frame-2 = {'REFERENCE' if ours_is_first else 'OURS'}\n\n"
        f"ours       = {args.ours}\n"
        f"reference  = {args.reference}\n"
        f"region     = {args.region}\n"
        f"normalised = {args.width}x{int(args.width / args.aspect)} @ {args.aspect:.4f}\n"
        f"seed       = {args.seed}\n"
    )
    print(f"wrote {outdir/'frame-1.png'}")
    print(f"wrote {outdir/'frame-2.png'}")
    print(f"wrote {outdir/'answer.txt'}  (sealed — the critic must not read it)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("measure", help="composition statistics vs concept 01")
    m.add_argument("frames", nargs="+")
    m.add_argument("--region", default="hud-masked",
                   choices=["hud-masked", *REGIONS.keys()])
    m.add_argument("--json", action="store_true")
    m.set_defaults(func=cmd_measure)

    q = sub.add_parser("pair", help="emit a blind, size-normalised A/B pair")
    q.add_argument("ours")
    q.add_argument("reference")
    q.add_argument("outdir")
    q.add_argument("--region", default="theatre", choices=list(REGIONS.keys()))
    q.add_argument("--width", type=int, default=1400)
    q.add_argument("--aspect", type=float, default=1.5)
    q.add_argument("--seed", type=int, default=None)
    q.set_defaults(func=cmd_pair)

    args = p.parse_args()
    if getattr(args, "seed", "unset") is None:
        args.seed = random.randrange(1 << 30)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
