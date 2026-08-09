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

// Broken Ring coordinates drive the Helios visual and optional navigation
// alignment. Logical platform and bridge IDs stay unchanged.
const RING_VISUAL = {
  style: "broken-ring",
  center: { x: 0, z: 0 },
  seed: 2749,
  innerRadius: 23.5,
  outerRadius: 45,
  fragmentSpan: 1.38,
  surfaceY: 0,
  understructureDepth: 4.2,
  platformDepth: 4.2,
  deckInset: 0.78,
  panelCount: 6,
  deckPanelGap: 0.13,
  armorBandWidth: 1.7,
  armorBlockCount: 13,
  wallJitter: 0.58,
  cracksPerFragment: 8,
  conduitCount: 4,
  starfield: { count: 520, innerRadius: 74, outerRadius: 106, height: 42 },
  palette: {
    understructure: 0x0e1218,
    basalt: 0x1a1f25,
    basaltEdge: 0x303840,
    deckShadow: 0x252b31,
    deck: 0x343b41,
    deckLight: 0x373f45,
    seam: 0x22282e,
    gold: 0xd99a3a,
    goldBright: 0xffc866,
    conduit: 0x35d8ce,
    conduitBright: 0x83fff1,
    spawn: 0x328dff,
    resource: 0x3ed9b5,
    rock: 0x1a232d,
    crystal: 0x46e5e2,
    star: 0xb7d8ff,
    void: 0x030812
  },
  fragments: [
    { id: "frag-n", centerAngle: -Math.PI / 2 },
    { id: "frag-e", centerAngle: 0 },
    { id: "frag-s", centerAngle: Math.PI / 2 },
    { id: "frag-w", centerAngle: Math.PI }
  ],
  spawnPads: [
    { id: "spawn-n", position: { x: 0, z: -32 }, radius: 2.05, color: 0x318cff },
    { id: "spawn-e", position: { x: 32, z: 0 }, radius: 2.05, color: 0x318cff },
    { id: "spawn-s", position: { x: 0, z: 32 }, radius: 2.05, color: 0x318cff },
    { id: "spawn-w", position: { x: -32, z: 0 }, radius: 2.05, color: 0x318cff }
  ],
  landmarks: [
    { id: "key-n", position: { x: 0, z: -24.5 }, radius: 1.65, color: 0xe9a749, label: "key" },
    { id: "key-e", position: { x: 24.5, z: 0 }, radius: 1.65, color: 0xe9a749, label: "key" },
    { id: "key-s", position: { x: 0, z: 24.5 }, radius: 1.65, color: 0xe9a749, label: "key" },
    { id: "key-w", position: { x: -24.5, z: 0 }, radius: 1.65, color: 0xe9a749, label: "key" }
  ],
  resourceZones: [
    { id: "zone-home-n", position: { x: -7, z: -39 }, radius: 1.5, color: 0x3ed9b5 },
    { id: "zone-home-e", position: { x: 29, z: 4 }, radius: 1.5, color: 0x3ed9b5 },
    { id: "zone-home-s", position: { x: 4, z: 29 }, radius: 1.5, color: 0x3ed9b5 },
    { id: "zone-home-w", position: { x: -29, z: -4 }, radius: 1.5, color: 0x3ed9b5 },
    { id: "zone-isle-ne", position: { x: 22, z: -22 }, radius: 2.1, color: 0x46e5e2 },
    { id: "zone-isle-se", position: { x: 22, z: 22 }, radius: 2.1, color: 0x46e5e2 },
    { id: "zone-isle-sw", position: { x: -22, z: 22 }, radius: 2.1, color: 0x46e5e2 },
    { id: "zone-isle-nw", position: { x: -22, z: -22 }, radius: 2.1, color: 0x46e5e2 }
  ],
  debrisField: { count: 110, coreRadius: 10, outerRadius: 67, ringClearance: 2.4 }
};

const visualBridge = (from, to, widthValues = {}) => ({
  from,
  to,
  surfaceY: RING_VISUAL.surfaceY,
  palette: RING_VISUAL.palette,
  ...widthValues
});
const visualRingPoint = (angle) => {
  const radius = RING_VISUAL.outerRadius - 0.9;
  return { x: Math.cos(angle) * radius, z: Math.sin(angle) * radius };
};
const visualGapBridge = (fromAngle, toAngle) =>
  visualBridge(visualRingPoint(fromAngle), visualRingPoint(toAngle), {
    width: 3.6,
    deckWidth: 2.95,
    understructureWidth: 3.6
  });
