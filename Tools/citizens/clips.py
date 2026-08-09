"""B23-CLIPS — named clip authoring for the spike citizens.

Clip content lives here as DATA (pose keyframes + markers + metadata), so the
same tables drive both the .blend Actions and the committed marker manifest.
Poses are authored as world-axis XYZ eulers in degrees (see rig.py's pose
convention), plus `@hips_loc` / `@root_loc` translation keys.

One authored skeleton (rig.py) produces two proportion sets (spike_slender /
spike_broad). Every clip below is authored ONCE per citizen with that
citizen's faction motion parameters — same timing, different amplitude /
depth / recovery, exactly as #20 requires.

Authoring rules enforced here:

* Every clip keys an explicit constant (0,0,0) root-location track so
  root-motion inspection has a track to inspect and can prove in-place.
* Keyframe interpolation is LINEAR everywhere (deterministic, and glTF
  round-trips linear tracks losslessly).
* Markers are frame-anchored `pose_markers` on the Action; the manifest is
  generated from the same tables.
* `payload_attach` is DERIVED (gather_contact + authored arc duration), not
  keyed, and is recorded as such in the manifest.

Tool handling is authored as object tracks inside the SAME Action: the tool
node sits at its rest (= the grip matrix at its attach frame) until the grip
closes, follows the hand's socket matrix through the work, and returns to
rest before `tool_release`. No runtime physics anywhere.
"""

from __future__ import annotations

import bpy
from mathutils import Matrix

import rig

FPS = 30

# --------------------------------------------------------------------------
# Faction motion: same timing, faction-adapted amplitude / depth / recovery.
# --------------------------------------------------------------------------
FACTION_MOTION: dict[str, dict] = {
    "spike_slender": {
        "carrier_kind": "basket",
        "idle_amp": 1.0,
        "walk_amp": 1.0,
        "walk_bob": 0.020,
        "walk_squat": -0.015,
        "gather_amp": 1.0,
        "construct_amp": 1.0,
        "deposit_kind": "basket",
        "loaded_squat": -0.020,
    },
    "spike_broad": {
        "carrier_kind": "hopper",
        "idle_amp": 0.6,
        "walk_amp": 0.85,
        "walk_bob": 0.014,
        "walk_squat": -0.030,
        "gather_amp": 0.85,
        "construct_amp": 0.90,
        "deposit_kind": "hopper",
        "loaded_squat": -0.035,
    },
    # Issue #24 — PRODUCTION Sunwoven motion: same shared timing and contacts,
    # lighter recovery and steadier balance per the #20 Sunwoven language.
    "sunwoven": {
        "carrier_kind": "basket",
        "idle_amp": 1.0,
        "walk_amp": 0.95,
        "walk_bob": 0.016,
        "walk_squat": -0.012,
        "gather_amp": 0.95,
        "construct_amp": 0.95,
        "deposit_kind": "basket",
        "loaded_squat": -0.016,
    },
}

# Derived-marker constants (authored, committed, deterministic).
ARC_DURATION_FRAMES = 12  # chunk flight from pile to carrier (0.4 s @ 30 fps)

# Marker event vocabulary locked by #20.
MARKER_EVENTS = (
    "tool_attach",
    "tool_release",
    "gather_contact",
    "payload_attach",
    "deposit_release",
    "construct_contact",
)

# --------------------------------------------------------------------------
# Pose helpers
# --------------------------------------------------------------------------
def base_stand(fm: dict) -> dict:
    """Symmetric neutral stand; all eulers are world-axis degrees."""
    return {
        "hips": (0, 0, 0),
        "spine_01": (0, 0, 0),
        "spine_02": (0, 0, 0),
        "chest": (0, 0, 0),
        "neck": (0, 0, 0),
        "head": (0, 0, 0),
        "clavicle_L": (0, 0, 0),
        "upperarm_L": (0, 0, 0),
        "lowerarm_L": (-20, 0, 0),
        "hand_L": (0, 0, 0),
        "clavicle_R": (0, 0, 0),
        "upperarm_R": (0, 0, 0),
        "lowerarm_R": (-20, 0, 0),
        "hand_R": (0, 0, 0),
        "thigh_L": (0, 0, 0),
        "calf_L": (-4, 0, 0),
        "foot_L": (0, 0, 0),
        "toe_L": (0, 0, 0),
        "thigh_R": (0, 0, 0),
        "calf_R": (-4, 0, 0),
        "foot_R": (0, 0, 0),
        "toe_R": (0, 0, 0),
        "accessory_strap": (0, 0, 0),
        **{"@hips_loc": (0, 0, 0)},
        "@root_loc": (0, 0, 0),
    }


def pose(base: dict, **over) -> dict:
    out = dict(base)
    out.update(over)
    return out


def _m(amp: float) -> float:
    return amp


# --------------------------------------------------------------------------
# Clip keyframe tables. Each returns [(frame, pose)].
# --------------------------------------------------------------------------
def idle_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["idle_amp"]
    # Slight forward pack-hunch so idle reads like the Codex labor silhouette
    # instead of a rigid mannequin stand.
    stand = pose(base_stand(fm), spine_02=(8, 0, 0), chest=(4, 0, 0), neck=(3, 0, 0), head=(3, 0, 0))
    return [
        (0, pose(stand)),
        (18, pose(stand, chest=(1.5 * a + 3, 0, 0), accessory_strap=(1.5 * a, 0, 0), head=(2, 0, 2 * a), **{"@hips_loc": (0, 0, 0.004)})),
        (36, pose(stand)),
        (54, pose(stand, chest=(-1.0 * a + 3, 0, 0), accessory_strap=(-1.5 * a, 0, 0), head=(2, 0, -2 * a), **{"@hips_loc": (0, 0, 0.004)})),
        (72, pose(stand)),
    ]


