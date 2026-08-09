#!/usr/bin/env python3
"""Bootstrap Sunwoven Weaver sprite facings from Codex construction refs.

HD visual source of truth: four Codex turnaround plates (Aug 2026).
Navy keyed to RGBA via sprite_key.py; native resolution preserved (1024² or iso native).

Real idle facings (from Codex):
  0 S  — front A-pose
  1 SE — iso ¾ gather pose
  2 E  — side turnaround (character crop from prop sheet)
  4 N  — back turnaround
  3 NE — stub: SE placeholder until Blender HD bake
  5 NW — mirror of NE (runtime mirrors E-side art)
  6 W  — mirror of E (runtime mirrors)
  7 SW — mirror of SE (runtime mirrors)

Walk/gather/build hold HD idle until real HD anim frames exist — no low-poly bakes.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sprite_key import key_codex_plate_to_rgba  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.expanduser(
    "~/.cursor/projects/Users-prateekranka-Claude-Projects-aoe-space-edition/assets"
)
OUT = os.path.join(REPO, "ThreeRuntime", "assets", "citizens", "sprites", "sunwoven-weaver")

# Codex attachment timestamps → view role
CODEX_PATTERNS = {
    "front": "09_14_56",
    "side": "09_15_34",
    "back": "09_15_44",
    "threequarter": "09_15_52",
}

# Side prop sheet — crop character column only (right half of 1024² sheet).
SIDE_CROP = {"x": 500, "y": 0, "w": 524, "h": 1024}


def _find_codex_ref(token: str) -> str | None:
    if not os.path.isdir(ASSETS):
        return None
    matches = sorted(
        p
        for name in os.listdir(ASSETS)
        if name.startswith("Codex_Image") and token in name
        for p in [os.path.join(ASSETS, name)]
        if os.path.isfile(p)
    )
    return matches[-1] if matches else None


def _resolve_sources() -> dict[str, str]:
    sources: dict[str, str] = {}
    for key, token in CODEX_PATTERNS.items():
        path = _find_codex_ref(token)
        if not path:
            raise FileNotFoundError(f"Missing Codex ref for {key} (pattern *{token}*) under {ASSETS}")
        sources[key] = path
    return sources


def _run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def _copy_native(src: str, dst: str) -> None:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def _crop_native(src: str, dst: str, x: int, y: int, w: int, h: int) -> None:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".crop.png"
    _run(["sips", "-c", str(h), str(w), src, "--cropOffset", str(y), str(x), "--out", tmp])
    shutil.move(tmp, dst)


def _finalize_png(path: str) -> None:
    key_codex_plate_to_rgba(path)


def _copy_clip_idle(src_facing: int, clip: str, facing: int) -> None:
    src = os.path.join(OUT, "idle", f"{src_facing}.png")
    dst = os.path.join(OUT, clip, f"{facing}.png")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def _probe_size(path: str) -> tuple[int, int]:
    out = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
        text=True,
    )
    w = h = 0
    for line in out.splitlines():
        if "pixelWidth" in line:
            w = int(line.split()[-1])
        if "pixelHeight" in line:
            h = int(line.split()[-1])
    return w, h


def main() -> int:
    sources = _resolve_sources()
    print("[bootstrap-sprites] Codex HD refs:")
    for key, path in sources.items():
        w, h = _probe_size(path)
        print(f"  {key}: {os.path.basename(path)} ({w}×{h})")

    idle_dir = os.path.join(OUT, "idle")
    os.makedirs(idle_dir, exist_ok=True)

    # 0 S — front (native 1024²)
    _copy_native(sources["front"], os.path.join(idle_dir, "0.png"))
    # 4 N — back
    _copy_native(sources["back"], os.path.join(idle_dir, "4.png"))
    # 2 E — side character crop
    crop = SIDE_CROP
    _crop_native(
        sources["side"],
        os.path.join(idle_dir, "2.png"),
        x=crop["x"],
        y=crop["y"],
        w=crop["w"],
        h=crop["h"],
    )
    # 1 SE — iso gather (native, may be smaller than 1024)
    _copy_native(sources["threequarter"], os.path.join(idle_dir, "1.png"))
    # 3 NE — stub until HD bake
    shutil.copy2(os.path.join(idle_dir, "1.png"), os.path.join(idle_dir, "3.png"))
    # Mirrored facings — runtime mirrors; files kept for offline completeness
    shutil.copy2(os.path.join(idle_dir, "3.png"), os.path.join(idle_dir, "5.png"))
    shutil.copy2(os.path.join(idle_dir, "2.png"), os.path.join(idle_dir, "6.png"))
    shutil.copy2(os.path.join(idle_dir, "1.png"), os.path.join(idle_dir, "7.png"))

    # Key every idle PNG → true RGBA
    for i in range(8):
        _finalize_png(os.path.join(idle_dir, f"{i}.png"))

    # Walk/gather/build: HD idle hold — single-frame stub (no low-poly bakes)
    for clip in ("walk", "gather", "build"):
        clip_dir = os.path.join(OUT, clip)
        if os.path.isdir(clip_dir):
            shutil.rmtree(clip_dir)
        os.makedirs(clip_dir, exist_ok=True)
        for facing in range(8):
            src_facing = 0 if facing in (0, 3, 4, 5) else facing
            _copy_clip_idle(src_facing, clip, facing)
            _finalize_png(os.path.join(clip_dir, f"{facing}.png"))

    # Manifest frame size = dominant Codex plate (1024² turnarounds)
    frame_w, frame_h = _probe_size(os.path.join(idle_dir, "0.png"))

    manifest = {
        "schema": "sunfold.sprite-manifest/1",
        "unit": "sunwoven-weaver",
        "frameWidth": frame_w,
        "frameHeight": frame_h,
        "fps": 10,
        "facings": ["S", "SE", "E", "NE", "N", "NW", "W", "SW"],
        "camera": {
            "pitchDegrees": 57,
            "yawDegrees": 45,
            "fovDegrees": 38,
            "note": "Must match ThreeRuntime/src/rts-camera.js and Tools/citizens/bake_sprites.py",
        },
        "clips": {
            "idle": {
                "frames": 1,
                "loop": True,
                "source": "real",
                "note": "HD Codex turnarounds — native resolution RGBA",
                "facingsReal": [0, 1, 2, 4],
                "facingsMirrored": [5, 6, 7],
                "facingsStubbed": [3],
            },
            "walk": {
                "frames": 1,
                "loop": True,
                "source": "stub",
                "note": "Holds HD idle; awaiting real HD walk frames",
            },
            "gather": {
                "frames": 1,
                "loop": True,
                "source": "partial",
                "note": "SE idle is Codex gather iso; other facings hold HD idle until bake",
            },
            "build": {
                "frames": 1,
                "loop": True,
                "source": "stub",
                "note": "Holds HD idle; awaiting real HD build frames",
            },
        },
        "bootstrap": {
            "refs": {k: os.path.relpath(v, REPO) if v.startswith(REPO) else v for k, v in sources.items()},
            "generatedBy": "Tools/citizens/bootstrap-sunwoven-sprites.py",
            "hdSource": "codex-aug-2026",
        },
    }
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    print(f"[bootstrap-sprites] wrote {OUT} — HD idle {frame_w}×{frame_h}, walk/gather/build stubbed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
