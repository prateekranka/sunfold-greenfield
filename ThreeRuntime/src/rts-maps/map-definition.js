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
 * @property {TerrainVisualSpec} [visual]
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
 * @property {ObjectiveVisualSpec} [visual]
 */

/**
 * Presentation-only solar objective values. Gameplay capture and effects stay
 * on ObjectiveSpec and are not changed by this optional visual contract.
 * @typedef {object} ObjectiveVisualSpec
 * @property {number} [radius]
 * @property {number} [coronaRadius]
 * @property {number} [coreColor]
 * @property {number} [coronaColor]
 * @property {number} [beamColor]
 * @property {number} [coreOpacity]
 * @property {number} [coronaOpacity]
 * @property {number} [emissive]
 * @property {number} [emissiveIntensity]
 * @property {number} [lightColor]
 * @property {number} [lightIntensity]
 * @property {number} [lightDistance]
 * @property {number} [lightDecay]
 * @property {{ color?: number, intensity?: number, distance?: number, decay?: number }} [light]
 * @property {{ innerRadius?: number, outerRadius?: number, color?: number, opacity?: number }} [captureZone]
 * @property {{ radiusTop?: number, radiusBottom?: number, height?: number, color?: number, opacity?: number }} [beam]
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
 * @property {{ from: { x: number, z: number }, to: { x: number, z: number }, surfaceY?: number, width?: number, deckWidth?: number, understructureWidth?: number, disabledStubLength?: number, palette?: Record<string, number> }} [visual]
 */

/**
 * Optional terrain treatment data. Renderers can use it for presentation.
 * Navigation can opt into matching fragment bounds and bridge endpoints while
 * retaining the map's logical IDs and connectivity.
 * @typedef {object} TerrainVisualSpec
 * @property {string} [style]
 * @property {{ x: number, z: number }} [center]
 * @property {number} [seed]
 * @property {number} [innerRadius]
 * @property {number} [outerRadius]
 * @property {number} [fragmentSpan]
 * @property {number} [surfaceY]
 * @property {number} [debrisClearance]
 * @property {Record<string, number>} [palette]
 * @property {{ id: string, centerAngle: number, span?: number, innerRadius?: number, outerRadius?: number }[]} [fragments]
 * @property {number} [platformDepth]
 * @property {number} [understructureDepth]
 * @property {number} [deckInset]
 * @property {number} [panelCount]
 * @property {number} [deckPanelGap]
 * @property {number} [armorBandWidth]
 * @property {number} [armorBlockCount]
 * @property {number} [wallJitter]
 * @property {number} [cracksPerFragment]
 * @property {number} [conduitCount]
 * @property {{ count?: number, innerRadius?: number, outerRadius?: number, height?: number }} [starfield]
 * @property {{ id: string, position: { x: number, z: number }, radius?: number, color?: number, label?: string }[]} [spawnPads]
 * @property {{ id: string, position: { x: number, z: number }, radius?: number, color?: number, label?: string }[]} [landmarks]
 * @property {{ id: string, position: { x: number, z: number }, radius?: number, color?: number }[]} [resourceZones]
 * @property {{ count?: number, innerRadius?: number, coreRadius?: number, outerRadius?: number, ringClearance?: number }} [debrisField]
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
