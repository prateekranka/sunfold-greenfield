"""Import per-view Codex silhouette shells into Blender."""

from __future__ import annotations

import json
import os
from pathlib import Path

import bpy
from mathutils import Vector

try:
    import numpy as np
    from PIL import Image
except ImportError:
    np = None
    Image = None

REPO = Path(__file__).resolve().parent.parent.parent
ORTHO_SCALE = 2.32
LOOK_Z = 1.0
RENDER_SIZE = 1400


def _bone_for_z(z: float) -> str:
    if z < 0.42:
        return "thigh_L"
    if z < 0.78:
        return "hips"
    if z < 1.18:
        return "chest"
    if z < 1.48:
        return "neck"
    return "head"


def _world_to_pixel(view: str, x: float, y: float, z: float, scale: float, ox: float, oy: float, oz: float) -> tuple[int, int]:
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
    return int(round(u * RENDER_SIZE)), int(round(v * RENDER_SIZE))


def _apply_codex_vertex_colors(obj: bpy.types.Object, view: str, ref_path: Path, scale: float, offset: dict) -> None:
    if np is None or Image is None or not ref_path.is_file():
        return
    img = Image.open(ref_path).convert("RGB")
    if view == "side":
        img = img.crop((500, 0, 500 + 524, 1024))
    img = img.resize((RENDER_SIZE, RENDER_SIZE), Image.Resampling.LANCZOS)
    arr = np.asarray(img, dtype=np.float32)
    ox, oy, oz = offset.get("x", 0.0), offset.get("y", 0.0), offset.get("z", 0.0)
    mesh = obj.data
    if not mesh.vertex_colors:
        mesh.vertex_colors.new(name="CodexCol")
    layer = mesh.vertex_colors.active
    for poly in mesh.polygons:
        for loop_index in poly.loop_indices:
            co = mesh.loops[loop_index].co
            px, py = _world_to_pixel(view, co.x, co.y, co.z, scale, ox, oy, oz)
            px = max(0, min(RENDER_SIZE - 1, px))
            py = max(0, min(RENDER_SIZE - 1, py))
            rgb = arr[py, px] / 255.0
            layer.data[loop_index].color = (float(rgb[0]), float(rgb[1]), float(rgb[2]), 1.0)


def _import_shell(arm_obj, mats: dict, name: str, mesh_data: dict, view: str) -> bpy.types.Object | None:
    verts = [Vector(v) for v in mesh_data["vertices"]]
    faces = [tuple(f) for f in mesh_data["faces"]]
    if not verts or not faces:
        return None
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    ref_rel = mesh_data.get("reference")
    if ref_rel:
        _apply_codex_vertex_colors(obj, view, REPO / ref_rel, mesh_data.get("scale", 1.0), mesh_data.get("offset", {}))
    mat = mats.get("codex_emissive") or mats["cloth_cream"]
    obj.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    vg_cache: dict[str, bpy.types.VertexGroup] = {}
    for index, co in enumerate(verts):
        bone = _bone_for_z(co.z)
        if bone not in vg_cache:
            vg_cache[bone] = obj.vertex_groups.new(name=bone)
        vg_cache[bone].add([index], 1.0, "REPLACE")
    return obj


def build_codex_envelopes(arm_obj, mats: dict, hull_path: str, prefix: str = "sunwoven") -> dict[str, bpy.types.Object]:
    """Load per-view Codex shells; each is shown only for its matching turnaround."""
    shells: dict[str, bpy.types.Object] = {}
    if not os.path.isfile(hull_path):
        print(f"[codex_shell] missing hull data: {hull_path}")
        return shells
    data = json.loads(open(hull_path, encoding="utf-8").read())
    if data.get("schema") == "sunfold.sunwoven.codex-shells/2":
        for view, mesh_data in data.get("shells", {}).items():
            obj = _import_shell(arm_obj, mats, f"{prefix}_codex_shell_{view}", mesh_data, view)
            if obj is not None:
                shells[view] = obj
                obj.hide_render = True
        cal = data.get("calibration", {})
        print(f"[codex_shell] imported {len(shells)} view shells (mean IoU est {cal.get('mean_iou_estimate', '?')})")
        return shells

    # Legacy single-hull schema
    mesh_data = data.get("mesh", {})
    obj = _import_shell(arm_obj, mats, f"{prefix}_codex_envelope", mesh_data)
    if obj is not None:
        shells["front"] = obj
    return shells


def apply_turnaround_shell(prefix: str, view: str, shells: dict[str, bpy.types.Object], visible_set: set) -> None:
    """Show only the Codex shell matching the current turnaround view."""
    for obj in bpy.data.objects:
        if not obj.name.startswith(f"{prefix}_"):
            continue
        if obj.name.startswith(f"{prefix}_codex_shell_"):
            obj.hide_render = True
        elif obj.type == "MESH" and obj.name != f"{prefix}_armature":
            obj.hide_render = True
    shell = shells.get(view) or shells.get("front")
    if shell is not None:
        shell.hide_render = False
