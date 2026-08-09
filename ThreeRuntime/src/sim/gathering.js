// The gather → carry → deliver → return cycle.
//
// Ported from `Sources/Simulation/GatheringSystem.swift`. Pure and
// deterministic: it reads state and a step duration and writes state. It never
// touches presentation and never reads frame timing.
//
// The cycle still has no phase field. Which leg a citizen is on is *derived*
// from what it is carrying, so no enum can fall out of step with the load it
// describes. The one persistent decision — which node this citizen works —
// lives on the unit as `assignment`, which is what makes gathering a loop
// rather than an errand the player re-issues after every delivery.
//
// ## The one deliberate change from the Swift original
//
// Swift extracted `gatherRates[kind] * deltaTime` straight into `unit.cargo`
// every tick. #20 makes the transfer *event-authoritative*: a chunk leaves the
// pile at `gather_contact` and becomes cargo at `payload_attach`, and an
// interruption between those two instants must still land the chunk. So the
// per-tick extraction now accrues into `unit.pending` — a speculative
// accumulator that has taken nothing from anything — and the deposit is only
// debited at `gather_contact`, when `AnimationController` calls `commitContact`.
//
// The **rate rule is unchanged**: a citizen standing in range of its node still
// accrues exactly `gatherRates[kind] * deltaTime` per tick, exactly as in Swift,
// including the ticks it spends settling, reaching for the scraper and playing
// the start clip. Throughput therefore matches the Swift original tick for tick;
// only the moment of transfer moved.
//
// ## Conservation
//
// At every instant:
//
//   extracted from deposits == airborne + committed cargo + credited stock
//
// `pending` is deliberately outside that ledger, because nothing has been taken
// from a deposit while it accrues. Discarding pending on an interruption
// destroys nothing. The three commit points are the only places resources move:
//
//   commitContact  deposit.remaining -> airborne chunk
//   commitPayload  airborne chunk    -> unit.cargo
//   commitDeposit  unit.cargo        -> faction stock
//
// Each is a strict hand-off of the same number. Nothing is created and nothing
// is destroyed, which is the property the determinism suite asserts.

import { activity, IDLE, distance } from "./types.js";
import { TUNING } from "./tuning.js";
import { unitKind, buildingKind, DEPOSIT_WORK_RADIUS, CHUNKS_PER_LOAD } from "./kinds.js";

/**
 * How many distinct standing positions a node offers.
 *
 * Six, because a citizen's footprint is 1.15 m and six stations on a 2.28 m
 * ring sit 2.4 m apart — just clear of each other. More slots would let workers
 * interpenetrate, which is what a single shared approach point already did.
 */
export const STATION_COUNT = 6;

/**
 * Roughly a footprint. Tight enough that a citizen visibly *stands* at its
 * station rather than stopping wherever it first came into range.
 */
const ARRIVAL_TOLERANCE = 0.9;

/** Slack on the capacity comparison, so float residue is not "not quite full". */
const LOAD_EPSILON = 1e-6;

const NO_LEG = Object.freeze({
  leg: "none",
  deposit: null,
  target: null,
  station: null,
  atStation: false,
  atTarget: false,
  canExtract: false
});

// MARK: - Field defences

/**
 * `pending` is not in the pinned Unit shape because it did not exist in Swift;
 * it is required by the event-authoritative transfer above. Creating it lazily
 * means a `populate.js` written against the pinned shape still produces units
 * this system can drive, and a restored snapshot that predates the field heals
 * on its first step rather than throwing.
 */
function ensureFields(unit) {
  if (unit.cargo === undefined) unit.cargo = null;
  if (unit.assignment === undefined) unit.assignment = null;
  if (unit.pending === undefined) unit.pending = null;
  if (unit.destination === undefined) unit.destination = null;
  return unit;
}

// MARK: - Load accounting

function airborneAmount(unit) {
  const animation = unit.animation;
  if (!animation || !animation.airborneChunks || animation.airborneChunks.length === 0) return 0;
  let total = 0;
  for (const chunk of animation.airborneChunks) total += chunk.amount;
  return total;
}

