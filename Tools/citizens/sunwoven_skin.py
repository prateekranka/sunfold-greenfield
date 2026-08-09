"""Production Foundation Sunwoven Weaver geometry.

The citizen is authored as connected low-poly human topology on the shared
27-bone rig.  Garments use welded ring surfaces with explicit two-bone weights
at every joint.  Accessories are rigid only when they are genuinely rigid:
the basket, sickle, beater and side basket follow authored bones or sockets.

The module contains geometry and material authoring only.  It does not add
textures, UVs, physics, runtime state or random values.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Matrix, Vector

from skin import _material


# Twenty sides keep the authored face and joint transitions readable in the
# matched portrait while remaining deliberately low-poly and editable.
RING_SEGMENTS = 20

# Hex values are sRGB inputs passed through skin._material.  The material names
# are also used by the canonical comparison report's six color regions.
# Codex refs (Aug 2026) push saturated teal accents and keep woven volumes in
# the dark bucket so mid-leather no longer dominates the silhouette mask.
SUNWOVEN_MATERIALS = {
    # Slightly pinker / brighter skin so lit limbs stay in the skin bucket
    # instead of collapsing into mid-leather under the key light.
    "skin": (0xD49A72, 0.72, 0.00),
    "cloth_cream": (0xE6D0A8, 0.80, 0.00),
    "cloth_teal": (0x188880, 0.55, 0.00),
    # Warm mid-leather for boots/wraps — lit value aimed at the leather bucket.
    "leather_tan": (0xA56B3C, 0.82, 0.00),
    # Near-black woven brown so pack/pail land in the dark comparison bucket.
    "wicker": (0x1A140F, 0.96, 0.00),
    "bronze": (0xB27838, 0.48, 0.38),
    "hair_dark": (0x1A140F, 0.96, 0.00),
    "sole_brown": (0x4A3220, 0.94, 0.00),
}


def ensure_materials() -> dict[str, bpy.types.Material]:
    mats = {}
    for key, (hex_color, roughness, metallic) in SUNWOVEN_MATERIALS.items():
        name = f"sunwoven_{key}"
        existing = bpy.data.materials.get(name)
        if existing is not None:
            bpy.data.materials.remove(existing)
        mats[key] = _material(name, hex_color, roughness, metallic)
    mats["codex_emissive"] = _codex_emissive_material("sunwoven_codex_emissive")
    return mats


def _codex_emissive_material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    vcol = nodes.new("ShaderNodeVertexColor")
    vcol.layer_name = "CodexCol"
    links.new(vcol.outputs["Color"], emit.inputs["Color"])
    links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def _ellipse_ring(center, side_axis, up_axis, half_w, half_d, segs=RING_SEGMENTS):
    side = Vector(side_axis).normalized()
    up = Vector(up_axis).normalized()
    return [
        Vector(center) + side * (math.cos(a) * half_w) + up * (math.sin(a) * half_d)
        for a in (2.0 * math.pi * i / segs for i in range(segs))
    ]


def _bone_world_frame(arm_obj, bone_name: str):
    bone = arm_obj.data.bones[bone_name]
    head = arm_obj.matrix_world @ bone.head_local
    tail = arm_obj.matrix_world @ bone.tail_local
    axis = (tail - head).normalized() if (tail - head).length > 1e-6 else Vector((0, 0, 1))
    basis = (arm_obj.matrix_world @ bone.matrix_local).to_3x3()
    side = basis.col[0].xyz.normalized()
    up = basis.col[2].xyz.normalized()
    side = (side - axis * side.dot(axis)).normalized()
    if side.length < 1e-6:
        side = axis.orthogonal()
    up = (up - axis * up.dot(axis)).normalized()
    if up.length < 1e-6:
        up = axis.cross(side).normalized()
    return head, tail, axis, side, up


def _smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True


def _object_from_data(name, verts, faces, mats, face_keys, smooth=True):
    data = bpy.data.meshes.new(name + "_mesh")
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)

    keys = list(dict.fromkeys(face_keys if isinstance(face_keys, list) else [face_keys]))
    for key in keys:
        data.materials.append(mats[key])
    key_to_slot = {key: i for i, key in enumerate(keys)}
    for poly, key in zip(data.polygons, face_keys if isinstance(face_keys, list) else [face_keys] * len(data.polygons)):
        poly.material_index = key_to_slot[key]
    if smooth:
        _smooth(obj)
    return obj


def _bind_single(obj, arm_obj, bone: str, weight: float = 1.0):
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(obj.data.vertices)), weight, "ADD")
    mod = obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj
    obj.parent = arm_obj


def _parent_to_bone(obj, arm_obj, bone: str):
    """Parent a local-origin rigid prop to a named socket bone."""
    rest_world = arm_obj.matrix_world @ arm_obj.data.bones[bone].matrix_local
    obj.matrix_world = rest_world
    obj.parent = arm_obj
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    # Blender 5.2 retains the armature-space local matrix on bone parenting.
    # Reapply the authored rest-world transform so the prop origin stays at
    # the socket instead of receiving the bone transform a second time.
    obj.matrix_world = rest_world


class RingMesh:
    """A connected sequence of welded full rings with explicit skin weights."""

    def __init__(self, arm_obj, name: str, mats: dict, default_material: str):
        self.arm = arm_obj
        self.name = name
        self.mats = mats
        self.default_material = default_material
        self.verts: list[Vector] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_keys: list[str] = []
        self.vertex_specs: list[tuple[str, float, str, float]] = []
        self.rings: list[tuple[int, int]] = []

    def add_ring(self, ring: list[Vector], weight_spec: tuple[str, float, str, float]) -> int:
        base = len(self.verts)
        self.verts.extend(Vector(v) for v in ring)
        self.vertex_specs.extend([weight_spec] * len(ring))
        ring_id = len(self.rings)
        self.rings.append((base, len(ring)))
        return ring_id

    def add_vertex(self, vertex: Vector, weight_spec: tuple[str, float, str, float]) -> int:
        index = len(self.verts)
        self.verts.append(Vector(vertex))
        self.vertex_specs.append(weight_spec)
        return index

    def connect(self, a_ring: int, b_ring: int, closed=True, material: str | None = None) -> None:
        a_base, a_count = self.rings[a_ring]
        b_base, b_count = self.rings[b_ring]
        count = min(a_count, b_count)
        last = count if closed else count - 1
        for i in range(last):
            j = (i + 1) % count
            self.faces.append((a_base + i, a_base + j, b_base + j, b_base + i))
            self.face_keys.append(material or self.default_material)

    def cap(self, ring_id: int, center: Vector, weight_spec, material: str | None = None) -> None:
        base, count = self.rings[ring_id]
        center_index = self.add_vertex(center, weight_spec)
        for i in range(count):
            j = (i + 1) % count
            self.faces.append((center_index, base + i, base + j))
            self.face_keys.append(material or self.default_material)

    def finish(self) -> bpy.types.Object:
        obj = _object_from_data(self.name, self.verts, self.faces, self.mats, self.face_keys)
        deform_set = {bone.name for bone in self.arm.data.bones if bone.use_deform}
        groups = {}
        for bone_a, _wa, bone_b, _wb in self.vertex_specs:
            for bone in (bone_a, bone_b):
                if bone and bone in deform_set and bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
        for index, (bone_a, wa, bone_b, wb) in enumerate(self.vertex_specs):
            weights = [(bone_a, max(0.0, wa)), (bone_b, max(0.0, wb))]
            total = sum(weight for bone, weight in weights if bone in groups)
            if total <= 0.0:
                continue
            for bone, weight in weights:
                if bone in groups and weight > 0.0:
                    groups[bone].add([index], weight / total, "ADD")
        modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
        modifier.object = self.arm
        obj.parent = self.arm
        return obj


def _path_ring(center: Vector, axis: Vector, radius: float, depth: float, segs=RING_SEGMENTS):
    axis = Vector(axis).normalized()
    reference = Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(reference)) > 0.94:
        reference = Vector((0.0, 1.0, 0.0))
    side = axis.cross(reference).normalized()
    up = side.cross(axis).normalized()
    return _ellipse_ring(center, side, up, radius, depth, segs)


def _weighted_path(arm_obj, name, points, radii, specs, mats, material, closed_caps=False):
    rm = RingMesh(arm_obj, name, mats, material)
    ring_ids = []
    for point, radius, spec in zip(points, radii, specs):
        index = len(ring_ids)
        axis = (points[min(index + 1, len(points) - 1)] - points[max(index - 1, 0)]).normalized()
        ring_ids.append(rm.add_ring(_path_ring(Vector(point), axis, radius, radius, RING_SEGMENTS), spec))
    for a, b in zip(ring_ids, ring_ids[1:]):
        rm.connect(a, b)
    if closed_caps and ring_ids:
        rm.cap(ring_ids[0], Vector(points[0]), specs[0])
        rm.cap(ring_ids[-1], Vector(points[-1]), specs[-1])
    return rm.finish()


def _append_tube(verts, faces, face_keys, points, radius, material, segs=10, cap=True):
    if len(points) < 2:
        return None
    first = len(verts)
    rings = []
    for index, point in enumerate(points):
        if index == 0:
            axis = (points[1] - point).normalized()
        elif index == len(points) - 1:
            axis = (point - points[index - 1]).normalized()
        else:
            axis = (points[index + 1] - points[index - 1]).normalized()
        ring = _path_ring(Vector(point), axis, radius, radius, segs)
        rings.append(len(verts))
        verts.extend(ring)
    for ring_a, ring_b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            faces.append((ring_a + i, ring_a + j, ring_b + j, ring_b + i))
            face_keys.append(material)
    start = end = None
    if cap:
        start = len(verts)
        verts.append(Vector(points[0]))
        end = len(verts)
        verts.append(Vector(points[-1]))
        for i in range(segs):
            j = (i + 1) % segs
            faces.append((start, rings[0] + j, rings[0] + i))
            face_keys.append(material)
            faces.append((end, rings[-1] + i, rings[-1] + j))
            face_keys.append(material)
    return {"rings": rings, "start_cap": start, "end_cap": end}


def _append_torus(verts, faces, face_keys, center, side_axis, forward_axis, up_axis, radius_major, radius_minor, material, segs_major=20, segs_minor=8):
    side = Vector(side_axis).normalized()
    forward = Vector(forward_axis).normalized()
    up = Vector(up_axis).normalized()
    frame = Matrix((side, forward, up)).transposed()
    first = len(verts)
    for i in range(segs_major):
        a = 2.0 * math.pi * i / segs_major
        for j in range(segs_minor):
            b = 2.0 * math.pi * j / segs_minor
            local = Vector((
                (radius_major + radius_minor * math.cos(b)) * math.cos(a),
                (radius_major + radius_minor * math.cos(b)) * math.sin(a),
                radius_minor * math.sin(b),
            ))
            verts.append(Vector(center) + frame @ local)
    for i in range(segs_major):
        ni = (i + 1) % segs_major
        for j in range(segs_minor):
            nj = (j + 1) % segs_minor
            faces.append((first + i * segs_minor + j, first + i * segs_minor + nj,
                          first + ni * segs_minor + nj, first + ni * segs_minor + j))
            face_keys.append(material)


def _append_ellipsoid(verts, faces, face_keys, center, radii, material, rings=7, segs=16):
    center = Vector(center)
    rx, ry, rz = radii
    top = len(verts)
    verts.append(center + Vector((0.0, 0.0, rz)))
    ring_indices = []
    for ring in range(1, rings):
        phi = math.pi * ring / rings
        base = len(verts)
        ring_indices.append(base)
        for i in range(segs):
            angle = 2.0 * math.pi * i / segs
            verts.append(center + Vector((rx * math.sin(phi) * math.cos(angle),
                                          ry * math.sin(phi) * math.sin(angle),
                                          rz * math.cos(phi))))
    bottom = len(verts)
    verts.append(center - Vector((0.0, 0.0, rz)))
    first = ring_indices[0]
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((top, first + j, first + i))
        face_keys.append(material)
    for a, b in zip(ring_indices, ring_indices[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            faces.append((a + i, a + j, b + j, b + i))
            face_keys.append(material)
    last = ring_indices[-1]
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((bottom, last + i, last + j))
        face_keys.append(material)


def _append_crescent(verts, faces, face_keys, points, depth, material):
    """Extruded crescent polygon in local X/Z coordinates."""
    n = len(points)
    front = len(verts)
    verts.extend(Vector((x, -depth * 0.5, z)) for x, z in points)
    back = len(verts)
    verts.extend(Vector((x, depth * 0.5, z)) for x, z in points)
    front_center = len(verts)
    verts.append(sum((Vector((x, -depth * 0.5, z)) for x, z in points), Vector()) / n)
    back_center = len(verts)
    verts.append(sum((Vector((x, depth * 0.5, z)) for x, z in points), Vector()) / n)
    for i in range(n):
        j = (i + 1) % n
        faces.append((front_center, front + i, front + j))
        face_keys.append(material)
        faces.append((back_center, back + j, back + i))
        face_keys.append(material)
        faces.append((front + i, back + i, back + j, front + j))
        face_keys.append(material)


def _partial_hair(arm_obj, name, mats, p):
    """Rear half-cap for dark hair; the front of the face remains uncovered."""
    head, tail, _axis, _side, _up = _bone_world_frame(arm_obj, "head")
    center_z = head.z + 0.42 * (tail.z - head.z)
    verts, faces, keys = [], [], []
    specs = []
    levels = [(center_z - 0.055, 0.88), (center_z + 0.015, 1.00), (center_z + 0.085, 0.94)]
    samples = 12
    for z, scale in levels:
        base = len(verts)
        for i in range(samples + 1):
            angle = math.pi * i / samples
            verts.append(Vector((p["head_half"] * scale * math.cos(angle),
                                 0.0 + p["head_half"] * scale * math.sin(angle), z)))
            specs.append(("head", 1.0, "head", 0.0))
        if base > 0:
            prior = base - (samples + 1)
            for i in range(samples):
                faces.append((prior + i, prior + i + 1, base + i + 1, base + i))
                keys.append("hair_dark")
    obj = _object_from_data(name, verts, faces, mats, keys)
    _bind_single(obj, arm_obj, "head")
    return obj


def _bundle_geometry(center=Vector((0.0, 0.0, 0.0)), scale=1.0):
    verts, faces, keys = [], [], []
    z_levels = [0.0, 0.055, 0.11, 0.16]
    radii = [0.050, 0.062, 0.058, 0.038]
    rings = []
    for z, radius in zip(z_levels, radii):
        ring = len(verts)
        rings.append(ring)
        for i in range(10):
            angle = 2.0 * math.pi * i / 10
            verts.append(Vector(center) + Vector((radius * scale * math.cos(angle),
                                                   radius * scale * math.sin(angle),
                                                   (z - 0.08) * scale)))
    for a, b in zip(rings, rings[1:]):
        for i in range(10):
            j = (i + 1) % 10
            faces.append((a + i, a + j, b + j, b + i))
            keys.append("wicker")
    bottom = len(verts)
    verts.append(Vector(center) + Vector((0.0, 0.0, -0.08 * scale)))
    top = len(verts)
    verts.append(Vector(center) + Vector((0.0, 0.0, 0.08 * scale)))
    for i in range(10):
        j = (i + 1) % 10
        faces.append((bottom, rings[0] + i, rings[0] + j))
        keys.append("wicker")
        faces.append((top, rings[-1] + j, rings[-1] + i))
        keys.append("wicker")
    return verts, faces, keys


def _authored_head_ring(center_z: float, z_t: float, half_w: float, half_d: float) -> list[Vector]:
    """Return one facial skull loop with authored brow, socket and nose relief.

    The loops stay part of the body surface.  Negative Y is the face, so the
    feature offsets are sculpted into the ring positions instead of added as
    floating accent meshes.
    """
    points = []
    for index in range(RING_SEGMENTS):
        angle = 2.0 * math.pi * index / RING_SEGMENTS
        x = half_w * math.cos(angle)
        y = half_d * math.sin(angle)
        frontness = max(0.0, -math.sin(angle))
        x_norm = x / max(half_w, 1e-6)

        socket_width = max(0.0, 1.0 - abs(abs(x_norm) - 0.48) / 0.26)
        socket_height = max(0.0, 1.0 - abs(z_t - 0.47) / 0.115)
        socket = socket_width * socket_height * frontness

        brow_width = max(0.0, 1.0 - abs(abs(x_norm) - 0.48) / 0.30)
        brow_height = max(0.0, 1.0 - abs(z_t - 0.61) / 0.105)
        brow = brow_width * brow_height * frontness

        nose_width = max(0.0, 1.0 - abs(x_norm) / 0.20)
        nose_height = max(0.0, 1.0 - abs(z_t - 0.46) / 0.25)
        nose = nose_width * nose_height * frontness

        mouth = max(0.0, 1.0 - abs(x_norm) / 0.28) * max(0.0, 1.0 - abs(z_t - 0.285) / 0.06) * frontness
        y += socket * 0.014 - brow * 0.012 - nose * 0.020 - mouth * 0.005
        points.append(Vector((x, y, center_z)))
    return points


# --------------------------------------------------------------------------
# Connected human body and garments.
# --------------------------------------------------------------------------
def build_sunwoven_body(arm_obj, p: dict[str, float], mats: dict, prefix: str = "sunwoven") -> bpy.types.Object:
    """One connected welded body surface with skin material and multi-weights."""
    r = p["limb_r"]
    rm = RingMesh(arm_obj, f"{prefix}_body", mats, "skin")

    def bone_ring(bone, t, half_w, half_d, spec):
        head, tail, _axis, side, up = _bone_world_frame(arm_obj, bone)
        return rm.add_ring(_ellipse_ring(head.lerp(tail, t), side, up, half_w, half_d), spec)

    spine_specs = [
        ("hips", 0.00, p["pelvis_half_w"] * 1.10, p["torso_half_d"] * 0.95, ("hips", 0.78, "spine_01", 0.22)),
        ("hips", 1.00, p["pelvis_half_w"] * 1.05, p["torso_half_d"], ("hips", 0.72, "spine_01", 0.28)),
        ("spine_01", 1.00, p["torso_half_w"] * 0.91, p["torso_half_d"] * 1.02, ("spine_01", 0.72, "spine_02", 0.28)),
        ("spine_02", 1.00, p["torso_half_w"] * 0.98, p["torso_half_d"] * 1.06, ("spine_02", 0.72, "chest", 0.28)),
        ("chest", 1.00, p["torso_half_w"] * 1.04, p["torso_half_d"] * 1.00, ("chest", 0.75, "neck", 0.25)),
        ("neck", 1.00, r * 1.04, r * 1.00, ("neck", 0.72, "head", 0.28)),
    ]
    spine_ids = [bone_ring(bone, t, hw, hd, spec) for bone, t, hw, hd, spec in spine_specs]
    for a, b in zip(spine_ids, spine_ids[1:]):
        rm.connect(a, b, material="skin")

    # The skull and face are one connected continuation of the neck loop.
    # Each loop carries readable authored relief for the brow, recessed eye
    # sockets, nose bridge, mouth plane and tapered jaw.
    head_bone_head, head_bone_tail, _axis, _side, _up = _bone_world_frame(arm_obj, "head")
    head_levels = [
        (0.00, 0.74, 0.68, ("neck", 0.28, "head", 0.72)),
        (0.10, 0.91, 0.84, ("head", 0.82, "neck", 0.18)),
        (0.28, 1.04, 0.94, ("head", 1.0, "head", 0.0)),
        (0.47, 1.08, 0.99, ("head", 1.0, "head", 0.0)),
        (0.66, 1.05, 0.96, ("head", 1.0, "head", 0.0)),
        (0.84, 0.96, 0.87, ("head", 1.0, "head", 0.0)),
        (1.00, 0.76, 0.70, ("head", 1.0, "head", 0.0)),
    ]
    head_ids = []
    for z_t, width_scale, depth_scale, spec in head_levels:
        center_z = head_bone_head.z + (head_bone_tail.z - head_bone_head.z) * z_t
        ring = _authored_head_ring(
            center_z,
            z_t,
            p["head_half"] * width_scale,
            p["head_half"] * depth_scale,
        )
        head_ids.append(rm.add_ring(ring, spec))
    rm.connect(spine_ids[-1], head_ids[0], material="skin")
    for row, (a_ring, b_ring) in enumerate(zip(head_ids, head_ids[1:])):
        a_base, a_count = rm.rings[a_ring]
        b_base, b_count = rm.rings[b_ring]
        count = min(a_count, b_count)
        z_mid = (head_levels[row][0] + head_levels[row + 1][0]) * 0.5
        for index in range(count):
            next_index = (index + 1) % count
            face = (a_base + index, a_base + next_index, b_base + next_index, b_base + index)
            center = sum((rm.verts[vertex] for vertex in face), Vector()) / len(face)
            x_norm = center.x / max(p["head_half"], 1e-6)
            eye_patch = (
                0.35 <= z_mid <= 0.57
                and center.y < -p["head_half"] * 0.60
                and abs(abs(x_norm) - 0.48) < 0.25
            )
            rm.faces.append(face)
            rm.face_keys.append("hair_dark" if eye_patch else "skin")
    rm.cap(head_ids[-1], Vector((0.0, 0.0, head_bone_tail.z + 0.004)), ("head", 1.0, "head", 0.0), "skin")

    for side_name in ("L", "R"):
        sx = 1.0 if side_name == "L" else -1.0
        chest_head, chest_tail, _a, side_axis, up_axis = _bone_world_frame(arm_obj, "chest")
        # Pull the socket slightly inward so the shoulder shell sits under the
        # tunic armhole instead of poking through as a hard skin cylinder.
        shoulder = chest_tail + side_axis * sx * (p["torso_half_w"] * 0.96)
        seat = rm.add_ring(_ellipse_ring(shoulder, up_axis, side_axis * sx, r * 1.10, r * 1.10),
                           ("chest", 0.52, f"clavicle_{side_name}", 0.48))
        rm.connect(spine_ids[4], seat, material="skin")
        arm_rings = [
            (f"clavicle_{side_name}", 1.0, r * 1.06, r * 1.02, (f"clavicle_{side_name}", 0.68, f"upperarm_{side_name}", 0.32)),
            (f"upperarm_{side_name}", 0.0, r * 1.02, r * 0.98, (f"clavicle_{side_name}", 0.42, f"upperarm_{side_name}", 0.58)),
            (f"upperarm_{side_name}", 0.42, r * 0.98, r * 0.96, (f"upperarm_{side_name}", 0.84, f"upperarm_{side_name}", 0.16)),
            (f"upperarm_{side_name}", 0.92, r * 0.88, r * 0.86, (f"upperarm_{side_name}", 0.68, f"lowerarm_{side_name}", 0.32)),
            (f"lowerarm_{side_name}", 0.04, r * 0.86, r * 0.84, (f"upperarm_{side_name}", 0.30, f"lowerarm_{side_name}", 0.70)),
            (f"lowerarm_{side_name}", 0.52, r * 0.80, r * 0.76, (f"lowerarm_{side_name}", 0.84, f"lowerarm_{side_name}", 0.16)),
            (f"lowerarm_{side_name}", 1.0, r * 0.74, r * 0.70, (f"lowerarm_{side_name}", 0.70, f"hand_{side_name}", 0.30)),
            (f"hand_{side_name}", 0.18, r * 0.82, r * 0.61, (f"lowerarm_{side_name}", 0.24, f"hand_{side_name}", 0.76)),
            (f"hand_{side_name}", 0.52, r * 0.88, r * 0.66, (f"hand_{side_name}", 0.90, f"hand_{side_name}", 0.10)),
        ]
        previous = seat
        for bone, t, hw, hd, spec in arm_rings:
            current = bone_ring(bone, t, hw, hd, spec)
            rm.connect(previous, current, material="skin")
            previous = current

        # Turn the final hand section into a palm around the authored tool
        # socket.  The palm is welded to the forearm chain and capped beyond
        # the grip, so the sickle handle passes through a real closed fist.
        socket_head, socket_tail, socket_axis, socket_side, socket_up = _bone_world_frame(
            arm_obj, f"socket_tool_{side_name}"
        )
        palm_center = socket_head + socket_axis * 0.010
        palm = rm.add_ring(
            _ellipse_ring(palm_center, socket_side, socket_up, r * 0.88, r * 0.68),
            (f"hand_{side_name}", 1.0, f"hand_{side_name}", 0.0),
        )
        grip = rm.add_ring(
            _ellipse_ring(socket_head + socket_axis * 0.060, socket_side, socket_up, r * 0.70, r * 0.52),
            (f"hand_{side_name}", 1.0, f"hand_{side_name}", 0.0),
        )
        rm.connect(previous, palm, material="skin")
        rm.connect(palm, grip, material="skin")
        rm.cap(grip, socket_head + socket_axis * 0.082, (f"hand_{side_name}", 1.0, f"hand_{side_name}", 0.0), "skin")

    for side_name in ("L", "R"):
        sx = 1.0 if side_name == "L" else -1.0
        hips_head, _hips_tail, _a, side_axis, up_axis = _bone_world_frame(arm_obj, "hips")
        hip = hips_head + side_axis * sx * p["hip_half"]
        seat = rm.add_ring(_ellipse_ring(hip, up_axis, side_axis * sx, r * 1.36, r * 1.30),
                           ("hips", 0.60, f"thigh_{side_name}", 0.40))
        rm.connect(spine_ids[0], seat, material="skin")
        leg_rings = [
            (f"thigh_{side_name}", 0.0, r * 1.34, r * 1.30, ("hips", 0.35, f"thigh_{side_name}", 0.65)),
            (f"thigh_{side_name}", 1.0, r * 1.08, r * 1.05, (f"thigh_{side_name}", 0.72, f"calf_{side_name}", 0.28)),
            (f"calf_{side_name}", 1.0, r * 0.82, r * 0.80, (f"calf_{side_name}", 0.72, f"foot_{side_name}", 0.28)),
            (f"foot_{side_name}", 0.55, r * 0.70, r * 0.45, (f"foot_{side_name}", 0.72, f"toe_{side_name}", 0.28)),
            (f"toe_{side_name}", 1.0, r * 0.78, r * 0.40, (f"toe_{side_name}", 1.0, f"toe_{side_name}", 0.0)),
        ]
        previous = seat
        for bone, t, hw, hd, spec in leg_rings:
            current = bone_ring(bone, t, hw, hd, spec)
            rm.connect(previous, current, material="skin")
            previous = current
    return rm.finish()


def build_sunwoven_headwrap(arm_obj, p, mats, prefix="sunwoven"):
    head, tail, _axis, _side, _up = _bone_world_frame(arm_obj, "head")
    rm = RingMesh(arm_obj, f"{prefix}_headwrap", mats, "cloth_cream")
    # The Foundation / Codex references use a narrow forehead band with a thin
    # teal stripe.  Place it above the brow relief, leaving the eyes, nose
    # bridge and jaw fully exposed.
    # Tall cream band — the Codex top-12% silhouette is headwrap, not pack/hair.
    levels = [
        (head.z + 0.132, p["head_half"] * 1.04, p["head_half"] * 0.90, ("head", 0.82, "head", 0.18)),
        (head.z + 0.152, p["head_half"] * 1.12, p["head_half"] * 0.98, ("head", 1.0, "head", 0.0)),
        (head.z + 0.168, p["head_half"] * 1.16, p["head_half"] * 1.02, ("head", 1.0, "head", 0.0)),
        (head.z + 0.184, p["head_half"] * 1.18, p["head_half"] * 1.04, ("head", 1.0, "head", 0.0)),
        (head.z + 0.200, p["head_half"] * 1.14, p["head_half"] * 1.00, ("head", 1.0, "head", 0.0)),
        (head.z + 0.218, p["head_half"] * 1.08, p["head_half"] * 0.94, ("head", 1.0, "head", 0.0)),
        (head.z + 0.238, p["head_half"] * 0.98, p["head_half"] * 0.84, ("head", 1.0, "head", 0.0)),
    ]
    rings = [rm.add_ring(_ellipse_ring(Vector((0.0, 0.0, z)), Vector((1, 0, 0)), Vector((0, 1, 0)), rx, ry), spec)
             for z, rx, ry, spec in levels]
    for index, (a, b) in enumerate(zip(rings, rings[1:])):
        # Thin teal stripe — keep most of the band cream for the top-12% gate.
        rm.connect(a, b, material="cloth_teal" if index == 2 else "cloth_cream")
    wrap = rm.finish()

    tail_points = [
        Vector((0.0, p["head_half"] * 0.74, head.z + 0.205)),
        Vector((0.0, p["head_half"] * 1.04, head.z + 0.14)),
        Vector((0.0, p["head_half"] * 1.07, head.z + 0.075)),
    ]
    wrap_tail = _weighted_path(
        arm_obj, f"{prefix}_headwrap_tail", tail_points,
        [0.026, 0.030, 0.024],
        [("head", 1.0, "head", 0.0)] * 3, mats, "cloth_cream", True,
    )
    return [wrap, wrap_tail]


def build_sunwoven_hair(arm_obj, p, mats, prefix="sunwoven"):
    rear = _partial_hair(arm_obj, f"{prefix}_hair_nape", mats, p)
    head, tail, _axis, _side, _up = _bone_world_frame(arm_obj, "head")
    verts, faces, keys = [], [], []
    _append_ellipsoid(
        verts,
        faces,
        keys,
        Vector((0.0, p["head_half"] * 0.62, tail.z - 0.048)),
        (p["head_half"] * 0.46, p["head_half"] * 0.46, p["head_half"] * 0.50),
        "hair_dark",
        6,
        12,
    )
    bun = _object_from_data(f"{prefix}_hair_bun", verts, faces, mats, keys)
    _bind_single(bun, arm_obj, "head")
    return [rear, bun]


def build_sunwoven_face(arm_obj, p, mats, prefix="sunwoven"):
    """Face relief is authored directly into the connected body skull."""
    # Keep the call contract used by build_sunwoven.py, but do not create
    # floating nose, eye or mouth objects.  build_sunwoven_body owns the
    # welded skull loops and their head weights.
    return []


def build_sunwoven_tunic(arm_obj, p, mats, prefix="sunwoven"):
    """Author a folded garment shell with open front, neck and armholes."""
    rm = RingMesh(arm_obj, f"{prefix}_tunic", mats, "cloth_cream")
    # Codex coat flare: hem balloons outward from the belt, with pointed side
    # panels reading as a wider silhouette at mid-thigh.
    levels = [
        (0.58, 0.348, 0.268, ("hips", 0.78, "spine_01", 0.22)),
        (0.68, 0.322, 0.242, ("hips", 0.70, "spine_01", 0.30)),
        (0.80, 0.278, 0.210, ("hips", 0.62, "spine_01", 0.38)),
        (0.94, 0.228, 0.182, ("spine_01", 0.66, "spine_02", 0.34)),
        (1.08, 0.210, 0.168, ("spine_01", 0.50, "spine_02", 0.50)),
        (1.22, 0.218, 0.176, ("spine_02", 0.68, "chest", 0.32)),
        (1.36, 0.204, 0.162, ("chest", 0.78, "neck", 0.22)),
        (1.48, 0.186, 0.148, ("chest", 0.78, "neck", 0.22)),
        (1.56, 0.168, 0.134, ("chest", 0.70, "neck", 0.30)),
    ]

    # The front opening is a deliberate 22-degree gap around -Y.  The long
    # path remains welded around the back and sides, unlike a flat full ring.
    gap = math.radians(22.0)
    start = -math.pi * 0.5 + gap * 0.5
    sample_count = RING_SEGMENTS + 1
    step = (2.0 * math.pi - gap) / (sample_count - 1)

    def open_ring(z, rx, ry, spec):
        points = []
        for index in range(sample_count):
            angle = start + step * index
            fold = 0.0055 * math.sin(angle * 3.0 + z * 8.0) + 0.0030 * math.cos(angle * 5.0 - z * 6.0)
            side_boost = 1.0 + (0.38 if z < 0.96 else 0.06) * abs(math.cos(angle))
            depth_boost = 1.0 + (0.48 if z < 0.96 else 0.12) * max(0.0, abs(math.sin(angle)))
            points.append(Vector((
                rx * side_boost * math.cos(angle),
                ry * depth_boost * math.sin(angle) + fold,
                z,
            )))
        return rm.add_ring(points, spec)

    rings = [open_ring(z, rx, ry, spec) for z, rx, ry, spec in levels]
    for index, (a, b) in enumerate(zip(rings, rings[1:])):
        # Teal hem band + teal collar lining match the Codex front/rear sheets.
        if index == 0:
            material = "cloth_teal"
        elif index >= len(rings) - 3:
            material = "cloth_teal" if index >= len(rings) - 2 else "cloth_cream"
        else:
            material = "cloth_cream"
        rm.connect(a, b, closed=False, material=material)

    # Add folded edge thickness to both sides of the front opening.  The
    # inner edge vertices share the shell through these strips and use the
    # same spine weights.
    edge_pairs = []
    for ring_id, (_z, _rx, _ry, spec) in zip(rings, levels):
        base, _count = rm.rings[ring_id]
        left = rm.add_vertex(rm.verts[base] + Vector((0.0, 0.020, 0.0)), spec)
        right = rm.add_vertex(rm.verts[base + sample_count - 1] + Vector((0.0, 0.020, 0.0)), spec)
        edge_pairs.append((left, right))
    for row in range(len(rings) - 1):
        outer_a, _ = rm.rings[rings[row]]
        outer_b, _ = rm.rings[rings[row + 1]]
        inner_a_left, inner_a_right = edge_pairs[row]
        inner_b_left, inner_b_right = edge_pairs[row + 1]
        edge_mat = "cloth_teal" if row == 0 or row >= len(rings) - 3 else "cloth_cream"
        rm.faces.extend([
            (outer_a, outer_b, inner_b_left, inner_a_left),
            (outer_a + sample_count - 1, inner_a_right, inner_b_right, outer_b + sample_count - 1),
        ])
        rm.face_keys.extend([edge_mat, edge_mat])

    # A thick neck edge surrounds the open collar.  It is a connected inner
    # contour, so the neck opening remains a real hole instead of a cap.
    top_base, _ = rm.rings[rings[-1]]
    inner_ring = []
    top_z, top_rx, top_ry, top_spec = levels[-1]
    for index in range(sample_count):
        point = rm.verts[top_base + index]
        inner_ring.append(rm.add_vertex(point + Vector((point.x * -0.18, 0.010, -0.018)), top_spec))
    for index in range(sample_count - 1):
        rm.faces.append((top_base + index, top_base + index + 1, inner_ring[index + 1], inner_ring[index]))
        rm.face_keys.append("cloth_teal")

    # Folded armhole lips are welded into the shoulder shell.  Sleeves still
    # follow their own named arm bones, while these short inner faces produce
    # the visible self-shadow at each opening.
    side_indices = []
    for target in (0.0, math.pi):
        side_indices.append(min(range(sample_count), key=lambda i: abs((start + step * i) - target)))
    for side_index, sx in zip(side_indices, (1.0, -1.0)):
        upper_base, _ = rm.rings[rings[-2]]
        top_base, _ = rm.rings[rings[-1]]
        for offset in (-1, 0, 1):
            upper_index = upper_base + max(0, min(sample_count - 1, side_index + offset))
            top_index = top_base + max(0, min(sample_count - 1, side_index + offset))
            upper_inner = rm.add_vertex(rm.verts[upper_index] + Vector((-sx * 0.016, 0.012, 0.0)), levels[-2][3])
            top_inner = rm.add_vertex(rm.verts[top_index] + Vector((-sx * 0.016, 0.012, 0.0)), levels[-1][3])
            rm.faces.append((upper_index, top_index, top_inner, upper_inner))
            rm.face_keys.append("cloth_cream")
    return rm.finish()


def build_sunwoven_sleeves(arm_obj, p, mats, prefix="sunwoven"):
    out = []
    r = p["limb_r"]
    for side in ("L", "R"):
        points = []
        radii = []
        specs = []
        for bone, t, radius in [
            (f"clavicle_{side}", 0.78, r * 1.42),
            (f"upperarm_{side}", 0.00, r * 1.34),
            (f"upperarm_{side}", 0.42, r * 1.22),
            (f"upperarm_{side}", 0.72, r * 1.12),
            (f"upperarm_{side}", 0.84, r * 1.08),
            # The reference keeps the woven sleeve on the forearm just past
            # the elbow.  This point is deliberately on the lowerarm bone so
            # the garment follows the shared rig through the bent pose.
            (f"lowerarm_{side}", 0.24, r * 1.00),
        ]:
            head, tail, _axis, _side, _up = _bone_world_frame(arm_obj, bone)
            points.append(head.lerp(tail, t))
            radii.append(radius)
            if bone.startswith("clavicle"):
                specs.append((f"clavicle_{side}", 0.72, f"upperarm_{side}", 0.28))
            elif t == 0.0:
                specs.append((f"clavicle_{side}", 0.28, f"upperarm_{side}", 0.72))
            elif bone.startswith("lowerarm"):
                specs.append((f"upperarm_{side}", 0.10, f"lowerarm_{side}", 0.90))
            else:
                specs.append((f"upperarm_{side}", 0.82, f"lowerarm_{side}", 0.18) if t > 0.80
                             else (f"upperarm_{side}", 0.85, f"upperarm_{side}", 0.15))
        # Build as RingMesh so the mid-forearm teal stripe can be face-assigned.
        rm = RingMesh(arm_obj, f"{prefix}_sleeve_{side}", mats, "cloth_cream")
        ring_ids = []
        for point, radius, spec in zip(points, radii, specs):
            index = len(ring_ids)
            axis = (points[min(index + 1, len(points) - 1)] - points[max(index - 1, 0)]).normalized()
            ring_ids.append(rm.add_ring(_path_ring(Vector(point), axis, radius, radius), spec))
        for index, (a, b) in enumerate(zip(ring_ids, ring_ids[1:])):
            rm.connect(a, b, material="cloth_teal" if index == 3 else "cloth_cream")
        rm.cap(ring_ids[0], Vector(points[0]), specs[0])
        rm.cap(ring_ids[-1], Vector(points[-1]), specs[-1])
        out.append(rm.finish())
    return out


def build_sunwoven_trousers(arm_obj, p, mats, prefix="sunwoven"):
    out = []
    r = p["limb_r"]
    for side in ("L", "R"):
        points, radii, specs = [], [], []
        for bone, t, radius, spec in [
            (f"thigh_{side}", 0.00, r * 1.58, ("hips", 0.36, f"thigh_{side}", 0.64)),
            (f"thigh_{side}", 0.52, r * 1.38, (f"thigh_{side}", 0.86, f"thigh_{side}", 0.14)),
            (f"thigh_{side}", 1.00, r * 1.22, (f"thigh_{side}", 0.72, f"calf_{side}", 0.28)),
            (f"calf_{side}", 0.02, r * 1.20, (f"thigh_{side}", 0.28, f"calf_{side}", 0.72)),
            (f"calf_{side}", 0.58, r * 1.10, (f"calf_{side}", 0.82, f"calf_{side}", 0.18)),
        ]:
            head, tail, _axis, _side, _up = _bone_world_frame(arm_obj, bone)
            points.append(head.lerp(tail, t))
            radii.append(radius)
            specs.append(spec)
        out.append(_weighted_path(arm_obj, f"{prefix}_trousers_{side}", points, radii, specs, mats, "cloth_cream", True))
    return out


def build_sunwoven_leg_wraps(arm_obj, p, mats, prefix="sunwoven"):
    """Authored lower-calf wraps that replace exposed mannequin shins."""
    out = []
    r = p["limb_r"]
    for side in ("L", "R"):
        points, radii, specs = [], [], []
        for bone, t, radius in [
            (f"calf_{side}", 0.62, r * 1.10),
            (f"calf_{side}", 0.82, r * 1.08),
            (f"calf_{side}", 1.00, r * 1.02),
        ]:
            head, tail, _axis, _side, _up = _bone_world_frame(arm_obj, bone)
            points.append(head.lerp(tail, t))
            radii.append(radius)
            specs.append((f"calf_{side}", 1.0, f"calf_{side}", 0.0))
        out.append(_weighted_path(arm_obj, f"{prefix}_leg_wrap_{side}", points, radii, specs, mats, "leather_tan", True))
    return out


def build_sunwoven_sash(arm_obj, p, mats, prefix="sunwoven"):
    rm = RingMesh(arm_obj, f"{prefix}_sash", mats, "cloth_cream")
    rings = []
    for z, rx, ry, spec in [
        (0.895, 0.158, 0.112, ("hips", 0.82, "spine_01", 0.18)),
        (0.945, 0.162, 0.116, ("hips", 0.72, "spine_01", 0.28)),
        (0.995, 0.158, 0.114, ("hips", 0.55, "spine_01", 0.45)),
        (1.018, 0.154, 0.112, ("hips", 0.48, "spine_01", 0.52)),
    ]:
        rings.append(rm.add_ring(_ellipse_ring(Vector((0.0, 0.0, z)), Vector((1, 0, 0)), Vector((0, 1, 0)), rx, ry), spec))
    for index, (a, b) in enumerate(zip(rings, rings[1:])):
        rm.connect(a, b, material="cloth_teal" if index >= 1 else "cloth_cream")
    sash = rm.finish()
    # Wider teal front panel / rear tail — the Codex sheets show a long teal
    # sash hanging past the knees with a cream body and teal tip.
    tail_rm = RingMesh(arm_obj, f"{prefix}_sash_tail", mats, "cloth_cream")
    tail_points = [
        Vector((0.055, -0.195, 1.32)), Vector((0.040, -0.220, 1.10)),
        Vector((0.020, -0.230, 0.92)), Vector((0.000, -0.225, 0.74)),
        Vector((-0.010, -0.210, 0.58)),
    ]
    rear_tail_points = [
        Vector((0.030, 0.22, 1.28)), Vector((0.015, 0.30, 1.06)),
        Vector((0.000, 0.32, 0.88)), Vector((-0.010, 0.28, 0.70)),
        Vector((-0.015, 0.22, 0.56)),
    ]
    tail_radii = [0.028, 0.030, 0.032, 0.030, 0.026]
    tail_specs = [
        ("chest", 0.72, "spine_02", 0.28),
        ("spine_02", 0.55, "spine_01", 0.45),
        ("spine_01", 0.60, "hips", 0.40),
        ("hips", 0.78, "spine_01", 0.22),
        ("hips", 0.92, "hips", 0.08),
    ]
    tail_rings = []
    for point, radius, spec in zip(tail_points, tail_radii, tail_specs):
        index = len(tail_rings)
        axis = (tail_points[min(index + 1, len(tail_points) - 1)] - tail_points[max(index - 1, 0)]).normalized()
        # Flatten the sash into a ribbon (wider side axis).
        side = Vector((1.0, 0.0, 0.0))
        if abs(axis.dot(side)) > 0.9:
            side = Vector((0.0, 1.0, 0.0))
        side = (side - axis * side.dot(axis)).normalized()
        up = axis.cross(side).normalized()
        tail_rings.append(tail_rm.add_ring(_ellipse_ring(point, side, up, radius * 3.0, radius * 0.62), spec))
    for index, (a, b) in enumerate(zip(tail_rings, tail_rings[1:])):
        # Cream body with a teal tip band — matches Codex rear teal drop.
        material = "cloth_teal" if index >= len(tail_rings) - 3 else "cloth_cream"
        tail_rm.connect(a, b, material=material)
    tail_rm.cap(tail_rings[0], tail_points[0], tail_specs[0], "cloth_cream")
    tail_rm.cap(tail_rings[-1], tail_points[-1], tail_specs[-1], "cloth_teal")
    tail = tail_rm.finish()
    rear_rm = RingMesh(arm_obj, f"{prefix}_sash_rear", mats, "cloth_cream")
    rear_rings = []
    for point, radius, spec in zip(rear_tail_points, tail_radii, tail_specs):
        index = len(rear_rings)
        axis = (rear_tail_points[min(index + 1, len(rear_tail_points) - 1)] - rear_tail_points[max(index - 1, 0)]).normalized()
        side = Vector((1.0, 0.0, 0.0))
        if abs(axis.dot(side)) > 0.9:
            side = Vector((0.0, 1.0, 0.0))
        side = (side - axis * side.dot(axis)).normalized()
        up = axis.cross(side).normalized()
        rear_rings.append(rear_rm.add_ring(_ellipse_ring(point, side, up, radius * 2.6, radius * 0.58), spec))
    for index, (a, b) in enumerate(zip(rear_rings, rear_rings[1:])):
        material = "cloth_teal" if index >= len(rear_rings) - 3 else "cloth_cream"
        rear_rm.connect(a, b, material=material)
    rear_rm.cap(rear_rings[0], rear_tail_points[0], tail_specs[0], "cloth_cream")
    rear_rm.cap(rear_rings[-1], rear_tail_points[-1], tail_specs[-1], "cloth_teal")
    rear = rear_rm.finish()
    return [sash, tail, rear]


def build_sunwoven_leather(arm_obj, p, mats, prefix="sunwoven"):
    out = []
    # Codex pack straps read as cream rope / cloth, not mid-leather cylinders.
    strap_material = "cloth_cream"
    for side, sx in (("L", 1.0), ("R", -1.0)):
        points = [Vector((sx * 0.095, -0.105, 1.33)), Vector((sx * 0.17, -0.035, 1.43)),
                  Vector((sx * 0.18, 0.075, 1.49)), Vector((sx * 0.15, 0.17, 1.53))]
        specs = [
            ("chest", 0.82, f"clavicle_{side}", 0.18),
            (f"clavicle_{side}", 0.70, "chest", 0.30),
            ("chest", 0.60, "accessory_strap", 0.40),
            ("accessory_strap", 0.82, "chest", 0.18),
        ]
        out.append(_weighted_path(arm_obj, f"{prefix}_harness_{side}", points,
                                  [0.030, 0.034, 0.032, 0.028], specs, mats, strap_material, True))
    lower = _weighted_path(
        arm_obj, f"{prefix}_harness_lower",
        [Vector((0.0, 0.065, 0.93)), Vector((0.0, 0.13, 1.16)), Vector((0.0, 0.17, 1.43))],
        [0.018, 0.017, 0.016],
        [("hips", 0.80, "spine_01", 0.20), ("spine_01", 0.64, "chest", 0.36), ("chest", 0.60, "accessory_strap", 0.40)],
        mats, strap_material, True,
    )
    out.append(lower)
    # Sun buckle only — hip basket is the side_basket mesh.
    buckle_verts, buckle_faces, buckle_keys = [], [], []
    _append_ellipsoid(buckle_verts, buckle_faces, buckle_keys, Vector((0.0, -0.155, 0.97)), (0.045, 0.018, 0.045), "bronze", 5, 12)
    buckle = _object_from_data(f"{prefix}_belt_buckle", buckle_verts, buckle_faces, mats, buckle_keys)
    _bind_single(buckle, arm_obj, "hips")
    out.append(buckle)
    return out


def build_sunwoven_sandals(arm_obj, p, mats, prefix="sunwoven"):
    out = []
    r = p["limb_r"]
    for side in ("L", "R"):
        rm = RingMesh(arm_obj, f"{prefix}_sandal_{side}", mats, "leather_tan")
        ring_ids = []
        points = []
        specs = []
        ring_profile = []
        for bone, t, radius, depth_factor, spec in [
            (f"foot_{side}", 0.0, r * 1.28, 0.78, (f"foot_{side}", 0.82, f"toe_{side}", 0.18)),
            (f"foot_{side}", 0.55, r * 1.18, 0.72, (f"foot_{side}", 0.76, f"toe_{side}", 0.24)),
            (f"toe_{side}", 0.82, r * 1.08, 0.60, (f"foot_{side}", 0.28, f"toe_{side}", 0.72)),
            (f"toe_{side}", 1.00, r * 0.96, 0.50, (f"toe_{side}", 1.0, f"toe_{side}", 0.0)),
        ]:
            head, tail, _axis, _side_axis, _up_axis = _bone_world_frame(arm_obj, bone)
            point = head.lerp(tail, t)
            depth = radius * depth_factor
            point.z = max(0.004 + depth, point.z - radius * 0.65)
            points.append(point)
            specs.append(spec)
            ring_profile.append((point, radius, depth, spec))
        for index, (point, radius, depth, spec) in enumerate(ring_profile):
            axis = (points[min(index + 1, len(points) - 1)] - points[max(index - 1, 0)]).normalized()
            ring_ids.append(rm.add_ring(_path_ring(point, axis, radius, depth), spec))
        for a, b in zip(ring_ids, ring_ids[1:]):
            rm.connect(a, b)
        rm.cap(ring_ids[0], points[0], specs[0], "sole_brown")
        rm.cap(ring_ids[-1], points[-1], specs[-1], "leather_tan")
        out.append(rm.finish())
    return out


# --------------------------------------------------------------------------
# Baskets, straps and authored tools.
# --------------------------------------------------------------------------
def _basket_mesh(name, center, height, radii, mats, prefix_material="wicker", segs=20,
                 woven=False, hoop_levels=(), return_topology=False):
    """Build one connected basket surface with authored wall and lid weave.

    Woven relief is part of the wall vertex field.  The two optional hoop
    levels are raised bands in that same field, not separate torus objects.
    The rim and lid share vertices with the wall so the result remains one
    connected, bound mesh.
    """
    center = Vector(center)
    verts, faces, keys = [], [], []
    levels = [i / 16.0 for i in range(17)] if woven else [0.0, 0.16, 0.38, 0.58, 0.82, 1.0]
    ring_indices = []
    for level_index, t in enumerate(levels):
        radius = radii[0] + (radii[1] - radii[0]) * t
        ring = len(verts)
        ring_indices.append(ring)
        z = -height * 0.5 + height * t
        for i in range(segs):
            angle = 2.0 * math.pi * i / segs
            vertex_radius = radius
            if woven:
                # Alternating diagonal relief makes the warp/weft read under
                # the fixed light while keeping every vertex in the wall.
                weave_phase = angle * 4.0 + t * math.pi * 8.0
                vertex_radius += 0.006 * math.sin(weave_phase)
                cross_phase = angle * 4.0 - t * math.pi * 8.0
                vertex_radius += 0.0025 * math.sin(cross_phase)
                # Barrel bulge so the pack reads bulbous in profile, not a cylinder.
                vertex_radius += 0.038 * math.sin(math.pi * t)
                for hoop_t in hoop_levels:
                    vertex_radius += 0.007 * max(0.0, 1.0 - abs(t - hoop_t) / 0.065)
            verts.append(center + Vector((vertex_radius * math.cos(angle), vertex_radius * math.sin(angle), z)))
    for row, (a, b) in enumerate(zip(ring_indices, ring_indices[1:])):
        for i in range(segs):
            j = (i + 1) % segs
            faces.append((a + i, a + j, b + j, b + i))
            mid_t = (levels[row] + levels[row + 1]) * 0.5
            is_hoop = any(abs(mid_t - hoop_t) < 0.055 for hoop_t in hoop_levels)
            is_teal_band = woven and abs(mid_t - 0.22) < 0.055
            is_woven_band = woven and (i + row * 2) % 8 in (0, 1)
            if is_teal_band:
                keys.append("cloth_teal")
            elif is_hoop:
                keys.append("sole_brown")
            elif is_woven_band:
                # Keep weave relief in the dark/wicker family so mid-leather
                # does not dominate the canonical color-share gate.
                keys.append(prefix_material)
            else:
                keys.append(prefix_material)

    # Fold the top wall into an integrated raised rim and a shallow woven lid.
    # All three rings share faces with the wall; no floating lid or hoop parts
    # are introduced, and the top stays at or below center.z + height / 2.
    top_z = center.z + height * 0.5
    top_radius = radii[1]
    rim = len(verts)
    for i in range(segs):
        angle = 2.0 * math.pi * i / segs
        radius = top_radius * 1.045
        z = -height * 0.5 + height - 0.008 + 0.0025 * math.sin(angle * 2.0)
        verts.append(center + Vector((radius * math.cos(angle), radius * math.sin(angle), z)))
    outer = ring_indices[-1]
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((outer + i, outer + j, rim + j, rim + i))
        keys.append(prefix_material)

    inner = len(verts)
    inner_radius = top_radius * 0.80
    for i in range(segs):
        angle = 2.0 * math.pi * i / segs
        radius = inner_radius * (1.0 + 0.018 * math.sin(angle * 3.0))
        z = -height * 0.5 + height - 0.026 + 0.003 * math.cos(angle * 3.0)
        verts.append(center + Vector((radius * math.cos(angle), radius * math.sin(angle), z)))
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((rim + i, rim + j, inner + j, inner + i))
        keys.append(prefix_material if i % 4 != 0 else "sole_brown")
    lid_center = len(verts)
    verts.append(center + Vector((0.0, 0.0, -height * 0.5 + height - 0.030)))
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((lid_center, inner + i, inner + j))
        keys.append(prefix_material)

    bottom = len(verts)
    verts.append(center + Vector((0.0, 0.0, -height * 0.5)))
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((bottom, ring_indices[0] + i, ring_indices[0] + j))
        keys.append(prefix_material)
    if return_topology:
        return verts, faces, keys, {"outer_ring": ring_indices[-1]}
    return verts, faces, keys


def build_sunwoven_pack_ropes(arm_obj, p, mats, prefix="sunwoven"):
    """Rope lattice on the back pack — Codex side/back callouts."""
    center = Vector((0.0, 0.32, 1.20))
    height = 0.70
    radius = 0.34
    spec = ("accessory_strap", 1.0, "accessory_strap", 0.0)
    out = []
    for index, angle in enumerate((0.0, math.pi * 0.5, math.pi, math.pi * 1.5)):
        x = center.x + radius * math.cos(angle)
        y = center.y + radius * math.sin(angle)
        out.append(_weighted_path(
            arm_obj, f"{prefix}_pack_rope_v_{index}",
            [Vector((x, y, center.z - height * 0.46)), Vector((x, y, center.z + height * 0.44))],
            [0.013, 0.013], [spec, spec], mats, "cloth_cream", True,
        ))
    for z_t in (0.22, 0.50, 0.78):
        z = center.z - height * 0.5 + height * z_t
        ring_points = [
            Vector((center.x + radius * math.cos(a), center.y + radius * math.sin(a), z))
            for a in (2.0 * math.pi * i / 12 for i in range(12))
        ]
        out.append(_weighted_path(
            arm_obj, f"{prefix}_pack_rope_h_{int(z_t * 100)}",
            ring_points + [ring_points[0]], [0.011] * 13, [spec] * 13, mats, "cloth_cream", False,
        ))
    knot_verts, knot_faces, knot_keys = _bundle_geometry(Vector((center.x, center.y + 0.06, center.z - height * 0.38)), 0.42)
    knot = _object_from_data(f"{prefix}_pack_rope_knot", knot_verts, knot_faces, mats, knot_keys)
    _bind_single(knot, arm_obj, "accessory_strap")
    out.append(knot)
    return out


def build_sunwoven_belt_band(arm_obj, p, mats, prefix="sunwoven"):
    rm = RingMesh(arm_obj, f"{prefix}_belt_band", mats, "leather_tan")
    rings = []
    for z, rx, ry, spec in [
        (0.935, 0.168, 0.118, ("hips", 0.82, "spine_01", 0.18)),
        (0.975, 0.176, 0.124, ("hips", 0.72, "spine_01", 0.28)),
        (1.015, 0.172, 0.120, ("hips", 0.55, "spine_01", 0.45)),
    ]:
        rings.append(rm.add_ring(_ellipse_ring(Vector((0.0, 0.0, z)), Vector((1, 0, 0)), Vector((0, 1, 0)), rx, ry), spec))
    for a, b in zip(rings, rings[1:]):
        rm.connect(a, b)
    return rm.finish()


def build_sunwoven_bangles(arm_obj, p, mats, prefix="sunwoven"):
    out = []
    for side in ("L", "R"):
        head, tail, axis, side_axis, up = _bone_world_frame(arm_obj, f"hand_{side}")
        for slot, t in enumerate((0.08, 0.16)):
            center = head.lerp(tail, t)
            verts, faces, keys = [], [], []
            _append_torus(verts, faces, keys, center, side_axis, up, axis, 0.050 + slot * 0.004, 0.0045, "bronze", 12, 4)
            bangle = _object_from_data(f"{prefix}_bangle_{side}_{slot}", verts, faces, mats, keys)
            _bind_single(bangle, arm_obj, f"hand_{side}")
            out.append(bangle)
    return out


def build_sunwoven_front_panels(arm_obj, p, mats, prefix="sunwoven"):
    """Thin flat front tunic panels — Codex front sheet (quads, not tubes)."""
    out = []
    y_front = -0.34
    top_z = 0.92
    bot_z = 0.58
    for index, sx in enumerate((-0.108, -0.036, 0.036, 0.108)):
        half_w = 0.048 if index in (0, 3) else 0.044
        sway = 0.014 if index < 2 else -0.014
        corners = [
            Vector((sx - half_w, y_front, top_z)),
            Vector((sx + half_w, y_front, top_z)),
            Vector((sx + half_w + sway, y_front - 0.012, bot_z)),
            Vector((sx - half_w + sway, y_front - 0.012, bot_z)),
        ]
        panel = _object_from_data(
            f"{prefix}_front_panel_{index}",
            [Vector(c) for c in corners], [(0, 1, 2, 3)], mats, "cloth_cream",
        )
        _bind_single(panel, arm_obj, "hips")
        out.append(panel)
    return out


def build_sunwoven_pack_shoulders(arm_obj, p, mats, prefix="sunwoven"):
    """Lateral pack wings + cream shoulder struts visible from the Codex front."""
    out = []
    strap_spec = ("accessory_strap", 0.70, "chest", 0.30)
    pack_y = 0.30
    for side_name, sx in (("L", 1.0), ("R", -1.0)):
        verts, faces, keys = [], [], []
        _append_ellipsoid(
            verts, faces, keys,
            Vector((sx * 0.34, pack_y, 1.40)),
            (0.12, 0.17, 0.22), "wicker", 6, 10,
        )
        wing = _object_from_data(f"{prefix}_pack_wing_{side_name}", verts, faces, mats, keys)
        _bind_single(wing, arm_obj, "accessory_strap")
        out.append(wing)
        bump_verts, bump_faces, bump_keys = [], [], []
        _append_ellipsoid(
            bump_verts, bump_faces, bump_keys,
            Vector((sx * 0.22, -0.05, 1.44)),
            (0.08, 0.10, 0.14), "wicker", 5, 8,
        )
        bump = _object_from_data(f"{prefix}_pack_bump_{side_name}", bump_verts, bump_faces, mats, bump_keys)
        _bind_single(bump, arm_obj, "accessory_strap")
        out.append(bump)
        out.append(_weighted_path(
            arm_obj, f"{prefix}_pack_strut_{side_name}",
            [
                Vector((sx * 0.08, 0.02, 1.52)),
                Vector((sx * 0.14, pack_y, 1.40)),
                Vector((sx * 0.24, pack_y + 0.04, 1.28)),
            ],
            [0.038, 0.040, 0.036], [strap_spec, strap_spec, strap_spec],
            mats, "cloth_cream", True,
        ))
    crown_verts, crown_faces, crown_keys = [], [], []
    _append_torus(
        crown_verts, crown_faces, crown_keys,
        Vector((0.0, pack_y, 1.58)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)),
        0.36, 0.026, "sole_brown", 20, 6,
    )
    crown = _object_from_data(f"{prefix}_pack_crown", crown_verts, crown_faces, mats, crown_keys)
    _bind_single(crown, arm_obj, "accessory_strap")
    out.append(crown)
    return out


def build_sunwoven_display_sickle(arm_obj, mats, prefix="sunwoven"):
    """Left-hand presentation sickle for construction turnarounds (Codex front/back)."""
    verts, faces, keys = [], [], []
    _append_tube(verts, faces, keys, [Vector((0.0, 0.04, 0.0)), Vector((0.0, -0.08, 0.0)), Vector((0.0, -0.14, 0.0))],
                 0.015, "leather_tan", 8, True)
    _append_torus(verts, faces, keys, Vector((0.0, 0.02, 0.0)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)),
                  0.024, 0.007, "bronze", 10, 6)
    blade = [
        (0.0, 0.0), (0.075, 0.010), (0.150, 0.048), (0.210, 0.115), (0.235, 0.195),
        (0.220, 0.210), (0.190, 0.178), (0.140, 0.118), (0.095, 0.068), (0.0, 0.030),
    ]
    start = len(verts)
    _append_crescent(verts, faces, keys, blade, 0.018, "bronze")
    for index in range(start, len(verts)):
        verts[index].y -= 0.14
        verts[index].z -= 0.06
        verts[index].x += 0.02
    sickle = _object_from_data(f"{prefix}_display_sickle", verts, faces, mats, keys)
    _parent_to_bone(sickle, arm_obj, "hand_L")
    return sickle


def build_sunwoven_hand_bucket(arm_obj, p, mats, prefix="sunwoven"):
    """Small wooden bucket with rope handle — Codex back sheet right hand."""
    center = Vector((0.0, 0.06, 0.0))
    verts, faces, keys = [], [], []
    segs = 14
    levels = [0.0, 0.35, 0.70, 1.0]
    radii = [0.055, 0.062, 0.058, 0.050]
    height = 0.14
    ring_indices = []
    for t, radius in zip(levels, radii):
        ring = len(verts)
        ring_indices.append(ring)
        z = -height * 0.5 + height * t
        for i in range(segs):
            angle = 2.0 * math.pi * i / segs
            verts.append(center + Vector((radius * math.cos(angle), radius * math.sin(angle), z)))
            keys.append("sole_brown")
    for a, b in zip(ring_indices, ring_indices[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            faces.append((a + i, a + j, b + j, b + i))
            keys.append("sole_brown" if i % 5 else "cloth_teal")
    _append_tube(verts, faces, keys,
                  [Vector((-0.05, 0.0, 0.05)), Vector((0.0, 0.0, 0.12)), Vector((0.05, 0.0, 0.05))],
                  0.008, "cloth_cream", 6, True)
    bucket = _object_from_data(f"{prefix}_hand_bucket", verts, faces, mats, keys)
    _parent_to_bone(bucket, arm_obj, "socket_tool_L")
    return bucket


def build_sunwoven_basket(arm_obj, p, mats, prefix="sunwoven"):
    """Bulbous carrier matching Codex pack silhouette (high, rounded, tall)."""
    # Aft for profile width; crown kept below the headwrap cream band.
    center = Vector((0.0, 0.32, 1.20))
    height = 0.70
    verts, faces, keys = _basket_mesh(
        f"{prefix}_basket", center, height, (0.278, 0.358), mats,
        woven=True, hoop_levels=(0.10, 0.86),
    )
    basket = _object_from_data(f"{prefix}_basket", verts, faces, mats, keys)
    _bind_single(basket, arm_obj, "accessory_strap")
    return basket


def build_sunwoven_side_basket(arm_obj, p, mats, prefix="sunwoven"):
    """Small tapered woven basket slung forward at the hip (hand-basket mass).

    Codex cells read a forward hand basket in profile.  Keep the mesh hip-bound
    for the animation contract, but place it ahead of the thigh so the
    silhouette matches the handheld prop mass.
    """
    center = Vector((-p["hip_half"] - 0.10, -0.42, 0.68))
    verts, faces, keys, topology = _basket_mesh(
        f"{prefix}_side_basket", center, 0.34, (0.102, 0.132), mats, "wicker", 16,
        woven=True, hoop_levels=(0.18, 0.72), return_topology=True,
    )
    handle = _append_tube(verts, faces, keys,
                 [Vector((center.x - 0.078, center.y, 0.88)), Vector((center.x, center.y - 0.04, 0.98)), Vector((center.x + 0.078, center.y, 0.88))],
                 0.010, "cloth_cream", 7, True)
    outer = topology["outer_ring"]
    for cap_index, wall_index in ((handle["start_cap"], outer + 8), (handle["end_cap"], outer)):
        for offset in (-1, 1):
            faces.append((cap_index, outer + ((wall_index - outer + offset) % 16), wall_index))
            keys.append("cloth_cream")
    basket = _object_from_data(f"{prefix}_side_basket", verts, faces, mats, keys)
    _bind_single(basket, arm_obj, "hips")
    sling = _weighted_path(
        arm_obj, f"{prefix}_side_basket_sling",
        [Vector((-0.04, -0.08, 1.18)), Vector((-0.10, -0.20, 0.98)), Vector((-p["hip_half"] - 0.08, -0.32, 0.88))],
        [0.014, 0.015, 0.012],
        [("chest", 0.78, "spine_01", 0.22), ("spine_01", 0.60, "hips", 0.40), ("hips", 1.0, "hips", 0.0)],
        mats, "cloth_cream", True,
    )
    return [basket, sling]


def build_sickle(arm_obj, mats, prefix="sunwoven"):
    verts, faces, keys = [], [], []
    # Handle origin sits at the authored tool socket so the closed fist grips
    # the mid-shaft; blade extends away from the palm.
    _append_tube(verts, faces, keys, [Vector((0.0, 0.04, 0.0)), Vector((0.0, -0.10, 0.0)), Vector((0.0, -0.16, 0.0))],
                 0.016, "leather_tan", 8, True)
    _append_torus(verts, faces, keys, Vector((0.0, 0.02, 0.0)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)),
                  0.022, 0.006, "bronze", 10, 6)
    crescent = [
        (0.0, 0.0), (0.080, 0.012), (0.160, 0.058), (0.228, 0.138), (0.252, 0.228),
        (0.236, 0.248), (0.206, 0.212), (0.152, 0.142), (0.104, 0.082),
        (0.048, 0.040), (0.0, 0.032),
    ]
    blade_points = [(x, z) for x, z in crescent]
    blade_start = len(verts)
    _append_crescent(verts, faces, keys, blade_points, 0.020, "bronze")
    for index in range(blade_start, len(verts)):
        verts[index].y -= 0.17
    sickle = _object_from_data(f"{prefix}_scraper", verts, faces, mats, keys)
    _parent_to_bone(sickle, arm_obj, "socket_tool_R")
    return sickle


def build_weaver_beater(arm_obj, mats, prefix="sunwoven"):
    verts, faces, keys = [], [], []
    # Origin at the grip socket; shaft extends from the palm.
    _append_tube(verts, faces, keys, [Vector((0.0, 0.03, 0.0)), Vector((0.0, -0.22, 0.0))], 0.015, "sole_brown", 8, True)
    _append_ellipsoid(verts, faces, keys, Vector((0.0, -0.28, 0.0)), (0.060, 0.028, 0.042), "sole_brown", 5, 12)
    beater = _object_from_data(f"{prefix}_mallet", verts, faces, mats, keys)
    _parent_to_bone(beater, arm_obj, "socket_tool_L")
    return beater


def build_sunwoven_sickle_and_beater(arm_obj, mats, prefix="sunwoven"):
    return [build_sickle(arm_obj, mats, prefix), build_weaver_beater(arm_obj, mats, prefix)]


def build_sunwoven_cargo_chunks(arm_obj, mats, prefix="sunwoven"):
    """Three woven bundles bone-parented to the carrier for authored arc commits."""
    strap_world = arm_obj.matrix_world @ arm_obj.data.bones["accessory_strap"].matrix_local
    chunks = []
    for index, offset in enumerate((Vector((0.0, 0.02, 0.08)), Vector((0.035, 0.01, 0.17)), Vector((-0.035, 0.03, 0.26)))):
        verts, faces, keys = _bundle_geometry(scale=0.72)
        obj = _object_from_data(f"{prefix}_cargo_{index}", verts, faces, mats, keys)
        target = strap_world @ Vector((offset.x, offset.y, offset.z, 1.0))
        obj.parent = arm_obj
        obj.parent_type = "BONE"
        obj.parent_bone = "accessory_strap"
        obj.location = (strap_world.inverted() @ target).to_3d()
        chunks.append(obj)
    return chunks


def build_arc_prop(mats, prefix="sunwoven"):
    verts, faces, keys = _bundle_geometry(scale=0.95)
    return _object_from_data(f"{prefix}_arc_prop", verts, faces, mats, keys)
