#!/usr/bin/env python3
"""Bake the cutout villager to AoE2-style 8-direction sprite sheets.

Facings follow the project's existing order (0 = S, clockwise). Only three of
the eight are painted art; the rest are derived, exactly the way AoE2 itself
ships five drawn directions and mirrors three:

    0 S   painted front
    1 SE  front, lightly narrowed (0.90) and turned 3.5° toward screen-right
    2 E   painted side
    3 NE  back, lightly narrowed (0.90) and turned 3.5° toward screen-right
    4 N   painted back (parts already cut from a mirrorSource plate)
    5 NW  mirror of NE
    6 W   mirror of E
    7 SW  mirror of SE

Mirroring swaps which hand carries the sickle. AoE2 has the same artefact and
it is invisible at unit scale; it is recorded in the manifest rather than hidden.

Every frame is cropped to one shared box anchored on the figure's ground line
and centre line, then feet are pinned to that ground line so a unit never hops
when the clip or facing changes.

Usage:
    python3 bake_sprites.py --out ../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image

import gait_ik
import rigpose as rp

FACINGS = [
    # index, name, view, squash, mirror, gain key, facing twist (degrees)
    # Diagonals are narrowed + lightly twisted stand-ins for missing three-quarter
    # paintings. Keep squash gentle (0.90) and twist small (3.5°) — 0.80/7° read as
    # crushed/warped at unit scale.
    (0, "S", "S", 1.00, False, "S", 0.0),
    (1, "SE", "S", 0.90, False, "SE", -3.5),
    (2, "E", "E", 1.00, False, "E", 0.0),
    (3, "NE", "N", 0.90, False, "NE", -3.5),
    (4, "N", "N", 1.00, False, "N", 0.0),
    (5, "NW", "N", 0.90, True, "NE", -3.5),
    (6, "W", "E", 1.00, True, "E", 0.0),
    (7, "SW", "S", 0.90, True, "SE", -3.5),
]

TWIST_PARTS = ("torso", "head")
# Slack around the figure on the render canvas. The build wind-up throws the tool
# arm most of a figure-width clear of the body, so this is sized for that pose,
# not for the rest pose. `main` fails if any frame still reaches the edge.
PAD = 560


def pin_to_ground(image: Image.Image, ground_y: float) -> Image.Image:
    """Translate so the lowest opaque pixel sits on the shared ground line.

    Prefer `pin_feet_to_ground` for clips where a tool (sickle) or a swing foot
    can dip below the planted soles — pinning the whole alpha box then lifts
    the body and reads as a vertical pop.
    """
    box = rp.content_box(image)
    if box is None:
        return image
    current_bottom = box[3] - 1  # PIL bbox bottom is exclusive
    dy = int(round(ground_y - current_bottom))
    if dy == 0:
        return image
    shifted = Image.new("RGBA", image.size, (0, 0, 0, 0))
    # paste clips negative offsets, so both lift and drop stay in-bounds
    shifted.paste(image, (0, dy), image)
    return shifted


def foot_bottom_y(
    rig: rp.Rig,
    pose: dict,
    canvas: tuple[int, int],
    origin: tuple[float, float],
    *,
    squash: float = 1.0,
    mirror: bool = False,
) -> int | None:
    """Lowest opaque pixel among foot parts only (ignores sickle, hands, hem)."""
    hide = tuple(pid for pid in rig.parts if "foot" not in pid)
    feet = rp.render_pose(rig, pose, canvas, origin, squash=squash, mirror=mirror, hide=hide)
    box = rp.content_box(feet)
    if box is None:
        return None
    return box[3] - 1


def pin_feet_to_ground(
    image: Image.Image,
    ground_y: float,
    foot_bottom: int | None,
) -> Image.Image:
    """Translate so the planted soles sit on the shared ground line.

    Uses a pre-measured foot bottom so a low sickle or swing toe cannot yank
    the whole figure up the frame.
    """
    if foot_bottom is None:
        return pin_to_ground(image, ground_y)
    dy = int(round(ground_y - foot_bottom))
    if dy == 0:
        return image
    shifted = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shifted.paste(image, (0, dy), image)
    return shifted


def resolve_angles(frame: dict, gains: dict, twist: float) -> dict[str, float]:
    """Turn authored ["gainKey", degrees] pairs into plain degrees for one facing."""
    out: dict[str, float] = {}
    for part_id, value in frame.get("angles", {}).items():
        if isinstance(value, list):
            key, degrees = value
            out[part_id] = degrees * gains.get(key, 1.0)
        else:
            out[part_id] = float(value)
    for part_id in TWIST_PARTS:
        if twist:
            out[part_id] = out.get(part_id, 0.0) + twist
    return out


def resolve_root(frame: dict, gains: dict) -> list[float]:
    root = frame.get("root", [0.0, 0.0])
    resolved = []
    for value in root:
        if isinstance(value, list):
            key, amount = value
            resolved.append(amount * gains.get(key, 1.0))
        else:
            resolved.append(float(value))
    return resolved


def resolve_pose(
    frame: dict,
    gains: dict,
    twist: float,
    *,
    clip: dict | None = None,
    rig: rp.Rig | None = None,
    frame_index: int = 0,
    frame_count: int = 1,
) -> dict:
    """Angles + root for one facing. Walk legs are cyninja gait-IK, not FK keys."""
    angles = resolve_angles(frame, gains, twist)
    root = resolve_root(frame, gains)
    gait = (clip or {}).get("gait")
    if gait and rig is not None:
        # phaseBias nudges samples off the exact plant-start (gu=0), where a
        # 4-frame bake otherwise hits full extension and tears the ankle cutout.
        bias = float(gait.get("phaseBias", 0.0))
        phase_u = (frame_index / frame_count + bias) % 1.0
        # Bend signs: profile (E) keeps both knees "forward" (same sign). Frontal
        # facings need opposite signs so knees do not knock. Prefer per-facing
        # viewGain.bendA/bendB (authored in godot-gait); fall back to opposite
        # defaults on S/N instead of the old same-sign override that caused
        # knock-knees.
        bend_a = float(gains.get("bendA", gait.get("bendA", 1.0)))
        bend_b = float(gains.get("bendB", gait.get("bendB", 1.0)))
        if "bendA" not in gains and "bendB" not in gains and rig.view in ("S", "N"):
            # Camera-facing outward knees (avoid knock-knees). Empirically:
            # S wants A=+1 B=-1; N (hips mirrored in paint) wants A=-1 B=+1.
            # The inverted pair collapses knee_gap and reads knock-kneed.
            bend_a, bend_b = (1.0, -1.0) if rig.view == "S" else (-1.0, 1.0)
        gait_ik.apply_gait(
            angles,
            root,
            rig,
            phase_u,
            stride=float(gait["stride"]) * gains.get("stride", 1.0),
            lift=float(gait["lift"]) * gains.get("lift", 1.0),
            contact=float(gait.get("contact", gait_ik.CONTACT)),
            bend_a=bend_a,
            bend_b=bend_b,
            phase_a=float(gait.get("phaseA", 0.5)),
            phase_b=float(gait.get("phaseB", 0.0)),
            plant_drop=float(gait.get("plantDrop", 0.0)) * gains.get("lift", 1.0),
        )
    return {"angles": angles, "root": root}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts-dir", default="parts")
    ap.add_argument("--clips", default="clips.json")
    ap.add_argument("--out", required=True)
    ap.add_argument("--frame-size", type=int, default=256)
    ap.add_argument("--ground-fraction", type=float, default=0.90,
                    help="where the figure's ground line sits in the frame, top-down")
    ap.add_argument("--headroom", type=float, default=1.34,
                    help="frame side as a multiple of the rest-pose figure height")
    ap.add_argument("--unit", default="sunwoven-villager")
    ap.add_argument("--unit-height", type=float, default=1.75,
                    help="the villager's real height in metres, ground line to crown")
    ap.add_argument("--contact-sheet", default="build/contact-sheet.png")
    args = ap.parse_args()

    root = Path(__file__).parent
    parts_root = root / args.parts_dir
    clips_doc = json.loads((root / args.clips).read_text())
    clips = clips_doc["clips"]
    view_gain = clips_doc["viewGain"]

    rigs: dict[str, rp.Rig] = {}
    substitutions: dict[str, str] = {}
    for view in ("S", "E", "N"):
        directory = parts_root / view
        if (directory / "parts.json").exists():
            rigs[view] = rp.load_rig(directory)
        else:
            rigs[view] = rp.load_rig(parts_root / "S")
            substitutions[view] = "S"
    if substitutions:
        print(f"WARNING: no painted rig for {sorted(substitutions)}; using S. "
              "Those facings are placeholders, not final art.")

    base = rigs["S"]
    canvas = (base.width + 2 * PAD, base.height + 2 * PAD)
    # The three sheets are not the same width - the side view is half as wide as
    # the front. Every view is placed by its own centre line and ground line onto
    # one shared anchor, so a unit does not slide sideways or float as it turns.
    anchor = (PAD + base.centre_px, PAD + base.ground_px)

    def origin_for(rig: rp.Rig) -> tuple[float, float]:
        return (anchor[0] - rig.centre_px, anchor[1] - rig.ground_px)

    # Pass 1 — render every frame once to find the union footprint, so the shared
    # frame box is measured rather than guessed.
    print("measuring frame box...")
    union = None
    for _, _, view, squash, mirror, gain_key, twist in FACINGS:
        rig = rigs[view]
        gains = view_gain[gain_key]
        for clip in clips.values():
            nframes = len(clip["frames"])
            for number, frame in enumerate(clip["frames"]):
                pose = resolve_pose(
                    frame, gains, twist,
                    clip=clip, rig=rig, frame_index=number, frame_count=nframes,
                )
                image = rp.render_pose(
                    rig, pose, canvas, origin_for(rig), squash=squash, mirror=mirror,
                )
                box = rp.content_box(image)
                if box is None:
                    continue
                union = box if union is None else (
                    min(union[0], box[0]), min(union[1], box[1]),
                    max(union[2], box[2]), max(union[3], box[3]),
                )
    assert union is not None
    if union[0] <= 0 or union[1] <= 0 or union[2] >= canvas[0] or union[3] >= canvas[1]:
        raise SystemExit(
            f"a pose reached the render canvas edge (union={union}, canvas={canvas}); "
            "raise PAD or the frame would be silently clipped"
        )

    ground_y, centre_x = anchor[1], anchor[0]
    side = int(round(args.headroom * base.height))
    # Size the square from VERTICAL extent (headroom + ground). Growing the side
    # to fit a wide walk stride shrinks the whole figure in the 256² output and
    # makes the stride disappear (~7px). Prefer a readable figure; extreme toe
    # tips may kiss the left/right edge.
    vert_side = max(
        side,
        int(round((ground_y - union[1]) / args.ground_fraction)) + 2,
        int(round((union[3] - ground_y) / max(1e-6, 1 - args.ground_fraction))) + 2,
    )
    horiz_need = int(round(2 * max(centre_x - union[0], union[2] - centre_x))) + 2
    side = vert_side
    if horiz_need > side * 1.08:
        print(
            f"  note: walk/tool width {horiz_need}px > frame {side}px; "
            "keeping vertical-sized frame so stride stays readable at 256²"
        )
    elif horiz_need > side:
        side = horiz_need
    top = ground_y - args.ground_fraction * side
    left = centre_x - side / 2
    frame_box = (int(round(left)), int(round(top)), int(round(left)) + side, int(round(top)) + side)
    print(f"  union={union} -> frame side {side}px (vert={vert_side}, horiz_need={horiz_need}), box {frame_box}")

    out_dir = Path(args.out)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    size = (args.frame_size, args.frame_size)
    sheet_rows: list[list[Image.Image]] = []
    written = 0

    for index, name, view, squash, mirror, gain_key, twist in FACINGS:
        rig = rigs[view]
        gains = view_gain[gain_key]
        for clip_name, clip in clips.items():
            target = out_dir / clip_name / str(index)
            target.mkdir(parents=True, exist_ok=True)
            row: list[Image.Image] = []
            nframes = len(clip["frames"])
            for number, frame in enumerate(clip["frames"]):
                pose = resolve_pose(
                    frame, gains, twist,
                    clip=clip, rig=rig, frame_index=number, frame_count=nframes,
                )
                image = rp.render_pose(
                    rig, pose, canvas, origin_for(rig), squash=squash, mirror=mirror,
                )
                foot_y = foot_bottom_y(
                    rig, pose, canvas, origin_for(rig), squash=squash, mirror=mirror,
                )
                image = pin_feet_to_ground(image, ground_y, foot_y)
                cropped = image.crop(frame_box).resize(size, Image.LANCZOS)
                cropped.save(target / f"{number}.png")
                written += 1
                row.append(cropped)
            if clip_name == "walk":
                sheet_rows.append([Image.open(target / f"{n}.png") for n in range(len(row))])
        print(f"  facing {index} {name:<2} <- view {view} squash={squash} mirror={mirror}")

    manifest = {
        "schema": "sunfold.sprite-manifest/1",
        "unit": args.unit,
        "frameWidth": args.frame_size,
        "frameHeight": args.frame_size,
        "fps": 10,
        "mirrorAtRuntime": False,
        "anchor": {"x": 0.5, "y": args.ground_fraction},
        "unitHeightMeters": args.unit_height,
        # The frame is taller than the villager - it has to hold a raised tool and
        # a stride. This is the whole frame in metres, so the player never has to
        # guess a scale factor from the pixel size.
        "worldHeight": round(args.unit_height * side / base.height, 6),
        "facings": [name for _, name, *_ in FACINGS],
        "facingSource": {
            str(i): {"view": v, "squash": s, "mirror": m, "painted": s == 1.0 and not m}
            for i, _, v, s, m, _, _ in FACINGS
        },
        "camera": {
            "pitchDegrees": 57,
            "yawDegrees": 45,
            "fovDegrees": 38,
            "note": "Must match ThreeRuntime/src/rts-camera.js.",
        },
        "clips": {
            name: {
                "frames": len(clip["frames"]),
                "loop": clip.get("loop", True),
                "fps": clip["fps"],
                "source": "cutout-bake",
                "events": clip.get("events", {}),
                "note": clip.get("note", ""),
            }
            for name, clip in clips.items()
        },
        "provenance": {
            "method": "2D cutout puppet baked from the painted turnaround",
            "paintedViews": sorted(set(v for _, _, v, s, m, _, _ in FACINGS if s == 1.0 and not m)),
            "substitutedViews": substitutions,
            "honesty": (
                "Facings 1, 3, 5, 7 are lightly narrowed (0.90) + twisted (3.5°) derivations of "
                "a painted view, not painted three-quarter art. Facings 5, 6, 7 are mirrored, "
                "which swaps the sickle to the other hand exactly as AoE2's own mirrored "
                "facings do. N parts are cut from a mirrorSource back plate so the tool hand "
                "matches S without a bake-time flip."
            ),
            "walkLegs": (
                "Walk legs use cyninja-style gait IK (tvanhens/cyninja-prompt-demo): authored "
                "foot plant/swing paths, 2-bone hip/knee solve, ankle world-aim that stays "
                "flat-to-plantarflex and never dorsiflexes tip-up. Arms/torso remain FK keys."
            ),
        },
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {written} frames + manifest -> {out_dir}")

    if args.contact_sheet and sheet_rows:
        cols = max(len(r) for r in sheet_rows)
        sheet = Image.new("RGBA", (cols * args.frame_size, len(sheet_rows) * args.frame_size),
                          (30, 34, 44, 255))
        for r, row in enumerate(sheet_rows):
            for c, cell in enumerate(row):
                sheet.alpha_composite(cell, (c * args.frame_size, r * args.frame_size))
        path = root / args.contact_sheet
        path.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(path)
        print(f"contact sheet (walk, all facings) -> {path}")


if __name__ == "__main__":
    main()
