#!/usr/bin/env python3
"""Quantified concept-parity comparison for the Foundation Sunwoven Weaver.

This report is intentionally separate from the Blender-to-GLB round-trip
report.  It compares the committed Foundation crop and the matched loaded-walk
render after a same-height ImageMagick normalization.  The source is painted,
so the result is a measured art-direction gate, not a pixel-identity claim.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
BUILD = HERE / "build"
RENDER = BUILD / "renders" / "canonical-match-sunwoven.png"
MANIFEST_PATH = HERE / "manifest" / "sunwoven-canonical-crop.json"
CONSTRUCTION_REFS_PATH = HERE / "manifest" / "sunwoven-codex-construction-refs.json"
OUT_PATH = BUILD / "canonical-comparison-sunwoven.json"
SHEET_DIR = BUILD / "reference-sheets"
SHEET_PATH = SHEET_DIR / "canonical-comparison-sunwoven.png"
QA_SHEET_DIR = BUILD / "qa-visual-sunwoven"

CANVAS_SIZE = 1400
IOU_THRESHOLD = 0.99
BACKGROUND = (5, 8, 20)
BUCKETS = ("cream", "leather_tan", "teal", "skin", "dark", "bronze")
PALETTE = np.array(
    [
        (0.77, 0.68, 0.52),
        (0.50, 0.30, 0.15),
        (0.08, 0.40, 0.37),
        (0.56, 0.33, 0.23),
        (0.12, 0.09, 0.07),
        (0.62, 0.34, 0.13),
    ],
    dtype=np.float32,
)


def run_magick(args: list[str]) -> None:
    subprocess.run(["magick", *args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def _background_field(image: np.ndarray, corner_size: int = 16) -> np.ndarray:
    """Fit the navy plate from corner patches before any canvas padding."""
    height, width, _ = image.shape
    size = max(4, min(corner_size, height // 8, width // 8))
    patches = [
        (slice(0, size), slice(0, size)),
        (slice(0, size), slice(width - size, width)),
        (slice(height - size, height), slice(0, size)),
        (slice(height - size, height), slice(width - size, width)),
    ]
    rows = []
    values = []
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


def _pad_normalized(pre: np.ndarray, pre_mask: np.ndarray, background: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Center a pre-normalized plate and its mask on the comparison canvas."""
    height, width, _ = pre.shape
    if height != CANVAS_SIZE:
        raise ValueError(f"normalization height must be {CANVAS_SIZE}, got {height}")
    canvas = np.empty((CANVAS_SIZE, CANVAS_SIZE, 3), dtype=np.float32)
    canvas[:] = np.median(background.reshape(-1, 3), axis=0)
    mask = np.zeros((CANVAS_SIZE, CANVAS_SIZE), dtype=bool)
    x0 = (CANVAS_SIZE - width) // 2
    x1 = x0 + width
    canvas[:, x0:x1] = pre
    mask[:, x0:x1] = pre_mask
    return canvas, mask


def load_normalized_pair(reference_path: Path, render_path: Path, crop_geometry: str | None = None) -> tuple[np.ndarray, np.ndarray, dict, np.ndarray, np.ndarray]:
    with tempfile.TemporaryDirectory(prefix="sunwoven-compare-") as temp:
        temp_path = Path(temp)
        reference_pre_path = temp_path / "reference-pre.png"
        render_pre_path = temp_path / "render-pre.png"
        ref_cmd = [str(reference_path)]
        if crop_geometry:
            ref_cmd.extend(["-crop", crop_geometry, "+repage"])
        ref_cmd.extend(["-resize", f"x{CANVAS_SIZE}", str(reference_pre_path)])
        run_magick(ref_cmd)
        run_magick([str(render_path), "-resize", f"x{CANVAS_SIZE}", str(render_pre_path)])
        reference_pre = np.asarray(Image.open(reference_pre_path).convert("RGB"), dtype=np.float32) / 255.0
        render_pre = np.asarray(Image.open(render_pre_path).convert("RGB"), dtype=np.float32) / 255.0
    reference_background = _background_field(reference_pre)
    render_background = _background_field(render_pre)
    reference_pre_mask = foreground_mask(reference_pre, reference_background)
    render_pre_mask = foreground_mask(render_pre, render_background)
    reference, reference_mask = _pad_normalized(reference_pre, reference_pre_mask, reference_background)
    render, render_mask = _pad_normalized(render_pre, render_pre_mask, render_background)
    normalization = {
        "canvas_px": CANVAS_SIZE,
        "background_estimation": "per-image corner-plane sampled before extent padding",
    }
    if crop_geometry:
        normalization["crop_geometry"] = crop_geometry
    return reference, render, normalization, reference_mask, render_mask


