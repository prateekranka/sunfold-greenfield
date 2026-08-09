"""Bake AoE2-style sprite sheets from the rigged Sunwoven citizen GLB source.

Runs inside Blender (background):

    blender --background --python Tools/citizens/bake_sprites.py -- \\
        --blend Tools/citizens/assets/sunwoven_lab.blend \\
        --out ThreeRuntime/assets/citizens/sprites/sunwoven-weaver

Uses the same locked RTS rig as ThreeRuntime/src/rts-camera.js:
pitch 57°, yaw 45° (FOV 38° defines the game camera, not the capture).

Capture is ORTHOGRAPHIC (the AoE2-sprite standard — no near-field
perspective skew) in two passes:

  1. measure: render all frames at a generous ortho scale, union the
     alpha bboxes per (clip, facing);
  2. frame: one clip-wide ortho scale so the tallest union fills
     FILL_TARGET of the canvas, every facing centered horizontally and
     all feet anchored to one canvas line (FEET_MARGIN).

Per-facing framing is required: the rig's armature origin is not at the
character's center, so set_facing() orbits the figure and each facing
lands at a different frame position unless corrected.

For each of 8 facings (unit rotated 0..315° about +Z) and each clip
(idle, walk, gather, …) renders ortho frames to PNG.

This stub renders idle frame 0 for all 8 facings when invoked with
--step bake-idle. Full walk/gather cycles are TODO once clip timing is
wired; bootstrap-sunwoven-sprites.py fills gaps from Codex refs until then.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# Locked RTS rig — keep in sync with rts-camera.js / tuning.js
PITCH_DEG = 57.0
YAW_DEG = 45.0
FOV_DEG = 38.0
# Camera position magnitude along the aim (sets pitch/yaw only — ortho
# capture framing is set by ORTHO_SCALE and the measured per-facing aims).
DISTANCE = 3.85
# Pass-1 measure scale and pass-2 framing.
ORTHO_SCALE = 4.0
PROBE_SIZE = 256
FILL_TARGET = 0.85  # matches measured Codex idle fill (0.80–0.89)
FEET_MARGIN = 0.06
TARGET = Vector((0.0, 0.9, 0.0))
FRAME_SIZE = 1024  # native HD bake — do not upscale tiny sources in previews
FACINGS = 8
EEVEE_SAMPLES = 128

PITCH = math.radians(PITCH_DEG)
YAW = math.radians(YAW_DEG)


def rts_camera_position(distance: float = DISTANCE) -> Vector:
    horiz = distance * math.cos(PITCH)
    y = distance * math.sin(PITCH)
    x = horiz * math.sin(YAW)
    z = horiz * math.cos(YAW)
    return TARGET + Vector((x, y, z))


def setup_camera() -> bpy.types.Object:
    cam_data = bpy.data.cameras.new("sprite_bake_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ORTHO_SCALE
    cam = bpy.data.objects.new("sprite_bake_cam", cam_data)
    bpy.context.collection.objects.link(cam)
    pos = rts_camera_position()
    cam.location = pos
    direction = TARGET - pos
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def find_armature() -> bpy.types.Object | None:
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE" and "sunwoven" in obj.name.lower():
            return obj
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def set_facing(armature: bpy.types.Object, facing_index: int) -> None:
    armature.rotation_euler[2] = math.radians(facing_index * (360.0 / FACINGS))


def hide_set_dressing() -> None:
    """Hide lab set dressing — citizen rig + tools only (transparent sprite plate)."""
    hide_names = {
        "sunwoven_ground",
        "sunwoven_rest_L_mallet",
        "sunwoven_rest_R_scraper",
        "sunwoven_source_pile_0",
        "sunwoven_source_pile_1",
        "sunwoven_source_pile_2",
        "sunwoven_deposit_target_pad",
        "sunwoven_deposit_target_ring",
        "sunwoven_construct_frame",
        "sunwoven_construct_frame_post",
    }
    for obj in bpy.data.objects:
        if obj.name in hide_names or obj.name.startswith("sunwoven_source_pile_"):
            obj.hide_render = True
        if obj.name.startswith("sunwoven_deposit_") or obj.name.startswith("sunwoven_work_"):
            obj.hide_render = True


def hide_codex_shells() -> None:
    """IoU silhouette shells are for turnaround QA — never sprite bakes."""
    for obj in bpy.data.objects:
        if "_codex_shell_" in obj.name or obj.name.endswith("_codex_envelope"):
            obj.hide_render = True


def setup_render(size: int = FRAME_SIZE) -> None:
    """EEVEE HD plate: transparent film, high samples, sRGB PNG."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = EEVEE_SAMPLES


WALK_CLIP = "sunwoven_walk_inplace"
WALK_FRAMES = [0, 9, 18, 27]  # contact / passing @ 30 fps → 4 poses / 10 fps playback

