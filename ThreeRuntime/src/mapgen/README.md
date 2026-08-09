# mapgen — procedural WorldMap generator for Sunfold Greenfield

A deterministic, dependency-free generator for the playable first-slice map,
implementing the documented `WorldMap` contract (AGENTS.md CP-14,
PROJECT_STATE.md, Docs/Design/00-CONTENT-SPEC.md). All visuals are generated
from code — no project art is referenced.

## Contract implemented

| Rule (from the docs) | Where |
|---|---|
| One continent cut by void water (not disc unions) | `buildLand`: gaussian coast lobes + river/lake/inlet carves + morphological erosion |
| Land coverage 75–80% of `WorldMap.bounds` | iterative lobe-scale solve to 0.775 (see `generateMap`) |
| Cores equidistant from the Dominion; asymmetry allowed | anchors: Sunwoven `(-32,14)`, Gravemark `(32,-14)`, Dominion `(0,0)` — 34.9 m both |
| Land is civilization-independent | one neutral land palette in the renderer; faction livery only on cores |
| Provisions+Matter+Lumen on home; **Aether only on expansions/Dominion/neutrals** | `anchorsFor` deposit plans |
| Docks on the outer coast via a deterministic void finder | `findDock` (lane-line biased) |
| Causeway spars only across the wet stretch, never a dry slab | `buildSpars`: wet-run chunks along the dock-to-dock line |
| Home↔expansion lanes dormant until the Outpost weaves them; expansion↔Dominion spine always open | `causeways[].dormant` |
| Determinism: locked seed `20260726`, tagged per-subsystem streams | `rng.js` (`stream(seed, tag)`) |
| Relief ≤ 2 m, settlement plazas flat, banks low | `buildHeights` |
| Conquest strike route home↔home stays open | asserted (A10) |

## Layouts

- `riverlands` (default) — branching bays + flank tarns
- `basin` — great lake ring around the Dominion island, arm channels,
  always-open causeway spine over the ring
- `fjords` — deep sounds; peninsula necks

## Files

- `rng.js` — mulberry32, tagged streams, value noise, FNV-1a
- `mapgen.js` — the generator (`generateMap`, `determinismCheck`, `debugScale`)
- `verify.mjs` — node-side assertion runner (mirrors the lab panel)
- `map-lab.html` — standalone three.js viewer + minimap + assertion panel;
  needs the repo's `node_modules/three` (three r0.178)

## Run

```bash
# from ThreeRuntime/
python3 -m http.server 8123 --directory .
# open http://localhost:8123/src/mapgen/map-lab.html
# URL params: ?layout=riverlands|basin|fjords&seed=20260726&weave=1&view=opening|overview
```

Headless capture (software WebGL):

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --disable-gpu --enable-unsafe-swiftshader --use-gl=angle --use-angle=swiftshader \
  --screenshot=out.png --window-size=1600,1000 --hide-scrollbars --timeout=12000 \
  "http://localhost:8123/src/mapgen/map-lab.html?layout=riverlands&view=opening"
```

Contract check:

```bash
node src/mapgen/verify.mjs          # all layouts, locked seed
node src/mapgen/verify.mjs 42       # any other seed
```

## Evidence

`QA/` holds captures for the locked seed `20260726` (all 11 contract assertions green
in the live browser and in `verify.mjs`):

- `riverlands-overview.png` / `basin-overview.png` / `fjords-overview.png`
- `riverlands-opening.png` — the first-slice view (Sunwoven home)
- `riverlands-opening-woven.png` — dormant home↔expansion causeway decks
  visible after the Outpost weave toggle

### Gauntlet B1b — composition statistics (framestat.py, clean frames)

Bar = concept 01 (`Docs/Concepts/01-sunwoven-foundation-opening.png`).
Pass: `void_frac ≥ 0.35`, `luma_p05 ≤ 0.010`, `dynamic_range ≥ 0.48`,
`sat_mean ≥ 0.42`, `dominant_hue_share ≤ 0.80`.

| frame | void_frac | luma_p05 | dyn_range | sat_mean | hue_share |
|---|---|---|---|---|---|
| concept 01 (bar) | 0.530 | 0.001 | 0.515 | 0.484 | 0.789 |
| riverlands opening | 0.396 | 0.000 | 0.732 | 0.583 | 0.755 |
| basin opening | 0.452 | 0.000 | 0.732 | 0.563 | 0.755 |
| fjords opening | 0.416 | 0.000 | 0.732 | 0.589 | 0.760 |
| riverlands overview | 0.602 | 0.000 | 0.667 | 0.675 | 0.707 |

(All five pass the B1b thresholds on every layout. Latest pass adds:
procedural mountain ranges with ridged peaks, rock-strata colouring and
snow caps, erosion-gully terrain detail, slope rock tinting, valley warmth,
boulders at drainage outlets, a brighter cool fill so long shadows read as
shade — all scenery-only, contract relief stays 2 m.)

### Gauntlet history (fresh blind critic each round)

- **R1 (blind A/B vs concept 01):** backdrop good; geometry judged graybox — flat
  tiled sand with grid seams, lone white dome, pawn figures, ladder bridges.
- **R2:** gap narrowed, not closed — terrain read as a board with sawtooth edges
  and a gray slab underside; pavilion primitive; bloom blown out; turquoise 0.0%.
- **R3:** metrics passed for the first time; "WITH FIXES" — settlement still
  leaked editor tells (concentric rings = selection UI, floating icon glows,
  plank bridges), turquoise functionally absent, gas giant read blue-cold.
- **R4:** final pass verdict (see `QA/` + the round summary in this repo).

Round-3/4 fixes: tapered strata underside, slope-shaded dunes, coast rim lip,
scalloped map borders, saffron canopy + gold ribs + spire + turquoise banners,
sunburst plaza rosette (no selection-UI rings), robed citizens with T-staffs,
woven golden causeways, warm gas giant, tamed bloom, contact shadows.

How it was reached: documented RTS camera (57° pitch / ~42° yaw / 38° FOV,
look-at 0.9 m), island-fills-half framing with the map rim and sky in shot,
wide void channels (P1 lever), sparse purple nebula at authored opacity ~0.55,
warm gas giant, ACES + bloom (threshold 0.88) + gentle vignette.

## Wiring notes (future)

The generator is pure logic with no three.js dependency: `generateMap` returns
flat `land`/`heights`/`regions` arrays plus deposits/docks/causeways in world
coordinates. The Swift `WorldMap` contract (bounds `[118,86]`→`120×90`, step
1.5 m, seed `20260726`) can be fed directly from `map.json` if the simulator
should stop authoring the field by hand.