def load_normalized_images() -> tuple[np.ndarray, np.ndarray, dict, np.ndarray, np.ndarray]:
    manifest = json.loads(MANIFEST_PATH.read_text())
    source = REPO / manifest["source"]
    crop = manifest["crop_px"]
    geometry = f'{crop["width"]}x{crop["height"]}+{crop["x"]}+{crop["y"]}'
    return load_normalized_pair(source, RENDER, geometry)


def foreground_mask(image: np.ndarray, background: np.ndarray | None = None) -> np.ndarray:
    if background is None:
        background = _background_field(image)
    distance = np.linalg.norm(image - background, axis=2)
    raw = distance > 0.075
    raw[:8] = False
    raw[-8:] = False
    # Close small antialiasing gaps in the painted/rendered figure, then retain
    # all meaningful components except long ground lines and tiny noise.
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


def bbox(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return 0, 0, 0, 0
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def center_mask(mask: np.ndarray) -> np.ndarray:
    x0, y0, x1, y1 = bbox(mask)
    if x1 <= x0 or y1 <= y0:
        return mask
    target_x = mask.shape[1] // 2
    target_y = int(mask.shape[0] * 0.50)
    shift_x = target_x - (x0 + x1) // 2
    shift_y = target_y - (y0 + y1) // 2
    return ndimage.shift(mask.astype(np.uint8), (shift_y, shift_x), order=0, mode="constant", cval=0).astype(bool)


def profile(mask: np.ndarray) -> np.ndarray:
    x0, y0, x1, y1 = bbox(mask)
    values = mask[y0:y1].sum(axis=1).astype(np.float32)
    if len(values) < 2:
        return np.zeros(256, dtype=np.float32)
    values /= max(values.max(), 1.0)
    return np.interp(np.linspace(0, len(values) - 1, 256), np.arange(len(values)), values)


def bucket_shares(image: np.ndarray, mask: np.ndarray) -> dict[str, float]:
    pixels = image[mask]
    if len(pixels) == 0:
        return {name: 0.0 for name in BUCKETS}
    distances = ((pixels[:, None, :] - PALETTE[None, :, :]) ** 2).sum(axis=2)
    nearest = np.argmin(distances, axis=1)
    return {name: float(np.mean(nearest == index)) for index, name in enumerate(BUCKETS)}


def top_cream_and_skin(image: np.ndarray, mask: np.ndarray) -> tuple[bool, float, dict[str, float]]:
    x0, y0, x1, y1 = bbox(mask)
    top_end = y0 + max(1, int((y1 - y0) * 0.12))
    top_mask = mask.copy()
    top_mask[top_end:] = False
    shares = bucket_shares(image, top_mask)
    all_shares = bucket_shares(image, mask)
    dominant = shares["cream"] >= max(shares.values())
    return bool(dominant), all_shares["skin"], shares


def dssim(reference: np.ndarray, render: np.ndarray, mask: np.ndarray) -> tuple[float, float]:
    ref_gray = np.dot(reference, np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))
    render_gray = np.dot(render, np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))
    if not np.any(mask):
        return 1.0, 1.0
    ref_values = ref_gray[mask]
    render_values = render_gray[mask]
    ref_norm = (ref_gray - ref_values.mean()) / max(ref_values.std(), 1e-6)
    render_norm = (render_gray - render_values.mean()) / max(render_values.std(), 1e-6)
    c1, c2 = 0.01 ** 2, 0.03 ** 2
    local = (2.0 * ref_norm * render_norm + c2) / (ref_norm ** 2 + render_norm ** 2 + c2)
    ssim = float(np.clip(np.mean(local[mask]), -1.0, 1.0))
    rmse = float(np.sqrt(np.mean((ref_norm[mask] - render_norm[mask]) ** 2)))
    return float((1.0 - ssim) / 2.0), rmse