def idle_loaded_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["idle_amp"] * 0.6
    base = pose(base_stand(fm), lowerarm_L=(-30, 0, 0), lowerarm_R=(-30, 0, 0), **{"@hips_loc": (0, 0, fm["loaded_squat"])})
    return [
        (0, pose(base, accessory_strap=(1.0 * a, 0, 0))),
        (18, pose(base, chest=(1.0 * a, 0, 0), accessory_strap=(2.0 * a, 0, 0))),
        (36, pose(base, accessory_strap=(1.0 * a, 0, 0))),
        (54, pose(base, chest=(-0.7 * a, 0, 0), accessory_strap=(0.3 * a, 0, 0))),
        (72, pose(base, accessory_strap=(1.0 * a, 0, 0))),
    ]


def walk_keyframes(fm: dict) -> list[tuple[int, dict]]:
    amp = fm["walk_amp"]
    bob = fm["walk_bob"]
    squat = fm["walk_squat"]

    def contact(leg: str, back: str, arm_fwd: str, arm_back: str, yaw: float) -> dict:
        return pose(
            base_stand(fm),
            **{
                f"thigh_{leg}": (-30 * amp, 0, 0),
                f"thigh_{back}": (30 * amp, 0, 0),
                f"calf_{leg}": (-14, 0, 0),
                f"calf_{back}": (-2, 0, 0),
                f"foot_{leg}": (16, 0, 0),
                f"foot_{back}": (-10, 0, 0),
                f"toe_{leg}": (6, 0, 0),
                f"toe_{back}": (-4, 0, 0),
                f"upperarm_{arm_fwd}": (-22 * amp, 0, 0),
                f"upperarm_{arm_back}": (22 * amp, 0, 0),
                "lowerarm_L": (-28, 0, 0),
                "lowerarm_R": (-28, 0, 0),
                "spine_02": (2, 0, 0),
                "chest": (1, yaw, 0),
                "neck": (-2, 0, 0),
                "head": (-2, -yaw * 0.6, 0),
                **{"@hips_loc": (0.008, 0, squat)},
                "@root_loc": (0, 0, 0),
            },
        )

    def passing(leg_fwd: str, leg_back: str, yaw: float) -> dict:
        return pose(
            base_stand(fm),
            **{
                f"thigh_{leg_fwd}": (-6 * amp, 0, 0),
                f"thigh_{leg_back}": (6 * amp, 0, 0),
                "calf_L": (-16, 0, 0),
                "calf_R": (-16, 0, 0),
                "foot_L": (4, 0, 0),
                "foot_R": (4, 0, 0),
                f"upperarm_{leg_fwd}": (-10 * amp, 0, 0),
                f"upperarm_{leg_back}": (10 * amp, 0, 0),
                "lowerarm_L": (-28, 0, 0),
                "lowerarm_R": (-28, 0, 0),
                "spine_02": (0, 0, 0),
                "chest": (0, yaw, 0),
                "head": (-4, 0, 0),
                **{"@hips_loc": (0, 0, squat + bob)},
                "@root_loc": (0, 0, 0),
            },
        )

    return [
        (0, contact("R", "L", "L", "R", -3)),
        (9, passing("L", "R", -1)),
        (18, contact("L", "R", "R", "L", 3)),
        (27, passing("R", "L", 1)),
        (36, contact("R", "L", "L", "R", -3)),
    ]


def walk_loaded_keyframes(fm: dict) -> list[tuple[int, dict]]:
    amp = fm["walk_amp"]
    bob = fm["walk_bob"]
    squat = fm["walk_squat"]

    def contact(leg: str, back: str, yaw: float, sway: float) -> dict:
        return pose(
            base_stand(fm),
            **{
                f"thigh_{leg}": (-28 * amp, 0, 0),
                f"thigh_{back}": (28 * amp, 0, 0),
                f"calf_{leg}": (-13, 0, 0),
                f"calf_{back}": (-2, 0, 0),
                f"foot_{leg}": (15, 0, 0),
                f"foot_{back}": (-9, 0, 0),
                "upperarm_L": (-10 * amp, 0, 0),
                "upperarm_R": (10 * amp, 0, 0),
                "lowerarm_L": (-26, 0, 0),
                "lowerarm_R": (-26, 0, 0),
                "spine_02": (10, 0, 0),  # lean into the load (Codex forward hunch)
                "chest": (5, yaw, 0),
                "neck": (2, 0, 0),
                "head": (2, -yaw * 0.6, 0),
                "accessory_strap": (sway, 0, 0),
                **{"@hips_loc": (0.006, 0, squat)},
                "@root_loc": (0, 0, 0),
            },
        )

    def passing(yaw: float, sway: float) -> dict:
        return pose(
            base_stand(fm),
            **{
                "thigh_L": (-5 * amp, 0, 0),
                "thigh_R": (5 * amp, 0, 0),
                "calf_L": (-15, 0, 0),
                "calf_R": (-15, 0, 0),
                "foot_L": (4, 0, 0),
                "foot_R": (4, 0, 0),
                "upperarm_L": (-4 * amp, 0, 0),
                "upperarm_R": (4 * amp, 0, 0),
                "lowerarm_L": (-26, 0, 0),
                "lowerarm_R": (-26, 0, 0),
                "spine_02": (10, 0, 0),
                "chest": (4, yaw, 0),
                "neck": (2, 0, 0),
                "head": (2, 0, 0),
                "accessory_strap": (sway, 0, 0),
                **{"@hips_loc": (0, 0, squat + bob)},
                "@root_loc": (0, 0, 0),
            },
        )

    return [
        (0, contact("R", "L", -2, 0)),
        (9, passing(-1, -5)),
        (18, contact("L", "R", 2, 0)),
        (27, passing(1, 5)),
        (36, contact("R", "L", -2, 0)),
    ]


