# RTS Space Maps — Architecture

Concept reference: `Docs/Art/rts-map-concepts.png`

## Goal

Data-driven RTS space maps that produce **playable gameplay spaces**, not visual-only scenes. Maps declare terrain, spawns, resources, objectives, bridges, hazards, and AI hints; runtime systems interpret the data.

## Framework

```
MapDefinition (data)
    ├── TerrainGenerator   → Three.js platform meshes + bridges + debris
    ├── ResourceSpawner    → harvestable nodes
    ├── PlayerSpawnManager → 4-player start positions
    ├── ObjectiveManager   → capture zones (solar core)
    ├── PathGraph          → A* navigation with bridge gating
    ├── HazardSystem       → solar flares, temporary bridge disable
    └── AIHints            → strategic metadata for AI / debug
```

Orchestrator: `ThreeRuntime/src/rts-maps/rts-map-world.js` → `createRtsMapWorld(mapId, scene)`.

Registry: `ThreeRuntime/src/rts-maps/maps/index.js`

## Reused from existing engine

| System | Source | Use |
|--------|--------|-----|
| RTS camera | `rts-camera.js` | AoE-style pan/zoom |
| Sprite units | `sprites/sprite-unit.js` | Citizen presentation |
| Resource kinds | `sim/types.js` (conceptual) | provisions/matter/lumen/aether + energy_materials |
| Build pipeline | `scripts/build-labs.mjs` | Bundle proof pages |

**Not duplicated:** `mapgen/mapgen.js` (fantasy continent procgen) and `sim/world.js` (land/water plates) stay separate — space maps use the new `rts-maps` layer.

## Map 1: Helios Rift (playable)

- **Theme:** Broken orbital ring around a dying star
- **Layout:** 4 ring fragments (N/E/S/W), central solar core, 4 expansion islets, 8 bridges (4 broken initially)
- **Mechanics:** repairable bridges, solar core capture, periodic solar flares
- **Proof scene:** `helios-rift-proof.html`

### Stubs (not playable)

- `lumen-basin` — registry entry only
- `orekhar-frontier` — registry entry only

## Files added / modified

**New:**
- `ThreeRuntime/src/rts-maps/*` — framework modules
- `ThreeRuntime/src/rts-maps/maps/helios-rift.js`
- `ThreeRuntime/src/helios-rift-proof.js` + `.html`
- `Docs/Art/rts-map-concepts.png`
- This doc

**Modified:**
- `ThreeRuntime/scripts/build-labs.mjs` — bundle Helios Rift proof

## Run Helios Rift

```bash
cd SunfoldGreenfield-threejs-wkwebview/ThreeRuntime
npm run build:labs
npx --yes serve assets/citizens -p 4177
# Open http://localhost:4177/helios-rift-proof
```

**Controls:** Left-click select · Right-click move/gather/repair · Repair button · AI hints → console (`window.__heliosRiftProof.getAIHints()`).

## Acceptance (Helios Rift)

| Criterion | Status |
|-----------|--------|
| Players spawn (4 starts) | ✅ |
| Units navigate (path graph + bridges) | ✅ |
| Resources exist (8 nodes + core) | ✅ |
| Expansions matter (corner islets, aether/energy) | ✅ |
| Objectives create conflict (solar core capture) | ✅ |
| AI hints exposed (JSON via API + button) | ✅ |
| Map feels different from flat grass proof | ✅ (ring void, bridges, flares) |

## Next steps (out of scope)

- Wire `RtsMapWorld` into full `SimulationSession` / Swift bridge
- Lumen Basin + Orekhar Frontier implementations
- Visual polish (shaders, megastructure art) after gameplay lock
