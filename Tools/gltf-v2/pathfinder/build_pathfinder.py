#!/usr/bin/env python3
"""build_pathfinder.py — Sunwoven Pathfinder/Scout GLTF builder, FROM SCRATCH.

gltf-v2 pipeline (new code; zero imports from Tools/citizens/).

Builds (Three.js conventions: +Y up, front = -Z, X = figure-left):
  - 22-bone armature (Root/Hips/Spine/Chest/Neck/Head + arms/legs +
    StandardPole/Pennant), forward lean ~9.2 deg baked into the REST pose
    (spine -0.06, chest -0.10, neck -0.03, head -0.02 rad).
  - low-poly skinned meshes: ivory robe w/ waist cinch + flared hem skirt,
    shoulder caps, turquoise sash, gold seam rings (collar/cuffs/hem),
    saffron hood BEHIND the skull + cowl drape, forehead gem, eyes/mouth,
    leather hip bag + diagonal gold strap, skin arms/legs, gold foot wraps,
    planted tall gold standard pole (1.6x body) with turquoise cross-blade
    pennant on a soft Pennant bone.
  - 5 clips: idle / walk / gather_start / gather_loop / gather_finish.
  - deterministic: every number authored; 2-bone IK solver places the grip
    hand on the pole shaft each frame.

Usage: blender -b -P build_pathfinder.py
Writes: ThreeRuntime/assets/citizens/pathfinder_scout.glb
"""

import json
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
# __file__ = <repo>/Tools/gltf-v2/pathfinder/build_pathfinder.py -> 4 dirnames = repo root
OUT_GLB = os.path.join(ROOT, "ThreeRuntime", "assets", "citizens", "pathfinder_scout.glb")

# ---------------------------------------------------------------------------
# palette (LINEAR RGBA — canon from v2 sheet hexes + sprite-kit linear values)
# ---------------------------------------------------------------------------
IVORY = (0.97, 0.93, 0.80, 1.0)
IVORY_SH = (0.90, 0.84, 0.68, 1.0)
SAFFRON = (0.98, 0.56, 0.14, 1.0)
SAFFRON_D = (0.86, 0.44, 0.11, 1.0)
GOLD = (0.90, 0.62, 0.24, 1.0)
GOLD_L = (1.0, 0.90, 0.24, 1.0)
GOLD_LINE = (0.88, 0.56, 0.19, 1.0)
TURQ = (0.25, 0.65, 0.65, 1.0)
TURQ_L = (0.49, 0.81, 0.79, 1.0)
SKIN = (0.80, 0.61, 0.42, 1.0)
SKIN_SH = (0.66, 0.48, 0.31, 1.0)
LEATHER = (0.62, 0.44, 0.28, 1.0)
LEATHER_D = (0.50, 0.35, 0.21, 1.0)
EYE = (0.10, 0.07, 0.05, 1.0)

MATS = {}


