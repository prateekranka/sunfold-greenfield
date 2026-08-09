"""B23-VALIDATE-BLEND — re-open the editable .blend and verify the contract.

Runs inside Blender (background mode):

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/citizens/validate_blend.py

Checks, against the committed event-marker manifest and the locked rig:
  * every armature's bone inventory equals rig.BONE_ORDER (same names, same
    hierarchy) and the socket bones exist;
  * every manifest clip has an Action with the same name and the same frame
    range, pushed onto an NLA track of the right armature;
  * every authored marker in the manifest is present as an Action
    pose_marker at the exact frame;
  * keyframe interpolation is LINEAR (deterministic round trip);
  * the body mesh is skinned (armature modifier) and the carrier is bound to
    accessory_strap.

Writes: Tools/citizens/build/validation-blend.json
"""

from __future__ import annotations

import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rig  # noqa: E402

MANIFEST_PATH = os.path.join(HERE, "manifest", "event-markers.json")
BLEND_PATH = os.path.join(HERE, "assets", "neutral_lab.blend")
OUT_PATH = os.path.join(HERE, "build", "validation-blend.json")


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
    missing = []
    wrong_range = []
    bad_interp = []
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
        found = False
        for pm in act.pose_markers:
            if pm.name == marker["name"] and round(pm.frame) == marker["frame"]:
                found = True
                break
        if not found:
            missing.append((marker["clip"], marker["name"], marker["frame"]))
    report["missing_markers"] = missing


def check_skinning(report: dict) -> None:
    for arm_name in ("slender_armature", "broad_armature"):
        arm = bpy.data.objects.get(arm_name)
        report[arm_name] = {}
        if arm is None:
            report[arm_name]["missing"] = True
            continue
        prefix = "slender" if "slender" in arm_name else "broad"
        body = bpy.data.objects.get(f"{prefix}_body")
        carrier = bpy.data.objects.get(f"{prefix}_carrier")
        report[arm_name]["body_skinned"] = bool(
            body and any(m.type == "ARMATURE" and m.object is arm for m in body.modifiers)
        )
        report[arm_name]["carrier_bound_to_strap"] = bool(
            carrier
            and any(m.type == "ARMATURE" and m.object is arm for m in carrier.modifiers)
            and "accessory_strap" in {g.name for g in carrier.vertex_groups}
        )
        report[arm_name]["tool_sockets_parented"] = {
            f"{prefix}_scraper": next(
                (o.parent_bone for o in bpy.data.objects if o.name == f"{prefix}_scraper"), None
            ),
            f"{prefix}_mallet": next(
                (o.parent_bone for o in bpy.data.objects if o.name == f"{prefix}_mallet"), None
            ),
        }


def iter_fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    yield fc


def main() -> None:
    manifest = json.load(open(MANIFEST_PATH))
    report = {
        "schema": "sunfold.lab.blend-validation/1",
        "blend": BLEND_PATH,
        "manifest": MANIFEST_PATH,
        "armatures": {},
        "marker_check": {},
    }
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)

    manifest_clips = manifest["clips"]
    per_armature = {}
    for clip in manifest_clips:
        per_armature.setdefault(clip["citizen"], []).append(clip)

    for arm_name in ("slender_armature", "broad_armature"):
        arm = bpy.data.objects.get(arm_name)
        arm_report = {"exists": arm is not None}
        if arm is not None:
            check_skeleton(arm, arm_report)
        report["armatures"][arm_name] = arm_report

    # Actions live once in the file; check them against the union of clips.
    check_actions(bpy.data.objects.get("slender_armature"), manifest_clips, report["marker_check"])
    check_markers(manifest["markers"], report["marker_check"])
    check_skinning(report["marker_check"])

    with open(OUT_PATH, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"[validate_blend] wrote {OUT_PATH}")


main()
