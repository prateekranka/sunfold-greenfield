// Exact 64-bit unsigned integer arithmetic on pairs of 32-bit halves.
//
// The simulation's RNG and its world hash are both specified as 64-bit
// operations. A JavaScript Number cannot hold 64 bits of integer exactly, and
// BigInt costs an allocation per operation — far too much for a generator that
// is drawn inside a 20 Hz step alongside 80 animated units. Splitting into two
// uint32 halves keeps every operation exact and allocation-free in the hot path.
//
// Every function here is total: it wraps modulo 2^64 exactly like the Swift
// `&+` / `&*` operators the original rules were written against.

/** Creates a 64-bit value from a high and a low 32-bit half. */
export function u64(hi, lo) {
  return { hi: hi >>> 0, lo: lo >>> 0 };
}

/** Wrapping 64-bit addition. */
export function add64(a, b) {
  const lo = a.lo + b.lo;
  const carry = lo > 0xffffffff ? 1 : 0;
  return { hi: (a.hi + b.hi + carry) >>> 0, lo: lo >>> 0 };
}

/**
 * The unsigned 64-bit product of two 32-bit values.
 *
 * Split into 16-bit limbs so no intermediate exceeds 2^32 — a double holds
 * every partial product exactly, which is what makes this identical to the
 * hardware 64-bit multiply rather than merely close to it.
 */
function umul32(a, b) {
  const aLow = a & 0xffff;
  const aHigh = a >>> 16;
  const bLow = b & 0xffff;
  const bHigh = b >>> 16;

  const lowLow = aLow * bLow;
  const lowHigh = aLow * bHigh;
  const highLow = aHigh * bLow;
  const highHigh = aHigh * bHigh;

  const middle = (lowLow >>> 16) + (lowHigh & 0xffff) + (highLow & 0xffff);
  const lo = (((middle & 0xffff) << 16) | (lowLow & 0xffff)) >>> 0;
  const hi = (highHigh + (lowHigh >>> 16) + (highLow >>> 16) + (middle >>> 16)) >>> 0;
  return { hi, lo };
}

/** Wrapping 64-bit multiplication. */
export function mul64(a, b) {
  const low = umul32(a.lo, b.lo);
  const hi = (low.hi + Math.imul(a.hi, b.lo) + Math.imul(a.lo, b.hi)) >>> 0;
  return { hi, lo: low.lo };
}

/** Bitwise exclusive or. */
export function xor64(a, b) {
  return { hi: (a.hi ^ b.hi) >>> 0, lo: (a.lo ^ b.lo) >>> 0 };
}

/** Logical right shift by 0…63 bits. */
export function shr64(value, bits) {
  if (bits === 0) return { hi: value.hi, lo: value.lo };
  if (bits < 32) {
    return {
      hi: value.hi >>> bits,
      lo: ((value.lo >>> bits) | (value.hi << (32 - bits))) >>> 0
    };
  }
  return { hi: 0, lo: value.hi >>> (bits - 32) };
}

/** Lower-case, zero-padded, 16-character hexadecimal. The canonical text form. */
export function hex64(value) {
  return value.hi.toString(16).padStart(8, "0") + value.lo.toString(16).padStart(8, "0");
}

/** Parses the canonical text form back into a 64-bit value. */
export function parseHex64(text) {
  if (typeof text !== "string" || !/^[0-9a-f]{16}$/.test(text)) {
    throw new TypeError(`not a canonical 64-bit hex value: ${String(text)}`);
  }
  return u64(parseInt(text.slice(0, 8), 16), parseInt(text.slice(8), 16));
}

export function equals64(a, b) {
  return a.hi === b.hi && a.lo === b.lo;
}
