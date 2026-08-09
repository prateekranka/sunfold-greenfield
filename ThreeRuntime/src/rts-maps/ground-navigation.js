// Pure land-navigation rules shared by command validation and runtime movement.

/**
 * @param {import('./map-definition.js').MapDefinition} definition
 * @param {Map<string, boolean>} bridgeStates
 * @param {number} x
 * @param {number} z
 */
export function isPointWalkable(definition, bridgeStates, x, z) {
  if (!Number.isFinite(x) || !Number.isFinite(z)) return false;
  const half = definition.bounds.halfExtent;
  if (Math.hypot(x, z) > half + 8) return false;

  for (const platform of definition.terrain.platforms) {
    if (!usesCircularPlatformFallback(platform, definition.terrain)) continue;
    const distance = Math.hypot(x - platform.center.x, z - platform.center.z);
    if (distance <= platform.radius + 1.5) return true;
  }

  if (isHeliosAnnularWalkable(x, z, definition.terrain)) return true;

  for (const bridge of definition.bridges) {
    if (!bridgeStates.get(bridge.id)) continue;
    const { from, to } = getBridgeEndpoints(bridge);
    const midpointX = (from.x + to.x) * 0.5;
    const midpointZ = (from.z + to.z) * 0.5;
    const length = Math.hypot(to.x - from.x, to.z - from.z);
    const width = bridge.visual?.deckWidth ?? bridge.visual?.width ?? 2.2;
    const distanceToLine = pointToSegmentDistance(x, z, from.x, from.z, to.x, to.z);
    if (
      distanceToLine <= Math.max(1.1, width * 0.62) &&
      Math.hypot(x - midpointX, z - midpointZ) <= length * 0.55
    ) return true;
  }

  return false;
}

/**
 * Find a reachable land route and reject every route that crosses open void.
 *
 * @param {import('./map-definition.js').MapDefinition} definition
 * @param {import('./path-graph.js').PathGraph} pathGraph
 * @param {Map<string, boolean>} bridgeStates
 * @param {number} fromX
 * @param {number} fromZ
 * @param {number} toX
 * @param {number} toZ
 * @returns {{ x: number, z: number }[]}
 */
export function findWalkablePath(definition, pathGraph, bridgeStates, fromX, fromZ, toX, toZ) {
  if (!isPointWalkable(definition, bridgeStates, fromX, fromZ)) return [];
  if (!isPointWalkable(definition, bridgeStates, toX, toZ)) return [];

  const path = pathGraph.findPath(fromX, fromZ, toX, toZ);
  if (!path.length) return [];
  const points = [{ x: fromX, z: fromZ }, ...path];
  return isPolylineWalkable(definition, bridgeStates, points) ? path : [];
}

/**
 * Resolve a formation slot back onto nearby land without accepting a void command.
 *
 * @param {import('./map-definition.js').MapDefinition} definition
 * @param {Map<string, boolean>} bridgeStates
 * @param {number} x
 * @param {number} z
 * @param {number} [maxDistance]
 * @returns {{ x: number, z: number } | null}
 */
export function nearestWalkablePoint(definition, bridgeStates, x, z, maxDistance = 2.4) {
  if (isPointWalkable(definition, bridgeStates, x, z)) return { x, z };
  const radialStep = 0.3;
  const directions = 16;
  for (let radius = radialStep; radius <= maxDistance + 1e-6; radius += radialStep) {
    for (let index = 0; index < directions; index += 1) {
      const angle = (index / directions) * Math.PI * 2;
      const candidate = {
        x: x + Math.cos(angle) * radius,
        z: z + Math.sin(angle) * radius
      };
      if (isPointWalkable(definition, bridgeStates, candidate.x, candidate.z)) return candidate;
    }
  }
  return null;
}

/**
 * @param {import('./map-definition.js').MapDefinition} definition
 * @param {Map<string, boolean>} bridgeStates
 * @param {{ x: number, z: number }[]} points
 * @param {number} [sampleSpacing]
 */