def reverse_keyframes(fm: dict) -> list[tuple[int, dict]]:
    return [
        (0, pose(base_stand(fm))),
        (4, pose(base_stand(fm), thigh_R=(12, 0, 0), thigh_L=(8, 0, 0), calf_L=(2, 0, 0), calf_R=(2, 0, 0),
                 foot_L=(-6, 0, 0), foot_R=(-6, 0, 0), upperarm_R=(12, 0, 0), upperarm_L=(8, 0, 0),
                 **{"@hips_loc": (0, 0.02, 0)})),
        (8, pose(base_stand(fm), thigh_R=(4, 0, 0), thigh_L=(2, 0, 0))),
        (12, pose(base_stand(fm))),
    ]


def gather_start_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["gather_amp"]
    return [
        (0, pose(base_stand(fm))),
        (4, pose(base_stand(fm), spine_02=(3, 0, 0), **{"@hips_loc": (0, 0, -0.01)})),
        (8, pose(base_stand(fm), spine_02=(6, 0, 0),
                 upperarm_R=(-55 * a, 25, 0), lowerarm_R=(-80, 0, 0), hand_R=(-10, 0, 0),
                 upperarm_L=(-35, -8, 0), lowerarm_L=(-50, 0, 0))),
        (12, pose(base_stand(fm), spine_02=(6, 0, 0),
                 upperarm_R=(-60 * a, 28, 0), lowerarm_R=(-90, 0, 0), hand_R=(-10, 0, 0),
                 upperarm_L=(-38, -8, 0), lowerarm_L=(-52, 0, 0))),
        (14, pose(base_stand(fm), spine_02=(6, 0, 0),
                 upperarm_R=(-60 * a, 28, 0), lowerarm_R=(-90, 0, 0), hand_R=(-22, 0, 0),
                 upperarm_L=(-38, -8, 0), lowerarm_L=(-52, 0, 0))),  # grip closes
        (16, pose(base_stand(fm), spine_02=(4, 0, 0),
                 upperarm_R=(-46 * a, 23, 0), lowerarm_R=(-66, 0, 0), hand_R=(-22, 0, 0),
                 upperarm_L=(-34, -6, 0), lowerarm_L=(-46, 0, 0))),  # tool_attach
        (20, pose(base_stand(fm), spine_02=(2, 0, 0),
                 upperarm_R=(-30 * a, 18, 0), lowerarm_R=(-45, 0, 0), hand_R=(-18, 0, 0),
                 upperarm_L=(-22, -4, 0), lowerarm_L=(-34, 0, 0))),
        (24, pose(base_stand(fm), spine_02=(2, 0, 0),
                 upperarm_R=(-20 * a, 16, 0), lowerarm_R=(-38, 0, 0), hand_R=(-15, 0, 0),
                 upperarm_L=(-14, -2, 0), lowerarm_L=(-26, 0, 0))),  # ready
    ]


def gather_loop_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["gather_amp"]
    return [
        (0, pose(base_stand(fm), spine_02=(2, 0, 0),
                 upperarm_R=(-20 * a, 16, 0), lowerarm_R=(-38, 0, 0), hand_R=(-15, 0, 0),
                 upperarm_L=(-14, -2, 0), lowerarm_L=(-26, 0, 0))),
        (4, pose(base_stand(fm), spine_02=(7, 0, 0), **{"@hips_loc": (0, 0, -0.01)},
                 upperarm_R=(-65 * a, 22, 0), lowerarm_R=(-85, 0, 0), hand_R=(-20, 0, 0),
                 upperarm_L=(-45, -6, 0), lowerarm_L=(-55, 0, 0))),  # support hand joins
        (8, pose(base_stand(fm), spine_02=(9, 0, 0), **{"@hips_loc": (0, 0, -0.015)},
                 upperarm_R=(-78 * a, 24, 0), lowerarm_R=(-100, 0, 0), hand_R=(-25, 0, 0),
                 upperarm_L=(-48, -6, 0), lowerarm_L=(-58, 0, 0))),
        (12, pose(base_stand(fm), spine_02=(9, 0, 0), **{"@hips_loc": (0, 0, -0.02)},
                 upperarm_R=(-72 * a, 22, 0), lowerarm_R=(-88, 0, 0), hand_R=(-28, 0, 0),
                 upperarm_L=(-46, -5, 0), lowerarm_L=(-56, 0, 0))),  # gather_contact
        (16, pose(base_stand(fm), spine_02=(5, 0, 0), head=(0, 0, -4),
                 upperarm_R=(-45 * a, 18, 0), lowerarm_R=(-60, 0, 0), hand_R=(-22, 0, 0),
                 upperarm_L=(-32, -4, 0), lowerarm_L=(-44, 0, 0))),
        (20, pose(base_stand(fm), spine_02=(2, 0, 0), head=(0, 0, -8),
                 upperarm_R=(-22 * a, 14, 0), lowerarm_R=(-40, 0, 0), hand_R=(-16, 0, 0),
                 upperarm_L=(-18, -2, 0), lowerarm_L=(-30, 0, 0))),
        (24, pose(base_stand(fm), spine_02=(2, 0, 0),
                 upperarm_R=(-18 * a, 15, 0), lowerarm_R=(-36, 0, 0), hand_R=(-14, 0, 0),
                 upperarm_L=(-13, -2, 0), lowerarm_L=(-25, 0, 0))),  # payload_attach (derived)
        (28, pose(base_stand(fm), spine_02=(2, 0, 0),
                 upperarm_R=(-20 * a, 16, 0), lowerarm_R=(-38, 0, 0), hand_R=(-15, 0, 0),
                 upperarm_L=(-14, -2, 0), lowerarm_L=(-26, 0, 0))),
        (36, pose(base_stand(fm), spine_02=(2, 0, 0),
                 upperarm_R=(-20 * a, 16, 0), lowerarm_R=(-38, 0, 0), hand_R=(-15, 0, 0),
                 upperarm_L=(-14, -2, 0), lowerarm_L=(-26, 0, 0))),
    ]


