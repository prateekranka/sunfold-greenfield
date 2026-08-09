// mapgen/rng.js — deterministic randomness for the Sunfold WorldMap generator.
//
// The simulation contract requires: no SystemRandomNumberGenerator, no
// Double.random; every subsystem draws from its own tagged stream so that
// adding a draw in one place cannot shift another subsystem's numbers.
//
// Streams are derived as hash(seed, tag) -> mulberry32. The seed is locked at
// 20260726 for the first playable map (see README / PROJECT_STATE).

/** FNV-1a style string hash -> uint32. */
export function hashString(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** mulberry32 — tiny, fast, good-enough deterministic PRNG. Returns [0,1). */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * A tagged stream: mulberry32 seeded from hash(seed, tag).
 * Deterministic across platforms (all integer math, no Math.* randomness).
 */
export function stream(seed, tag) {
  return mulberry32((hashString(tag) ^ (seed >>> 0)) >>> 0);
}

/* ------------------------------------------------------------------ *
 *  Value noise (deterministic, integer-hash based). Two octaves fbm.  *
 * ------------------------------------------------------------------ */

function hash2(ix, iz, seed) {
  let h = (seed ^ Math.imul(ix, 374761393) ^ Math.imul(iz, 668265263)) >>> 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

function smooth(t) {
  return t * t * (3 - 2 * t);
}

/** Deterministic value noise in [0,1]. x,z are world coordinates. */
export function valueNoise(x, z, seed) {
  const ix = Math.floor(x);
  const iz = Math.floor(z);
  const fx = smooth(x - ix);
  const fz = smooth(z - iz);
  const a = hash2(ix, iz, seed);
  const b = hash2(ix + 1, iz, seed);
  const c = hash2(ix, iz + 1, seed);
  const d = hash2(ix + 1, iz + 1, seed);
  const top = a + (b - a) * fx;
  const bot = c + (d - c) * fx;
  return top + (bot - top) * fz;
}

/** Two-octave fbm in [0,1]. */
export function fbm2(x, z, seed) {
  return (
    valueNoise(x, z, seed) * 0.6 +
    valueNoise(x * 2.13 + 17.7, z * 2.13 - 9.3, seed ^ 0x9e3779b9) * 0.4
  );
}

/** Deterministic FNV-1a over a string — for map identity hashing. */
export function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}
