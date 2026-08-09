// The shared vocabulary every simulation system speaks.
//
// World coordinates are `{ x, z }` on the ground plane, matching Three.js —
// the Swift original used a `SIMD2<Float>` whose second lane was this same
// ground axis under the name `y`. Points are plain objects rather than a class
// so a snapshot round trip is a structural copy with nothing to reconstruct.

/** The four legible resources. Order here is the order shown in the top bar. */
export const RESOURCE_KINDS = Object.freeze(["provisions", "matter", "lumen", "aether"]);

/** Renewable sources never deplete; the rest draw down a finite deposit. */
export function isRenewable(kind) {
  return kind === "provisions";
}

export const FACTIONS = Object.freeze(["sunwoven", "gravemark"]);

export function opponentOf(faction) {
  return faction === "sunwoven" ? "gravemark" : "sunwoven";
}

/**
 * What a unit is currently doing. Presentation reads this to choose a pose; it
 * never infers activity from position deltas.
 *
 * These are the same seven gameplay activities the Swift simulation owns. #20's
 * animation contract is expressed as controller substates inside
 * `animation.js`, deliberately **not** as new members of this list — the issue
 * forbids new gameplay enums, and an activity is a gameplay fact.
 */
export const ACTIVITY_TAGS = Object.freeze([
  "idle",
  "moving",
  "gathering",
  "boarding",
  "aboard",
  "constructing",
  "attacking"
]);

/** An activity is a tag plus, for the four that reference something, its id. */
export function activity(tag, subject = null) {
  if (!ACTIVITY_TAGS.includes(tag)) throw new RangeError(`unknown activity: ${tag}`);
  return { tag, subject };
}

export const IDLE = Object.freeze({ tag: "idle", subject: null });

export function point(x, z) {
  return { x, z };
}

export function addPoints(a, b) {
  return { x: a.x + b.x, z: a.z + b.z };
}

export function subtractPoints(a, b) {
  return { x: a.x - b.x, z: a.z - b.z };
}

export function scalePoint(p, scalar) {
  return { x: p.x * scalar, z: p.z * scalar };
}

export function length(p) {
  return Math.sqrt(p.x * p.x + p.z * p.z);
}

export function distance(a, b) {
  const dx = a.x - b.x;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dz * dz);
}

/** Squared distance — for comparisons, where the square root is wasted work. */
export function distanceSquared(a, b) {
  const dx = a.x - b.x;
  const dz = a.z - b.z;
  return dx * dx + dz * dz;
}

export function normalised(p) {
  const magnitude = length(p);
  if (magnitude < 1e-6) return { x: 0, z: 0 };
  return { x: p.x / magnitude, z: p.z / magnitude };
}

export function clonePoint(p) {
  return p ? { x: p.x, z: p.z } : null;
}

/** A bundle of the four resources. Used for stock, costs and rates alike. */
export function pool({ provisions = 0, matter = 0, lumen = 0, aether = 0 } = {}) {
  return { provisions, matter, lumen, aether };
}

export const ZERO_POOL = Object.freeze(pool());

export function clonePool(source) {
  return { provisions: source.provisions, matter: source.matter, lumen: source.lumen, aether: source.aether };
}

export function addPools(a, b) {
  return {
    provisions: a.provisions + b.provisions,
    matter: a.matter + b.matter,
    lumen: a.lumen + b.lumen,
    aether: a.aether + b.aether
  };
}

export function subtractPools(a, b) {
  return {
    provisions: a.provisions - b.provisions,
    matter: a.matter - b.matter,
    lumen: a.lumen - b.lumen,
    aether: a.aether - b.aether
  };
}

export function scalePool(source, scalar) {
  return {
    provisions: source.provisions * scalar,
    matter: source.matter * scalar,
    lumen: source.lumen * scalar,
    aether: source.aether * scalar
  };
}

/** True when this pool can pay `cost` in full. */
export function covers(have, cost) {
  return RESOURCE_KINDS.every((kind) => have[kind] >= cost[kind]);
}

/** Regions. Home and expansion anchors per faction, plus the neutral middle. */
export const REGION_IDS = Object.freeze([
  "sunwovenHome",
  "gravemarkHome",
  "sunwovenExpansion",
  "gravemarkExpansion",
  "dominion"
]);

export function homeRegion(faction) {
  return faction === "sunwoven" ? "sunwovenHome" : "gravemarkHome";
}

export function expansionRegion(faction) {
  return faction === "sunwoven" ? "sunwovenExpansion" : "gravemarkExpansion";
}

export function isHomeRegion(region) {
  return region === "sunwovenHome" || region === "gravemarkHome";
}