def material(name, color, metallic=0.0, roughness=0.85, emission=0.0,
             emission_color=None):
    """Separate Principled material per class (cloth / gold / turquoise /
    emissive seam / skin / leather). Emission strength drives the self-
    luminous solar-fabric look (EEVEE: keep metallic low, lean on emission)."""
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission > 0:
            ec = emission_color if emission_color is not None else color
            bsdf.inputs["Emission Color"].default_value = (*ec[:3], 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission
    MATS[name] = m
    return m


def make_materials():
    material("pf_ivory", IVORY, 0.0, 0.85, 0.34)          # solar fabric
    material("pf_ivory_sh", IVORY_SH, 0.0, 0.88, 0.22)    # skirt
    material("pf_saffron", SAFFRON, 0.0, 0.80, 0.35)      # hood
    material("pf_saffron_d", SAFFRON_D, 0.0, 0.85, 0.20)  # cowl drape
    material("pf_turq", TURQ, 0.0, 0.55, 0.30)            # sash trim
    material("pf_turq_l", TURQ_L, 0.0, 0.45, 0.90)        # luminous pennant
    material("pf_gold", GOLD, 0.35, 0.30, 0.80)           # pole / foot wraps
    material("pf_gold_line", GOLD_LINE, 0.25, 0.35, 0.90)  # seam rings / strap
    material("pf_gold_l", GOLD_L, 0.20, 0.30, 1.20)       # gem
    material("pf_skin", SKIN, 0.0, 0.70, 0.0)
    material("pf_skin_sh", SKIN_SH, 0.0, 0.75, 0.0)
    material("pf_leather", LEATHER, 0.0, 0.90, 0.0)
    material("pf_leather_d", LEATHER_D, 0.0, 0.90, 0.0)
    material("pf_eye", EYE, 0.0, 0.40, 0.0)


# ---------------------------------------------------------------------------
# coordinate helpers: design space (X right, Y up, Z fwd, front=-Z) ->
# Blender native (X right, Z up, Y fwd, front=-Y). Author in Blender space so
# the stock glTF exporter (Y-up, -Z-forward) round-trips exactly.
# ---------------------------------------------------------------------------
def B(x, y, z):
    """design (x, y_up, z_fwd) -> Blender (x, z, y)."""
    return (x, z, y)


DEG = math.pi / 180.0

# ---------------------------------------------------------------------------
# scene setup
# ---------------------------------------------------------------------------
def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in list(bpy.data.collections):
        if col.name != "Collection":
            bpy.data.collections.remove(col)
    sc = bpy.context.scene
    sc.render.fps = 30
    sc.render.fps_base = 1
    sc.unit_settings.scale_length = 1.0


# ---------------------------------------------------------------------------
# primitives (each created, then transforms applied so verts carry the final
# coords and the object sits at the origin with identity transform — safest
# for the glTF skin exporter)
# ---------------------------------------------------------------------------
def finalize(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)
    return obj


def prim_cylinder(name, mat, loc, r, h, segs=8):
    # Blender cylinder axis = Blender Z = design Y (up) — no rotation needed.
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=h,
                                        location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return finalize(obj)


def prim_sphere(name, mat, loc, r, scale=(1.0, 1.0, 1.0), segs=8, rings=5):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings,
                                         radius=r, location=loc)
    obj = bpy.context.object
    obj.name = name
    # Blender sphere is Z-up: scale (sx, sy, sz) Blender = design (sx, sz, sy)
    obj.scale = (scale[0], scale[2], scale[1])
    obj.data.materials.append(mat)
    return finalize(obj)


def prim_box(name, mat, loc, half):
    """half = design half-extents (hx, hy, hz) -> Blender (hx, hz, hy)."""
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (half[0], half[2], half[1])
    obj.data.materials.append(mat)
    return finalize(obj)


def prim_torus(name, mat, loc, R, r, major_segs=14, minor_segs=5):
    # Blender torus default lies in the XY plane (hole along Z) = a horizontal
    # ring around the vertical body — no rotation needed.
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r,
                                     major_segments=major_segs,
                                     minor_segments=minor_segs, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return finalize(obj)


def lathe_tube(name, mat, profile, segs=10):
    """Open tube from a (y, radius) profile in DESIGN space; rings at
    theta_j = 2*pi*j/segs around +Y. Capped both ends with fans."""
    rings = len(profile)
    verts = []
    for (y, r) in profile:
        for j in range(segs):
            th = 2.0 * math.pi * j / segs
            verts.append(B(r * math.cos(th), y, r * math.sin(th)))
    faces = []
    for i in range(rings - 1):
        for j in range(segs):
            j2 = (j + 1) % segs
            a = i * segs + j
            b = i * segs + j2
            c = (i + 1) * segs + j2
            d = (i + 1) * segs + j
            faces.append((a, b, c, d))
    # caps: top ring (y = profile[-1][0]), bottom ring (y = profile[0][0])
    for ring_idx, y, r in ((rings - 1, profile[-1][0], profile[-1][1]),
                           (0, profile[0][0], profile[0][1])):
        center = len(verts)
        verts.append(B(0.0, y, 0.0))
        fan = [center]
        for j in range(segs):
            fan.append(ring_idx * segs + j)
        faces.append(tuple(fan))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return finalize(obj)


