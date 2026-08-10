#!/usr/bin/env python3
"""Build the Sunwoven Foundation building kit in Blender.

The script is the source of truth for three gameplay models:

* Civilization Core
* Farm
* Formation Yard

Each GLB carries one hierarchy with six named visibility groups. The Three.js
renderer maps those groups to healthy, damaged, critical, and destroyed HP
bands. This avoids four complete copies of each model while preserving real
silhouette loss as damage rises.

Run with Blender, not the system Python:

    blender --background --python Tools/blender/build_sunwoven_foundation_buildings.py -- \
      --output ThreeRuntime/assets/buildings \
      --evidence /absolute/evidence/path
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import random
import sys

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "ThreeRuntime" / "assets" / "buildings"
WEATHER_COLOR_ATTRIBUTE = "SunfoldSurface"

PALETTE = {
    # Linear values calibrated under the Helios ACES rig. Ivory remains the
    # faction highlight, but graphite ceramic and aged brass now carry the
    # structure so the kit belongs to the surrounding ring.
    "ivory": (0.255, 0.218, 0.166, 1.0),
    "ivory_light": (0.335, 0.294, 0.220, 1.0),
    "ceramic": (0.155, 0.132, 0.112, 1.0),
    "ceramic_light": (0.225, 0.194, 0.158, 1.0),
    "gold": (0.365, 0.185, 0.050, 1.0),
    "gold_light": (0.545, 0.345, 0.105, 1.0),
    "teal": (0.010, 0.215, 0.245, 1.0),
    "teal_light": (0.020, 0.58, 0.56, 1.0),
    "soil": (0.070, 0.040, 0.030, 1.0),
    "crop": (0.44, 0.245, 0.055, 1.0),
    "crop_light": (0.68, 0.43, 0.11, 1.0),
    "scorch": (0.025, 0.020, 0.018, 1.0),
    "ash": (0.072, 0.063, 0.060, 1.0),
    "contact": (0.012, 0.016, 0.020, 1.0),
    "ember": (1.0, 0.105, 0.012, 1.0),
}

STATE_GROUPS = (
    "state_shared",
    "state_healthy_damaged",
    "state_healthy_only",
    "state_damaged_plus",
    "state_critical_plus",
    "state_destroyed_only",
)


def parse_args() -> argparse.Namespace:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--skip-render", action="store_true")
    return parser.parse_args(args)


def reset_scene() -> None:
    # Selection-based deletion skips objects hidden by the previous damage-state
    # render. Remove datablocks directly so later buildings do not inherit
    # suffixed state-group names or stale hidden geometry.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    roughness: float,
    metallic: float = 0.0,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    # Keep the authored weather field visible in Blender. The exporter uses the
    # active color attribute explicitly because material-node recognition can
    # vary between Blender exporter versions.
    vertex_color = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    vertex_color.layer_name = WEATHER_COLOR_ATTRIBUTE
    multiply = mat.node_tree.nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1.0
    multiply.inputs[1].default_value = color
    mat.node_tree.links.new(vertex_color.outputs["Color"], multiply.inputs[2])
    mat.node_tree.links.new(multiply.outputs["Color"], bsdf.inputs["Base Color"])
    mat["sunfold_surface_contract"] = "sunfold.weathered-building/1"
    return mat


def make_materials() -> dict[str, bpy.types.Material]:
    return {
        "ivory": material("SW_Ivory_Cloth", PALETTE["ivory_light"], roughness=0.82),
        "ivory_fold": material("SW_Ivory_Fold", PALETTE["ivory"], roughness=0.87),
        "ceramic": material("SW_Warm_Ceramic", PALETTE["ceramic_light"], roughness=0.9),
        "ceramic_dark": material("SW_Ceramic_Shadow", PALETTE["ceramic"], roughness=0.94),
        "gold": material("SW_Woven_Gold", PALETTE["gold"], roughness=0.56, metallic=0.34),
        "gold_light": material(
            "SW_Woven_Gold_Light", PALETTE["gold_light"], roughness=0.5, metallic=0.3
        ),
        "teal": material("SW_Teal_Fabric", PALETTE["teal"], roughness=0.78),
        "teal_glow": material(
            "SW_Teal_Lantern",
            PALETTE["teal_light"],
            roughness=0.34,
            emission=PALETTE["teal_light"],
            emission_strength=1.4,
        ),
        "soil": material("SW_Living_Soil", PALETTE["soil"], roughness=0.98),
        "crop": material("SW_Sun_Crop", PALETTE["crop"], roughness=0.82),
        "crop_light": material("SW_Sun_Crop_Tips", PALETTE["crop_light"], roughness=0.74),
        "scorch": material("SW_Scorch", PALETTE["scorch"], roughness=0.98),
        "ash": material("SW_Ash_Ceramic", PALETTE["ash"], roughness=0.95),
        "contact": material("SW_Contact_Shadow", PALETTE["contact"], roughness=1.0),
        "ember": material(
            "SW_Ember",
            PALETTE["ember"],
            roughness=0.5,
            emission=PALETTE["ember"],
            emission_strength=7.5,
        ),
    }


def empty(name: str, parent: bpy.types.Object | None = None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.35
    obj.parent = parent
    return obj


def state_hierarchy(kind: str) -> tuple[bpy.types.Object, dict[str, bpy.types.Object]]:
    root = empty(kind)
    root["sunfold_kind"] = kind
    root["damage_contract"] = "sunfold.building-damage/1"
    groups = {name: empty(name, root) for name in STATE_GROUPS}
    return root, groups


def finish_object(
    obj: bpy.types.Object,
    name: str,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    bevel: float = 0.0,
    smooth: bool = False,
) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_mesh"
    obj.parent = parent
    if mat:
        obj.data.materials.append(mat)
    if bevel > 0:
        modifier = obj.modifiers.new("crafted edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def add_cylinder(
    name: str,
    radius: float,
    depth: float,
    z: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    vertices: int = 24,
    bevel: float = 0.06,
    scale_xy: tuple[float, float] = (1.0, 1.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    obj.scale.x = scale_xy[0]
    obj.scale.y = scale_xy[1]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, name, mat, parent, bevel=bevel, smooth=True)


def add_cone(
    name: str,
    radius1: float,
    radius2: float,
    depth: float,
    z: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    vertices: int = 16,
    bevel: float = 0.04,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=(0, 0, z)
    )
    return finish_object(bpy.context.object, name, mat, parent, bevel=bevel, smooth=True)


def add_box(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    bevel: float = 0.06,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.scale = (scale[0] * 0.5, scale[1] * 0.5, scale[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, name, mat, parent, bevel=bevel)


def add_torus(
    name: str,
    major_radius: float,
    minor_radius: float,
    z: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    major_segments: int = 48,
    minor_segments: int = 8,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=(0, 0, z),
    )
    return finish_object(bpy.context.object, name, mat, parent, smooth=True)


def add_beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    vertices: int = 8,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    delta = b - a
    mid = (a + b) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length, location=mid)
    obj = bpy.context.object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, name, mat, parent, bevel=radius * 0.18, smooth=True)


def add_curve(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    curve.materials.append(mat)
    return obj


def add_petal(
    name: str,
    angle: float,
    inner_radius: float,
    outer_radius: float,
    z_inner: float,
    z_mid: float,
    z_outer: float,
    width_inner: float,
    width_outer: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    thickness: float = 0.055,
) -> bpy.types.Object:
    radial = Vector((math.cos(angle), math.sin(angle), 0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    middle_radius = inner_radius + (outer_radius - inner_radius) * 0.54
    centerline = [
        radial * inner_radius + Vector((0, 0, z_inner)),
        radial * middle_radius + Vector((0, 0, z_mid)),
        radial * outer_radius + Vector((0, 0, z_outer)),
    ]
    widths = [width_inner, (width_inner + width_outer) * 0.58, width_outer]
    verts = []
    for point, width in zip(centerline, widths):
        verts.append(tuple(point - tangent * width * 0.5))
        verts.append(tuple(point + tangent * width * 0.5))
    faces = [(0, 1, 3, 2), (2, 3, 5, 4)]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    mesh.materials.append(mat)
    solid = obj.modifiers.new("woven thickness", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 0
    bevel_mod = obj.modifiers.new("sewn edge", "BEVEL")
    bevel_mod.width = min(0.045, thickness * 0.65)
    bevel_mod.segments = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=solid.name)
    bpy.ops.object.modifier_apply(modifier=bevel_mod.name)
    obj.select_set(False)
    return obj


def add_banner(
    name: str,
    anchor: tuple[float, float, float],
    angle: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    length: float = 0.9,
    drop: float = 0.65,
) -> bpy.types.Object:
    radial = Vector((math.cos(angle), math.sin(angle), 0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    a = Vector(anchor)
    verts = [
        tuple(a),
        tuple(a + tangent * length),
        tuple(a + tangent * length * 0.82 - Vector((0, 0, drop))),
        tuple(a - Vector((0, 0, drop * 0.8)) + radial * 0.09),
    ]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    mesh.materials.append(mat)
    solid = obj.modifiers.new("cloth thickness", "SOLIDIFY")
    solid.thickness = 0.035
    solid.offset = 0
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=solid.name)
    obj.select_set(False)
    return obj


def add_fabric_panel(
    name: str,
    vertices: list[tuple[float, float, float]],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    thickness: float = 0.065,
) -> bpy.types.Object:
    """Create one authored cloth panel from a clockwise polygon."""
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(vertices, [], [tuple(range(len(vertices)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    mesh.materials.append(mat)
    solid = obj.modifiers.new("woven thickness", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 0
    bevel_mod = obj.modifiers.new("bound edge", "BEVEL")
    bevel_mod.width = min(0.045, thickness * 0.65)
    bevel_mod.segments = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=solid.name)
    bpy.ops.object.modifier_apply(modifier=bevel_mod.name)
    obj.select_set(False)
    return obj


def add_scorch_disc(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_circle_add(vertices=16, radius=1.0, fill_type="NGON", location=location)
    obj = bpy.context.object
    obj.scale = (scale[0], scale[1], 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, name, mat, parent)


def add_ember_cluster(prefix: str, center: tuple[float, float, float], parent, mats, count=7) -> None:
    rng = random.Random(prefix)
    for index in range(count):
        angle = rng.random() * math.tau
        radius = rng.uniform(0.18, 0.82)
        size = rng.uniform(0.035, 0.085)
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1,
            radius=size,
            location=(
                center[0] + math.cos(angle) * radius,
                center[1] + math.sin(angle) * radius,
                center[2] + rng.uniform(0.01, 0.10),
            ),
        )
        finish_object(bpy.context.object, f"{prefix}_{index:02d}", mats["ember"], parent, smooth=True)


def build_core(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root, g = state_hierarchy("civilizationCore")
    shared = g["state_shared"]
    hd = g["state_healthy_damaged"]
    healthy = g["state_healthy_only"]
    damaged = g["state_damaged_plus"]
    critical = g["state_critical_plus"]
    destroyed = g["state_destroyed_only"]

    # A thin authored pad fills the 4 cm presentation offset used by the
    # runtime and supplies a dark contact line without a transparent decal.
    add_cylinder("core_contact_pad", 5.62, 0.04, -0.02, mats["contact"], shared, vertices=36, bevel=0.025)
    add_cylinder("core_wreck_contact_pad", 5.34, 0.04, -0.02, mats["contact"], destroyed, vertices=32, bevel=0.025)

    # Three stepped ceramic plinths keep the hero silhouette grounded.
    add_cylinder("core_plinth_01", 5.35, 0.32, 0.16, mats["ceramic_dark"], shared, vertices=24, bevel=0.10)
    add_cylinder("core_plinth_02", 4.95, 0.30, 0.46, mats["ceramic"], shared, vertices=24, bevel=0.09)
    add_cylinder("core_plinth_03", 4.55, 0.30, 0.75, mats["ceramic"], shared, vertices=24, bevel=0.08)
    add_torus("core_walkway_kerb", 4.15, 0.14, 0.94, mats["gold_light"], shared)
    add_torus("core_floor_inlay", 3.42, 0.055, 1.02, mats["teal_glow"], shared, major_segments=36)

    # Open drum. Alternating turquoise fabric bays sit between twelve gold ribs.
    add_cylinder("core_inner_drum", 3.02, 3.20, 2.57, mats["ivory_fold"], shared, vertices=24, bevel=0.08)
    for index in range(12):
        angle = (index + 0.5) * math.tau / 12
        x, y = math.cos(angle) * 3.06, math.sin(angle) * 3.06
        panel_mat = mats["teal"] if index % 2 == 0 else mats["ivory"]
        parent = healthy if index in (2, 9) else hd if index in (5, 11) else shared
        add_box(
            f"core_drum_panel_{index:02d}",
            (x, y, 2.60),
            (1.33, 0.12, 2.42),
            panel_mat,
            parent,
            bevel=0.06,
            rotation=(0, 0, angle + math.pi / 2),
        )
        add_beam(
            f"core_column_{index:02d}",
            (math.cos(angle) * 3.47, math.sin(angle) * 3.47, 1.03),
            (math.cos(angle) * 3.30, math.sin(angle) * 3.30, 4.60),
            0.105,
            mats["gold_light"],
            shared if index not in (3, 8) else hd,
        )

    add_torus("core_architrave", 3.56, 0.18, 4.64, mats["gold_light"], shared)

    # Two scalloped canopy tiers. Several petals live in narrower HP groups, so
    # the silhouette loses real fabric instead of receiving a tint-only overlay.
    for index in range(12):
        angle = (index + 0.5) * math.tau / 12
        parent = healthy if index in (1, 7) else hd if index in (4, 10) else shared
        mat = mats["ivory"] if index % 2 == 0 else mats["ivory_fold"]
        add_petal(
            f"core_lower_petal_{index:02d}", angle, 2.76, 4.82 if index % 2 == 0 else 4.48,
            5.15, 4.92, 4.36 if index % 2 == 0 else 4.52,
            1.56, 1.00, mat, parent, thickness=0.07
        )
        add_beam(
            f"core_lower_batten_{index:02d}",
            (math.cos(angle) * 2.74, math.sin(angle) * 2.74, 5.17),
            (math.cos(angle) * (4.74 if index % 2 == 0 else 4.40), math.sin(angle) * (4.74 if index % 2 == 0 else 4.40), 4.43 if index % 2 == 0 else 4.59),
            0.045, mats["gold"], parent, vertices=6
        )

    # Six paired outer arches give the Core the reference's open pavilion read.
    # They rise from the plinth, bow outside the drum, and gather under the solar
    # wheel. The negative space between each pair stays visible at gameplay zoom.
    for bay in range(6):
        center = (bay + 0.5) * math.tau / 6
        parent = healthy if bay == 4 else hd if bay == 1 else shared
        for side in (-1, 1):
            angle = center + side * 0.12
            points = [
                (math.cos(angle) * 4.55, math.sin(angle) * 4.55, 1.02),
                (math.cos(angle) * 5.02, math.sin(angle) * 5.02, 3.15),
                (math.cos(angle) * 3.62, math.sin(angle) * 3.62, 5.28),
                (math.cos(angle) * 2.98, math.sin(angle) * 2.98, 6.13),
            ]
            add_curve(f"core_outer_arch_{bay:02d}_{side:+d}", points, 0.065, mats["gold_light"], parent)
        left = center - 0.12
        right = center + 0.12
        add_beam(
            f"core_arch_collar_{bay:02d}",
            (math.cos(left) * 3.60, math.sin(left) * 3.60, 5.27),
            (math.cos(right) * 3.60, math.sin(right) * 3.60, 5.27),
            0.07, mats["gold_light"], parent, vertices=8
        )

    motion_ring = empty("motion_core_ring", shared)
    add_torus("core_solar_wheel_outer", 3.03, 0.13, 6.25, mats["gold_light"], motion_ring)
    add_torus("core_solar_wheel_inner", 2.47, 0.085, 6.25, mats["gold"], motion_ring, major_segments=36)
    for index in range(12):
        angle = index * math.tau / 12
        add_beam(
            f"core_wheel_spoke_{index:02d}",
            (math.cos(angle) * 2.45, math.sin(angle) * 2.45, 6.25),
            (math.cos(angle) * 3.0, math.sin(angle) * 3.0, 6.25),
            0.04, mats["gold"], motion_ring, vertices=6
        )

    for index in range(12):
        angle = (index + 0.5) * math.tau / 12
        parent = healthy if index in (3, 8) else hd if index in (0, 6) else shared
        add_petal(
            f"core_upper_petal_{index:02d}", angle, 1.62, 3.36 if index % 2 == 0 else 3.10,
            6.92, 6.74, 6.31 if index % 2 == 0 else 6.43,
            1.05, 0.70, mats["ivory"] if index % 2 == 0 else mats["ivory_fold"], parent, thickness=0.06
        )

    add_cone("core_crown_drum", 1.72, 1.12, 1.75, 7.58, mats["teal"], shared, vertices=12)
    add_torus("core_crown_collar", 1.48, 0.12, 8.44, mats["gold_light"], shared, major_segments=36)
    for index in range(8):
        angle = (index + 0.5) * math.tau / 8
        add_petal(
            f"core_crown_petal_{index:02d}", angle, 0.62, 2.04,
            8.75, 8.68, 8.31, 0.68, 0.42,
            mats["ivory"] if index % 2 == 0 else mats["ivory_fold"],
            healthy if index == 5 else shared,
            thickness=0.055,
        )
    add_cone("core_finial_base", 0.64, 0.30, 1.52, 9.45, mats["gold_light"], shared, vertices=8)
    add_cone("core_finial_spire", 0.24, 0.0, 2.25, 11.30, mats["gold_light"], hd, vertices=8)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=0.34, location=(0, 0, 9.48))
    finish_object(bpy.context.object, "core_lantern", mats["teal_glow"], shared, smooth=True)

    # Five tall masts and catenary cords frame the pavilion. Two disappear at
    # damaged, one more at critical, leaving a deliberately asymmetric skyline.
    mast_tops = []
    for index in range(5):
        angle = (index + 0.25) * math.tau / 5
        parent = healthy if index in (1, 4) else hd if index == 3 else shared
        foot = (math.cos(angle) * 4.72, math.sin(angle) * 4.72, 0.92)
        top = (math.cos(angle) * 4.98, math.sin(angle) * 4.98, 8.72 + (index % 2) * 0.25)
        add_beam(f"core_mast_{index:02d}", foot, top, 0.075, mats["gold_light"], parent, vertices=8)
        add_cone(
            f"core_mast_finial_{index:02d}", 0.16, 0.0, 0.55, top[2] + 0.27,
            mats["gold_light"], parent, vertices=6, bevel=0.025
        ).location.x = top[0]
        bpy.context.object.location.y = top[1]
        add_banner(f"core_banner_{index:02d}", (top[0], top[1], top[2] - 0.25), angle, mats["teal"], parent)
        mast_tops.append(top)
    for index in range(5):
        a = mast_tops[index]
        b = mast_tops[(index + 1) % 5]
        midpoint = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, min(a[2], b[2]) - 0.95)
        add_curve(f"core_cord_{index:02d}", [a, midpoint, b], 0.018, mats["gold"], healthy if index in (0, 3) else hd)

    # Damage additions. Scorches sit just above the canopy plane and broken
    # members create a new grounded diagonal at each HP threshold.
    add_scorch_disc("core_scorch_drum", (2.88, -0.95, 3.0), (0.62, 0.42), mats["scorch"], damaged).rotation_euler = (math.radians(76), 0, math.radians(18))
    add_beam("core_fallen_mast", (-3.9, 1.6, 0.88), (-0.8, 4.2, 0.28), 0.095, mats["gold"], damaged)
    add_box("core_broken_panel", (3.9, -1.4, 0.42), (1.5, 0.75, 0.10), mats["teal"], damaged, bevel=0.04, rotation=(0.14, 0.08, 0.38))
    add_beam("core_critical_spire_fall", (-0.2, -1.0, 0.42), (3.4, 2.7, 0.20), 0.15, mats["gold"], critical)
    add_scorch_disc("core_critical_burn", (0.35, 0.2, 1.055), (1.45, 1.05), mats["scorch"], critical)
    add_ember_cluster("core_critical_ember", (0.35, 0.2, 1.08), critical, mats, count=11)

    # Destroyed state is a compact wreck, not a hidden building. It preserves
    # footprint recognition, hot centre, and a few fallen ivory petals.
    add_cylinder("core_wreck_plinth", 5.15, 0.30, 0.15, mats["ash"], destroyed, vertices=24, bevel=0.08)
    add_cylinder("core_wreck_crater", 3.15, 0.18, 0.32, mats["scorch"], destroyed, vertices=20, bevel=0.04)
    add_torus("core_wreck_broken_ring", 3.65, 0.13, 0.39, mats["gold"], destroyed, major_segments=24)
    for index, angle in enumerate((0.2, 1.4, 2.7, 4.25, 5.35)):
        start = (math.cos(angle) * 1.0, math.sin(angle) * 1.0, 0.45)
        end = (math.cos(angle) * 4.65, math.sin(angle) * 4.65, 0.18)
        add_beam(f"core_wreck_rib_{index:02d}", start, end, 0.12, mats["gold"], destroyed)
        add_box(
            f"core_wreck_cloth_{index:02d}",
            (math.cos(angle) * 3.3, math.sin(angle) * 3.3, 0.28),
            (2.1, 0.95, 0.10),
            mats["ivory_fold"],
            destroyed,
            bevel=0.04,
            rotation=(0.10, 0.12, angle + 0.25),
        )
    add_ember_cluster("core_wreck_ember", (0, 0, 0.44), destroyed, mats, count=18)

    hp_anchor = empty("hp_anchor", root)
    hp_anchor.location.z = 12.8
    return root


def add_crop_tuft(name: str, x: float, y: float, z: float, parent, mats, rng: random.Random) -> None:
    for blade in range(5):
        angle = rng.uniform(-0.6, 0.6)
        height = rng.uniform(0.50, 0.88)
        base = (x + rng.uniform(-0.10, 0.10), y + rng.uniform(-0.10, 0.10), z)
        end = (
            base[0] + math.sin(angle) * 0.18,
            base[1] + rng.uniform(-0.08, 0.12),
            z + height,
        )
        add_beam(f"{name}_blade_{blade}", base, end, 0.027, mats["crop"], parent, vertices=5)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.065, location=end)
        finish_object(bpy.context.object, f"{name}_seed_{blade}", mats["crop_light"], parent)


def build_farm(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root, g = state_hierarchy("farm")
    shared = g["state_shared"]
    hd = g["state_healthy_damaged"]
    healthy = g["state_healthy_only"]
    damaged = g["state_damaged_plus"]
    critical = g["state_critical_plus"]
    destroyed = g["state_destroyed_only"]
    rng = random.Random(5191)

    add_box("farm_contact_pad", (0, 0, -0.02), (7.22, 7.22, 0.04), mats["contact"], shared, bevel=0.20)
    add_box("farm_wreck_contact_pad", (0, 0, -0.02), (7.04, 7.04, 0.04), mats["contact"], destroyed, bevel=0.18)

    add_box("farm_base", (0, 0, 0.18), (7.0, 7.0, 0.36), mats["ceramic_dark"], shared, bevel=0.18)
    add_box("farm_soil", (0, 0, 0.43), (6.15, 6.15, 0.22), mats["soil"], shared, bevel=0.12)
    # Woven-gold kerb and teal irrigation channels make the low silhouette read.
    for axis in (-1, 1):
        add_box(f"farm_kerb_x_{axis}", (axis * 3.30, 0, 0.52), (0.26, 6.75, 0.34), mats["gold_light"], shared, bevel=0.07)
        add_box(f"farm_kerb_y_{axis}", (0, axis * 3.30, 0.52), (6.75, 0.26, 0.34), mats["gold_light"], shared, bevel=0.07)
    for index, x in enumerate((-1.85, 0, 1.85)):
        add_box(f"farm_furrow_{index}", (x, 0, 0.57), (1.08, 5.45, 0.24), mats["soil"], shared, bevel=0.18)
        add_box(f"farm_irrigation_{index}", (x + 0.67, 0, 0.58), (0.07, 5.55, 0.035), mats["teal_glow"], shared, bevel=0.02)

    motion_crops = empty("motion_farm_crops", shared)
    for row, x in enumerate((-1.85, 0, 1.85)):
        for step, y in enumerate((-2.25, -1.12, 0, 1.12, 2.25)):
            parent = healthy if (row, step) in ((0, 1), (2, 3), (1, 4)) else hd if (row, step) in ((0, 4), (2, 0), (1, 1)) else motion_crops
            add_crop_tuft(f"farm_crop_{row}_{step}", x, y, 0.67, parent, mats, rng)

    # Corner pennant: the one tall cue on the plot.
    add_beam("farm_marker_mast", (2.92, 2.92, 0.54), (2.92, 2.92, 2.20), 0.065, mats["gold_light"], healthy, vertices=8)
    add_banner("farm_marker_pennant", (2.92, 2.92, 2.05), math.pi * 0.75, mats["teal"], healthy, length=0.72, drop=0.48)

    add_scorch_disc("farm_damage_patch", (-1.65, 0.95, 0.705), (0.72, 1.22), mats["scorch"], damaged)
    add_box("farm_broken_kerb", (3.18, -1.65, 0.46), (0.32, 2.1, 0.30), mats["gold"], damaged, bevel=0.05, rotation=(0.08, 0.18, 0.20))
    add_scorch_disc("farm_critical_burn", (0.50, -0.55, 0.715), (1.75, 2.15), mats["scorch"], critical)
    add_ember_cluster("farm_critical_ember", (0.5, -0.55, 0.73), critical, mats, count=8)

    add_box("farm_wreck_base", (0, 0, 0.16), (6.85, 6.85, 0.32), mats["ash"], destroyed, bevel=0.16)
    add_box("farm_wreck_soil", (0, 0, 0.36), (5.95, 5.95, 0.15), mats["scorch"], destroyed, bevel=0.10)
    for index, (x, y, angle) in enumerate(((-2.9, 0.8, 0.15), (2.6, -1.2, -0.32), (0.4, 2.8, 1.42))):
        add_box(f"farm_wreck_kerb_{index}", (x, y, 0.42), (0.28, 2.4, 0.28), mats["gold"], destroyed, bevel=0.05, rotation=(0.08, 0.20, angle))
    add_ember_cluster("farm_wreck_ember", (0, 0, 0.49), destroyed, mats, count=10)

    hp_anchor = empty("hp_anchor", root)
    hp_anchor.location.z = 3.1
    return root


def build_yard(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root, g = state_hierarchy("formationYard")
    shared = g["state_shared"]
    hd = g["state_healthy_damaged"]
    healthy = g["state_healthy_only"]
    damaged = g["state_damaged_plus"]
    critical = g["state_critical_plus"]
    destroyed = g["state_destroyed_only"]

    add_box("yard_contact_pad", (0, 0, -0.02), (8.22, 6.22, 0.04), mats["contact"], shared, bevel=0.19)
    add_box("yard_wreck_contact_pad", (0, 0, -0.02), (8.04, 6.04, 0.04), mats["contact"], destroyed, bevel=0.17)

    # A rectangular muster deck separates the Yard from the circular Core at a
    # black-and-white thumbnail. Its long axis is the production/readiness cue.
    add_box("yard_deck_base", (0, 0, 0.19), (8.0, 6.0, 0.38), mats["ceramic_dark"], shared, bevel=0.16)
    add_box("yard_deck_top", (0, 0, 0.47), (7.55, 5.55, 0.20), mats["ceramic"], shared, bevel=0.12)
    for side in (-1, 1):
        add_box(f"yard_kerb_long_{side}", (0, side * 2.73, 0.61), (7.45, 0.15, 0.22), mats["gold_light"], shared, bevel=0.04)
        add_box(f"yard_kerb_short_{side}", (side * 3.72, 0, 0.61), (0.15, 5.35, 0.22), mats["gold_light"], shared, bevel=0.04)
    add_torus("yard_training_ring", 2.08, 0.07, 0.60, mats["teal_glow"], shared, major_segments=36)
    for index in range(8):
        angle = index * math.tau / 8
        add_beam(
            f"yard_floor_ray_{index:02d}",
            (math.cos(angle) * 0.8, math.sin(angle) * 0.8, 0.59),
            (math.cos(angle) * 2.95, math.sin(angle) * 2.22, 0.59),
            0.035, mats["gold"], shared, vertices=6
        )

    mast_tops = []
    corners = ((-3.35, -2.35), (3.35, -2.35), (3.35, 2.35), (-3.35, 2.35))
    for index, (x, y) in enumerate(corners):
        angle = math.atan2(y, x)
        parent = healthy if index == 2 else hd if index == 1 else shared
        foot = (x * 0.91, y * 0.91, 0.55)
        top = (x * 1.06, y * 1.08, 3.58 + (index % 2) * 0.12)
        add_beam(f"yard_mast_{index:02d}", foot, top, 0.12, mats["gold_light"], parent, vertices=8)
        add_cone(f"yard_mast_cap_{index:02d}", 0.19, 0, 0.58, top[2] + 0.28, mats["gold_light"], parent, vertices=6).location.x = top[0]
        bpy.context.object.location.y = top[1]
        add_banner(f"yard_pennant_{index:02d}", (top[0], top[1], top[2] - 0.18), angle, mats["teal"], parent, length=0.68, drop=0.56)
        mast_tops.append(top)

    # Four hipped woven panels form a square canopy. Gaps between them keep the
    # building see-through, while the long eaves echo the reference pavilion.
    roof_panels = (
        ("front", [(-1.25, -0.92, 4.55), (1.25, -0.92, 4.55), (4.08, -3.12, 3.40), (-4.08, -3.12, 3.40)], shared, mats["ivory"]),
        ("right", [(1.25, -0.92, 4.55), (1.25, 0.92, 4.55), (4.08, 3.12, 3.40), (4.08, -3.12, 3.40)], hd, mats["ivory_fold"]),
        ("back", [(1.25, 0.92, 4.55), (-1.25, 0.92, 4.55), (-4.08, 3.12, 3.40), (4.08, 3.12, 3.40)], healthy, mats["ivory"]),
        ("left", [(-1.25, 0.92, 4.55), (-1.25, -0.92, 4.55), (-4.08, -3.12, 3.40), (-4.08, 3.12, 3.40)], shared, mats["ivory_fold"]),
    )
    for name, vertices, parent, panel_mat in roof_panels:
        add_fabric_panel(f"yard_canopy_{name}", vertices, panel_mat, parent, thickness=0.08)

    # Perimeter and diagonal battens keep the roof readable when the cloth is
    # only a few dozen pixels high.
    for index, top in enumerate(mast_tops):
        next_top = mast_tops[(index + 1) % len(mast_tops)]
        parent = healthy if index == 1 else hd if index == 0 else shared
        add_beam(
            f"yard_eave_{index:02d}",
            (top[0], top[1], 3.42),
            (next_top[0], next_top[1], 3.42),
            0.065, mats["gold"], parent, vertices=8
        )
        add_beam(
            f"yard_roof_rib_{index:02d}",
            (top[0], top[1], 3.42),
            ((-1 if top[0] < 0 else 1) * 1.18, (-1 if top[1] < 0 else 1) * 0.86, 4.54),
            0.055, mats["gold_light"], parent, vertices=8
        )
    crown = add_cone("yard_crown", 1.55, 0.36, 1.30, 4.72, mats["teal"], shared, vertices=4)
    crown.rotation_euler.z = math.pi / 4
    add_cone("yard_finial", 0.30, 0, 0.82, 5.64, mats["gold_light"], hd, vertices=8)

    # Weapon rack and three upright spear silhouettes survive normal gameplay.
    add_box("yard_weapon_rack", (-2.78, 0, 1.03), (0.28, 3.05, 0.26), mats["gold"], shared, bevel=0.06)
    for index, y in enumerate((-1.0, 0, 1.0)):
        add_beam(f"yard_weapon_{index:02d}", (-2.78, y, 1.05), (-2.64 + index * 0.08, y, 2.42 + index * 0.12), 0.045, mats["gold_light"], shared, vertices=6)
        add_cone(f"yard_weapon_tip_{index:02d}", 0.10, 0, 0.34, 2.58 + index * 0.12, mats["gold_light"], shared, vertices=4, bevel=0.015).location.x = -2.64 + index * 0.08
        bpy.context.object.location.y = y

    motion_loom = empty("motion_yard_loom", shared)
    add_torus("yard_loom_outer", 1.36, 0.07, 1.18, mats["gold_light"], motion_loom, major_segments=32)
    add_torus("yard_loom_inner", 0.84, 0.045, 1.18, mats["teal_glow"], motion_loom, major_segments=28)

    add_scorch_disc("yard_damage_burn", (1.65, -1.2, 0.615), (0.95, 0.72), mats["scorch"], damaged)
    add_beam("yard_fallen_mast", (-3.0, 2.5, 0.55), (-0.4, 4.3, 0.25), 0.12, mats["gold"], damaged)
    add_box("yard_torn_canopy", (3.0, 1.5, 0.43), (2.7, 1.35, 0.10), mats["ivory_fold"], damaged, bevel=0.05, rotation=(0.16, -0.12, 0.45))
    add_scorch_disc("yard_critical_burn", (-0.25, 0.40, 0.625), (1.8, 1.45), mats["scorch"], critical)
    add_beam("yard_critical_crown", (-0.5, 0.0, 0.85), (3.7, -2.0, 0.25), 0.18, mats["gold"], critical)
    add_ember_cluster("yard_critical_ember", (-0.25, 0.4, 0.65), critical, mats, count=10)

    add_box("yard_wreck_deck", (0, 0, 0.18), (7.9, 5.9, 0.36), mats["ash"], destroyed, bevel=0.14)
    add_scorch_disc("yard_wreck_burn", (0, 0, 0.38), (2.4, 2.0), mats["scorch"], destroyed)
    for index, angle in enumerate((0.35, 1.75, 3.30, 5.15)):
        add_beam(
            f"yard_wreck_mast_{index:02d}",
            (math.cos(angle) * 0.5, math.sin(angle) * 0.5, 0.55),
            (math.cos(angle) * 3.75, math.sin(angle) * 3.75, 0.22),
            0.13, mats["gold"], destroyed
        )
    for index, angle in enumerate((0.1, 2.1, 4.25)):
        add_box(
            f"yard_wreck_cloth_{index:02d}",
            (math.cos(angle) * 2.5, math.sin(angle) * 2.5, 0.31),
            (3.2, 1.45, 0.11), mats["ivory_fold"], destroyed,
            bevel=0.05, rotation=(0.13, 0.09, angle + 0.2)
        )
    add_ember_cluster("yard_wreck_ember", (0, 0, 0.48), destroyed, mats, count=14)

    hp_anchor = empty("hp_anchor", root)
    hp_anchor.location.z = 6.7
    return root


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    result = [root]
    for child in root.children:
        result.extend(descendants(child))
    return result


def stable_name_seed(name: str) -> int:
    return sum((index + 1) * ord(character) for index, character in enumerate(name)) & 0xFFFF


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def convert_authored_curves(root: bpy.types.Object) -> int:
    """Convert curves before painting so every exported primitive carries COLOR_0."""
    converted = 0
    for obj in list(descendants(root)):
        if obj.type != "CURVE":
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.hide_viewport = False
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        converted += 1
    return converted


def weather_profile(material_name: str) -> tuple[float, float, float]:
    """Return minimum value, variation, and lower-edge darkening."""
    name = material_name.upper()
    if "CONTACT" in name:
        return (0.86, 0.05, 0.0)
    if "EMBER" in name:
        return (0.94, 0.05, 0.0)
    if "IVORY" in name:
        return (0.76, 0.18, 0.08)
    if "CERAMIC" in name or "ASH" in name:
        return (0.70, 0.22, 0.10)
    if "GOLD" in name:
        return (0.82, 0.14, 0.04)
    if "TEAL" in name:
        return (0.74, 0.18, 0.05)
    if "SOIL" in name or "SCORCH" in name:
        return (0.68, 0.22, 0.03)
    if "CROP" in name:
        return (0.80, 0.17, 0.04)
    return (0.76, 0.18, 0.06)


def apply_weathered_mesh(obj: bpy.types.Object) -> int:
    if obj.type != "MESH" or not obj.data.vertices or not obj.data.materials:
        return 0
    mesh = obj.data
    existing = mesh.color_attributes.get(WEATHER_COLOR_ATTRIBUTE)
    if existing:
        mesh.color_attributes.remove(existing)
    attribute = mesh.color_attributes.new(
        name=WEATHER_COLOR_ATTRIBUTE,
        type="BYTE_COLOR",
        domain="POINT",
    )
    mesh.color_attributes.active_color_index = len(mesh.color_attributes) - 1
    mesh.color_attributes.render_color_index = len(mesh.color_attributes) - 1
    material_name = obj.data.materials[0].name
    minimum, variation, lower_darkening = weather_profile(material_name)
    seed = stable_name_seed(obj.name)

    for index, vertex in enumerate(mesh.vertices):
        world = obj.matrix_world @ vertex.co
        broad = 0.5 + 0.5 * math.sin(
            world.x * 0.73 + world.y * 0.51 + world.z * 0.29 + seed * 0.017
        )
        cross = 0.5 + 0.5 * math.sin(
            world.x * 1.93 - world.y * 1.27 + world.z * 0.83 + seed * 0.041
        )
        grain = 0.5 + 0.5 * math.sin(
            (world.x + world.y) * 7.1 + world.z * 4.9 + seed * 0.113
        )
        field = broad * 0.54 + cross * 0.34 + grain * 0.12
        height = clamp01(world.z / 3.2)
        factor = (minimum + variation * field) * (1.0 - lower_darkening * (1.0 - height))
        warm_shift = (broad - 0.5) * 0.075
        attribute.data[index].color = (
            clamp01(factor * (1.0 + warm_shift)),
            clamp01(factor * (0.985 + warm_shift * 0.25)),
            clamp01(factor * (0.955 - warm_shift * 0.7)),
            1.0,
        )
    mesh.update()
    return len(mesh.vertices)


def apply_weathered_surface(root: bpy.types.Object) -> dict[str, int | str]:
    converted = convert_authored_curves(root)
    bpy.context.view_layer.update()
    colored_meshes = 0
    colored_vertices = 0
    for obj in descendants(root):
        count = apply_weathered_mesh(obj)
        if count:
            colored_meshes += 1
            colored_vertices += count
    root["surface_contract"] = "sunfold.weathered-building/1"
    root["surface_color_attribute"] = WEATHER_COLOR_ATTRIBUTE
    return {
        "surfaceContract": "sunfold.weathered-building/1",
        "vertexColorAttribute": WEATHER_COLOR_ATTRIBUTE,
        "weatheredMeshCount": colored_meshes,
        "weatheredVertexCount": colored_vertices,
        "convertedCurveCount": converted,
    }


def set_state_visibility(root: bpy.types.Object, state: str) -> None:
    visible = {
        "healthy": {"state_shared", "state_healthy_damaged", "state_healthy_only"},
        "damaged": {"state_shared", "state_healthy_damaged", "state_damaged_plus"},
        "critical": {"state_shared", "state_damaged_plus", "state_critical_plus"},
        "destroyed": {"state_destroyed_only"},
    }[state]
    for group_name in STATE_GROUPS:
        group = next((child for child in root.children if child.name == group_name), None)
        if not group:
            continue
        hidden = group_name not in visible
        # Blender does not inherit an Empty's render flag through its children.
        # Three.js does inherit Group.visible, so recurse here to make the
        # offline proof exercise the same state contract as the runtime.
        for obj in descendants(group):
            obj.hide_render = hidden
            obj.hide_viewport = hidden


def select_hierarchy(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in descendants(root):
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root: bpy.types.Object, path: Path) -> None:
    select_hierarchy(root)
    # Blender's glTF exporter emits a white baseColorFactor when a color node is
    # linked to Principled Base Color. Temporarily expose the authored material
    # color while ACTIVE still exports COLOR_0, then restore the preview graph.
    material_links: list[tuple[bpy.types.NodeTree, bpy.types.NodeSocket, bpy.types.NodeSocket]] = []
    materials = {
        material
        for obj in descendants(root)
        if obj.type == "MESH"
        for material in obj.data.materials
        if material and material.use_nodes
    }
    for mat in materials:
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if not bsdf:
            continue
        base_color = bsdf.inputs.get("Base Color")
        if not base_color:
            continue
        for link in list(base_color.links):
            material_links.append((mat.node_tree, link.from_socket, link.to_socket))
            mat.node_tree.links.remove(link)

    try:
        bpy.ops.export_scene.gltf(
            filepath=str(path),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
            export_animations=False,
            export_extras=True,
            export_materials="EXPORT",
            export_vertex_color="ACTIVE",
            export_all_vertex_colors=False,
            export_cameras=False,
            export_lights=False,
        )
    finally:
        for node_tree, from_socket, to_socket in material_links:
            node_tree.links.new(from_socket, to_socket)


def add_preview_world(root: bpy.types.Object, kind: str) -> None:
    world = bpy.context.scene.world or bpy.data.worlds.new("Sunfold Preview World")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.004, 0.007, 0.014, 1)
    bg.inputs["Strength"].default_value = 0.26

    is_core = kind == "civilization_core"
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=8.4 if is_core else 6.2, depth=0.28, location=(0, 0, -0.16))
    ground = finish_object(bpy.context.object, "preview_ground", make_materials()["ceramic_dark"], empty("preview_environment"), bevel=0.10, smooth=True)
    ground.hide_render = False
    apply_weathered_mesh(ground)

    def light(name, kind_name, energy, color, location, size=5.0):
        data = bpy.data.lights.new(name, kind_name)
        data.energy = energy
        data.color = color
        if kind_name == "AREA":
            data.shape = "DISK"
            data.size = size
        obj = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (math.radians(28), 0, math.radians(145))
        return obj

    light("preview_key", "AREA", 1450, (1.0, 0.54, 0.23), (-7, -9, 13), 7.5)
    light("preview_fill", "AREA", 650, (0.16, 0.68, 0.82), (8, 2, 9), 6.0)
    light("preview_rim", "AREA", 900, (0.35, 0.45, 1.0), (1, 10, 11), 5.0)

    camera_data = bpy.data.cameras.new("preview_camera")
    camera = bpy.data.objects.new("preview_camera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = (13.5, -15.5, 12.5) if is_core else (10.5, -12.0, 9.0)
    target = Vector((0, 0, 4.3 if is_core else 1.9))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 18.4 if is_core else 12.5
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    # Blender 5.2 exposes Eevee Next through the stable BLENDER_EEVEE enum.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 960
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.image_settings.color_depth = "8"
    scene.camera.data.lens = 52


def render_states(root: bpy.types.Object, kind: str, evidence: Path) -> None:
    evidence.mkdir(parents=True, exist_ok=True)
    add_preview_world(root, kind)
    for state in ("healthy", "damaged", "critical", "destroyed"):
        set_state_visibility(root, state)
        bpy.context.scene.render.filepath = str(evidence / f"{kind}-{state}.png")
        bpy.ops.render.render(write_still=True)


def object_stats(root: bpy.types.Object) -> dict[str, int]:
    meshes = [obj for obj in descendants(root) if obj.type == "MESH"]
    return {
        "meshCount": len(meshes),
        "vertexCount": sum(len(obj.data.vertices) for obj in meshes),
        "triangleCount": sum(len(obj.data.loop_triangles) for obj in meshes),
        "materialCount": len({slot.material.name for obj in meshes for slot in obj.material_slots if slot.material}),
    }


def build_one(kind: str, builder, output: Path, evidence: Path | None, skip_render: bool) -> dict:
    reset_scene()
    mats = make_materials()
    root = builder(mats)
    surface_stats = apply_weathered_surface(root)
    for obj in descendants(root):
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
    stats = object_stats(root)

    source_dir = output / "source"
    source_dir.mkdir(parents=True, exist_ok=True)
    blend_path = source_dir / f"sunwoven_{kind}.blend"
    glb_path = output / f"sunwoven_{kind}.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), compress=True)
    export_glb(root, glb_path)

    if evidence and not skip_render:
        render_states(root, kind, evidence)

    return {
        "kind": kind,
        "glb": glb_path.name,
        "source": str(Path("source") / blend_path.name),
        "sizeBytes": glb_path.stat().st_size,
        **stats,
        **surface_stats,
    }


def main() -> None:
    args = parse_args()
    # Generated sources are deterministic. Keep no numbered backup beside the
    # committed .blend files when the script is rerun.
    bpy.context.preferences.filepaths.save_version = 0
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    evidence = args.evidence.resolve() if args.evidence else None

    entries = []
    entries.append(build_one("civilization_core", build_core, output, evidence, args.skip_render))
    entries.append(build_one("farm", build_farm, output, evidence, args.skip_render))
    entries.append(build_one("formation_yard", build_yard, output, evidence, args.skip_render))

    manifest = {
        "schema": "sunfold.building-kit/1",
        "faction": "sunwoven",
        "age": "foundation",
        "coordinateSystem": "glTF Y-up; origins at footprint centres",
        "surfaceStyle": {
            "contract": "sunfold.weathered-building/1",
            "vertexColorAttribute": WEATHER_COLOR_ATTRIBUTE,
            "contactGrounding": True,
        },
        "damageBands": {
            "healthy": {"minimumLifeRatioExclusive": 0.75},
            "damaged": {"minimumLifeRatioExclusive": 0.50},
            "critical": {"minimumLifeRatioExclusive": 0.0},
            "destroyed": {"maximumLifeRatioInclusive": 0.0},
        },
        "visibilityGroups": {
            "state_shared": ["healthy", "damaged", "critical"],
            "state_healthy_damaged": ["healthy", "damaged"],
            "state_healthy_only": ["healthy"],
            "state_damaged_plus": ["damaged", "critical"],
            "state_critical_plus": ["critical"],
            "state_destroyed_only": ["destroyed"],
        },
        "motionNodes": {
            "motion_core_ring": "slow continuous yaw",
            "motion_farm_crops": "restrained wind sway",
            "motion_yard_loom": "slow continuous yaw",
        },
        "buildings": entries,
    }
    manifest_path = output / "sunwoven-foundation-buildings.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