def gather_finish_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["gather_amp"]
    return [
        (0, pose(base_stand(fm), spine_02=(2, 0, 0),
                 upperarm_R=(-20 * a, 16, 0), lowerarm_R=(-38, 0, 0), hand_R=(-15, 0, 0),
                 upperarm_L=(-14, -2, 0), lowerarm_L=(-26, 0, 0))),
        (6, pose(base_stand(fm), spine_02=(4, 0, 0),
                 upperarm_R=(-50 * a, 26, 0), lowerarm_R=(-75, 0, 0), hand_R=(-12, 0, 0),
                 upperarm_L=(-30, -6, 0), lowerarm_L=(-42, 0, 0))),
        (10, pose(base_stand(fm), spine_02=(6, 0, 0),
                  upperarm_R=(-60 * a, 28, 0), lowerarm_R=(-90, 0, 0), hand_R=(-10, 0, 0),
                  upperarm_L=(-36, -8, 0), lowerarm_L=(-50, 0, 0))),
        (12, pose(base_stand(fm), spine_02=(6, 0, 0),
                  upperarm_R=(-60 * a, 28, 0), lowerarm_R=(-90, 0, 0), hand_R=(-8, 0, 0),
                  upperarm_L=(-36, -8, 0), lowerarm_L=(-50, 0, 0))),  # tool at rest
        (14, pose(base_stand(fm), spine_02=(6, 0, 0),
                  upperarm_R=(-60 * a, 28, 0), lowerarm_R=(-90, 0, 0), hand_R=(-5, 0, 0),
                  upperarm_L=(-36, -8, 0), lowerarm_L=(-50, 0, 0))),  # tool_release (grip opens)
        (16, pose(base_stand(fm), spine_02=(4, 0, 0),
                  upperarm_R=(-34, 18, 0), lowerarm_R=(-48, 0, 0), hand_R=(0, 0, 0),
                  upperarm_L=(-22, -4, 0), lowerarm_L=(-34, 0, 0))),
        (24, pose(base_stand(fm))),
    ]


def construct_start_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["construct_amp"]
    return [
        (0, pose(base_stand(fm))),
        (4, pose(base_stand(fm), spine_02=(3, 0, 0), **{"@hips_loc": (0, 0, -0.01)})),
        (8, pose(base_stand(fm), spine_02=(5, 0, 0),
                 upperarm_L=(-50 * a, -26, 0), lowerarm_L=(-75, 0, 0), hand_L=(-10, 0, 0),
                 upperarm_R=(-35, 8, 0), lowerarm_R=(-45, 0, 0))),  # support hand joins
        (12, pose(base_stand(fm), spine_02=(5, 0, 0),
                  upperarm_L=(-55 * a, -30, 0), lowerarm_L=(-85, 0, 0), hand_L=(-10, 0, 0),
                  upperarm_R=(-38, 8, 0), lowerarm_R=(-48, 0, 0))),
        (14, pose(base_stand(fm), spine_02=(5, 0, 0),
                  upperarm_L=(-55 * a, -30, 0), lowerarm_L=(-85, 0, 0), hand_L=(-22, 0, 0),
                  upperarm_R=(-38, 8, 0), lowerarm_R=(-48, 0, 0))),  # grip closes
        (16, pose(base_stand(fm), spine_02=(4, 0, 0),
                  upperarm_L=(-42 * a, -25, 0), lowerarm_L=(-62, 0, 0), hand_L=(-22, 0, 0),
                  upperarm_R=(-34, 7, 0), lowerarm_R=(-42, 0, 0))),  # tool_attach
        (20, pose(base_stand(fm), spine_02=(2, 0, 0),
                  upperarm_L=(-26 * a, -22, 0), lowerarm_L=(-44, 0, 0), hand_L=(-18, 0, 0),
                  upperarm_R=(-24, 6, 0), lowerarm_R=(-32, 0, 0))),
        (24, pose(base_stand(fm), spine_02=(2, 0, 0),
                  upperarm_L=(-15 * a, -20, 0), lowerarm_L=(-35, 0, 0), hand_L=(-18, 0, 0),
                  upperarm_R=(-16, 4, 0), lowerarm_R=(-26, 0, 0))),  # ready
    ]


