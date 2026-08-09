#!/usr/bin/env python3
"""Per-view Codex silhouette shells for near-identity construction turnarounds."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
BUILD = HERE / "build"
CONSTRUCTION_REFS = HERE / "manifest" / "sunwoven-codex-construction-refs.json"
OUT_PATH = BUILD / "codex-hull-sunwoven.json"

RENDER_SIZE = 1400
ORTHO_SCALE = 2.32
LOOK_Z = 1.0
SHELL_DEPTH = 0.22
VOXEL_STEP = 3


def mask_from_pixels(view: str, mask: np.ndarray, scale: float, ox: float, oy: float, oz: float, size: int) -> np.ndarray:
    """Fast raster from mask pixels without building mesh."""
    raster = np.zeros((size, size), dtype=bool)
    ys, xs = np.where(mask)
    ortho = ORTHO_SCALE * scale
    px_w = max(1, int(round(ortho / size * VOXEL_STEP)))
    for py, px in zip(ys[::VOXEL_STEP], xs[::VOXEL_STEP]):
        x, y, z = pixel_to_world(view, float(px), float(py), size, scale, ox, oy, oz)
        u, v = world_to_pixel(view, x, y, z, scale, ox, oy, oz, size)
        cx, cy = int(round(u)), int(round(v))
        raster[
            max(0, cy - px_w):min(size, cy + px_w + 1),
            max(0, cx - px_w):min(size, cx + px_w + 1),
        ] = True
    return ndimage.binary_dilation(raster, structure=np.ones((9, 9), dtype=bool))


def _background_field(image: np.ndarray, corner_size: int = 16) -> np.ndarray:
    height, width, _ = image.shape
    size = max(4, min(corner_size, height // 8, width // 8))
    patches = [
        (slice(0, size), slice(0, size)),
        (slice(0, size), slice(width - size, width)),
        (slice(height - size, height), slice(0, size)),
        (slice(height - size, height), slice(width - size, width)),
    ]
    rows, values = [], []
    for ys, xs in patches:
        yy, xx = np.mgrid[ys, xs]
        xx = (xx / max(width - 1, 1)).reshape(-1)
        yy = (yy / max(height - 1, 1)).reshape(-1)
        rows.append(np.column_stack((np.ones_like(xx), xx, yy, xx * yy)))
        values.append(image[ys, xs].reshape(-1, 3))
    design = np.concatenate(rows, axis=0)
    samples = np.concatenate(values, axis=0)
    coefficients, *_ = np.linalg.lstsq(design, samples, rcond=None)
    grid_y, grid_x = np.mgrid[0:height, 0:width]
    design_grid = np.stack(
        (
            np.ones_like(grid_x, dtype=np.float32),
            grid_x / max(width - 1, 1),
            grid_y / max(height - 1, 1),
            (grid_x * grid_y) / max((width - 1) * (height - 1), 1),
        ),
        axis=-1,
    )
    return np.clip(design_grid @ coefficients, 0.0, 1.0).astype(np.float32)


def foreground_mask(image: np.ndarray) -> np.ndarray:
    background = _background_field(image)
    distance = np.linalg.norm(image - background, axis=2)
    raw = distance > 0.075
    raw[:8] = False
    raw[-8:] = False
    mask = ndimage.binary_closing(raw, structure=np.ones((7, 7), dtype=bool), iterations=1)
    mask = ndimage.binary_opening(mask, structure=np.ones((3, 3), dtype=bool), iterations=1)
    labels, count = ndimage.label(mask)
    if count == 0:
        return mask
    objects = ndimage.find_objects(labels)
    areas = np.bincount(labels.ravel())
    largest = int(np.argmax(areas[1:]) + 1)
    main_slice = objects[largest - 1]
    if main_slice is None:
        return mask
    main_y, main_x = main_slice
    y0, y1 = main_y.start, main_y.stop
    x0, x1 = main_x.start, main_x.stop
    selected = np.zeros_like(mask)
    for label, slc in enumerate(objects, start=1):
        if slc is None or label == 0:
            continue
        ys, xs = slc
        area = int(areas[label])
        width = xs.stop - xs.start
        height = ys.stop - ys.start
        if width > image.shape[1] * 0.65 and height < image.shape[0] * 0.055:
            continue
        near_main = (
            xs.stop >= x0 - 80 and xs.start <= x1 + 80 and
            ys.stop >= y0 - 80 and ys.start <= y1 + 80
        )
        if label == largest or (area >= image.shape[0] * image.shape[1] * 0.00025 and near_main):
            selected[labels == label] = True
    return ndimage.binary_dilation(selected, structure=np.ones((3, 3), dtype=bool))


def load_view_mask(path: Path, crop: dict | None, target_size: int, largest_only: bool = False) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    if crop:
        img = img.crop((crop["x"], crop["y"], crop["x"] + crop["width"], crop["y"] + crop["height"]))
    img = img.resize((target_size, target_size), Image.Resampling.LANCZOS)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    mask = foreground_mask(arr)
    if largest_only:
        labels, count = ndimage.label(mask)
        if count > 0:
            areas = np.bincount(labels.ravel())
            largest = int(np.argmax(areas[1:]) + 1)
            mask = labels == largest
    return mask


def pixel_to_world(view: str, px: float, py: float, size: int, scale: float, ox: float, oy: float, oz: float) -> tuple[float, float, float]:
    u = px / size
    v = py / size
    ortho = ORTHO_SCALE * scale
    if view == "front":
        x = (u - 0.5) * ortho + ox
        z = LOOK_Z + (0.5 - v) * ortho + oz
        y = oy
        return x, y, z
    if view == "side":
        y = ((u - 0.5) * ortho) + oy
        z = LOOK_Z + (0.5 - v) * ortho + oz
        x = ox
        return x, y, z
    # back
    x = -((u - 0.5) * ortho) + ox
    z = LOOK_Z + (0.5 - v) * ortho + oz
    y = oy
    return x, y, z


def world_to_pixel(view: str, x: float, y: float, z: float, scale: float, ox: float, oy: float, oz: float, size: int) -> tuple[float, float]:
    ortho = ORTHO_SCALE * scale
    if view == "front":
        u = (x - ox) / ortho + 0.5
        v = 0.5 - (z - LOOK_Z - oz) / ortho
    elif view == "side":
        u = ((y - oy)) / ortho + 0.5
        v = 0.5 - (z - LOOK_Z - oz) / ortho
    else:
        u = (-(x - ox)) / ortho + 0.5
        v = 0.5 - (z - LOOK_Z - oz) / ortho
    return u * size, v * size


def center_mask(mask: np.ndarray) -> np.ndarray:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return mask
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    target_x = mask.shape[1] // 2
    target_y = int(mask.shape[0] * 0.50)
    shift_x = target_x - (x0 + x1) // 2
    shift_y = target_y - (y0 + y1) // 2
    return ndimage.shift(mask.astype(np.uint8), (shift_y, shift_x), order=0, mode="constant", cval=0).astype(bool)


def mask_iou(a: np.ndarray, b: np.ndarray) -> float:
    aa = center_mask(a)
    bb = center_mask(b)
    union = aa | bb
    inter = aa & bb
    return float(inter.sum() / max(1, union.sum()))


def rasterize_shell(view: str, verts: list, scale: float, ox: float, oy: float, oz: float, size: int) -> np.ndarray:
    raster = np.zeros((size, size), dtype=bool)
    ortho = ORTHO_SCALE * scale
    px_size_x = ortho / size
    px_size_z = ortho / size
    half_y = SHELL_DEPTH * 0.5
    for x, y, z in verts:
        for py in np.linspace(-half_y, half_y, 3):
            u, v = world_to_pixel(view, x, y + py, z, scale, ox, oy, oz, size)
            px0 = int(round(u - px_size_x * size * 0.5))
            px1 = int(round(u + px_size_x * size * 0.5))
            py0 = int(round(v - px_size_z * size * 0.5))
            py1 = int(round(v + px_size_z * size * 0.5))
            raster[max(0, py0):min(size, py1 + 1), max(0, px0):min(size, px1 + 1)] = True
    return ndimage.binary_dilation(raster, structure=np.ones((3, 3), dtype=bool))


def build_view_shell(view: str, mask: np.ndarray, scale: float, ox: float, oy: float, oz: float) -> tuple[list, list]:
    size = RENDER_SIZE
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return [], []
    step = VOXEL_STEP
    xs = xs[::step]
    ys = ys[::step]
    ortho = ORTHO_SCALE * scale
    px_w = ortho / size * step * 1.10
    px_h = ortho / size * step * 1.10
    half_d = SHELL_DEPTH * 0.5
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    vert_map: dict[tuple, int] = {}

    def add_box(cx: float, cy: float, cz: float, hx: float, hy: float, hz: float) -> None:
        corners = [
            (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
            (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
            (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
            (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
        ]
        idx = []
        for c in corners:
            key = (round(c[0], 5), round(c[1], 5), round(c[2], 5))
            if key not in vert_map:
                vert_map[key] = len(verts)
                verts.append(c)
            idx.append(vert_map[key])
        faces.extend([
            (idx[0], idx[1], idx[2], idx[3]),
            (idx[4], idx[7], idx[6], idx[5]),
            (idx[0], idx[4], idx[5], idx[1]),
            (idx[2], idx[6], idx[7], idx[3]),
            (idx[0], idx[3], idx[7], idx[4]),
            (idx[1], idx[5], idx[6], idx[2]),
        ])

    for py, px in zip(ys, xs):
        x, y, z = pixel_to_world(view, float(px), float(py), size, scale, ox, oy, oz)
        if view == "front":
            add_box(x, y, z, px_w * 0.5, half_d, px_h * 0.5)
        elif view == "side":
            add_box(x, y, z, half_d, px_w * 0.5, px_h * 0.5)
        else:
            add_box(x, y, z, px_w * 0.5, half_d, px_h * 0.5)
    return verts, faces


def calibrate_view(view: str, mask: np.ndarray) -> tuple[float, float, float, float, float]:
    best = (-1.0, 1.0, 0.0, 0.0, 0.0)
    size = RENDER_SIZE
    grids = [
        np.linspace(0.98, 1.04, 7),
        np.linspace(-0.025, 0.025, 5),
        np.linspace(-0.035, 0.035, 5),
        np.linspace(-0.05, 0.01, 5),
    ]
    for scale in grids[0]:
        for ox in grids[1]:
            for oy in grids[2]:
                for oz in grids[3]:
                    raster = mask_from_pixels(view, mask, float(scale), float(ox), float(oy), float(oz), size)
                    score = mask_iou(raster, mask)
                    if score > best[0]:
                        best = (score, float(scale), float(ox), float(oy), float(oz))
    return best[1], best[2], best[3], best[4], best[0]


def main() -> None:
    construction = json.loads(CONSTRUCTION_REFS.read_text())
    masks: dict[str, np.ndarray] = {}
    for view, ref_entry in construction["references"].items():
        if isinstance(ref_entry, str):
            ref_path = REPO / ref_entry
            crop = None
        else:
            ref_path = REPO / ref_entry["path"]
            crop = ref_entry.get("crop_px")
        masks[view] = load_view_mask(ref_path, crop, RENDER_SIZE, largest_only=(view == "side"))

    shells: dict[str, dict] = {}
    per_view_iou: dict[str, float] = {}
    for view, mask in masks.items():
        if isinstance(ref_entry := construction["references"][view], str):
            ref_path = REPO / ref_entry
        else:
            ref_path = REPO / ref_entry["path"]
        scale, ox, oy, oz, score = calibrate_view(view, mask)
        verts, faces = build_view_shell(view, mask, scale, ox, oy, oz)
        shells[view] = {"vertices": verts, "faces": faces, "scale": scale, "offset": {"x": ox, "y": oy, "z": oz}, "reference": str(ref_path.relative_to(REPO))}
        per_view_iou[view] = score
        print(f"[codex_envelope] {view}: scale={scale:.4f} offset=({ox:.3f},{oy:.3f},{oz:.3f}) cal IoU={score:.4f} verts={len(verts)}")

    payload = {
        "schema": "sunfold.sunwoven.codex-shells/2",
        "mode": "per_view_silhouette_shells",
        "calibration": {
            "ortho_scale": ORTHO_SCALE,
            "look_z": LOOK_Z,
            "render_size": RENDER_SIZE,
            "per_view_iou_estimate": per_view_iou,
            "mean_iou_estimate": float(np.mean(list(per_view_iou.values()))),
        },
        "shells": shells,
    }
    BUILD.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"[codex_envelope] wrote {OUT_PATH} mean IoU est {payload['calibration']['mean_iou_estimate']:.4f}")


if __name__ == "__main__":
    main()
