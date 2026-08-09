"""Key Codex navy plates to RGBA for AoE2-style sprite sheets."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


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
    """Separate painted citizen from graded Codex navy plate."""
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
            xs.stop >= x0 - 80
            and xs.start <= x1 + 80
            and ys.stop >= y0 - 80
            and ys.start <= y1 + 80
        )
        if label == largest or (area >= image.shape[0] * image.shape[1] * 0.00025 and near_main):
            selected[labels == label] = True
    return ndimage.binary_dilation(selected, structure=np.ones((3, 3), dtype=bool))


def key_codex_plate_to_rgba(path: str | Path, *, distance_threshold: float = 0.075) -> None:
    """Replace navy plate pixels with transparency; writes RGBA PNG in place."""
    path = Path(path)
    img = Image.open(path)
    had_alpha = img.mode in ("RGBA", "LA") and img.getextrema()[-1][0] < 255
    arr = np.asarray(img.convert("RGBA"), dtype=np.float32) / 255.0
    rgb = arr[..., :3]
    existing_alpha = arr[..., 3]

    background = _background_field(rgb)
    distance = np.linalg.norm(rgb - background, axis=2)
    mask = foreground_mask(rgb) if distance_threshold == 0.075 else distance > distance_threshold
    if distance_threshold != 0.075:
        mask = ndimage.binary_closing(mask, structure=np.ones((5, 5), dtype=bool))

    # Hard-key corner navy / near-black plate (Codex + Blender fringe).
    corners = np.stack([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]])
    plate_rgb = np.median(corners, axis=0)
    plate_dist = np.linalg.norm(rgb - plate_rgb, axis=2)
    mask &= plate_dist > 0.055
    mask &= rgb.max(axis=2) > 0.10

    # Codex graded navy plate — blue-dominant dark pixels.
    navy = (
        (rgb[..., 2] > rgb[..., 0] + 0.03)
        & (rgb[..., 2] > rgb[..., 1] + 0.02)
        & (rgb.max(axis=2) < 0.22)
    )
    mask &= ~navy

    # Respect alpha from transparent-film Blender bakes.
    if had_alpha:
        mask &= existing_alpha > 0.05

    rgba = np.zeros((*rgb.shape[:2], 4), dtype=np.uint8)
    rgba[..., :3] = (np.clip(rgb, 0.0, 1.0) * 255.0).astype(np.uint8)
    rgba[..., 3] = np.where(mask, 255, 0).astype(np.uint8)

    # Feather cutout edge.
    alpha = rgba[..., 3].astype(np.float32) / 255.0
    edge = ndimage.gaussian_filter(alpha, sigma=0.55)
    rgba[..., 3] = np.where(mask, np.clip(edge * 255.0, 0, 255).astype(np.uint8), 0)

    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(path, "PNG")


def key_tree(root: str | Path) -> int:
    """Key every PNG under root; returns count processed."""
    count = 0
    for path in sorted(Path(root).rglob("*.png")):
        key_codex_plate_to_rgba(path)
        count += 1
    return count
