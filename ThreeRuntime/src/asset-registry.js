// Logical asset registry — unit art lookup (Fidelity Ladder).
//
// Data: assets/asset-registry.json (schema sunfold.asset-registry/1).
// The runtime maps a sim unit to a logical id via `assetIdForUnit`:
//   `${faction}.${kind}.${tier}`   (tier = state.age[faction], "foundation"|"voyager")
// and follows that id's fallback chain until a representation can actually be
// realised (authored directionalSprite first, procedural.* terminal last).
//
// This module is pure: the registry data is injected so Node tests can load it
// with readFileSync and the browser build can bundle it through esbuild's json
// loader without a fetch path (the runtime ships with connect-src 'none').

export const REGISTRY_SCHEMA = "sunfold.asset-registry/1";

/** Age tiers that appear in registry ids, oldest first. */
export const AGE_TIERS = Object.freeze(["foundation", "voyager"]);

/**
 * Validate + freeze a registry payload.
 * @param {object} data parsed asset-registry.json
 * @returns {Readonly<{schema: string, entries: Readonly<Record<string, object>>}>}
 */
export function createRegistry(data) {
  if (!data || data.schema !== REGISTRY_SCHEMA) {
    throw new TypeError(`asset registry: expected schema ${REGISTRY_SCHEMA}`);
  }
  if (!data.entries || typeof data.entries !== "object") {
    throw new TypeError("asset registry: entries object is required");
  }
  const entries = {};
  for (const [id, entry] of Object.entries(data.entries)) {
    if (!entry || entry.id !== id) {
      throw new TypeError(`asset registry: entry ${id} must carry a matching id field`);
    }
    entries[id] = Object.freeze({ ...entry });
  }
  return Object.freeze({ schema: data.schema, entries: Object.freeze(entries) });
}

/** @param {ReturnType<typeof createRegistry>} registry */
export function entryForId(registry, id) {
  return registry?.entries?.[id] ?? null;
}

/**
 * Ordered fallback chain for an id: the id's entry first, then each entry's
 * `fallback`, cycle-guarded. Terminal entries (procedural.*) have no fallback.
 * Unknown ids yield an empty chain.
 * @param {ReturnType<typeof createRegistry>} registry
 * @param {string} id
 */
export function resolveChain(registry, id) {
  const chain = [];
  const seen = new Set();
  let current = id;
  while (current && !seen.has(current)) {
    seen.add(current);
    const entry = entryForId(registry, current);
    if (!entry) break;
    chain.push(entry);
    current = entry.fallback ?? null;
  }
  return chain;
}

/**
 * Best entry to realise for an id without attempting IO:
 * - directionalSprite entries with a spriteSheet are authored art;
 * - gltf entries with a gltf source are authored art;
 * - entries without a source fall through to the next link;
 * - procedural entries are the terminal debug stand-in.
 * Returns `{ entry, source }` or null when nothing in the chain is realisable.
 * @param {ReturnType<typeof createRegistry>} registry
 * @param {string} id
 */
export function resolveEntry(registry, id) {
  for (const entry of resolveChain(registry, id)) {
    if (entry.representation === "directionalSprite") {
      if (entry.spriteSheet) return { entry, source: "authored" };
      continue;
    }
    if (entry.representation === "gltf") {
      if (entry.gltf) return { entry, source: "authored" };
      continue;
    }
    if (entry.representation === "procedural") {
      return { entry, source: "procedural" };
    }
  }
  return null;
}

/**
 * Map a sim unit to its logical registry id.
 * @param {{faction?: string, kind?: string} | null} unit
 * @param {Record<string, string>} [ages] state.age — faction → tier
 */
export function assetIdForUnit(unit, ages = {}) {
  const faction = unit?.faction ?? "sunwoven";
  const kind = unit?.kind ?? "citizen";
  const tier = ages?.[faction];
  const safeTier = AGE_TIERS.includes(tier) ? tier : AGE_TIERS[0];
  return `${faction}.${kind}.${safeTier}`;
}
