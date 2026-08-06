// Presentation layer: project sim units onto registry-resolved views.
//
// Each unit gets a UnitView: a container group holding one object per LOD
// tier from its registry entry (gltf prototype clone → directionalSprite
// billboard → procedural stand-in). The active tier is chosen by the unit's
// projected screen size (see gltf-units.js lodTarget) and only the active
// tier is visible / animated. Authored sources that cannot load fall down
// the tier list; the procedural tier is the visible debug floor.
//
// WebGL visuals stay out of the determinism path — the sim stays authoritative;
// this module only mirrors positions / facing / activity into views.

import * as THREE from "three";
import { SpriteUnit } from "./sprite-unit.js";
import { GoldenSpriteUnit, isGoldenManifest } from "./golden-unit.js";
import { resolveChain } from "../asset-registry.js";
import { projectedScreenFraction, lodTarget } from "../gltf-units.js";

/** Map sim activity → logical clip names. */
export function clipForUnit(unit) {
  if (!unit) return "idle";
  const tag = unit.activity?.tag;
  // Carrying wins over movement: the carrier clip already encodes the walk.
  if (tag === "carrying" || unit.carrying) return "carry";
  const moving =
    (unit.movementPath && unit.movementPath.length > 0) ||
    (unit.destination &&
      (Math.abs(unit.destination.x - unit.position.x) > 0.05 ||
        Math.abs(unit.destination.z - unit.position.z) > 0.05));
  if (moving) return "walk";
  if (tag === "gathering") return "gather";
  if (tag === "constructing") return "build";
  return "idle";
}

const FACTION_RING_COLORS = Object.freeze({
  sunwoven: 0xe2b866,
  gravemark: 0xb87333
});

/** One manifest fetch per sheet — spawn bursts resolve from this cache. */
const manifestFetchCache = new Map();

/** Faint ownership ring under units whose entry carries factionMask. */
function factionRing(faction, radius) {
  const ring = new THREE.Mesh(
    new THREE.CircleGeometry(radius, 28),
    new THREE.MeshBasicMaterial({
      color: FACTION_RING_COLORS[faction] ?? 0x9a9aa0,
      transparent: true,
      opacity: 0.22,
      depthWrite: false
    })
  );
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.015;
  ring.name = "faction-ring";
  return ring;
}

/** AoE2-style selection ring for `unit.selected`. */
const selectionRingMaterial = new THREE.MeshBasicMaterial({
  color: 0x7dff7d,
  transparent: true,
  opacity: 0.55,
  depthWrite: false
});

function selectionRing(radius) {
  const ring = new THREE.Mesh(
    new THREE.RingGeometry(radius * 0.72, radius, 40),
    selectionRingMaterial
  );
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.02;
  ring.name = "selection-ring";
  return ring;
}

let _blobShadowTexture = null;
let _blobShadowMaterial = null;

/** Lazy: canvas creation needs a DOM, which Node tests do not have. */
function getBlobShadowMaterial() {
  if (_blobShadowMaterial) return _blobShadowMaterial;
  if (typeof document === "undefined") return null;
  const canvas = document.createElement("canvas");
  canvas.width = 64;
  canvas.height = 64;
  const ctx = canvas.getContext("2d");
  const gradient = ctx.createRadialGradient(32, 32, 4, 32, 32, 30);
  gradient.addColorStop(0, "rgba(0, 0, 0, 0.55)");
  gradient.addColorStop(0.7, "rgba(0, 0, 0, 0.28)");
  gradient.addColorStop(1, "rgba(0, 0, 0, 0)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 64, 64);
  _blobShadowTexture = new THREE.CanvasTexture(canvas);
  _blobShadowTexture.colorSpace = THREE.NoColorSpace;
  _blobShadowMaterial = new THREE.MeshBasicMaterial({
    map: _blobShadowTexture,
    transparent: true,
    depthWrite: false
  });
  return _blobShadowMaterial;
}

function blobShadow(radius) {
  const material = getBlobShadowMaterial();
  if (!material) return null;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(radius * 2, radius * 2), material);
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = 0.01;
  mesh.name = "blob-shadow";
  return mesh;
}

