// Orekhar Frontier — stub registry entry (not playable yet).

import { registerMap } from "../map-definition.js";

registerMap({
  id: "orekhar-frontier",
  name: "Orekhar Frontier",
  theme: "The Asteroid Belt",
  description: "Fragmented asteroid platforms with rotating hazards. Coming soon.",
  playable: false,
  bounds: { halfExtent: 50 },
  terrain: { layout: "asteroid-belt", platforms: [] },
  spawns: [],
  resources: [],
  objectives: [],
  bridges: [],
  hazards: [],
  aiHints: {
    expansionLocations: [],
    dangerZones: [],
    highValueObjectives: [],
    preferredAttackRoutes: [],
    defensivePositions: []
  }
});
