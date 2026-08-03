// Deterministic unit movement.
//
// Ported from `Sources/Simulation/MovementSystem.swift`,
// `Sources/Simulation/ObstacleNavigation.swift` and the facing half of
// `Sources/Simulation/Locomotion.swift`.
//
// The ground plane is XZ. Every world point is `{ x, z }`; the Swift original's
// `SIMD2<Float>` second lane (`.y`) is this file's `z`.
//
// Determinism rules this file obeys, from `CONTRACT.md`:
//
//   * `step` walks `state.units.orderedIDs()` — ascending id, never Map order.
//   * Every "nearest"/"best"/"first" choice breaks its tie on ascending id, or
//     on an ascending fixed index where the candidates are lattice cells.
//   * No `Math.random()`, no clock read. `step` advances purely from the
//     `deltaTime` it is handed, so 600 calls of `1/20` always produce the same
//     positions no matter what the render loop is doing around it.
//   * The Swift movement rules draw no random numbers, so neither does this
//     file. `state.random.stream("movement.jitter")` is deliberately unused:
//     inventing a jitter the original does not have would be a new gameplay
//     rule, not a port. Group spread comes from `formationOffset`, which is a
//     pure function of the unit's slot in the id-sorted selection.
//
// Deviations from the Swift original, each forced and each documented at the
// site that makes it:
//
//   1. Void travel (Light Transport) is not ported. `WorldMap` in this runtime
//      exposes no `isNavigableVoid`/`clampToVoid`, so `planVoid` has no truth to
//      stand on. Void-travelling kinds are refused an order and are never moved,
//      rather than being given invented water rules. See `VOID_TRAVEL_DEFERRED`.
//   2. Swift separates `isStandable` (footprint clear of water) from
//      `isTraversable` (footprint also clear of the outer coast) using a signed
//      land field. This runtime's `WorldMap` exposes only the boolean
//      `isLand(point)`, so both collapse into one disc-sampling predicate,
//      `standable`. See its comment.
//   3. Swift gates the obstacle planner on `unit.kind == .citizen` to avoid
//      disturbing combat chasing in the ticket that introduced it. Combat is
//      deferred in this migration, so there is no chasing to preserve and the
//      contract asks `resolveOrder` for a waypoint path without qualifying by
//      kind. The kind gate is lifted; the *activity* and *stored route* gates
//      that keep gathering and construction on the cheap straight line are kept
//      exactly. See `advance`.
//   4. Facing has no `targetFacing` latch. See `advanceFacing`.
//   5. `resolveDestination` is obstacle-aware. Swift's is terrain-only (its
//      callers pass empty building/deposit dictionaries); the contract for this
//      port requires footprints, deposit work radii and bounds. The obstacle
//      truth is the same `obstaclesFor` set the planner uses, so the two agree.

import { activity, distance } from "./types.js";
import { DEPOSIT_WORK_RADIUS, buildingKind, unitKind } from "./kinds.js";

const TWO_PI = Math.PI * 2;

// MARK: - Constants, all carried across from the Swift source

/** How close counts as arrived on the cheap straight-line route. */
export const ARRIVAL_RADIUS = 0.35;
/** A destination rewritten by less than this is the same destination. */
const DESTINATION_EPSILON = 0.05;
/** A waypoint this close is already reached. */
const WAYPOINT_EPSILON = 0.01;
/** Exact-arrival epsilon on the routed path. */
const ROUTED_ARRIVAL_EPSILON = 0.001;

// ObstacleNavigation
const GRID_SPACING = 1.0;
const LINE_SAMPLE_SPACING = 0.3;
const OBSTACLE_PADDING = 0.25;
/**
 * A deposit's work stations sit just inside its work radius, so the blocker is
 * the work radius minus the visual skirt — otherwise a citizen could never
 * legally reach the node it was sent to.
 */
const DEPOSIT_BLOCKER_RADIUS = DEPOSIT_WORK_RADIUS - 0.15;
const MAX_GRID_CELLS = 16_384;
const DIAGONAL_COST = 1.4142135;

// Terrain clamping
/** Halvings used by the traversable clamp. Swift `clampToTraversable`. */
const TRAVERSABLE_CLAMP_STEPS = 14;
/** Halvings used by the land clamp. Swift `clampToLand`. */
const LAND_CLAMP_STEPS = 8;
/**
 * Points sampled around a footprint when testing whether a unit fits.
 *
 * The Swift map answers "how far is the nearest water" with a signed field and
 * compares it to the footprint radius in one operation. This runtime's map
 * answers only "is this point land", so the disc has to be sampled. Eight
 * points at 45° is the whole boundary at the resolution a 1.15 m footprint
 * needs; the centre is tested separately.
 */
