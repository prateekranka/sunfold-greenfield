#!/usr/bin/env python3
"""Stack unit Walk/Carry/Gather/Build (etc.) 256 sheets into runtime-atlas.png.

Preserves fixed 256² cells and feet baseline — never re-crops or recenters.

Usage (from repo root):

    python3 SunfoldGreenfield-threejs-wkwebview/Tools/citizens/pack-unit-combined-atlas.py \\
      --unit village-manbun-wanderer --clips walk,carry,gather,build
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image

Image.MAX_IMAGE_PIXELS = None

ROOT = Path(__file__).resolve().parents[3]  # aoe-space-edition
GAME_ROOT = ROOT / "SunfoldGreenfield-threejs-wkwebview/ThreeRuntime/assets/citizens/sprites"
RES_ROOT = ROOT / "SunfoldGreenfield-threejs-wkwebview/Resources/ThreeRuntime/sprites"

FACINGS = [
    "S", "SSE", "SE", "ESE", "E", "ENE", "NE", "NNE",
    "N", "NNW", "NW", "WNW", "W", "WSW", "SW", "SSW",
]

DEFAULT_CLIPS = ["walk", "carry", "gather", "build"]


def title_clip(clip: str) -> str:
    return clip[:1].upper() + clip[1:].lower()


def sheet_fname(clip: str, prefix: str = "Citizen") -> str:
    return f"{prefix}_{title_clip(clip)}_16dir_8frames_256.png"


def humanize_unit(unit: str) -> str:
    return " ".join(part.capitalize() for part in unit.replace("_", "-").split("-"))


def pack(
    *,
    unit: str,
    clips: list[str],
    prefix: str = "Citizen",
    character_name: str | None = None,
    dry_run: bool = False,
) -> dict:
    src = ROOT / "assets/sprites" / unit / "runtime"
    game = GAME_ROOT / unit
    res = RES_ROOT / unit
    name = character_name or humanize_unit(unit)

    clip_rows: list[tuple[str, str, int]] = []
    for i, clip in enumerate(clips):
        clip_rows.append((clip, sheet_fname(clip, prefix), i * 16))

    sheets = []
    for clip_name, fname, origin in clip_rows:
        p = src / fname
        if not p.exists():
            p = game / fname
        if not p.exists():
            raise SystemExit(f"{clip_name}: missing runtime sheet {fname} under {src} or {game}")
        if dry_run:
            print(f"[dry-run] would open {p}")
            sheets.append((clip_name, None, origin, fname, p))
            continue
        im = Image.open(p).convert("RGBA")
        if im.size != (2048, 4096):
            raise SystemExit(f"{clip_name}: expected 2048×4096, got {im.size}")
        sheets.append((clip_name, im, origin, fname, p))

    n = len(clip_rows)
    atlas_h = 4096 * n
    if dry_run:
        print(f"[dry-run] would write atlas 2048×{atlas_h} → {game / 'runtime-atlas.png'}")
    else:
        atlas = Image.new("RGBA", (2048, atlas_h), (0, 0, 0, 0))
        for i, (_name, im, _origin, _fname, _p) in enumerate(sheets):
            atlas.paste(im, (0, i * 4096))
        game.mkdir(parents=True, exist_ok=True)
        out_png = game / "runtime-atlas.png"
        atlas.save(out_png, optimize=True)
        print(f"wrote {out_png} {atlas.size}")
        for dest in (src, res):
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy2(out_png, dest / "runtime-atlas.png")

        for _name, fname, _origin in [(c, f, o) for c, f, o in clip_rows]:
            src_png = src / fname if (src / fname).exists() else game / fname
            src_json = src_png.with_suffix(".json")
            for dest in (game, res):
                dest.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src_png, dest / fname)
                if src_json.exists():
                    shutil.copy2(src_json, dest / src_json.name)

    clips_meta: dict = {
        "idle": {
            "frames": 1,
            "fps": 1,
            "loop": True,
            "source": f"{clips[0]}_f0_hold" if clips else "walk_f0_hold",
            "originRow": 0,
        },
    }
    provenance_files: dict = {}
    for clip_name, fname, origin in clip_rows:
        clips_meta[clip_name] = {
            "frames": 8,
            "fps": 10,
            "loop": True,
            "source": "real",
            "originRow": origin,
        }
        provenance_files[clip_name] = fname

    equip = ROOT / "assets/sprites" / unit / "citizen_equipment_states.json"
    if not equip.exists():
        equip = ROOT / "assets/sprites" / unit / f"{unit}_equipment_states.json"

    manifest = {
        "schema": "sunfold.sprite-manifest/1",
        "unit": unit,
        "characterName": name,
        "playback": "atlas",
        "frameWidth": 256,
        "frameHeight": 256,
        "fps": 10,
        "mirrorAtRuntime": False,
        "premultipliedAlpha": True,
        "anchor": {
            "x": 0.5,
            "y": 0.899414,
            "semantics": "feet_baseline_center_top_origin",
            "threeJsCenterBottomOrigin": {"x": 0.5, "y": 0.100586},
            "note": "plane footroom = 1 - anchor.y ≈ 0.10; equivalent to center.set(0.5, 0.10)",
        },
        "unitHeightMeters": 1.75,
        "worldHeight": 2.45,
        "facings": FACINGS,
        "directionCount": 16,
        "facingConvention": "FACINGS_16 clockwise from south (+Z), 22.5°; use yawToFacing16",
        "atlas": {
            "image": "runtime-atlas.png",
            "width": 2048,
            "height": atlas_h,
            "columns": 8,
            "rows": 16 * n,
            "layout": "facing-grid",
            "runtimeCellPx": 256,
        },
        "clips": clips_meta,
        "provenance": {
            **provenance_files,
            "equipmentContract": str(equip.relative_to(ROOT)) if equip.exists() else None,
            "geminiUsed": False,
            "note": (
                ", ".join(f"{c} {o}-{o + 15}" for c, _f, o in clip_rows)
                + "; fixed feet; no per-pose recenter"
            ),
            "packedBy": "pack-unit-combined-atlas.py",
        },
    }
    text = json.dumps(manifest, indent=2) + "\n"
    if dry_run:
        print(f"[dry-run] would write atlas-manifest.json / Citizen.sprite.json → {game}, {src}, {res}")
        print("clips originRow:", {k: v["originRow"] for k, v in clips_meta.items()})
    else:
        for dest in (game, src, res):
            dest.mkdir(parents=True, exist_ok=True)
            (dest / "atlas-manifest.json").write_text(text)
            (dest / "Citizen.sprite.json").write_text(text)
        print("clips originRow:", {k: v["originRow"] for k, v in clips_meta.items()})
    return manifest


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--unit", required=True, help="Unit id, e.g. village-manbun-wanderer")
    ap.add_argument(
        "--clips",
        default=",".join(DEFAULT_CLIPS),
        help="Comma-separated clip names in atlas stack order",
    )
    ap.add_argument("--prefix", default="Citizen", help="Sheet filename prefix (Citizen_Walk_…)")
    ap.add_argument("--character-name", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    clips = [c.strip() for c in args.clips.split(",") if c.strip()]
    if not clips:
        raise SystemExit("--clips must list at least one clip")
    pack(
        unit=args.unit,
        clips=clips,
        prefix=args.prefix,
        character_name=args.character_name,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
