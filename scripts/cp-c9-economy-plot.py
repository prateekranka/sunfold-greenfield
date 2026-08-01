#!/usr/bin/env python3
"""Render deterministic CP-C9 economy evidence as an SVG."""

from __future__ import annotations

import csv
import html
import math
import sys
from pathlib import Path


WIDTH = 1280
HEIGHT = 820
LEFT = 84
RIGHT = 230
PLOT_WIDTH = WIDTH - LEFT - RIGHT
PANEL_HEIGHT = 184
PANEL_GAP = 58

STOCK_SERIES = (
    ("stock_provisions", "Provisions", "#d5a247"),
    ("stock_matter", "Matter", "#86a8ba"),
    ("stock_lumen", "Lumen", "#e9d36a"),
    ("stock_aether", "Aether", "#a78ee8"),
)
HOME_SERIES = (
    ("home_provisions_remaining", "Provisions", "#d5a247"),
    ("home_matter_remaining", "Matter", "#86a8ba"),
    ("home_lumen_remaining", "Lumen", "#e9d36a"),
    ("home_aether_remaining", "Aether", "#a78ee8"),
)


def parse_number(value: str) -> float:
    lowered = value.strip().lower()
    if lowered in {"infinity", "+infinity", "inf", "+inf"}:
        return math.inf
    if lowered in {"-infinity", "-inf"}:
        return -math.inf
    return float(value)


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise ValueError(f"{path} contains no samples")
    return rows


def finite_values(rows: list[dict[str, str]], field: str) -> list[float]:
    values = [parse_number(row[field]) for row in rows]
    return [value for value in values if math.isfinite(value)]


def scale_max(rows: list[dict[str, str]], fields: tuple[str, ...]) -> float:
    values = [
        value
        for field in fields
        for value in finite_values(rows, field)
    ]
    maximum = max(values, default=1.0)
    if maximum <= 0:
        return 1.0
    if maximum == min(values, default=0.0):
        return maximum * 1.25 if maximum else 1.0
    return maximum * 1.08


def x_position(value: float, maximum: float) -> float:
    return LEFT + (value / maximum) * PLOT_WIDTH if maximum else LEFT


def y_position(value: float, maximum: float, top: float) -> float:
    return top + PANEL_HEIGHT - (value / maximum) * PANEL_HEIGHT


def number_label(value: float) -> str:
    if abs(value) >= 1000:
        return f"{value:,.0f}"
    if abs(value - round(value)) < 1e-9:
        return f"{value:.0f}"
    return f"{value:.1f}"


def escaped(value: str) -> str:
    return html.escape(value, quote=True)


def line_path(
    rows: list[dict[str, str]],
    field: str,
    x_max: float,
    y_max: float,
    top: float,
) -> str:
    commands: list[str] = []
    segment_open = False
    for row in rows:
        x = parse_number(row["match_time_seconds"])
        y = parse_number(row[field])
        if not math.isfinite(y):
            segment_open = False
            continue
        point = f"{x_position(x, x_max):.3f},{y_position(y, y_max, top):.3f}"
        commands.append(("M" if not segment_open else "L") + point)
        segment_open = True
    return " ".join(commands)


def legend(
    series: tuple[tuple[str, str, str], ...],
    x: float,
    y: float,
    dashed: bool = False,
) -> list[str]:
    output: list[str] = []
    for index, (_, label, color) in enumerate(series):
        offset = index * 28
        dash = ' stroke-dasharray="7 5"' if dashed else ""
        output.append(
            f'<line x1="{x:.1f}" y1="{y + offset:.1f}" '
            f'x2="{x + 24:.1f}" y2="{y + offset:.1f}" '
            f'stroke="{color}" stroke-width="3"{dash}/>'
        )
        output.append(
            f'<text x="{x + 34:.1f}" y="{y + offset + 5:.1f}" '
            f'class="legend">{escaped(label)}</text>'
        )
    return output