const FOOTPRINT_SAMPLES = 8;

// Obstacle escape search, used only when the segment clamp has nowhere to
// retreat to. Deterministic: radius ascending, then sample index ascending.
const ESCAPE_RING_STEP = 0.5;
const ESCAPE_RING_SAMPLES = 16;
const ESCAPE_RING_HEADROOM = 4;
const ESCAPE_RING_MINIMUM_REACH = 12;

// Locomotion — facing only. Gait, phase and pose are presentation and belong to
// `animation.js`; facing is simulation truth because the contract puts
// `unit.facing` on the unit.
/** Heading change required before a unit re-aims, in radians (12°). */
const FACING_DEADBAND = (12 * Math.PI) / 180;
/** Upper bound on turn speed, radians per second. */
const MAX_TURN_RATE = 6;
/** Below this speed the movement direction is noise, so steering is suspended. */
const STEER_MINIMUM_SPEED = 0.12;
/** Longest step the facing integrator will honour, in seconds. */
const MAX_FACING_DELTA_TIME = 0.25;

/**
 * Void travel is deferred in this migration.
 *
 * `MovementSystem.advanceVoid` / `ObstacleNavigation.planVoid` need
 * `map.isNavigableVoid(point, margin)` and `map.clampToVoid`, neither of which
 * `world.js` exposes under the pinned contract. Rather than invent a water
 * rule, a void-travelling kind is refused an order and never advanced.
 */
const VOID_TRAVEL_DEFERRED = true;

// MARK: - Small pure helpers

function clamp(value, lower, upper) {
  return Math.min(Math.max(value, lower), upper);
}

/** Swift `Float.rounded()` is half-away-from-zero; `Math.round` is half-up. */
function roundHalfAwayFromZero(value) {
  return value < 0 ? -Math.round(-value) : Math.round(value);
}

/** Wraps an angle into (-π, π]. */
function wrapSigned(angle) {
  let wrapped = angle % TWO_PI;
  if (wrapped > Math.PI) wrapped -= TWO_PI;
  if (wrapped <= -Math.PI) wrapped += TWO_PI;
  return wrapped;
}

/** Signed shortest rotation from `from` to `to`, in (-π, π]. */
function shortestAngle(from, to) {
  return wrapSigned(to - from);
}

/**
 * Yaw about +Y that points a unit along `direction`. Zero is north (−Z),
 * matching the map's north-up contract and the mesh rig's authored facing.
 */
function headingOf(direction) {
  return Math.atan2(-direction.x, -direction.z);
}

function lerpPoint(from, to, fraction) {
  return {
    x: from.x + (to.x - from.x) * fraction,
    z: from.z + (to.z - from.z) * fraction
  };
}

function samePoint(a, b) {
  return a.x === b.x && a.z === b.z;
}

function copyPoint(p) {
  return { x: p.x, z: p.z };
}

function isAboard(unit) {
  return !!unit.activity && unit.activity.tag === "aboard";
}

function isMovingActivity(unit) {
  return !!unit.activity && unit.activity.tag === "moving";
}

function isIdleActivity(unit) {
  return !!unit.activity && unit.activity.tag === "idle";
}

/** Arrival from a plain move order returns the unit to idle — and nothing else. */
function finishMoveActivity(unit) {
  if (isMovingActivity(unit)) unit.activity = activity("idle");
}

/** A unit that actually covered ground while idle is, by definition, moving. */
function beginMoveActivity(unit) {
  if (isIdleActivity(unit)) unit.activity = activity("moving");
}

// MARK: - Terrain legality

function withinBounds(map, p) {
  const bounds = map.bounds;
  return p.x >= bounds.minX && p.x <= bounds.maxX && p.z >= bounds.minZ && p.z <= bounds.maxZ;
}

/**
 * Whether a unit of `margin` footprint fits at `point` on dry ground.
 *
 * This is Swift's `isStandable(_:margin:)` and `isTraversable(_:margin:)` fused
 * into one predicate — see deviation 2 at the top of the file. The boundary of
 * the footprint disc is sampled because the only terrain truth this runtime's
 * map publishes is the boolean `isLand`.
 */
function standable(map, point, margin) {
  if (!withinBounds(map, point)) return false;
  if (!map.isLand(point)) return false;
  if (!(margin > 0)) return true;
  for (let index = 0; index < FOOTPRINT_SAMPLES; index += 1) {
    const angle = (index / FOOTPRINT_SAMPLES) * TWO_PI;
    const sample = {
      x: point.x + Math.sin(angle) * margin,
      z: point.z + Math.cos(angle) * margin
    };
    if (!withinBounds(map, sample)) return false;
    if (!map.isLand(sample)) return false;
  }
  return true;
}

