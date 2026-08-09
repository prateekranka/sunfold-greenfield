#!/usr/bin/env python3
"""Forward kinematics and compositing for the 2D cutout villager.

Every part is a cropped RGBA layer plus a pivot. A pose gives each part a local
rotation in degrees and the root a translation, and this module resolves the
chain into one affine per part and paints them in z order.

Rotations are isotropic, so all maths happens in figure *pixels*, never in the
normalized units the rig is authored in (the figure box is not square, and
rotating in normalized space would shear every limb).

Angle sign: positive is counter-clockwise as seen on screen.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

Matrix = tuple[float, float, float, float, float, float]  # a b c / d e f, affine 2x3

IDENTITY: Matrix = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0)


def multiply(m: Matrix, n: Matrix) -> Matrix:
    a, b, c, d, e, f = m
    p, q, r, s, t, u = n
    return (
        a * p + b * s, a * q + b * t, a * r + b * u + c,
        d * p + e * s, d * q + e * t, d * r + e * u + f,
    )


def translation(dx: float, dy: float) -> Matrix:
    return (1.0, 0.0, dx, 0.0, 1.0, dy)


def rotation(degrees: float) -> Matrix:
    """Counter-clockwise on screen, in an image space whose y axis points down."""
    radians = math.radians(degrees)
    cos, sin = math.cos(radians), math.sin(radians)
    return (cos, sin, 0.0, -sin, cos, 0.0)


def scaling(sx: float, sy: float) -> Matrix:
    return (sx, 0.0, 0.0, 0.0, sy, 0.0)


def invert(m: Matrix) -> Matrix:
    a, b, c, d, e, f = m
    det = a * e - b * d
    if abs(det) < 1e-12:
        raise ValueError("singular affine")
    ia, ib = e / det, -b / det
    id_, ie = -d / det, a / det
    return (ia, ib, -(ia * c + ib * f), id_, ie, -(id_ * c + ie * f))


def apply(m: Matrix, x: float, y: float) -> tuple[float, float]:
    a, b, c, d, e, f = m
    return (a * x + b * y + c, d * x + e * y + f)


@dataclass
class Part:
    id: str
    parent: str | None
    z: int
    image: Image.Image
    offset_px: tuple[float, float]
    pivot_px: tuple[float, float]
    rest_angle: float = 0.0


@dataclass
class Rig:
    view: str
    width: int
    height: int
    ground_line: float
    centre_line: float
    parts: dict[str, Part]
    order: list[str]

    @property
    def ground_px(self) -> float:
        return self.ground_line * self.height

    @property
    def centre_px(self) -> float:
        return self.centre_line * self.width


def load_rig(parts_dir: Path) -> Rig:
    manifest = json.loads((parts_dir / "parts.json").read_text())
    w, h = manifest["figurePixelSize"]
    parts: dict[str, Part] = {}
    for record in manifest["parts"]:
        parts[record["id"]] = Part(
            id=record["id"],
            parent=record["parent"],
            z=record["z"],
            image=Image.open(parts_dir / record["file"]).convert("RGBA"),
            offset_px=(record["offset"][0] * w, record["offset"][1] * h),
            pivot_px=(record["pivot"][0] * w, record["pivot"][1] * h),
            rest_angle=float(record.get("restAngle", 0.0)),
        )
    order = sorted(parts, key=lambda pid: parts[pid].z)
    return Rig(
        view=manifest["view"],
        width=w,
        height=h,
        ground_line=manifest.get("groundLine", 1.0),
        centre_line=manifest.get("centreLine", 0.5),
        parts=parts,
        order=order,
    )


def resolve_chain(rig: Rig, angles: dict[str, float], root: Matrix) -> dict[str, Matrix]:
    """World affine per part, parents before children.

    `restAngle` is a constant added to every pose angle. The side sheet draws the
    arms spread away from the body, so a pose that says "swing 0" would keep them
    spread; the rest angle folds the drawn rest pose back to a neutral one so a
    single set of clip keys reads the same in every view.
    """
    resolved: dict[str, Matrix] = {}

    def world(part_id: str) -> Matrix:
        if part_id in resolved:
            return resolved[part_id]
        part = rig.parts[part_id]
        base = root if part.parent is None else world(part.parent)
        px, py = part.pivot_px
        angle = angles.get(part_id, 0.0) + part.rest_angle
        local = multiply(translation(px, py), multiply(rotation(angle),
                                                      translation(-px, -py)))
        resolved[part_id] = multiply(base, local)
        return resolved[part_id]

    for part_id in rig.parts:
        world(part_id)
    return resolved


def render_pose(
    rig: Rig,
    pose: dict,
    canvas_size: tuple[int, int],
    figure_origin: tuple[float, float],
    squash: float = 1.0,
    mirror: bool = False,
    hide: tuple[str, ...] = (),
) -> Image.Image:
    """Composite one pose. `squash` narrows the figure to fake a three-quarter turn."""
    angles = pose.get("angles", {})
    dx, dy = pose.get("root", [0.0, 0.0])

    # Figure space -> canvas: optional mirror and horizontal squash about the centre line,
    # then the root translation, then the canvas origin.
    root = translation(figure_origin[0], figure_origin[1])
    root = multiply(root, translation(dx * rig.width, dy * rig.height))
    if squash != 1.0 or mirror:
        sx = (-1.0 if mirror else 1.0) * squash
        root = multiply(root, translation(rig.centre_px, 0.0))
        root = multiply(root, scaling(sx, 1.0))
        root = multiply(root, translation(-rig.centre_px, 0.0))

    world = resolve_chain(rig, angles, root)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))

    for part_id in rig.order:
        if part_id in hide:
            continue
        part = rig.parts[part_id]
        matrix = multiply(world[part_id], translation(*part.offset_px))

        # Rasterize into just the transformed footprint rather than the whole
        # canvas — a full-canvas affine per part per frame is the difference
        # between a bake that takes minutes and one that takes seconds.
        pw, ph = part.image.size
        corners = [apply(matrix, x, y) for x, y in ((0, 0), (pw, 0), (pw, ph), (0, ph))]
        x0 = max(0, int(math.floor(min(c[0] for c in corners))) - 2)
        y0 = max(0, int(math.floor(min(c[1] for c in corners))) - 2)
        x1 = min(canvas_size[0], int(math.ceil(max(c[0] for c in corners))) + 2)
        y1 = min(canvas_size[1], int(math.ceil(max(c[1] for c in corners))) + 2)
        if x1 <= x0 or y1 <= y0:
            continue

        local = multiply(translation(-x0, -y0), matrix)
        layer = part.image.transform(
            (x1 - x0, y1 - y0), Image.AFFINE, invert(local), resample=Image.BICUBIC
        )
        canvas.alpha_composite(layer, (x0, y0))
    return canvas


def content_box(image: Image.Image, floor: int = 4) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    return alpha.point(lambda v: 255 if v > floor else 0).getbbox()
