// A canonical fingerprint of simulation state, defined once so every
// determinism test compares the same thing.
//
// Ported from `Sources/Simulation/WorldHash.swift` and widened for the
// JavaScript runtime, which now owns cargo, deposits, production queues and the
// animation-facing substate that the Swift hash never had to carry.
//
// **Quantising is the point.** Two runs that agree to the millimetre are the
// same run; comparing raw double bit patterns would fail on a difference no
// player could observe and no bug could cause. Sorting by entity id is the
// other half — insertion order is not a stable identity and would make the hash
// a coin flip rather than a measurement.

import { hex64, mul64, u64, xor64 } from "./int64.js";

/**
 * Bumped whenever the field order or the field set below changes. A recorded
 * hash from an older layout is not comparable to a new one, and a silent
 * comparison across layouts is exactly the failure this number prevents.
 */
export const WORLD_HASH_LAYOUT_VERSION = 3;

const OFFSET_BASIS = u64(0xcbf29ce4, 0x84222325);
const PRIME = u64(0x00000100, 0x000001b3);

/** The declaration order the hash walks. Reordering these changes every hash. */
export const FACTION_ORDER = Object.freeze(["sunwoven", "gravemark"]);
export const RESOURCE_ORDER = Object.freeze(["provisions", "matter", "lumen", "aether"]);

const INT64_MAX = u64(0x7fffffff, 0xffffffff);
const INT64_MIN = u64(0x80000000, 0x00000000);

export class Hasher {
  constructor() {
    this.value = OFFSET_BASIS;
  }

  /** Mixes one 64-bit value, little-endian, one byte at a time. */
  u64(value) {
    let hi = value.hi >>> 0;
    let lo = value.lo >>> 0;
    for (let index = 0; index < 4; index += 1) {
      this.value = mul64(xor64(this.value, u64(0, lo & 0xff)), PRIME);
      lo = lo >>> 8;
    }
    for (let index = 0; index < 4; index += 1) {
      this.value = mul64(xor64(this.value, u64(0, hi & 0xff)), PRIME);
      hi = hi >>> 8;
    }
    return this;
  }

  /** Mixes a non-negative safe integer (ids, counts, tick numbers). */
  int(value) {
    const rounded = Math.trunc(value);
    if (rounded < 0) return this.u64(twosComplement(rounded));
    return this.u64(u64(Math.floor(rounded / 4294967296), rounded >>> 0));
  }

  /**
   * Mixes a stable string tag rather than an enum ordinal, so reordering a
   * declaration cannot silently change a recorded hash.
   */
  tag(text) {
    let hash = OFFSET_BASIS;
    const value = String(text);
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      // Tags are ASCII by contract; anything else is a bug worth failing on.
      if (code > 0x7f) throw new TypeError(`hash tag must be ASCII: ${value}`);
      hash = mul64(xor64(hash, u64(0, code)), PRIME);
    }
    return this.u64(hash);
  }

  /** Hundredths — life, resources, construction progress. */
  centi(value) {
    return this.u64(quantise(value, 100));
  }

  /** Millimetres — every world coordinate. */
  milli(value) {
    return this.u64(quantise(value, 1000));
  }

  /** An optional entity id; absence is a stable zero rather than a skipped field. */
  optionalID(value) {
    return this.int(value === null || value === undefined ? 0 : value);
  }

  /** An optional world point; absence is a stable sentinel rather than a skipped field. */
  optionalPoint(point) {
    if (!point) return this.int(0).milli(0).milli(0);
    return this.int(1).milli(point.x).milli(point.z);
  }

  digest() {
    return hex64(this.value);
  }
}

function twosComplement(value) {
  const magnitude = Math.abs(value);
  const hi = Math.floor(magnitude / 4294967296) >>> 0;
  const lo = magnitude >>> 0;
  if (value >= 0) return u64(hi, lo);
  // Negate: invert and add one.
  const invertedLo = (~lo >>> 0) + 1;
  const carry = invertedLo > 0xffffffff ? 1 : 0;
  return u64(((~hi >>> 0) + carry) >>> 0, invertedLo >>> 0);
}

/**
 * Hundredths or millimetres, as a two's-complement bit pattern so negatives
 * hash cleanly. Non-finite values are pinned rather than thrown: an infinite
 * renewable deposit yield exists in this simulation on purpose and must not
 * crash a determinism test.
 */
export function quantise(value, scale) {
  if (!Number.isFinite(value)) {
    if (Number.isNaN(value)) throw new TypeError("cannot hash NaN — a rule produced an undefined number");
    return value > 0 ? INT64_MAX : INT64_MIN;
  }
  const scaled = Math.round(value * scale);
  if (!Number.isSafeInteger(scaled)) return scaled > 0 ? INT64_MAX : INT64_MIN;
  return twosComplement(scaled);
}