def panel(
    rows: list[dict[str, str]],
    title: str,
    top: float,
    series: tuple[tuple[str, str, str], ...],
    y_max: float,
    x_max: float,
    dashed: bool = False,
) -> list[str]:
    output = [
        f'<rect x="{LEFT}" y="{top:.1f}" width="{PLOT_WIDTH}" '
        f'height="{PANEL_HEIGHT}" class="panel"/>',
        f'<text x="{LEFT}" y="{top - 16:.1f}" class="panel-title">'
        f'{escaped(title)}</text>',
    ]
    for fraction in (0.0, 0.5, 1.0):
        y = top + PANEL_HEIGHT - fraction * PANEL_HEIGHT
        label = number_label(y_max * fraction)
        output.append(
            f'<line x1="{LEFT}" y1="{y:.1f}" x2="{LEFT + PLOT_WIDTH}" '
            f'y2="{y:.1f}" class="grid"/>'
        )
        output.append(
            f'<text x="{LEFT - 12}" y="{y + 5:.1f}" text-anchor="end" '
            f'class="axis">{escaped(label)}</text>'
        )
    for field, label, color in series:
        path = line_path(rows, field, x_max, y_max, top)
        if path:
            dash = ' stroke-dasharray="7 5"' if dashed else ""
            output.append(
                f'<path d="{path}" fill="none" stroke="{color}" '
                f'stroke-width="3"{dash}/>'
            )
    output.extend(legend(series, LEFT + PLOT_WIDTH + 30, top + 20, dashed))
    return output


def population_panel(
    rows: list[dict[str, str]],
    top: float,
    x_max: float,
) -> list[str]:
    population_max = scale_max(rows, ("population_used", "population_cap"))
    dwelling_max = max(
        1.0,
        max(float(row["completed_dwellings"]) for row in rows) * 1.2,
    )
    output = [
        f'<rect x="{LEFT}" y="{top:.1f}" width="{PLOT_WIDTH}" '
        f'height="{PANEL_HEIGHT}" class="panel"/>',
        f'<text x="{LEFT}" y="{top - 16:.1f}" class="panel-title">'
        "Population and completed Dwellings</text>",
    ]
    for fraction in (0.0, 0.5, 1.0):
        y = top + PANEL_HEIGHT - fraction * PANEL_HEIGHT
        left_label = number_label(population_max * fraction)
        right_label = number_label(dwelling_max * fraction)
        output.append(
            f'<line x1="{LEFT}" y1="{y:.1f}" x2="{LEFT + PLOT_WIDTH}" '
            f'y2="{y:.1f}" class="grid"/>'
        )
        output.append(
            f'<text x="{LEFT - 12}" y="{y + 5:.1f}" text-anchor="end" '
            f'class="axis">{escaped(left_label)}</text>'
        )
        output.append(
            f'<text x="{LEFT + PLOT_WIDTH + 12}" y="{y + 5:.1f}" '
            f'class="axis">{escaped(right_label)}</text>'
        )

    for field, color, dashed in (
        ("population_used", "#f0eee8", False),
        ("population_cap", "#8f8c83", True),
        ("completed_dwellings", "#d5a247", False),
    ):
        maximum = dwelling_max if field == "completed_dwellings" else population_max
        path = line_path(rows, field, x_max, maximum, top)
        if path:
            dash = ' stroke-dasharray="7 5"' if dashed else ""
            output.append(
                f'<path d="{path}" fill="none" stroke="{color}" '
                f'stroke-width="3"{dash}/>'
            )

    entries = (
        ("Population used", "#f0eee8", False),
        ("Population cap", "#8f8c83", True),
        ("Dwellings", "#d5a247", False),
    )
    for index, (label, color, dashed) in enumerate(entries):
        y = top + 20 + index * 28
        dash = ' stroke-dasharray="7 5"' if dashed else ""
        output.append(
            f'<line x1="{LEFT + PLOT_WIDTH + 30}" y1="{y:.1f}" '
            f'x2="{LEFT + PLOT_WIDTH + 54}" y2="{y:.1f}" '
            f'stroke="{color}" stroke-width="3"{dash}/>'
        )
        output.append(
            f'<text x="{LEFT + PLOT_WIDTH + 64}" y="{y + 5:.1f}" '
            f'class="legend">{escaped(label)}</text>'
        )
    return output


