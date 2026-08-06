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

/** @param {number} yawRadians world yaw (0 = facing +Z) */
export function yawToFacing16(yawRadians) {
  const steps = 16;
  const slice = (Math.PI * 2) / steps;
  // Math.round(-0.5) is -0 in JS; the wrap convention: normalize yaw into
  // [0, 2π) first, then round to the nearest 22.5° cell (half-step rounds up).
  let yaw = ((yawRadians % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
  return Math.round(yaw / slice) % steps;
}

/** @param {number} facingIndex 0–15 */
export function facingName16(facingIndex) {
  return FACINGS_16[((facingIndex % 16) + 16) % 16];
}