function committedAmount(unit) {
  return unit.cargo ? unit.cargo.amount : 0;
}

function pendingAmount(unit) {
  return unit.pending ? unit.pending.amount : 0;
}

/**
 * Everything that is already the citizen's, whether on its back or mid-arc.
 *
 * `pending` is excluded on purpose. If it counted, a citizen would flip between
 * "full" and "not full" as pending was cleared on the way to a drop-off, and it
 * would walk back to the node it had just left.
 */
function realisedLoad(unit) {
  return committedAmount(unit) + airborneAmount(unit);
}

/**
 * True once a citizen may not stand at a node and take more.
 *
 * Airborne counts: those chunks are already committed to this carrier and will
 * land whatever happens next.
 */
function isFull(unit) {
  return realisedLoad(unit) >= TUNING.carryCapacity - LOAD_EPSILON;
}

/**
 * True when the citizen may walk away from its station.
 *
 * A tool in hand or a chunk in the air is an authored obligation from #20: the
 * scraper is returned to its rest before exit, and an airborne chunk completes
 * its arc. Leaving the station with either outstanding would strand them, so
 * the deliver leg holds position until `AnimationController` has finished its
 * cleanup. This reads `unit.animation` but never writes it.
 */
function canLeaveStation(unit) {
  const animation = unit.animation;
  if (!animation) return true;
  if (animation.toolHeld !== null && animation.toolHeld !== undefined) return false;
  return !animation.airborneChunks || animation.airborneChunks.length === 0;
}

// MARK: - Geometry

/**
 * Clamps a work point to somewhere the citizen may legally stand.
 *
 * Swift routed this through `MovementSystem.resolveDestination`, which for a
 * grounded citizen reduces to exactly this call on the map. Going to the map
 * directly keeps `gathering.js` off the movement module's import edge — the two
 * are written by different owners — while applying the identical rule.
 */
function resolveStandingPoint(state, unit, requested) {
  const map = state.map;
  if (!map || typeof map.clampToLand !== "function") return { x: requested.x, z: requested.z };
  const clamped = map.clampToLand(requested, unitKind(unit.kind).footprintRadius);
  return clamped ? { x: clamped.x, z: clamped.z } : null;
}

/** A point `standOff` metres short of `target`, on the line from `origin`. */
function approachPoint(target, origin, standOff) {
  const awayX = origin.x - target.x;
  const awayZ = origin.z - target.z;
  const magnitude = Math.sqrt(awayX * awayX + awayZ * awayZ);
  if (magnitude <= 1e-4) return { x: target.x, z: target.z };
  return {
    x: target.x + (awayX / magnitude) * standOff,
    z: target.z + (awayZ / magnitude) * standOff
  };
}

/**
 * The nearest complete, drop-off-accepting building of this citizen's faction.
 *
 * Walked in ascending id order with a strict `<`, so two equidistant Cores
 * resolve to the lower id on every replay.
 */
function nearestDropOff(state, unit) {
  let best = null;
  let bestDistance = Infinity;
  for (const building of state.buildings.ordered()) {
    if (building.faction !== unit.faction) continue;
    if (!(building.constructionProgress >= 1)) continue;
    if (!buildingKind(building.kind).acceptsDropOff) continue;
    const candidate = distance(building.position, unit.position);
    if (candidate < bestDistance) {
      best = building;
      bestDistance = candidate;
    }
  }
  return best;
}

function dropOffReach(building) {
  return buildingKind(building.kind).footprintRadius + DEPOSIT_WORK_RADIUS;
}

// MARK: - Leg descriptors

