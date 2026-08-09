#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sunwoven Citizen (Villager) — GLTF v2 builder, FROM SCRATCH.

Self-contained Blender 5.2 headless script. Builds the villager armature +
low-poly skinned meshes + materials + 6 authored clips, exports
ThreeRuntime/assets/citizens/citizen_villager.glb, then renders 4 dark-composite
turnaround QA views (front / side-E / rear / 3-4) into Docs/QA/ThreeJS/villager-v2/
and writes the clip manifest JSON.

Canon: sunwoven-villager-character-sheet.png (v2) + hermes-brief.md.
Palette (linear RGBA, from the sprite fidelity passes):
  IVORY (0.97,0.93,0.80) emis 0.34 | SAFFRON (0.98,0.56,0.14) emis 0.45
  TURQ (0.25,0.65,0.65) emis 0.35  | GOLD (0.90,0.62,0.24) metal 0.35 emis 0.8
  SKIN (0.80,0.61,0.42)            | LEATHER (0.62,0.44,0.28)

Conventions: Blender scene is Z-up; the GLTF exporter converts to glTF Y-up
(gltf = (bx, bz, -by)), so the character is authored standing along +Z facing
+Y, which becomes +Y up facing -Z (Three.js convention). Unit height 1.70 m,
ground anchor at feet center. Head:body ~1:4.5 (per v2 sheet).