/**
 * The last point on the segment `from → proposed` that satisfies `accepts`.
 *
 * Retreating along the attempted move, rather than projecting toward anything,
 * is the rule Swift's `clampToLand`/`clampToTraversable` are built on: a clamp
 * can only ever land somewhere the unit could have walked, so it can never jump
 * a unit across a river or through a wall.
 */
function clampAlongSegment(from, proposed, accepts, steps) {
  if (accepts(proposed)) return copyPoint(proposed);
  if (!accepts(from)) return null;

  let good = copyPoint(from);
  let bad = copyPoint(proposed);
  for (let index = 0; index < steps; index += 1) {
    const middle = lerpPoint(good, bad, 0.5);
    if (accepts(middle)) good = middle;
    else bad = middle;
  }
  return good;
}

/** Swift `WorldMap.clampToLand(_:from:margin:)` — returns `from` when stuck. */
function clampToLandAlongSegment(map, proposed, from, margin) {
  const clamped = clampAlongSegment(
    from,
    proposed,
    (point) => standable(map, point, margin),
    LAND_CLAMP_STEPS
  );
  return clamped === null ? copyPoint(from) : clamped;
}

// MARK: - Dynamic obstacles

/**
 * The circular blockers one unit must route around, in ascending entity id —
 * buildings first, then deposits, matching Swift's `structures + nodes`.
 *
 * A building's radius absorbs the moving unit's own footprint plus a small
 * padding, so a route planned against centres keeps hulls apart. A deposit's
 * radius does not: the work radius is already a centre-to-centre clearance.
 */
function obstaclesFor(unit, state) {
  const unitRadius = unitKind(unit.kind).footprintRadius;
  const obstacles = [];
  if (state.buildings) {
    for (const building of state.buildings.ordered()) {
      obstacles.push({
        center: building.position,
        radius: buildingKind(building.kind).footprintRadius + unitRadius + OBSTACLE_PADDING
      });
    }
  }
  if (state.deposits) {
    for (const deposit of state.deposits.ordered()) {
      obstacles.push({ center: deposit.position, radius: DEPOSIT_BLOCKER_RADIUS });
    }
  }
  return obstacles;
}

function clearOfObstacles(point, obstacles) {
  for (let index = 0; index < obstacles.length; index += 1) {
    const obstacle = obstacles[index];
    if (distance(point, obstacle.center) < obstacle.radius) return false;
  }
  return true;
}

function largestObstacleRadius(obstacles) {
  let largest = 0;
  for (let index = 0; index < obstacles.length; index += 1) {
    if (obstacles[index].radius > largest) largest = obstacles[index].radius;
  }
  return largest;
}

/**
 * Whether `point` is a legal standing place for `unit`: on land, inside the map
 * bounds, off every building footprint and off every deposit work radius.
 */
function isLegal(point, unit, state, obstacles = obstaclesFor(unit, state)) {
  if (!standable(state.map, point, unitKind(unit.kind).footprintRadius)) return false;
  return clearOfObstacles(point, obstacles);
}

// MARK: - Grid route planner (Swift `ObstacleNavigation`)

/**
 * A binary min-heap ordered by (score, heuristic, index).
 *
 * The third key is what makes the search reproducible: two cells with the same
 * f and h must still come out in a fixed order, and the cell index is the only
 * total order the lattice has.
 */
class MinHeap {
  constructor() {
    this.storage = [];
  }

  static ordered(left, right) {
    if (left.score !== right.score) return left.score < right.score;
    if (left.heuristic !== right.heuristic) return left.heuristic < right.heuristic;
    return left.index < right.index;
  }

  push(item) {
    this.storage.push(item);
    let child = this.storage.length - 1;
    while (child > 0) {
      const parent = (child - 1) >> 1;
      if (!MinHeap.ordered(this.storage[child], this.storage[parent])) break;
      const swap = this.storage[child];
      this.storage[child] = this.storage[parent];
      this.storage[parent] = swap;
      child = parent;
    }
  }

  pop() {
    if (this.storage.length === 0) return null;
    if (this.storage.length === 1) return this.storage.pop();

    const result = this.storage[0];
    this.storage[0] = this.storage.pop();
    let parent = 0;
    for (;;) {
      const left = parent * 2 + 1;
      if (left >= this.storage.length) break;
      const right = left + 1;
      let child = left;
      if (right < this.storage.length && MinHeap.ordered(this.storage[right], this.storage[left])) {
        child = right;
      }
      if (!MinHeap.ordered(this.storage[child], this.storage[parent])) break;
      const swap = this.storage[parent];
      this.storage[parent] = this.storage[child];
      this.storage[child] = swap;
      parent = child;
    }
    return result;
  }
}

