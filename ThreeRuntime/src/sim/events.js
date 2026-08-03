// The authoritative simulation events defined by the citizen contract in #20.
//
// These are **not** gameplay enums and they are not bridge messages. They are
// the in-runtime record of the moment a rule committed — the point after which
// an interruption must preserve the result rather than reverse it. Presentation
// reads them to drive animation; the simulation reads them to know what may no
// longer be undone.

/** Every event kind the citizen work cycle can produce. Order is the review order. */
export const EVENT_KINDS = Object.freeze([
  "tool_attach",
  "tool_release",
  "gather_contact",
  "payload_attach",
  "deposit_release",
  "construct_contact"
]);

/**
 * A bounded, ordered trace of the events produced this match.
 *
 * Bounded because a five-minute benchmark run at 20 Hz would otherwise grow an
 * unbounded array inside the render process; the cap is far above anything one
 * acceptance capture needs, and overflow is counted rather than silently
 * dropped so a trace can never claim to be complete when it is not.
 */
export class EventLog {
  constructor(capacity = 20000) {
    this.capacity = capacity;
    this.entries = [];
    this.dropped = 0;
    this.counts = Object.fromEntries(EVENT_KINDS.map((kind) => [kind, 0]));
  }

  emit(kind, tick, unitID, detail = {}) {
    if (!EVENT_KINDS.includes(kind)) throw new RangeError(`unknown simulation event: ${kind}`);
    this.counts[kind] += 1;
    if (this.entries.length >= this.capacity) {
      this.dropped += 1;
      return;
    }
    this.entries.push({ kind, tick, unitID, ...detail });
  }

  /** Every event for one unit, in the order it fired. */
  forUnit(unitID) {
    return this.entries.filter((entry) => entry.unitID === unitID);
  }

  clear() {
    this.entries.length = 0;
    this.dropped = 0;
    for (const kind of EVENT_KINDS) this.counts[kind] = 0;
  }

  /**
   * Deliberately excluded from the world hash and from save snapshots.
   *
   * The trace is an observation of the run, not state the run depends on —
   * hashing it would make a save taken mid-match differ from the same match
   * replayed from tick zero purely because one of them remembered more history.
   */
  summary() {
    return { total: this.entries.length, dropped: this.dropped, counts: { ...this.counts } };
  }
}
