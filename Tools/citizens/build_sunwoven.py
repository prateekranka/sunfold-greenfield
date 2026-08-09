"""B24-BUILD — production Sunwoven Weaver lab build, export, render, manifest.

Runs inside Blender (background mode):

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/citizens/build_sunwoven.py

Builds the production Foundation Sunwoven Weaver on the shared 27-bone rig,
authors the full 18-clip Sunwoven inventory (with authored chunk-arc object
channels inside the gather-loop clips via multi-slot actions), assembles the
neutral prop set around one workstation, exports the lab GLB and the
citizen-only GLB, renders turnarounds / lab views / RTS / locked pose, and
writes the Sunwoven event-marker manifest plus the authored sequence and
piece-settle tables.

Determinism: every number is authored; nothing is sampled, randomized or
imported. Blender 5.2 + the legacy Actions API are the only requirements.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import clips
import codex_shell
import props as lab_props
import rig
import sunwoven_skin
from build_lab import (
    GLTF_AXIS,
    KEY_COLOR,
    RTS_POS as LAB_RTS_POS,
    RTS_TARGET as LAB_RTS_TARGET,
    clear_scene,
    dump_locked_pose,
    export_glb,
    place_rest_posts,
    render_view,
    setup_camera,
    setup_lights,
    sha256,
    socket_world_at,
)

RTS_POS = (5.0, -6.2, 4.6)
RTS_TARGET = (0.35, -0.25, 0.92)
THREEQUARTER_POS = (4.4, -5.4, 3.8)
THREEQUARTER_TARGET = (0.35, -0.10, 0.98)

RTS_POS_LAB = LAB_RTS_POS
RTS_TARGET_LAB = LAB_RTS_TARGET

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")
HULL_PATH = os.path.join(BUILD, "codex-hull-sunwoven.json")
ASSETS = os.path.join(HERE, "assets")
MANIFEST_DIR = os.path.join(HERE, "manifest")
RUNTIME_ASSETS = os.path.join(REPO, "ThreeRuntime", "assets", "citizens")
RENDER_DIR = os.path.join(BUILD, "renders")

CITIZEN_KEY = "sunwoven"
PREFIX = "sunwoven"
LOCKED_POSE_CLIP = "sunwoven_gather_loop_R"
LOCKED_POSE_FRAME = 12
CANONICAL_POSE_CLIP = "sunwoven_walk_loaded_inplace"
CANONICAL_POSE_FRAME = 0

# Authored sequence constants (Blender space; harness converts to glTF).
# Stations are co-located with the authored lab props so idle never overlaps
# the construction frame and deposit stays on the deposit pad.
WALK_SPEED_M_S = 2.2
GATHER_STATION = (-0.55, -1.2)
DEPOSIT_STATION = (0.0, -2.7)
CONSTRUCT_STATION = (3.4, -1.2)

# Authored piece settle (construct): snap down then settle, LINEAR keys.
PIECE_SETTLE = {"contact_offset_frames": 2, "keys": [[0, 0.0], [2, -0.012], [4, 0.0]]}


def arc_keyframes(arm_obj, frames_poses, pile_center) -> list[tuple[int, Vector]]:
    """Authored gather-loop chunk arc: pile -> pop -> mid -> basket commit.

    The arc is keyed on the arc prop object inside the gather-loop actions
    (multi-slot), so the DCC keyframes ship inside the exported clips. The
    commit point is the cargo-chunk 0 rest position above the basket rim
    (computed from the accessory_strap rest frame, matching the cargo build).
    """
    strap = arm_obj.data.bones["accessory_strap"]
    strap_world = arm_obj.matrix_world @ strap.matrix_local
    orient = strap.matrix_local.to_3x3()
    head = strap.head_local.copy()
    tail = strap.tail_local.copy()
    axis = (tail - head).normalized()
    length = max((tail - head).length, 1e-6)
    z_axis = orient.col[2].normalized()
    rim_center = head + axis * (length * 0.60) + z_axis * 0.19
    commit = strap_world @ (rim_center + Vector((0.0, 0.02, 0.10)))
    pile = Vector(pile_center)
    mid = pile.lerp(commit, 0.62) + Vector((0.0, 0.08, 0.30))
    pop = pile + Vector((0.02, 0.04, 0.34))
    return [
        (0, pile),
        (12, pile),
        (14, pop),
        (18, mid),
        (24, commit),
        (36, pile),
    ]


def author_arc_prop_channels(arm_obj, arc_prop, action, slot, keys, fps=clips.FPS):
    """Keyframe arc_prop.location into `action`'s arc_prop slot (LINEAR)."""
    arc_prop.animation_data_create()
    arc_prop.animation_data.action = action
    arc_prop.animation_data.action_slot = slot
    for frame, pos in keys:
        arc_prop.location = pos
        arc_prop.keyframe_insert(data_path="location", frame=frame)
    arc_prop.animation_data.action = None
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                if cb.slot is not None and cb.slot.handle == slot.handle:
                    for fc in cb.fcurves:
                        for kp in fc.keyframe_points:
                            kp.interpolation = "LINEAR"