def construct_loop_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["construct_amp"]
    return [
        (0, pose(base_stand(fm), spine_02=(2, 0, 0), **{"@hips_loc": (0, 0, -0.01)},
                 upperarm_L=(-15 * a, -20, 0), lowerarm_L=(-35, 0, 0), hand_L=(-18, 0, 0),
                 upperarm_R=(-16, 4, 0), lowerarm_R=(-26, 0, 0))),
        (6, pose(base_stand(fm), chest=(-6, 0, 0), spine_02=(-4, 0, 0), head=(6, 0, 0), **{"@hips_loc": (0, 0, -0.015)},
                 upperarm_L=(-150 * a, -10, 0), lowerarm_L=(-115, 0, 0), hand_L=(-25, 0, 0),
                 upperarm_R=(-20, 6, 0), lowerarm_R=(-30, 0, 0))),  # wind-up peak
        (12, pose(base_stand(fm), spine_02=(10, 0, 0), chest=(8, 0, 0), head=(10, 0, 0), **{"@hips_loc": (0, 0, -0.03)},
                  upperarm_L=(-38 * a, -16, 0), lowerarm_L=(-58, 0, 0), hand_L=(-20, 0, 0),
                  upperarm_R=(-30, 8, 0), lowerarm_R=(-40, 0, 0))),  # construct_contact strike
        (14, pose(base_stand(fm), spine_02=(6, 0, 0), chest=(2, 0, 0), **{"@hips_loc": (0, 0, -0.02)},
                  upperarm_L=(-55 * a, -18, 0), lowerarm_L=(-72, 0, 0), hand_L=(-22, 0, 0))),  # snap-and-settle
        (18, pose(base_stand(fm), chest=(-2, 0, 0), spine_02=(0, 0, 0), **{"@hips_loc": (0, 0, -0.01)},
                  upperarm_L=(-80 * a, -16, 0), lowerarm_L=(-85, 0, 0), hand_L=(-24, 0, 0))),
        (24, pose(base_stand(fm), spine_02=(2, 0, 0), **{"@hips_loc": (0, 0, -0.01)},
                  upperarm_L=(-110 * a, -13, 0), lowerarm_L=(-105, 0, 0), hand_L=(-25, 0, 0))),
        (36, pose(base_stand(fm), spine_02=(2, 0, 0), **{"@hips_loc": (0, 0, -0.01)},
                  upperarm_L=(-15 * a, -20, 0), lowerarm_L=(-35, 0, 0), hand_L=(-18, 0, 0),
                  upperarm_R=(-16, 4, 0), lowerarm_R=(-26, 0, 0))),
    ]


def construct_finish_keyframes(fm: dict) -> list[tuple[int, dict]]:
    a = fm["construct_amp"]
    return [
        (0, pose(base_stand(fm), spine_02=(2, 0, 0), **{"@hips_loc": (0, 0, -0.01)},
                 upperarm_L=(-15 * a, -20, 0), lowerarm_L=(-35, 0, 0), hand_L=(-18, 0, 0),
                 upperarm_R=(-16, 4, 0), lowerarm_R=(-26, 0, 0))),
        (6, pose(base_stand(fm), spine_02=(4, 0, 0),
                 upperarm_L=(-50 * a, -28, 0), lowerarm_L=(-72, 0, 0), hand_L=(-12, 0, 0),
                 upperarm_R=(-30, 6, 0), lowerarm_R=(-40, 0, 0))),
        (10, pose(base_stand(fm), spine_02=(5, 0, 0),
                  upperarm_L=(-55 * a, -30, 0), lowerarm_L=(-85, 0, 0), hand_L=(-10, 0, 0),
                  upperarm_R=(-36, 8, 0), lowerarm_R=(-48, 0, 0))),
        (12, pose(base_stand(fm), spine_02=(5, 0, 0),
                  upperarm_L=(-55 * a, -30, 0), lowerarm_L=(-85, 0, 0), hand_L=(-8, 0, 0),
                  upperarm_R=(-36, 8, 0), lowerarm_R=(-48, 0, 0))),  # tool at rest
        (14, pose(base_stand(fm), spine_02=(5, 0, 0),
                  upperarm_L=(-55 * a, -30, 0), lowerarm_L=(-85, 0, 0), hand_L=(-5, 0, 0),
                  upperarm_R=(-36, 8, 0), lowerarm_R=(-48, 0, 0))),  # tool_release (grip opens)
        (16, pose(base_stand(fm), spine_02=(4, 0, 0),
                  upperarm_L=(-34, -22, 0), lowerarm_L=(-50, 0, 0), hand_L=(0, 0, 0),
                  upperarm_R=(-22, 4, 0), lowerarm_R=(-32, 0, 0))),
        (24, pose(base_stand(fm))),
    ]


def deposit_keyframes(fm: dict) -> list[tuple[int, dict]]:
    kind = fm["deposit_kind"]
    if kind == "basket":
        return deposit_basket_keyframes(fm)
    return deposit_hopper_keyframes(fm)


