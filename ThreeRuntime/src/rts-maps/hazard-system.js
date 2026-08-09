// Periodic map hazards — solar flares, disabled bridge sections, etc.

/**
 * @typedef {object} HazardState
 * @property {string} id
 * @property {string} type
 * @property {number} intervalSeconds
 * @property {number} durationSeconds
 * @property {number} timer
 * @property {boolean} active
 * @property {Record<string, unknown>} params
 */

/**
 * @param {import('./map-definition.js').HazardSpec[]} specs
 * @returns {HazardState[]}
 */
export function createHazards(specs) {
  return specs.map((s) => ({
    id: s.id,
    type: s.type,
    intervalSeconds: s.intervalSeconds,
    durationSeconds: s.durationSeconds,
    timer: s.intervalSeconds * 0.6,
    active: false,
    params: s.params ?? {}
  }));
}

/**
 * @param {HazardState[]} hazards
 * @param {number} dt
 * @param {(hazard: HazardState, active: boolean) => void} [onChange]
 */
export function tickHazards(hazards, dt, onChange) {
  for (const h of hazards) {
    if (h.active) {
      h.timer -= dt;
      if (h.timer <= 0) {
        h.active = false;
        h.timer = h.intervalSeconds;
        onChange?.(h, false);
      }
    } else {
      h.timer -= dt;
      if (h.timer <= 0) {
        h.active = true;
        h.timer = h.durationSeconds;
        onChange?.(h, true);
      }
    }
  }
}

/**
 * @param {HazardState} hazard
 * @param {number} x
 * @param {number} z
 * @param {{ x: number, z: number }} [corePos]
 */
export function hazardDamageAt(hazard, x, z, corePos = { x: 0, z: 0 }) {
  if (!hazard.active || hazard.type !== "solar_flare") return 0;
  const exposure = Math.max(0, 1 - Math.hypot(x - corePos.x, z - corePos.z) / 55);
  const coverBonus = hazard.params.coverReduction ?? 0.35;
  return (hazard.params.dps ?? 8) * exposure * (1 - coverBonus * 0.5);
}

/**
 * @param {HazardState[]} hazards
 * @param {import('./path-graph.js').PathGraph} pathGraph
 */
export function getDisabledBridgesDuringFlare(hazards, pathGraph) {
  const flare = hazards.find((h) => h.type === "solar_flare" && h.active);
  if (!flare) return [];
  const disabled = flare.params.disableBridgeIds;
  if (Array.isArray(disabled)) return disabled;
  return [];
}

/**
 * Apply temporary hazard availability without changing a bridge's repaired state.
 *
 * @param {HazardState} hazard
 * @param {boolean} active
 * @param {import('./path-graph.js').PathGraph} pathGraph
 * @param {Map<string, boolean>} bridgeStates
 */
export function applyHazardBridgeAvailability(hazard, active, pathGraph, bridgeStates) {
  if (hazard.type !== "solar_flare") return;
  const affected = hazard.params.disableBridgeIds;
  if (!Array.isArray(affected)) return;
  for (const bridgeId of affected) {
    const physicallyEnabled = bridgeStates.get(bridgeId) ?? false;
    pathGraph.setBridgeEnabled(bridgeId, active ? false : physicallyEnabled);
  }
}
