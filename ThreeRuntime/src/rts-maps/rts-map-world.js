// Orchestrates MapDefinition subsystems into a playable RTS map instance.

import { getMapDefinition } from "./maps/index.js";
import { PathGraph } from "./path-graph.js";
import { buildTerrain, setBridgeVisual, TERRAIN_PALETTE } from "./terrain-generator.js";
import { spawnResources } from "./resource-spawner.js";
import { createPlayerSpawns } from "./player-spawn-manager.js";
import { spawnObjectives, tickObjectiveCapture } from "./objective-manager.js";
import { createHazards, tickHazards, hazardDamageAt, getDisabledBridgesDuringFlare } from "./hazard-system.js";
import { buildAIHints } from "./ai-hints.js";

/**
 * @typedef {object} RtsMapWorld
 * @property {import('./map-definition.js').MapDefinition} definition
 * @property {import('./path-graph.js').PathGraph} pathGraph
 * @property {ReturnType<typeof createPlayerSpawns>} spawns
 * @property {ReturnType<typeof spawnResources>} resources
 * @property {ReturnType<typeof spawnObjectives>} objectives
 * @property {ReturnType<typeof createHazards>} hazards
 * @property {import('three').Group} terrainGroup
 * @property {Map<string, import('three').Group>} bridgeMeshes
 * @property {Map<string, boolean>} bridgeStates
 * @property {import('./ai-hints.js').buildAIHints extends (...a: infer _) => infer R ? R : never} aiHints
 */

/**
 * @param {string} mapId
 * @param {import('three').Group} sceneRoot
 * @returns {RtsMapWorld}
 */
export function createRtsMapWorld(mapId, sceneRoot) {
  const definition = getMapDefinition(mapId);
  const pathGraph = new PathGraph(definition);
  const bridgeStates = new Map();

  for (const b of definition.bridges) {
    const enabled = b.startsEnabled !== false;
    bridgeStates.set(b.id, enabled);
    pathGraph.setBridgeEnabled(b.id, enabled);
  }

  const { group: terrainGroup, bridgeMeshes } = buildTerrain(definition.terrain, definition.bridges);
  for (const [id, mesh] of bridgeMeshes) {
    const spec = definition.bridges.find((b) => b.id === id);
    mesh.userData.spec = spec;
  }
  sceneRoot.add(terrainGroup);

  const resources = spawnResources(definition.resources, terrainGroup);
  const objectives = spawnObjectives(definition.objectives, terrainGroup);
  const spawns = createPlayerSpawns(definition.spawns);
  const hazards = createHazards(definition.hazards);

  const aiHints = buildAIHints(definition, { pathGraph, bridgeStates });

  return {
    definition,
    pathGraph,
    spawns,
    resources,
    objectives,
    hazards,
    terrainGroup,
    bridgeMeshes,
    bridgeStates,
    aiHints,
    /** @param {number} dt */
    tick(dt, units = []) {
      tickHazards(this.hazards, dt, (h, active) => {
        if (h.type === "solar_flare") {
          const corona = this.objectives[0]?.mesh?.getObjectByName("corona");
          if (corona?.material) {
            corona.material.opacity = active
              ? corona.userData.flareOpacity ?? 0.32
              : corona.userData.restingOpacity ?? 0.2;
          }
          for (const bridgeId of getDisabledBridgesDuringFlare(this.hazards, this.pathGraph)) {
            if (active && this.bridgeStates.get(bridgeId)) {
              this.pathGraph.setBridgeEnabled(bridgeId, false);
            } else if (!active) {
              this.pathGraph.setBridgeEnabled(bridgeId, this.bridgeStates.get(bridgeId) ?? false);
            }
          }
        }
      });

      const core = this.objectives.find((o) => o.type === "solar_core");
      const corePos = core?.position ?? { x: 0, z: 0 };
      for (const u of units) {
        const dps = this.hazards.reduce((sum, h) => sum + hazardDamageAt(h, u.x, u.z, corePos), 0);
        if (dps > 0) u.hp = Math.max(0, (u.hp ?? 100) - dps * dt);
      }

      if (core) {
        tickObjectiveCapture(
          core,
          dt,
          units.map((u) => ({ playerId: u.playerId ?? 0, x: u.x, z: u.z }))
        );
      }
    },
    repairBridge(bridgeId) {
      if (!this.bridgeStates.has(bridgeId)) return false;
      this.bridgeStates.set(bridgeId, true);
      this.pathGraph.setBridgeEnabled(bridgeId, true);
      const mesh = this.bridgeMeshes.get(bridgeId);
      if (mesh) setBridgeVisual(mesh, true, TERRAIN_PALETTE);
      return true;
    },
    isWalkable(x, z) {
      const half = this.definition.bounds.halfExtent;
      if (Math.hypot(x, z) > half + 8) return false;
      for (const p of this.definition.terrain.platforms) {
        if (!usesCircularPlatformFallback(p, this.definition.terrain)) continue;
        const d = Math.hypot(x - p.center.x, z - p.center.z);
        if (d <= p.radius + 1.5) return true;
      }
      if (isHeliosAnnularWalkable(x, z, this.definition.terrain)) return true;
      for (const b of this.definition.bridges) {
        if (!this.bridgeStates.get(b.id)) continue;
        const { from, to } = getBridgeEndpoints(b);
        const t = 0.5;
        const mx = from.x * (1 - t) + to.x * t;
        const mz = from.z * (1 - t) + to.z * t;
        const dLine = pointToSegmentDist(x, z, from.x, from.z, to.x, to.z);
        if (dLine < 2.2 && Math.hypot(x - mx, z - mz) < Math.hypot(to.x - from.x, to.z - from.z) * 0.55) {
          return true;
        }
      }
      return false;
    },
    getFreshAIHints() {
      return buildAIHints(this.definition, { pathGraph: this.pathGraph, bridgeStates: this.bridgeStates });
    }
  };
}

function pointToSegmentDist(px, pz, ax, az, bx, bz) {
  const abx = bx - ax;
  const abz = bz - az;
  const len2 = abx * abx + abz * abz;
  let t = ((px - ax) * abx + (pz - az) * abz) / len2;
  t = Math.max(0, Math.min(1, t));
  const cx = ax + t * abx;
  const cz = az + t * abz;
  return Math.hypot(px - cx, pz - cz);
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