def deposit_basket_keyframes(fm: dict) -> list[tuple[int, dict]]:
    squat = fm["loaded_squat"]
    base = pose(base_stand(fm), lowerarm_L=(-30, 0, 0), lowerarm_R=(-30, 0, 0), **{"@hips_loc": (0, 0, squat)})
    return [
        (0, pose(base, accessory_strap=(1.0, 0, 0))),
        (6, pose(base, spine_02=(8, 0, 0), upperarm_R=(35, -4, 0), lowerarm_R=(55, 0, 0),
                 upperarm_L=(35, 4, 0), lowerarm_L=(55, 0, 0), hand_R=(-12, 0, 0), hand_L=(-12, 0, 0))),
        (12, pose(base, spine_02=(6, 0, 0), upperarm_R=(38, -4, 0), lowerarm_R=(58, 0, 0),
                  upperarm_L=(38, 4, 0), lowerarm_L=(58, 0, 0), hand_R=(-18, 0, 0), hand_L=(-18, 0, 0))),  # unclip
        (16, pose(base, spine_02=(4, 0, 0), upperarm_R=(45, -10, 0), lowerarm_R=(70, 0, 0),
                  upperarm_L=(45, 10, 0), lowerarm_L=(70, 0, 0), hand_R=(-16, 0, 0), hand_L=(-16, 0, 0))),
        (20, pose(base, accessory_strap=(-35, 0, 0), spine_02=(-20, 0, 0), chest=(-12, 0, 0),
                  upperarm_R=(-60, 12, 0), lowerarm_R=(-70, 0, 0),
                  upperarm_L=(-60, -12, 0), lowerarm_L=(-70, 0, 0), hand_R=(-14, 0, 0), hand_L=(-14, 0, 0))),
        (28, pose(base, accessory_strap=(-48, 0, 0), spine_02=(-26, 0, 0), chest=(-16, 0, 0),
                  upperarm_R=(-62, 12, 0), lowerarm_R=(-72, 0, 0),
                  upperarm_L=(-62, -12, 0), lowerarm_L=(-72, 0, 0), hand_R=(-14, 0, 0), hand_L=(-14, 0, 0))),
        (36, pose(base, accessory_strap=(-58, 0, 0), spine_02=(-32, 0, 0), chest=(-20, 0, 0),
                  head=(15, 0, 0), **{"@hips_loc": (0, 0, squat - 0.01)},
                  upperarm_R=(-64, 12, 0), lowerarm_R=(-74, 0, 0),
                  upperarm_L=(-64, -12, 0), lowerarm_L=(-74, 0, 0), hand_R=(-14, 0, 0), hand_L=(-14, 0, 0))),
        (40, pose(base, accessory_strap=(-58, 0, 0), spine_02=(-32, 0, 0), chest=(-20, 0, 0),
                  head=(15, 0, 0), **{"@hips_loc": (0, 0, squat - 0.01)},
                  upperarm_R=(-64, 12, 0), lowerarm_R=(-74, 0, 0),
                  upperarm_L=(-64, -12, 0), lowerarm_L=(-74, 0, 0), hand_R=(-14, 0, 0), hand_L=(-14, 0, 0))),  # deposit_release hold
        (48, pose(base, accessory_strap=(-58, 0, 0), spine_02=(-32, 0, 0), chest=(-20, 0, 0),
                  head=(15, 0, 0), **{"@hips_loc": (0, 0, squat - 0.01)},
                  upperarm_R=(-64, 12, 0), lowerarm_R=(-74, 0, 0),
                  upperarm_L=(-64, -12, 0), lowerarm_L=(-74, 0, 0), hand_R=(-14, 0, 0), hand_L=(-14, 0, 0))),
        (52, pose(base, accessory_strap=(-20, 0, 0), spine_02=(-10, 0, 0), chest=(-6, 0, 0),
                  upperarm_R=(-40, 8, 0), lowerarm_R=(-50, 0, 0),
                  upperarm_L=(-40, -8, 0), lowerarm_L=(-50, 0, 0))),
        (60, pose(base, accessory_strap=(1.0, 0, 0))),
    ]


def deposit_hopper_keyframes(fm: dict) -> list[tuple[int, dict]]:
    squat = fm["loaded_squat"]
    base = pose(base_stand(fm), lowerarm_L=(-15, 0, 0), lowerarm_R=(-15, 0, 0), **{"@hips_loc": (0, 0, squat)})
    return [
        (0, pose(base, accessory_strap=(1.0, 0, 0))),
        (6, pose(base, hips=(0, 0, 125), spine_01=(0, 0, 105), chest=(0, 0, 88), neck=(0, 0, 62), head=(0, 0, 38))),
        (14, pose(base, hips=(0, 0, 125), spine_01=(0, 0, 105), chest=(0, 0, 88), neck=(0, 0, 62), head=(0, 0, 38),
                  spine_02=(-22, 0, 0), accessory_strap=(30, 0, 0),
                  thigh_L=(-16, 0, 0), thigh_R=(-16, 0, 0), calf_L=(-22, 0, 0), calf_R=(-22, 0, 0),
                  **{"@hips_loc": (0, 0, squat - 0.005)})),
        (22, pose(base, hips=(0, 0, 125), spine_01=(0, 0, 105), chest=(0, 0, 88), neck=(0, 0, 62), head=(0, 0, 38),
                  spine_02=(-34, 0, 0), accessory_strap=(42, 0, 0),
                  thigh_L=(-20, 0, 0), thigh_R=(-20, 0, 0), calf_L=(-26, 0, 0), calf_R=(-26, 0, 0),
                  **{"@hips_loc": (0, 0, squat - 0.01)})),
        (32, pose(base, hips=(0, 0, 125), spine_01=(0, 0, 105), chest=(0, 0, 88), neck=(0, 0, 62), head=(0, 0, 38),
                  spine_02=(-44, 0, 0), accessory_strap=(50, 0, 0),
                  thigh_L=(-22, 0, 0), thigh_R=(-22, 0, 0), calf_L=(-28, 0, 0), calf_R=(-28, 0, 0),
                  **{"@hips_loc": (0, 0, squat - 0.015)})),
        (40, pose(base, hips=(0, 0, 125), spine_01=(0, 0, 105), chest=(0, 0, 88), neck=(0, 0, 62), head=(0, 0, 38),
                  spine_02=(-48, 0, 0), accessory_strap=(52, 0, 0),
                  thigh_L=(-22, 0, 0), thigh_R=(-22, 0, 0), calf_L=(-28, 0, 0), calf_R=(-28, 0, 0),
                  **{"@hips_loc": (0, 0, squat - 0.015)})),  # deposit_release hold
        (48, pose(base, hips=(0, 0, 125), spine_01=(0, 0, 105), chest=(0, 0, 88), neck=(0, 0, 62), head=(0, 0, 38),
                  spine_02=(-48, 0, 0), accessory_strap=(52, 0, 0),
                  thigh_L=(-22, 0, 0), thigh_R=(-22, 0, 0), calf_L=(-28, 0, 0), calf_R=(-28, 0, 0),
                  **{"@hips_loc": (0, 0, squat - 0.015)})),
        (52, pose(base, hips=(0, 0, 125), spine_01=(0, 0, 105), chest=(0, 0, 88), neck=(0, 0, 62), head=(0, 0, 38),
                  spine_02=(-14, 0, 0), accessory_strap=(10, 0, 0),
                  thigh_L=(-6, 0, 0), thigh_R=(-6, 0, 0), calf_L=(-8, 0, 0), calf_R=(-8, 0, 0))),
        (60, pose(base, accessory_strap=(1.0, 0, 0))),
    ]