# ---------------------------------------------------------------------------
# armature
# ---------------------------------------------------------------------------
BONES = [
    # (name, head, tail, parent)  — design coords, converted to Blender
    ("Root", (0, 0.00, 0), (0, 0.04, 0), None),
    ("Hips", (0, 0.88, 0), (0, 0.94, 0), "Root"),
    ("Spine", (0, 0.94, 0), (0, 1.04, 0), "Hips"),
    ("Chest", (0, 1.04, 0), (0, 1.16, 0), "Spine"),
    ("Neck", (0, 1.16, 0), (0, 1.30, 0), "Chest"),
    ("Head", (0, 1.30, 0), (0, 1.53, 0), "Neck"),
    ("Shoulder_L", (0.115, 1.12, 0), (0.135, 1.12, 0), "Chest"),
    ("UpperArm_L", (0.135, 1.12, 0), (0.135, 0.84, 0), "Shoulder_L"),
    ("LowerArm_L", (0.135, 0.84, 0), (0.135, 0.58, 0), "UpperArm_L"),
    ("Hand_L", (0.135, 0.58, 0), (0.135, 0.55, 0), "LowerArm_L"),
    ("Shoulder_R", (-0.115, 1.12, 0), (-0.135, 1.12, 0), "Chest"),
    ("UpperArm_R", (-0.135, 1.12, 0), (-0.135, 0.84, 0), "Shoulder_R"),
    ("LowerArm_R", (-0.135, 0.84, 0), (-0.135, 0.58, 0), "UpperArm_R"),
    ("Hand_R", (-0.135, 0.58, 0), (-0.135, 0.55, 0), "LowerArm_R"),
    ("UpperLeg_L", (0.065, 0.88, 0), (0.065, 0.47, 0), "Hips"),
    ("LowerLeg_L", (0.065, 0.47, 0), (0.065, 0.08, 0), "UpperLeg_L"),
    ("Foot_L", (0.065, 0.08, 0), (0.065, 0.06, -0.08), "LowerLeg_L"),
    ("UpperLeg_R", (-0.065, 0.88, 0), (-0.065, 0.47, 0), "Hips"),
    ("LowerLeg_R", (-0.065, 0.47, 0), (-0.065, 0.08, 0), "UpperLeg_R"),
    ("Foot_R", (-0.065, 0.08, 0), (-0.065, 0.06, -0.08), "LowerLeg_R"),
    # planted standard: origin at the ground, pole runs up design-Y
    ("StandardPole", (0.24, 0.004, -0.18), (0.24, 2.75, -0.18), "Root"),
    ("Pennant", (0.24, 2.55, -0.18), (0.24, 2.65, -0.18), "StandardPole"),
]

# forward lean baked into the REST pose (rad, about design X = Blender X):
# positive rx pitches up-axis toward +Y = BACKWARD (front is -Y), so forward
# lean is NEGATIVE.  spine+chest cum = -0.16 rad = -9.2 deg  (spec 8-12).
LEAN = {"Spine": -0.06, "Chest": -0.10, "Neck": -0.03, "Head": -0.02}

# clip grip target (design space): shaft at (0.24, grip_y, -0.18)
GRIP_Y = 0.72
GRIP_TARGET = (0.24, GRIP_Y, -0.18)