Determinism: no randomness anywhere; every number authored; linear keyframes.
"""

import json
import math
import os

import bpy
from mathutils import Quaternion, Vector

# ----------------------------------------------------------------------------
# Paths / constants
# ----------------------------------------------------------------------------
ROOT = "/Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield-threejs-wkwebview"
GLB_PATH = os.path.join(ROOT, "ThreeRuntime/assets/citizens/citizen_villager.glb")
QA_DIR = os.path.join(ROOT, "Docs/QA/ThreeJS/villager-v2")
MANIFEST_PATH = os.path.join(QA_DIR, "villager_v2_clip_manifest.json")
os.makedirs(QA_DIR, exist_ok=True)

FPS = 24.0
TWO_PI = 2.0 * math.pi
PI = math.pi

# ----------------------------------------------------------------------------
# Palette (linear RGBA, canon from sprite pipeline / v2 sheet)
# ----------------------------------------------------------------------------
IVORY = (0.97, 0.93, 0.80, 1.0)
SAFFRON = (0.98, 0.56, 0.14, 1.0)
TURQ = (0.25, 0.65, 0.65, 1.0)
GOLD = (0.90, 0.62, 0.24, 1.0)
GOLD_L = (1.00, 0.90, 0.24, 1.0)
GOLD_LINE = (0.88, 0.56, 0.19, 1.0)
SKIN = (0.80, 0.61, 0.42, 1.0)
LEATHER = (0.62, 0.44, 0.28, 1.0)
LEATHER_D = (0.50, 0.35, 0.21, 1.0)


def mat(name, base, roughness=0.8, metallic=0.0, emission=0.0, emission_color=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    tree = m.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
        out = tree.nodes.get("Material Output")
        if out is None:
            out = tree.nodes.new("ShaderNodeOutputMaterial")
        tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = emission_color or base
        bsdf.inputs["Emission Strength"].default_value = emission
    m.diffuse_color = base
    return m


MATS = {}


def build_materials():
    MATS.update({
        "ivory": mat("villager_ivory", IVORY, roughness=0.85, emission=0.34),
        "saffron": mat("villager_saffron", SAFFRON, roughness=0.8, emission=0.45),
        "turq": mat("villager_turq", TURQ, roughness=0.6, emission=0.35),
        "gold": mat("villager_gold", GOLD, metallic=0.35, roughness=0.35, emission=0.8),
        "gold_l": mat("villager_gold_l", GOLD_L, metallic=0.3, roughness=0.4, emission=1.1),
        "gold_line": mat("villager_gold_line", GOLD_LINE, metallic=0.25, roughness=0.4, emission=1.8),
        "gem": mat("villager_gem", GOLD_L, metallic=0.2, roughness=0.2, emission=2.6),
        "skin": mat("villager_skin", SKIN, roughness=0.75, emission=0.08),
        "eye": mat("villager_eye", (0.05, 0.04, 0.04, 1.0), roughness=0.6),
        "leather": mat("villager_leather", LEATHER, roughness=0.7),
        "leather_d": mat("villager_leather_d", LEATHER_D, roughness=0.75),
        "shadow": mat("villager_shadow", (0.012, 0.012, 0.016, 1.0), roughness=1.0),
    })

# ----------------------------------------------------------------------------
# Scene reset
# ----------------------------------------------------------------------------
def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for name in list(bpy.data.objects.keys()):
        bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    if bpy.context.scene.world is not None:
        bpy.context.scene.world = None
    for coll in ("meshes", "materials", "actions", "armatures", "worlds", "cameras", "lights"):
        for name in list(getattr(bpy.data, coll).keys()):
            getattr(bpy.data, coll).remove(getattr(bpy.data, coll)[name], do_unlink=True)
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 96


# ----------------------------------------------------------------------------
# Geometry helpers
# ----------------------------------------------------------------------------
def ring_cylinder(z0, z1, r0, r1, segs, cx=0.0, cy=0.0, cap_bottom=True, cap_top=True):
    """Vertical frustum; rings = [(z, start_idx, end_idx)] for weight assignment."""
    verts = []
    for z, r in ((z0, r0), (z1, r1)):
        for i in range(segs):
            a = TWO_PI * i / segs
            verts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
    n = segs
    faces = []
    for i in range(segs):
        a, b = i, (i + 1) % n
        faces.append((a, b, b + n, a + n))
    rings = [(z0, 0, n), (z1, n, 2 * n)]
    if cap_bottom:
        c = len(verts)
        verts.append((cx, cy, z0))
        faces += [(i, (i + 1) % n, c) for i in range(n)]
    if cap_top:
        c = len(verts)
        verts.append((cx, cy, z1))
        faces += [(n + i, c, n + (i + 1) % n) for i in range(n)]
    return verts, faces, rings


def frustum_4ring(zs, rs, segs, cx=0.0, cy=0.0):
    """Open frustum with 4 authored rings; returns (verts, faces, rings)."""
    verts = []
    for z, r in zip(zs, rs):
        for i in range(segs):
            a = TWO_PI * i / segs
            verts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
    n = segs
    faces = []
    for band in range(3):
        base = band * n
        for i in range(n):
            a, b = base + i, base + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    rings = [(z, i * n, (i + 1) * n) for i, z in enumerate(zs)]
    return verts, faces, rings


def sphere_mesh(cx, cy, cz, rx, ry, rz, rings, segs):
    """Lat/long sphere; rings = interior latitude rings."""
    verts = [(cx, cy, cz + rz)]
    for i in range(1, rings + 1):
        phi = PI * i / (rings + 1)
        for j in range(segs):
            th = TWO_PI * j / segs
            verts.append((cx + rx * math.sin(phi) * math.cos(th),
                          cy + ry * math.sin(phi) * math.sin(th),
                          cz + rz * math.cos(phi)))
    verts.append((cx, cy, cz - rz))
    bottom = len(verts) - 1
    faces = []
    for j in range(segs):
        a, b = 1 + j, 1 + (j + 1) % segs
        faces.append((0, b, a))
    for i in range(rings - 1):
        r0s, r1s = 1 + i * segs, 1 + (i + 1) * segs
        for j in range(segs):
            a, b = r0s + j, r0s + (j + 1) % segs
            c, d = r1s + (j + 1) % segs, r1s + j
            faces.append((a, b, c, d))
    last = 1 + (rings - 1) * segs
    for j in range(segs):
        a, b = last + j, last + (j + 1) % segs
        faces.append((a, b, bottom))
    return verts, faces


def torus_z(cx, cy, cz, major, minor, segm, segt):
    """Ring lying in the horizontal plane (band around the vertical Z axis)."""
    verts = []
    for i in range(segm):
        a = TWO_PI * i / segm
        dx, dy = math.cos(a), math.sin(a)
        for k in range(segt):
            b = TWO_PI * k / segt
            rr = major + minor * math.cos(b)
            verts.append((cx + dx * rr, cy + dy * rr, cz + minor * math.sin(b)))
    faces = []
    for i in range(segm):
        for k in range(segt):
            a0, a1 = i * segt + k, i * segt + (k + 1) % segt
            b0, b1 = ((i + 1) % segm) * segt + k, ((i + 1) % segm) * segt + (k + 1) % segt
            faces.append((a0, b0, b1, a1))
    return verts, faces


def box_center(cx, cy, cz, sx, sy, sz):
    x0, x1 = cx - sx / 2, cx + sx / 2
    y0, y1 = cy - sy / 2, cy + sy / 2
    z0, z1 = cz - sz / 2, cz + sz / 2
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def strip_box(p0, p1, width, thickness):
    """Thin closed box running from p0 (verts 0-3) to p1 (verts 4-7)."""
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    v = [
        (x0 - width / 2, y0 - thickness / 2, z0), (x0 + width / 2, y0 - thickness / 2, z0),
        (x0 + width / 2, y0 + thickness / 2, z0), (x0 - width / 2, y0 + thickness / 2, z0),
        (x1 - width / 2, y1 - thickness / 2, z1), (x1 + width / 2, y1 - thickness / 2, z1),
        (x1 + width / 2, y1 + thickness / 2, z1), (x1 - width / 2, y1 + thickness / 2, z1),
    ]
    f = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def make_mesh(name, verts, faces, material, smooth=False, groups=None, armature=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    me.materials.append(material)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if groups:
        for gname, (indices, weight) in groups.items():
            vg = obj.vertex_groups.new(name=gname)
            vg.add(list(indices), weight, "REPLACE")
    if armature is not None:
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = armature
        obj.parent = armature
    return obj


# ----------------------------------------------------------------------------
# Armature
# ----------------------------------------------------------------------------
# (name, parent, head, tail) — character stands along +Z, faces +Y
BONES = [
    ("root", None, (0.0, 0.0, 0.0), (0.0, 0.0, 0.06)),
    ("hips", "root", (0.0, 0.0, 0.95), (0.0, 0.0, 1.09)),
    ("spine", "hips", (0.0, 0.0, 1.09), (0.0, 0.0, 1.27)),
    ("chest", "spine", (0.0, 0.0, 1.27), (0.0, 0.0, 1.40)),
    ("neck", "chest", (0.0, 0.0, 1.40), (0.0, 0.0, 1.52)),
    ("head", "neck", (0.0, 0.0, 1.52), (0.0, 0.0, 1.60)),
    ("shoulder_L", "chest", (-0.145, 0.0, 1.315), (-0.170, 0.005, 1.26)),
    ("upperArm_L", "shoulder_L", (-0.170, 0.005, 1.26), (-0.178, 0.008, 1.05)),
    ("lowerArm_L", "upperArm_L", (-0.178, 0.008, 1.05), (-0.178, 0.008, 0.82)),
    ("hand_L", "lowerArm_L", (-0.178, 0.008, 0.82), (-0.178, 0.008, 0.76)),
    ("shoulder_R", "chest", (0.145, 0.0, 1.315), (0.170, 0.005, 1.26)),
    ("upperArm_R", "shoulder_R", (0.170, 0.005, 1.26), (0.178, 0.008, 1.05)),
    ("lowerArm_R", "upperArm_R", (0.178, 0.008, 1.05), (0.178, 0.008, 0.82)),
    ("hand_R", "lowerArm_R", (0.178, 0.008, 0.82), (0.178, 0.008, 0.76)),
    ("upperLeg_L", "hips", (-0.085, 0.0, 0.86), (-0.085, 0.0, 0.47)),
    ("lowerLeg_L", "upperLeg_L", (-0.085, 0.0, 0.47), (-0.085, 0.0, 0.10)),
    ("foot_L", "lowerLeg_L", (-0.085, 0.0, 0.10), (-0.085, 0.085, 0.045)),
    ("upperLeg_R", "hips", (0.085, 0.0, 0.86), (0.085, 0.0, 0.47)),
    ("lowerLeg_R", "upperLeg_R", (0.085, 0.0, 0.47), (0.085, 0.0, 0.10)),
    ("foot_R", "lowerLeg_R", (0.085, 0.0, 0.10), (0.085, 0.085, 0.045)),
    ("satchel", "hips", (0.165, 0.02, 0.86), (0.165, 0.02, 0.74)),
]

ARM = None
REST_MAT = {}  # bone name -> rest 3x3 matrix (armature space)


def build_armature():
    global ARM, REST_MAT
    arm_data = bpy.data.armatures.new("CitizenVillager_Armature")
    ARM = bpy.data.objects.new("CitizenVillager_Rig", arm_data)
    bpy.context.scene.collection.objects.link(ARM)
    bpy.context.view_layer.objects.active = ARM
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        eb.roll = 0.0
        eb.use_connect = False
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    for name, _, _, _ in BONES:
        eb = arm_data.edit_bones[name]
        REST_MAT[name] = eb.matrix.to_3x3().copy()
        m = REST_MAT[name]
        print("BONE_AXES %s X=(%.3f,%.3f,%.3f) Y=(%.3f,%.3f,%.3f) Z=(%.3f,%.3f,%.3f)" %
              (name, m[0][0], m[1][0], m[2][0], m[0][1], m[1][1], m[2][1], m[0][2], m[1][2], m[2][2]))
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_data.pose_position = "POSE"
    return ARM


# ----------------------------------------------------------------------------
# Meshes — kit inventory per v2 sheet:
# 1 headwrap 2 forehead gem 3 torso robe 4 flared skirt 5 turquoise sash
# 6 satchel body 7 satchel strap 8 gold seam rings 9 foot wraps 10 skin body
# ----------------------------------------------------------------------------
def build_meshes(arm):
    # ---- 10. skin body -----------------------------------------------------
    v, f = sphere_mesh(0.0, 0.0, 1.505, 0.105, 0.105, 0.12, 4, 12)
    make_mesh("villager_head", v, f, MATS["skin"], smooth=True,
              groups={"head": (range(len(v)), 1.0)}, armature=arm)

    # human face: dark eyes + mouth line (user-mandated; faceless heads read
    # as mannequins). Front = +Y (gem sits at y=0.125). Face zone is BELOW
    # the wrap bands (band1 torus spans z 1.453-1.517): eyes at z≈1.44 on
    # the bare skin, proud of the sphere surface (surface y≈0.088 there);
    # mouth a thin dark strip lower on the face.
    for side, ex in (("L", -0.035), ("R", 0.035)):
        v, f = sphere_mesh(ex, 0.095, 1.44, 0.012, 0.009, 0.012, 2, 8)
        make_mesh(f"villager_eye_{side}", v, f, MATS["eye"],
                  smooth=True,
                  groups={"head": (range(len(v)), 1.0)}, armature=arm)
    v, f = box_center(0.0, 0.078, 1.415, 0.048, 0.010, 0.012)
    make_mesh("villager_mouth", v, f, MATS["eye"],
              groups={"head": (range(len(v)), 1.0)}, armature=arm)

    v, f, _ = ring_cylinder(1.30, 1.40, 0.048, 0.052, 8)
    make_mesh("villager_neck", v, f, MATS["skin"], smooth=True,
              groups={"neck": (range(len(v)), 1.0)}, armature=arm)

    for side, sx in (("L", -0.160), ("R", 0.160)):
        v, f, _ = ring_cylinder(1.06, 1.26, 0.040, 0.046, 8, cx=sx)
        make_mesh("villager_upperarm_%s" % side, v, f, MATS["skin"], smooth=True,
                  groups={"upperArm_%s" % side: (range(len(v)), 1.0)}, armature=arm)
        v, f, _ = ring_cylinder(0.82, 1.06, 0.033, 0.037, 8, cx=sx)
        make_mesh("villager_forearm_%s" % side, v, f, MATS["skin"], smooth=True,
                  groups={"lowerArm_%s" % side: (range(len(v)), 1.0)}, armature=arm)
        v, f = sphere_mesh(sx, 0.008, 0.775, 0.042, 0.042, 0.045, 2, 8)
        make_mesh("villager_hand_%s" % side, v, f, MATS["skin"], smooth=True,
                  groups={"hand_%s" % side: (range(len(v)), 1.0)}, armature=arm)
        v, f = sphere_mesh(sx, 0.008, 1.05, 0.048, 0.048, 0.05, 2, 8)
        make_mesh("villager_elbow_%s" % side, v, f, MATS["skin"], smooth=True,
                  groups={"upperArm_%s" % side: (range(0, len(v) // 2), 0.5),
                          "lowerArm_%s" % side: (range(len(v) // 2, len(v)), 0.5)},
                  armature=arm)

    for side, sx in (("L", -0.085), ("R", 0.085)):
        v, f, _ = ring_cylinder(0.47, 0.86, 0.052, 0.058, 8, cx=sx)
        make_mesh("villager_thigh_%s" % side, v, f, MATS["skin"], smooth=True,
                  groups={"upperLeg_%s" % side: (range(len(v)), 1.0)}, armature=arm)
        v, f, _ = ring_cylinder(0.10, 0.47, 0.040, 0.046, 8, cx=sx)
        make_mesh("villager_shin_%s" % side, v, f, MATS["skin"], smooth=True,
                  groups={"lowerLeg_%s" % side: (range(len(v)), 1.0)}, armature=arm)
        v, f = sphere_mesh(sx, 0.0, 0.47, 0.056, 0.056, 0.058, 2, 8)
        make_mesh("villager_knee_%s" % side, v, f, MATS["skin"], smooth=True,
                  groups={"upperLeg_%s" % side: (range(0, len(v) // 2), 0.5),
                          "lowerLeg_%s" % side: (range(len(v) // 2, len(v)), 0.5)},
                  armature=arm)

    # ---- 3. torso robe (ivory; waist -> chest bulge -> collar) -------------
    v, f, rings = frustum_4ring([0.97, 1.14, 1.28, 1.36], [0.145, 0.155, 0.168, 0.105], 10)
    n = 10
    make_mesh("villager_torso", v, f, MATS["ivory"], smooth=True,
              groups={"hips": (range(0, n), 1.0),
                      "spine": (range(n, 2 * n), 1.0),
                      "chest": (range(2 * n, 4 * n), 1.0)}, armature=arm)

    # sleeves (ivory, elbow length)
    for side, sx in (("L", -0.160), ("R", 0.160)):
        v, f, _ = ring_cylinder(1.04, 1.30, 0.058, 0.066, 8, cx=sx)
        make_mesh("villager_sleeve_%s" % side, v, f, MATS["ivory"], smooth=True,
                  groups={"upperArm_%s" % side: (range(len(v)), 1.0)}, armature=arm)

    # ---- 4. flared skirt (ivory, knee-length hem) --------------------------
    v, f, rings = ring_cylinder(0.50, 0.97, 0.235, 0.155, 12, cap_bottom=False)
    n = 12
    make_mesh("villager_skirt", v, f, MATS["ivory"], smooth=True,
              groups={"hips": (range(0, n), 1.0),
                      "hips_mid": (range(n, 2 * n), 0.5),
                      "upperLeg_L_mid": (range(n, 2 * n), 0.25),
                      "upperLeg_R_mid": (range(n, 2 * n), 0.25),
                      "upperLeg_L_hem": (range(2 * n, 3 * n), 0.5),
                      "upperLeg_R_hem": (range(2 * n, 3 * n), 0.5)}, armature=arm)

    # ---- 5. turquoise sash + tail ------------------------------------------
    v, f, _ = ring_cylinder(0.925, 1.00, 0.160, 0.160, 12, cap_bottom=False, cap_top=False)
    make_mesh("villager_sash", v, f, MATS["turq"], smooth=True,
              groups={"hips": (range(len(v)), 1.0)}, armature=arm)
    v, f = strip_box((-0.135, 0.015, 0.93), (-0.125, 0.028, 0.80), 0.028, 0.012)
    make_mesh("villager_sash_tail", v, f, MATS["turq"],
              groups={"hips": (range(len(v)), 1.0)}, armature=arm)

    # ---- 1. headwrap (saffron turban: dome + 2 wrapped bands + front drape) -
    v, f = sphere_mesh(0.0, 0.0, 1.575, 0.135, 0.13, 0.125, 4, 12)
    make_mesh("villager_wrap_dome", v, f, MATS["saffron"], smooth=True,
              groups={"head": (range(len(v)), 1.0)}, armature=arm)
    v, f = torus_z(0.0, 0.0, 1.485, 0.128, 0.032, 12, 4)
    make_mesh("villager_wrap_band1", v, f, MATS["saffron"], smooth=True,
              groups={"head": (range(len(v)), 1.0)}, armature=arm)
    v, f = torus_z(0.0, 0.0, 1.545, 0.123, 0.028, 12, 4)
    make_mesh("villager_wrap_band2", v, f, MATS["saffron"], smooth=True,
              groups={"head": (range(len(v)), 1.0)}, armature=arm)
    # front drape: brow band -> hanging tail over the LEFT temple (moved off
    # the face center so the eyes/mouth stay visible; reads as a wrap tail
    # from S/E/W)
    v, f = strip_box((-0.075, 0.115, 1.44), (-0.068, 0.085, 1.38), 0.03, 0.014)
    make_mesh("villager_wrap_drape", v, f, MATS["saffron"],
              groups={"head": (range(len(v)), 1.0)}, armature=arm)

    # ---- 2. forehead gem (emissive gold diamond) ---------------------------
    gx, gy, gz = 0.0, 0.125, 1.505
    gem_v = [(gx, gy, gz + 0.035), (gx, gy, gz - 0.028), (gx - 0.020, gy, gz),
             (gx + 0.020, gy, gz), (gx, gy + 0.028, gz), (gx, gy - 0.010, gz)]
    gem_f = [(0, 2, 4), (0, 4, 3), (0, 3, 5), (0, 5, 2),
             (1, 4, 2), (1, 3, 4), (1, 5, 3), (1, 2, 5)]
    make_mesh("villager_gem", gem_v, gem_f, MATS["gem"],
              groups={"head": (range(len(gem_v)), 1.0)}, armature=arm)

    # ---- 6/7. satchel (leather) + strap + gold scrolls ----------------------
    v, f = box_center(0.165, 0.02, 0.80, 0.13, 0.10, 0.17)
    make_mesh("villager_satchel_body", v, f, MATS["leather"],
              groups={"satchel": (range(len(v)), 1.0)}, armature=arm)
    v, f = box_center(0.165, 0.072, 0.865, 0.135, 0.045, 0.02)
    make_mesh("villager_satchel_flap", v, f, MATS["leather_d"],
              groups={"satchel": (range(len(v)), 1.0)}, armature=arm)
    for i, (sx, sy, sz, ang) in enumerate([(0.135, 0.085, 0.895, 0.5), (0.175, 0.095, 0.905, 0.1),
                                           (0.212, 0.080, 0.892, -0.4)]):
        v, f, _ = ring_cylinder(sz - 0.03, sz + 0.03, 0.011, 0.011, 8, cx=sx, cy=sy)
        ca, sa = math.cos(ang), math.sin(ang)
        rv = [(x, y * ca - z * sa, y * sa + z * ca) for (x, y, z) in v]
        make_mesh("villager_scroll_%d" % i, rv, f, MATS["gold"],
                  groups={"satchel": (range(len(rv)), 1.0)}, armature=arm)
    # diagonal strap: left shoulder -> right hip (saffron)
    v, f = strip_box((-0.135, 0.085, 1.30), (0.170, 0.075, 0.90), 0.05, 0.028)
    make_mesh("villager_satchel_strap", v, f, MATS["saffron"],
              groups={"chest": (range(0, 4), 1.0), "hips": (range(4, 8), 1.0)}, armature=arm)

    # ---- 8. gold seam rings (dedicated emissive material) -------------------
    v, f = torus_z(0.0, 0.0, 1.365, 0.112, 0.019, 12, 4)
    make_mesh("villager_ring_collar", v, f, MATS["gold_line"], smooth=True,
              groups={"chest": (range(len(v)), 1.0)}, armature=arm)
    for side, sx in (("L", -0.160), ("R", 0.160)):
        v, f = torus_z(sx, 0.008, 1.045, 0.066, 0.016, 12, 4)
        make_mesh("villager_ring_cuff_%s" % side, v, f, MATS["gold_line"], smooth=True,
                  groups={"upperArm_%s" % side: (range(len(v)), 1.0)}, armature=arm)
    v, f = torus_z(0.0, 0.0, 0.50, 0.238, 0.020, 12, 4)
    make_mesh("villager_ring_hem", v, f, MATS["gold_line"], smooth=True,
              groups={"upperLeg_L": (range(0, len(v) // 2), 0.5),
                      "upperLeg_R": (range(len(v) // 2, len(v)), 0.5)}, armature=arm)

    # ---- 9. foot wraps (woven gold) -----------------------------------------
    for side, sx in (("L", -0.085), ("R", 0.085)):
        v, f = box_center(sx, 0.042, 0.026, 0.085, 0.145, 0.052)
        make_mesh("villager_foot_%s" % side, v, f, MATS["gold"],
                  groups={"foot_%s" % side: (range(len(v)), 1.0)}, armature=arm)
        v, f = torus_z(sx, 0.0, 0.075, 0.056, 0.015, 12, 4)
        make_mesh("villager_foot_ankle_%s" % side, v, f, MATS["gold"], smooth=True,
                  groups={"foot_%s" % side: (range(len(v)), 1.0)}, armature=arm)


# ----------------------------------------------------------------------------
# Animation authoring
# ----------------------------------------------------------------------------
def wq(bone_name, axis, angle):
    """Axis-angle rotation in WORLD space at rest, converted to bone-local quat."""
    m3 = REST_MAT[bone_name].inverted()
    v = (m3 @ Vector(axis)).normalized()
    return Quaternion(v, angle)


def arm_animdata():
    if ARM.animation_data is None:
        ARM.animation_data_create()
    return ARM.animation_data


def key(act, bone, frame, loc=None, rot=None, sca=None):
    arm_animdata().action = act
    pb = ARM.pose.bones[bone]
    if loc is not None:
        pb.location = Vector(loc)
        pb.keyframe_insert("location", frame=frame)
    if rot is not None:
        pb.rotation_quaternion = rot
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    if sca is not None:
        pb.scale = Vector(sca)
        pb.keyframe_insert("scale", frame=frame)


def _iter_fcurves(act):
    """Blender 5.x: fcurves live under layered actions (layers/strips/channelbags)."""
    if hasattr(act, "layers"):
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for fc in bag.fcurves:
                        yield fc
    else:  # legacy pre-5.x fallback
        for fc in act.fcurves:
            yield fc


def linearize(act):
    for fc in _iter_fcurves(act):
        fc.extrapolation = "LINEAR"
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def rest_keys(act, f):
    """Identity transforms for every animated bone at frame f."""
    for bn in ("hips", "spine", "chest", "neck", "head", "upperArm_R", "lowerArm_R",
               "hand_R", "upperArm_L", "lowerArm_L", "upperLeg_L", "lowerLeg_L",
               "upperLeg_R", "lowerLeg_R", "satchel"):
        key(act, bn, f, rot=Quaternion())


def idle_clip():
    act = bpy.data.actions.new("idle")
    arm_animdata().action = act
    for f in (0, 24, 48, 72, 96):
        t = f / 96.0 * TWO_PI
        breath = 0.022 * math.sin(t)
        sway = 0.035 * math.sin(t)
        key(act, "hips", f, rot=wq("hips", (0, 0, 1), sway * 0.55))
        key(act, "spine", f, rot=wq("spine", (1, 0, 0), breath * 0.8))
        key(act, "chest", f, rot=wq("chest", (1, 0, 0), breath * 1.2))
        key(act, "neck", f, rot=wq("neck", (1, 0, 0), breath * 0.5))
        key(act, "head", f, rot=wq("head", (1, 0, 0), breath * 0.4))
        key(act, "upperArm_L", f, rot=wq("upperArm_L", (1, 0, 0), 0.03 * math.sin(t + 0.5)))
        key(act, "upperArm_R", f, rot=wq("upperArm_R", (1, 0, 0), 0.03 * math.sin(t + 0.5)))
        key(act, "satchel", f, rot=wq("satchel", (1, 0, 0), 0.02 * math.sin(t + 1.0)))
    linearize(act)
    return act


def walk_clip():
    act = bpy.data.actions.new("walk")
    arm_animdata().action = act
    for f in (0, 6, 12, 18, 24):
        t = f / 24.0 * TWO_PI
        swing_l = 0.52 * math.sin(t)
        swing_r = 0.52 * math.sin(t + PI)
        knee_l = max(0.0, 0.85 * (0.5 - 0.5 * math.cos(t))) + 0.12
        knee_r = max(0.0, 0.85 * (0.5 - 0.5 * math.cos(t + PI))) + 0.12
        bob = 0.032 * math.sin(t + PI / 2)
        key(act, "hips", f, loc=(0.0, 0.0, bob), rot=wq("hips", (0, 0, 1), 0.05 * math.sin(t)))
        key(act, "upperLeg_L", f, rot=wq("upperLeg_L", (1, 0, 0), swing_l))
        key(act, "lowerLeg_L", f, rot=wq("lowerLeg_L", (1, 0, 0), -knee_l))
        key(act, "upperLeg_R", f, rot=wq("upperLeg_R", (1, 0, 0), swing_r))
        key(act, "lowerLeg_R", f, rot=wq("lowerLeg_R", (1, 0, 0), -knee_r))
        key(act, "foot_L", f, rot=wq("foot_L", (1, 0, 0), -0.12 * math.sin(t)))
        key(act, "foot_R", f, rot=wq("foot_R", (1, 0, 0), -0.12 * math.sin(t + PI)))
        key(act, "upperArm_L", f, rot=wq("upperArm_L", (1, 0, 0), -0.38 * math.sin(t + PI)))
        key(act, "upperArm_R", f, rot=wq("upperArm_R", (1, 0, 0), -0.38 * math.sin(t)))
        key(act, "lowerArm_L", f, rot=wq("lowerArm_L", (1, 0, 0), -0.18))
        key(act, "lowerArm_R", f, rot=wq("lowerArm_R", (1, 0, 0), -0.18))
        key(act, "spine", f, rot=wq("spine", (1, 0, 0), 0.04 * math.sin(t)))
        key(act, "chest", f, rot=wq("chest", (1, 0, 0), 0.05 * math.sin(t)))
        key(act, "satchel", f, rot=wq("satchel", (1, 0, 0), 0.10 * math.sin(t + 1.2)))
    linearize(act)
    return act


# shared poses -----------------------------------------------------------------
def contact_pose(act, f):
    """Bent to ground, right hand reaching down-forward (gather contact)."""
    key(act, "hips", f, rot=wq("hips", (1, 0, 0), 0.52))
    key(act, "spine", f, rot=wq("spine", (1, 0, 0), 0.30))
    key(act, "chest", f, rot=wq("chest", (1, 0, 0), 0.16))
    key(act, "neck", f, rot=wq("neck", (1, 0, 0), 0.12))
    key(act, "head", f, rot=wq("head", (1, 0, 0), 0.08))
    key(act, "upperArm_R", f, rot=wq("upperArm_R", (1, 0, 0), 1.30))
    key(act, "lowerArm_R", f, rot=wq("lowerArm_R", (1, 0, 0), 0.45))
    key(act, "hand_R", f, rot=wq("hand_R", (1, 0, 0), 0.25))
    key(act, "upperArm_L", f, rot=wq("upperArm_L", (1, 0, 0), -0.42))
    key(act, "lowerArm_L", f, rot=wq("lowerArm_L", (1, 0, 0), -0.15))
    key(act, "upperLeg_L", f, rot=wq("upperLeg_L", (1, 0, 0), -0.14))
    key(act, "lowerLeg_L", f, rot=wq("lowerLeg_L", (1, 0, 0), -0.30))
    key(act, "upperLeg_R", f, rot=wq("upperLeg_R", (1, 0, 0), -0.05))
    key(act, "lowerLeg_R", f, rot=wq("lowerLeg_R", (1, 0, 0), -0.12))
    key(act, "satchel", f, rot=wq("satchel", (1, 0, 0), 0.02))


def stow_pose(act, f, pulse=False):
    """Hand at satchel (right hip); slight satchel squash on stow."""
    key(act, "hips", f, rot=wq("hips", (1, 0, 0), 0.40))
    key(act, "spine", f, rot=wq("spine", (1, 0, 0), 0.22))
    key(act, "chest", f, rot=wq("chest", (1, 0, 0), 0.12))
    key(act, "neck", f, rot=wq("neck", (1, 0, 0), 0.10))
    key(act, "head", f, rot=wq("head", (1, 0, 0), 0.06))
    q_pitch = wq("upperArm_R", (1, 0, 0), 0.55)
    q_yaw = wq("upperArm_R", (0, 0, 1), 0.85)
    key(act, "upperArm_R", f, rot=q_yaw @ q_pitch)
    q_lp = wq("lowerArm_R", (1, 0, 0), 0.15)
    q_ly = wq("lowerArm_R", (0, 0, 1), 0.55)
    key(act, "lowerArm_R", f, rot=q_ly @ q_lp)
    key(act, "hand_R", f, rot=wq("hand_R", (1, 0, 0), 0.10))
    key(act, "upperArm_L", f, rot=wq("upperArm_L", (1, 0, 0), -0.30))
    key(act, "lowerArm_L", f, rot=wq("lowerArm_L", (1, 0, 0), -0.10))
    key(act, "upperLeg_L", f, rot=wq("upperLeg_L", (1, 0, 0), -0.10))
    key(act, "lowerLeg_L", f, rot=wq("lowerLeg_L", (1, 0, 0), -0.22))
    key(act, "upperLeg_R", f, rot=wq("upperLeg_R", (1, 0, 0), -0.04))
    key(act, "lowerLeg_R", f, rot=wq("lowerLeg_R", (1, 0, 0), -0.10))
    key(act, "satchel", f, sca=(1.06, 0.94, 1.04) if pulse else (1.0, 1.0, 1.0))


def gather_start_clip():
    act = bpy.data.actions.new("gather_start")
    arm_animdata().action = act
    rest_keys(act, 0)
    contact_pose(act, 48)
    for f in (12, 24, 36):
        t = f / 48.0
        for (bn, ax, val) in [("hips", (1, 0, 0), 0.52), ("spine", (1, 0, 0), 0.30),
                              ("chest", (1, 0, 0), 0.16), ("neck", (1, 0, 0), 0.12),
                              ("head", (1, 0, 0), 0.08), ("upperArm_R", (1, 0, 0), 1.30),
                              ("lowerArm_R", (1, 0, 0), 0.45), ("hand_R", (1, 0, 0), 0.25),
                              ("upperArm_L", (1, 0, 0), -0.42), ("lowerArm_L", (1, 0, 0), -0.15),
                              ("upperLeg_L", (1, 0, 0), -0.14), ("lowerLeg_L", (1, 0, 0), -0.30),
                              ("upperLeg_R", (1, 0, 0), -0.05), ("lowerLeg_R", (1, 0, 0), -0.12),
                              ("satchel", (1, 0, 0), 0.02)]:
            key(act, bn, f, rot=wq(bn, ax, val * t))
    linearize(act)
    return act


def gather_loop_clip():
    act = bpy.data.actions.new("gather_loop")
    arm_animdata().action = act
    contact_pose(act, 0)
    contact_pose(act, 12)
    stow_pose(act, 24, pulse=True)
    stow_pose(act, 36, pulse=False)
    contact_pose(act, 48)
    linearize(act)
    return act


def gather_finish_clip():
    act = bpy.data.actions.new("gather_finish")
    arm_animdata().action = act
    contact_pose(act, 0)
    for f in (12, 24, 36):
        t = f / 48.0
        for (bn, ax, val) in [("hips", (1, 0, 0), 0.52), ("spine", (1, 0, 0), 0.30),
                              ("chest", (1, 0, 0), 0.16), ("neck", (1, 0, 0), 0.12),
                              ("head", (1, 0, 0), 0.08), ("upperArm_R", (1, 0, 0), 1.30),
                              ("lowerArm_R", (1, 0, 0), 0.45), ("hand_R", (1, 0, 0), 0.25),
                              ("upperArm_L", (1, 0, 0), -0.42), ("lowerArm_L", (1, 0, 0), -0.15),
                              ("upperLeg_L", (1, 0, 0), -0.14), ("lowerLeg_L", (1, 0, 0), -0.30),
                              ("upperLeg_R", (1, 0, 0), -0.05), ("lowerLeg_R", (1, 0, 0), -0.12),
                              ("satchel", (1, 0, 0), 0.02)]:
            key(act, bn, f, rot=wq(bn, ax, val * (1.0 - t)))
    rest_keys(act, 48)
    linearize(act)
    return act


def deposit_clip():
    act = bpy.data.actions.new("deposit")
    arm_animdata().action = act
    rest_keys(act, 0)
    stow_pose(act, 14, pulse=True)
    # place: hand extended forward-down
    key(act, "hips", 28, rot=wq("hips", (1, 0, 0), 0.30))
    key(act, "spine", 28, rot=wq("spine", (1, 0, 0), 0.18))
    key(act, "chest", 28, rot=wq("chest", (1, 0, 0), 0.10))
    key(act, "neck", 28, rot=wq("neck", (1, 0, 0), 0.08))
    key(act, "head", 28, rot=wq("head", (1, 0, 0), 0.05))
    key(act, "upperArm_R", 28, rot=wq("upperArm_R", (1, 0, 0), 0.80))
    key(act, "lowerArm_R", 28, rot=wq("lowerArm_R", (1, 0, 0), 0.35))
    key(act, "hand_R", 28, rot=wq("hand_R", (1, 0, 0), 0.15))
    key(act, "upperArm_L", 28, rot=wq("upperArm_L", (1, 0, 0), -0.25))
    key(act, "lowerArm_L", 28, rot=wq("lowerArm_L", (1, 0, 0), -0.10))
    key(act, "upperLeg_L", 28, rot=wq("upperLeg_L", (1, 0, 0), -0.08))
    key(act, "lowerLeg_L", 28, rot=wq("lowerLeg_L", (1, 0, 0), -0.18))
    key(act, "upperLeg_R", 28, rot=wq("upperLeg_R", (1, 0, 0), -0.03))
    key(act, "lowerLeg_R", 28, rot=wq("lowerLeg_R", (1, 0, 0), -0.08))
    key(act, "satchel", 28, rot=wq("satchel", (1, 0, 0), 0.0), sca=(1.0, 1.0, 1.0))
    rest_keys(act, 48)
    linearize(act)
    return act


def build_clips():
    clips = [idle_clip(), walk_clip(), gather_start_clip(), gather_loop_clip(),
             gather_finish_clip(), deposit_clip()]
    arm_animdata().action = bpy.data.actions["idle"]
    return clips


# ----------------------------------------------------------------------------
# GLB export + structural parse
# ----------------------------------------------------------------------------
def export_glb():
    try:
        bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
    except Exception:
        pass
    bpy.context.scene.frame_set(0)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_skins=True,
        export_materials="EXPORT",
        export_apply=False,
        export_anim_single_armature=True,
    )
    print("GLB_EXPORTED %s size=%d" % (GLB_PATH, os.path.getsize(GLB_PATH)))


def parse_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    assert data[:4] == b"glTF", "not a glb"
    jlen = int.from_bytes(data[12:16], "little")
    js = data[20:20 + jlen].decode("utf-8")
    return json.loads(js)


def verify_glb():
    """Structural verification from the shipped GLB JSON (authoritative)."""
    g = parse_glb(GLB_PATH)
    anims = [a.get("name", "anim_%d" % i) for i, a in enumerate(g.get("animations", []))]
    bone_count = len(g["skins"][0]["joints"]) if g.get("skins") else 0
    mesh_count = len(g.get("meshes", []))
    node_count = len(g.get("nodes", []))
    material_count = len(g.get("materials", []))
    verts = 0
    for m in g.get("meshes", []):
        for p in m["primitives"]:
            verts += g["accessors"][p["attributes"]["POSITION"]]["count"]
    clip_info = []
    for a in g.get("animations", []):
        name = a.get("name", "?")
        inputs = []
        for s in a["samplers"]:
            acc = g["accessors"][s["input"]]
            inputs.append((acc.get("min", [0.0])[0], acc.get("max", [0.0])[0]))
        t0 = min(x[0] for x in inputs)
        t1 = max(x[1] for x in inputs)
        clip_info.append({"name": name, "t0_s": round(t0, 3), "t1_s": round(t1, 3),
                          "frames": int(round((t1 - t0) * FPS)) + 1,
                          "channels": len(a["channels"])})
    print("VERIFY bones=%d meshes=%d nodes=%d materials=%d verts=%d anims=%s" %
          (bone_count, mesh_count, node_count, material_count, verts, sorted(anims)))
    for c in clip_info:
        print("VERIFY_CLIP %s t0=%.3f t1=%.3f frames=%d channels=%d" %
              (c["name"], c["t0_s"], c["t1_s"], c["frames"], c["channels"]))
    return bone_count, mesh_count, verts, clip_info, material_count


# ----------------------------------------------------------------------------
# Renders (EEVEE, dark composite bg (18,18,24), bloom)
# ----------------------------------------------------------------------------
def sRGB_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def setup_render():
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    try:
        scene.eevee.taa_render_samples = 64
    except Exception:
        try:
            scene.eevee.render_samples = 64
        except Exception:
            pass
    # dark composite bg: linearize sRGB (18,18,24)
    bg = (sRGB_to_linear(18), sRGB_to_linear(18), sRGB_to_linear(24), 1.0)
    world = bpy.data.worlds.new("DarkBg")
    scene.world = world
    world.use_nodes = True
    bg_node = world.node_tree.nodes.get("Background")
    if bg_node is None:
        bg_node = world.node_tree.nodes.new("ShaderNodeBackground")
    bg_node.inputs["Color"].default_value = bg
    bg_node.inputs["Strength"].default_value = 1.0
    # bloom: EEVEE Next glow if available, else compositor Fog Glow
    glow_ok = False
    try:
        if hasattr(scene.eevee, "glow_enabled"):
            scene.eevee.glow_enabled = True
            scene.eevee.glow_intensity = 0.6
            scene.eevee.glow_threshold = 0.6
            scene.eevee.glow_bloom = 0.4
            glow_ok = True
    except Exception:
        pass
    if not glow_ok:
        scene.use_nodes = True
        tree = None
        if hasattr(scene, "compositing_node_group"):
            tree = bpy.data.node_groups.new("CompositorFallback", "CompositorNodeTree")
            scene.compositing_node_group = tree
        else:  # legacy pre-5.x
            tree = scene.node_tree
        tree.nodes.clear()
        rl = tree.nodes.new("CompositorNodeRLayers")
        glare = tree.nodes.new("CompositorNodeGlare")
        try:  # Blender 5.x: glare settings are input sockets with display-name enums
            glare.inputs["Type"].default_value = "Fog Glow"
            glare.inputs["Quality"].default_value = "High"
            glare.inputs["Threshold"].default_value = 0.55
            glare.inputs["Size"].default_value = 9
            glare.inputs["Strength"].default_value = 0.25
        except Exception:
            glare.glare_type = "FOG_GLOW"  # legacy pre-5.x
            glare.quality = "HIGH"
            glare.size = 9
            glare.threshold = 0.55
            glare.mix = 0.25
        try:
            comp = tree.nodes.new("CompositorNodeComposite")
            comp_input = comp.inputs["Image"]
        except Exception:  # Blender 5.x: group output node drives the frame
            if "Image" not in [i.name for i in tree.interface.items_tree]:
                tree.interface.new_socket(
                    "Image", in_out="OUTPUT", socket_type="NodeSocketColor")
            comp = tree.nodes.new("NodeGroupOutput")
            comp_input = comp.inputs["Image"]
        tree.links.new(rl.outputs["Image"], glare.inputs["Image"])
        tree.links.new(glare.outputs["Image"], comp_input)
    print("GLOW_MODE=" + ("eevee_next" if glow_ok else "compositor_fog_glow"))
    # contact shadow disc (render-only, added after export)
    v, f, _ = ring_cylinder(0.0, 0.004, 0.34, 0.34, 16)
    make_mesh("villager_shadow_disc", v, f, MATS["shadow"])
    # lights
    sun = bpy.data.objects.new("KeySun", bpy.data.lights.new("KeySun", "SUN"))
    scene.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.data.color = (1.0, 0.93, 0.82)
    sun.rotation_euler = Vector((2.5, 3.0, 4.0)).to_track_quat("-Z", "Y").to_euler()
    for name, loc, energy, color in [
        ("FillCool", (-3.2, 2.4, 1.4), 140.0, (0.75, 0.82, 1.0)),
        ("RimGold", (-2.6, -3.2, 3.6), 90.0, (1.0, 0.85, 0.6)),
    ]:
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        scene.collection.objects.link(light)
        light.data.energy = energy
        light.data.size = 2.4
        light.data.color = color
        light.location = Vector(loc)
        light.rotation_euler = (-Vector(loc)).to_track_quat("-Z", "Y").to_euler()


def render_views():
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("QA_Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.30
    cam = bpy.data.objects.new("QA_Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0.0, 0.0, 0.85))
    views = [
        ("front", Vector((0.0, 3.2, 0.85))),
        ("side_e", Vector((3.2, 0.0, 0.85))),
        ("rear", Vector((0.0, -3.2, 0.85))),
        ("threequarter", Vector((2.26, 2.26, 0.85))),
    ]
    scene.frame_set(0)
    for tag, cam_pos in views:
        cam.location = cam_pos
        cam.rotation_euler = (target - cam_pos).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(QA_DIR, "villager_v2_%s.png" % tag)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("RENDER %s ok size=%d" % (tag, os.path.getsize(path)))
    # debug pose frames (walk mid-stride front; gather contact 3/4)
    arm_animdata().action = bpy.data.actions["walk"]
    scene.frame_set(12)
    cam.location = Vector((0.0, 3.2, 0.85))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(QA_DIR, "villager_v2_debug_walk_front.png")
    bpy.ops.render.render(write_still=True)
    arm_animdata().action = bpy.data.actions["gather_loop"]
    scene.frame_set(0)
    cam.location = Vector((2.26, 2.26, 0.85))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(QA_DIR, "villager_v2_debug_gather_34.png")
    bpy.ops.render.render(write_still=True)
    arm_animdata().action = bpy.data.actions["idle"]
    scene.frame_set(0)


# ----------------------------------------------------------------------------
# Manifest
# ----------------------------------------------------------------------------
def write_manifest(bone_count, mesh_count, verts, clip_info, material_count):
    mesh_inventory = {}
    total_verts = 0
    total_tris = 0
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and not obj.name.startswith("villager_shadow"):
            mesh_inventory[obj.name] = {"verts": len(obj.data.vertices),
                                        "tris": len(obj.data.polygons),
                                        "material": obj.data.materials[0].name if obj.data.materials else None}
            total_verts += len(obj.data.vertices)
            total_tris += len(obj.data.polygons)
    manifest = {
        "asset": "citizen_villager.glb",
        "variant": "sunwoven-villager-v2",
        "scale": "unit height 1.70 m, +Y up (glTF), ground anchor at feet center",
        "proportions": "head:body ~1:4.5 (v2 sheet grid)",
        "facing": "-Z (Three.js convention); authored Blender +Z up facing +Y",
        "bone_count": bone_count,
        "clip_count": len(clip_info),
        "clips": clip_info,
        "mesh_count": mesh_count,
        "mesh_inventory": mesh_inventory,
        "total_vertices_glb": verts,
        "total_vertices_blender": total_verts,
        "total_tris_blender": total_tris,
        "material_count_glb": material_count,
        "glb_size_bytes": os.path.getsize(GLB_PATH),
        "render_lock": "single blender -b invocation (build + export + render)",
        "determinism": "no randomness; authored numeric keyframes; linear interpolation",
        "notes": ("emissive seams via dedicated villager_gold_line material (strength 1.8); "
                  "gem strength 2.6; EEVEE-safe metallic<=0.35; root motion: none (root bone unanimated)"),
    }
    with open(MANIFEST_PATH, "w") as fh:
        json.dump(manifest, fh, indent=2)
    print("MANIFEST_WRITTEN %s" % MANIFEST_PATH)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def main():
    reset_scene()
    build_materials()
    arm = build_armature()
    build_meshes(arm)
    build_clips()
    export_glb()
    bone_count, mesh_count, verts, clip_info, material_count = verify_glb()
    setup_render()
    render_views()
    write_manifest(bone_count, mesh_count, verts, clip_info, material_count)
    print("BUILD_DONE bones=%d meshes=%d verts=%d clips=%d glb=%d" %
          (bone_count, mesh_count, verts, len(clip_info), os.path.getsize(GLB_PATH)))


main()
print("SCRIPT_END_OK")