/**
 * One unit's visual presence: a container in the scene plus one object per
 * LOD tier. Only the active tier is visible and animated.
 */
class UnitView {
  /**
   * @param {object|null} entry registry entry (null for forced procedural)
   * @param {string|null} id logical asset id
   * @param {THREE.Group} container
   * @param {{kind: string, object: object}[]} tiers close → far
   * @param {number[]} [tierLodIndices] ladder index of each tier (holes where
   *   a source was unavailable, e.g. [0, 2] when the sprite tier failed)
   */
  constructor(entry, id, container, tiers, tierLodIndices = null) {
    this.entry = entry;
    this.id = id;
    this.container = container;
    this.tiers = tiers;
    this.tierLodIndices = tierLodIndices ?? tiers.map((_, i) => i);
    this.activeTier = 0;
    this.lastLogicalClip = "idle";
    this.userData = {};
    for (const tier of tiers) {
      const group = this._tierGroup(tier);
      group.visible = false;
      this.container.add(group);
    }
    if (tiers.length > 0) this._setTierVisible(0, true);
  }

  /** The scene object of a tier (gltf instances carry it on `.root`). */
  _tierGroup(tier) {
    return tier.kind === "gltf" ? tier.object.root : tier.object.group ?? tier.object;
  }

  _tierObject(index) {
    const tier = this.tiers[index];
    return tier ? tier.object : null;
  }

  _setTierVisible(index, visible) {
    const tier = this.tiers[index];
    if (!tier) return;
    const group = this._tierGroup(tier);
    group.visible = visible;
    if (tier.kind === "gltf") {
      if (visible) tier.object.playClip(this.lastLogicalClip);
      else tier.object.pause();
    }
  }

  /**
   * Map a ladder index to the nearest available tier; ties prefer the farther
   * tier (a missing mid tier falls toward the cheaper representation).
   */
  _nearestAvailableTier(ladderIndex) {
    let best = 0;
    let bestDistance = Infinity;
    let bestLod = -1;
    for (let i = 0; i < this.tiers.length; i += 1) {
      const lod = this.tierLodIndices[i] ?? 0;
      const distance = Math.abs(lod - ladderIndex);
      if (distance < bestDistance || (distance === bestDistance && lod > bestLod)) {
        best = i;
        bestDistance = distance;
        bestLod = lod;
      }
    }
    return best;
  }

  setTransform(unit) {
    this.container.position.set(unit.position.x, 0, unit.position.z);
    const tier = this.tiers[this.activeTier];
    if (!tier) return;
    const yaw = typeof unit.facing === "number" ? unit.facing : 0;
    if (tier.kind === "gltf") tier.object.root.rotation.y = yaw;
    else if (tier.kind === "sprite" && tier.object.setYaw) tier.object.setYaw(yaw);
  }

  /** Drive the active tier's clip from sim activity. */
  syncClip(unit) {
    const logical = clipForUnit(unit);
    this.lastLogicalClip = logical;
    const tier = this.tiers[this.activeTier];
    if (!tier) return;
    if (tier.kind === "gltf") {
      tier.object.playClip(logical);
      return;
    }
    if (tier.kind !== "sprite") return;
    const view = tier.object;
    // Prefer clips the loaded sheet actually has (e.g. space-villager has no
    // build); otherwise fall back to idle rather than a missing frame.
    const resolved = view.manifest?.clips?.[logical]
      ? logical
      : view.manifest?.clips?.idle
        ? "idle"
        : logical;
    if (view.clip !== resolved) {
      view.setClip(resolved).catch((error) => {
        console.error(error);
        if (typeof window !== "undefined") {
          window.dispatchEvent(
            new CustomEvent("sunfold:spriteError", {
              detail: { message: error?.message || String(error) }
            })
          );
        }
      });
    }
  }

  /** Advance animation of the active tier (dt = 0 while paused). */
  update(dt) {
    const tier = this.tiers[this.activeTier];
    if (!tier) return;
    if (tier.kind === "gltf") tier.object.update(dt);
    else if (tier.kind === "sprite") tier.object.update(dt);
  }