const visualCoreBridge = (from, to) =>
  visualBridge(from, to, {
    width: 2.35,
    deckWidth: 1.9,
    understructureWidth: 2.35
  });

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
    palette: { platform: 0x8a7a62, energy: 0x3ecfc0, solar: 0xffa030 },
    visual: RING_VISUAL
  },
  spawns: [
    { playerId: 0, platformId: "frag-n", position: { x: 0, z: -RING_R + 2 }, yaw: Math.PI / 2, startingCitizens: 8 },
    { playerId: 1, platformId: "frag-e", position: { x: RING_R - 2, z: 0 }, yaw: Math.PI, startingCitizens: 6 },
    { playerId: 2, platformId: "frag-s", position: { x: 0, z: RING_R - 2 }, yaw: -Math.PI / 2, startingCitizens: 6 },
    { playerId: 3, platformId: "frag-w", position: { x: -RING_R + 2, z: 0 }, yaw: 0, startingCitizens: 6 }
  ],
  resources: [
    { id: "home-n-matter", kind: "matter", position: { x: -7, z: -39 }, platformId: "frag-n", amount: 700 },
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
      visual: {
        radius: 4.8,
        coronaRadius: 6.55,
        haloSize: 21,
        glareSize: 16,
        glareOpacity: 0.88,
        limbOpacity: 0.86,
        sparkCount: 64,
        sparkInnerRadius: 6.9,
        sparkOuterRadius: 13.5,
        sparkSize: 0.5,
        height: 5.3,
        coreColor: 0xffb22b,
        coronaColor: 0xff8f24,
        haloColor: 0xffb13a,
        beamColor: 0x35d8ce,
        coreOpacity: 1,
        coronaOpacity: 0.16,
        flareCoronaOpacity: 0.27,
        haloOpacity: 0.72,
        captureZone: {
          innerRadius: 8.9,
          outerRadius: 9.35,
          color: 0xf2a64a,
          opacity: 0.08
        },
        beam: {
          radiusTop: 0.08,
          radiusBottom: 0.18,
          height: 5.4,
          color: 0x71e6dc,
          opacity: 0.1
        },
        emissive: 0xff5f0f,
        emissiveIntensity: 0.34,
        lightColor: 0xff7924,
        lightIntensity: 5.2,
        lightDistance: 52,
        lightDecay: 2
      },
      effects: { energyBonus: 1.25, techAcceleration: 1.15 }
    }
  ],
  bridges: [
    {
      id: "bridge-ne",
      fromPlatformId: "frag-n",
      toPlatformId: "frag-e",
      ...bNE,
      visual: visualGapBridge(-Math.PI / 2 + RING_VISUAL.fragmentSpan / 2, -RING_VISUAL.fragmentSpan / 2),
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "medium" }
    },
    {
      id: "bridge-es",
      fromPlatformId: "frag-e",
      toPlatformId: "frag-s",
      ...bES,
      visual: visualGapBridge(RING_VISUAL.fragmentSpan / 2, Math.PI / 2 - RING_VISUAL.fragmentSpan / 2),
      startsEnabled: false,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-sw",
      fromPlatformId: "frag-s",
      toPlatformId: "frag-w",
      ...bSW,
      visual: visualGapBridge(Math.PI / 2 + RING_VISUAL.fragmentSpan / 2, Math.PI - RING_VISUAL.fragmentSpan / 2),
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "medium" }
    },
    {
      id: "bridge-wn",
      fromPlatformId: "frag-w",
      toPlatformId: "frag-n",
      ...bWN,
      visual: visualGapBridge(Math.PI + RING_VISUAL.fragmentSpan / 2, -Math.PI / 2 - RING_VISUAL.fragmentSpan / 2),
      startsEnabled: false,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-n-core",
      fromPlatformId: "frag-n",
      toPlatformId: "core-platform",
      ...bNCore,
      visual: visualCoreBridge({ x: 0, z: -24 }, { x: 0, z: -10 }),
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-e-core",
      fromPlatformId: "frag-e",
      toPlatformId: "core-platform",
      ...bECore,
      visual: visualCoreBridge({ x: 24, z: 0 }, { x: 10, z: 0 }),
      startsEnabled: false,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-s-core",
      fromPlatformId: "frag-s",
      toPlatformId: "core-platform",
      ...bSCore,
      visual: visualCoreBridge({ x: 0, z: 24 }, { x: 0, z: 10 }),
      startsEnabled: true,
      metadata: { type: "repairable_bridge", cost: "energy_materials", importance: "high" }
    },
    {
      id: "bridge-w-core",
      fromPlatformId: "frag-w",
      toPlatformId: "core-platform",
      ...bWCore,
      visual: visualCoreBridge({ x: -24, z: 0 }, { x: -10, z: 0 }),
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
