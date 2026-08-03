"""B23-BUILD — deterministic neutral-lab build, export, render and manifest pass.

Runs inside Blender (background mode):

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/citizens/build_lab.py -- --step all

Builds the full neutral lab (two proportion citizens on one skeleton, identical
prop sets, all named clips with authored tool + accessory motion), preserves
the editable .blend, exports the skinned and lab GLBs under the Three.js
assets, renders the lab + construction + locked-pose views, and writes the
event-marker / clip-semantic manifest and a run report.

Determinism: every number is authored; nothing is sampled, randomized or
imported. Blender 5.2 with the legacy Actions API is the only requirement.
"""

from __future__ import annotations

import hashlib
import math
import json
import os
import shlex
import subprocess
import sys

import bpy
import mathutils
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import clips
import props as lab_props
import rig
from skin import build_carrier, build_mannequin, build_tool

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")
ASSETS = os.path.join(HERE, "assets")
MANIFEST_DIR = os.path.join(HERE, "manifest")
RUNTIME_ASSETS = os.path.join(REPO, "ThreeRuntime", "assets", "lab")
RENDER_DIR = os.path.join(BUILD, "renders")
LOCKED_POSE_CLIP = "slender_gather_loop_R"
LOCKED_POSE_FRAME = 12

# Repository-derived RTS camera (main.js) and lighting.
RTS_POS = (0.0, 7.5, 12.5)
RTS_TARGET = (0.0, 0.0, 0.0)
KEY_DIRECTION = (-4.0, 10.0, 5.0)
KEY_COLOR = (1.0, 0.824, 0.549)  # 0xffd28c
KEY_ENERGY = float(os.environ.get("B23_KEY_ENERGY", "10.0"))
FILL_DIRECTION = (2.0, 3.0, -4.0)
FILL_COLOR = (0.078, 0.09, 0.169)  # 0x14172b
FILL_ENERGY = float(os.environ.get("B23_FILL_ENERGY", "1.5"))
BOUNCE_DIRECTION = (0.0, -6.0, 2.0)
BOUNCE_COLOR = (0.52, 0.57, 0.72)  # 0x8592b8, hemisphere-sky-ish
BOUNCE_ENERGY = float(os.environ.get("B23_BOUNCE_ENERGY", "3.0"))
BG_COLOR = (0.0196, 0.0275, 0.0667)  # 0x050711
WORLD_STRENGTH = float(os.environ.get("B23_WORLD_STRENGTH", "1.0"))

CITIZENS = ("spike_slender", "spike_broad")
POSITIONS = {"spike_slender": 0.0, "spike_broad": 5.0}
LAB_LOOK_AT = (2.5, 0.0, 1.2)


def clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for arm in list(bpy.data.armatures):
        bpy.data.armatures.remove(arm)
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)


def build_citizen(proportion_key: str, origin_x: float):
    """Build one armature + mannequin + carrier + tools at origin_x."""
    p = rig.PROPORTIONS[proportion_key]
    fm = clips.FACTION_MOTION[proportion_key]
    prefix = "slender" if proportion_key == "spike_slender" else "broad"

    arm = rig.build_armature(f"{prefix}_armature", p)
    body = build_mannequin(arm, p, name=f"{prefix}_body")
    carrier = build_carrier(arm, p, fm["carrier_kind"], name=f"{prefix}_carrier")
    scraper = build_tool(f"{prefix}_scraper", "scraper")
    mallet = build_tool(f"{prefix}_mallet", "mallet")

    # Place tools at the socket grips, then parent them to the sockets so
    # they ride the skeleton (authored, never physics).
    for tool, socket in ((scraper, "socket_tool_R"), (mallet, "socket_tool_L")):
        rest_world = arm.matrix_world @ arm.data.bones[socket].matrix_local
        tool.matrix_world = rest_world
        tool.parent = arm
        tool.parent_type = "BONE"
        tool.parent_bone = socket

    arm.location = (origin_x, 0.0, 0.0)
    return arm, body, carrier, scraper, mallet