  /** Switch LOD tier by projected screen size (with hysteresis). */
  maybeSwitchLod(camera, unit) {
    const entry = this.entry;
    if (!entry?.lods?.length || !camera) return;
    const fraction = projectedScreenFraction(camera, unit.position, entry.scaleMeters ?? 1.8);
    const activeLod = this.tierLodIndices[this.activeTier] ?? 0;
    const targetLod = lodTarget(entry, fraction, activeLod);
    if (targetLod === activeLod) return;
    const targetTier = this._nearestAvailableTier(targetLod);
    if (targetTier === this.activeTier || !this.tiers[targetTier]) return;
    this._setTierVisible(this.activeTier, false);
    this.activeTier = targetTier;
    this._setTierVisible(targetTier, true);
    this.setTransform(unit);
    this.syncClip(unit);
  }

  dispose() {
    for (const tier of this.tiers) {
      const group = this._tierGroup(tier);
      this.container.remove(group);
    }
  }
}

/**
 * @param {object} opts
 * @param {THREE.Scene} opts.scene
 * @param {object|null} [opts.registry] createRegistry() result
 * @param {(unit: object, ages: object) => string} [opts.assetId] logical id fn
 * @param {Record<string, {manifest: object, basePath?: string} | object>} [opts.manifests]
 *   preloaded manifests keyed by registry id (preferred under CSP; the value is
 *   either {manifest, basePath} or the manifest object itself)
 * @param {import("../gltf-units.js").GltfUnitLibrary} [opts.gltfLibrary] cached GLB prototypes
 * @param {THREE.Camera} [opts.camera] for LOD switching by projected size
 * @param {({kind: string, faction: string, height: number}) => THREE.Group} [opts.proceduralFactory]
 * @param {boolean} [opts.forceProcedural] debug: render every unit procedurally
 * @param {"sprite"|"procedural"|null} [opts.forceArt] debug: pin one representation
 * @param {boolean} [opts.blobShadows] soft blob shadow under every unit
 * @param {string} [opts.spriteRoot] prefix before `sprites/<sheet>/` for the
 *   manifest/texture fetch path (dev labs serve assets under /assets/citizens/)
 */
export class UnitPresentationLayer {
  constructor({
    scene,
    registry = null,
    assetId = null,
    manifests = {},
    gltfLibrary = null,
    camera = null,
    proceduralFactory = null,
    forceProcedural = false,
    forceArt = null,
    blobShadows = false,
    spriteRoot = ""
  }) {
    this.scene = scene;
    this.registry = registry;
    this.assetId = assetId ?? ((unit) => `${unit?.faction ?? "sunwoven"}.${unit?.kind ?? "citizen"}.foundation`);
    this.manifests = manifests;
    this.gltfLibrary = gltfLibrary;
    this.camera = camera;
    this.proceduralFactory = proceduralFactory;
    this.forceProcedural = Boolean(forceProcedural);
    this.forceArt = forceArt ?? (forceProcedural ? "procedural" : null);
    this.blobShadows = Boolean(blobShadows);
    this.spriteRoot = spriteRoot;
    /** @type {Map<number, UnitView>} */
    this.views = new Map();
    this.ready = false;
    this._initPromise = null;
  }

  async init() {
    if (this._initPromise) return this._initPromise;
    this._initPromise = Promise.resolve().then(() => {
      this.ready = true;
    });
    return this._initPromise;
  }

  /**
   * Realise a view for a sim unit: walk the registry fallback chain, build
   * the entry's LOD tiers, and fall to the procedural stand-in if nothing
   * loads. Never throws.
   */
  async _createView(unit, ages) {
    if (this.forceProcedural) {
      return this._proceduralView(unit, null);
    }
    const id = this.assetId(unit, ages);
    for (const entry of resolveChain(this.registry, id)) {
      const { tiers, ladder } = await this._buildTiers(entry, unit);
      if (tiers.length === 0) continue;
      const view = new UnitView(entry, id, new THREE.Group(), tiers, ladder);
      view.userData.entryId = entry.id;
      view.userData.procedural = tiers[0].kind === "procedural";
      return view;
    }
    return this._proceduralView(unit, null);
  }