def write_sheet(reference: np.ndarray, render: np.ndarray, ref_mask: np.ndarray, render_mask: np.ndarray) -> None:
    SHEET_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sunwoven-sheet-") as temp:
        temp_path = Path(temp)
        ref_path = temp_path / "reference.png"
        render_path = temp_path / "render.png"
        mask_path = temp_path / "mask.png"
        Image.fromarray(np.uint8(np.clip(reference * 255.0, 0, 255)), "RGB").save(ref_path)
        Image.fromarray(np.uint8(np.clip(render * 255.0, 0, 255)), "RGB").save(render_path)
        aligned = np.zeros((*ref_mask.shape, 3), dtype=np.uint8)
        aligned[..., 0] = ref_mask * 255
        aligned[..., 1] = render_mask * 255
        aligned[..., 2] = render_mask * 255
        Image.fromarray(aligned, "RGB").save(mask_path)
        run_magick([str(ref_path), str(render_path), "+append", str(SHEET_PATH)])
        # Keep the machine-readable mask beside the report for human review.
        Image.fromarray(aligned, "RGB").save(SHEET_DIR / "canonical-comparison-mask-sunwoven.png")


def compute_metrics(reference: np.ndarray, render: np.ndarray, ref_mask: np.ndarray, render_mask: np.ndarray) -> tuple[dict, dict]:
    for name, mask in (("reference", ref_mask), ("render", render_mask)):
        area = float(mask.mean())
        if not 0.04 <= area <= 0.55:
            raise SystemExit(f"foreground mask sanity failure for {name}: area_ratio={area:.6f}; expected 0.04..0.55")
    aligned_ref = center_mask(ref_mask)
    aligned_render = center_mask(render_mask)
    union = aligned_ref | aligned_render
    intersection = aligned_ref & aligned_render
    ref_box = bbox(ref_mask)
    render_box = bbox(render_mask)
    ref_aspect = (ref_box[2] - ref_box[0]) / max(1, ref_box[3] - ref_box[1])
    render_aspect = (render_box[2] - render_box[0]) / max(1, render_box[3] - render_box[1])
    ref_profile = profile(ref_mask)
    render_profile = profile(render_mask)
    profile_corr = (
        float(np.corrcoef(ref_profile, render_profile)[0, 1])
        if np.std(ref_profile) > 1e-6 and np.std(render_profile) > 1e-6
        else None
    )
    ref_colors = bucket_shares(reference, ref_mask)
    render_colors = bucket_shares(render, render_mask)
    color_delta = {name: abs(render_colors[name] - ref_colors[name]) for name in BUCKETS}
    cream_dominant, skin_share, top_shares = top_cream_and_skin(render, render_mask)
    score_mask = ndimage.binary_dilation(union, structure=np.ones((5, 5), dtype=bool))
    dssim_value, rmse_value = dssim(reference, render, score_mask)
    metrics = {
        "silhouette_mask_iou": float(intersection.sum() / max(1, union.sum())),
        "silhouette_aspect_ratio": {
            "reference_width_over_height": float(ref_aspect),
            "render_width_over_height": float(render_aspect),
            "relative_delta": float(abs(render_aspect / max(ref_aspect, 1e-6) - 1.0)),
        },
        "vertical_mass_profile_correlation": profile_corr,
        "color_region_share": {
            "reference": ref_colors,
            "render": render_colors,
            "absolute_delta": color_delta,
        },
        "dssim_masked_contrast_normalized_grayscale": dssim_value,
        "rmse_masked_contrast_normalized_grayscale": rmse_value,
        "top_mask_12_percent": {
            "cream_dominant": cream_dominant,
            "render_bucket_shares": top_shares,
        },
        "skin_hue_region_share": skin_share,
        "bounding_boxes": {"reference": ref_box, "render": render_box},
    }
    gates = {
        "1_silhouette_mask_iou": {"threshold": IOU_THRESHOLD, "actual": metrics["silhouette_mask_iou"], "passed": metrics["silhouette_mask_iou"] >= IOU_THRESHOLD},
        "2_silhouette_aspect_ratio": {"threshold_relative_delta": 0.08, "actual_relative_delta": metrics["silhouette_aspect_ratio"]["relative_delta"], "passed": metrics["silhouette_aspect_ratio"]["relative_delta"] <= 0.08},
        "3_vertical_mass_profile_correlation": {
            "threshold": 0.90,
            "actual": profile_corr,
            "passed": profile_corr is not None and profile_corr >= 0.90,
            "degenerate": profile_corr is None,
        },
        "4_color_region_share": {"threshold_absolute_delta": 0.08, "actual_absolute_delta": color_delta, "passed": all(delta <= 0.08 for delta in color_delta.values())},
        "5_dssim": {"threshold": 0.35, "actual": dssim_value, "passed": dssim_value <= 0.35},
        "6_face_and_headwrap": {"cream_dominant_top_12_percent": cream_dominant, "skin_share_threshold": 0.02, "skin_share_actual": skin_share, "passed": cream_dominant and skin_share >= 0.02},
    }
    return metrics, gates


