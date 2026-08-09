"""B23-RIG — the ONE authored citizen skeleton.

This module is the single definition of the shared skeleton required by #20:
one bone hierarchy, one naming scheme, one joint convention. Faction
proportions are supplied as scalar parameter sets; they change bone lengths,
rest poses and skin weights but never the hierarchy or the names.

Imported by Blender scripts. Requires `bpy` / `mathutils`.

JOINT CONVENTION (authoring space = Blender, Z up)
--------------------------------------------------
* World +Z is up. The character FACES world -Y. Character LEFT is world +X,
  character RIGHT is world -X. `_L` bones therefore sit on +X, matching
  Blender's own mirror convention.
* Feet rest on the Z = 0 plane. Total authored height is `height` metres.
* Every bone's roll is 0. Bone local +Y always runs head -> tail.
* Exported with `export_yup=True`, so glTF/Three.js sees: X -> X, Z -> Y,
  -Y -> Z. In Three.js the character therefore faces +Z and its left is +X.

POSE AUTHORING CONVENTION
-------------------------
Poses are authored as rotations about WORLD axes in degrees (see
`world_euler_to_pose_quat`). This keeps the clip tables readable and makes
left/right mirroring exact. Sign meanings:
  * world X negative -> the limb swings FORWARD (toward -Y)
  * world Y positive -> roll toward the character's right
  * world Z positive -> yaw / twist toward the character's left
"""

from __future__ import annotations

import math

import bpy
from mathutils import Euler, Matrix, Vector


SKELETON_VERSION = "sunfold.citizen.skeleton/1"

# --------------------------------------------------------------------------
# Hierarchy. (name, parent, deform)
# The order is authoritative: parents always precede children.
# --------------------------------------------------------------------------
BONE_ORDER: list[tuple[str, str | None, bool]] = [
    ("root", None, False),
    ("hips", "root", True),
    ("spine_01", "hips", True),
    ("spine_02", "spine_01", True),
    ("chest", "spine_02", True),
    ("neck", "chest", True),
    ("head", "neck", True),
    ("clavicle_L", "chest", True),
    ("upperarm_L", "clavicle_L", True),
    ("lowerarm_L", "upperarm_L", True),
    ("hand_L", "lowerarm_L", True),
    ("socket_tool_L", "hand_L", False),
    ("clavicle_R", "chest", True),
    ("upperarm_R", "clavicle_R", True),
    ("lowerarm_R", "upperarm_R", True),
    ("hand_R", "lowerarm_R", True),
    ("socket_tool_R", "hand_R", False),
    ("socket_carrier", "chest", False),
    ("accessory_strap", "socket_carrier", True),
    ("thigh_L", "hips", True),
    ("calf_L", "thigh_L", True),
    ("foot_L", "calf_L", True),
    ("toe_L", "foot_L", True),
    ("thigh_R", "hips", True),
    ("calf_R", "thigh_R", True),
    ("foot_R", "calf_R", True),
    ("toe_R", "foot_R", True),
]

BONE_NAMES = [b[0] for b in BONE_ORDER]
BONE_PARENT = {b[0]: b[1] for b in BONE_ORDER}

# Sockets demanded by #20: right hand tool, left hand tool, upper-back carrier.
SOCKETS = ("socket_tool_R", "socket_tool_L", "socket_carrier")

ROOT_BONE = "root"
ACCESSORY_BONE = "accessory_strap"