export function isPolylineWalkable(definition, bridgeStates, points, sampleSpacing = 0.55) {
  if (!Array.isArray(points) || points.length === 0) return false;
  for (let index = 0; index < points.length; index += 1) {
    const point = points[index];
    if (!isPointWalkable(definition, bridgeStates, point.x, point.z)) return false;
    if (index === 0) continue;
    const previous = points[index - 1];
    const distance = Math.hypot(point.x - previous.x, point.z - previous.z);
    const samples = Math.max(1, Math.ceil(distance / sampleSpacing));
    for (let sample = 1; sample < samples; sample += 1) {
      const t = sample / samples;
      const x = previous.x + (point.x - previous.x) * t;
      const z = previous.z + (point.z - previous.z) * t;
      if (!isPointWalkable(definition, bridgeStates, x, z)) return false;
    }
  }
  return true;
}

function pointToSegmentDistance(px, pz, ax, az, bx, bz) {
  const abx = bx - ax;
  const abz = bz - az;
  const lengthSquared = abx * abx + abz * abz;
  if (lengthSquared <= Number.EPSILON) return Math.hypot(px - ax, pz - az);
  let t = ((px - ax) * abx + (pz - az) * abz) / lengthSquared;
  t = Math.max(0, Math.min(1, t));
  const closestX = ax + t * abx;
  const closestZ = az + t * abz;
  return Math.hypot(px - closestX, pz - closestZ);
}

function getBridgeEndpoints(bridge) {
  const visualFrom = bridge.visual?.from;
  const visualTo = bridge.visual?.to;
  if (isCoordinate(visualFrom) && isCoordinate(visualTo)) {
    return { from: visualFrom, to: visualTo };
  }
  return { from: bridge.from, to: bridge.to };
}

function isCoordinate(point) {
  return Number.isFinite(point?.x) && Number.isFinite(point?.z);
}

function usesCircularPlatformFallback(platform, terrain) {
  if (platform.id === "core-platform" || platform.id.startsWith("isle-")) return true;
  const visual = terrain.visual;
  if (visual?.style !== "broken-ring" || !Array.isArray(visual.fragments)) return true;
  return !visual.fragments.some((fragment) => fragment?.id === platform.id);
}

function isHeliosAnnularWalkable(x, z, terrain) {
  const visual = terrain.visual;
  if (visual?.style !== "broken-ring" || !Array.isArray(visual.fragments)) return false;

  const centerX = visual.center?.x ?? 0;
  const centerZ = visual.center?.z ?? 0;
  if (!Number.isFinite(centerX) || !Number.isFinite(centerZ)) return false;

  for (const fragment of visual.fragments) {
    if (!fragment || typeof fragment.id !== "string") continue;
    const platform = terrain.platforms.find((entry) => entry.id === fragment.id);
    if (!platform || fragment.id === "core-platform" || fragment.id.startsWith("isle-")) continue;

    const innerRadius = Number.isFinite(fragment.innerRadius)
      ? fragment.innerRadius
      : Number.isFinite(visual.innerRadius)
        ? visual.innerRadius
        : platform.radius * 1.9;
    const outerRadius = Number.isFinite(fragment.outerRadius)
      ? fragment.outerRadius
      : Number.isFinite(visual.outerRadius)
        ? visual.outerRadius
        : platform.radius * 3.9;
    const span = Number.isFinite(fragment.span)
      ? fragment.span
      : Number.isFinite(visual.fragmentSpan)
        ? visual.fragmentSpan
        : Math.PI * 0.42;
    if (
      !Number.isFinite(fragment.centerAngle) ||
      !Number.isFinite(innerRadius) ||
      !Number.isFinite(outerRadius) ||
      !Number.isFinite(span) ||
      innerRadius < 0 ||
      outerRadius <= innerRadius ||
      span <= 0
    ) continue;

    const dx = x - centerX;
    const dz = z - centerZ;
    const radius = Math.hypot(dx, dz);
    if (radius < innerRadius || radius > outerRadius) continue;

    const angle = Math.atan2(dz, dx);
    const delta = Math.atan2(
      Math.sin(angle - fragment.centerAngle),
      Math.cos(angle - fragment.centerAngle)
    );
    if (Math.abs(delta) <= span * 0.5) return true;
  }

  return false;
}