def build_armature():
    arm_data = bpy.data.armatures.new("PathfinderScoutRig")
    arm = bpy.data.objects.new("PathfinderScout", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for (name, head, tail, parent) in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = Vector(B(*head))
        eb.tail = Vector(B(*tail))
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")

    # bake the forward lean into the rest/bind pose
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    for name, ang in LEAN.items():
        arm.pose.bones[name].rotation_euler = Euler((ang, 0.0, 0.0))
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


ARM = None  # set by build_meshes


def skin(obj, groups):
    """groups: {bone_name: weight} or {bone_name: callable(vert_co_design) -> w}.

    First group replaces (wipes default group-0 weight), later groups ADD so
    multi-bone verts accumulate deterministically."""
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = ARM
    first = True
    for bone, w in groups.items():
        g = obj.vertex_groups.new(name=bone)
        mode = "REPLACE" if first else "ADD"
        if callable(w):
            for v in obj.data.vertices:
                ww = w(Vector((v.co[0], v.co[2], v.co[1])))  # Blender -> design
                if ww > 0.0:
                    g.add([v.index], ww, mode)
        else:
            g.add([i for i in range(len(obj.data.vertices))], w, mode)
        first = False
    obj.parent = ARM
    return obj


# ---------------------------------------------------------------------------
# meshes
# ---------------------------------------------------------------------------
def build_meshes():
    global ARM
    make_materials()
    ARM = build_armature()

    m_ivory = MATS["pf_ivory"]
    m_ivory_sh = MATS["pf_ivory_sh"]
    m_saffron = MATS["pf_saffron"]
    m_saffron_d = MATS["pf_saffron_d"]
    m_turq = MATS["pf_turq"]
    m_turq_l = MATS["pf_turq_l"]
    m_gold = MATS["pf_gold"]
    m_gold_line = MATS["pf_gold_line"]
    m_gold_l = MATS["pf_gold_l"]
    m_skin = MATS["pf_skin"]
    m_skin_sh = MATS["pf_skin_sh"]
    m_leather = MATS["pf_leather"]
    m_leather_d = MATS["pf_leather_d"]
    m_eye = MATS["pf_eye"]

    # ---- robe (waist-cinched) + flared skirt --------------------------------
    lathe_tube("robe", m_ivory, [
        (1.16, 0.105), (1.10, 0.118), (1.00, 0.112),
        (0.92, 0.098), (0.84, 0.086), (0.80, 0.082),
    ])
    lathe_tube("skirt", m_ivory_sh, [
        (0.80, 0.082), (0.70, 0.096), (0.58, 0.114),
        (0.46, 0.132), (0.34, 0.152),
    ])

    # ---- torso trim --------------------------------------------------------
    prim_torus("sash", m_turq, B(0, 0.80, 0), 0.082, 0.018)
    prim_torus("collar_ring", m_gold_line, B(0, 1.14, 0), 0.108, 0.015)
    prim_torus("hem_ring", m_gold_line, B(0, 0.335, 0), 0.150, 0.013)

    # shoulder caps (wider chest read)
    for side, sx in (("L", 1), ("R", -1)):
        prim_sphere(f"shoulder_cap_{side}", m_ivory, B(sx * 0.115, 1.10, 0),
                    0.058)

    # ---- head --------------------------------------------------------------
    prim_sphere("head", m_skin, B(0, 1.53, 0), 0.165)
    prim_cylinder("neck", m_skin, B(0, 1.21, 0), 0.045, 0.20)
    # saffron hood BEHIND the skull (face plane stays clear), rising above
    # the crown like a cowl; plus a cowl drape behind the neck
    prim_sphere("hood", m_saffron, B(0, 1.555, 0.09), 0.19,
                scale=(1.0, 1.18, 1.05))
    prim_sphere("hood_drape", m_saffron_d, B(0, 1.33, 0.10), 0.13,
                scale=(1.05, 1.25, 0.85))
    prim_sphere("gem", m_gold_l, B(0, 1.60, -0.175), 0.026)
    prim_sphere("eye_L", m_eye, B(0.042, 1.515, -0.150), 0.014)
    prim_sphere("eye_R", m_eye, B(-0.042, 1.515, -0.150), 0.014)
    prim_box("mouth", m_eye, B(0, 1.44, -0.155), (0.014, 0.004, 0.004))

    # ---- arms / hands / cuffs ----------------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        prim_cylinder(f"upperarm_{side}", m_skin, B(sx * 0.135, 0.98, 0),
                      0.034, 0.28)
        prim_cylinder(f"forearm_{side}", m_skin_sh, B(sx * 0.135, 0.71, 0),
                      0.030, 0.26)
        prim_sphere(f"hand_{side}", m_skin, B(sx * 0.135, 0.565, 0), 0.033)
        prim_torus(f"cuff_{side}", m_gold_line, B(sx * 0.135, 0.585, 0),
                   0.033, 0.010)

    # ---- legs / feet (gold foot wraps) -------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        prim_cylinder(f"thigh_{side}", m_skin, B(sx * 0.065, 0.675, 0),
                      0.042, 0.41)
        prim_cylinder(f"shin_{side}", m_skin_sh, B(sx * 0.065, 0.275, 0),
                      0.036, 0.39)
        prim_box(f"foot_{side}", m_gold, B(sx * 0.065, 0.055, -0.05),
                 (0.045, 0.028, 0.075))

    # ---- hip bag (opposite the pole) + diagonal strap ----------------------
    prim_box("bag", m_leather_d, B(-0.145, 0.635, -0.030), (0.070, 0.058, 0.095))
    prim_box("bag_flap", m_leather, B(-0.145, 0.695, -0.030), (0.070, 0.022, 0.095))
    # diagonal ribbon: right hip -> left shoulder (design XY plane)
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=B(-0.0075, 0.89, 0.005))
    strap = bpy.context.object
    strap.name = "strap"
    strap.scale = (0.022, 0.008, 0.226)  # Blender (x, z, y) -> design (0.022, 0.226, 0.008)
    strap.rotation_euler = (0.0, math.radians(32.8), 0.0)
    strap.data.materials.append(m_gold_line)
    finalize(strap)

    # ---- standard: planted pole, base disc, finial, cross-blade pennant ----
    prim_cylinder("pole", m_gold, B(0.24, 1.377, -0.18), 0.020, 2.746)
    prim_cylinder("pole_base", m_gold, B(0.24, 0.011, -0.18), 0.055, 0.014)
    prim_sphere("finial", m_gold, B(0.24, 2.732, -0.18), 0.018)
    prim_box("blade_x", m_turq_l, B(0.24, 2.60, -0.18), (0.085, 0.010, 0.022))
    prim_box("blade_z", m_turq_l, B(0.24, 2.60, -0.18), (0.010, 0.010, 0.085))
    prim_sphere("pennant_hub", m_gold, B(0.24, 2.60, -0.18), 0.014)

    # ---- skinning ----------------------------------------------------------
    def robe_weights(bone):
        def f(v):
            y = v[1]
            hips = max(0.0, min(1.0, (1.00 - y) / 0.16))
            chest = max(0.0, min(1.0, (y - 0.94) / 0.18))
            spine = max(0.0, 1.0 - hips - chest)
            return {"Hips": hips, "Spine": spine, "Chest": chest}[bone]
        return f

    skin(bpy.data.objects["robe"], {
        "Hips": robe_weights("Hips"),
        "Spine": robe_weights("Spine"),
        "Chest": robe_weights("Chest"),
    })
    def w_thigh(side):
        def f(v):
            if (v[0] < 0) != (side == "L"):
                return 0.0
            return max(0.0, min(1.0, (0.52 - v[1]) / 0.14))
        return f

    skin(bpy.data.objects["skirt"], {
        "Hips": lambda v: max(0.0, min(1.0, (v[1] - 0.38) / 0.16)),
        "UpperLeg_L": w_thigh("L"),
        "UpperLeg_R": w_thigh("R"),
    })
    skin(bpy.data.objects["sash"], {"Hips": 1.0})
    skin(bpy.data.objects["collar_ring"], {"Chest": 1.0})
    skin(bpy.data.objects["hem_ring"], {"Hips": 1.0})
    for side in ("L", "R"):
        skin(bpy.data.objects[f"shoulder_cap_{side}"], {f"Shoulder_{side}": 1.0})
    skin(bpy.data.objects["head"], {"Head": 1.0})
    skin(bpy.data.objects["neck"], {"Neck": 1.0})
    skin(bpy.data.objects["hood"], {"Head": 1.0})
    skin(bpy.data.objects["hood_drape"], {"Head": 1.0})
    skin(bpy.data.objects["gem"], {"Head": 1.0})
    skin(bpy.data.objects["eye_L"], {"Head": 1.0})
    skin(bpy.data.objects["eye_R"], {"Head": 1.0})
    skin(bpy.data.objects["mouth"], {"Head": 1.0})
    for side in ("L", "R"):
        skin(bpy.data.objects[f"upperarm_{side}"], {f"UpperArm_{side}": 1.0})
        skin(bpy.data.objects[f"forearm_{side}"], {f"LowerArm_{side}": 1.0})
        skin(bpy.data.objects[f"hand_{side}"], {f"Hand_{side}": 1.0})
        skin(bpy.data.objects[f"cuff_{side}"], {f"Hand_{side}": 1.0})
        skin(bpy.data.objects[f"thigh_{side}"], {f"UpperLeg_{side}": 1.0})
        skin(bpy.data.objects[f"shin_{side}"], {f"LowerLeg_{side}": 1.0})
        skin(bpy.data.objects[f"foot_{side}"], {f"Foot_{side}": 1.0})
    skin(bpy.data.objects["bag"], {"Hips": 1.0})
    skin(bpy.data.objects["bag_flap"], {"Hips": 1.0})
    skin(bpy.data.objects["strap"], {"Chest": 1.0})
    skin(bpy.data.objects["pole"], {"StandardPole": 1.0})
    skin(bpy.data.objects["pole_base"], {"StandardPole": 1.0})
    skin(bpy.data.objects["finial"], {"StandardPole": 1.0})
    skin(bpy.data.objects["blade_x"], {"Pennant": 1.0})
    skin(bpy.data.objects["blade_z"], {"Pennant": 1.0})
    skin(bpy.data.objects["pennant_hub"], {"Pennant": 1.0})
    return ARM