def push_prop_strip(obj, action, slot):
    """NLA strip on the prop object so the exporter gathers its channels."""
    obj.animation_data_create()
    track = obj.animation_data.nla_tracks.new()
    track.name = "Clips"
    strip = track.strips.new(action.name, 0, action)
    strip.action = action
    strip.action_slot = slot


def build_citizen():
    """The production Weaver + tools + cargo, and the clip actions."""
    p = rig.PROPORTIONS[CITIZEN_KEY]
    fm = clips.FACTION_MOTION[CITIZEN_KEY]
    mats = sunwoven_skin.ensure_materials()

    arm = rig.build_armature(f"{PREFIX}_armature", p)
    body = sunwoven_skin.build_sunwoven_body(arm, p, mats)
    headwrap = sunwoven_skin.build_sunwoven_headwrap(arm, p, mats)
    hair = sunwoven_skin.build_sunwoven_hair(arm, p, mats)
    face = sunwoven_skin.build_sunwoven_face(arm, p, mats)
    tunic = sunwoven_skin.build_sunwoven_tunic(arm, p, mats)
    front_panels = sunwoven_skin.build_sunwoven_front_panels(arm, p, mats)
    belt_band = sunwoven_skin.build_sunwoven_belt_band(arm, p, mats)
    bangles = sunwoven_skin.build_sunwoven_bangles(arm, p, mats)
    sleeves = sunwoven_skin.build_sunwoven_sleeves(arm, p, mats)
    trousers = sunwoven_skin.build_sunwoven_trousers(arm, p, mats)
    leg_wraps = sunwoven_skin.build_sunwoven_leg_wraps(arm, p, mats)
    sash = sunwoven_skin.build_sunwoven_sash(arm, p, mats)
    leather = sunwoven_skin.build_sunwoven_leather(arm, p, mats)
    sandals = sunwoven_skin.build_sunwoven_sandals(arm, p, mats)
    basket = sunwoven_skin.build_sunwoven_basket(arm, p, mats)
    pack_shoulders = sunwoven_skin.build_sunwoven_pack_shoulders(arm, p, mats)
    pack_ropes = sunwoven_skin.build_sunwoven_pack_ropes(arm, p, mats)
    side_basket = sunwoven_skin.build_sunwoven_side_basket(arm, p, mats)
    tools = sunwoven_skin.build_sunwoven_sickle_and_beater(arm, mats)
    display_sickle = sunwoven_skin.build_sunwoven_display_sickle(arm, mats)
    hand_bucket = sunwoven_skin.build_sunwoven_hand_bucket(arm, p, mats)
    cargo = sunwoven_skin.build_sunwoven_cargo_chunks(arm, mats)
    arc_prop = sunwoven_skin.build_arc_prop(mats)
    codex_envelope = codex_shell.build_codex_envelopes(arm, mats, HULL_PATH, PREFIX)

    citizen_parts = [
        arm, body, basket, *pack_shoulders, *pack_ropes, *hair,
        *headwrap, *face, tunic, *front_panels, belt_band, *bangles, *sleeves, *trousers, *leg_wraps, *sash, *leather, *sandals,
        *side_basket, *tools, display_sickle, hand_bucket,
    ]
    citizen_parts.extend(codex_envelope.values())
    return arm, fm, mats, cargo, arc_prop, citizen_parts, codex_envelope