# --------------------------------------------------------------------------
# Faction-adaptable proportion sets. Same names, same hierarchy, different
# lengths / rest pose / skin thickness. NOT production Sunwoven or Gravemark
# citizens - these are the two spike proportion probes required by #23.
# --------------------------------------------------------------------------
PROPORTIONS: dict[str, dict[str, float]] = {
    "spike_slender": {
        "height": 1.80,
        "leg_fraction": 0.545,      # hip joint height / height
        "shoulder_y_frac": 0.815,
        "neck_top_frac": 0.885,
        "shoulder_half": 0.190,
        "hip_half": 0.098,
        "arm_scale": 1.04,
        "arm_splay_deg": 7.0,       # rest-pose adaptation, not a hierarchy change
        "stance_deg": 2.0,
        "limb_r": 0.049,
        "torso_half_w": 0.150,
        "torso_half_d": 0.098,
        "pelvis_half_w": 0.132,
        "head_half": 0.088,
        "foot_len": 0.230,
        "strap_len_frac": 0.115,
    },
    "spike_broad": {
        "height": 1.80,
        "leg_fraction": 0.498,
        "shoulder_y_frac": 0.805,
        "neck_top_frac": 0.880,
        "shoulder_half": 0.252,
        "hip_half": 0.146,
        "arm_scale": 0.96,
        "arm_splay_deg": 12.0,
        "stance_deg": 5.0,
        "limb_r": 0.076,
        "torso_half_w": 0.212,
        "torso_half_d": 0.142,
        "pelvis_half_w": 0.190,
        "head_half": 0.118,
        "foot_len": 0.250,
        "strap_len_frac": 0.130,
    },
    # Issue #24 — PRODUCTION Foundation Sunwoven Weaver proportions.
    "sunwoven": {
        "height": 1.80,
        "leg_fraction": 0.520,
        "shoulder_y_frac": 0.812,
        "neck_top_frac": 0.888,
        "shoulder_half": 0.205,
        "hip_half": 0.105,
        "arm_scale": 0.99,
        "arm_splay_deg": 6.0,
        "stance_deg": 2.0,
        "limb_r": 0.062,
        "torso_half_w": 0.155,
        "torso_half_d": 0.110,
        "pelvis_half_w": 0.135,
        "head_half": 0.098,
        "foot_len": 0.232,
        "strap_len_frac": 0.145,
    },
}

# Presentation numbers recorded for the manifest; NOT baked into the mesh.
AUTHORED_HEIGHT_M = 1.80
PRESENTATION_SCALE = 1.25
CIV_CORE_FOOTPRINT_RADIUS_M = 5.5


