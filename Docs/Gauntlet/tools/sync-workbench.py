#!/usr/bin/env python3
"""Inline workbench-data.json into workbench.html so the page opens from file://.

`workbench.html` fetches `workbench-data.json` at runtime, which works when the
folder is served over HTTP but is blocked by every browser when the page is opened
directly as a `file://` URL. The page therefore carries an inline copy of the same
payload as a fallback, and this script keeps that copy in step.

Run it after every edit to workbench-data.json:

    python3 Docs/Gauntlet/tools/sync-workbench.py

It rewrites only the text between the INLINE_DATA_START / INLINE_DATA_END markers.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
HTML = ROOT / "workbench.html"
DATA = ROOT / "workbench-data.json"

PATTERN = re.compile(
    r"(/\* INLINE_DATA_START \*/).*?(/\* INLINE_DATA_END \*/)",
    re.DOTALL,
)


def main() -> int:
    if not HTML.exists() or not DATA.exists():
        print(f"missing {HTML if not HTML.exists() else DATA}", file=sys.stderr)
        return 1

    try:
        payload = json.loads(DATA.read_text())
    except json.JSONDecodeError as e:
        print(f"workbench-data.json is not valid JSON: {e}", file=sys.stderr)
        return 1

    html = HTML.read_text()
    if not PATTERN.search(html):
        print("INLINE_DATA markers not found in workbench.html", file=sys.stderr)
        return 1

    # `</script>` inside a string literal would close the enclosing script tag.
    literal = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
    html = PATTERN.sub(lambda m: f"{m.group(1)} {literal} {m.group(2)}", html, count=1)
    HTML.write_text(html)

    print(f"inlined {len(literal):,} chars · "
          f"{len(payload.get('log', []))} log entries · "
          f"{len(payload.get('bars', []))} bars")
    return 0


if __name__ == "__main__":
    sys.exit(main())
