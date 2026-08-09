"""B23-SKIN — build the neutral mannequin mesh and bind it to a rig armature.

A single mesh object holds every segment box (one box per deform segment in
`rig.segment_table`). Vertex weights are authored deterministically:

* tail corners (t = 1 along the bone) belong to that segment's bone;
* head corners (t = 0) blend toward the parent bone by `head_blend`, so a
  limb joint bends around the parent's tail instead of shearing;
* the blend is skipped when the parent is a non-deform bone (no group).

The carrier accessory (basket / hopper) is a second skinned mesh bound to
`accessory_strap`, so its motion is authored through the clip, never a
runtime physics sim.

Everything is pure geometry + mathutils; no randomness, no imported assets.
"""

from __future__ import annotations

import bpy
from mathutils import Matrix, Vector

from rig import segment_table


def _linear(v: float) -> float:
    """sRGB byte -> linear, for matching hex colors 1:1 with Three.js."""
    c = max(0.0, min(1.0, v))
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(hex_value: int) -> tuple[float, float, float]:
    r = (hex_value >> 16) & 0xFF
    g = (hex_value >> 8) & 0xFF
    b = hex_value & 0xFF
    return (_linear(r / 255.0), _linear(g / 255.0), _linear(b / 255.0))


def box_geometry(
    center: Vector, half: Vector, orient: Matrix
) -> tuple[list[Vector], list[tuple[int, ...]]]:
    """Axis-aligned (in `orient` frame) box, outward CCW winding.

    Corners (sx, sy, sz) in {-,+}^3 ordered:
      0:(-,-,-) 1:(-,-,+) 2:(-,+,-) 3:(-,+,+) 4:(+,-,-) 5:(+,-,+)
      6:(+,+,-) 7:(+,+,+)
    """
    verts = [
        center + orient @ Vector((half.x * sx, half.y * sy, half.z * sz))
        for sy in (-1.0, 1.0)
        for sx in (-1.0, 1.0)
        for sz in (-1.0, 1.0)
    ]
    faces = [
        (0, 2, 3, 1),  # -X
        (4, 5, 7, 6),  # +X
        (0, 1, 5, 4),  # -Y
        (6, 7, 3, 2),  # +Y
        (0, 4, 6, 2),  # -Z
        (1, 3, 7, 5),  # +Z
    ]
    return verts, faces


def _bone_frame(arm_obj, bone_name: str) -> tuple[Vector, Vector, Matrix]:
    """(head, tail, orientation 3x3) of a rest bone in armature space."""
    bone = arm_obj.data.bones[bone_name]
    return bone.head_local.copy(), bone.tail_local.copy(), bone.matrix_local.to_3x3()


def _segment_box(
    head: Vector, tail: Vector, orient: Matrix, half_w: float, half_d: float
) -> tuple[list[Vector], list[tuple[int, ...]]]:
    """Box spanning head..tail with a half_w x half_d cross-section.

    The box's local +Y runs head->tail (the locked joint convention), so
    corners 0..3 sit at the head (t=0) end and corners 4..7 at the tail.
    """
    axis = (tail - head).normalized()
    length = max((tail - head).length, 1e-6)
    x_axis = orient.col[0].normalized()
    z_axis = orient.col[2].normalized()
    if x_axis.length < 1e-6:
        x_axis = Vector((1.0, 0.0, 0.0))
    if z_axis.length < 1e-6:
        z_axis = Vector((0.0, 0.0, 1.0))
    frame = Matrix((x_axis, axis, z_axis)).transposed()
    verts, faces = box_geometry(
        Vector((0.0, length * 0.5, 0.0)), Vector((half_w, length * 0.5, half_d)), Matrix.Identity(3)
    )
    return [head + frame @ v for v in verts], faces