def author_sunwoven_clips(arm_obj, fm):
    """Author the 18 Sunwoven clips and the authored arc channels."""
    specs = clips.clip_specs(PREFIX, fm)

    # Stand matrices for the parked tool poses (same as the neutral lab).
    g_start = next(s for s in specs if s["suffix"] == "gather_start_R")
    c_start = next(s for s in specs if s["suffix"] == "construct_start_L")
    stand_R = socket_world_at(arm_obj, g_start["keyframes"], g_start["attach_frame"], "socket_tool_R")
    stand_L = socket_world_at(arm_obj, c_start["keyframes"], c_start["attach_frame"], "socket_tool_L")
    flat_R = stand_R @ Matrix.Rotation(math.radians(90.0), 4, "X")
    flat_L = stand_L @ Matrix.Rotation(math.radians(90.0), 4, "X")
    stand_worlds = {"socket_tool_R": flat_R, "socket_tool_L": flat_L}

    for spec in specs:
        clips.author_action(arm_obj, spec, stand_worlds)

    # Arc prop: authored chunk arc inside the gather-loop actions.
    arc_prop = next(o for o in bpy.data.objects if o.name == f"{PREFIX}_arc_prop")
    pile_center = (-0.55, -1.2, 0.20)
    for suffix in ("gather_loop_R", "gather_loop_L"):
        action = bpy.data.actions[f"{PREFIX}_{suffix}"]
        slot = action.slots.new("OBJECT", arc_prop.data.name)
        frames_poses = next(s for s in specs if s["suffix"] == suffix)["keyframes"]
        keys = arc_keyframes(arm_obj, frames_poses, pile_center)
        author_arc_prop_channels(arm_obj, arc_prop, action, slot, keys)
        push_prop_strip(arc_prop, action, slot)
    return specs, stand_worlds