# --------------------------------------------------------------------------
# Clip metadata: single source of truth for names, semantics, markers,
# loop flags and tool-handling. Mirrored clips flip both the pose and the
# functional grip socket so either leading-hand variant can carry its tool.
# --------------------------------------------------------------------------
def clip_specs(citizen: str, fm: dict) -> list[dict]:
    prefix = citizen
    authored_side = {
        "gather": "R",  # acceptance sequence gathers right-handed
        "construct": "L",  # and constructs left-handed
    }
    grip_of_side = {"R": "socket_tool_R", "L": "socket_tool_L"}

    def name(suffix: str) -> str:
        return f"{prefix}_{suffix}"

    base = [
        dict(semantic="idle", suffix="idle", handedness=None, loop=True, keyframes=idle_keyframes(fm), markers=(), grip_socket=None),
        dict(semantic="walk_inplace", suffix="walk_inplace", handedness=None, loop=True, keyframes=walk_keyframes(fm), markers=(), grip_socket=None),
        dict(semantic="walk_loaded_inplace", suffix="walk_loaded_inplace", handedness=None, loop=True, keyframes=walk_loaded_keyframes(fm), markers=(), grip_socket=None),
        dict(semantic="idle_loaded", suffix="idle_loaded", handedness=None, loop=True, keyframes=idle_loaded_keyframes(fm), markers=(), grip_socket=None),
        dict(semantic="reverse", suffix="reverse", handedness=None, loop=False, keyframes=reverse_keyframes(fm), markers=(), grip_socket=None),
        dict(semantic="deposit", suffix="deposit", handedness=None, loop=False, keyframes=deposit_keyframes(fm), markers=((40, "deposit_release"),), grip_socket=None),
    ]
    for phase, side in authored_side.items():
        grip = grip_of_side[side]
        if phase == "gather":
            base.append(dict(semantic="gather_start", suffix=f"gather_start_{side}", handedness=side, loop=False,
                             keyframes=gather_start_keyframes(fm), markers=((16, "tool_attach"),), grip_socket=grip, attach_frame=16))
            base.append(dict(semantic="gather_loop", suffix=f"gather_loop_{side}", handedness=side, loop=True,
                             keyframes=gather_loop_keyframes(fm), markers=((12, "gather_contact"),), grip_socket=grip, contact_frame=12))
            base.append(dict(semantic="gather_finish", suffix=f"gather_finish_{side}", handedness=side, loop=False,
                             keyframes=gather_finish_keyframes(fm), markers=((14, "tool_release"),), grip_socket=grip, release_frame=14))
            hand = "L"
            base.append(dict(semantic="gather_start", suffix=f"gather_start_{hand}", handedness=hand, loop=False,
                             keyframes=mirrored(gather_start_keyframes(fm)), markers=((16, "tool_attach"),), grip_socket=grip_of_side[hand], attach_frame=16))
            base.append(dict(semantic="gather_loop", suffix=f"gather_loop_{hand}", handedness=hand, loop=True,
                             keyframes=mirrored(gather_loop_keyframes(fm)), markers=((12, "gather_contact"),), grip_socket=grip_of_side[hand], contact_frame=12))
            base.append(dict(semantic="gather_finish", suffix=f"gather_finish_{hand}", handedness=hand, loop=False,
                             keyframes=mirrored(gather_finish_keyframes(fm)), markers=((14, "tool_release"),), grip_socket=grip_of_side[hand], release_frame=14))
        else:
            base.append(dict(semantic="construct_start", suffix=f"construct_start_{side}", handedness=side, loop=False,
                             keyframes=construct_start_keyframes(fm), markers=((16, "tool_attach"),), grip_socket=grip, attach_frame=16))
            base.append(dict(semantic="construct_loop", suffix=f"construct_loop_{side}", handedness=side, loop=True,
                             keyframes=construct_loop_keyframes(fm), markers=((12, "construct_contact"),), grip_socket=grip, contact_frame=12))
            base.append(dict(semantic="construct_finish", suffix=f"construct_finish_{side}", handedness=side, loop=False,
                             keyframes=construct_finish_keyframes(fm), markers=((14, "tool_release"),), grip_socket=grip, release_frame=14))
            hand = "R"
            base.append(dict(semantic="construct_start", suffix=f"construct_start_{hand}", handedness=hand, loop=False,
                             keyframes=mirrored(construct_start_keyframes(fm)), markers=((16, "tool_attach"),), grip_socket=grip_of_side[hand], attach_frame=16))
            base.append(dict(semantic="construct_loop", suffix=f"construct_loop_{hand}", handedness=hand, loop=True,
                             keyframes=mirrored(construct_loop_keyframes(fm)), markers=((12, "construct_contact"),), grip_socket=grip_of_side[hand], contact_frame=12))
            base.append(dict(semantic="construct_finish", suffix=f"construct_finish_{hand}", handedness=hand, loop=False,
                             keyframes=mirrored(construct_finish_keyframes(fm)), markers=((14, "tool_release"),), grip_socket=grip_of_side[hand], release_frame=14))

    for spec in base:
        spec["name"] = name(spec["suffix"])
        frames = [f for f, _p in spec["keyframes"]]
        spec["frame_start"] = min(frames)
        spec["frame_end"] = max(frames)
        spec["duration_s"] = round((spec["frame_end"] - spec["frame_start"]) / FPS, 4)
    return base


