// Every mobile thing and every fixed structure the simulation can own.
//
// Ported verbatim from `Sources/Domain/EntityKinds.swift`. Combat profiles are
// carried across even though the combat system itself is deferred in this
// migration — the numbers are the locked roster, and re-typing them later from
// a second source is how two roster tables drift apart.

export const UNIT_KINDS = Object.freeze([
  "citizen",
  "pathfinder",
  "vanguard",
  "quarrel",
  "lightTransport",
  "bastionWalker"
]);

export const BUILDING_KINDS = Object.freeze([
  "civilizationCore",
  "farm",
  "matterExtractor",
  "dwelling",
  "formationYard",
  "lumenSpire",
  "expansionOutpost",
  "dawnLoom",
  "dominionSpire"
]);

const UNITS = Object.freeze({
  citizen: {
    displayName: "Citizen",
    speed: 3.4,
    travelsVoid: false,
    canGather: true,
    isMilitary: false,
    canCaptureDominion: false,
    populationCost: 1,
    maxLife: 40,
    sightRange: 9,
    footprintRadius: 1.15
  },
  pathfinder: {
    displayName: "Pathfinder",
    speed: 4.6,
    travelsVoid: false,
    canGather: false,
    isMilitary: false,
    canCaptureDominion: false,
    populationCost: 1,
    maxLife: 45,
    sightRange: 20,
    footprintRadius: 1.15
  },
  vanguard: {
    displayName: "Vanguard",
    speed: 3.0,
    travelsVoid: false,
    canGather: false,
    isMilitary: true,
    canCaptureDominion: true,
    populationCost: 1,
    maxLife: 75,
    sightRange: 11,
    footprintRadius: 1.4
  },
  quarrel: {
    displayName: "Quarrel",
    speed: 3.2,
    travelsVoid: false,
    canGather: false,
    isMilitary: true,
    canCaptureDominion: true,
    populationCost: 1,
    maxLife: 50,
    sightRange: 13,
    footprintRadius: 1.15
  },
  lightTransport: {
    displayName: "Light Transport",
    speed: 5.2,
    travelsVoid: true,
    canGather: false,
    isMilitary: false,
    canCaptureDominion: false,
    populationCost: 0,
    maxLife: 140,
    sightRange: 14,
    footprintRadius: 4.0
  },
  bastionWalker: {
    displayName: "Bastion Walker",
    speed: 2.6,
    travelsVoid: false,
    canGather: false,
    isMilitary: true,
    canCaptureDominion: true,
    populationCost: 3,
    maxLife: 190,
    sightRange: 10,
    footprintRadius: 2.25
  }
});

const BUILDINGS = Object.freeze({
  civilizationCore: {
    displayName: "Civilization Core",
    maxLife: 600,
    footprintRadius: 5.5,
    acceptsDropOff: true,
    populationGrant: 0,
    trains: Object.freeze(["citizen"]),
    isNeutralObjective: false
  },
  farm: {
    displayName: "Farm",
    maxLife: 120,
    footprintRadius: 3.6,
    acceptsDropOff: true,
    populationGrant: 0,
    trains: Object.freeze([]),
    isNeutralObjective: false
  },
  matterExtractor: {
    displayName: "Matter Extractor",
    maxLife: 160,
    footprintRadius: 2.6,
    acceptsDropOff: true,
    populationGrant: 0,
    trains: Object.freeze([]),
    isNeutralObjective: false
  },
  dwelling: {
    displayName: "Dwelling",
    maxLife: 180,
    footprintRadius: 2.6,
    acceptsDropOff: false,
    populationGrant: 8,
    trains: Object.freeze([]),
    isNeutralObjective: false
  },
  formationYard: {
    displayName: "Formation Yard",
    maxLife: 260,
    footprintRadius: 4.0,
    acceptsDropOff: false,
    populationGrant: 0,
    trains: Object.freeze(["pathfinder", "vanguard"]),
    isNeutralObjective: false
  },
  lumenSpire: {
    displayName: "Lumen Spire",
    maxLife: 210,
    footprintRadius: 3.0,
    acceptsDropOff: false,
    populationGrant: 0,
    trains: Object.freeze(["quarrel"]),
    isNeutralObjective: false
  },
  expansionOutpost: {
    displayName: "Expansion Outpost",
    maxLife: 240,
    footprintRadius: 3.0,
    acceptsDropOff: false,
    populationGrant: 2,
    trains: Object.freeze([]),
    isNeutralObjective: false
  },
  dawnLoom: {
    displayName: "Dawn Loom",
    maxLife: 320,
    footprintRadius: 4.4,
    acceptsDropOff: false,
    populationGrant: 0,
    trains: Object.freeze([]),
    isNeutralObjective: false
  },
  dominionSpire: {
    displayName: "Dominion Spire",
    maxLife: 1200,
    footprintRadius: 4.0,
    acceptsDropOff: false,
    populationGrant: 0,
    trains: Object.freeze([]),
    isNeutralObjective: true
  }
});

export function unitKind(kind) {
  const entry = UNITS[kind];
  if (!entry) throw new RangeError(`unknown unit kind: ${kind}`);
  return entry;
}

export function buildingKind(kind) {
  const entry = BUILDINGS[kind];
  if (!entry) throw new RangeError(`unknown building kind: ${kind}`);
  return entry;
}

/** How close a citizen must be to work a resource node. */
export const DEPOSIT_WORK_RADIUS = 2.4;

/**
 * How many chunks one deposit is drawn as, and how many one carried load is.
 *
 * #20 makes gathering three authored contact loops per load, each removing one
 * visible chunk. Three is therefore a simulation number, not an animation
 * number — the carrier fills in thirds and the source depletes in thirds.
 */
export const CHUNKS_PER_LOAD = 3;