const DIRECTIONS = Object.freeze([
  Object.freeze({ column: -1, row: 0, cost: 1 }),
  Object.freeze({ column: 1, row: 0, cost: 1 }),
  Object.freeze({ column: 0, row: -1, cost: 1 }),
  Object.freeze({ column: 0, row: 1, cost: 1 }),
  Object.freeze({ column: -1, row: -1, cost: DIAGONAL_COST }),
  Object.freeze({ column: 1, row: -1, cost: DIAGONAL_COST }),
  Object.freeze({ column: -1, row: 1, cost: DIAGONAL_COST }),
  Object.freeze({ column: 1, row: 1, cost: DIAGONAL_COST })
]);

/**
 * A* over a fixed 1 m lattice, then a line-of-sight string pull.
 *
 * This is the Swift planner, not a re-derivation: same lattice, same eight
 * moves, same diagonal-corner rule, same tie-breaking, same smoothing pass. The
 * returned endpoint is always a truthful destination — when the requested point
 * is blocked or disconnected the search keeps the closest node it actually
 * reached and says so through `reachedRequestedDestination`.
 */
function planGrid({ start, requested, bounds, padding, maxCells, passable, fallback }) {
  const minX = Math.max(
    bounds.minX,
    Math.floor((Math.min(start.x, requested.x) - padding) / GRID_SPACING) * GRID_SPACING
  );
  const maxX = Math.min(
    bounds.maxX,
    Math.ceil((Math.max(start.x, requested.x) + padding) / GRID_SPACING) * GRID_SPACING
  );
  const minZ = Math.max(
    bounds.minZ,
    Math.floor((Math.min(start.z, requested.z) - padding) / GRID_SPACING) * GRID_SPACING
  );
  const maxZ = Math.min(
    bounds.maxZ,
    Math.ceil((Math.max(start.z, requested.z) + padding) / GRID_SPACING) * GRID_SPACING
  );

  const columns = Math.max(Math.ceil((maxX - minX) / GRID_SPACING) + 1, 2);
  const rows = Math.max(Math.ceil((maxZ - minZ) / GRID_SPACING) + 1, 2);
  const count = columns * rows;
  if (!(count > 0)) return null;

  if (count > maxCells) {
    const destination = fallback();
    if (destination === null) return null;
    return {
      destination,
      waypoints: [copyPoint(destination)],
      reachedRequestedDestination: samePoint(destination, requested)
    };
  }

  const pointAt = (index) => {
    const row = Math.floor(index / columns);
    const column = index % columns;
    return { x: minX + column * GRID_SPACING, z: minZ + row * GRID_SPACING };
  };

  const nearestIndex = (p) => {
    const column = Math.min(
      Math.max(roundHalfAwayFromZero((p.x - minX) / GRID_SPACING), 0),
      columns - 1
    );
    const row = Math.min(
      Math.max(roundHalfAwayFromZero((p.z - minZ) / GRID_SPACING), 0),
      rows - 1
    );
    return row * columns + column;
  };

  const startIndex = nearestIndex(start);
  const goalIndex = nearestIndex(requested);
  const startAndGoalShareCell = startIndex === goalIndex;

  const points = new Array(count);
  for (let index = 0; index < count; index += 1) points[index] = pointAt(index);
  // Preserve exact start and arrival positions. The rest of the graph is still a
  // fixed lattice, so this does not make the search depend on anything but the
  // two endpoints.
  points[startIndex] = copyPoint(start);
  if (!startAndGoalShareCell) points[goalIndex] = copyPoint(requested);

  const walkable = new Array(count);
  for (let index = 0; index < count; index += 1) walkable[index] = passable(points[index]);
  if (!walkable[startIndex]) return null;

  const lineIsClear = (from, to) => {
    const span = distance(from, to);
    const samples = Math.max(Math.ceil(span / LINE_SAMPLE_SPACING), 1);
    for (let sample = 1; sample <= samples; sample += 1) {
      if (!passable(lerpPoint(from, to, sample / samples))) return false;
    }
    return true;
  };

  if (startAndGoalShareCell) {
    const canReach = passable(requested) && lineIsClear(start, requested);
    const destination = canReach ? copyPoint(requested) : copyPoint(start);
    return {
      destination,
      waypoints: [copyPoint(destination)],
      reachedRequestedDestination: canReach
    };
  }

  const heuristic = (index) => distance(points[index], requested);

  const gScore = new Array(count).fill(Infinity);
  const cameFrom = new Array(count).fill(-1);
  const closed = new Array(count).fill(false);
  const open = new MinHeap();
  gScore[startIndex] = 0;
  open.push({ index: startIndex, score: heuristic(startIndex), heuristic: heuristic(startIndex) });

  let bestIndex = startIndex;
  let bestDistance = heuristic(startIndex);
  let reachedRequestedDestination = false;

  for (;;) {
    const current = open.pop();
    if (current === null) break;
    if (closed[current.index]) continue;
    closed[current.index] = true;

    const distanceToGoal = heuristic(current.index);
    // Ties on distance break on the lower cell index, never on visit order.
    if (distanceToGoal < bestDistance || (distanceToGoal === bestDistance && current.index < bestIndex)) {
      bestDistance = distanceToGoal;
      bestIndex = current.index;
    }

    if (current.index === goalIndex && walkable[goalIndex]) {
      reachedRequestedDestination = true;
      bestIndex = goalIndex;
      break;
    }

    const currentRow = Math.floor(current.index / columns);
    const currentColumn = current.index % columns;
    for (let step = 0; step < DIRECTIONS.length; step += 1) {
      const direction = DIRECTIONS[step];
      const nextColumn = currentColumn + direction.column;
      const nextRow = currentRow + direction.row;
      if (nextColumn < 0 || nextColumn >= columns || nextRow < 0 || nextRow >= rows) continue;

      const next = nextRow * columns + nextColumn;
      if (!walkable[next] || closed[next]) continue;

      // Do not cut a diagonal corner between two blocked cells.
      if (direction.column !== 0 && direction.row !== 0) {
        const horizontal = currentRow * columns + nextColumn;
        const vertical = nextRow * columns + currentColumn;
        if (!walkable[horizontal] || !walkable[vertical]) continue;
      }

      if (!lineIsClear(points[current.index], points[next])) continue;

      const candidate = gScore[current.index] + direction.cost;
      if (!(candidate < gScore[next])) continue;
      gScore[next] = candidate;
      cameFrom[next] = current.index;
      const nextHeuristic = heuristic(next);
      open.push({ index: next, score: candidate + nextHeuristic, heuristic: nextHeuristic });
    }
  }

  if (!closed[bestIndex]) return null;

  const indices = [bestIndex];
  let cursor = bestIndex;
  while (cursor !== startIndex) {
    const parent = cameFrom[cursor];
    if (parent < 0) break;
    indices.push(parent);
    cursor = parent;
  }
  indices.reverse();

  const routePoints = indices.map((index) => points[index]);
  let waypoints = [];
  let anchor = copyPoint(start);
  let routeIndex = 0;
  while (routeIndex < routePoints.length) {
    let furthest = routeIndex;
    for (let candidate = routeIndex; candidate < routePoints.length; candidate += 1) {
      if (lineIsClear(anchor, routePoints[candidate])) furthest = candidate;
    }

    const point = routePoints[furthest];
    if (distance(anchor, point) > WAYPOINT_EPSILON) {
      waypoints.push(copyPoint(point));
      anchor = copyPoint(point);
    }
    routeIndex = furthest + 1;
  }

  const destination = waypoints.length > 0 ? copyPoint(waypoints[waypoints.length - 1]) : copyPoint(start);
  if (distance(destination, start) <= WAYPOINT_EPSILON) waypoints = [copyPoint(start)];
  return { destination, waypoints, reachedRequestedDestination };
}

