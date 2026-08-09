// Data-driven RTS space map contract.
// Maps declare terrain, spawns, resources, objectives, bridges, hazards, and AI hints.
// Gameplay systems read MapDefinition — individual maps never embed logic.

/** @typedef {'provisions'|'matter'|'lumen'|'aether'|'energy_materials'} ResourceKind */

/**
 * @typedef {object} MapDefinition
 * @property {string} id
 * @property {string} name
 * @property {string} theme
 * @property {string} [description]
 * @property {boolean} [playable]
 * @property {{ halfExtent: number, center?: { x: number, z: number } }} bounds
 * @property {TerrainSpec} terrain
 * @property {PlayerSpawnSpec[]} spawns
 * @property {ResourceNodeSpec[]} resources
 * @property {ObjectiveSpec[]} objectives
 * @property {BridgeSpec[]} bridges
 * @property {HazardSpec[]} hazards
 * @property {AIHintsSpec} aiHints
 */

/**
 * @typedef {object} TerrainSpec
 * @property {'ring'|'basin'|'asteroid-belt'} layout
 * @property {PlatformSpec[]} platforms
 * @property {DebrisSpec[]} [debris]
 * @property {{ color?: number, emissive?: number }} [palette]
 */

/** @typedef {{ id: string, center: { x: number, z: number }, radius: number, arc?: number, yaw?: number, height?: number }} PlatformSpec */

/** @typedef {{ id: string, center: { x: number, z: number }, radius: number }} DebrisSpec */

/**
 * @typedef {object} PlayerSpawnSpec
 * @property {number} playerId
 * @property {string} platformId
 * @property {{ x: number, z: number }} position
 * @property {number} [yaw]
 * @property {number} [startingCitizens]
 */

/**
 * @typedef {object} ResourceNodeSpec
 * @property {string} id
 * @property {ResourceKind} kind
 * @property {{ x: number, z: number }} position
 * @property {number} [amount]
 * @property {string} [platformId]
 */

/**
 * @typedef {object} ObjectiveSpec
 * @property {string} id
 * @property {'solar_core'|'outpost'|'relic'} type
 * @property {{ x: number, z: number }} position
 * @property {number} captureRadius
 * @property {Record<string, unknown>} [effects]
 */

/**
 * @typedef {object} BridgeSpec
 * @property {string} id
 * @property {string} fromPlatformId
 * @property {string} toPlatformId
 * @property {{ x: number, z: number }} from
 * @property {{ x: number, z: number }} to
 * @property {boolean} [startsEnabled]
 * @property {{ type: string, cost: string, importance?: string }} [metadata]
 */

/**
 * @typedef {object} HazardSpec
 * @property {string} id
 * @property {'solar_flare'|'rotating_debris'} type
 * @property {number} intervalSeconds
 * @property {number} durationSeconds
 * @property {Record<string, unknown>} [params]
 */

/**
 * @typedef {object} AIHintsSpec
 * @property {{ id: string, position: { x: number, z: number }, reason?: string }[]} expansionLocations
 * @property {{ id: string, position: { x: number, z: number }, severity?: string }[]} dangerZones
 * @property {{ id: string, position: { x: number, z: number }, value?: string }[]} highValueObjectives
 * @property {{ id: string, from: string, to: string, via?: string[] }[]} preferredAttackRoutes
 * @property {{ id: string, position: { x: number, z: number }, platformId?: string }[]} defensivePositions
 */

/** @type {Map<string, MapDefinition>} */
const registry = new Map();

/**
 * @param {MapDefinition} def
 */
export function registerMap(def) {
  if (!def?.id) throw new Error("MapDefinition requires id");
  registry.set(def.id, Object.freeze(structuredClone(def)));
}

/**
 * @param {string} id
 * @returns {MapDefinition}
 */
export function getMapDefinition(id) {
  const def = registry.get(id);
  if (!def) throw new Error(`Unknown map: ${id}`);
  return def;
}

export function listMaps() {
  return [...registry.values()];
}

export function listPlayableMaps() {
  return listMaps().filter((m) => m.playable !== false);
}