def render(rows: list[dict[str, str]], source: Path) -> str:
    x_max = max(
        1.0,
        max(parse_number(row["match_time_seconds"]) for row in rows),
    )
    stock_max = scale_max(rows, tuple(field for field, _, _ in STOCK_SERIES))
    home_max = scale_max(rows, tuple(field for field, _, _ in HOME_SERIES))
    stock_top = 104.0
    home_top = stock_top + PANEL_HEIGHT + PANEL_GAP
    population_top = home_top + PANEL_HEIGHT + PANEL_GAP
    x_ticks = (0.0, x_max / 2.0, x_max)
    output = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" '
        f'height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
        "<title>Sunfold CP-C9 economy evidence</title>",
        "<style>",
        "text { font-family: -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif; }",
        ".title { fill: #f0eee8; font-size: 24px; font-weight: 700; }",
        ".subtitle { fill: #a8a49b; font-size: 13px; }",
        ".panel-title { fill: #f0eee8; font-size: 16px; font-weight: 700; }",
        ".axis { fill: #a8a49b; font-size: 12px; }",
        ".legend { fill: #d4d0c6; font-size: 13px; }",
        ".grid { stroke: #383a3d; stroke-width: 1; }",
        ".panel { fill: #17191b; stroke: #424449; stroke-width: 1; }",
        ".x-axis { fill: #a8a49b; font-size: 12px; }",
        "</style>",
        '<rect width="100%" height="100%" fill="#0c0d0f"/>',
        f'<text x="{LEFT}" y="42" class="title">Sunfold CP-C9 economy evidence</text>',
        f'<text x="{LEFT}" y="66" class="subtitle">{escaped(source.name)}</text>',
    ]
    output.extend(panel(rows, "Treasury stock", stock_top, STOCK_SERIES, stock_max, x_max))
    output.extend(
        panel(
            rows,
            "Home remaining yield",
            home_top,
            HOME_SERIES,
            home_max,
            x_max,
            dashed=True,
        )
    )
    output.extend(population_panel(rows, population_top, x_max))
    for value in x_ticks:
        x = x_position(value, x_max)
        output.append(
            f'<line x1="{x:.1f}" y1="{population_top + PANEL_HEIGHT}" '
            f'x2="{x:.1f}" y2="{population_top + PANEL_HEIGHT + 7}" '
            'stroke="#a8a49b" stroke-width="1"/>'
        )
        output.append(
            f'<text x="{x:.1f}" y="{population_top + PANEL_HEIGHT + 28}" '
            f'text-anchor="middle" class="x-axis">{number_label(value)} s</text>'
        )
    output.append(
        f'<text x="{LEFT + PLOT_WIDTH / 2:.1f}" y="{HEIGHT - 18}" '
        'text-anchor="middle" class="subtitle">Match time</text>'
    )
    output.append(
        f'<text x="{WIDTH - RIGHT + 30}" y="{HEIGHT - 18}" class="subtitle">'
        "Home Provisions is renewable (∞ values omitted)</text>"
    )
    output.append("</svg>")
    return "\n".join(output) + "\n"


def main(arguments: list[str]) -> int:
    if len(arguments) not in (2, 3):
        print(
            "usage: cp-c9-economy-plot.py INPUT.csv [OUTPUT.svg]",
            file=sys.stderr,
        )
        return 2
    source = Path(arguments[1])
    destination = Path(arguments[2]) if len(arguments) == 3 else source.with_suffix(".svg")
    svg = render(read_rows(source), source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(svg, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