/** Swift `ObstacleNavigation.plan`. Null when the unit is not legally placed. */
function plan(from, to, unit, state) {
  const map = state.map;
  const margin = unitKind(unit.kind).footprintRadius;
  const obstacles = obstaclesFor(unit, state);

  if (!standable(map, from, margin)) return null;

  return planGrid({
    start: from,
    requested: to,
    bounds: map.bounds,
    padding: Math.max(8, largestObstacleRadius(obstacles) + 3),
    maxCells: MAX_GRID_CELLS,
    passable: (point) => standable(map, point, margin) && clearOfObstacles(point, obstacles),
    fallback: () => clampToLandAlongSegment(map, to, from, margin)
  });
}

/**
 * The nearest legal standing point to `around`, searched outward on fixed
 * rings. Used only when the segment clamp has nowhere to retreat to, because
 * the unit's own position is already illegal.
 *
 * Deterministic by construction: radius ascending, then sample index ascending,
 * with no distance comparison to tie on.
 */
function nearestLegalOnRings(around, unit, state, obstacles) {
  const reach = Math.max(ESCAPE_RING_MINIMUM_REACH, largestObstacleRadius(obstacles) + ESCAPE_RING_HEADROOM);
  const rings = Math.ceil(reach / ESCAPE_RING_STEP);
  for (let ring = 1; ring <= rings; ring += 1) {
    const radius = ring * ESCAPE_RING_STEP;
    for (let sample = 0; sample < ESCAPE_RING_SAMPLES; sample += 1) {
      const angle = (sample / ESCAPE_RING_SAMPLES) * TWO_PI;
      const candidate = {
        x: around.x + Math.sin(angle) * radius,
        z: around.z + Math.cos(angle) * radius
      };
      if (isLegal(candidate, unit, state, obstacles)) return candidate;
    }
  }
  return null;
}

