// GLB prototype library — real asset loading for the Three.js runtime.
//
// Fidelity Ladder: the gltf tier is the close-gameplay representation.
//   - prototypes are loaded once (GLTFLoader.parse on bundled data: URLs, or
//     GLTFLoader.load under a permissive CSP for dev/lab) and cached;
//   - units spawn by cloning the cached prototype (SkeletonUtils.clone) so
//     every instance gets its own skin buffers and animation state;
//   - each instance owns an AnimationMixer and ≤2 material instances
//     (entry.materialSlots) so a crowd of units never multiplies materials;
//   - the LOD helpers pick a representation tier from the unit's projected
//     screen size (entry.lods, minScreenFraction thresholds).

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { clone as cloneSkeleton } from "three/addons/utils/SkeletonUtils.js";

/** Clips that should loop when played from a logical clip name. */
const LOOPING_CLIPS = new Set([
  "idle",
  "walk",
  "gather",
  "gather_loop",
  "deposit",
  "construct_loop"
]);

// ---- pure clip resolution -------------------------------------------------

/**
 * Map a logical clip name (idle/walk/gather/…) to an animation present in a
 * GLB. Order: explicit clipMap → exact name → substring match (loop variants
 * preferred) → idle → null.
 * @param {THREE.AnimationClip[]} animations
 * @param {string} logical
 * @param {Record<string, string>} [clipMap]
 */
export function resolveClipName(animations, logical, clipMap = {}) {
  if (!Array.isArray(animations) || animations.length === 0) return null;
  const names = animations.map((clip) => clip.name);
  if (clipMap[logical] && names.includes(clipMap[logical])) return clipMap[logical];
  if (names.includes(logical)) return logical;
  const containing = names.filter((name) => name.includes(logical));
  if (containing.length === 1) return containing[0];
  if (containing.length > 1) {
    return (
      containing.find((name) => name.includes("loop")) ??
      containing.find((name) => name.includes("start")) ??
      containing[0]
    );
  }
  return names.includes("idle") ? "idle" : null;
}

// ---- material slots (one or two per unit) ---------------------------------

export const DEFAULT_SLOTS = Object.freeze([{ name: "primary", match: ".*" }]);

/**
 * Assign a material name to its slot (first match wins; unknown → primary).
 * @param {string} name
 * @param {{name: string, match: string}[]} slots
 */
export function slotForMaterialName(name, slots) {
  const list = slots && slots.length > 0 ? slots : DEFAULT_SLOTS;
  for (const slot of list) {
    if (slot.match && new RegExp(slot.match, "i").test(name ?? "")) return slot;
  }
  return list[0];
}

/**
 * Replace every mesh material on `root` with per-slot instance materials.
 * Result: at most `slots.length` material instances per unit (the milestone's
 * one-or-two-slot budget), regardless of how many materials the GLB carries.
 * Optional per-slot faction tint (entry.tint[slot][faction]) recolours the
 * base color without touching the prototype.
 * @param {THREE.Object3D} root
 * @param {{materialSlots?: {name: string, match: string}[], tint?: object, faction?: string}} opts
 * @returns {Map<string, THREE.Material>} slot → instance material
 */
export function applyMaterialSlots(root, { materialSlots, tint = {}, faction } = {}) {
  const slots = materialSlots && materialSlots.length > 0 ? materialSlots : DEFAULT_SLOTS;
  const instances = new Map();
  root.traverse((object) => {
    if (!object.isMesh) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    const assigned = materials.map((material) => {
      const slot = slotForMaterialName(material?.name, slots);
      let instance = instances.get(slot.name);
      if (!instance) {
        instance = material ? material.clone() : new THREE.MeshStandardMaterial();
        const tintColor = tint?.[slot.name]?.[faction];
        if (typeof tintColor === "number" && instance.color) {
          instance.color.setHex(tintColor);
        }
        instances.set(slot.name, instance);
      }
      return instance;
    });
    object.material = assigned.length === 1 ? assigned[0] : assigned;
  });
  return instances;
}