def socket_world_at(arm_obj, frames_poses, frame: int, socket: str) -> Matrix:
    """Socket world matrix at `frame` for the given keyframe table (no action)."""
    scene = bpy.context.scene
    scene.frame_set(frame)
    pose = None
    for f, p in frames_poses:
        if f == frame:
            pose = p
            break
    if pose is not None:
        for bone, euler in pose.items():
            if bone.startswith("@"):
                continue
            pb = arm_obj.pose.bones[bone]
            pb.rotation_quaternion = rig.world_euler_to_pose_quat(arm_obj, bone, *euler)
        if "@hips_loc" in pose:
            arm_obj.pose.bones["hips"].location = pose["@hips_loc"]
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    return arm_obj.matrix_world @ arm_obj.pose.bones[socket].matrix


def place_rest_posts(arm_obj, spec_list, socket, side, prefix) -> Matrix:
    """Park rest posts under the tools' parked (stand) transforms."""
    source_suffix = "gather_start_R" if socket == "socket_tool_R" else "construct_start_L"
    start = next(s for s in spec_list if s["suffix"] == source_suffix)
    stand = socket_world_at(arm_obj, start["keyframes"], start["attach_frame"], socket)
    rest_name = f"{prefix}_rest_{side}_" + ("scraper" if socket == "socket_tool_R" else "mallet")
    rest = bpy.data.objects.get(rest_name)
    if rest is not None:
        rest.location = (stand.translation.x, stand.translation.y, stand.translation.z - 0.14)
    return stand


def author_citizen_clips(arm_obj, proportion_key: str, stand_matrices: dict[str, Matrix]) -> list[dict]:
    fm = clips.FACTION_MOTION[proportion_key]
    prefix = "slender" if proportion_key == "spike_slender" else "broad"
    specs = clips.clip_specs(prefix, fm)
    for spec in specs:
        clips.author_action(arm_obj, spec, stand_matrices)
    return specs


