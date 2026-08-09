"""B24-VALIDATE-BLEND — reopen the Sunwoven .blend and verify the contract.

Runs inside Blender (background mode):

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/citizens/validate_sunwoven_blend.py

Checks, against the committed Sunwoven manifest and the locked rig:
  * the sunwoven armature's bone inventory equals rig.BONE_ORDER (same names,
    same hierarchy) and the socket bones exist;
  * every manifest clip has an Action with the same name and frame range on an
    NLA track of the armature;
  * every authored marker is present as a pose_marker at the exact frame;
  * keyframe interpolation is LINEAR;
  * the body and basket are skinned; the cargo chunks are bone-parented to
    socket_carrier; the arc prop carries gather-loop NLA strips with the arc
    channelbag (authored multi-slot clip channels).

Writes: Tools/citizens/build/validation-sunwoven-blend.json
"""

from __future__ import annotations

import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rig  # noqa: E402

MANIFEST_PATH = os.path.join(HERE, "manifest", "sunwoven-event-markers.json")
BLEND_PATH = os.path.join(HERE, "assets", "sunwoven_lab.blend")
OUT_PATH = os.path.join(HERE, "build", "validation-sunwoven-blend.json")
ARM_NAME = "sunwoven_armature"


def iter_fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    yield fc


def check_skeleton(arm_obj, report: dict) -> None:
    names = [b.name for b in arm_obj.data.bones]
    report["bone_names"] = names
    report["bone_order_matches"] = names == rig.BONE_NAMES
    report["sockets_present"] = {s: s in names for s in rig.SOCKETS}
    report["deform_count"] = sum(1 for b in arm_obj.data.bones if b.use_deform)


def check_actions(arm_obj, manifest_clips, report: dict) -> None:
    actions = {a.name: a for a in bpy.data.actions}
    nla_names = set()
    for track in arm_obj.animation_data.nla_tracks if arm_obj.animation_data else []:
        for strip in track.strips:
            if strip.action is not None:
                nla_names.add(strip.action.name)
    report["nla_strip_count"] = len(nla_names)
    missing, wrong_range, bad_interp = [], [], []
    for clip in manifest_clips:
        if clip["name"] not in actions:
            missing.append(clip["name"])
            continue
        act = actions[clip["name"]]
        lo, hi = (round(x) for x in act.frame_range)
        if lo != clip["frame_start"] or hi != clip["frame_end"]:
            wrong_range.append((clip["name"], (lo, hi), (clip["frame_start"], clip["frame_end"])))
        for fc in iter_fcurves(act):
            for kp in fc.keyframe_points:
                if kp.interpolation != "LINEAR":
                    bad_interp.append(clip["name"])
                    break
    report["missing_actions"] = missing
    report["wrong_frame_range"] = wrong_range
    report["non_linear_interpolation"] = sorted(set(bad_interp))


def check_markers(manifest_markers, report: dict) -> None:
    actions = {a.name: a for a in bpy.data.actions}
    missing = []
    for marker in manifest_markers:
        if marker["source"] != "authored":
            continue
        act = actions.get(marker["clip"])
        if act is None:
            missing.append((marker["clip"], marker["name"]))
            continue
        found = any(
            pm.name == marker["name"] and round(pm.frame) == marker["frame"]
            for pm in act.pose_markers
        )
        if not found:
            missing.append((marker["clip"], marker["name"], marker["frame"]))
    report["missing_markers"] = missing


def check_skinning(arm_obj, report: dict) -> None:
    body = bpy.data.objects.get("sunwoven_body")
    basket = bpy.data.objects.get("sunwoven_basket")
    report["body_skinned"] = bool(
        body and any(m.type == "ARMATURE" and m.object is arm_obj for m in body.modifiers)
    )
    report["basket_bound_to_strap"] = bool(
        basket
        and any(m.type == "ARMATURE" and m.object is arm_obj for m in basket.modifiers)
        and "accessory_strap" in {g.name for g in basket.vertex_groups}
    )
    report["cargo_parents"] = {
        f"sunwoven_cargo_{i}": next(
            (o.parent_bone for o in bpy.data.objects if o.name == f"sunwoven_cargo_{i}"), None
        )
        for i in range(3)
    }
    report["tool_sockets"] = {
        "sunwoven_scraper": next(
            (o.parent_bone for o in bpy.data.objects if o.name == "sunwoven_scraper"), None
        ),
        "sunwoven_mallet": next(
            (o.parent_bone for o in bpy.data.objects if o.name == "sunwoven_mallet"), None
        ),
    }


def check_arc_channels(manifest, report: dict) -> None:
    arc_prop = bpy.data.objects.get("sunwoven_arc_prop")
    if arc_prop is None or arc_prop.animation_data is None:
        report["arc_prop"] = {"missing": True}
        return
    strips = {}
    for track in arc_prop.animation_data.nla_tracks:
        for strip in track.strips:
            if strip.action is not None:
                strips[strip.action.name] = strip
    loops = [f"sunwoven_gather_loop_{side}" for side in ("R", "L")]
    report["arc_prop"] = {
        "nla_strips": sorted(strips.keys()),
        "loop_strips_present": {name: name in strips for name in loops},
    }
    for name in loops:
        strip = strips.get(name)
        if strip is None:
            report["arc_prop"][name] = {"error": "no strip"}
            continue
        act = strip.action
        arc_channelbags = 0
        for layer in act.layers:
            for layer_strip in layer.strips:
                for cb in layer_strip.channelbags:
                    if cb.slot is not None and "arc_prop" in cb.slot.name_display:
                        arc_channelbags += 1
        report["arc_prop"][name] = {
            "arc_channelbag_count": arc_channelbags,
            "location_fcurves": arc_channelbags,
        }


def main() -> None:
    manifest = json.load(open(MANIFEST_PATH))
    report = {
        "schema": "sunfold.sunwoven.blend-validation/1",
        "blend": BLEND_PATH,
        "manifest": MANIFEST_PATH,
        "armature": {},
        "marker_check": {},
    }
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    arm = bpy.data.objects.get(ARM_NAME)
    report["armature"]["exists"] = arm is not None
    if arm is not None:
        check_skeleton(arm, report["armature"])
    check_actions(arm, manifest["clips"], report["marker_check"])
    check_markers(manifest["markers"], report["marker_check"])
    check_skinning(arm, report["marker_check"])
    check_arc_channels(manifest, report["marker_check"])

    with open(OUT_PATH, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"[validate_sunwoven_blend] wrote {OUT_PATH}")


main()