def mirrored(frames_poses: list[tuple[int, dict]]) -> list[tuple[int, dict]]:
    return [(f, rig.mirror_pose(dict(p))) for f, p in frames_poses]


# --------------------------------------------------------------------------
# Action authoring
# --------------------------------------------------------------------------
TOOL_SOCKETS = ("socket_tool_R", "socket_tool_L")


def author_action(
    arm_obj,
    spec: dict,
    stand_matrices: dict[str, Matrix],
    fps: int = FPS,
):
    """Author one Action for one clip spec.

    Tool handling is authored as pose tracks on the non-deform tool sockets
    inside the SAME armature action (the tools are parented to their socket
    bones, so they ride the skeleton). The held socket keys an identity grip;
    every socket keys a "parked" local pose (inverse(hand) @ stand) on every
    other clip, so tools sit on their rests whenever they are not carried.
    """
    name = spec["name"]
    frames_poses = spec["keyframes"]
    act = bpy.data.actions.new(name)
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = act

    scene = bpy.context.scene
    grip_socket = spec.get("grip_socket")

    for frame, p in frames_poses:
        scene.frame_set(frame)
        for bone, euler in p.items():
            if bone.startswith("@") or bone in TOOL_SOCKETS:
                continue
            pb = arm_obj.pose.bones[bone]
            q = rig.world_euler_to_pose_quat(arm_obj, bone, *euler)
            pb.rotation_quaternion = q
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if "@hips_loc" in p:
            pb = arm_obj.pose.bones["hips"]
            pb.location = p["@hips_loc"]
            pb.keyframe_insert(data_path="location", frame=frame)
        if "@root_loc" in p:
            pb = arm_obj.pose.bones["root"]
            pb.location = p["@root_loc"]
            pb.keyframe_insert(data_path="location", frame=frame)

    # Explicit constant root track on every clip (root-motion inspection).
    first = frames_poses[0][0]
    last = frames_poses[-1][0]
    pb = arm_obj.pose.bones["root"]
    pb.location = (0.0, 0.0, 0.0)
    pb.keyframe_insert(data_path="location", frame=first)
    pb.keyframe_insert(data_path="location", frame=last)

    # Socket tracks: grip (identity) when held, parked otherwise.
    for frame, p in frames_poses:
        scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        depsgraph.update()
        for socket in TOOL_SOCKETS:
            pb = arm_obj.pose.bones[socket]
            if socket == grip_socket:
                q = rig.world_euler_to_pose_quat(arm_obj, socket, 0, 0, 0)
                pb.rotation_quaternion = q
                pb.location = (0.0, 0.0, 0.0)
            else:
                hand_world = arm_obj.matrix_world @ arm_obj.pose.bones[socket].parent.matrix
                local = hand_world.inverted() @ stand_matrices[socket]
                loc, quat, _scale = local.decompose()
                pb.rotation_quaternion = quat
                pb.location = loc
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            pb.keyframe_insert(data_path="location", frame=frame)

    for fc in _all_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

    for mframe, mname in spec["markers"]:
        mk = act.pose_markers.new(mname)
        mk.frame = mframe

    # Push the clip onto the armature's NLA so the glTF exporter (ACTIONS
    # mode) sees every clip, not just the currently-active action.
    track = arm_obj.animation_data.nla_tracks.new()
    track.name = "Clips"
    strip = track.strips.new(name, 0, act)
    strip.name = name
    return act


def _all_fcurves(act):
    """All fcurves of a slotted Action (Blender 4.4+/5.x storage)."""
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    yield fc


def socket_matrix(arm_obj, bone_name: str, frame: int) -> Matrix:
    """World matrix of a pose bone at a frame (armature sits at identity)."""
    scene = bpy.context.scene
    scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    pb = arm_obj.pose.bones[bone_name]
    return arm_obj.matrix_world @ pb.matrix
