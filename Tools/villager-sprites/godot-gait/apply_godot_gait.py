#!/usr/bin/env python3
"""Merge Godot gait-lab export into clips.json bend signs (and optional overrides).

Usage (from Tools/villager-sprites):
  # After pressing E in the Godot gait lab:
  python3 godot-gait/apply_godot_gait.py

  # Then re-bake:
  python3 bake_sprites.py --out ../../ThreeRuntime/assets/citizens/sprites/sunwoven-villager

Godot authors the walk IK; this repo's Python cutout pipeline still owns pixels
(manifest, 256² frames, healing/caps). This script only syncs bendA/bendB (and
stride/lift/contact/plantDrop) from export/walk_angles.json into clips.json.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SPRITES = ROOT.parent
CLIPS = SPRITES / "clips.json"
DEFAULT_EXPORT = ROOT / "export" / "walk_angles.json"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--export", type=Path, default=DEFAULT_EXPORT)
    ap.add_argument("--clips", type=Path, default=CLIPS)
    ap.add_argument(
        "--write-bends-only",
        action="store_true",
        help="Only update bendA/bendB on walk.gait (default also syncs stride/lift/contact/plantDrop).",
    )
    args = ap.parse_args()

    if not args.export.is_file():
        raise SystemExit(
            f"Missing {args.export}. Open godot-gait in Godot, press E to export."
        )

    export = json.loads(args.export.read_text())
    clips = json.loads(args.clips.read_text())
    walk = clips.setdefault("clips", {}).setdefault("walk", {})
    gait = walk.setdefault("gait", {})
    view_gain = clips.setdefault("viewGain", {})

    export_walk = export["clips"]["walk"]
    if not args.write_bends_only:
        for key in ("stride", "lift", "contact", "phaseA", "phaseB", "plantDrop"):
            src = export_walk.get("gait", {})
            # plantDrop in Godot export vs plantDrop / contact naming
            if key == "plantDrop" and "plantDrop" in src:
                gait["plantDrop"] = src["plantDrop"]
            elif key in src:
                gait[key] = src[key]

    export_gains = export_walk.get("viewGain", {})
    for facing, g in export_gains.items():
        if facing not in view_gain:
            continue
        view_gain[facing]["stride"] = g.get("stride", view_gain[facing].get("stride", 1.0))
        view_gain[facing]["lift"] = g.get("lift", view_gain[facing].get("lift", 1.0))
        # bend signs live on walk.gait in clips today as bendA/bendB globals.
        # Per-facing bends are the knock-knee fix — store on viewGain and teach
        # bake_sprites to read them (apply writes both places for visibility).
        view_gain[facing]["bendA"] = g.get("bendA", 1.0)
        view_gain[facing]["bendB"] = g.get("bendB", 1.0)

    # Keep legacy global bend fields as the E (profile) defaults.
    e = export_gains.get("E", {})
    gait["bendA"] = e.get("bendA", gait.get("bendA", 1.0))
    gait["bendB"] = e.get("bendB", gait.get("bendB", 1.0))
    gait["source"] = "godot-gait lab + tvanhens/cyninja-prompt-demo"

    args.clips.write_text(json.dumps(clips, indent=2) + "\n")
    print(f"Updated {args.clips}")
    print("Per-facing bends:")
    for facing, g in sorted(export_gains.items()):
        print(f"  {facing}: bendA={g.get('bendA')} bendB={g.get('bendB')}")
    print("Next: ensure bake_sprites/gait_ik read viewGain bendA/bendB, then bake.")


if __name__ == "__main__":
    main()
