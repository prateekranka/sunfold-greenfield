// Stable, durable identity for everything the simulation owns.
//
// Architectural rule, carried over unchanged from the Swift implementation:
// never use array position as gameplay identity. Every unit, building, deposit
// and queue item carries an id for its whole life, and ids are handed out in a
// deterministic, replayable order.

/** Allocates entity ids in a deterministic, replayable order. */
export class EntityIDAllocator {
  constructor(next = 1) {
    this.next = next >>> 0;
  }

  allocate() {
    const id = this.next;
    // Wrapping like the Swift `&+=` it was ported from. Reaching 2^32 entities
    // in one match is not a scenario this game has, but a wrap is still defined
    // behaviour rather than an overflow trap in the middle of a step.
    this.next = (this.next + 1) >>> 0;
    if (this.next === 0) this.next = 1;
    return id;
  }

  snapshot() {
    return { next: this.next };
  }

  static restore(snapshot) {
    return new EntityIDAllocator(snapshot.next);
  }
}

/**
 * An insertion-ordered map keyed by entity id.
 *
 * Every rule that walks entities sorts by id first — insertion order is not a
 * stable identity across a save/restore round trip, and iterating a plain
 * object would additionally reorder integer-like keys behind our back. Keeping
 * one type for all four collections means no system can forget the rule.
 */
export class EntityStore {
  constructor(entries = []) {
    this.map = new Map(entries);
    this.orderedCache = null;
  }

  get size() {
    return this.map.size;
  }

  get(id) {
    return this.map.get(id);
  }

  has(id) {
    return this.map.has(id);
  }

  set(id, entity) {
    this.map.set(id, entity);
    this.orderedCache = null;
    return entity;
  }

  delete(id) {
    const removed = this.map.delete(id);
    if (removed) this.orderedCache = null;
    return removed;
  }

  values() {
    return this.map.values();
  }

  keys() {
    return this.map.keys();
  }

  /**
   * Every entity in ascending id order — the only order a rule may iterate in.
   *
   * Cached because a 20 Hz step walks this several times over 80+ entities and
   * re-sorting each pass is measurable at benchmark density. The cache is
   * dropped on any structural change, so it can never serve a stale set.
   */
  ordered() {
    if (this.orderedCache === null) {
      this.orderedCache = [...this.map.values()].sort((left, right) => left.id - right.id);
    }
    return this.orderedCache;
  }

  /** Ascending ids, snapshotted — safe to mutate the store while iterating. */
  orderedIDs() {
    return this.ordered().map((entity) => entity.id);
  }
}
