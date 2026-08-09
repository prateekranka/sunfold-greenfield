#!/usr/bin/env python3
"""verify_pathfinder.py — structural verification of the exported GLB.

Imports pathfinder_scout.glb back into a fresh Blender scene and reports:
bone count + names, clip (action) names + frame ranges + keyframe counts,
mesh inventory (objects, verts, polys, material), material list, and a few
key bone world positions (orientation sanity: root at ground, head above
hips, figure facing Blender -Y == glTF -Z).

Usage: blender -b -P verify_pathfinder.py
Writes: Docs/QA/ThreeJS/pathfinder-v2/verify-structure.json
"""

import json
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GLB = os.path.join(ROOT, "ThreeRuntime", "assets", "citizens", "pathfinder_scout.glb")
OUT_JSON = os.path.join(ROOT, "Docs", "QA", "ThreeJS", "pathfinder-v2",
                        "verify-structure.json")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=GLB)

report = {}

arm = None
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        arm = o
        break
assert arm is not None, "no armature found in GLB"

report["armature"] = arm.name
report["bone_count"] = len(arm.data.bones)
report["bones"] = [b.name for b in arm.data.bones]

def keyframe_count(a):
    """Blender 4.4+ moved fcurves into action slots; be defensive."""
    try:
        if hasattr(a, "fcurves"):
            return sum(len(fc.keyframe_points) for fc in a.fcurves)
        if hasattr(a, "slots"):
            total = 0
            for s in a.slots:
                for fc in getattr(s, "fcurves", []):
                    total += len(fc.keyframe_points)
            if total:
                return total
        if hasattr(a, "layers"):
            total = 0
            for lay in a.layers:
                for st in lay.strips:
                    for fc in getattr(st, "fcurves", []):
                        total += len(fc.keyframe_points)
            return total
    except Exception:
        return -1
    return -1


# action inventory
acts = []
for a in bpy.data.actions:
    fr = a.frame_range
    acts.append({
        "name": a.name,
        "frame_start": int(fr[0]),
        "frame_end": int(fr[1]),
        "keyframes": keyframe_count(a),
    })
acts.sort(key=lambda d: d["name"])
report["clips"] = acts

# mesh inventory
meshes = []
total_verts = 0
total_polys = 0
for o in sorted(bpy.data.objects, key=lambda o: o.name):
    if o.type != "MESH":
        continue
    mats = [m.name for m in o.data.materials if m]
    meshes.append({
        "name": o.name,
        "verts": len(o.data.vertices),
        "polys": len(o.data.polygons),
        "materials": mats,
    })
    total_verts += len(o.data.vertices)
    total_polys += len(o.data.polygons)
report["mesh_count"] = len(meshes)
report["meshes"] = meshes
report["total_verts"] = total_verts
report["total_polys"] = total_polys

report["materials"] = sorted(m.name for m in bpy.data.materials)

# orientation sanity: key bone heads in world space (Blender Z-up here)
bpy.context.view_layer.update()
key_pos = {}
for bname in ("Root", "Hips", "Chest", "Head", "StandardPole", "Pennant"):
    pb = arm.pose.bones.get(bname)
    if pb is not None:
        key_pos[bname] = [round(v, 4) for v in (arm.matrix_world @ pb.matrix).translation]
report["key_bone_world_positions_blender_zup"] = key_pos

report["glb_size_bytes"] = os.path.getsize(GLB)

os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
with open(OUT_JSON, "w") as fh:
    json.dump(report, fh, indent=2)

print("=== verify report ===")
print(f"bones: {report['bone_count']}")
print("clips:", [(c["name"], c["frame_start"], c["frame_end"]) for c in report["clips"]])
print(f"mesh objects: {report['mesh_count']}  verts: {total_verts}  polys: {total_polys}")
print("materials:", report["materials"])
print("key positions:", key_pos)
print(f"glb bytes: {report['glb_size_bytes']}")
print(f"wrote {OUT_JSON}")