// MARK: - Facing

/**
 * Rate-limited facing with a deadband, from `Locomotion.advanceFacing`.
 *
 * Deviation 4: the Swift original measures the deadband against a separate
 * latched `targetFacing`, so a committed turn holds its target while the body
 * catches up. The pinned Unit shape in `CONTRACT.md` has one facing field and
 * no place to store a second, so the deadband is measured against the current
 * facing instead. The consequence is confined to the middle of a turn whose
 * heading is itself still changing; a unit walking a straight segment turns
 * identically under both rules, and neither can oscillate — once inside the
 * deadband the unit simply stops re-aiming.
 */
function advanceFacing(unit, before, deltaTime) {
  const step = clamp(deltaTime, 0, MAX_FACING_DELTA_TIME);
  if (!(step > 0)) return;
  if (!Number.isFinite(unit.facing)) unit.facing = 0;

  const delta = { x: unit.position.x - before.x, z: unit.position.z - before.z };
  const travelled = Math.sqrt(delta.x * delta.x + delta.z * delta.z);
  if (travelled <= 1e-5) return;
  if (travelled / step < STEER_MINIMUM_SPEED) return;

  const heading = headingOf(delta);
  const offTarget = shortestAngle(unit.facing, heading);
  if (Math.abs(offTarget) <= FACING_DEADBAND) return;

  const limit = MAX_TURN_RATE * step;
  unit.facing = wrapSigned(unit.facing + clamp(offTarget, -limit, limit));
}

// MARK: - Per-unit advance

function stopAtLegalPoint(unit, state) {
  unit.destination = null;
  unit.movementPath = [];
  unit.movementPathTarget = null;
  unit.region = state.map.region(unit.position);
  finishMoveActivity(unit);
}

/**
 * The cheap straight-line route.
 *
 * Gathering and construction rewrite `unit.destination` every tick without a
 * stored path. Running the planner for them would be both wrong (their target
 * is a work station inside an obstacle's skirt) and ruinously expensive, so
 * they get this: walk at the unit's speed and let the terrain clamp keep the
 * step legal.
 */
function advanceStraightLine(unit, destination, state, deltaTime) {
  const map = state.map;
  const toTarget = { x: destination.x - unit.position.x, z: destination.z - unit.position.z };
  const span = Math.sqrt(toTarget.x * toTarget.x + toTarget.z * toTarget.z);
  if (span <= ARRIVAL_RADIUS) {
    unit.position = copyPoint(destination);
    unit.destination = null;
    unit.region = map.region(destination);
    finishMoveActivity(unit);
    return;
  }

  const speed = unitKind(unit.kind).speed;
  const travel = Math.min(Math.max(speed * deltaTime, 0), span);
  if (!(travel > 0)) return;

  const heading = { x: toTarget.x / span, z: toTarget.z / span };
  const proposed = {
    x: unit.position.x + heading.x * travel,
    z: unit.position.z + heading.z * travel
  };
  const legal = clampToLandAlongSegment(
    map,
    proposed,
    unit.position,
    unitKind(unit.kind).footprintRadius
  );
  unit.position = legal;
  unit.region = map.region(legal);
  beginMoveActivity(unit);
}

