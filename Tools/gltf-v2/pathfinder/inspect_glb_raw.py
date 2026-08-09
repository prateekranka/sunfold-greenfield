#!/usr/bin/env python3
"""inspect_glb_raw.py — parse the GLB binary container directly (no Blender).

Extracts the JSON chunk and reports: node/bone hierarchy, animation clips
(name, channels, sampler keyframe counts + first/last times), mesh accessor
vertex counts, material inventory. Ground truth for the structural report.
"""

import json
import struct
import sys

path = sys.argv[1] if len(sys.argv) > 1 else (
    "/Users/prateekranka/Claude/Projects/aoe-space-edition/"
    "SunfoldGreenfield-threejs-wkwebview/ThreeRuntime/assets/citizens/"
    "pathfinder_scout.glb")

with open(path, "rb") as fh:
    data = fh.read()

magic, version, length = struct.unpack_from("<III", data, 0)
assert magic == 0x46546C67, "not a GLB"
assert version == 2

# chunk 0 = JSON
chunk_len, chunk_type = struct.unpack_from("<II", data, 12)
assert chunk_type == 0x4E4F534A  # JSON
gltf = json.loads(data[20:20 + chunk_len].decode("utf-8"))

print(f"=== GLB {path}")
print(f"size: {len(data)} bytes  gltf json len: {chunk_len}")

nodes = gltf.get("nodes", [])
skins = gltf.get("skins", [])
meshes = gltf.get("meshes", [])
mats = gltf.get("materials", [])
anims = gltf.get("animations", [])
accessors = gltf.get("accessors", [])

bone_count = 0
for skin in skins:
    bone_count += len(skin.get("joints", []))
print(f"nodes: {len(nodes)}  skins: {len(skins)}  joints(bones): {bone_count}")
print(f"meshes: {len(meshes)}  materials: {len(mats)}  animations: {len(anims)}")

print("\n-- meshes --")
total_verts = 0
for mi, mesh in enumerate(meshes):
    for pi, prim in enumerate(mesh.get("primitives", [])):
        pos_idx = prim.get("attributes", {}).get("POSITION")
        if pos_idx is None:
            print(f"  mesh[{mi}] '{mesh.get('name')}' prim[{pi}] NO-POSITION "
                  f"(attrs={sorted(prim.keys())})")
            continue
        pos_acc = accessors[pos_idx]
        nv = pos_acc["count"]
        total_verts += nv
        mat_name = mats[prim["material"]]["name"] if "material" in prim else "-"
        print(f"  mesh[{mi}] '{mesh.get('name')}' prim[{pi}] verts={nv} "
              f"mode={prim.get('mode', 4)} mat='{mat_name}'")
print(f"total skinned verts: {total_verts}")

print("\n-- materials --")
for m in mats:
    pbr = m.get("pbrMetallicRoughness", {})
    print(f"  '{m['name']}' base={pbr.get('baseColorFactor')} "
          f"met={pbr.get('metallicFactor')} rough={pbr.get('roughnessFactor')} "
          f"emis={m.get('emissiveFactor')} strength={m.get('extensions', {}).get('KHR_materials_emissive_strength', {}).get('emissiveStrength')}")

print("\n-- animations --")
for a in anims:
    name = a.get("name", "?")
    chans = a.get("channels", [])
    samplers = a.get("samplers", [])
    times = []
    for s in samplers:
        t = accessors[s["input"]]
        times.append((t["count"], t.get("min", [None])[0], t.get("max", [None])[0]))
    tracks = {}
    for c in chans:
        node = nodes[c["target"]["node"]].get("name", "?")
        path = c["target"]["path"]
        tracks.setdefault(path, set()).add(node)
    print(f"  '{name}': channels={len(chans)} samplers={len(samplers)}")
    for (cnt, t0, t1) in sorted(set(times)):
        print(f"      keyframes={cnt} times={t0}..{t1}")
    for p, ns in sorted(tracks.items()):
        print(f"      path={p} on {len(ns)} bones: {sorted(ns)[:6]}{'...' if len(ns) > 6 else ''}")