GATHER_CLIP = "sunwoven_gather_loop_R"
# AoE2 hunt/gather ref: wind-up → chop contact → recovery (~1.2 s @ 5 fps)
GATHER_FRAMES = [0, 4, 8, 12, 20, 28]

BUILD_CLIP = "sunwoven_construct_loop_L"
# AoE2 build ref: hammer wind-up → strike → settle → raise
BUILD_FRAMES = [0, 6, 12, 14, 18, 24]


def apply_clip_frame(clip_name: str, frame: int) -> None:
    action = bpy.data.actions.get(clip_name)
    if not action:
        return
    for obj in bpy.data.objects:
        if obj.animation_data is None:
            obj.animation_data_create()
        obj.animation_data.action = action
    bpy.context.scene.frame_set(frame)


def render_facing(out_dir: str, clip: str, facing: int, frame: int = 0) -> str:
    clip_dir = os.path.join(out_dir, clip)
    os.makedirs(clip_dir, exist_ok=True)
    path = os.path.join(clip_dir, f"{facing}.png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def render_clip_frame(out_dir: str, clip: str, facing: int, frame_index: int) -> str:
    clip_dir = os.path.join(out_dir, clip, str(facing))
    os.makedirs(clip_dir, exist_ok=True)
    path = os.path.join(clip_dir, f"{frame_index}.png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def _load_manifest(out_dir: str) -> dict:
    path = os.path.join(out_dir, "manifest.json")
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    return {}


def _save_manifest(out_dir: str, manifest: dict) -> None:
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")


def measure_render_bbox(filepath: str) -> tuple | None:
    """Alpha bbox (x0, y0, x1, y1) of a rendered PNG, bottom-up pixel space."""
    if not os.path.isfile(filepath):
        return None
    img = bpy.data.images.load(filepath)
    try:
        w, h = img.size
        px = np.array(img.pixels, dtype=np.float32).reshape(h, w, 4)
        ys, xs = np.where(px[:, :, 3] > 8 / 255)
        if len(ys) == 0:
            return None
        return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    finally:
        bpy.data.images.remove(img)


def merge_bbox(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def view_axes(cam) -> tuple[Vector, Vector]:
    """Camera local +X/+Y in world, derived from the Euler (XYZ = Rz·Ry·Rx)."""
    p, y = cam.rotation_euler.x, cam.rotation_euler.z
    cp, sp = math.cos(p), math.sin(p)
    cy, sy = math.cos(y), math.sin(y)
    return Vector((cy, sy, 0.0)), Vector((-sy * cp, cy * cp, sp))


def measure_clip_facing_unions(
    cam: bpy.types.Object,
    arm: bpy.types.Object,
    action: str,
    frames: list[int],
    size: int = PROBE_SIZE,
) -> tuple[dict, int]:
    """Pass 1: render all frames at the probe size, union the bbox per facing.

    Render Result is not populated in background mode, so probes are rendered
    to unique temp files and measured from disk.
    """
    bpy.context.scene.render.resolution_x = size
    bpy.context.scene.render.resolution_y = size
    unions: dict = {}
    max_h_px = 0
    for facing in range(FACINGS):
        set_facing(arm, facing)
        bb = None
        for source_frame in frames:
            apply_clip_frame(action, source_frame)
            probe = os.path.join(
                tempfile.gettempdir(),
                f"sunfold_probe_{action}_{facing}_{source_frame}.png",
            )
            bpy.context.scene.render.filepath = probe
            bpy.ops.render.render(write_still=True)
            bb = merge_bbox(bb, measure_render_bbox(probe))
            os.remove(probe)
        if bb:
            unions[facing] = bb
            max_h_px = max(max_h_px, bb[3] - bb[1] + 1)
    return unions, max_h_px


def facing_aim_offset(
    cam: bpy.types.Object,
    bb: tuple,
    wpp: float,
    size: int,
    ortho_scale: float,
) -> Vector:
    """View-center shift that centers a facing's union bbox horizontally and
    pins its feet to the FEET_MARGIN canvas line. bb is in bottom-up pixels."""
    right, up = view_axes(cam)
    cx = (bb[0] + bb[2]) / 2
    bottom_px = bb[1]
    feet_world = cam.location + right * (cx - size / 2) * wpp + up * (bottom_px - size / 2) * wpp
    return feet_world - cam.location - up * (FEET_MARGIN - 0.5) * ortho_scale


def bake_idle(args: argparse.Namespace) -> None:
    if args.blend and os.path.isfile(args.blend):
        bpy.ops.wm.open_mainfile(filepath=args.blend)
    setup_render(args.size)
    cam = setup_camera()
    hide_set_dressing()
    hide_codex_shells()
    arm = find_armature()
    if not arm:
        print("[bake_sprites] no armature found", file=sys.stderr)
        sys.exit(1)
    unions, max_h_px = measure_clip_facing_unions(cam, arm, "sunwoven_idle", [0])
    wpp = ORTHO_SCALE / PROBE_SIZE
    ortho_scale = max_h_px * wpp / FILL_TARGET
    offsets = {
        facing: facing_aim_offset(cam, bb, wpp, PROBE_SIZE, ortho_scale)
        for facing, bb in unions.items()
    }
    cam.data.ortho_scale = ortho_scale
    base_loc = cam.location.copy()
    bpy.context.scene.render.resolution_x = args.size
    bpy.context.scene.render.resolution_y = args.size
    for facing in range(FACINGS):
        set_facing(arm, facing)
        cam.location = base_loc + offsets.get(facing, Vector((0.0, 0.0, 0.0)))
        out = render_facing(args.out, "idle", facing)
        print(f"[bake_sprites] {out}")
    spec = {
        "bakedBy": "Tools/citizens/bake_sprites.py",
        "camera": {
            "pitchDegrees": PITCH_DEG,
            "yawDegrees": YAW_DEG,
            "fovDegrees": FOV_DEG,
            "distance": DISTANCE,
            "orthoScale": round(ortho_scale, 4),
            "fillTarget": FILL_TARGET,
        },
        "facings": FACINGS,
        "clip": "idle",
        "frame": 0,
    }
    with open(os.path.join(args.out, "bake-report-idle.json"), "w", encoding="utf-8") as fh:
        json.dump(spec, fh, indent=2)
        fh.write("\n")


def _measure_clip(
    cam: bpy.types.Object,
    arm: bpy.types.Object,
    source_action: str,
    source_frames: list[int],
) -> tuple[float, dict]:
    if source_action not in bpy.data.actions:
        print(f"[bake_sprites] missing action {source_action}", file=sys.stderr)
        sys.exit(1)
    unions, max_h_px = measure_clip_facing_unions(cam, arm, source_action, source_frames)
    wpp = ORTHO_SCALE / PROBE_SIZE
    ortho_scale = max_h_px * wpp / FILL_TARGET
    offsets = {
        facing: facing_aim_offset(cam, bb, wpp, PROBE_SIZE, ortho_scale)
        for facing, bb in unions.items()
    }
    return ortho_scale, offsets


def _render_clip_frames(
    args: argparse.Namespace,
    *,
    cam: bpy.types.Object,
    arm: bpy.types.Object,
    clip_name: str,
    source_action: str,
    source_frames: list[int],
    fps: int,
    note: str,
    ortho_scale: float,
    offsets: dict,
) -> None:
    cam.data.ortho_scale = ortho_scale
    base_loc = cam.location.copy()
    bpy.context.scene.render.resolution_x = args.size
    bpy.context.scene.render.resolution_y = args.size
    for facing in range(FACINGS):
        set_facing(arm, facing)
        cam.location = base_loc + offsets.get(facing, Vector((0.0, 0.0, 0.0)))
        for frame_index, source_frame in enumerate(source_frames):
            apply_clip_frame(source_action, source_frame)
            out = render_clip_frame(args.out, clip_name, facing, frame_index)
            print(f"[bake_sprites] {out}")

    manifest = _load_manifest(args.out)
    manifest["frameWidth"] = args.size
    manifest["frameHeight"] = args.size
    manifest.setdefault("clips", {})
    manifest["clips"][clip_name] = {
        "frames": len(source_frames),
        "loop": True,
        "source": "real",
        "fps": fps,
        "note": note,
    }
    _save_manifest(args.out, manifest)

    spec = {
        "bakedBy": "Tools/citizens/bake_sprites.py",
        "camera": {
            "pitchDegrees": PITCH_DEG,
            "yawDegrees": YAW_DEG,
            "fovDegrees": FOV_DEG,
            "distance": DISTANCE,
            "orthoScale": round(ortho_scale, 4),
            "fillTarget": FILL_TARGET,
        },
        "facings": FACINGS,
        "clip": clip_name,
        "sourceAction": source_action,
        "frames": source_frames,
        "fps": fps,
    }
    report = os.path.join(args.out, f"bake-report-{clip_name}.json")
    with open(report, "w", encoding="utf-8") as fh:
        json.dump(spec, fh, indent=2)
        fh.write("\n")


def _bake_single_clip(
    args: argparse.Namespace,
    *,
    clip_name: str,
    source_action: str,
    source_frames: list[int],
    fps: int,
    note: str,
) -> None:
    if args.blend and os.path.isfile(args.blend):
        bpy.ops.wm.open_mainfile(filepath=args.blend)
    setup_render(args.size)
    cam = setup_camera()
    hide_set_dressing()
    hide_codex_shells()
    arm = find_armature()
    if not arm:
        print("[bake_sprites] no armature found", file=sys.stderr)
        sys.exit(1)
    ortho_scale, offsets = _measure_clip(cam, arm, source_action, source_frames)
    _render_clip_frames(
        args,
        cam=cam,
        arm=arm,
        clip_name=clip_name,
        source_action=source_action,
        source_frames=source_frames,
        fps=fps,
        note=note,
        ortho_scale=ortho_scale,
        offsets=offsets,
    )


def bake_walk(args: argparse.Namespace) -> None:
    _bake_single_clip(
        args,
        clip_name="walk",
        source_action=WALK_CLIP,
        source_frames=WALK_FRAMES,
        fps=10,
        note="Baked from sunwoven_walk_inplace @ frames 0/9/18/27 (AoE2 walk cadence)",
    )


def bake_gather(args: argparse.Namespace) -> None:
    _bake_single_clip(
        args,
        clip_name="gather",
        source_action=GATHER_CLIP,
        source_frames=GATHER_FRAMES,
        fps=5,
        note="Baked from sunwoven_gather_loop_R — chop contact @ 12 (AoE2 hunt/gather ref)",
    )


def bake_build(args: argparse.Namespace) -> None:
    _bake_single_clip(
        args,
        clip_name="build",
        source_action=BUILD_CLIP,
        source_frames=BUILD_FRAMES,
        fps=5,
        note="Baked from sunwoven_construct_loop_L — hammer strike @ 12 (AoE2 build ref)",
    )


def bake_all_clips(args: argparse.Namespace) -> None:
    """Bake walk/gather/build with ONE shared ortho scale so the unit keeps a
    consistent size across clips (feet anchored to the same canvas line)."""
    if args.blend and os.path.isfile(args.blend):
        bpy.ops.wm.open_mainfile(filepath=args.blend)
    setup_render(args.size)
    cam = setup_camera()
    hide_set_dressing()
    hide_codex_shells()
    arm = find_armature()
    if not arm:
        print("[bake_sprites] no armature found", file=sys.stderr)
        sys.exit(1)
    clips = [
        ("walk", WALK_CLIP, WALK_FRAMES, 10, "Baked from sunwoven_walk_inplace @ frames 0/9/18/27 (AoE2 walk cadence)"),
        ("gather", GATHER_CLIP, GATHER_FRAMES, 5, "Baked from sunwoven_gather_loop_R — chop contact @ 12 (AoE2 hunt/gather ref)"),
        ("build", BUILD_CLIP, BUILD_FRAMES, 5, "Baked from sunwoven_construct_loop_L — hammer strike @ 12 (AoE2 build ref)"),
    ]
    wpp = ORTHO_SCALE / PROBE_SIZE
    max_h_px = 0
    unions_by_clip: dict = {}
    for clip_name, source_action, source_frames, _fps, _note in clips:
        if source_action not in bpy.data.actions:
            print(f"[bake_sprites] missing action {source_action}", file=sys.stderr)
            sys.exit(1)
        unions, max_h = measure_clip_facing_unions(cam, arm, source_action, source_frames)
        unions_by_clip[clip_name] = unions
        max_h_px = max(max_h_px, max_h)
    ortho_scale = max_h_px * wpp / FILL_TARGET
    base_loc = cam.location.copy()
    for clip_name, source_action, source_frames, fps, note in clips:
        cam.location = base_loc
        offsets = {
            facing: facing_aim_offset(cam, bb, wpp, PROBE_SIZE, ortho_scale)
            for facing, bb in unions_by_clip[clip_name].items()
        }
        _render_clip_frames(
            args,
            cam=cam,
            arm=arm,
            clip_name=clip_name,
            source_action=source_action,
            source_frames=source_frames,
            fps=fps,
            note=note,
            ortho_scale=ortho_scale,
            offsets=offsets,
        )


def main() -> None:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", default=os.path.join(HERE, "assets", "sunwoven_lab.blend"))
    parser.add_argument("--out", default=os.path.join(REPO, "ThreeRuntime", "assets", "citizens", "sprites", "sunwoven-weaver"))
    parser.add_argument(
        "--size",
        type=int,
        default=FRAME_SIZE,
        help="Square render resolution per frame (default 1024)",
    )
    parser.add_argument(
        "--step",
        default="bake-idle",
        choices=["bake-idle", "bake-walk", "bake-gather", "bake-build", "bake-all-clips"],
    )
    args = parser.parse_args(argv)
    if args.step == "bake-idle":
        bake_idle(args)
    elif args.step == "bake-walk":
        bake_walk(args)
    elif args.step == "bake-gather":
        bake_gather(args)
    elif args.step == "bake-build":
        bake_build(args)
    elif args.step == "bake-all-clips":
        bake_all_clips(args)


if __name__ == "__main__":
    main()
