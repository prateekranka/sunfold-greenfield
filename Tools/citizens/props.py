"""B23-PROPS — the identical, unstyled neutral-lab props.

One prop set per citizen workstation, built from the same geometry so the
comparison lab stays neutral (no faction palette, no faction styling). All
props are static meshes; tools sit at their rests and are authored into
clips only while carried.

Layout (Blender space, citizen at origin faces -Y; character LEFT = +X,
character RIGHT = -X):
  * source pile     : front-right  (3 loose chunks)
  * deposit target  : ahead        (low ring pad)
  * construction    : front-left   (three-piece waist-high frame)
  * scraper rest    : right side   (waist-high, one-handed scraper)
  * mallet rest     : left side    (waist-high, one-handed mallet)

`build_prop_set(origin_x)` returns every prop translated by (+origin_x, 0, 0)
so the broad citizen's workstation mirrors the slender one's exactly.
"""

from __future__ import annotations

import bpy
import math
from mathutils import Euler, Matrix, Vector

from skin import _material, box_geometry

NEUTRAL_GROUND = 0x3A3835
NEUTRAL_CHUNK = 0x7C7668
NEUTRAL_TARGET_PAD = 0x6A665B
NEUTRAL_TARGET_RING = 0x5C594F
NEUTRAL_FRAME = 0x77725F
NEUTRAL_REST = 0x625E52


def _mesh_object(name: str, verts, faces, hex_color: int, roughness: float, metallic: float) -> bpy.types.Object:
    data = bpy.data.meshes.new(name + "_mesh")
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    data.materials.append(_material(name + "_mat", hex_color, roughness, metallic))
    return obj


def _capped_cylinder(name: str, radius: float, depth: float, hex_color: int, roughness: float) -> bpy.types.Object:
    """Capped cylinder built with from_pydata and triangulated caps.

    The caps are emitted as triangle fans, never as one large n-gon: EEVEE
    in this Blender 5.2 build renders black for any scene containing a mesh
    with a large n-gon face (probed: 48-gon caps, and any bmesh.to_mesh
    object, made every other object vanish).
    """
    segs = 48
    half = depth / 2.0
    verts = []
    for ring in (0, 1):
        z = -half if ring == 0 else half
        for i in range(segs):
            a = 2.0 * math.pi * i / segs
            verts.append(Vector((radius * math.cos(a), radius * math.sin(a), z)))
    faces = []
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((i, j, segs + j, segs + i))  # side quad
    for i in range(segs - 2):
        faces.append((0, i + 2, i + 1))  # bottom cap fan
    for i in range(segs - 2):
        faces.append((segs, segs + i + 1, segs + i + 2))  # top cap fan
    return _mesh_object(name, verts, faces, hex_color, roughness, 0.0)


def build_ground(origin_x: float = 0.0, name: str = "lab_ground") -> bpy.types.Object:
    """Flat neutral pad under a workstation (r = 5.5, 0.12 thick)."""
    obj = _capped_cylinder(name, 5.5, 0.12, NEUTRAL_GROUND, 0.94)
    obj.location = (origin_x, 0.0, -0.06)
    return obj


def build_source_pile(origin_x: float = 0.0, name: str = "source_pile") -> list[bpy.types.Object]:
    """Three loose low-poly chunks front-right of the gather workstation."""
    chunks = []
    placements = [
        ((0.0, 0.0, 0.14), Euler((0.2, -0.35, 0.1), "XYZ"), (0.20, 0.16, 0.14)),
        ((0.24, 0.10, 0.10), Euler((0.6, 0.4, 0.7), "XYZ"), (0.16, 0.20, 0.12)),
        ((-0.22, 0.16, 0.09), Euler((-0.5, 0.2, -0.4), "XYZ"), (0.15, 0.14, 0.16)),
    ]
    for i, (offset, rot, half) in enumerate(placements):
        verts, faces = box_geometry(Vector((0.0, 0.0, 0.0)), Vector(half), Matrix.Identity(3))
        # skew a few corners so each chunk reads as a loose rock, not a crate
        verts[0] += Vector((0.04, 0.03, -0.02))
        verts[3] += Vector((-0.03, 0.05, 0.02))
        verts[5] += Vector((0.05, -0.04, 0.03))
        obj = _mesh_object(f"{name}_{i}", verts, faces, NEUTRAL_CHUNK, 0.92, 0.0)
        obj.rotation_euler = rot
        obj.location = (origin_x + offset[0] - 0.55, -1.2 + offset[1], offset[2])
        chunks.append(obj)
    return chunks