def write_sheet_to(reference: np.ndarray, render: np.ndarray, ref_mask: np.ndarray, render_mask: np.ndarray, sheet_path: Path) -> None:
    sheet_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sunwoven-sheet-") as temp:
        temp_path = Path(temp)
        ref_path = temp_path / "reference.png"
        render_path = temp_path / "render.png"
        Image.fromarray(np.uint8(np.clip(reference * 255.0, 0, 255)), "RGB").save(ref_path)
        Image.fromarray(np.uint8(np.clip(render * 255.0, 0, 255)), "RGB").save(render_path)
        run_magick([str(ref_path), str(render_path), "+append", str(sheet_path)])


def crop_render_to_foreground(render_path: Path, margin: int = 24) -> Path:
    """Tight-crop an isolated turnaround to its foreground bbox (side-view parity)."""
    img = Image.open(render_path).convert("RGB")
    arr = np.asarray(img, dtype=np.float32) / 255.0
    mask = foreground_mask(arr)
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return render_path
    x0, x1 = max(0, int(xs.min()) - margin), min(img.width, int(xs.max()) + 1 + margin)
    y0, y1 = max(0, int(ys.min()) - margin), min(img.height, int(ys.max()) + 1 + margin)
    cropped = img.crop((x0, y0, x1, y1))
    temp = render_path.parent / f"{render_path.stem}-cropped.png"
    cropped.save(temp)
    return temp