/** The routed path follow — Swift's citizen branch, with the kind gate lifted. */
function advanceRouted(unit, state, deltaTime) {
  const map = state.map;
  let destination = unit.destination;

  // Gathering and construction rewrite the same destination every tick.
  // Preserve the stored route when that rewrite is within the arrival epsilon,
  // rather than treating float noise as a new order.
  if (unit.movementPathTarget && distance(unit.movementPathTarget, destination) <= DESTINATION_EPSILON) {
    destination = copyPoint(unit.movementPathTarget);
    unit.destination = destination;
  }

  if (distance(unit.position, destination) <= ROUTED_ARRIVAL_EPSILON) {
    unit.destination = null;
    unit.movementPath = [];
    unit.movementPathTarget = null;
    unit.region = map.region(unit.position);
    finishMoveActivity(unit);
    return;
  }

  const destinationChanged = unit.movementPathTarget
    ? distance(unit.movementPathTarget, destination) > DESTINATION_EPSILON
    : true;
  if (destinationChanged || unit.movementPath.length === 0) {
    const route = plan(unit.position, destination, unit, state);
    if (route === null) {
      stopAtLegalPoint(unit, state);
      return;
    }
    destination = route.destination;
    unit.destination = destination;
    unit.movementPath = route.waypoints;
    unit.movementPathTarget = copyPoint(destination);
  }

  while (unit.movementPath.length > 0 && distance(unit.position, unit.movementPath[0]) <= WAYPOINT_EPSILON) {
    unit.movementPath.shift();
  }

  if (unit.movementPath.length === 0) {
    unit.destination = null;
    unit.movementPathTarget = null;
    finishMoveActivity(unit);
    return;
  }

  const waypoint = unit.movementPath[0];
  const toWaypoint = { x: waypoint.x - unit.position.x, z: waypoint.z - unit.position.z };
  const span = Math.sqrt(toWaypoint.x * toWaypoint.x + toWaypoint.z * toWaypoint.z);
  if (!(span > 0.0001)) return;

  const heading = { x: toWaypoint.x / span, z: toWaypoint.z / span };
  const travel = Math.min(Math.max(unitKind(unit.kind).speed * deltaTime, 0), span);
  if (!(travel > 0)) return;
  const proposed = {
    x: unit.position.x + heading.x * travel,
    z: unit.position.z + heading.z * travel
  };

  if (!isLegal(proposed, unit, state)) {
    // A newly completed foundation or deposit change invalidates an old path.
    // Replan from the current legal point; never slide along the blocker or
    // cross it by clamping the point sideways.
    const route = plan(unit.position, destination, unit, state);
    if (route === null || (samePoint(route.destination, unit.position) && !route.reachedRequestedDestination)) {
      stopAtLegalPoint(unit, state);
      return;
    }
    unit.destination = route.destination;
    unit.movementPath = route.waypoints;
    unit.movementPathTarget = copyPoint(route.destination);
    return;
  }

  unit.position = proposed;
  unit.region = map.region(unit.position);
  beginMoveActivity(unit);

  if (travel >= span - 0.0001) {
    unit.movementPath.shift();
    if (unit.movementPath.length === 0) {
      unit.destination = null;
      unit.movementPathTarget = null;
      finishMoveActivity(unit);
    }
  }
}

function advance(unit, state, deltaTime) {
  // A unit riding a transport is carried, not walked.
  if (isAboard(unit)) return;
  // Deviation 1: no void truth in this runtime's map, so a void kind is left
  // exactly where it is rather than moved by an invented rule.
  if (VOID_TRAVEL_DEFERRED && unitKind(unit.kind).travelsVoid) return;

  if (!Array.isArray(unit.movementPath)) unit.movementPath = [];
  if (!unit.destination) {
    unit.movementPath = [];
    unit.movementPathTarget = null;
    return;
  }

  // Only explicit move orders carry a stored route. Assignment-driven
  // destinations keep the cheap straight line and must not invoke the planner
  // on every gathering or construction tick.
  const hasStoredRoute = unit.movementPathTarget !== null && unit.movementPathTarget !== undefined;
  if ((!hasStoredRoute && unit.movementPath.length === 0) || !isMovingActivity(unit)) {
    advanceStraightLine(unit, unit.destination, state, deltaTime);
    return;
  }

  advanceRouted(unit, state, deltaTime);
}

// MARK: - Group orders

/**
 * A stable, outward-growing ring so a group arrives as a readable cluster.
 *
 * Ported from `SkirmishSimulation.formationOffset`. Pure in `(index, count)`,
 * and the index is the unit's slot in the id-sorted selection — so the same
 * unit keeps the same slot on every replay, with no random draw involved.
 */
export function formationOffset(index, count) {
  if (count <= 1 || index <= 0) return { x: 0, z: 0 };
  const ring = Math.floor(index / 6) + 1;
  const slotsInRing = ring * 6;
  const slot = (index - 1) % slotsInRing;
  const angle = (slot / slotsInRing) * TWO_PI;
  const radius = ring * 2.2;
  return { x: Math.sin(angle) * radius, z: Math.cos(angle) * radius };
}

/**
 * Orders one unit to walk somewhere, exactly as `SkirmishSimulation.order`
 * does: clear the assignment, store the route, and mark the unit moving.
 *
 * Additive to the pinned contract — `simulation.js` owns orders and may call
 * this or write the same three fields itself. It lives here because the fields
 * it writes are the ones `step` reads, and splitting that pair across two
 * owners is how they drift.
 */
export function orderUnitMove(state, unitID, point) {
  const unit = state.units.get(unitID);
  if (!unit) return null;
  const route = MovementSystem.resolveOrder(point, unit, state);
  if (route === null) return null;
  unit.assignment = null;
  unit.destination = copyPoint(route.destination);
  unit.movementPath = route.waypoints.map(copyPoint);
  unit.movementPathTarget = copyPoint(route.destination);
  unit.activity = activity("moving");
  return unit.destination;
}

