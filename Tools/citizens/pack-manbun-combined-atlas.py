#!/usr/bin/env python3
"""Back-compat wrapper — prefer pack-unit-combined-atlas.py --unit village-manbun-wanderer."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location(
    "pack_unit_combined_atlas",
    _HERE / "pack-unit-combined-atlas.py",
)
_mod = importlib.util.module_from_spec(_SPEC)
assert _SPEC and _SPEC.loader
sys.modules["pack_unit_combined_atlas"] = _mod
_SPEC.loader.exec_module(_mod)


def pack_manbun() -> None:
    _mod.pack(
        unit="village-manbun-wanderer",
        clips=["walk", "carry", "gather", "build"],
        prefix="Citizen",
        character_name="Village Man-Bun Wanderer",
    )


if __name__ == "__main__":
    pack_manbun()
