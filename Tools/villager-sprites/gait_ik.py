#!/usr/bin/env python3
"""Two-bone gait IK for the cutout villager — adapted from tvanhens/cyninja.

The cyninja "Ink & Bones" walk does not FK the legs. You author where each
foot goes (a plant/swing path); hip and knee angles fall out of a 2-bone IK
solve, and the foot bone is aimed at an absolute world angle so soles stay
grounded and airborne ankles stay plantarflexed (toe down — never tip-up).

Angle convention matches rigpose.py / cyninja: 0 = screen-down, positive
swings the tip toward screen-right (east). Flat sole ≈ world 0 on our painted
boots (cyninja uses 90 because its foot bone rests pointing east).
"""

from __future__ import annotations

import math
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import rigpose as rp

# Default fraction of the cycle a walk foot spends on the ground.
CONTACT = 0.60


def _unit(api_deg: float) -> tuple[float, float]:
    """0 → down, 90 → east."""
    r = math.radians(api_deg)
    return (math.sin(r), math.cos(r))


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else hi if v > hi else v


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = _clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _angle_of(vx: float, vy: float) -> float:
    """Api angle of a vector (0 = down, 90 = east)."""
    return math.degrees(math.atan2(vx, vy))


def leg_geometry(rig: "rp.Rig", side: str) -> dict:
    """Pivot chain and rest bone angles for legA / legB."""
    thigh = rig.parts[f"leg{side}_thigh"]
    shin = rig.parts[f"leg{side}_shin"]
    foot = rig.parts[f"leg{side}_foot"]
    hip = thigh.pivot_px
    knee = shin.pivot_px
    ankle = foot.pivot_px
    v1 = (knee[0] - hip[0], knee[1] - hip[1])
    v2 = (ankle[0] - knee[0], ankle[1] - knee[1])
    return {
        "hip": hip,
        "knee": knee,
        "ankle": ankle,
        "l1": math.hypot(*v1),
        "l2": math.hypot(*v2),
        "rest_thigh": _angle_of(*v1),
        "rest_shin": _angle_of(*v2),
        "rest_foot": foot.rest_angle,
        "thigh_rest_angle": thigh.rest_angle,
        "shin_rest_angle": shin.rest_angle,
    }


