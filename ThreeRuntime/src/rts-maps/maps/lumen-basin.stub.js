// Lumen Basin — stub registry entry (not playable yet).

import { registerMap } from "../map-definition.js";

registerMap({
  id: "lumen-basin",
  name: "Lumen Basin",
  theme: "The Crystal Expanse",
  description: "Living crystal formations in a turquoise energy basin. Coming soon.",
  playable: false,
  bounds: { halfExtent: 48 },
  terrain: { layout: "basin", platforms: [] },
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