# ---------------------------------------------------------------------------
# clip authoring — deterministic, explicit values
# ---------------------------------------------------------------------------
def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)


def ik_arm(arm, shoulder_name, elbow_name, hand_name, target_design,
           bend_ref_design):
    """2-bone IK: place the hand bone head on target. Rotations are set in
    each bone's local frame via matrix math (rest-frame aware). All values
    deterministic. target/bend_ref in DESIGN space (converted inside)."""
    tgt = Vector(B(*target_design))
    bref = Vector(B(*bend_ref_design))
    pb_s = arm.pose.bones[shoulder_name]
    pb_e = arm.pose.bones[elbow_name]
    pb_h = arm.pose.bones[hand_name]
    L1 = (pb_s.bone.tail_local - pb_s.bone.head_local).length
    L2 = (pb_e.bone.tail_local - pb_e.bone.head_local).length
    S = pb_s.matrix.translation
    d = (tgt - S)
    dist = d.length
    if dist < 1e-6 or dist >= L1 + L2 - 1e-4:
        return
    u = d / dist
    cos_a = (L1 * L1 + dist * dist - L2 * L2) / (2.0 * L1 * dist)
    cos_a = max(-1.0, min(1.0, cos_a))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    n = u.cross(bref)
    if n.length < 1e-6:
        n = Vector((0.0, 0.0, 1.0))
    n.normalize()
    perp = n.cross(u)
    perp.normalize()
    E = S + L1 * (cos_a * u + sin_a * perp)
    T_elbow = E
    T_hand = tgt
    for pb, tgt_pt in ((pb_s, T_elbow), (pb_e, T_hand)):
        aim = (tgt_pt - pb.matrix.translation).normalized()
        # desired rotation: bone local +Y -> aim; pick X via cross with a hint
        hint = Vector((0.0, 0.0, 1.0))
        if abs(aim.dot(hint)) > 0.95:
            hint = Vector((1.0, 0.0, 0.0))
        x_ax = aim.cross(hint).normalized()
        z_ax = x_ax.cross(aim).normalized()
        R_des = Matrix((x_ax, aim, z_ax)).transposed().to_4x4()
        # local basis = parent_pose^-1 * desired * rest_local^-1
        if pb.parent is not None:
            M_parent = pb.parent.matrix
        else:
            M_parent = Matrix.Identity(4)
        M_rest_local = pb.bone.matrix_local.copy()
        if pb.parent is not None:
            M_rest_local = pb.parent.bone.matrix_local.inverted() @ M_rest_local
        M_basis = M_parent.inverted() @ R_des @ M_rest_local.inverted()
        loc, rot, scl = M_basis.decompose()
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = rot
    # hand: keep a neutral forward tilt so it reads as gripping
    pb_h.rotation_mode = "XYZ"
    pb_h.rotation_euler = Euler((0.0, 0.0, 0.0))