/**
 * Orders a selection to one point, spread over a formation ring.
 *
 * Slots derive from durable ids, never from selection order, so the same unit
 * keeps the same slot every time the same group is ordered to the same place.
 */
export function orderMove(state, unitIDs, point) {
  const ordered = [...unitIDs].sort((left, right) => left - right);
  const results = [];
  for (let index = 0; index < ordered.length; index += 1) {
    const id = ordered[index];
    if (!state.units.has(id)) continue;
    const offset = formationOffset(index, ordered.length);
    const destination = orderUnitMove(state, id, {
      x: point.x + offset.x,
      z: point.z + offset.z
    });
    if (destination !== null) results.push({ id, destination });
  }
  return results;
}

// MARK: - The contract surface

export const MovementSystem = {
  arrivalRadius: ARRIVAL_RADIUS,

  /**
   * Clamps an imprecise order to somewhere `unit` may legally stand: on land,
   * inside `state.map.bounds`, off every building footprint and off every
   * deposit work radius.
   *
   * Null only when nothing legal exists for this unit — it is aboard a
   * transport, it travels the void (deferred), or neither the segment back
   * toward the unit, nor the rings around the request, nor the map's own clamp,
   * nor the unit's current position is a place it could stand.
   */
  resolveDestination(point, unit, state) {
    if (isAboard(unit)) return null;
    if (VOID_TRAVEL_DEFERRED && unitKind(unit.kind).travelsVoid) return null;

    const map = state.map;
    const margin = unitKind(unit.kind).footprintRadius;
    const obstacles = obstaclesFor(unit, state);
    const accepts = (candidate) => isLegal(candidate, unit, state, obstacles);

    if (accepts(point)) return copyPoint(point);

    // Retreat along the ordered move. Landing on the near edge of whatever
    // blocked the tap is both legal and somewhere the unit could have walked.
    const retreat = clampAlongSegment(unit.position, point, accepts, TRAVERSABLE_CLAMP_STEPS);
    if (retreat !== null) return retreat;

    // The unit itself is standing illegally, so there is no segment to retreat
    // along. Search outward from the request instead.
    const ringed = nearestLegalOnRings(point, unit, state, obstacles);
    if (ringed !== null) return ringed;

    const clamped = map.clampToLand(point, margin);
    if (clamped && accepts(clamped)) return copyPoint(clamped);

    if (accepts(unit.position)) return copyPoint(unit.position);
    return null;
  },

  /**
   * A destination plus the waypoints that reach it around circular obstacles.
   *
   * Terrain is clamped first, exactly as Swift does, so the planner is never
   * asked to reach a point in the sea; the planner then routes around
   * buildings and deposits and returns the closest node it actually reached
   * when the request is blocked or disconnected.
   */
  resolveOrder(point, unit, state) {
    if (isAboard(unit)) return null;
    if (VOID_TRAVEL_DEFERRED && unitKind(unit.kind).travelsVoid) return null;

    const map = state.map;
    const margin = unitKind(unit.kind).footprintRadius;

    let terrainDestination;
    if (standable(map, point, margin)) {
      terrainDestination = copyPoint(point);
    } else {
      const clamped = clampAlongSegment(
        unit.position,
        point,
        (candidate) => standable(map, candidate, margin),
        TRAVERSABLE_CLAMP_STEPS
      );
      if (clamped !== null) {
        terrainDestination = clamped;
      } else {
        // The unit is not standing on legal ground, so nothing on the segment
        // helps. Fall back to the map's own clamp before giving up.
        const mapClamped = map.clampToLand(point, margin);
        if (!mapClamped) return null;
        terrainDestination = copyPoint(mapClamped);
      }
    }

    const route = plan(unit.position, terrainDestination, unit, state);
    if (route === null) return null;
    return route;
  },

  /**
   * Advances every unit that has somewhere to be, by `deltaTime` seconds.
   *
   * Reads no clock: the only time this function knows about is the argument, so
   * 600 calls of `1/20` produce the same result whatever the render cadence
   * around them. Iterates ascending id, so no unit's step can depend on another
   * unit's insertion order.
   */
  step(state, deltaTime) {
    const ids = state.units.orderedIDs();
    for (let index = 0; index < ids.length; index += 1) {
      const unit = state.units.get(ids[index]);
      if (!unit) continue;
      const before = copyPoint(unit.position);
      advance(unit, state, deltaTime);
      advanceFacing(unit, before, deltaTime);
    }
  },

  /** Whether `point` is a legal standing place for `unit`. */
  isLegal(point, unit, state) {
    return isLegal(point, unit, state);
  },

  formationOffset,
  orderUnitMove,
  orderMove
};