def export_glb(objects_to_export: list | None, path: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    if objects_to_export is not None:
        for obj in objects_to_export:
            obj.select_set(True)
    kwargs = dict(
        filepath=path,
        export_format="GLB",
        use_selection=objects_to_export is not None,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_current_frame=False,
        export_bake_animation=False,
        export_force_sampling=False,
        export_def_bones=False,
        export_extras=True,
        export_skins=True,
        export_morph=False,
    )
    bpy.ops.export_scene.gltf(**kwargs)


def setup_camera(ortho: bool, look_at: tuple, distance_dir: tuple) -> bpy.types.Object:
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("lab_cam")
    cam = bpy.data.objects.new("lab_cam", cam_data)
    scene.collection.objects.link(cam)
    cam_data.type = "ORTHO" if ortho else "PERSP"
    cam_data.clip_start = 0.01
    if ortho:
        cam_data.ortho_scale = 3.6
    else:
        cam_data.angle = math.radians(38.0)
    target = Vector(look_at)
    pos = target + Vector(distance_dir)
    cam.location = pos
    direction = target - pos
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


def setup_lights(scene) -> None:
    world = scene.world or bpy.data.worlds.new("LabWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (*BG_COLOR, 1.0)
        bg.inputs[1].default_value = WORLD_STRENGTH

    key = bpy.data.objects.new("key_sun", bpy.data.lights.new("key_sun", "SUN"))
    scene.collection.objects.link(key)
    key.data.energy = KEY_ENERGY
    key.data.color = KEY_COLOR
    # main.js places the key at (-4,10,5) shining at the origin; the sun must
    # travel along (target - source), so point -Z along -KEY_DIRECTION.
    key.rotation_euler = Vector((0.0, 0.0, -1.0)).rotation_difference(
        -Vector(KEY_DIRECTION).normalized()
    ).to_euler()

    fill = bpy.data.objects.new("fill_sun", bpy.data.lights.new("fill_sun", "SUN"))
    scene.collection.objects.link(fill)
    fill.data.energy = FILL_ENERGY
    fill.data.color = FILL_COLOR
    fill.rotation_euler = Vector((0.0, 0.0, -1.0)).rotation_difference(
        -Vector(FILL_DIRECTION).normalized()
    ).to_euler()

    bounce = bpy.data.objects.new("bounce_sun", bpy.data.lights.new("bounce_sun", "SUN"))
    scene.collection.objects.link(bounce)
    bounce.data.energy = BOUNCE_ENERGY
    bounce.data.color = BOUNCE_COLOR
    bounce.rotation_euler = Vector((0.0, 0.0, -1.0)).rotation_difference(
        -Vector(BOUNCE_DIRECTION).normalized()
    ).to_euler()


def render_view(scene, cam, out_path: str, width: int = 1600, height: int = 900) -> None:
    bpy.context.view_layer.update()
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.camera = cam
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)


def assemble_marker_manifest(specs_by_citizen: dict[str, list[dict]]) -> dict:
    clips_out = []
    markers_out = []
    for citizen, specs in specs_by_citizen.items():
        for spec in specs:
            clip = {
                "name": spec["name"],
                "citizen": citizen,
                "semantic": spec["semantic"],
                "handedness": spec["handedness"],
                "loop": spec["loop"],
                "frame_start": spec["frame_start"],
                "frame_end": spec["frame_end"],
                "duration_s": spec["duration_s"],
                "grip_socket": spec.get("grip_socket"),
            }
            clips_out.append(clip)
            for frame, mname in spec["markers"]:
                markers_out.append(
                    {
                        "clip": spec["name"],
                        "name": mname,
                        "frame": frame,
                        "time_s": round(frame / clips.FPS, 4),
                        "source": "authored",
                    }
                )
            if spec["semantic"] == "gather_loop" and spec.get("handedness"):
                contact = next(f for f, n in spec["markers"] if n == "gather_contact")
                arrive = contact + clips.ARC_DURATION_FRAMES
                markers_out.append(
                    {
                        "clip": spec["name"],
                        "name": "payload_attach",
                        "frame": arrive,
                        "time_s": round(arrive / clips.FPS, 4),
                        "source": "derived",
                        "anchor": "gather_contact",
                        "offset_frames": clips.ARC_DURATION_FRAMES,
                    }
                )
    manifest = {
        "schema": "sunfold.lab.event-markers/1",
        "fps": clips.FPS,
        "arc_duration_frames": clips.ARC_DURATION_FRAMES,
        "marker_events": list(clips.MARKER_EVENTS),
        "clips": clips_out,
        "markers": markers_out,
    }
    return manifest


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_report(outputs: dict) -> dict:
    return {
        "generator": "Tools/citizens/build_lab.py",
        "blender": bpy.app.version_string,
        "blender_build": bpy.app.build_hash.decode() if isinstance(bpy.app.build_hash, bytes) else str(bpy.app.build_hash),
        "python": sys.version.split()[0],
        "fps": clips.FPS,
        "outputs": outputs,
    }


# Blender (x,y,z) -> glTF (x,z,-y) rigid transform, per the rig contract.
GLTF_AXIS = Matrix(
    (
        (1.0, 0.0, 0.0, 0.0),
        (0.0, 0.0, 1.0, 0.0),
        (0.0, -1.0, 0.0, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    )
)


def dump_locked_pose(arm_obj, body_obj, out_path: str, frame: int, fps: int) -> None:
    """Write bone poses + deformed skin vertices at `frame` in glTF space.

    The vertex list is the visual truth of the pose: comparing it against the
    Three.js import proves the round trip on what actually renders.
    """
    scene = bpy.context.scene
    scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    bones = {}
    for pb in arm_obj.pose.bones:
        m = arm_obj.matrix_world @ pb.matrix
        mg = GLTF_AXIS @ m @ GLTF_AXIS.inverted()
        loc, quat, _scale = mg.decompose()
        bones[pb.name] = {
            "position": [round(v, 6) for v in loc],
            "quaternion": [round(v, 6) for v in quat],
        }
    body_eval = body_obj.evaluated_get(depsgraph)
    verts = []
    for v in body_eval.data.vertices:
        w = GLTF_AXIS @ (body_obj.matrix_world @ v.co)
        verts.append([round(c, 6) for c in (w.x, w.y, w.z)])
    payload = {
        "schema": "sunfold.lab.locked-pose/1",
        "clip": LOCKED_POSE_CLIP,
        "frame": frame,
        "time_s": round(frame / fps, 4),
        "space": "gltf (x, z, -y from blender)",
        "bones": bones,
        "skin_vertex_count": len(verts),
        "skin_vertices": verts,
    }
    with open(out_path, "w") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
    print(f"[build_lab] wrote {out_path}")


def main() -> None:
    steps = set()
    env_steps = os.environ.get("B23_STEPS", "")
    if env_steps:
        steps.update(s.strip() for s in env_steps.split(",") if s.strip())
    for a in sys.argv:
        if a.startswith("--step="):
            steps.update(s.strip() for s in a[len("--step="):].split(",") if s.strip())
    if not steps or "all" in steps:
        steps = {"build", "export", "render", "manifest"}
    citizen_key = os.environ.get("B23_CITIZEN")
    if citizen_key not in (None, *CITIZENS):
        raise ValueError(f"B23_CITIZEN must be one of {CITIZENS}, got {citizen_key!r}")
    citizen_only = citizen_key is not None

    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(ASSETS, exist_ok=True)
    os.makedirs(MANIFEST_DIR, exist_ok=True)
    os.makedirs(RUNTIME_ASSETS, exist_ok=True)
    os.makedirs(RENDER_DIR, exist_ok=True)

    scene = bpy.context.scene
    scene.frame_start = 0
    scene.frame_end = 72
    scene.render.fps = clips.FPS
    scene.render.fps_base = 1.0

    clear_scene()
    setup_lights(scene)

    specs_by_citizen: dict[str, list[dict]] = {}
    stand_worlds: dict[str, dict[str, Matrix]] = {}
    prop_sets = {}

    for key in ((citizen_key,) if citizen_only else CITIZENS):
        prefix = "slender" if key == "spike_slender" else "broad"
        arm, _body, _carrier, _scraper, _mallet = build_citizen(key, 0.0 if citizen_only else POSITIONS[key])
        # Compute parked stand matrices from the attach-frame poses first.
        fm = clips.FACTION_MOTION[key]
        prefix_specs = clips.clip_specs(prefix, fm)
        g_start = next(s for s in prefix_specs if s["suffix"] == "gather_start_R")
        c_start = next(s for s in prefix_specs if s["suffix"] == "construct_start_L")
        stand_R = socket_world_at(arm, g_start["keyframes"], g_start["attach_frame"], "socket_tool_R")
        stand_L = socket_world_at(arm, c_start["keyframes"], c_start["attach_frame"], "socket_tool_L")
        # Lay the tools flat on the rack (rotate ~90 deg about X).
        flat_R = stand_R @ Matrix.Rotation(math.radians(90.0), 4, "X")
        flat_L = stand_L @ Matrix.Rotation(math.radians(90.0), 4, "X")
        stand_worlds[key] = {"socket_tool_R": flat_R, "socket_tool_L": flat_L}

        if not citizen_only:
            props_set = lab_props.build_prop_set(POSITIONS[key], prefix=prefix)
            prop_sets[key] = props_set

        # Author clips AFTER the stand matrices exist.
        specs = author_citizen_clips(arm, key, stand_worlds[key])
        specs_by_citizen[key] = specs

        if not citizen_only:
            # Park the rest posts under the flat tools.
            place_rest_posts(arm, specs, "socket_tool_R", "R", prefix)
            place_rest_posts(arm, specs, "socket_tool_L", "L", prefix)

    if "build" in steps and not citizen_only:
        blend_path = os.path.join(ASSETS, "neutral_lab.blend")
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
        print(f"[build_lab] saved {blend_path}")

    if "export" in steps:
        if citizen_only:
            prefix = "slender" if citizen_key == "spike_slender" else "broad"
            armature = next(o for o in bpy.data.objects if o.name == f"{prefix}_armature")
            parts = [armature]
            parts += [o for o in bpy.data.objects if o.parent is armature]
            export_glb(parts, os.path.join(RUNTIME_ASSETS, f"citizen_{prefix}.glb"))
            print(f"[build_lab] exported citizen_{prefix}.glb (citizen-only pass)")
        else:
            export_glb(None, os.path.join(RUNTIME_ASSETS, "neutral_lab.glb"))
            print("[build_lab] exported neutral_lab.glb")

    if "render" in steps and not citizen_only:
        # Lab views (repository RTS camera rig, perspective).
        lab_views = {
            "lab-front": (0.0, -7.0, 4.2),
            "lab-rear": (0.0, 7.0, 4.2),
            "lab-side": (7.0, 0.0, 4.2),
            "lab-threequarter": (4.95, -4.95, 4.2),
            "lab-rts": RTS_POS,
        }
        for view, pos in lab_views.items():
            cam = setup_camera(False, LAB_LOOK_AT if view != "lab-rts" else RTS_TARGET, pos)
            render_view(scene, cam, os.path.join(RENDER_DIR, f"{view}.png"))
        # Construction turnarounds (orthographic, per citizen).
        for key in CITIZENS:
            prefix = "slender" if key == "spike_slender" else "broad"
            x = POSITIONS[key]
            armature = bpy.data.objects[f"{prefix}_armature"]
            visible = {armature, *[obj for obj in bpy.data.objects if obj.parent is armature]}
            prior_hidden = {obj: obj.hide_render for obj in bpy.data.objects}
            for obj in bpy.data.objects:
                if obj.type in {"MESH", "ARMATURE"}:
                    obj.hide_render = obj not in visible
            tracks = list(armature.animation_data.nla_tracks) if armature.animation_data else []
            prior_mutes = [track.mute for track in tracks]
            for track in tracks:
                track.mute = True
            if armature.animation_data:
                armature.animation_data.action = None
            for pose_bone in armature.pose.bones:
                pose_bone.matrix_basis = Matrix.Identity(4)
            scene.frame_set(0)
            look = (x, 0.0, 1.0)
            for view, off in (
                ("front", (0.0, -1.0, 0.0)),
                ("side", (1.0, 0.0, 0.0)),
                ("rear", (0.0, 1.0, 0.0)),
                ("threequarter", (0.707, -0.707, 0.0)),
            ):
                cam = setup_camera(True, look, tuple(Vector(off) * 8.0))
                cam.data.ortho_scale = 2.4
                render_view(scene, cam, os.path.join(RENDER_DIR, f"turnaround-{prefix}-{view}.png"), 1024, 1024)
            for track, mute in zip(tracks, prior_mutes):
                track.mute = mute
            for obj, hidden in prior_hidden.items():
                obj.hide_render = hidden
        # Locked-pose source render (slender gather_loop_R contact frame).
        arm = next(o for o in bpy.data.objects if o.name == "slender_armature")
        body = next(o for o in bpy.data.objects if o.name == "slender_body")
        act = bpy.data.actions[LOCKED_POSE_CLIP]
        cam = setup_camera(False, (0.0, 0.0, 0.9), (0.0, -4.5, 2.1))
        arm.animation_data.action = act
        scene.frame_set(LOCKED_POSE_FRAME)
        render_view(scene, cam, os.path.join(RENDER_DIR, "locked-pose-source.png"))
        dump_locked_pose(arm, body, os.path.join(BUILD, "locked-pose-source.json"), LOCKED_POSE_FRAME, clips.FPS)
        arm.animation_data.action = None
        print("[build_lab] rendered lab views, turnarounds, locked pose")

    if "manifest" in steps and not citizen_only:
        manifest = assemble_marker_manifest(specs_by_citizen)
        manifest_path = os.path.join(MANIFEST_DIR, "event-markers.json")
        with open(manifest_path, "w") as fh:
            json.dump(manifest, fh, indent=2)
        # Keep a copy beside the runtime assets for the harness.
        runtime_manifest = os.path.join(RUNTIME_ASSETS, "event-markers.json")
        with open(runtime_manifest, "w") as fh:
            json.dump(manifest, fh, indent=2)
        print(f"[build_lab] wrote {manifest_path}")

        outputs = {
            "blend": os.path.join(ASSETS, "neutral_lab.blend"),
            "citizen_glb": os.path.join(RUNTIME_ASSETS, "citizen_slender.glb"),
            "lab_glb": os.path.join(RUNTIME_ASSETS, "neutral_lab.glb"),
            "manifest": manifest_path,
            "renders": RENDER_DIR,
        }
        for k in ("citizen_glb", "lab_glb"):
            if os.path.exists(outputs[k]):
                outputs[k + "_sha256"] = sha256(outputs[k])
        report = run_report(outputs)
        report_path = os.path.join(BUILD, "run-report.json")
        with open(report_path, "w") as fh:
            json.dump(report, fh, indent=2)
        print(f"[build_lab] wrote {report_path}")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
