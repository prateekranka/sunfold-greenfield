// Every cost, rate, timing and radius in the skirmish lives here.
//
// Ported verbatim from `Sources/Domain/SkirmishTuning.swift`. Nothing in this
// file may be duplicated as a literal elsewhere. Values are the documented
// baseline for the first playable seed and may only be changed from recorded
// natural playthrough timing, never from intuition.

import { pool } from "./types.js";

export const TUNING = Object.freeze({
  // MARK: - Starting state
  startingResources: pool({ provisions: 180, matter: 160, lumen: 40, aether: 0 }),
  startingCitizens: 4,
  startingPopulationCap: 10,

  /** Yield seeded into each authored home deposit. Provisions are renewable. */
  homeDepositYields: pool({ provisions: Infinity, matter: 700, lumen: 550, aether: 180 }),
  offHomeDepositYields: pool({ provisions: Infinity, matter: 420, lumen: 300, aether: 180 }),

  // MARK: - Simulation
  simulationHz: 20,
  maxStepsPerFrame: 5,

  // MARK: - Gathering (units per second while actively working)
  gatherRates: pool({ provisions: 1.6, matter: 1.4, lumen: 1.1, aether: 0.9 }),

  /**
   * How much a citizen carries before walking a load home. Sets the rhythm of
   * the whole early game: too small and the fragment is a conveyor belt of
   * walking, too large and a node is worked in one uninterrupted stand.
   */
  carryCapacity: 10,

  /**
   * Quiet Core trickle so one early mistake cannot hard-lock a first match.
   * The AI receives the identical rule — this is not a player handicap.
   */
  coreTrickle: pool({ provisions: 0.25, matter: 0.2, lumen: 0.1, aether: 0 }),

  // MARK: - Units
  citizenCost: pool({ provisions: 50 }),
  pathfinderCost: pool({ provisions: 35, lumen: 10 }),
  vanguardCost: pool({ provisions: 45, matter: 20 }),
  quarrelCost: pool({ provisions: 35, lumen: 30 }),
  transportCapacity: 4,

  // MARK: - Buildings
  farmCost: pool({ matter: 70 }),
  farmBuildTime: 12,
  matterExtractorCost: pool({ matter: 60 }),
  matterExtractorBuildTime: 14,
  dwellingCost: pool({ matter: 55 }),
  dwellingBuildTime: 14,
  formationYardCost: pool({ matter: 110, lumen: 20 }),
  formationYardBuildTime: 18,
  lumenSpireCost: pool({ matter: 90, lumen: 45 }),
  lumenSpireBuildTime: 18,
  expansionOutpostCost: pool({ matter: 100, lumen: 30 }),
  expansionOutpostBuildTime: 20,
  expansionOutpostPopulationGrant: 2,
  dawnLoomCost: pool({ matter: 130, lumen: 50 }),
  dawnLoomBuildTime: 26,

  // MARK: - Age up
  voyagerCost: pool({ provisions: 180, matter: 180, lumen: 100, aether: 80 }),
  voyagerChannelDuration: 20,

  // MARK: - Production
  maxQueueLength: 10,
  /** Fraction of cost returned when a queued train item or foundation is cancelled. */
  cancelRefundFraction: 0.75,

  // MARK: - Victory
  dominionHoldDuration: 45,
  enemyCoreLife: 600,
  dominionCaptureRadius: 12,
  dominionContestDecay: 0.5,
  dominionVacancyReset: 8,
  dominionHoldSchedule: Object.freeze([
    Object.freeze({ after: 0, hold: 45 }),
    Object.freeze({ after: 420, hold: 30 }),
    Object.freeze({ after: 540, hold: 20 })
  ]),

  // MARK: - Presentation scale
  unitVisualScale: 1.25,

  // MARK: - Camera
  cameraPitchDegrees: 57,
  cameraDefaultZoom: 64,
  cameraMinZoom: 34,
  cameraMaxZoom: 165
});

export const STEP_DURATION = 1 / TUNING.simulationHz;

const BUILDING_COSTS = Object.freeze({
  farm: TUNING.farmCost,
  matterExtractor: TUNING.matterExtractorCost,
  dwelling: TUNING.dwellingCost,
  formationYard: TUNING.formationYardCost,
  lumenSpire: TUNING.lumenSpireCost,
  expansionOutpost: TUNING.expansionOutpostCost,
  dawnLoom: TUNING.dawnLoomCost,
  // Neither is buildable, so neither has a price. Listed rather than defaulted,
  // so adding a building forces the question.
  civilizationCore: pool(),
  dominionSpire: pool()
});

const BUILDING_TIMES = Object.freeze({
  farm: TUNING.farmBuildTime,
  matterExtractor: TUNING.matterExtractorBuildTime,
  dwelling: TUNING.dwellingBuildTime,
  formationYard: TUNING.formationYardBuildTime,
  lumenSpire: TUNING.lumenSpireBuildTime,
  expansionOutpost: TUNING.expansionOutpostBuildTime,
  dawnLoom: TUNING.dawnLoomBuildTime,
  civilizationCore: 0,
  dominionSpire: 0
});

const UNIT_COSTS = Object.freeze({
  citizen: TUNING.citizenCost,
  pathfinder: TUNING.pathfinderCost,
  vanguard: TUNING.vanguardCost,
  quarrel: TUNING.quarrelCost,
  lightTransport: pool(),
  bastionWalker: pool()
});

/** Build duration in fixed 20 Hz simulation ticks. */
const UNIT_BUILD_TICKS = Object.freeze({
  citizen: 280,
  pathfinder: 220,
  vanguard: 260,
  quarrel: 300,
  lightTransport: 0,
  bastionWalker: 0
});

export function buildingCost(kind) {
  const cost = BUILDING_COSTS[kind];
  if (!cost) throw new RangeError(`unknown building kind: ${kind}`);
  return cost;
}

export function buildTime(kind) {
  const time = BUILDING_TIMES[kind];
  if (time === undefined) throw new RangeError(`unknown building kind: ${kind}`);
  return time;
}

export function unitCost(kind) {
  const cost = UNIT_COSTS[kind];
  if (!cost) throw new RangeError(`unknown unit kind: ${kind}`);
  return cost;
}

export function unitBuildTicks(kind) {
  const ticks = UNIT_BUILD_TICKS[kind];
  if (ticks === undefined) throw new RangeError(`unknown unit kind: ${kind}`);
  return ticks;
}

export function depositYield(kind, region) {
  const isHome = region === "sunwovenHome" || region === "gravemarkHome";
  return (isHome ? TUNING.homeDepositYields : TUNING.offHomeDepositYields)[kind];
}

/** Seconds of Dominion hold required at a given match time. */
export function dominionHoldRequirement(elapsed) {
  let requirement = TUNING.dominionHoldDuration;
  for (const step of TUNING.dominionHoldSchedule) {
    if (elapsed >= step.after) requirement = step.hold;
  }
  return requirement;
}
