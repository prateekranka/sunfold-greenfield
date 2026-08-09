// Orchestrates MapDefinition subsystems into a playable RTS map instance.

import { getMapDefinition } from "./maps/index.js";
import { PathGraph } from "./path-graph.js";
import { buildTerrain, setBridgeVisual, TERRAIN_PALETTE } from "./terrain-generator.js";
import { spawnResources } from "./resource-spawner.js";
import { createPlayerSpawns } from "./player-spawn-manager.js";
import { spawnObjectives, tickObjectiveCapture } from "./objective-manager.js";
import {
  applyHazardBridgeAvailability,
  createHazards,
  tickHazards,
  hazardDamageAt
} from "./hazard-system.js";
import { buildAIHints } from "./ai-hints.js";
import { findWalkablePath, isPointWalkable, nearestWalkablePoint } from "./ground-navigation.js";

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
          applyHazardBridgeAvailability(h, active, this.pathGraph, this.bridgeStates);
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
      return isPointWalkable(this.definition, this.bridgeStates, x, z);
    },
    findGroundPath(fromX, fromZ, toX, toZ) {
      return findWalkablePath(
        this.definition,
        this.pathGraph,
        this.bridgeStates,
        fromX,
        fromZ,
        toX,
        toZ
      );
    },
    nearestWalkablePoint(x, z, maxDistance) {
      return nearestWalkablePoint(this.definition, this.bridgeStates, x, z, maxDistance);
    },
    getFreshAIHints() {
      return buildAIHints(this.definition, { pathGraph: this.pathGraph, bridgeStates: this.bridgeStates });
    }
  };
}