/**
 * The canonical fingerprint of the whole world.
 *
 * Two runs of one seed that agree here played the same match.
 */
export function worldHash(state) {
  const hasher = new Hasher();
  hasher.int(WORLD_HASH_LAYOUT_VERSION);
  hasher.int(state.clock.tick);

  for (const faction of FACTION_ORDER) {
    const pool = state.stock[faction];
    for (const kind of RESOURCE_ORDER) hasher.centi(pool ? pool[kind] : 0);
  }

  for (const unit of sortedByID(state.units)) {
    hasher.int(unit.id);
    hasher.tag(unit.kind);
    hasher.tag(unit.faction);
    hasher.milli(unit.position.x);
    hasher.milli(unit.position.z);
    hasher.centi(unit.life);
    hasher.tag(unit.activity.tag);
    hasher.optionalID(unit.activity.subject);
    hasher.tag(unit.cargo ? unit.cargo.kind : "none");
    hasher.centi(unit.cargo ? unit.cargo.amount : 0);
    hasher.optionalID(unit.assignment);
    hasher.optionalPoint(unit.destination);
    // The animation-facing substate is hashed because #20's contract makes it
    // event-authoritative: a resumed match whose citizen forgot it was holding
    // a tool is a different match, not a cosmetic difference.
    hasher.tag(unit.animation.state);
    hasher.int(unit.animation.loopIndex);
    hasher.int(unit.animation.phaseTicks);
    hasher.tag(unit.animation.leadHand);
    hasher.tag(unit.animation.toolHeld ? unit.animation.toolHeld : "none");
    hasher.int(unit.animation.carriedChunks);
    hasher.int(unit.animation.airborneChunks.length);
    for (const chunk of unit.animation.airborneChunks) {
      hasher.int(chunk.remainingTicks);
      hasher.tag(chunk.kind);
      hasher.centi(chunk.amount);
    }
  }

  for (const building of sortedByID(state.buildings)) {
    hasher.int(building.id);
    hasher.tag(building.kind);
    // "neutral" is a stable string like every other tag here, so the Dominion
    // Spire folds into the fingerprint without a faction.
    hasher.tag(building.faction ?? "neutral");
    hasher.milli(building.position.x);
    hasher.milli(building.position.z);
    hasher.centi(building.life);
    hasher.centi(building.constructionProgress);
    hasher.int(building.installedComponents);
  }

  for (const deposit of sortedByID(state.deposits)) {
    hasher.int(deposit.id);
    hasher.tag(deposit.kind);
    hasher.milli(deposit.position.x);
    hasher.milli(deposit.position.z);
    hasher.centi(deposit.remaining);
    hasher.int(deposit.chunksRemaining);
  }

  const queueIDs = [...state.productionQueues.keys()].sort((left, right) => left - right);
  for (const buildingID of queueIDs) {
    const queue = state.productionQueues.get(buildingID);
    if (!queue || queue.items.length === 0) continue;
    hasher.int(buildingID);
    // The hold reason decides whether the front spawns or waits, and the
    // started flag decides the refund fraction the queue would hand back — both
    // change the match's future, so both are fingerprinted.
    hasher.tag(queue.heldReason ?? "none");
    hasher.int(queue.items.length);
    for (const item of queue.items) {
      hasher.tag(item.kind);
      hasher.int(item.progressTicks);
      hasher.int(item.hasStarted ? 1 : 0);
    }
  }

  // The scheduled-order queue decides the match's future like any other state,
  // so it is fingerprinted too: two runs whose states agree but whose pending
  // orders differ are not the same match. The recorded input script is history
  // and stays out, like the event log.
  const orders = state.orders;
  hasher.int(orders.sequence);
  hasher.int(orders.pending.length);
  for (const order of orders.pending) {
    hasher.int(order.scheduledTick);
    hasher.int(order.sequence);
    hasher.tag(order.kind);
    hasher.tag(canonicalPayload(order.payload));
  }

  return hasher.digest();
}

/**
 * A stable serialisation of an order payload for hashing. Keys are sorted
 * recursively, so two payloads that name the same fields in a different
 * insertion order hash identically — only the logical content is compared.
 */
function canonicalPayload(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value ?? null);
  if (Array.isArray(value)) return `[${value.map(canonicalPayload).join(",")}]`;
  const keys = Object.keys(value).sort();
  const fields = keys.map((key) => `${JSON.stringify(key)}:${canonicalPayload(value[key])}`);
  return `{${fields.join(",")}}`;
}

function sortedByID(collection) {
  return [...collection.values()].sort((left, right) => left.id - right.id);
}