// ---- one skinned, animated instance ---------------------------------------

/**
 * A cloned, per-unit instance of a cached GLB prototype.
 * @property {THREE.Group} root
 * @property {THREE.AnimationMixer} mixer
 */
export class GltfInstance {
  /**
   * @param {{scene: THREE.Group, animations: THREE.AnimationClip[]}} proto cached prototype
   * @param {object|null} entry asset-registry entry (clipMap/materialSlots/tint)
   * @param {string} [faction]
   */
  constructor(proto, entry, faction) {
    this.entry = entry ?? null;
    this.root = cloneSkeleton(proto.scene);
    this.mixer = new THREE.AnimationMixer(this.root);
    this.animations = proto.animations;
    this.actions = new Map();
    this.currentAction = null;
    this.currentClip = null;
    applyMaterialSlots(this.root, {
      materialSlots: entry?.materialSlots,
      tint: entry?.tint,
      faction
    });
    this.root.userData.procedural = false;
  }

  /** @param {string} logical idle/walk/gather/… */
  playClip(logical) {
    if (logical === this.currentClip) return;
    const name = resolveClipName(this.animations, logical, this.entry?.clipMap);
    if (!name) return;
    let action = this.actions.get(name);
    if (!action) {
      const clip = THREE.AnimationClip.findByName(this.animations, name);
      if (!clip) return;
      action = this.mixer.clipAction(clip);
      action.setLoop(
        LOOPING_CLIPS.has(name) || name.includes("loop") ? THREE.LoopRepeat : THREE.LoopOnce
      );
      action.clampWhenFinished = true;
      this.actions.set(name, action);
    }
    if (this.currentAction && this.currentAction !== action) this.currentAction.stop();
    action.reset().play();
    this.currentAction = action;
    this.currentClip = logical;
  }

  /** Stop animation without losing clip state (LOD switched away). */
  pause() {
    this.currentAction?.stop();
  }

  /** @param {number} dt seconds */
  update(dt) {
    this.mixer.update(dt);
  }
}

// ---- prototype cache -------------------------------------------------------

/**
 * Loads GLB prototypes once and clones them per spawned unit.
 * Prefer `registerBuffer(path, dataUrl)` (bundled, CSP-proof) over fetch.
 */
export class GltfUnitLibrary {
  /** @param {{basePath?: string}} [opts] fetch path prefix for dev/lab */
  constructor({ basePath = "" } = {}) {
    this.basePath = basePath;
    this.loader = new GLTFLoader();
    /** @type {Map<string, {scene: THREE.Group, animations: THREE.AnimationClip[], gltf: object}>} */
    this.prototypes = new Map();
    /** @type {Map<string, ArrayBuffer>} bundled buffers by registry gltf path */
    this.buffers = new Map();
    /** @type {Map<string, Promise>} */
    this._pending = new Map();
  }

  /** @param {string} path registry gltf path (e.g. "units/citizen_villager.glb") */
  has(path) {
    return this.prototypes.has(path);
  }

  /**
   * Register a bundled data: URL for a path (esbuild dataurl loader). The
   * shipping runtime uses this exclusively — no network, CSP-safe.
   * @param {string} path
   * @param {string} dataUrl
   */
  registerBuffer(path, dataUrl) {
    const comma = dataUrl.indexOf(",");
    const binary = atob(comma >= 0 ? dataUrl.slice(comma + 1) : dataUrl);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    this.buffers.set(path, bytes.buffer);
  }

  /**
   * Preload prototypes for the given gltf paths. Failures are absorbed: the
   * path is simply absent from the cache and callers fall down the LOD chain.
   * @param {string[]} paths
   */
  async preload(paths) {
    const unique = [...new Set(paths.filter(Boolean))];
    await Promise.all(unique.map((path) => this._load(path)));
  }

  /** Resolves once every in-flight preload has settled (success or failure). */
  async ready() {
    await Promise.all([...this._pending.values()]);
  }

