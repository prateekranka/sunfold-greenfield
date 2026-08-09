// Exposes strategic hints from a MapDefinition for AI / debug tooling.

/**
 * @param {import('./map-definition.js').MapDefinition} def
 * @param {{ pathGraph?: import('./path-graph.js').PathGraph, bridgeStates?: Map<string, boolean> }} [runtime]
 */
export function buildAIHints(def, runtime = {}) {
  const hints = structuredClone(def.aiHints);

  // Enrich with live bridge state for attack route viability
  if (runtime.pathGraph && hints.preferredAttackRoutes) {
    hints.preferredAttackRoutes = hints.preferredAttackRoutes.map((route) => {
      const via = route.via ?? [];
      const blocked = via.some((bridgeId) => {
        if (runtime.bridgeStates?.has(bridgeId)) {
          return !runtime.bridgeStates.get(bridgeId);
        }
        return !runtime.pathGraph.isBridgeEnabled(bridgeId);
      });
      return { ...route, blocked };
    });
  }

  return Object.freeze(hints);
}

/**
 * @param {import('./map-definition.js').MapDefinition} def
 */
export function validateAIHints(def) {
  const issues = [];
  const platformIds = new Set(def.terrain.platforms.map((p) => p.id));
  for (const loc of def.aiHints.expansionLocations ?? []) {
    if (loc.platformId && !platformIds.has(loc.platformId)) {
      issues.push(`expansion ${loc.id}: unknown platform ${loc.platformId}`);
    }
  }
  return issues;
}
