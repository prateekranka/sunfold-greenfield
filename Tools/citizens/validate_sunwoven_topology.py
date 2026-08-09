"""B24-TOPOLOGY — deterministic connected-topology checks for Sunwoven.

A per-bone box build produces many disconnected connected components (one box
per segment, no edges between boxes). A welded ring-tube produces ONE component.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/citizens/validate_sunwoven_topology.py

Writes: Tools/citizens/build/validation-sunwoven-topology.json
"""

from __future__ import annotations

import json
import os

import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
BLEND_PATH = os.path.join(HERE, "assets", "sunwoven_lab.blend")
OUT_PATH = os.path.join(HERE, "build", "validation-sunwoven-topology.json")

GARMENT_MESHES = (
    "sunwoven_headwrap",
    "sunwoven_headwrap_tail",
    "sunwoven_hair_nape",
    "sunwoven_tunic",
    "sunwoven_sleeve_L",
    "sunwoven_sleeve_R",
    "sunwoven_trousers_L",
    "sunwoven_trousers_R",
    "sunwoven_sash",
    "sunwoven_sash_tail",
    "sunwoven_harness_L",
    "sunwoven_harness_R",
    "sunwoven_harness_lower",
    "sunwoven_hip_pouch_L",
    "sunwoven_hip_pouch_R",
    "sunwoven_sandal_L",
    "sunwoven_sandal_R",
    "sunwoven_side_basket_sling",
)


def connected_components(data) -> tuple[int, list[int]]:
    bm = bmesh.new()
    bm.from_mesh(data)
    seen = [False] * len(bm.verts)
    bm.verts.ensure_lookup_table()
    comps = 0
    sizes = []
    for v in bm.verts:
        if seen[v.index]:
            continue
        comps += 1
        stack = [v]
        n = 0
        while stack:
            cur = stack.pop()
            if seen[cur.index]:
                continue
            seen[cur.index] = True
            n += 1
            for e in cur.link_edges:
                other = e.other_vert(cur)
                if not seen[other.index]:
                    stack.append(other)
        sizes.append(n)
    bm.free()
    return comps, sorted(sizes, reverse=True)


def edges_sharingverts(data) -> int:
    bm = bmesh.new()
    bm.from_mesh(data)
    shared = 0
    for v in bm.verts:
        if len(v.link_edges) > 4:
            shared += 1
    bm.free()
    return shared


def mesh_report(obj) -> dict:
    components, sizes = connected_components(obj.data)
    return {
        "present": True,
        "vertices": len(obj.data.vertices),
        "faces": len(obj.data.polygons),
        "connected_components": components,
        "largest_component_vertices": max(sizes) if sizes else 0,
        "vertices_with_more_than_four_edges": edges_sharingverts(obj.data),
        "armature_modifier_present": any(m.type == "ARMATURE" for m in obj.modifiers),
        "vertex_groups": len(obj.vertex_groups),
        "passed": components == 1 and any(m.type == "ARMATURE" for m in obj.modifiers) and len(obj.vertex_groups) > 0,
    }


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    body = bpy.data.objects.get("sunwoven_body")
    report = {
        "schema": "sunfold.sunwoven.topology/2",
        "blend": BLEND_PATH,
        "body_present": body is not None,
        "garment_meshes": {},
    }
    if body is None:
        report["passed"] = False
        report["error"] = "sunwoven_body missing"
    else:
        comps, sizes = connected_components(body.data)
        shared = edges_sharingverts(body.data)
        report["body_vertex_count"] = len(body.data.vertices)
        report["body_face_count"] = len(body.data.polygons)
        report["connected_components"] = comps
        report["first_component_size"] = max(sizes) if sizes else 0
        report["vertices_with_more_than_four_edges"] = shared
        report["weights_present"] = len(body.vertex_groups) >= 10
        report["armature_modifier_present"] = any(m.type == "ARMATURE" for m in body.modifiers)
        # Pass: exactly one connected component (the whole body welded) and
        # a number of high-valence weld vertices (the joints) > 0.
        report["passed"] = comps == 1 and shared > 0 and report["weights_present"] and report["armature_modifier_present"]
        for name in GARMENT_MESHES:
            obj = bpy.data.objects.get(name)
            report["garment_meshes"][name] = {"present": False, "passed": False} if obj is None else mesh_report(obj)
        report["garments_present"] = all(item["present"] for item in report["garment_meshes"].values())
        report["garments_connected"] = all(item["passed"] for item in report["garment_meshes"].values())
        report["passed"] = report["passed"] and report["garments_present"] and report["garments_connected"]
    with open(OUT_PATH, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"[validate_sunwoven_topology] wrote {OUT_PATH}")
    if not report.get("passed", False):
        raise SystemExit(1)


main()