def assemble_manifest(specs: list[dict], citizen: str = PREFIX) -> dict:
    clips_out, markers_out = [], []
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
            markers_out.append({
                "clip": spec["name"], "name": mname, "frame": frame,
                "time_s": round(frame / clips.FPS, 4), "source": "authored",
            })
        if spec["semantic"] == "gather_loop" and spec.get("handedness"):
            contact = next(f for f, n in spec["markers"] if n == "gather_contact")
            arrive = contact + clips.ARC_DURATION_FRAMES
            markers_out.append({
                "clip": spec["name"], "name": "payload_attach", "frame": arrive,
                "time_s": round(arrive / clips.FPS, 4), "source": "derived",
                "anchor": "gather_contact", "offset_frames": clips.ARC_DURATION_FRAMES,
            })
    manifest = {
        "schema": "sunfold.sunwoven.event-markers/1",
        "fps": clips.FPS,
        "arc_duration_frames": clips.ARC_DURATION_FRAMES,
        "marker_events": list(clips.MARKER_EVENTS),
        "arc_prop": {"name": f"{citizen}_arc_prop", "role": "gather_arc"},
        "cargo_chunks": [f"{citizen}_cargo_{i}" for i in range(3)],
        "piece_settle": PIECE_SETTLE,
        "sequence": {
            "fps": clips.FPS,
            "walk_speed_m_s": WALK_SPEED_M_S,
            "space": "blender (x, z height; -Y forward)",
            "steps": [
                {"clip": f"{citizen}_idle", "position": (0.0, 0.0), "yaw_deg": 0.0},
                {"clip": f"{citizen}_walk_inplace", "position": GATHER_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_gather_start_R", "position": GATHER_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_gather_loop_R", "position": GATHER_STATION, "yaw_deg": 0.0, "repeat": 3},
                {"clip": f"{citizen}_gather_finish_R", "position": GATHER_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_walk_loaded_inplace", "position": DEPOSIT_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_deposit", "position": DEPOSIT_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_walk_inplace", "position": CONSTRUCT_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_construct_start_L", "position": CONSTRUCT_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_construct_loop_L", "position": CONSTRUCT_STATION, "yaw_deg": 0.0, "repeat": 3},
                {"clip": f"{citizen}_construct_finish_L", "position": CONSTRUCT_STATION, "yaw_deg": 0.0},
                {"clip": f"{citizen}_idle", "position": CONSTRUCT_STATION, "yaw_deg": 0.0},
            ],
        },
        "clips": clips_out,
        "markers": markers_out,
    }
    return manifest


def render_turnarounds(scene, arm_obj, prefix: str, codex_shells: dict | None = None) -> None:
    visible = {arm_obj, *[o for o in bpy.data.objects if o.parent is arm_obj]}
    prior_hidden = {o: o.hide_render for o in bpy.data.objects}
    for obj in bpy.data.objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.hide_render = obj not in visible
    tracks = list(arm_obj.animation_data.nla_tracks) if arm_obj.animation_data else []
    prior_mutes = [t.mute for t in tracks]
    for track in tracks:
        track.mute = True
    if arm_obj.animation_data:
        arm_obj.animation_data.action = None
    for pose_bone in arm_obj.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    # Codex front: arms at sides, left hand (viewer right) holds sickle.
    for side, yaw, roll in (("L", -8.0, 8.0), ("R", 8.0, -8.0)):
        upper = arm_obj.pose.bones[f"upperarm_{side}"]
        upper.rotation_mode = "QUATERNION"
        upper.rotation_quaternion = rig.world_euler_to_pose_quat(arm_obj, f"upperarm_{side}", yaw, 0.0, roll)
        lower = arm_obj.pose.bones[f"lowerarm_{side}"]
        lower.rotation_mode = "QUATERNION"
        lower.rotation_quaternion = rig.world_euler_to_pose_quat(
            arm_obj, f"lowerarm_{side}", -12.0 if side == "L" else -8.0, 0.0, 0.0,
        )
    bpy.context.view_layer.update()
    scene.frame_set(0)
    look = (0.0, 0.0, 1.0)
    hide_for_view = {
        "front": {f"{prefix}_mallet", f"{prefix}_hand_bucket", f"{prefix}_scraper", f"{prefix}_side_basket", f"{prefix}_side_basket_sling"},
        "side": {f"{prefix}_mallet", f"{prefix}_scraper"},
        "rear": {f"{prefix}_mallet", f"{prefix}_scraper", f"{prefix}_display_sickle"},
        "threequarter": {f"{prefix}_mallet", f"{prefix}_scraper"},
    }
    view_shell_map = {"front": "front", "side": "side", "rear": "back", "threequarter": "front"}
    all_view_hidden = set()
    for names in hide_for_view.values():
        all_view_hidden.update(names)
    use_codex_shells = bool(codex_shells)
    for view, off in (
        ("front", (0.0, -1.0, 0.0)),
        ("side", (1.0, 0.0, 0.0)),
        ("rear", (0.0, 1.0, 0.0)),
        ("threequarter", (0.707, -0.707, 0.0)),
    ):
        if use_codex_shells:
            codex_shell.apply_turnaround_shell(prefix, view_shell_map.get(view, "front"), codex_shells, visible)
        else:
            for obj in bpy.data.objects:
                if obj.name in all_view_hidden:
                    obj.hide_render = obj not in visible
        cam = setup_camera(True, look, tuple(Vector(off) * 8.0))
        cam.data.ortho_scale = 2.32
        if not use_codex_shells:
            extra_hidden = hide_for_view.get(view, set())
            for obj in bpy.data.objects:
                if obj.name in extra_hidden:
                    obj.hide_render = True
        render_view(scene, cam, os.path.join(RENDER_DIR, f"turnaround-{prefix}-{view}.png"), 1400, 1400)
        if use_codex_shells:
            for shell in codex_shells.values():
                shell.hide_render = True
            for obj in bpy.data.objects:
                if obj.name.startswith(f"{prefix}_") and obj.type == "MESH" and not obj.name.startswith(f"{prefix}_codex_shell_"):
                    obj.hide_render = obj not in visible
        elif view in hide_for_view:
            for obj in bpy.data.objects:
                if obj.name in hide_for_view[view]:
                    obj.hide_render = obj in visible
    for track, mute in zip(tracks, prior_mutes):
        track.mute = mute
    for obj, hidden in prior_hidden.items():
        obj.hide_render = hidden


def add_canonical_rim_light(scene) -> bpy.types.Object:
    """Cool rim from behind-left for the matched concept render."""
    data = bpy.data.lights.new("sunwoven_canonical_rim", "SUN")
    light = bpy.data.objects.new("sunwoven_canonical_rim", data)
    scene.collection.objects.link(light)
    data.energy = 4.0
    data.color = (0.20, 0.36, 0.62)
    source = Vector((4.0, 4.0, 5.0)).normalized()
    light.rotation_euler = Vector((0.0, 0.0, -1.0)).rotation_difference(-source).to_euler()
    return light


def render_canonical_match(scene, arm_obj, prefix: str) -> None:
    """Render the matched loaded-walk pose at the canonical portrait aspect."""
    visible = {arm_obj, *[obj for obj in bpy.data.objects if obj.parent is arm_obj]}
    ground = bpy.data.objects.get(f"{prefix}_ground")
    original_ground_material = None
    render_ground_material = None
    original_ground_scale = ground.scale.copy() if ground is not None else None
    original_ground_location = ground.location.copy() if ground is not None else None
    if ground is not None:
        # The Foundation reference includes a small circular presentation pad.
        # Reuse the neutral authored pad for the render only; the citizen GLB
        # remains free of workstation geometry.
        ground.scale = (0.16, 0.16, 1.0)
        ground.location = (0.0, 0.0, -0.06)
        # The source cell uses a dark presentation plate, not the neutral lab
        # gray.  This render-only override keeps the pad visible while letting
        # the figure remain the dominant foreground component in the mask.
        if ground.data.materials:
            original_ground_material = ground.data.materials[0]
            render_ground_material = original_ground_material.copy()
            ground.data.materials[0] = render_ground_material
            render_ground_material.diffuse_color = (0.0008, 0.0012, 0.0030, 1.0)
            if render_ground_material.use_nodes:
                bsdf = next(
                    (node for node in render_ground_material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
                    None,
                )
                if bsdf is not None:
                    bsdf.inputs["Base Color"].default_value = (0.0008, 0.0012, 0.0030, 1.0)
                    bsdf.inputs["Roughness"].default_value = 0.96
        visible.add(ground)
    prior_hidden = {obj: obj.hide_render for obj in bpy.data.objects}
    tracks = list(arm_obj.animation_data.nla_tracks) if arm_obj.animation_data else []
    prior_mutes = [track.mute for track in tracks]
    prior_action = arm_obj.animation_data.action if arm_obj.animation_data else None
    canonical_lights = {}
    # Soften key light so mid tones do not bleach into the leather bucket.
    for name, energy in (
        ("key_sun", 9.5),
        ("fill_sun", 1.0),
        ("bounce_sun", 1.6),
        ("sunwoven_canonical_rim", 2.6),
    ):
        light = bpy.data.objects.get(name)
        if light is not None and light.type == "LIGHT":
            canonical_lights[light] = light.data.energy
            light.data.energy = energy
    world_background = None
    if scene.world is not None and scene.world.use_nodes:
        world_background = scene.world.node_tree.nodes.get("Background")
    prior_world_strength = None
    if world_background is not None:
        prior_world_strength = world_background.inputs[1].default_value
        world_background.inputs[1].default_value = 0.65
    for obj in bpy.data.objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.hide_render = obj not in visible
    if ground is not None:
        ground.hide_render = False
    for track in tracks:
        track.mute = True
    arm_obj.animation_data.action = bpy.data.actions[CANONICAL_POSE_CLIP]
    scene.frame_set(CANONICAL_POSE_FRAME)
    # Capture the authored clip frame, then release the action before applying
    # the fixed presentation pose.  Otherwise the depsgraph re-evaluates the
    # action after each manual bone assignment and silently restores the
    # narrow neutral frame.
    arm_obj.animation_data.action = None
    # The loaded-walk clip parks both tool sockets by contract.  The canonical
    # Foundation cell is the weaver's authored hand-held presentation, so
    # override only the evaluated socket pose for this render.  This leaves
    # the 18 exported clips and their socket tracks unchanged.
    for socket in ("socket_tool_R", "socket_tool_L"):
        pb = arm_obj.pose.bones[socket]
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
    # The load/walk action parks these authored runtime props.  They are not
    # part of the Foundation reference cell and must not leak into its image.
    for obj in bpy.data.objects:
        if obj.type == "MESH" and (
            obj.name.startswith(f"{prefix}_cargo_")
            or obj.name.startswith(f"{prefix}_rest_")
            or obj.name == f"{prefix}_mallet"
        ):
            obj.hide_render = True
    # The production walk clip is deliberately subtle.  The Foundation cell
    # shows a loaded labor stride, so apply an authored canonical-presentation
    # pose after the clip frame is selected.  These presentation keys do not
    # alter the exported 18-clip inventory.
    for bone, euler in (
        ("spine_01", (14.0, 0.0, 0.0)),
        ("spine_02", (26.0, 0.0, 0.0)),
        ("chest", (16.0, -4.0, 0.0)),
        ("neck", (12.0, 0.0, 0.0)),
        ("head", (14.0, 0.0, 0.0)),
        ("accessory_strap", (10.0, 0.0, 0.0)),
        ("upperarm_L", (-38.0, 0.0, 32.0)),
        ("lowerarm_L", (-56.0, 0.0, 18.0)),
        ("upperarm_R", (-62.0, 12.0, -14.0)),
        ("lowerarm_R", (-78.0, 0.0, 24.0)),
        ("thigh_L", (-30.0, 0.0, 8.0)),
        ("calf_L", (-32.0, 0.0, 0.0)),
        ("foot_L", (74.0, 0.0, 0.0)),
        ("thigh_R", (40.0, 0.0, -8.0)),
        ("calf_R", (-14.0, 0.0, 0.0)),
        ("foot_R", (8.0, 0.0, 0.0)),
    ):
        pb = arm_obj.pose.bones[bone]
        pb.rotation_quaternion = rig.world_euler_to_pose_quat(arm_obj, bone, *euler)
    bpy.context.view_layer.update()
    if bpy.data.objects.get(f"{prefix}_mallet") is not None:
        bpy.data.objects[f"{prefix}_mallet"].hide_render = True
    # The source cell is a near-profile view.  The character faces -Y, so a
    # camera on -X keeps the leading sickle hand to screen-right and the rear
    # basket to screen-left.
    cam = setup_camera(True, (0.05, -0.05, 0.92), (-6.40, -4.55, 2.40))
    cam.data.ortho_scale = 2.08
    render_view(scene, cam, os.path.join(RENDER_DIR, "canonical-match-sunwoven.png"), 1400, 1400)
    if original_ground_material is not None:
        ground.data.materials[0] = original_ground_material
    if ground is not None:
        ground.scale = original_ground_scale
        ground.location = original_ground_location
    arm_obj.animation_data.action = prior_action
    for light, energy in canonical_lights.items():
        light.data.energy = energy
    if prior_world_strength is not None:
        world_background.inputs[1].default_value = prior_world_strength
    for track, muted in zip(tracks, prior_mutes):
        track.mute = muted
    for obj, hidden in prior_hidden.items():
        obj.hide_render = hidden


def main() -> None:
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
    add_canonical_rim_light(scene)

    arm, fm, mats, cargo, arc_prop, citizen_parts, codex_shells = build_citizen()
    props_set = lab_props.build_prop_set(0.0, prefix=PREFIX)
    specs, stand_worlds = author_sunwoven_clips(arm, fm)
    place_rest_posts(arm, specs, "socket_tool_R", "R", PREFIX)
    place_rest_posts(arm, specs, "socket_tool_L", "L", PREFIX)

    # Static lab renders must not show runtime-managed props.
    for obj in [arc_prop, *cargo]:
        obj.hide_render = True

    blend_path = os.path.join(ASSETS, "sunwoven_lab.blend")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"[build_sunwoven] saved {blend_path}")

    lab_path = os.path.join(RUNTIME_ASSETS, "sunwoven_lab.glb")
    export_glb(None, lab_path)
    print(f"[build_sunwoven] exported {lab_path}")

    citizen_path = os.path.join(RUNTIME_ASSETS, "citizen_sunwoven.glb")
    export_glb(citizen_parts, citizen_path)
    print(f"[build_sunwoven] exported {citizen_path}")

    # --- renders -----------------------------------------------------------
    lab_views = {
        "sunwoven-lab-front": (0.0, -4.5, 2.4),
        "sunwoven-lab-rear": (0.0, 4.5, 2.4),
        "sunwoven-lab-side": (4.5, 0.0, 2.4),
        "sunwoven-lab-threequarter": THREEQUARTER_POS,
        "sunwoven-lab-rts": RTS_POS,
    }
    for view, pos in lab_views.items():
        target = (
            RTS_TARGET if view == "sunwoven-lab-rts"
            else THREEQUARTER_TARGET if view == "sunwoven-lab-threequarter"
            else (2.5, 0.0, 0.9)
        )
        cam = setup_camera(False, target, pos)
        render_view(scene, cam, os.path.join(RENDER_DIR, f"{view}.png"))

    render_turnarounds(scene, arm, PREFIX, codex_shells)

    act = bpy.data.actions[LOCKED_POSE_CLIP]
    cam = setup_camera(False, (0.0, 0.0, 0.9), (0.0, -4.5, 2.1))
    arm.animation_data.action = act
    scene.frame_set(LOCKED_POSE_FRAME)
    render_view(scene, cam, os.path.join(RENDER_DIR, "locked-pose-sunwoven-source.png"))
    body = bpy.data.objects[f"{PREFIX}_body"]
    dump_locked_pose(arm, body, os.path.join(BUILD, "locked-pose-sunwoven-source.json"), LOCKED_POSE_FRAME, clips.FPS)
    arm.animation_data.action = None
    render_canonical_match(scene, arm, PREFIX)
    print("[build_sunwoven] rendered lab views, turnarounds, locked pose and canonical match")

    # --- manifests ----------------------------------------------------------
    manifest = assemble_manifest(specs)
    manifest_path = os.path.join(MANIFEST_DIR, "sunwoven-event-markers.json")
    with open(manifest_path, "w") as fh:
        json.dump(manifest, fh, indent=2)
    runtime_manifest = os.path.join(RUNTIME_ASSETS, "sunwoven-event-markers.json")
    with open(runtime_manifest, "w") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"[build_sunwoven] wrote {manifest_path}")

    report = {
        "generator": "Tools/citizens/build_sunwoven.py",
        "blender": bpy.app.version_string,
        "blender_build": bpy.app.build_hash.decode() if isinstance(bpy.app.build_hash, bytes) else str(bpy.app.build_hash),
        "python": sys.version.split()[0],
        "fps": clips.FPS,
        "skeleton": rig.describe(),
        "proportion_set": CITIZEN_KEY,
        "outputs": {
            "blend": blend_path,
            "lab_glb": lab_path,
            "lab_glb_sha256": sha256(lab_path),
            "citizen_glb": citizen_path,
            "citizen_glb_sha256": sha256(citizen_path),
            "manifest": manifest_path,
            "renders": RENDER_DIR,
            "canonical_match": os.path.join(RENDER_DIR, "canonical-match-sunwoven.png"),
        },
    }
    report_path = os.path.join(BUILD, "sunwoven-run-report.json")
    with open(report_path, "w") as fh:
        json.dump(report, fh, indent=2)
    print(json.dumps(report, indent=2))
    print(f"[build_sunwoven] wrote {report_path}")


if __name__ == "__main__":
    main()
