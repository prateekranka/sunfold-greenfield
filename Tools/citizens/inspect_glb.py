"""B23-INSPECT — raw GLB inventory and manifest cross-check (pure Python).

Reads the exported GLBs with no Blender and no Three.js dependency, decodes
accessor counts for vertex/triangle statistics, and cross-checks the clip
inventory against the committed event-marker manifest.

    python3 Tools/citizens/inspect_glb.py

Writes: Tools/citizens/build/validation-glb.json
"""

from __future__ import annotations

import json
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")
MANIFEST = os.path.join(HERE, "manifest", "event-markers.json")
SUNWOVEN_MANIFEST = os.path.join(HERE, "manifest", "sunwoven-event-markers.json")
GLBS = {
    "citizen": os.path.join(REPO, "ThreeRuntime", "assets", "lab", "citizen_slender.glb"),
    "citizen_broad": os.path.join(REPO, "ThreeRuntime", "assets", "lab", "citizen_broad.glb"),
    "lab": os.path.join(REPO, "ThreeRuntime", "assets", "lab", "neutral_lab.glb"),
    "citizen_sunwoven": os.path.join(REPO, "ThreeRuntime", "assets", "citizens", "citizen_sunwoven.glb"),
    "lab_sunwoven": os.path.join(REPO, "ThreeRuntime", "assets", "citizens", "sunwoven_lab.glb"),
}
# (manifest, prefix) per GLB key; prefix filters the expected clip inventory.
GLB_PLAN = {
    "citizen": (MANIFEST, "slender_"),
    "citizen_broad": (MANIFEST, "broad_"),
    "lab": (MANIFEST, None),
    "citizen_sunwoven": (SUNWOVEN_MANIFEST, "sunwoven_"),
    "lab_sunwoven": (SUNWOVEN_MANIFEST, None),
}


class GLB:
    def __init__(self, path: str):
        with open(path, "rb") as fh:
            self.data = fh.read()
        self._chunks = {}
        offset = 12
        while offset < len(self.data):
            clen, ctype = struct.unpack_from("<II", self.data, offset)
            offset += 8
            chunk = self.data[offset : offset + clen]
            offset += clen
            self._chunks[ctype] = chunk
        self.doc = json.loads(self._chunks[0x4E4F534A].decode("utf-8"))
        self.bin = self._chunks.get(0x004E4942, b"")

    def accessor(self, index: int) -> dict:
        return self.doc["accessors"][index]

    def buffer_view(self, index: int) -> dict:
        return self.doc["bufferViews"][index]

    def read_accessor_data(self, index: int) -> list:
        acc = self.accessor(index)
        bv = self.buffer_view(acc["bufferView"])
        comp = acc["componentType"]
        fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[comp]
        size = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[comp]
        count = acc["count"]
        n = acc["type"][:1]
        comps = {"S": 1, "V": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
        start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        vals = struct.unpack_from(f"<{count * comps}{fmt}", self.bin, start)
        step = comps
        return [vals[i : i + step] for i in range(0, len(vals), step)]


def mesh_stats(glb: GLB, mesh_index: int, mesh: dict) -> dict:
    stats = {"name": mesh.get("name"), "vertex_count": 0, "triangle_count": 0}
    for prim in mesh.get("primitives", []):
        pos = prim.get("attributes", {}).get("POSITION")
        if pos is not None:
            stats["vertex_count"] += glb.accessor(pos)["count"]
        idx = prim.get("indices")
        if idx is not None:
            stats["triangle_count"] += glb.accessor(idx)["count"] // 3
    return stats


def skinned_nodes(glb: GLB) -> list[str]:
    return [
        n.get("name") for n in glb.doc.get("nodes", []) if n.get("skin") is not None and n.get("mesh") is not None
    ]


def inspect(path: str, manifest_clips: set[str], expected_prefix: str | None = None) -> dict:
    glb = GLB(path)
    doc = glb.doc
    node_names = {n.get("name") for n in doc.get("nodes", [])}
    clip_names = [a.get("name") for a in doc.get("animations", [])]
    skins = doc.get("skins", [])
    expected = {c for c in manifest_clips if expected_prefix is None or c.startswith(expected_prefix)}
    report = {
        "file": os.path.basename(path),
        "scene_count": len(doc.get("scenes", [])),
        "node_count": len(doc.get("nodes", [])),
        "mesh_count": len(doc.get("meshes", [])),
        "skinned_mesh_count": len(skinned_nodes(glb)),
        "skinned_meshes": skinned_nodes(glb),
        "skin_count": len(skins),
        "joint_count": max((len(s.get("joints", [])) for s in skins), default=0),
        "bone_nodes": len(node_names),
        "joint_lists": [len(s.get("joints", [])) for s in skins],
        "material_count": len(doc.get("materials", [])),
        "texture_count": len(doc.get("textures", [])),
        "image_count": len(doc.get("images", [])),
        "animation_count": len(doc.get("animations", [])),
        "clip_names": sorted(clip_names),
        "meshes": [mesh_stats(glb, i, m) for i, m in enumerate(doc.get("meshes", []))],
        "total_vertices": 0,
        "total_triangles": 0,
        "sockets_present": [s for s in ("socket_tool_R", "socket_tool_L", "socket_carrier") if s in node_names],
        "expected_prefix": expected_prefix,
    }
    report["total_vertices"] = sum(m["vertex_count"] for m in report["meshes"])
    report["total_triangles"] = sum(m["triangle_count"] for m in report["meshes"])

    present = set(clip_names)
    report["expected_clip_count"] = len(expected)
    report["missing_expected_clips"] = sorted(expected - present)
    report["unexpected_clips"] = sorted(present - expected)
    report["all_expected_present"] = expected <= present
    return report


def main() -> None:
    manifests = {}
    for key, (manifest_path, _prefix) in GLB_PLAN.items():
        if manifest_path not in manifests:
            manifests[manifest_path] = json.load(open(manifest_path))
    report = {"schema": "sunfold.lab.glb-inventory/1", "glbs": {}}
    for key, path in GLBS.items():
        if os.path.exists(path):
            manifest_path, prefix = GLB_PLAN[key]
            manifest_clips = {c["name"] for c in manifests[manifest_path]["clips"]}
            report["glbs"][key] = inspect(path, manifest_clips, prefix)
            report["glbs"][key]["manifest"] = manifest_path
    out = os.path.join(BUILD, "validation-glb.json")
    with open(out, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"[inspect_glb] wrote {out}")


if __name__ == "__main__":
    main()
