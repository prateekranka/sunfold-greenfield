#!/usr/bin/env python3
"""Pack per-frame citizen sprites into runtime-atlas.png + atlas-manifest.json.

The gameplay player reads the atlas (UV animation). The per-frame tree remains
the bake/QA source of truth.

Usage (from repo SunfoldGreenfield-threejs-wkwebview):

    python3 Tools/citizens/pack-runtime-atlas.py
    python3 Tools/citizens/pack-runtime-atlas.py \\
        --sprites ThreeRuntime/assets/citizens/sprites/sunwoven-villager
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


CLIPS = ["idle", "walk", "gather", "build"]


def pack(root: Path) -> None:
    manifest = json.loads((root / "manifest.json").read_text())
    fw, fh = manifest["frameWidth"], manifest["frameHeight"]
    facings = manifest["facings"]
    clips = [c for c in CLIPS if c in manifest["clips"]]
    max_frames = max(manifest["clips"][c]["frames"] for c in clips)
    atlas_w = max_frames * fw
    atlas_h = len(clips) * len(facings) * fh
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

    atlas_clips: dict = {}
    for ci, name in enumerate(clips):
        clip = manifest["clips"][name]
        n = clip["frames"]
        origin_row = ci * len(facings)
        for fi in range(len(facings)):
            for fr in range(n):
                src = root / name / str(fi) / f"{fr}.png"
                alt = root / name / f"{fi}.png"
                path = src if src.exists() else alt
                cell = Image.open(path).convert("RGBA")
                if cell.size != (fw, fh):
                    cell = cell.resize((fw, fh), Image.Resampling.NEAREST)
                atlas.alpha_composite(cell, (fr * fw, (origin_row + fi) * fh))
        entry = {
            "frames": n,
            "fps": clip.get("fps", manifest.get("fps", 10)),
            "loop": clip.get("loop", True),
            "source": clip.get("source", "real"),
            "originRow": origin_row,
        }
        if clip.get("events"):
            entry["events"] = clip["events"]
        atlas_clips[name] = entry

    out = root / "runtime-atlas.png"
    atlas.save(out, optimize=True)
    atlas_manifest = {
        **{k: v for k, v in manifest.items() if k != "clips"},
        "playback": "atlas",
        "atlas": {
            "image": "runtime-atlas.png",
            "width": atlas_w,
            "height": atlas_h,
            "columns": max_frames,
            "rows": len(clips) * len(facings),
        },
        "clips": atlas_clips,
        "provenance": {
            **(manifest.get("provenance") or {}),
            "runtimeAtlas": "Packed from per-frame PNGs for UV playback.",
        },
    }
    (root / "atlas-manifest.json").write_text(json.dumps(atlas_manifest, indent=2) + "\n")
    print(f"wrote {out} ({atlas_w}×{atlas_h})")
    print(f"clips: { {k: v['originRow'] for k, v in atlas_clips.items()} }")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sprites",
        type=Path,
        default=Path("ThreeRuntime/assets/citizens/sprites/sunwoven-villager"),
    )
    args = parser.parse_args()
    pack(args.sprites.resolve())


if __name__ == "__main__":
    main()