def build_deposit_target(origin_x: float = 0.0, name: str = "deposit_target") -> list[bpy.types.Object]:
    """Low neutral ring pad the citizen dumps into."""
    pad = _capped_cylinder(name + "_pad", 0.95, 0.06, NEUTRAL_TARGET_PAD, 0.8)
    pad.location = (origin_x - 0.2, -2.7, 0.0)
    ring_verts, ring_faces = box_geometry(Vector((0.0, 0.0, 0.0)), Vector((0.50, 0.035, 0.05)), Matrix.Identity(3))
    ring = _mesh_object(name + "_ring", ring_verts, ring_faces, NEUTRAL_TARGET_RING, 0.6, 0.2)
    ring.location = (origin_x - 0.2, -2.7, 0.10)
    return [pad, ring]


def build_construction_frame(origin_x: float = 0.0, name: str = "construction_frame") -> list[bpy.types.Object]:
    """Three-piece waist-high construction frame (three separate components)."""
    pieces = []
    half_h = 0.475  # waist-high frame: 0.95 m tall
    positions = [(-0.55, 0.0), (0.55, 0.0), (0.0, -0.62)]
    for i, (px, py) in enumerate(positions):
        verts, faces = [], []
        if i < 2:
            v, f = box_geometry(Vector((0.0, 0.0, 0.0)), Vector((0.07, half_h, 0.07)), Matrix.Identity(3))
            verts.extend(v)
            faces.extend(f)
            base = len(verts)
            v2, f2 = box_geometry(Vector((0.0, half_h, 0.0)), Vector((0.05, 0.05, 0.05)), Matrix.Identity(3))
            verts.extend(v2)
            faces.extend(tuple(base + j for j in quad) for quad in f2)
        else:
            v, f = box_geometry(Vector((0.0, 0.0, 0.0)), Vector((0.72, 0.07, 0.07)), Matrix.Identity(3))
            verts.extend(v)
            faces.extend(f)
            for sx in (-0.55, 0.55):
                base = len(verts)
                v2, f2 = box_geometry(Vector((sx, 0.0, 0.0)), Vector((0.05, 0.09, 0.05)), Matrix.Identity(3))
                verts.extend(v2)
                faces.extend(tuple(base + j for j in quad) for quad in f2)
        obj = _mesh_object(f"{name}_{i}", verts, faces, NEUTRAL_FRAME, 0.78, 0.08)
        obj.location = (origin_x + px + 0.55, -1.6 + py, 0.0)
        pieces.append(obj)
    return pieces


def build_rest(origin_x: float = 0.0, side: str = "R", kind: str = "scraper", prefix: str = "") -> bpy.types.Object:
    """Waist-high tool rest (post + rack) at the citizen's side.

    side "R" sits on the character's right (-X), "L" on the left (+X).
    """
    sx = -1.0 if side == "R" else 1.0
    verts, faces = [], []
    v, f = box_geometry(Vector((0.0, 0.0, 0.0)), Vector((0.05, 0.40, 0.05)), Matrix.Identity(3))
    verts.extend(v)
    faces.extend(f)
    base = len(verts)
    v2, f2 = box_geometry(Vector((-0.30 * sx, 0.0, 0.0)), Vector((0.30, 0.04, 0.06)), Matrix.Identity(3))
    verts.extend(v2)
    faces.extend(tuple(base + j for j in quad) for quad in f2)
    obj = _mesh_object(f"{prefix}_rest_{side}_{kind}", verts, faces, NEUTRAL_REST, 0.8, 0.05)
    obj.location = (origin_x + 1.28 * sx, -0.45, 0.92)
    return obj


def build_prop_set(origin_x: float = 0.0, prefix: str = "slender") -> dict:
    """One full workstation prop set, translated to `origin_x`."""
    return {
        "ground": build_ground(origin_x, name=f"{prefix}_ground"),
        "source_pile": build_source_pile(origin_x, name=f"{prefix}_source_pile"),
        "deposit_target": build_deposit_target(origin_x, name=f"{prefix}_deposit_target"),
        "construction_frame": build_construction_frame(origin_x, name=f"{prefix}_construction_frame"),
        "rest_scraper": build_rest(origin_x, "R", "scraper", prefix),
        "rest_mallet": build_rest(origin_x, "L", "mallet", prefix),
    }