function extractDescriptor(state, unit, deposit) {
  const station = resolveStandingPoint(state, unit, GatheringSystem.workStation(deposit, unit)) || {
    x: deposit.position.x,
    z: deposit.position.z
  };
  const atStation =
    distance(unit.position, station) <= ARRIVAL_TOLERANCE &&
    distance(unit.position, deposit.position) <= DEPOSIT_WORK_RADIUS + ARRIVAL_TOLERANCE;
  const room = TUNING.carryCapacity - realisedLoad(unit);
  const compatible = !unit.cargo || unit.cargo.kind === deposit.kind;
  return {
    leg: "extract",
    deposit,
    target: null,
    station,
    atStation,
    atTarget: false,
    canExtract: room > LOAD_EPSILON && deposit.remaining > 0 && compatible
  };
}

function deliverDescriptor(state, unit) {
  const target = nearestDropOff(state, unit);
  if (!target) {
    // Nowhere to deliver. The load is held, never deleted — #20's "idle loaded
    // if none exists", and the resource becomes deliverable the moment a
    // drop-off exists again.
    return { ...NO_LEG, leg: "hold" };
  }
  return {
    leg: "deliver",
    deposit: null,
    target,
    station: null,
    atStation: false,
    atTarget: distance(unit.position, target.position) <= dropOffReach(target),
    canExtract: false
  };
}

// MARK: - Legs

/** Walk to this citizen's station on the node, then accrue. */
function gatherLeg(state, unit, deposit, deltaTime) {
  unit.activity = activity("gathering", deposit.id);

  // Resolving up front means a station clamped off the fragment's edge becomes
  // a reachable point rather than a destination the citizen walks at forever.
  const station = resolveStandingPoint(state, unit, GatheringSystem.workStation(deposit, unit)) || {
    x: deposit.position.x,
    z: deposit.position.z
  };

  if (distance(unit.position, station) > ARRIVAL_TOLERANCE) {
    unit.destination = station;
    // Nothing accrues while walking, and any speculative accrual from a
    // previous stand is abandoned rather than carried across the trip.
    unit.pending = null;
    return;
  }

  unit.destination = null;

  // Standing at a station always satisfies this; the slack only matters when a
  // station was clamped, and it is still unambiguously "at the rock" rather
  // than reaching the node from across the fragment.
  if (distance(unit.position, deposit.position) > DEPOSIT_WORK_RADIUS + ARRIVAL_TOLERANCE) return;

  // Carrying one kind at a time. Switching nodes mid-load would silently
  // convert what is already on a citizen's back, so a partial load of the wrong
  // kind is delivered before the new node is worked.
  if (unit.cargo && unit.cargo.kind !== deposit.kind) return;
  if (unit.pending && unit.pending.kind !== deposit.kind) unit.pending = null;

  const alreadyPending = pendingAmount(unit);
  const room = TUNING.carryCapacity - realisedLoad(unit) - alreadyPending;
  if (room <= LOAD_EPSILON) return;

  // `remaining` is not debited until `gather_contact`, so two citizens on one
  // node must not both accrue the last of it. Each reserves against what is
  // left after its own outstanding claim; the commit clamps again.
  const availableYield = deposit.remaining - alreadyPending;
  if (!(availableYield > 0)) return;

  const rate = TUNING.gatherRates[deposit.kind];
  const extracted = Math.min(rate * deltaTime, room, availableYield);
  if (!(extracted > 0)) return;

  unit.pending = { kind: deposit.kind, amount: alreadyPending + extracted };
}

/**
 * Walk the load to the nearest accepting building.
 *
 * The hand-over itself is no longer here: it happens at `deposit_release`,
 * fired by `AnimationController` at the deepest tip/dump pose, which calls
 * `commitDeposit`. This leg only decides where to stand.
 */
function deliverLeg(state, unit) {
  // An outstanding tool or airborne chunk is finished at the node first. #20
  // requires the scraper back on its rest before exit and the chunk landed.
  if (!canLeaveStation(unit)) {
    unit.destination = null;
    return;
  }
  unit.pending = null;

  const descriptor = deliverDescriptor(state, unit);
  if (descriptor.leg === "hold") {
    unit.destination = null;
    unit.activity = IDLE;
    return;
  }

  const target = descriptor.target;
  if (!descriptor.atTarget) {
    const reach = dropOffReach(target);
    const approach = approachPoint(target.position, unit.position, reach * 0.85);
    unit.destination = resolveStandingPoint(state, unit, approach);
    return;
  }

  unit.destination = null;
}