  /** Build all available LOD tiers for an entry (missing sources are skipped). */
  async _buildTiers(entry, unit) {
    let lods = entry.lods;
    if (this.forceArt === "sprite") {
      lods = (lods ?? []).filter((lod) => lod.kind === "sprite");
    }
    if (!Array.isArray(lods) || lods.length === 0) {
      const tier = await this._buildSingleTier(entry, unit);
      return tier ? { tiers: [tier], ladder: [0] } : { tiers: [], ladder: [] };
    }
    const tiers = [];
    const ladder = [];
    for (let i = 0; i < lods.length; i += 1) {
      const lod = lods[i];
      if (lod.kind === "gltf") {
        try {
          if (this.gltfLibrary?.has(lod.gltf)) {
            tiers.push({ kind: "gltf", object: this.gltfLibrary.instantiate(lod.gltf, entry, unit.faction) });
            ladder.push(i);
          } else {
            this._notifyFallback(entry.id, new Error(`prototype ${lod.gltf} unavailable`));
          }
        } catch (error) {
          this._notifyFallback(entry.id, error);
        }
        continue;
      }
      if (lod.kind === "sprite") {
        const sprite = await this._buildSpriteTier(entry);
        if (sprite) {
          tiers.push({ kind: "sprite", object: sprite });
          ladder.push(i);
        }
        continue;
      }
      if (lod.kind === "procedural") {
        const group = this._buildProceduralTier(entry, unit);
        if (group) {
          tiers.push({ kind: "procedural", object: group });
          ladder.push(i);
        }
      }
    }
    return { tiers, ladder };
  }

  /** Entries without lods keep the original single-representation behaviour. */
  async _buildSingleTier(entry, unit) {
    if (entry.representation === "procedural") {
      const group = this._buildProceduralTier(entry, unit);
      return group ? { kind: "procedural", object: group } : null;
    }
    if (entry.representation === "directionalSprite") {
      const sprite = await this._buildSpriteTier(entry);
      return sprite ? { kind: "sprite", object: sprite } : null;
    }
    return null;
  }

  /** @returns {Promise<SpriteUnit | GoldenSpriteUnit | null>} */
  async _buildSpriteTier(entry) {
    const override = this.manifests[entry.id];
    const sheet = entry.spriteSheet;
    if (!override && !sheet) return null;
    const basePath = override
      ? override.basePath ?? ""
      : `${this.spriteRoot}sprites/${sheet}/`;
    const bundled = override ? override.manifest ?? override : null;
    try {
      let view;
      if (bundled) {
        view = isGoldenManifest(bundled)
          ? new GoldenSpriteUnit(bundled, { basePath })
          : new SpriteUnit(bundled, { basePath });
        await view.applyManifest(bundled);
      } else {
        // Fetch the manifest once per sheet; every unit reuses the cache so a
        // spawn burst resolves in microtasks instead of network round-trips.
        let fetched = manifestFetchCache.get(basePath);
        if (!fetched) {
          const res = await fetch(`${basePath}atlas-manifest.json`);
          if (!res.ok) {
            throw new Error(`sprite manifest ${basePath}atlas-manifest.json → HTTP ${res.status}`);
          }
          fetched = await res.json();
          manifestFetchCache.set(basePath, fetched);
        }
        view = isGoldenManifest(fetched)
          ? new GoldenSpriteUnit(fetched, { basePath })
          : new SpriteUnit(fetched, { basePath });
        await view.applyManifest(fetched);
      }
      view._entry = entry;
      view.group.userData.entryId = entry.id;
      return view;
    } catch (error) {
      this._notifyFallback(entry.id, error);
      return null;
    }
  }

  /** @returns {THREE.Group | null} */
  _buildProceduralTier(entry, unit) {
    if (!this.proceduralFactory) return null;
    const group = this.proceduralFactory({
      kind: unit.kind,
      faction: unit.faction,
      height: entry?.scaleMeters ?? 1.8
    });
    group._entry = entry;
    group.userData.entryId = entry?.id ?? `procedural.${unit.kind}`;
    group.userData.procedural = true;
    return group;
  }

