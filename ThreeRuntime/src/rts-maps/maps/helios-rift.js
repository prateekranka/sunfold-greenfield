// Helios Rift — "The Broken Ring"
// Shattered orbital civilization around a dying star.
// Gameplay: expansion + chokepoint control via repairable bridges.

import { registerMap } from "../map-definition.js";

const RING_R = 34;
const FRAG_R = 11;

/** @type {import('../map-definition.js').PlatformSpec[]} */
const platforms = [
  { id: "frag-n", center: { x: 0, z: -RING_R }, radius: FRAG_R, arc: Math.PI * 0.62, yaw: 0 },
  { id: "frag-e", center: { x: RING_R, z: 0 }, radius: FRAG_R, arc: Math.PI * 0.62, yaw: Math.PI / 2 },
  { id: "frag-s", center: { x: 0, z: RING_R }, radius: FRAG_R, arc: Math.PI * 0.62, yaw: Math.PI },
  { id: "frag-w", center: { x: -RING_R, z: 0 }, radius: FRAG_R, arc: Math.PI * 0.62, yaw: -Math.PI / 2 },
  { id: "core-platform", center: { x: 0, z: 0 }, radius: 9, arc: Math.PI * 2 },
  // Expansion islets
  { id: "isle-ne", center: { x: 22, z: -22 }, radius: 5.5, arc: Math.PI * 2 },
  { id: "isle-se", center: { x: 22, z: 22 }, radius: 5.5, arc: Math.PI * 2 },
  { id: "isle-sw", center: { x: -22, z: 22 }, radius: 5.5, arc: Math.PI * 2 },
  { id: "isle-nw", center: { x: -22, z: -22 }, radius: 5.5, arc: Math.PI * 2 }
];

function bridgeEnds(fromId, toId) {
  const from = platforms.find((p) => p.id === fromId);
  const to = platforms.find((p) => p.id === toId);
  if (!from || !to) throw new Error(`bridge platform missing: ${fromId} ${toId}`);
  const dx = to.center.x - from.center.x;
  const dz = to.center.z - from.center.z;
  const len = Math.hypot(dx, dz);
  const ux = dx / len;
  const uz = dz / len;
  return {
    from: { x: from.center.x + ux * (from.radius * 0.55), z: from.center.z + uz * (from.radius * 0.55) },
    to: { x: to.center.x - ux * (to.radius * 0.55), z: to.center.z - uz * (to.radius * 0.55) }
  };
}

const bNE = bridgeEnds("frag-n", "frag-e");
const bES = bridgeEnds("frag-e", "frag-s");
const bSW = bridgeEnds("frag-s", "frag-w");
const bWN = bridgeEnds("frag-w", "frag-n");
const bNCore = bridgeEnds("frag-n", "core-platform");
const bECore = bridgeEnds("frag-e", "core-platform");
const bSCore = bridgeEnds("frag-s", "core-platform");
const bWCore = bridgeEnds("frag-w", "core-platform");

