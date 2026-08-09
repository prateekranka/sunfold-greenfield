#!/usr/bin/env python3
"""Cut a keyed reference view into rigged part layers.

The painted figure's alpha already carries the silhouette, so a part never has to
declare an outline. It declares only where it lives:

* `cuts`   — thick line segments that sever the silhouette at joints. A limb in
             this pose is already separated from the torso by background over
             most of its length, so one short segment across the shoulder,
             elbow, knee or ankle is enough to isolate it exactly.
* `seeds`  — a flood fill from these points claims the connected region the cuts
             just carved out. This is what makes a limb follow its painted edge
             instead of a hand-guessed polygon.
* `regions`— convex polygons, for the cases a flood fill cannot separate: a prop
             painted *in front of* the body, where no background gap exists.
             Regions resolve before seeds, in declaration order.

Cut pixels are then healed back to whichever part owns the nearest silhouette,
so the seam leaves no gap. Finally every part with `capRadius > 0` also takes a
disc of silhouette centred on its pivot, on top of what it already owns. That
deliberate double-ownership with its parent is what stops a rotated limb from
opening a wedge-shaped hole at its own joint.

Usage:
    python3 cut_parts.py rig/rig-S.json --out-dir parts --qa build/qa-parts-S.png
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

QA_COLOURS = [
    (232, 78, 78), (78, 158, 232), (120, 200, 96), (240, 176, 64),
    (176, 112, 232), (64, 208, 200), (232, 120, 176), (150, 150, 90),
    (96, 120, 232), (208, 96, 64), (96, 200, 160), (200, 200, 96),
    (160, 96, 128), (96, 160, 96), (232, 148, 112), (128, 128, 200),
    (200, 128, 96), (112, 184, 216), (184, 96, 184), (144, 176, 64),
]

NEIGHBOURS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def load_figure(rig: dict, root: Path) -> Image.Image:
    source = Image.open(root / rig["source"]).convert("RGBA")
    if rig.get("mirrorSource"):
        source = source.transpose(Image.FLIP_LEFT_RIGHT)
    x0, y0, x1, y1 = rig["figureBox"]
    figure = source.crop((x0, y0, x1, y1))
    if rig.get("key"):
        # Backdrop sealed in by the pose - the wedge between a spread arm and the
        # ribs - survives the border flood and would be cut into a body part, so
        # it rides along when that part swings. Remove it before anything claims it.
        figure = key_enclosed_backdrop(figure, rig["key"], rig.get("keyTolerance", 34.0),
                                       rig.get("keyMinArea", 400))
    # The three turnaround sheets are not drawn at one scale. Normalizing every
    # view to the same figure height is what stops a unit changing size as it
    # turns, and it lets the rigs share one canvas and one sprite frame box.
    target = rig.get("targetHeight")
    if target and figure.height != target:
        width = max(1, round(figure.width * target / figure.height))
        figure = figure.resize((width, target), Image.LANCZOS)
    return figure


def rasterize_polygons(polygons: list, size: tuple[int, int]) -> np.ndarray:
    canvas = Image.new("1", size, 0)
    draw = ImageDraw.Draw(canvas)
    w, h = size
    for polygon in polygons:
        draw.polygon([(px * w, py * h) for px, py in polygon], fill=1)
    return np.asarray(canvas, dtype=bool)


def rasterize_cuts(cuts: list, default_thickness: float, size: tuple[int, int]) -> np.ndarray:
    canvas = Image.new("1", size, 0)
    draw = ImageDraw.Draw(canvas)
    w, h = size
    for cut in cuts:
        thickness = cut.get("thickness", default_thickness)
        width = max(2, int(round(thickness * h)))
        ax, ay = cut["from"]
        bx, by = cut["to"]
        draw.line([(ax * w, ay * h), (bx * w, by * h)], fill=1, width=width)
    return np.asarray(canvas, dtype=bool)


def flood(available: np.ndarray, seeds: list, size: tuple[int, int]) -> np.ndarray:
    """4-connected flood fill from normalized seed points over `available`."""
    w, h = size
    out = np.zeros_like(available)
    queue: deque[tuple[int, int]] = deque()
    for sx, sy in seeds:
        x, y = int(sx * w), int(sy * h)
        if not (0 <= x < w and 0 <= y < h):
            raise SystemExit(f"seed ({sx}, {sy}) is outside the figure box")
        if not available[y, x]:
            raise SystemExit(
                f"seed ({sx}, {sy}) -> px ({x}, {y}) is not on free silhouette "
                "(it is background, already claimed, or sitting on a cut)"
            )
        if not out[y, x]:
            out[y, x] = True
            queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in NEIGHBOURS:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and available[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                queue.append((ny, nx))
    return out


def heal(owner: np.ndarray, silhouette: np.ndarray) -> int:
    """Give every unowned silhouette pixel to its nearest owner.

    Two passes. The first walks only along the silhouette, which is what closes a
    cut seam: the severed pixels rejoin whichever side they touch. The second
    ignores the silhouette so it can also reach *islands* — a scrap of sleeve or
    blade that a cut isolated from every seed. Without it those islands fall
    through to the fallback part, and a scrap of arm rides on the torso, visible
    the moment the real arm swings away from it.

    Returns the number of island pixels re-homed by the second pass.
    """
    h, w = owner.shape

    def bfs(passable: np.ndarray) -> None:
        queue: deque[tuple[int, int]] = deque()
        ys, xs = np.where(owner >= 0)
        queue.extend(zip(ys.tolist(), xs.tolist()))
        while queue:
            y, x = queue.popleft()
            label = owner[y, x]
            for dy, dx in NEIGHBOURS:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and owner[ny, nx] < 0:
                    owner[ny, nx] = label
                    queue.append((ny, nx))

    bfs(silhouette)
    stranded = int((silhouette & (owner < 0)).sum())
    if stranded:
        bfs(np.ones((h, w), dtype=bool))
        owner[~silhouette] = -1
    return stranded


def disc(centre, radius: float, size: tuple[int, int]) -> np.ndarray:
    w, h = size
    cx, cy, r = centre[0] * w, centre[1] * h, radius * h
    ys, xs = np.ogrid[:h, :w]
    return ((xs - cx) ** 2 + (ys - cy) ** 2) <= r * r


def geodesic_dilate(mask: np.ndarray, silhouette: np.ndarray, steps: int) -> np.ndarray:
    """Grow a mask outward by `steps` pixels, never leaving the silhouette.

    A cut leaves the parent with a straight synthetic edge where the child used
    to sit. Rotate the child and that edge is exposed as a gap. Growing the
    parent back under the child fills it. Every part is drawn above its parent,
    so the overlap is invisible in the rest pose and only shows up as coverage
    once the joint moves.
    """
    out = mask.copy()
    for _ in range(steps):
        grown = out.copy()
        grown[1:, :] |= out[:-1, :]
        grown[:-1, :] |= out[1:, :]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown & silhouette
    return out


def key_enclosed_backdrop(image: Image.Image, key, tolerance: float, min_area: int) -> Image.Image:
    """Drop backdrop still trapped inside a prop, such as the sky in a handle loop.

    The border flood in isolate_backdrop.py cannot reach an enclosed pocket, so it
    survives as an opaque navy patch. A plain colour threshold would also eat the
    darkest wicker and the shaded leather, so only *blobs* are removed: a pocket of
    trapped backdrop is one large connected region, a dark texel is not.
    """
    rgba = np.asarray(image)
    key_rgb = np.asarray(key, dtype=float)
    near = (np.sqrt(((rgba[:, :, :3].astype(float) - key_rgb) ** 2).sum(axis=2)) < tolerance)
    near &= rgba[:, :, 3] > 8

    h, w = near.shape
    seen = np.zeros_like(near)
    kill = np.zeros_like(near)
    for sy, sx in zip(*np.where(near)):
        if seen[sy, sx]:
            continue
        blob = [(sy, sx)]
        seen[sy, sx] = True
        queue = deque(blob)
        while queue:
            y, x = queue.popleft()
            for dy, dx in NEIGHBOURS:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    blob.append((ny, nx))
                    queue.append((ny, nx))
        if len(blob) >= min_area:
            for y, x in blob:
                kill[y, x] = True

    if not kill.any():
        return image
    out = rgba.copy()
    out[:, :, 3] = np.where(kill, 0, out[:, :, 3])
    return Image.fromarray(out, "RGBA")


def place_prop(part: dict, size: tuple[int, int], root: Path) -> Image.Image:
    """Scale, rotate and drop a separately-drawn prop onto a full-figure layer."""
    spec = part["propSource"]
    prop = Image.open(root / spec["image"]).convert("RGBA").crop(tuple(spec["box"]))
    if spec.get("flip"):
        prop = prop.transpose(Image.FLIP_LEFT_RIGHT)
    if spec.get("key"):
        prop = key_enclosed_backdrop(prop, spec["key"], spec.get("keyTolerance", 34.0),
                                     spec.get("keyMinArea", 400))

    w, h = size
    x0, y0, x1, y1 = part["place"]
    target_w, target_h = (x1 - x0) * w, (y1 - y0) * h
    if part.get("fit") == "stretch":
        # A prop drawn three-quarter-on is too wide for a profile view. Stretching
        # to the place box narrows the basket to the depth it really has on a back.
        prop = prop.resize((max(1, round(target_w)), max(1, round(target_h))), Image.LANCZOS)
    else:
        scale = min(target_w / prop.width, target_h / prop.height)
        prop = prop.resize((max(1, round(prop.width * scale)), max(1, round(prop.height * scale))),
                           Image.LANCZOS)
    angle = part.get("placeRotate", 0.0)
    if angle:
        prop = prop.rotate(angle, resample=Image.BICUBIC, expand=True)

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    cx, cy = (x0 + x1) * 0.5 * w, (y0 + y1) * 0.5 * h
    layer.alpha_composite(prop, (int(round(cx - prop.width / 2)), int(round(cy - prop.height / 2))))
    return layer


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("rig")
    ap.add_argument("--out-dir", default="parts")
    ap.add_argument("--qa")
    ap.add_argument("--alpha-floor", type=int, default=8)
    args = ap.parse_args()

    rig_path = Path(args.rig)
    root = rig_path.parent.parent
    rig = json.loads(rig_path.read_text())

    figure = load_figure(rig, root)
    size = figure.size
    w, h = size
    silhouette = np.asarray(figure)[:, :, 3] > args.alpha_floor

    parts = rig["parts"]
    ids = [p["id"] for p in parts]
    if len(set(ids)) != len(ids):
        raise SystemExit("duplicate part ids in rig")
    if rig["fallback"] not in ids:
        raise SystemExit(f"fallback part {rig['fallback']!r} is not declared")
    for part in parts:
        if part.get("parent") and part["parent"] not in ids:
            raise SystemExit(f"part {part['id']!r} has unknown parent {part['parent']!r}")

    blocked = rasterize_cuts(rig.get("cuts", []), rig.get("cutThickness", 0.005), size)
    owner = np.full((h, w), -1, dtype=np.int16)

    # Phase A — explicit polygons, for props painted in front of the body.
    for index, part in enumerate(parts):
        if part.get("regions"):
            claim = rasterize_polygons(part["regions"], size) & silhouette & (owner < 0)
            owner[claim] = index

    # Phase B — flood fill inside the regions the cuts carved out.
    for index, part in enumerate(parts):
        if part.get("seeds"):
            available = silhouette & ~blocked & (owner < 0)
            owner[flood(available, part["seeds"], size)] = index

    # Phase C — a seedless fallback sweeps up whatever is still free and uncut.
    # With seeds it was already flooded in phase B, and anything left over is an
    # island that phase D re-homes by proximity instead.
    fallback_index = ids.index(rig["fallback"])
    if not parts[fallback_index].get("seeds"):
        owner[silhouette & ~blocked & (owner < 0)] = fallback_index

    # Phase D — close the cut seams, then re-home anything a cut stranded.
    stranded = heal(owner, silhouette)

    # Phase E — additive joint caps and parent overlap, shared with neighbours.
    masks = []
    for index, part in enumerate(parts):
        mask = owner == index
        cap = part.get("capRadius", 0.0)
        if cap > 0:
            # Restrict the cap to silhouette that is actually *connected* to this
            # part. A raw disc at the elbow reaches across the armpit gap and
            # grabs a scrap of torso, which then flies off with the swinging arm.
            radius_px = max(1, int(round(cap * h)))
            region = mask | (disc(part["pivot"], cap, size) & silhouette)
            mask = geodesic_dilate(mask, region, 2 * radius_px + 2)
        grow = part.get("dilate", 0.0)
        if grow > 0:
            mask = geodesic_dilate(mask, silhouette, max(1, int(round(grow * h))))
        masks.append(mask)

    out_dir = root / args.out_dir / rig["view"]
    out_dir.mkdir(parents=True, exist_ok=True)
    rgba = np.asarray(figure)

    by_id = {part["id"]: index for index, part in enumerate(parts)}
    records = []
    for index, part in enumerate(parts):
        if part.get("propSource"):
            # A prop the sheet draws separately from the body — the side view
            # hands the basket, pail and sickle over as loose objects, so they are
            # scaled and placed onto the figure rather than carved out of it.
            layer_image = place_prop(part, size, root)
            mask = np.asarray(layer_image)[:, :, 3] > args.alpha_floor
            layer = np.asarray(layer_image)
        else:
            source_index = by_id[part["cloneOf"]] if part.get("cloneOf") else index
            mask = masks[source_index]
            if not mask.any():
                raise SystemExit(f"part {part['id']!r} claimed no pixels")
            layer = rgba.copy()
            layer[:, :, 3] = np.where(mask, layer[:, :, 3], 0)

        shade = part.get("shade")
        if shade:
            layer = layer.copy()
            layer[:, :, :3] = np.clip(layer[:, :, :3].astype(float) * shade, 0, 255).astype(np.uint8)

        rows, cols = np.where(mask.any(axis=1))[0], np.where(mask.any(axis=0))[0]
        bx0, by0 = int(cols[0]), int(rows[0])
        bx1, by1 = int(cols[-1]) + 1, int(rows[-1]) + 1

        Image.fromarray(layer[by0:by1, bx0:bx1], mode="RGBA").save(out_dir / f"{part['id']}.png")
        records.append(
            {
                "id": part["id"],
                "parent": part.get("parent"),
                "z": part["z"],
                "file": f"{part['id']}.png",
                "offset": [bx0 / w, by0 / h],
                "size": [(bx1 - bx0) / w, (by1 - by0) / h],
                "pixelSize": [bx1 - bx0, by1 - by0],
                "pivot": part["pivot"],
                "pivotLocal": [part["pivot"][0] * w - bx0, part["pivot"][1] * h - by0],
                "restAngle": part.get("restAngle", 0.0),
                "pixels": int(mask.sum()),
            }
        )

    manifest = {
        "schema": "sunfold.cutout-parts/2",
        "view": rig["view"],
        "facingHint": rig.get("facingHint"),
        "source": rig["source"],
        "mirrorSource": bool(rig.get("mirrorSource")),
        "figureBox": rig["figureBox"],
        "figurePixelSize": [w, h],
        "groundLine": rig.get("groundLine", 1.0),
        "centreLine": rig.get("centreLine", 0.5),
        "parts": records,
    }
    (out_dir / "parts.json").write_text(json.dumps(manifest, indent=2) + "\n")

    total = int(silhouette.sum())
    print(f"{rig['view']}: {len(records)} parts, figure {w}x{h}, silhouette {total} px, "
          f"islands re-homed by proximity: {stranded} px")
    for record in records:
        share = 100.0 * record["pixels"] / total
        print(f"  {record['id']:<14} z={record['z']:<3} px={record['pixels']:>7} ({share:5.1f}%)")

    if args.qa:
        painted = np.zeros((h, w, 3), dtype=np.uint8)
        painted[:] = (24, 24, 28)
        for index in range(len(parts)):
            painted[owner == index] = QA_COLOURS[index % len(QA_COLOURS)]
        qa = Image.fromarray(painted, mode="RGB")
        draw = ImageDraw.Draw(qa)
        for cut in rig.get("cuts", []):
            draw.line(
                [(cut["from"][0] * w, cut["from"][1] * h), (cut["to"][0] * w, cut["to"][1] * h)],
                fill=(255, 255, 255),
                width=2,
            )
        for part in parts:
            px, py = part["pivot"][0] * w, part["pivot"][1] * h
            draw.ellipse([px - 8, py - 8, px + 8, py + 8], outline=(255, 255, 255), width=3)
            draw.ellipse([px - 2, py - 2, px + 2, py + 2], fill=(20, 20, 20))
            draw.text((px + 11, py - 6), part["id"], fill=(255, 255, 255))
        qa_path = root / args.qa
        qa_path.parent.mkdir(parents=True, exist_ok=True)
        qa.save(qa_path)
        print(f"qa -> {qa_path}")


if __name__ == "__main__":
    main()