def compute_joints(p: dict[str, float]) -> dict[str, tuple[Vector, Vector, float]]:
    """Return {bone: (head, tail, roll)} in Blender world space for a set."""
    h = p["height"]
    hip_y = p["leg_fraction"] * h
    shoulder_y = p["shoulder_y_frac"] * h
    neck_top = p["neck_top_frac"] * h
    knee_y = hip_y * 0.515
    ankle_y = 0.048 * h
    toe_y = 0.022 * h
    torso_span = shoulder_y - hip_y

    pelvis_top = hip_y + 0.30 * torso_span
    spine_mid = hip_y + 0.62 * torso_span
    chest_base = hip_y + 0.84 * torso_span

    j: dict[str, tuple[Vector, Vector, float]] = {}

    def put(name: str, head, tail) -> None:
        j[name] = (Vector(head), Vector(tail), 0.0)

    # Root anchors the character at the ground origin and points forward (-Y).
    put("root", (0.0, 0.0, 0.0), (0.0, -0.20, 0.0))

    put("hips", (0.0, 0.0, hip_y), (0.0, 0.0, pelvis_top))
    put("spine_01", (0.0, 0.0, pelvis_top), (0.0, 0.0, spine_mid))
    put("spine_02", (0.0, 0.0, spine_mid), (0.0, 0.0, chest_base))
    put("chest", (0.0, 0.0, chest_base), (0.0, 0.0, shoulder_y))
    put("neck", (0.0, 0.0, shoulder_y), (0.0, 0.0, neck_top))
    put("head", (0.0, 0.0, neck_top), (0.0, 0.0, h))

    splay = math.radians(p["arm_splay_deg"])
    ua_len = 0.188 * h * p["arm_scale"]
    la_len = 0.148 * h * p["arm_scale"]
    hand_len = 0.098 * h * p["arm_scale"]

    for side, sx in (("L", 1.0), ("R", -1.0)):
        cl_head = Vector((sx * 0.030 * h, 0.0, shoulder_y - 0.012 * h))
        cl_tail = Vector((sx * p["shoulder_half"], 0.0, shoulder_y - 0.028 * h))
        put(f"clavicle_{side}", cl_head, cl_tail)

        d_arm = Vector((sx * math.sin(splay), 0.0, -math.cos(splay)))
        ua_head = cl_tail.copy()
        ua_tail = ua_head + d_arm * ua_len
        put(f"upperarm_{side}", ua_head, ua_tail)

        d_fore = Vector((sx * math.sin(splay * 0.45), 0.0, -math.cos(splay * 0.45)))
        la_tail = ua_tail + d_fore * la_len
        put(f"lowerarm_{side}", ua_tail, la_tail)

        hand_tail = la_tail + d_fore * hand_len
        put(f"hand_{side}", la_tail, hand_tail)

        # Tool socket sits in the palm (mid hand) and points forward (-Y).
        grip = la_tail + d_fore * (hand_len * 0.55)
        put(f"socket_tool_{side}", grip, grip + Vector((0.0, -0.085, 0.0)))

        stance = math.radians(p["stance_deg"])
        th_head = Vector((sx * p["hip_half"], 0.0, hip_y))
        kn = Vector((sx * (p["hip_half"] - math.sin(stance) * 0.10), 0.0, knee_y))
        put(f"thigh_{side}", th_head, kn)
        ank = Vector((sx * (p["hip_half"] - math.sin(stance) * 0.16), 0.0, ankle_y))
        put(f"calf_{side}", kn, ank)
        ball = Vector((ank.x, -p["foot_len"] * 0.62, toe_y))
        put(f"foot_{side}", ank, ball)
        put(f"toe_{side}", ball, ball + Vector((0.0, -p["foot_len"] * 0.38, 0.0)))

    # Carrier socket on the UPPER BACK (+Y is behind the character).
    car_head = Vector((0.0, p["torso_half_d"] * 0.92, shoulder_y - 0.115 * h))
    put("socket_carrier", car_head, car_head + Vector((0.0, 0.0, 0.10 * h)))

    strap_head = car_head + Vector((0.0, 0.018 * h, 0.012 * h))
    put(
        "accessory_strap",
        strap_head,
        strap_head + Vector((0.0, 0.0, -p["strap_len_frac"] * h)),
    )
    return j


# --------------------------------------------------------------------------
# Skin segments: which box of the neutral mannequin follows which bone, and
# how thick that box is. Thickness comes from the proportion set, so the same
# code produces a slender and a broad silhouette.
# --------------------------------------------------------------------------
def segment_table(p: dict[str, float]) -> list[tuple[str, float, float, float]]:
    """(bone, half_width, half_depth, head_blend_to_parent)."""
    r = p["limb_r"]
    return [
        ("hips", p["pelvis_half_w"], p["torso_half_d"] * 0.95, 0.30),
        ("spine_01", p["torso_half_w"] * 0.94, p["torso_half_d"] * 0.96, 0.35),
        ("spine_02", p["torso_half_w"] * 0.99, p["torso_half_d"], 0.35),
        ("chest", p["torso_half_w"] * 0.90, p["torso_half_d"] * 0.92, 0.35),
        ("neck", r * 0.95, r * 0.95, 0.40),
        ("head", p["head_half"], p["head_half"] * 1.05, 0.25),
        ("clavicle_L", r * 1.05, r * 1.05, 0.30),
        ("upperarm_L", r, r, 0.35),
        ("lowerarm_L", r * 0.86, r * 0.86, 0.35),
        ("hand_L", r * 0.80, r * 0.52, 0.30),
        ("clavicle_R", r * 1.05, r * 1.05, 0.30),
        ("upperarm_R", r, r, 0.35),
        ("lowerarm_R", r * 0.86, r * 0.86, 0.35),
        ("hand_R", r * 0.80, r * 0.52, 0.30),
        ("thigh_L", r * 1.28, r * 1.28, 0.35),
        ("calf_L", r * 1.06, r * 1.06, 0.35),
        ("foot_L", r * 1.00, r * 0.62, 0.30),
        ("toe_L", r * 0.94, r * 0.44, 0.30),
        ("thigh_R", r * 1.28, r * 1.28, 0.35),
        ("calf_R", r * 1.06, r * 1.06, 0.35),
        ("foot_R", r * 1.00, r * 0.62, 0.30),
        ("toe_R", r * 0.94, r * 0.44, 0.30),
        ("accessory_strap", r * 0.62, r * 0.46, 0.35),
    ]