def key_bones(arm, frame, rots, locs):
    """Apply rot/loc to pose bones and keyframe them."""
    for name, rot in rots.items():
        pb = arm.pose.bones[name]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler(rot)
    for name, loc in locs.items():
        pb = arm.pose.bones[name]
        pb.location = Vector(loc)
    bpy.context.view_layer.update()
    for name in rots:
        arm.pose.bones[name].keyframe_insert("rotation_euler", frame=frame)
    for name in locs:
        arm.pose.bones[name].keyframe_insert("location", frame=frame)


def new_action(arm, name, nframes, sampler):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    reset_pose(arm)
    ik_bones = ("Shoulder_L", "UpperArm_L", "LowerArm_L", "Hand_L")
    for f in range(nframes):
        bpy.context.scene.frame_set(f)
        pose = sampler(f)
        key_bones(arm, f, pose["rot"], pose.get("loc", {}))
        # left grip arm: IK onto the pole shaft
        bpy.context.view_layer.update()
        ik_arm(arm, "Shoulder_L", "UpperArm_L", "LowerArm_L", GRIP_TARGET,
               (0.55, 0.0, -0.84))
        bpy.context.view_layer.update()
        for bname in ik_bones:
            pb = arm.pose.bones[bname]
            if pb.rotation_mode == "QUATERNION":
                pb.keyframe_insert("rotation_quaternion", frame=f)
            else:
                pb.keyframe_insert("rotation_euler", frame=f)
    act.frame_range = (0, nframes - 1)
    return act


