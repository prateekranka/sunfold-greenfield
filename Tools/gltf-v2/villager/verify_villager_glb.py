#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Independent structural verification of citizen_villager.glb.
Loads the shipped GLB back into Blender headless and prints node/bone/
animation counts; also sanity-checks skinned meshes and materials.
Run with: blender -b -P verify_villager_glb.py
"""
import json
import os

import bpy

GLB_PATH = "/Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield-threejs-wkwebview/ThreeRuntime/assets/citizens/citizen_villager.glb"

assert os.path.exists(GLB_PATH), "GLB missing: %s" % GLB_PATH
bpy.ops.import_scene.gltf(filepath=GLB_PATH)

bones = []
mesh_objects = []
skinned = 0
verts = 0
tris = 0
materials = set()
anim_names = []

for obj in bpy.context.scene.objects:
    if obj.type == "ARMATURE":
        bones = [b.name for b in obj.data.bones]
        if obj.animation_data:
            for track in obj.animation_data.nla_tracks:
                pass  # imported actions live on the object's animation_data.action
            act = obj.animation_data.action
            if act is not None:
                anim_names.append(act.name)
            # Blender glTF import also creates NLA tracks per animation
            if obj.animation_data.nla_tracks:
                anim_names += [t.name for t in obj.animation_data.nla_tracks]
    if obj.type == "MESH":
        mesh_objects.append(obj.name)
        verts += len(obj.data.vertices)
        tris += len(obj.data.polygons)
        for slot in obj.material_slots:
            if slot.material:
                materials.add(slot.material.name)
        if obj.find_armature() is not None or any(m.type == "ARMATURE" for m in obj.modifiers):
            skinned += 1

print("VERIFY2 glb=%s" % GLB_PATH)
print("VERIFY2 bone_count=%d" % len(bones))
print("VERIFY2 bone_names=%s" % sorted(bones))
print("VERIFY2 mesh_count=%d skinned_mesh_objects=%d verts=%d tris=%d" %
      (len(mesh_objects), skinned, verts, tris))
print("VERIFY2 materials=%s" % sorted(materials))
print("VERIFY2 animation_count=%d" % len(set(anim_names)))
print("VERIFY2 animation_names=%s" % sorted(set(anim_names)))

# quick structural read of the glb json as a second opinion
with open(GLB_PATH, "rb") as fh:
    data = fh.read()
jlen = int.from_bytes(data[12:16], "little")
g = json.loads(data[20:20 + jlen].decode("utf-8"))
print("VERIFY2 json nodes=%d meshes=%d materials=%d skins=%d animations=%d" %
      (len(g.get("nodes", [])), len(g.get("meshes", [])),
       len(g.get("materials", [])), len(g.get("skins", [])),
       len(g.get("animations", []))))
print("VERIFY2 json clip_names=%s" % sorted(a.get("name", "?") for a in g.get("animations", [])))
print("VERIFY2_END_OK")
