"""B23-RIG preflight probe (Blender side).

Runs inside Blender and records EXACT tool versions plus empirically probed
capabilities. Nothing here is written from memory; every value is read back
from the running process or from a throwaway export.

Canonical command:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/citizens/preflight.py

Writes: Tools/citizens/build/preflight_blender.json
"""

from __future__ import annotations

import json
import os
import shlex
import struct
import sys
import tempfile

import bpy


HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")


def print_command_line() -> None:
    print("[preflight.py] argv: " + " ".join(shlex.quote(a) for a in sys.argv))
    print(
        "[preflight.py] canonical: "
        "/Applications/Blender.app/Contents/MacOS/Blender --background "
        "--python Tools/citizens/preflight.py"
    )


def gltf_addon_info() -> dict:
    info = {"module_found": False}
    try:
        import addon_utils  # type: ignore

        for mod in addon_utils.modules():
            name = getattr(mod, "__name__", "")
            if "gltf" in name.lower():
                bl_info = getattr(mod, "bl_info", None)
                if bl_info is None and hasattr(addon_utils, "module_bl_info"):
                    bl_info = addon_utils.module_bl_info(mod)
                info["module_found"] = True
                info["module_name"] = name
                info["bl_info_version"] = list((bl_info or {}).get("version", ()))
                info["bl_info_blender"] = list((bl_info or {}).get("blender", ()))
                info["bl_info_name"] = (bl_info or {}).get("name")
                info["file"] = getattr(mod, "__file__", None)
    except Exception as exc:  # pragma: no cover - diagnostic only
        info["error"] = repr(exc)

    # The exporter stamps its own version into asset.generator; that string is
    # the authoritative record, so grab it from a real export below.
    return info


def export_operator_options() -> list[str]:
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    return sorted(p.identifier for p in props if p.identifier != "rna_type")


def probe_action_slot_api() -> dict:
    """Blender 4.4+ introduced slotted Actions. Find out what this build needs."""
    out = {
        "Action_has_slots": hasattr(bpy.types.Action, "slots"),
        "AnimData_has_action_slot": hasattr(bpy.types.AnimData, "action_slot"),
    }
    arm_data = bpy.data.armatures.new("probe_arm")
    arm_obj = bpy.data.objects.new("probe_arm", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones.new("probe_bone")
    eb.head = (0.0, 0.0, 0.0)
    eb.tail = (0.0, 0.0, 1.0)
    bpy.ops.object.mode_set(mode="OBJECT")

    arm_obj.animation_data_create()
    act = bpy.data.actions.new("probe_action")
    arm_obj.animation_data.action = act
    pb = arm_obj.pose.bones["probe_bone"]
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    try:
        pb.keyframe_insert(data_path="rotation_quaternion", frame=0)
        out["keyframe_insert_ok"] = True
    except Exception as exc:
        out["keyframe_insert_ok"] = False
        out["keyframe_insert_error"] = repr(exc)

    fcurve_count = len(getattr(act, "fcurves", []))
    slot_fcurves = 0
    if out["Action_has_slots"]:
        out["slot_count_after_insert"] = len(act.slots)
        for layer in act.layers:
            for strip in layer.strips:
                for cbag in getattr(strip, "channelbags", []):
                    slot_fcurves += len(cbag.fcurves)
        out["slotted_fcurve_count"] = slot_fcurves
        if out["AnimData_has_action_slot"]:
            slot = arm_obj.animation_data.action_slot
            out["auto_assigned_slot"] = None if slot is None else slot.identifier
    out["legacy_action_fcurve_count"] = fcurve_count
    out["pose_markers_supported"] = hasattr(act, "pose_markers")

    # Clean up so the probe never contaminates a later build.
    arm_obj.animation_data_clear()
    bpy.data.objects.remove(arm_obj, do_unlink=True)
    bpy.data.armatures.remove(arm_data)
    bpy.data.actions.remove(act)
    return out


def probe_export_extras() -> dict:
    """Export a one-cube scene carrying custom props and read the JSON back."""
    out = {}
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    bpy.ops.mesh.primitive_cube_add(size=1.0)
    cube = bpy.context.active_object
    cube.name = "extras_probe"
    cube["sunfold_probe_string"] = "hello"
    cube["sunfold_probe_json"] = json.dumps({"a": [1, 2, 3]})
    bpy.context.scene["sunfold_scene_probe"] = "scene_level"

    tmp = os.path.join(tempfile.mkdtemp(prefix="b23_extras_"), "extras_probe.glb")
    bpy.ops.export_scene.gltf(
        filepath=tmp,
        export_format="GLB",
        export_extras=True,
        use_selection=False,
    )
    doc = read_glb_json(tmp)
    out["generator"] = doc.get("asset", {}).get("generator")
    out["asset_version"] = doc.get("asset", {}).get("version")
    node_extras = None
    for node in doc.get("nodes", []):
        if node.get("name") == "extras_probe":
            node_extras = node.get("extras")
    out["node_extras"] = node_extras
    out["node_extras_survived"] = bool(
        node_extras and node_extras.get("sunfold_probe_string") == "hello"
    )
    out["scene_extras"] = doc.get("scenes", [{}])[0].get("extras")
    out["scene_extras_survived"] = bool(
        out["scene_extras"] and out["scene_extras"].get("sunfold_scene_probe") == "scene_level"
    )
    out["animation_extras_channel_exists_in_spec"] = False  # glTF 2.0 has no marker channel
    out["probe_glb"] = tmp
    return out


def read_glb_json(path: str) -> dict:
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, _length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    offset = 12
    while offset < len(data):
        clen, ctype = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + clen]
        offset += clen
        if ctype == 0x4E4F534A:  # JSON
            return json.loads(chunk.decode("utf-8"))
    raise RuntimeError("no JSON chunk")


def main() -> None:
    print_command_line()
    os.makedirs(BUILD, exist_ok=True)

    report = {
        "blender": {
            "version_string": bpy.app.version_string,
            "version_tuple": list(bpy.app.version),
            "build_hash": bpy.app.build_hash.decode()
            if isinstance(bpy.app.build_hash, bytes)
            else str(bpy.app.build_hash),
            "build_date": bpy.app.build_date.decode()
            if isinstance(bpy.app.build_date, bytes)
            else str(bpy.app.build_date),
            "build_commit_date": str(bpy.app.build_commit_date),
            "build_branch": str(bpy.app.build_branch),
            "build_platform": str(bpy.app.build_platform),
            "binary_path": bpy.app.binary_path,
            "python_version": sys.version,
        },
        "gltf_addon": gltf_addon_info(),
        "export_operator_options": export_operator_options(),
        "action_slot_api": probe_action_slot_api(),
        "render_engines": sorted(
            item.identifier
            for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
        ),
    }
    report["extras_probe"] = probe_export_extras()

    out_path = os.path.join(BUILD, "preflight_blender.json")
    with open(out_path, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"[preflight.py] wrote {out_path}")


main()