def compare_view(
    view: str,
    reference_path: Path,
    render_path: Path,
    crop_geometry: str | None = None,
    render_foreground_crop: bool = False,
) -> dict:
    effective_render = crop_render_to_foreground(render_path) if render_foreground_crop else render_path
    reference, render, normalization, ref_mask, render_mask = load_normalized_pair(
        reference_path, effective_render, crop_geometry,
    )
    metrics, gates = compute_metrics(reference, render, ref_mask, render_mask)
    sheet_path = QA_SHEET_DIR / f"codex-comparison-{view}.png"
    write_sheet_to(reference, render, center_mask(ref_mask), center_mask(render_mask), sheet_path)
    return {
        "view": view,
        "reference": str(reference_path.relative_to(REPO)),
        "render": str(render_path.relative_to(REPO)),
        "normalization": normalization,
        "metrics": metrics,
        "gates": gates,
        "passed": all(gate["passed"] for gate in gates.values()),
        "comparison_sheet": str(sheet_path.relative_to(REPO)),
    }


def main() -> int:
    construction = json.loads(CONSTRUCTION_REFS_PATH.read_text())
    view_reports = {}
    for view, ref_entry in construction["references"].items():
        render_key = "back" if view == "back" else view
        render_rel = construction["renders"][render_key]
        if isinstance(ref_entry, str):
            ref_rel = ref_entry
            crop_geometry = None
            render_foreground_crop = False
        else:
            ref_rel = ref_entry["path"]
            crop = ref_entry.get("crop_px")
            crop_geometry = None
            if crop:
                crop_geometry = f'{crop["width"]}x{crop["height"]}+{crop["x"]}+{crop["y"]}'
            render_foreground_crop = bool(ref_entry.get("render_foreground_crop", False))
        ref_path = REPO / ref_rel
        render_path = REPO / render_rel
        if not ref_path.exists():
            raise SystemExit(f"Codex reference missing: {ref_path}")
        if not render_path.exists():
            raise SystemExit(f"turnaround render missing: {render_path}")
        view_reports[view] = compare_view(view, ref_path, render_path, crop_geometry, render_foreground_crop)

    primary_view = construction.get("primary_gate_view", "front")
    primary = view_reports[primary_view]
    legacy_metrics = legacy_gates = None
    if RENDER.exists() and MANIFEST_PATH.exists():
        reference, render, _normalization, ref_mask, render_mask = load_normalized_images()
        legacy_metrics, legacy_gates = compute_metrics(reference, render, ref_mask, render_mask)
        write_sheet(reference, render, center_mask(ref_mask), center_mask(render_mask))

    report = {
        "schema": "sunfold.sunwoven.canonical-comparison/2",
        "status": "codex_construction_gate",
        "inputs": {
            "construction_refs": str(CONSTRUCTION_REFS_PATH.relative_to(REPO)),
            "primary_gate_view": primary_view,
            "legacy_reference": str(MANIFEST_PATH.relative_to(REPO)),
            "legacy_render": str(RENDER.relative_to(REPO)),
        },
        "computation": {
            "path": "ImageMagick 7 normalization + Pillow/numpy/scipy metrics",
            "textures": 0,
            "note": "Primary gate compares authored T-pose turnarounds against Aug 2026 Codex construction sheets.",
        },
        "views": view_reports,
        "metrics": primary["metrics"],
        "gates": primary["gates"],
        "legacy_evolution_crop": {"metrics": legacy_metrics, "gates": legacy_gates} if legacy_metrics is not None else None,
        "passed": primary["passed"],
        "comparison_sheet": primary["comparison_sheet"],
    }
    OUT_PATH.write_text(json.dumps(report, indent=2) + "\n")
    QA_SHEET_DIR.mkdir(parents=True, exist_ok=True)
    (QA_SHEET_DIR / "canonical-comparison-sunwoven.json").write_text(json.dumps(report, indent=2) + "\n")
    shutil.copy2(REPO / primary["comparison_sheet"], QA_SHEET_DIR / "canonical-comparison-sunwoven.png")
    print(json.dumps(report, indent=2))
    print(f"[compare_canonical] wrote {OUT_PATH}")
    for view, result in view_reports.items():
        print(f"[compare_canonical] {view} IoU={result['metrics']['silhouette_mask_iou']:.4f} passed={result['passed']}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