def _material(name: str, hex_color: int, roughness: float, metallic: float):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*hex_to_linear(hex_color), 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def build_mannequin(arm_obj, p: dict[str, float], name: str = "citizen_body") -> bpy.types.Object:
    """Create the skinned body mesh for one citizen and bind it to `arm_obj`."""
    from rig import segment_table

    table = segment_table(p)
    deform_set = {b.name for b in arm_obj.data.bones if b.use_deform}
    parent_of = {eb.name: eb.parent.name for eb in arm_obj.data.bones if eb.parent is not None}

    verts: list[Vector] = []
    faces: list[tuple[int, ...]] = []
    weight_plan: list[list[tuple[str, float]]] = []

    for bone_name, half_w, half_d, head_blend in table:
        if bone_name not in deform_set:
            continue
        head, tail, orient = _bone_frame(arm_obj, bone_name)
        base = len(verts)
        box_verts, box_faces = _segment_box(head, tail, orient, half_w, half_d)
        verts.extend(box_verts)
        faces.extend(tuple(base + i for i in f) for f in box_faces)

        parent = parent_of.get(bone_name)
        parent_weight = 0.0 if parent not in deform_set else head_blend
        my_weight = 1.0 - parent_weight
        for corner in range(8):
            entry: list[tuple[str, float]] = []
            if corner < 4 and parent_weight > 0.0 and parent is not None:
                entry.append((parent, parent_weight))
            entry.append((bone_name, my_weight if corner < 4 else 1.0))
            weight_plan.append(entry)

    mesh_data = bpy.data.meshes.new(name + "_mesh")
    mesh_data.from_pydata(verts, [], faces)
    mesh_data.update()
    mesh_obj = bpy.data.objects.new(name, mesh_data)
    bpy.context.scene.collection.objects.link(mesh_obj)
    mesh_data.materials.append(_material(name + "_mat", 0x8A8578, 0.82, 0.0))

    groups = {}
    for bone_name in sorted(deform_set):
        groups[bone_name] = mesh_obj.vertex_groups.new(name=bone_name)
    for vi, entries in enumerate(weight_plan):
        for bone_name, weight in entries:
            groups[bone_name].add([vi], weight, "ADD")

    mod = mesh_obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj
    mesh_obj.parent = arm_obj
    return mesh_obj


def build_carrier(
    arm_obj,
    p: dict[str, float],
    kind: str,  # "basket" (slender) | "hopper" (broad)
    name: str = "carrier",
) -> bpy.types.Object:
    """Skinned carrier accessory bound 1:1 to `accessory_strap`.

    The accessory_strap bone hangs from the upper-back carrier socket; the
    carrier mesh is built around that bone's rest frame so its motion is
    entirely clip-authored (no runtime physics).
    """
    strap = arm_obj.data.bones["accessory_strap"]
    orient = strap.matrix_local.to_3x3()
    head = strap.head_local.copy()
    tail = strap.tail_local.copy()
    length = max((tail - head).length, 1e-6)
    axis = (tail - head).normalized()

    if kind == "basket":
        half_w, half_d, half_h = 0.20, 0.15, 0.17
        center_t = 0.55
        color = 0x6E6A5E
    else:
        half_w, half_d, half_h = 0.23, 0.17, 0.20
        center_t = 0.55
        color = 0x58545C

    center = head + axis * (length * center_t)
    frame = Matrix((orient.col[0].normalized(), axis, orient.col[2].normalized())).transposed()
    verts, faces = box_geometry(Vector((0.0, 0.0, 0.0)), Vector((half_w, half_h, half_d)), Matrix.Identity(3))
    world_verts = [center + frame @ v for v in verts]

    mesh_data = bpy.data.meshes.new(name + "_mesh")
    mesh_data.from_pydata(world_verts, [], faces)
    mesh_data.update()

    obj = bpy.data.objects.new(name, mesh_data)
    bpy.context.scene.collection.objects.link(obj)
    mesh_data.materials.append(_material(name + "_mat", color, 0.9, 0.0))

    group = obj.vertex_groups.new(name="accessory_strap")
    group.add(range(len(world_verts)), 1.0, "ADD")

    mod = obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj
    obj.parent = arm_obj
    return obj


def build_tool(name: str, kind: str) -> bpy.types.Object:
    """One-handed neutral tool as a static mesh (grip at local origin, along -Y)."""
    verts: list[Vector] = []
    faces: list[tuple[int, ...]] = []

    def add_box(center: Vector, half: Vector) -> None:
        base = len(verts)
        v, f = box_geometry(center, half, Matrix.Identity(3))
        verts.extend(v)
        faces.extend(tuple(base + i for i in quad) for quad in f)

    if kind == "scraper":
        add_box(Vector((0.0, -0.05, 0.0)), Vector((0.018, 0.16, 0.018)))
        add_box(Vector((0.0, -0.28, -0.02)), Vector((0.05, 0.06, 0.015)))
    else:  # mallet
        add_box(Vector((0.0, -0.05, 0.0)), Vector((0.02, 0.18, 0.02)))
        add_box(Vector((0.0, -0.32, 0.0)), Vector((0.045, 0.075, 0.045)))

    mesh_data = bpy.data.meshes.new(name + "_mesh")
    mesh_data.from_pydata(verts, [], faces)
    mesh_data.update()
    obj = bpy.data.objects.new(name, mesh_data)
    bpy.context.scene.collection.objects.link(obj)
    mesh_data.materials.append(_material(name + "_mat", 0x7A7466, 0.55, 0.35))
    obj.rotation_mode = "QUATERNION"
    return obj
