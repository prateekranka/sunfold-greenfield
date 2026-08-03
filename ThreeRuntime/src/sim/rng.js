// SplitMix64 — a small, fully specified generator, ported unchanged from
// `Sources/Simulation/DeterministicRandom.swift`.
//
// The simulation must replay identically from a seed, so it never touches
// `Math.random()` or any other source whose sequence is not pinned by our own
// state. Adding a draw in one subsystem must not shift another's numbers, which
// is what the tagged streams below are for.

import { add64, mul64, shr64, u64, xor64, hex64, parseHex64 } from "./int64.js";

const GOLDEN_GAMMA = u64(0x9e3779b9, 0x7f4a7c15);
const MIX_A = u64(0xbf58476d, 0x1ce4e5b9);
const MIX_B = u64(0x94d049bb, 0x133111eb);

const FNV_OFFSET_BASIS = u64(0xcbf29ce4, 0x84222325);
const FNV_PRIME = u64(0x00000100, 0x000001b3);

/** FNV-1a over the UTF-8 bytes of `text`, as a 64-bit value. */
export function fnv1a64(text) {
  let hash = FNV_OFFSET_BASIS;
  const bytes = utf8Bytes(text);
  for (let index = 0; index < bytes.length; index += 1) {
    hash = xor64(hash, u64(0, bytes[index]));
    hash = mul64(hash, FNV_PRIME);
  }
  return hash;
}

/**
 * UTF-8 encoding without `TextEncoder`, which is not guaranteed to exist in
 * every headless test host and would be one more thing to keep identical
 * between the test runner and WKWebView.
 */
function utf8Bytes(text) {
  const bytes = [];
  for (const character of String(text)) {
    let code = character.codePointAt(0);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code < 0x10000) {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      bytes.push(
        0xf0 | (code >> 18),
        0x80 | ((code >> 12) & 0x3f),
        0x80 | ((code >> 6) & 0x3f),
        0x80 | (code & 0x3f)
      );
    }
  }
  return bytes;
}

export class DeterministicRandom {
  /** @param {{hi:number, lo:number}} seed */
  constructor(seed) {
    // Avoid the all-zero state, which is a weak starting point for SplitMix64.
    this.state = seed.hi === 0 && seed.lo === 0 ? { ...GOLDEN_GAMMA } : { hi: seed.hi >>> 0, lo: seed.lo >>> 0 };
    /** Draws taken so far. Serialised, so a restored stream continues rather than restarts. */
    this.draws = 0;
  }

  /**
   * A generator derived from a seed and a stable string tag.
   *
   * Each subsystem draws from its own stream, so adding a call in one place
   * cannot shift the numbers every other system receives.
   */
  static stream(seed, tag) {
    return new DeterministicRandom(xor64(seed, fnv1a64(tag)));
  }

  /** The next raw 64-bit value. */
  next() {
    this.state = add64(this.state, GOLDEN_GAMMA);
    let z = this.state;
    z = mul64(xor64(z, shr64(z, 30)), MIX_A);
    z = mul64(xor64(z, shr64(z, 27)), MIX_B);
    this.draws += 1;
    return xor64(z, shr64(z, 31));
  }

  /**
   * Uniform in [0, 1).
   *
   * 24 bits is exactly what a binary float can represent without bias, and the
   * quotient of two exactly-representable values is itself exact — so this
   * number is the same on every engine that implements IEEE 754.
   */
  unitFloat() {
    return (this.next().hi >>> 8) / 16777216;
  }

  /** Uniform in [lower, upper). */
  float(lower, upper) {
    return lower + this.unitFloat() * (upper - lower);
  }

  /** Uniform integer in [0, bound). `bound` must be a positive safe integer. */
  int(bound) {
    if (!Number.isInteger(bound) || bound <= 0) {
      throw new RangeError(`random bound must be a positive integer: ${bound}`);
    }
    return Math.floor(this.unitFloat() * bound) % bound;
  }

  /** Serialised generator state — enough to continue the identical sequence. */
  snapshot() {
    return { state: hex64(this.state), draws: this.draws };
  }

  static restore(snapshot) {
    const generator = new DeterministicRandom(parseHex64(snapshot.state));
    generator.state = parseHex64(snapshot.state);
    generator.draws = snapshot.draws | 0;
    return generator;
  }
}

/**
 * The set of tagged streams the simulation owns.
 *
 * Registered by name rather than created on demand, so the tag list is
 * reviewable and a typo becomes an error instead of a silently separate stream.
 */
export const RNG_STREAM_TAGS = Object.freeze([
  "world.populate",
  "world.deposits",
  "movement.jitter",
  "gathering.station",
  "production.spawn",
  "adversary.plan"
]);

export class RandomStreams {
  constructor(seed) {
    this.seed = { hi: seed.hi >>> 0, lo: seed.lo >>> 0 };
    this.streams = new Map();
    for (const tag of RNG_STREAM_TAGS) {
      this.streams.set(tag, DeterministicRandom.stream(this.seed, tag));
    }
  }

  /** The generator for `tag`. Unknown tags are a programming error, not a new stream. */
  stream(tag) {
    const generator = this.streams.get(tag);
    if (!generator) throw new RangeError(`unregistered RNG stream tag: ${tag}`);
    return generator;
  }

  snapshot() {
    const out = {};
    for (const tag of RNG_STREAM_TAGS) out[tag] = this.streams.get(tag).snapshot();
    return out;
  }

  static restore(seed, snapshot) {
    const streams = new RandomStreams(seed);
    for (const tag of RNG_STREAM_TAGS) {
      if (!snapshot || !snapshot[tag]) throw new TypeError(`snapshot is missing RNG stream: ${tag}`);
      streams.streams.set(tag, DeterministicRandom.restore(snapshot[tag]));
    }
    return streams;
  }
}

/** Builds a 64-bit seed from a decimal or hexadecimal string, or a safe integer. */
export function seedFrom(value) {
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) {
    return u64(Math.floor(value / 4294967296), value >>> 0);
  }
  if (typeof value === "string") {
    if (/^[0-9a-f]{16}$/i.test(value)) return parseHex64(value.toLowerCase());
    if (/^\d+$/.test(value)) {
      const parsed = Number(value);
      if (Number.isSafeInteger(parsed)) return seedFrom(parsed);
    }
    // Any other text becomes a seed through the same hash the stream tags use,
    // so "sunwoven-opening" is a legitimate, stable seed rather than an error.
    return fnv1a64(value);
  }
  throw new TypeError(`cannot build a seed from: ${String(value)}`);
}
