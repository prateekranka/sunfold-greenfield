#!/usr/bin/env python3
"""render_turnaround.py — dark-composite turnaround QA renders FROM THE GLB.

Imports the exported pathfinder_scout.glb, plays the 'idle' clip at a fixed
frame, and renders 5 orthographic views (front, side-E, rear, 3/4, top) as
transparent RGBA PNGs with: EEVEE, Standard view transform, warm key sun +
cool fill + warm rim, soft ground-contact shadow discs. The shadow discs use
an UNLIT radial-alpha material (pure black emission) so the later PIL
composite over (18,18,24) shows them as dark contact shade.

Usage: blender -b -P render_turnaround.py
Writes: Docs/QA/ThreeJS/pathfinder-v2/raw-<view>.png  (then composite.py)
"""

import math
import os

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GLB = os.path.join(ROOT, "ThreeRuntime", "assets", "citizens", "pathfinder_scout.glb")
OUT_DIR = os.path.join(ROOT, "Docs", "QA", "ThreeJS", "pathfinder-v2")

CLIP = "idle"
FRAME = 4
SIZE = 1024
BG = (0.0706, 0.0706, 0.0941)  # (18,18,24)/255, linear-ish world color

# view definitions in BLENDER space after glTF import (Z-up, figure faces -Y)
VIEWS = [
    ("front",  (0.0, -7.0, 1.42), (0.0, 0.0, 1.42)),
    ("side_e", (-7.0, 0.0, 1.42), (0.0, 0.0, 1.42)),
    ("rear",   (0.0, 7.0, 1.42), (0.0, 0.0, 1.42)),
    ("three_q",(-4.95, -4.95, 1.42), (0.0, 0.0, 1.42)),
    ("top",    (0.0, 0.0, 8.5), (0.0, 0.0, 1.42)),
]


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    ee = sc.eevee
    for attr, val in (("taa_render_samples", 32),):
        if hasattr(ee, attr):
            setattr(ee, attr, val)

    if sc.world is None:
        sc.world = bpy.data.worlds.new("pf_world")
    w = sc.world
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (*BG, 1.0)
        bg.inputs[1].default_value = 1.0

    # warm key sun (above-front-left), cool fill, warm rim from behind
    def sun(name, rot_deg, energy, color, shadow=False):
        bpy.ops.object.light_add(type="SUN", location=(0, 0, 6))
        o = bpy.context.object
        o.name = name
        o.data.energy = energy
        o.data.angle = math.radians(4)
        o.data.color = color
        o.rotation_euler = tuple(math.radians(a) for a in rot_deg)
        if hasattr(o.data, "use_shadow"):
            o.data.use_shadow = shadow
        return o

    sun("pf_key", (62, 0, 25), 1.25, (1.0, 0.93, 0.82), shadow=True)
    sun("pf_fill", (118, 0, -35), 0.50, (0.75, 0.85, 1.0))
    sun("pf_rim", (25, 0, 170), 0.85, (1.0, 0.80, 0.55))


def shadow_disc(name, cx, cy, radius):
    """Unlit radial-alpha shadow plane (pure black emission mix)."""
    bpy.ops.mesh.primitive_grid_add(size=2.0, x_subdivisions=24, y_subdivisions=24,
                                    location=(cx, cy, 0.002))
    grid = bpy.context.object
    grid.name = name
    grid.scale = (radius, radius, 1.0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    m = bpy.data.materials.new(name + "_mat")
    m.use_nodes = True
    try:
        m.blend_method = "BLEND"
        m.shadow_method = "NONE"
    except Exception:
        pass
    nt = m.node_tree
    nodes = nt.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    tex = nodes.new("ShaderNodeTexCoord")
    ln = nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    div = nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    div.inputs[1].default_value = 1.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    e0 = ramp.color_ramp.elements[0]
    e0.position = 0.0
    e0.color = (0.0, 0.0, 0.0, 0.55)
    e1 = ramp.color_ramp.elements[1]
    e1.position = 1.0
    e1.color = (0.0, 0.0, 0.0, 0.0)
    mix = nodes.new("ShaderNodeMixShader")
    trans = nodes.new("ShaderNodeBsdfTransparent")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
    nt.links.new(tex.outputs[1], ln.inputs[0])        # object coords
    nt.links.new(ln.outputs[0], div.inputs[0])
    nt.links.new(div.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], mix.inputs[0])
    nt.links.new(trans.outputs[0], mix.inputs[1])
    nt.links.new(emit.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    grid.data.materials.append(m)
    return grid


def look_at(cam, eye, target):
    """Orient the camera so its -Z points from eye toward target."""
    z = (Vector(eye) - Vector(target)).normalized()
    up = Vector((0.0, 0.0, 1.0))
    if abs(z.dot(up)) > 0.99:      # top-down: pick a non-parallel up
        up = Vector((0.0, 1.0, 0.0))
    x = up.cross(z).normalized()
    y = z.cross(x)
    cam.rotation_euler = Matrix((x, y, z)).transposed().to_4x4().to_euler()


def render_views(arm):
    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("pf_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.7
    cam = bpy.data.objects.new("pf_cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    results = []
    for (name, eye, target) in VIEWS:
        cam.location = Vector(eye)
        look_at(cam, eye, target)
        out = os.path.join(OUT_DIR, f"raw-{name}.png")
        sc.render.filepath = out
        bpy.ops.render.render(write_still=True)
        results.append((name, out))
        print(f"RENDERED {name} -> {out}")
    return results


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=GLB)
    # Blender 5.x importer spawns a hidden, un-materialed 'Icosphere'
    # placeholder — drop it so it never enters render or counts.
    for o in list(bpy.data.objects):
        if o.name == "Icosphere" or not o.visible_get():
            bpy.data.objects.remove(o, do_unlink=True)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    act = bpy.data.actions.get(CLIP)
    if act is None:
        raise SystemExit(f"clip '{CLIP}' not found in GLB; actions: "
                         f"{sorted(a.name for a in bpy.data.actions)}")
    arm.animation_data_create()
    arm.animation_data.action = act
    bpy.context.scene.frame_set(FRAME)
    setup_scene()
    shadow_disc("shadow_unit", 0.0, 0.0, 0.36)
    shadow_disc("shadow_std", 0.24, -0.18, 0.15)
    render_views(arm)
    print("RENDER_DONE")


if __name__ == "__main__":
    main()