  /** @param {object} unit @param {object|null} entry */
  _proceduralView(unit, entry) {
    const group = this._buildProceduralTier(entry, unit);
    if (!group) return null;
    const view = new UnitView(entry, null, new THREE.Group(), [{ kind: "procedural", object: group }], [0]);
    view.userData.entryId = entry?.id ?? `procedural.${unit.kind}`;
    view.userData.procedural = true;
    return view;
  }

  /** @param {string} id @param {unknown} error */
  _notifyFallback(id, error) {
    if (typeof window === "undefined") return;
    window.dispatchEvent(
      new CustomEvent("sunfold:proceduralFallback", {
        detail: { id, message: error instanceof Error ? error.message : String(error) }
      })
    );
  }

  /**
   * Sync visual views to the live sim state (every unit kind — the registry
   * decides the representation).
   * @param {{ units: { ordered: () => object[] }, age?: object } | null} state
   * @param {number} dt
   */
  sync(state, dt) {
    if (!this.ready || !state) return;
    const ages = state.age ?? {};
    const live = new Set();
    for (const unit of state.units.ordered()) {
      live.add(unit.id);
      let view = this.views.get(unit.id);
      if (!view) {
        this._createView(unit, ages)
          .then((created) => {
            if (!created || this.views.has(unit.id)) return;
            this.views.set(unit.id, created);
            this.scene.add(created.container);
            created.setTransform(unit);
            created.syncClip(unit);
          })
          .catch((error) => console.error("unit view failed", error));
        continue;
      }
      view.setTransform(unit);
      view.syncClip(unit);
      view.maybeSwitchLod(this.camera, unit);
      view.update(dt);
      this._syncFactionRing(view, unit);
      this._syncSelectionRing(view, unit);
      this._syncBlobShadow(view, unit);
    }
    for (const [id, view] of this.views) {
      if (live.has(id)) continue;
      view.dispose();
      this.scene.remove(view.container);
      this.views.delete(id);
    }
  }

  /** Add/remove the faction ownership ring per the entry's factionMask. */
  _syncFactionRing(view, unit) {
    const entry = view.entry;
    const wants = Boolean(entry?.factionMask) && Boolean(unit.faction);
    let ring = view.container.getObjectByName("faction-ring");
    if (wants && !ring) {
      const radius = Math.max(0.5, (entry.scaleMeters ?? 1.8) * 0.35);
      ring = factionRing(unit.faction, radius);
      view.container.add(ring);
    } else if (!wants && ring) {
      view.container.remove(ring);
      ring.geometry.dispose();
      ring.material.dispose();
    }
  }

  /** AoE2-style selection ring for units flagged `selected`. */
  _syncSelectionRing(view, unit) {
    const wants = Boolean(unit.selected);
    let ring = view.container.getObjectByName("selection-ring");
    if (wants && !ring) {
      const radius = Math.max(0.9, (view.entry?.scaleMeters ?? 1.8) * 0.62);
      ring = selectionRing(radius);
      view.container.add(ring);
    } else if (!wants && ring) {
      view.container.remove(ring);
      ring.geometry.dispose();
    }
  }

  /** Soft blob shadow under every unit when enabled (AoE2-style). */
  _syncBlobShadow(view, unit) {
    const wants = this.blobShadows;
    let shadow = view.container.getObjectByName("blob-shadow");
    if (wants && !shadow) {
      const radius = Math.max(0.6, (view.entry?.scaleMeters ?? 1.8) * 0.48);
      shadow = blobShadow(radius);
      if (shadow) view.container.add(shadow);
    } else if (!wants && shadow) {
      view.container.remove(shadow);
      shadow.geometry.dispose();
    }
  }

  dispose() {
    for (const view of this.views.values()) {
      view.dispose();
      this.scene.remove(view.container);
    }
    this.views.clear();
  }
}

/** Legacy name — the layer now presents every unit kind through the registry. */
export const CitizenSpriteLayer = UnitPresentationLayer;