def s_idle(f):
    n = 120
    ph = 2.0 * math.pi * f / n
    return {
        "rot": {
            "Hips": (0.0, 0.0, 0.010 * math.sin(ph)),
            "Spine": (0.008 * math.sin(ph), 0.0, 0.0),
            "Chest": (0.012 * math.sin(ph), 0.0, 0.0),
            "Neck": (0.005 * math.sin(ph), 0.0, 0.0),
            "Head": (0.004 * math.sin(ph), 0.0, 0.0),
            "Shoulder_R": (0.015 * math.sin(ph + 1.0), 0.0, 0.02),
            "LowerArm_R": (0.12, 0.0, 0.0),
            "UpperLeg_L": (0.06, 0.0, 0.0),
            "LowerLeg_L": (-0.08, 0.0, 0.0),
            "Foot_L": (0.03, 0.0, 0.0),
            "UpperLeg_R": (0.06, 0.0, 0.0),
            "LowerLeg_R": (-0.08, 0.0, 0.0),
            "Foot_R": (0.03, 0.0, 0.0),
            "Pennant": (0.022 * math.sin(ph), 0.0,
                        0.030 * math.sin(ph + 0.7)),
        },
        "loc": {"Hips": (0.0, 0.006 * math.sin(ph), 0.0)},
    }


def s_walk(f):
    n = 30
    ph = 2.0 * math.pi * f / n
    amp, arm_amp = 0.66, 0.9
    bob = 0.010 * abs(math.sin(2.0 * ph))
    roll = 0.028 * math.sin(2.0 * ph + math.pi / 2.0)
    sh_r = -arm_amp * math.sin(ph + math.pi) * 0.6
    return {
        "rot": {
            "Hips": (0.0, 0.0, 0.05 * math.sin(2.0 * ph)),
            "Spine": (0.5 * roll, 0.0, 0.0),
            "Chest": (roll, 0.0, 0.0),
            "Neck": (0.6 * roll, 0.0, 0.0),
            "Head": (0.5 * roll, 0.0, 0.0),
            "Shoulder_R": (sh_r, 0.0, 0.02),
            "LowerArm_R": (0.15 + 0.35 * abs(sh_r), 0.0, 0.0),
            "UpperLeg_L": (amp * math.sin(ph), 0.0, 0.0),
            "LowerLeg_L": (-max(0.0, math.cos(ph)) * 0.6 * amp, 0.0, 0.0),
            "Foot_L": (0.02 * math.sin(ph), 0.0, 0.0),
            "UpperLeg_R": (amp * math.sin(ph + math.pi), 0.0, 0.0),
            "LowerLeg_R": (-max(0.0, math.cos(ph + math.pi)) * 0.6 * amp,
                           0.0, 0.0),
            "Foot_R": (0.02 * math.sin(ph + math.pi), 0.0, 0.0),
            "StandardPole": (0.4 * roll, 0.0, 0.0),
            "Pennant": (0.025 * math.sin(ph) + 0.015 * math.sin(2.0 * ph),
                        0.0, 0.035 * math.sin(ph + 1.0)),
        },
        "loc": {"Hips": (0.0, bob, 0.0)},
    }


