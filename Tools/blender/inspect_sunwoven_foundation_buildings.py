#!/usr/bin/env python3
"""Fail-closed GLB inventory for the Sunwoven Foundation building kit."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "ThreeRuntime" / "assets" / "buildings"
REQUIRED_GROUPS = {
    "state_shared",
    "state_healthy_damaged",
    "state_healthy_only",
    "state_damaged_plus",
    "state_critical_plus",
    "state_destroyed_only",
    "hp_anchor",
}
PLAN = {
    "civilizationCore": ("sunwoven_civilization_core.glb", "motion_core_ring"),
    "farm": ("sunwoven_farm.glb", "motion_farm_crops"),
    "formationYard": ("sunwoven_formation_yard.glb", "motion_yard_loom"),
}


def read_glb(path: Path) -> dict:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError(f"{path.name}: invalid GLB header")
    offset = 12
    document = None
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.decode("utf-8"))
    if document is None:
        raise ValueError(f"{path.name}: missing JSON chunk")
    return document


def inspect(kind: str, filename: str, motion_node: str) -> dict:
    path = ASSET_DIR / filename
    document = read_glb(path)
    node_names = {node.get("name") for node in document.get("nodes", [])}
    missing = sorted((REQUIRED_GROUPS | {kind, motion_node}) - node_names)
    triangle_count = 0
    vertex_count = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            position = primitive.get("attributes", {}).get("POSITION")
            if position is not None:
                vertex_count += document["accessors"][position]["count"]
            indices = primitive.get("indices")
            if indices is not None:
                triangle_count += document["accessors"][indices]["count"] // 3
    result = {
        "kind": kind,
        "file": filename,
        "sizeBytes": path.stat().st_size,
        "nodeCount": len(document.get("nodes", [])),
        "meshCount": len(document.get("meshes", [])),
        "vertexCount": vertex_count,
        "triangleCount": triangle_count,
        "materialCount": len(document.get("materials", [])),
        "animationCount": len(document.get("animations", [])),
        "missingRequiredNodes": missing,
    }
    result["passes"] = (
        not missing
        and result["sizeBytes"] <= 1_500_000
        and triangle_count <= 30_000
        and vertex_count <= 30_000
        and result["materialCount"] <= 12
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    entries = [inspect(kind, filename, motion) for kind, (filename, motion) in PLAN.items()]
    report = {
        "schema": "sunfold.building-glb-validation/1",
        "limits": {
            "sizeBytesPerGlb": 1_500_000,
            "trianglesPerGlb": 30_000,
            "verticesPerGlb": 30_000,
            "materialsPerGlb": 12,
        },
        "entries": entries,
        "passes": all(entry["passes"] for entry in entries),
    }
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
    print(encoded, end="")
    if not report["passes"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
