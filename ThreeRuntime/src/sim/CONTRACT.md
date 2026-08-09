# Simulation module contract — Three.js runtime (issue #22)

Every system in `ThreeRuntime/src/sim/` codes against exactly this. It is pinned
before any system is written so parallel work cannot disagree about state shape,
iteration order or ownership.

## Non-negotiable rules

1. **Fixed 20 Hz.** A system receives `deltaTime` (always `1/20`) or a tick
   count. No system may read `performance.now()`, `Date`, or any frame timing.
2. **Determinism.** No `Math.random()`. Randomness comes only from
   `state.random.stream(tag)` on a tag registered in `rng.js`.
3. **Iteration order.** Every loop over entities walks `store.orderedIDs()` or
   `store.ordered()` — ascending entity id. Never `Map` insertion order, never
   `Object.keys`.
4. **Ties break by id.** Any "nearest", "best" or "first" selection that can tie
   must break the tie on ascending entity id.
5. **No new gameplay enums.** `ACTIVITY_TAGS` in `types.js` is closed. Animation
   detail lives in the controller substates of `animation.js`.
6. **Nothing is silently destroyed.** Resources, cargo and construction progress
   are conserved or explicitly refunded. Never delete a load to simplify a case.
7. **Mutate in place.** Systems mutate the entity objects held by the store and
   call `store.set(id, entity)` only when replacing or adding. Adding or
   removing an entity invalidates the store's order cache automatically.

## State shape

```js
state = {
  seed: { hi, lo },                  // 64-bit, from rng.js seedFrom()
  mapID: "riverlands",
  playerFaction: "sunwoven",
  clock: SimulationClock,            // clock.js — .tick, .elapsed, .stepDuration
  random: RandomStreams,             // rng.js
  allocator: EntityIDAllocator,      // ids.js
  map: WorldMap,                     // world.js
  stock: { sunwoven: Pool, gravemark: Pool },
  age: { sunwoven: "foundation", gravemark: "foundation" },
  units: EntityStore,                // ids.js
  buildings: EntityStore,
  deposits: EntityStore,
  productionQueues: Map<number, {
    items: [{ kind, progressTicks, hasStarted }],
    heldReason: null | "populationCap" | "noSpawnPosition"
  }>,
  events: EventLog,                  // events.js
  paused: boolean
}
```

`Pool` is `{ provisions, matter, lumen, aether }` from `types.js`.
A world point is `{ x, z }`. There is no `y` — the ground plane is XZ.

### Unit

```js
{
  id, faction, kind,
  position: { x, z },
  destination: { x, z } | null,
  movementPath: [{ x, z }],
  movementPathTarget: { x, z } | null,
  facing: number,                    // radians about Y
  activity: { tag, subject },        // types.js activity(); subject is an id or null
  life: number,
  region: string | null,
  carrying: [id],                    // transports only
  cargo: { kind, amount } | null,    // one resource kind at a time
  assignment: id | null,             // the deposit this citizen keeps returning to
  boardingProgress: number,
  animation: {
    state: string,                   // animation.js controller substate
    loopIndex: number,               // 0..3 — which of the three contact loops
    phaseTicks: number,              // ticks elapsed inside the current substate
    leadHand: "left" | "right" | "none",
    toolHeld: "scraper" | "mallet" | null,
    carriedChunks: number,           // 0..3 committed chunks visible on the carrier
    airborneChunks: [{ kind, amount, remainingTicks }]
  }
}
```

### Building

```js
{ id, faction | null, kind, position, region, life, constructionProgress, installedComponents }
```

`installedComponents` is 0..3 — the three neutral frame pieces #20 locks with
`construct_contact`. `constructionProgress` stays the continuous 0…1 rule.

### Deposit

```js
{ id, kind, position, region, remaining, chunksRemaining }
```

`chunksRemaining` is the visible loose pile, 0..3, decremented at each
`gather_contact` and refilled to 3 when it empties while yield remains.

## Module ownership — no file is written by two owners

| File | Owner | Exports |
|---|---|---|
| `int64.js` `rng.js` `clock.js` `hash.js` `ids.js` `types.js` `tuning.js` `kinds.js` `events.js` | lead | done — read only |
| `world.js` `populate.js` | B22-WORLD | `WorldMap`, `populate(state)` |
| `movement.js` | B22-MOVE | `MovementSystem` |
| `gathering.js` `animation.js` | B22-WORK | `GatheringSystem`, `AnimationController` |
| `construction.js` `production.js` | B22-BUILD | `ConstructionSystem`, `ProductionSystem` |
| `simulation.js` `snapshot.js` | lead | orchestration |
| `tests/**` | B22-TEST | determinism suite |

## Required exports

### `world.js`

```js
export class WorldMap {
  static create(mapID, random)         // random = state.random.stream("world.populate")
  bounds                               // { minX, maxX, minZ, maxZ }
  isLand(point) -> boolean
  region(point) -> RegionID | null     // null when off-map or on void
  clampToLand(point, margin) -> { x, z } | null
  regionAnchor(regionID) -> { x, z }
  landCoverage() -> number             // fraction of bounds that is land
}
export const MAP_IDS = ["riverlands", "basin", "fjords"];
```

The map must be a pure function of `(mapID, seed)`, so a snapshot stores only
those two and rebuilds the rest.

### `populate.js`

```js
export function populate(state)   // seeds units, buildings, deposits, allocator
```

### `movement.js`

```js
export const MovementSystem = {
  resolveDestination(point, unit, state) -> { x, z } | null,
  resolveOrder(point, unit, state) -> { destination, waypoints } | null,
  step(state, deltaTime) -> void
};
```

### `gathering.js`

```js
export const GatheringSystem = {
  step(state, deltaTime) -> void,
  orderGather(state, unitIDs, depositID) -> void,
  workStation(deposit, unit) -> { x, z },
  isFull(unit) -> boolean
};
```

### `animation.js`

```js
export const AnimationController = {
  create() -> animation,                       // the initial animation block
  step(state, deltaTime) -> void,              // advances substates, fires events
  requestInterrupt(state, unit) -> boolean,    // true when cleanup is now running
  isBusy(unit) -> boolean
};
export const CITIZEN_ANIMATION_STATES = [...];
```

### `construction.js`

```js
export const ConstructionSystem = {
  step(state, deltaTime) -> void,
  workRadius(buildingKind) -> number,
  assignBuilders(state, buildingID, faction, preferredIDs) -> number,
  placeBuilding(state, kind, point, faction, preferredIDs) -> id | null,
  cancelConstruction(state, buildingID) -> boolean,
  buildBlocker(state, kind, faction) -> { reason, ... } | null,
  maxBuildersPerSite                             // 4
};
```

### `production.js`

```js
export const ProductionSystem = {
  step(state) -> void,
  enqueue(state, kind, buildingID) -> { ok: true } | { ok: false, reason },
  cancelFront(state, buildingID) -> boolean,
  populationCommitment(state, faction) -> { used, cap },
  onBuildingDestroyed(state, buildingID) -> void,
  progress(state, buildingID) -> number
};
```

## Step order

`simulation.js` runs exactly this order every tick, matching the Swift original:

1. Core trickle for both factions
2. `GatheringSystem.step`
3. `ConstructionSystem.step`
4. `MovementSystem.step`
5. `ProductionSystem.step`
6. `AnimationController.step` — last, so it reacts to the state this tick produced

Combat, adversary AI, boarding, fog and victory are **deferred** in this
migration and recorded as such in the migration matrix. Do not stub them with
invented rules.