export const HELIOS_RIFT = {
  id: "helios-rift",
  name: "Helios Rift",
  theme: "The Broken Ring",
  description: "Shattered orbital ring around a dying star. Control bridges, capture the solar core.",
  playable: true,
  bounds: { halfExtent: 52, center: { x: 0, z: 0 } },
  terrain: {
    layout: "ring",
    platforms,
    debris: [
      { id: "deb-1", center: { x: 44, z: -8 }, radius: 2.2 },
      { id: "deb-2", center: { x: -38, z: 14 }, radius: 1.8 },
      { id: "deb-3", center: { x: 12, z: 46 }, radius: 2.5 },
      { id: "deb-4", center: { x: -16, z: -42 }, radius: 2.0 },
      { id: "deb-5", center: { x: 48, z: 28 }, radius: 1.6 }
    ],
    palette: { platform: 0x8a7a62, energy: 0x3ecfc0, solar: 0xffa030 }
  },
  spawns: [
    { playerId: 0, platformId: "frag-n", position: { x: 0, z: -RING_R + 2 }, yaw: Math.PI / 2, startingCitizens: 8 },
    { playerId: 1, platformId: "frag-e", position: { x: RING_R - 2, z: 0 }, yaw: Math.PI, startingCitizens: 6 },
    { playerId: 2, platformId: "frag-s", position: { x: 0, z: RING_R - 2 }, yaw: -Math.PI / 2, startingCitizens: 6 },
    { playerId: 3, platformId: "frag-w", position: { x: -RING_R + 2, z: 0 }, yaw: 0, startingCitizens: 6 }
  ],
  resources: [
    { id: "home-n-matter", kind: "matter", position: { x: -4, z: -RING_R + 5 }, platformId: "frag-n", amount: 700 },
    { id: "home-e-lumen", kind: "lumen", position: { x: RING_R - 5, z: 4 }, platformId: "frag-e", amount: 550 },
    { id: "home-s-matter", kind: "matter", position: { x: 4, z: RING_R - 5 }, platformId: "frag-s", amount: 700 },
    { id: "home-w-lumen", kind: "lumen", position: { x: -RING_R + 5, z: -4 }, platformId: "frag-w", amount: 550 },
    { id: "exp-ne-aether", kind: "aether", position: { x: 22, z: -22 }, platformId: "isle-ne", amount: 180 },
    { id: "exp-se-energy", kind: "energy_materials", position: { x: 22, z: 22 }, platformId: "isle-se", amount: 400 },
    { id: "exp-sw-matter", kind: "matter", position: { x: -22, z: 22 }, platformId: "isle-sw", amount: 500 },
    { id: "exp-nw-lumen", kind: "lumen", position: { x: -22, z: -22 }, platformId: "isle-nw", amount: 400 },
    { id: "core-energy", kind: "energy_materials", position: { x: 5, z: 3 }, amount: 300 }
  ],
  objectives: [
    {
      id: "solar-core",
      type: "solar_core",
      position: { x: 0, z: 0 },
      captureRadius: 10,
      effects: { energyBonus: 1.25, techAcceleration: 1.15 }
    }
  ],
  bridges: [
    {
      id: "bridge-ne",
      fromPlatformId: "frag-n",
      toPlatformId: "frag-e",
      ...bNE,
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "medium" }
    },
    {
      id: "bridge-es",
      fromPlatformId: "frag-e",
      toPlatformId: "frag-s",
      ...bES,
      startsEnabled: false,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-sw",
      fromPlatformId: "frag-s",
      toPlatformId: "frag-w",
      ...bSW,
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "medium" }
    },
    {
      id: "bridge-wn",
      fromPlatformId: "frag-w",
      toPlatformId: "frag-n",
      ...bWN,
      startsEnabled: false,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-n-core",
      fromPlatformId: "frag-n",
      toPlatformId: "core-platform",
      ...bNCore,
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-e-core",
      fromPlatformId: "frag-e",
      toPlatformId: "core-platform",
      ...bECore,
      startsEnabled: false,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-s-core",
      fromPlatformId: "frag-s",
      toPlatformId: "core-platform",
      ...bSCore,
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-w-core",
      fromPlatformId: "frag-w",
      toPlatformId: "core-platform",
      ...bWCore,
      startsEnabled: false,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    }
  ],
  hazards: [
    {
      id: "flare-main",
      type: "solar_flare",
      intervalSeconds: 45,
      durationSeconds: 8,
      params: {
        dps: 10,
        coverReduction: 0.35,
        disableBridgeIds: ["bridge-n-core", "bridge-s-core"]
      }
    }
  ],
  aiHints: {
    expansionLocations: [
      { id: "exp-ne", position: { x: 22, z: -22 }, platformId: "isle-ne", reason: "aether outcrop" },
      { id: "exp-se", position: { x: 22, z: 22 }, platformId: "isle-se", reason: "energy harvest" },
      { id: "exp-sw", position: { x: -22, z: 22 }, platformId: "isle-sw", reason: "matter cluster" },
      { id: "exp-nw", position: { x: -22, z: -22 }, platformId: "isle-nw", reason: "lumen cache" }
    ],
    dangerZones: [
      { id: "solar-core", position: { x: 0, z: 0 }, severity: "high" },
      { id: "void-gap-ne", position: { x: 24, z: -24 }, severity: "medium" }
    ],
    highValueObjectives: [
      { id: "solar-core", position: { x: 0, z: 0 }, value: "energy+tech" }
    ],
    preferredAttackRoutes: [
      { id: "route-n-via-core", from: "frag-n", to: "frag-s", via: ["bridge-n-core", "bridge-s-core"] },
      { id: "route-e-flank", from: "frag-e", to: "frag-w", via: ["bridge-es", "bridge-sw", "bridge-wn"] }
    ],
    defensivePositions: [
      { id: "choke-ne", position: { x: 24, z: -24 }, platformId: "frag-n" },
      { id: "choke-core", position: { x: 0, z: 8 }, platformId: "core-platform" }
    ]
  }
};

registerMap(HELIOS_RIFT);
