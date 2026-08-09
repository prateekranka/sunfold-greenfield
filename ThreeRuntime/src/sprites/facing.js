// AoE2-style 8-direction facing from world yaw (radians, +Y up, 0 = +Z / “south”).

/** Facings indexed 0–7 clockwise from south (toward +Z). */
export const FACINGS = Object.freeze(["S", "SE", "E", "NE", "N", "NW", "W", "SW"]);

/** @param {number} yawRadians world yaw (0 = facing +Z) */
export function yawToFacing(yawRadians) {
  const steps = 8;
  const slice = (Math.PI * 2) / steps;
  let idx = Math.round(yawRadians / slice) % steps;
  if (idx < 0) idx += steps;
  return idx;
}

/**
 * Facing with hysteresis so tiny yaw chatter near a cell edge does not pop.
 * @param {number} yawRadians
 * @param {number} currentFacing 0–7
 * @param {number} [hold=0.58] fraction of a cell from center before switching
 */
export function yawToFacingStable(yawRadians, currentFacing, hold = 0.58) {
  const steps = 8;
  const slice = (Math.PI * 2) / steps;
  const candidate = yawToFacing(yawRadians);
  const cur = ((currentFacing % steps) + steps) % steps;
  if (candidate === cur) return cur;
  let delta = yawRadians - cur * slice;
  delta = ((delta + Math.PI) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
  if (Math.abs(delta) < slice * hold) return cur;
  return candidate;
}

/** @param {number} facingIndex 0–7 */
export function facingName(facingIndex) {
  return FACINGS[((facingIndex % 8) + 8) % 8];
}

/**
 * True when the authored art for this facing is a horizontal mirror of another.
 * @param {number} facingIndex
 * @returns {{ mirror: boolean, sourceFacing?: number }}
 */
export function facingMirror(facingIndex) {
  switch (facingIndex) {
    case 5: return { mirror: true, sourceFacing: 3 }; // NW ← NE
    case 6: return { mirror: true, sourceFacing: 2 }; // W ← E
    case 7: return { mirror: true, sourceFacing: 1 }; // SW ← SE
    default: return { mirror: false };
  }
}

// ---- 16-direction facing (golden-unit sheets) ------------------------------

/** Facings indexed 0–15 clockwise from south (toward +Z), 22.5° steps. */
export const FACINGS_16 = Object.freeze([
  "S", "SSE", "SE", "ESE", "E", "ENE", "NE", "NNE",
  "N", "NNW", "NW", "WNW", "W", "WSW", "SW", "SSW"
]);

/**
 * Dedicated idle sheet columns (L→R): NE E SE S SW W NW N.
 * Map a FACINGS_16 index onto the nearest idle column.
 * @param {number} facing16 0–15
 * @returns {number} 0–7 column index
 */
export function facing16ToIdle8Column(facing16) {
  // NE E SE S SW W NW N
  const map = [
    3, // S
    2, // SSE → SE
    2, // SE
    1, // ESE → E
    1, // E
    0, // ENE → NE
    0, // NE
    7, // NNE → N
    7, // N
    6, // NNW → NW
    6, // NW
    5, // WNW → W
    5, // W
    4, // WSW → SW
    4, // SW
    3  // SSW → S
  ];
  const i = ((facing16 % 16) + 16) % 16;
  return map[i];
}

/** @param {number} yawRadians world yaw (0 = facing +Z) */
export function yawToFacing16(yawRadians) {
  const steps = 16;
  const slice = (Math.PI * 2) / steps;
  // Math.round(-0.5) is -0 in JS; the wrap convention: normalize yaw into
  // [0, 2π) first, then round to the nearest 22.5° cell (half-step rounds up).
  let yaw = ((yawRadians % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
  return Math.round(yaw / slice) % steps;
}

/**
 * 16-dir facing with hysteresis (avoids boundary pop while orbiting / swaying).
 * @param {number} yawRadians
 * @param {number} currentFacing 0–15
 * @param {number} [hold=0.58] fraction of a 22.5° cell from center before switch
 */
export function yawToFacing16Stable(yawRadians, currentFacing, hold = 0.58) {
  const steps = 16;
  const slice = (Math.PI * 2) / steps;
  const candidate = yawToFacing16(yawRadians);
  const cur = ((currentFacing % steps) + steps) % steps;
  if (candidate === cur) return cur;
  let delta = yawRadians - cur * slice;
  delta = ((delta + Math.PI) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
  if (Math.abs(delta) < slice * hold) return cur;
  return candidate;
}

/** @param {number} facingIndex 0–15 */
export function facingName16(facingIndex) {
  return FACINGS_16[((facingIndex % 16) + 16) % 16];
}