def _gather_crouch(t):
    """Blend factor t in [0,1]: standing -> crouch reach. All additive on top
    of the bind lean."""
    return {
        "rot": {
            "Spine": (-0.06 * t, 0.0, 0.0),
            "Chest": (-0.08 * t, 0.0, 0.0),
            "Neck": (-0.03 * t, 0.0, 0.0),
            "Head": (-0.02 * t, 0.0, 0.0),
            "UpperLeg_L": (0.30 * t, 0.0, 0.0),
            "LowerLeg_L": (-0.50 * t, 0.0, 0.0),
            "UpperLeg_R": (0.30 * t, 0.0, 0.0),
            "LowerLeg_R": (-0.50 * t, 0.0, 0.0),
            "Foot_L": (0.10 * t, 0.0, 0.0),
            "Foot_R": (0.10 * t, 0.0, 0.0),
            "Shoulder_R": (-0.50 * t, 0.30 * t, 0.10 * t),
            "LowerArm_R": (0.95 * t, 0.0, 0.0),
            "Hand_R": (0.05 * t, 0.0, 0.0),
            "Pennant": (0.02 * t, 0.0, 0.03 * t),
        },
        "loc": {"Hips": (0.0, -0.10 * t, 0.0)},
    }


def s_gather_start(f):
    n = 15
    t = f / (n - 1)
    base = _gather_crouch(t)
    base["rot"]["Pennant"] = (0.015 * math.sin(2.0 * math.pi * f / n),
                              0.0, 0.02 * math.sin(2.0 * math.pi * f / n))
    return base


def s_gather_loop(f):
    n = 30
    ph = 2.0 * math.pi * f / n
    base = _gather_crouch(1.0)
    # work bob: hips +-0.015, chest rock +-0.02, reach hand pulse
    base["loc"]["Hips"] = (0.0, -0.10 + 0.015 * math.sin(ph), 0.0)
    base["rot"]["Chest"] = (-0.08 + 0.02 * math.sin(ph), 0.0, 0.0)
    base["rot"]["LowerArm_R"] = (0.95 + 0.06 * math.sin(ph + 1.0), 0.0, 0.0)
    base["rot"]["Pennant"] = (0.025 * math.sin(ph), 0.0, 0.035 * math.sin(ph + 0.7))
    return base


def s_gather_finish(f):
    n = 15
    t = 1.0 - f / (n - 1)
    base = _gather_crouch(t)
    base["rot"]["Pennant"] = (0.015 * math.sin(2.0 * math.pi * f / n),
                              0.0, 0.02 * math.sin(2.0 * math.pi * f / n))
    return base


CLIPS = [
    ("idle", 120, s_idle),
    ("walk", 30, s_walk),
    ("gather_start", 15, s_gather_start),
    ("gather_loop", 30, s_gather_loop),
    ("gather_finish", 15, s_gather_finish),
]


def build_clips(arm):
    for (name, n, sampler) in CLIPS:
        new_action(arm, name, n, sampler)


# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------
def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kwargs = dict(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_skins=True,
        export_animations=True,
        export_anim_rest_position_armature=True,
        export_frame_range=False,
        export_current_frame=False,
        export_nla_strips=True,
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError as e:
        # older/newer exporter signatures: retry with the core kwargs only
        print("EXPORT_KWARGS_FALLBACK:", e)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                                  export_yup=True, export_skins=True,
                                  export_animations=True)


def summary():
    arm = bpy.data.objects["PathfinderScout"]
    bones = len(arm.data.bones)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    verts = sum(len(o.data.vertices) for o in objs)
    polys = sum(len(o.data.polygons) for o in objs)
    print("=== build summary ===")
    print(f"bones: {bones}")
    print(f"mesh objects: {len(objs)}")
    print(f"total verts: {verts}  polys: {polys}")
    print("actions:", sorted(a.name for a in bpy.data.actions))
    print("materials:", sorted(MATS.keys()))
    print(f"glb: {OUT_GLB}")


def main():
    clear_scene()
    build_meshes()
    build_clips(ARM)
    export_glb(OUT_GLB)
    summary()


if __name__ == "__main__":
    main()
