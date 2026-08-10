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
PALETTE_MATERIALS = {
    "SW_Ivory_Cloth",
    "SW_Teal_Fabric",
    "SW_Woven_Gold",
    "SW_Contact_Shadow",
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


def inspect(kind: str, filename: str, motion_node: str, asset_dir: Path) -> dict:
    path = asset_dir / filename
    document = read_glb(path)
    node_names = {node.get("name") for node in document.get("nodes", [])}
    missing = sorted((REQUIRED_GROUPS | {kind, motion_node}) - node_names)
    triangle_count = 0
    vertex_count = 0
    primitive_count = 0
    weathered_primitive_count = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            primitive_count += 1
            if "COLOR_0" in primitive.get("attributes", {}):
                weathered_primitive_count += 1
            position = primitive.get("attributes", {}).get("POSITION")
            if position is not None:
                vertex_count += document["accessors"][position]["count"]
            indices = primitive.get("indices")
            if indices is not None:
                triangle_count += document["accessors"][indices]["count"] // 3
    root_node = next((node for node in document.get("nodes", []) if node.get("name") == kind), {})
    root_extras = root_node.get("extras", {})
    material_names = {material.get("name") for material in document.get("materials", [])}
    expected_palette_materials = PALETTE_MATERIALS & material_names
    authored_palette_materials = {
        material.get("name")
        for material in document.get("materials", [])
        if material.get("name") in PALETTE_MATERIALS
        and material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3]
        != [1, 1, 1]
    }
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
        "primitiveCount": primitive_count,
        "weatheredPrimitiveCount": weathered_primitive_count,
        "surfaceContract": root_extras.get("surface_contract"),
        "surfaceColorAttribute": root_extras.get("surface_color_attribute"),
        "hasContactShadowMaterial": "SW_Contact_Shadow" in material_names,
        "expectedPaletteMaterialCount": len(expected_palette_materials),
        "authoredPaletteMaterialCount": len(authored_palette_materials),
        "missingPaletteMaterials": sorted(expected_palette_materials - authored_palette_materials),
        "missingRequiredNodes": missing,
    }
    result["passes"] = (
        not missing
        and result["sizeBytes"] <= 1_500_000
        and triangle_count <= 30_000
        and vertex_count <= 30_000
        and result["materialCount"] <= 12
        and primitive_count > 0
        and weathered_primitive_count == primitive_count
        and result["surfaceContract"] == "sunfold.weathered-building/1"
        and result["surfaceColorAttribute"] == "SunfoldSurface"
        and result["hasContactShadowMaterial"]
        and result["expectedPaletteMaterialCount"] >= 3
        and result["authoredPaletteMaterialCount"] == result["expectedPaletteMaterialCount"]
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-dir", type=Path, default=ASSET_DIR)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    asset_dir = args.asset_dir.resolve()
    entries = [
        inspect(kind, filename, motion, asset_dir)
        for kind, (filename, motion) in PLAN.items()
    ]
    report = {
        "schema": "sunfold.building-glb-validation/2",
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