  _load(path) {
    if (this._pending.has(path)) return this._pending.get(path);
    const promise = new Promise((resolve, reject) => {
      const finish = (gltf) => {
        const proto = { scene: gltf.scene, animations: gltf.animations, gltf };
        this.prototypes.set(path, proto);
        resolve(proto);
      };
      if (this.buffers.has(path)) {
        this.loader.parse(this.buffers.get(path), "", finish, reject);
      } else {
        this.loader.load(`${this.basePath}${path}`, finish, undefined, reject);
      }
    }).catch((error) => {
      // Absorb: the path stays absent from the cache and callers fall down
      // the LOD chain. Rejecting here would fail the whole preload batch.
      this._pending.delete(path);
      console.warn(`gltf prototype ${path} unavailable: ${error?.message ?? error}`);
    });
    this._pending.set(path, promise);
    return promise;
  }

  /**
   * Clone a cached prototype into a fresh skinned instance.
   * @param {string} path
   * @param {object|null} entry
   * @param {string} [faction]
   * @returns {GltfInstance}
   */
  instantiate(path, entry = null, faction = "sunwoven") {
    const proto = this.prototypes.get(path);
    if (!proto) throw new Error(`prototype ${path} is not preloaded`);
    return new GltfInstance(proto, entry, faction);
  }
}

// ---- LOD by projected screen size -----------------------------------------

/**
 * Approximate fraction of the viewport height a world-space object of
 * `worldHeight` metres occupies at `position`, seen by `camera`. Works for
 * perspective and orthographic cameras; the RTS camera is a fixed-pitch
 * perspective rig, so the distance-based approximation is exact enough.
 * @param {THREE.Camera} camera
 * @param {{x: number, z: number}} position
 * @param {number} worldHeight
 */
export function projectedScreenFraction(camera, position, worldHeight) {
  if (!camera) return 1;
  if (camera.isOrthographicCamera) {
    const viewportHeight = Math.abs((camera.top ?? 1) - (camera.bottom ?? -1));
    return viewportHeight > 0 ? worldHeight / viewportHeight : 1;
  }
  const point = new THREE.Vector3(position.x, position.y ?? 0, position.z);
  const distance = camera.position.distanceTo(point);
  const fovRadians = ((camera.fov ?? 38) * Math.PI) / 180;
  const viewportHeight = 2 * distance * Math.tan(fovRadians / 2);
  return viewportHeight > 0 ? worldHeight / viewportHeight : 1;
}

/**
 * Active LOD tier for a projected fraction: the first tier whose
 * `minScreenFraction` the fraction clears. Tiers are ordered close → far.
 * @param {object} entry
 * @param {number} fraction
 */
export function lodIndexForEntry(entry, fraction) {
  const lods = entry?.lods;
  if (!Array.isArray(lods) || lods.length === 0) return 0;
  for (let i = 0; i < lods.length; i += 1) {
    if (fraction >= (lods[i].minScreenFraction ?? 0)) return i;
  }
  return lods.length - 1;
}

/**
 * LOD target with hysteresis: a switch is only accepted when the fraction has
 * crossed a tier boundary by more than `hysteresis` (12% by default), so
 * units hovering on a threshold do not thrash between representations.
 * @param {object} entry
 * @param {number} fraction
 * @param {number} active current tier index
 * @param {number} [hysteresis]
 */
export function lodTarget(entry, fraction, active = 0, hysteresis = 0.12) {
  const lods = entry?.lods;
  if (!Array.isArray(lods) || lods.length <= 1) return 0;
  const computed = lodIndexForEntry(entry, fraction);
  if (computed === active) return active;
  const boundary = lods[Math.min(active, computed)].minScreenFraction ?? 0;
  if (computed > active) {
    // Moving farther: accept only past the boundary on the far side.
    return fraction <= boundary * (1 - hysteresis) ? computed : active;
  }
  // Moving closer: accept only past the boundary on the near side.
  return fraction >= boundary * (1 + hysteresis) ? computed : active;
}