function advance(state, unit, deltaTime) {
  const deposit = state.deposits.get(unit.assignment);

  // A node that has been exhausted or removed ends the assignment, but not the
  // trip: a citizen holding a load still walks it home first. The assignment is
  // kept until the load is delivered, which is what keeps `advance` running for
  // this unit at all.
  if (!deposit || !(deposit.remaining > 0)) {
    if (!unit.cargo && canLeaveStation(unit)) {
      unit.assignment = null;
      unit.pending = null;
      unit.destination = null;
      unit.activity = IDLE;
    } else {
      deliverLeg(state, unit);
    }
    return;
  }

  if (isFull(unit)) {
    if (canLeaveStation(unit)) {
      deliverLeg(state, unit);
    } else {
      // Full but still winding the authored cycle down at the node. Hold the
      // station; the controller returns the tool and lands the chunk, and the
      // deliver leg starts on the tick after that.
      unit.destination = null;
    }
    return;
  }

  gatherLeg(state, unit, deposit, deltaTime);
}

// MARK: - System

export const GatheringSystem = {
  /** Advances every citizen with a gather assignment, in ascending id order. */
  step(state, deltaTime) {
    for (const id of state.units.orderedIDs()) {
      const unit = state.units.get(id);
      if (!unit) continue;
      ensureFields(unit);
      if (unit.assignment === null) continue;
      if (!unitKind(unit.kind).canGather) continue;
      if (unit.activity && unit.activity.tag === "aboard") continue;
      advance(state, unit, deltaTime);
    }
  },

  /**
   * Assigns citizens to work a deposit.
   *
   * Anything in the selection that cannot gather is walked to the node instead,
   * so a mixed selection does something sensible rather than half-ignoring the
   * tap. Ids are sorted so a multi-select resolves identically on replay.
   */
  orderGather(state, unitIDs, depositID) {
    const deposit = state.deposits.get(depositID);
    if (!deposit || !(deposit.remaining > 0)) return;

    const ids = [...unitIDs].sort((left, right) => left - right);
    for (const id of ids) {
      const unit = state.units.get(id);
      if (!unit) continue;
      ensureFields(unit);
      if (!unitKind(unit.kind).canGather) {
        const point = resolveStandingPoint(state, unit, deposit.position);
        if (point) unit.destination = point;
        continue;
      }
      unit.assignment = depositID;
      unit.activity = activity("gathering", depositID);
    }
  },

  /**
   * The fixed spot this citizen works this node from.
   *
   * A pure function of the node and the unit's durable id, which buys two
   * things at once. Workers fan out around the rock instead of converging on
   * one point and standing inside each other. And because the station never
   * moves, a citizen returning from a delivery walks back to the spot it left,
   * which reads as its own working position rather than a scramble for a gap.
   */
  workStation(deposit, unit) {
    const slot = (unit.id >>> 0) % STATION_COUNT;
    const angle = (slot / STATION_COUNT) * 2 * Math.PI;
    const radius = DEPOSIT_WORK_RADIUS * 0.95;
    return {
      x: deposit.position.x + Math.sin(angle) * radius,
      z: deposit.position.z + Math.cos(angle) * radius
    };
  },

  isFull,

  /**
   * Which leg this citizen is on, computed without mutating anything.
   *
   * `AnimationController` needs the same answer `step` acts on, one system
   * later in the tick, and deriving it twice from different rules is how two
   * copies of a decision drift apart.
   */
  legOf(state, unit) {
    if (!unitKind(unit.kind).canGather) return NO_LEG;
    if (unit.activity && unit.activity.tag === "aboard") return NO_LEG;

    const assignment = unit.assignment === undefined ? null : unit.assignment;
    const deposit = assignment === null ? null : state.deposits.get(assignment);

    if (!deposit || !(deposit.remaining > 0)) {
      if (!unit.cargo) return NO_LEG;
      return deliverDescriptor(state, unit);
    }

    if (isFull(unit)) {
      if (canLeaveStation(unit)) return deliverDescriptor(state, unit);
      // Winding down at the node — still the extract leg, with nothing left to
      // extract, so the controller finishes its cycle instead of being cut off.
      const descriptor = extractDescriptor(state, unit, deposit);
      descriptor.canExtract = false;
      return descriptor;
    }

    return extractDescriptor(state, unit, deposit);
  },

  /** True when this citizen still owes the node a tool or a landing chunk. */
  canLeaveStation,

  /**
   * The `gather_contact` commit. One chunk leaves the pile.
   *
   * Everything accrued since the last contact is debited from the node in one
   * move and handed back as the chunk that is about to fly. The clamp against
   * `remaining` is what keeps two citizens sharing the last of a node from
   * driving it negative. Returns `null` when there was nothing to take, in
   * which case the pile is untouched — no chunk is spent for no resource.
   */
  commitContact(state, unit) {
    const pending = unit.pending;
    unit.pending = null;
    if (!pending || !(pending.amount > 0)) return null;

    const deposit = state.deposits.get(unit.assignment);
    if (!deposit) return null;
    if (deposit.kind !== pending.kind) return null;

    const amount = Math.min(pending.amount, deposit.remaining);
    if (!(amount > 0)) return null;

    deposit.remaining -= amount;

    if (deposit.chunksRemaining > 0) deposit.chunksRemaining -= 1;
    // The visible pile is drawn as three loose chunks. It refills the moment it
    // empties while yield remains, so a node reads as "still worth working"
    // right up to the tick it is spent.
    if (deposit.chunksRemaining <= 0 && deposit.remaining > 0) {
      deposit.chunksRemaining = CHUNKS_PER_LOAD;
    }

    return { kind: deposit.kind, amount, depositID: deposit.id };
  },

  /**
   * The `payload_attach` commit. An arriving chunk becomes carrier cargo.
   *
   * A mismatched kind cannot happen — `gatherLeg` refuses to accrue a second
   * kind — but if it ever did, the amount is refunded to the node it came from,
   * or failing that credited to the faction. Both conserve; dropping it would
   * not, and #20 forbids discarding committed work.
   */
  commitPayload(state, unit, chunk) {
    if (!chunk || !(chunk.amount > 0)) return 0;
    ensureFields(unit);

    if (!unit.cargo) {
      unit.cargo = { kind: chunk.kind, amount: chunk.amount };
      return chunk.amount;
    }
    if (unit.cargo.kind === chunk.kind) {
      unit.cargo.amount += chunk.amount;
      return chunk.amount;
    }

    const source = chunk.depositID === undefined ? null : state.deposits.get(chunk.depositID);
    if (source && source.kind === chunk.kind) {
      source.remaining += chunk.amount;
      return 0;
    }
    const pool = state.stock[unit.faction];
    if (pool) pool[chunk.kind] += chunk.amount;
    return 0;
  },

  /**
   * The `deposit_release` commit. All committed cargo transfers atomically.
   *
   * Atomic by construction: one read, one add, one clear, with nothing between
   * them that can fail. There is no partial delivery to leave a citizen holding
   * a remainder it can never spend.
   */
  commitDeposit(state, unit) {
    const cargo = unit.cargo;
    if (!cargo || !(cargo.amount > 0)) {
      unit.cargo = null;
      return null;
    }
    const pool = state.stock[unit.faction];
    if (!pool) return null;
    pool[cargo.kind] += cargo.amount;
    unit.cargo = null;
    return { kind: cargo.kind, amount: cargo.amount };
  },

  /**
   * Abandons speculative accrual. Used by an interruption that reverses before
   * `gather_contact` fires. Nothing has left a deposit, so nothing is lost.
   */
  abortPending(unit) {
    unit.pending = null;
  },

  /** Public for `populate.js` and for restores that predate the `pending` field. */
  ensureFields
};