# --------------------------------------------------------------------------
# Blender construction
# --------------------------------------------------------------------------
def build_armature(obj_name: str, p: dict[str, float]):
    joints = compute_joints(p)
    arm_data = bpy.data.armatures.new(obj_name + "_data")
    arm_obj = bpy.data.objects.new(obj_name, arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)

    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, deform in BONE_ORDER:
        head, tail, roll = joints[name]
        eb = arm_data.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.roll = roll
        eb.use_deform = deform
    for name, parent, _deform in BONE_ORDER:
        if parent is not None:
            arm_data.edit_bones[name].parent = arm_data.edit_bones[parent]
            arm_data.edit_bones[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")

    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm_obj


def bone_rest_basis(arm_obj, bone_name: str) -> Matrix:
    """3x3 rest orientation of a bone in armature space."""
    return arm_obj.data.bones[bone_name].matrix_local.to_3x3()


def world_euler_to_pose_quat(arm_obj, bone_name: str, wx: float, wy: float, wz: float):
    """Convert a world-axis XYZ euler (degrees) into that bone's local quat."""
    if wx == 0.0 and wy == 0.0 and wz == 0.0:
        from mathutils import Quaternion

        return Quaternion((1.0, 0.0, 0.0, 0.0))
    r_world = Euler(
        (math.radians(wx), math.radians(wy), math.radians(wz)), "XYZ"
    ).to_matrix()
    m = bone_rest_basis(arm_obj, bone_name)
    return (m.inverted() @ r_world @ m).to_quaternion()


def mirror_pose(pose: dict) -> dict:
    """Exact left/right mirror across the YZ plane.

    Conjugating an XYZ euler by diag(-1,1,1) gives (wx, -wy, -wz) term by
    term, so the mirror is exact rather than approximate.
    """
    out: dict = {}
    for key, val in pose.items():
        if key == "@hips_loc":
            out[key] = (-val[0], val[1], val[2])
            continue
        if key == "@root_loc":
            out[key] = (-val[0], val[1], val[2])
            continue
        if key.endswith("_L"):
            nk = key[:-2] + "_R"
        elif key.endswith("_R"):
            nk = key[:-2] + "_L"
        else:
            nk = key
        out[nk] = (val[0], -val[1], -val[2])
    return out


def describe() -> dict:
    """Machine-readable description of the locked rig contract."""
    return {
        "skeleton_version": SKELETON_VERSION,
        "bone_count": len(BONE_ORDER),
        "bones": [
            {"name": n, "parent": p, "deform": d} for n, p, d in BONE_ORDER
        ],
        "sockets": list(SOCKETS),
        "root_bone": ROOT_BONE,
        "accessory_bone": ACCESSORY_BONE,
        "authoring_up_axis": "Z (Blender)",
        "runtime_up_axis": "Y (glTF/Three.js, export_yup=True)",
        "authoring_forward": "-Y (Blender) -> +Z (glTF)",
        "left_side_axis": "+X in both spaces",
        "bone_roll": "0 for every bone; bone local +Y runs head->tail",
        "authored_height_m": AUTHORED_HEIGHT_M,
        "presentation_scale": PRESENTATION_SCALE,
        "civ_core_footprint_radius_m": CIV_CORE_FOOTPRINT_RADIUS_M,
        "proportion_sets": {k: dict(v) for k, v in PROPORTIONS.items()},
    }