def solve_chain(
    hip: tuple[float, float],
    l1: float,
    l2: float,
    target: tuple[float, float],
    bend: float = 1.0,
) -> tuple[float, float]:
    """Return (upper_world_deg, lower_world_deg) so shin tip reaches target."""
    dx = target[0] - hip[0]
    dy = target[1] - hip[1]
    dist = _clamp(math.hypot(dx, dy), abs(l1 - l2) + 0.5, l1 + l2 - 0.5)
    base = _angle_of(dx, dy)
    cos_a = _clamp((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
    a1 = math.degrees(math.acos(cos_a))
    upper_world = base + bend * a1
    ux, uy = _unit(upper_world)
    knee = (hip[0] + l1 * ux, hip[1] + l1 * uy)
    bx, by = _unit(base)
    reach = (hip[0] + dist * bx, hip[1] + dist * by)
    lower_world = _angle_of(reach[0] - knee[0], reach[1] - knee[1])
    return upper_world, lower_world


def foot_path(
    phase_u: float,
    stride: float,
    lift: float,
    ground_y: float,
    hip_x: float,
    contact: float = CONTACT,
) -> tuple[float, float, float]:
    """Author the ankle target and foot world aim for one gait phase.

    Returns (target_x, target_y, foot_world_deg).
    Planted feet roll heel/ball → flat → toe-off; swing stays plantarflexed
    (toe down). Positive foot_world would be dorsiflexed tip-up — never emitted.
    """
    gu = phase_u % 1.0
    if gu < 0:
        gu += 1.0
    contact = _clamp(contact, 0.05, 0.95)

    # 0.42 of stride — readable AoE contact without full-extension ankle tear.
    half = stride * 0.42
    if gu < contact:
        # PLANTED: front → back. Ankle Y stays on the ground line — any rise here
        # made pin_to_ground translate the whole sprite by a different dy each
        # frame and the head/backpack popped between walk keys.
        s = gu / contact
        x = _lerp(half, -half, s)
        y = ground_y
        # Flat sole through mid-stance; mild push-off plantarflex (negative).
        # Keep this gentle — cutout boots read "broken" past ~10° of counter-rotate.
        toe = _lerp(0.0, -5.0, _smoothstep(0.65, 1.0, s))
    else:
        # SWING: arc frontward. y must be continuous with plant at both ends —
        # a min-lift floor (old max(sin, 0.45)) snapped the foot up at toe-off
        # and slammed it down at heel-strike, which read as leg jitter.
        v = (gu - contact) / (1.0 - contact)
        x = _lerp(-half, half, _smoothstep(0.0, 1.0, v))
        y = ground_y - lift * math.sin(math.pi * v)
        toe = -7.0 * (1.0 - v) * (1.0 - v)

    return (hip_x + x, y, toe)


def solve_leg(
    geom: dict,
    target: tuple[float, float],
    foot_world: float,
    bend: float,
    root: tuple[float, float] = (0.0, 0.0),
    pelvis_world: float = 0.0,
) -> dict[str, float]:
    """IK one leg → local thigh/shin/foot deltas for rigpose."""
    hip = (geom["hip"][0] + root[0], geom["hip"][1] + root[1])
    upper_world, lower_world = solve_chain(hip, geom["l1"], geom["l2"], target, bend)

    thigh = upper_world - pelvis_world - geom["rest_thigh"] - geom["thigh_rest_angle"]
    shin = (
        lower_world
        - upper_world
        - (geom["rest_shin"] - geom["rest_thigh"])
        - geom["shin_rest_angle"]
    )
    # Aim the painted boot: world foot ≈ lower_world + rest_foot + foot_local.
    # Never dorsiflex tip-up past flat. Cap local ankle travel so a deep knee
    # bend cannot wrench the cutout boot into a "broken hinge" silhouette.
    foot = min(0.0, foot_world) - lower_world - geom["rest_foot"]
    foot = _clamp(foot, -22.0, 22.0)
    return {"thigh": thigh, "shin": shin, "foot": foot}


def apply_gait(
    angles: dict[str, float],
    root: list[float],
    rig: "rp.Rig",
    phase_u: float,
    *,
    stride: float,
    lift: float,
    contact: float = CONTACT,
    bend_a: float = 1.0,
    bend_b: float = 1.0,
    phase_a: float = 0.5,
    phase_b: float = 0.0,
    plant_drop: float = 0.0,
) -> None:
    """Overwrite legA/legB angles in `angles` from a cyninja-style gait.

    `root` is [dx, dy] in figure-normalized units (same as clips.json).
    Foot targets are in figure pixels; planted ankles stay on the rest ground
    line while root bob moves the hips over them.

    `plant_drop` raises the ankle targets (smaller y) by that many pixels so a
    fully-extended rest stance still has knee bend and stride reach — without
    it every forward plant hits the IK length clamp and the feet tip weirdly.
    """
    root_px = (root[0] * rig.width, root[1] * rig.height)
    # Shared plant center + ground line for BOTH feet. Orbiting each ankle's own
    # rest X made contact poses asymmetric (one key almost standing still, the
    # opposite key a huge leap) — that is the walk stutter between steps.
    geom_a = leg_geometry(rig, "A")
    geom_b = leg_geometry(rig, "B")
    center_x = 0.5 * (geom_a["ankle"][0] + geom_b["ankle"][0])
    ground_y = 0.5 * (geom_a["ankle"][1] + geom_b["ankle"][1]) - plant_drop
    for side, phase, bend, geom in (
        ("A", phase_a, bend_a, geom_a),
        ("B", phase_b, bend_b, geom_b),
    ):
        gu = (phase_u + phase) % 1.0
        tx, ty, foot_world = foot_path(gu, stride, lift, ground_y, center_x, contact)
        # World-space plant: ankle y is absolute; root bob is absorbed by knees.
        target = (tx + root_px[0], ty)
        solved = solve_leg(geom, target, foot_world, bend, root=root_px)
        angles[f"leg{side}_thigh"] = solved["thigh"]
        angles[f"leg{side}_shin"] = solved["shin"]
        angles[f"leg{side}_foot"] = solved["foot"]
