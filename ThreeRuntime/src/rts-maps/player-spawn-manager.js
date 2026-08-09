// Player spawn management — starting positions and initial citizen counts.

/**
 * @typedef {object} PlayerSpawnState
 * @property {number} playerId
 * @property {{ x: number, z: number }} position
 * @property {number} yaw
 * @property {number} startingCitizens
 * @property {string} platformId
 * @property {number} color
 */

const PLAYER_COLORS = [0x5ad4ff, 0xff6a6a, 0x9dff6a, 0xffd45a];

/**
 * @param {import('./map-definition.js').PlayerSpawnSpec[]} spawns
 * @returns {PlayerSpawnState[]}
 */
export function createPlayerSpawns(spawns) {
  return spawns.map((s, i) => ({
    playerId: s.playerId,
    position: { ...s.position },
    yaw: s.yaw ?? 0,
    startingCitizens: s.startingCitizens ?? 6,
    platformId: s.platformId,
    color: PLAYER_COLORS[s.playerId % PLAYER_COLORS.length]
  }));
}

/**
 * @param {PlayerSpawnState[]} spawns
 * @param {number} playerId
 */
export function getSpawnForPlayer(spawns, playerId) {
  return spawns.find((s) => s.playerId === playerId) ?? spawns[0];
}
