// Blender-authored building presentation for the Foundation slice.
//
// Simulation life is the only source of damage truth. This renderer maps life
// ratios to authored visibility groups and animates the transition. It never
// changes life, combat, construction, production, or pathing.

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

export const BUILDING_DAMAGE_STATES = Object.freeze([
  "healthy",
  "damaged",
  "critical",
  "destroyed"
]);

export const BUILDING_STATE_GROUPS = Object.freeze({
  healthy: Object.freeze(["state_shared", "state_healthy_damaged", "state_healthy_only"]),
  damaged: Object.freeze(["state_shared", "state_healthy_damaged", "state_damaged_plus"]),
  critical: Object.freeze(["state_shared", "state_damaged_plus", "state_critical_plus"]),
  destroyed: Object.freeze(["state_destroyed_only"])
});

const ALL_STATE_GROUPS = Object.freeze([
  "state_shared",
  "state_healthy_damaged",
  "state_healthy_only",
  "state_damaged_plus",
  "state_critical_plus",
  "state_destroyed_only"
]);

const REVEAL_GROUP = Object.freeze({
  healthy: "state_healthy_only",
  damaged: "state_damaged_plus",
  critical: "state_critical_plus",
  destroyed: "state_destroyed_only"
});

/**
 * Convert simulation life to one authored state.
 * Boundaries are deliberate: 75% is damaged, 50% is critical, and zero is a wreck.
 * @param {number} life
 * @param {number} maxLife
 */
export function damageStateForLife(life, maxLife) {
  const safeMax = Number.isFinite(maxLife) && maxLife > 0 ? maxLife : 1;
  const safeLife = Number.isFinite(life) ? Math.max(0, Math.min(life, safeMax)) : safeMax;
  const ratio = safeLife / safeMax;
  if (ratio > 0.75) return "healthy";
  if (ratio > 0.50) return "damaged";
  if (ratio > 0) return "critical";
  return "destroyed";
}
/** @param {string} state */
export function visibleGroupNamesForState(state) {
  return BUILDING_STATE_GROUPS[state] ?? BUILDING_STATE_GROUPS.healthy;
}

function dataUrlToBuffer(dataUrl) {
  const comma = dataUrl.indexOf(",");
  const encoded = comma >= 0 ? dataUrl.slice(comma + 1) : dataUrl;
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function cloneAnimatedMaterials(root) {
  const cloned = new Map();
  const animated = [];
  root.traverse((object) => {
    if (!object.isMesh || !object.material) return;
    const source = Array.isArray(object.material) ? object.material : [object.material];
    const next = source.map((material) => {
      const name = material?.name ?? "";
      if (!/SW_(Teal_Lantern|Ember)/i.test(name)) return material;
      if (!cloned.has(material.uuid)) cloned.set(material.uuid, material.clone());
      const instance = cloned.get(material.uuid);
      if (!animated.includes(instance)) {
        animated.push(instance);
        instance.userData.baseEmissiveIntensity = instance.emissiveIntensity ?? 1;
        instance.userData.isEmber = /Ember/i.test(name);
      }
      return instance;
    });
    object.material = Array.isArray(object.material) ? next : next[0];
  });
  return { cloned: [...cloned.values()], animated };
}

/** One cloned building and its presentation-only damage transition. */
export class GltfBuildingInstance {
  constructor(prototype, { kind, life, maxLife, reducedMotion = false } = {}) {
    this.kind = kind;
    this.root = prototype.scene.clone(true);
    this.root.name = `building_${kind}`;
    this.root.userData.buildingKind = kind;
    this.reducedMotion = Boolean(reducedMotion);
    this.elapsed = 0;
    this.transition = null;
    this.state = null;
    this.groups = new Map();
    for (const name of ALL_STATE_GROUPS) {
      const group = this.root.getObjectByName(name);
      if (!group) throw new Error(`${kind} GLB is missing ${name}`);
      this.groups.set(name, group);
    }
    this.motionCoreRing = this.root.getObjectByName("motion_core_ring");
    this.motionFarmCrops = this.root.getObjectByName("motion_farm_crops");
    this.motionYardLoom = this.root.getObjectByName("motion_yard_loom");
    const materialState = cloneAnimatedMaterials(this.root);
    this.instanceMaterials = materialState.cloned;
    this.animatedMaterials = materialState.animated;
    this.setLife(life ?? maxLife ?? 1, maxLife ?? 1, { immediate: true });
  }

  setPosition(x, z, y = 0) {
    this.root.position.set(x, y, z);
  }

  setYaw(radians) {
    this.root.rotation.y = radians;
  }

  setLife(life, maxLife, { immediate = false } = {}) {
    const next = damageStateForLife(life, maxLife);
    this.life = life;
    this.maxLife = maxLife;
    if (next === this.state) return false;
    this.state = next;
    const visible = new Set(visibleGroupNamesForState(next));
    for (const [name, group] of this.groups) {
      group.visible = visible.has(name);
      group.position.y = 0;
      group.scale.setScalar(1);
    }
    const reveal = this.groups.get(REVEAL_GROUP[next]);
    if (reveal && !immediate && !this.reducedMotion) {
      reveal.position.y = next === "destroyed" ? 0.9 : 0.22;
      reveal.scale.setScalar(next === "destroyed" ? 0.88 : 0.94);
      this.transition = { group: reveal, elapsed: 0, duration: next === "destroyed" ? 0.72 : 0.38 };
    } else {
      this.transition = null;
    }
    this.root.userData.damageState = next;
    return true;
  }

  update(deltaTime) {
    const dt = Math.max(0, Math.min(Number(deltaTime) || 0, 0.1));
    this.elapsed += dt;
    if (!this.reducedMotion) {
      if (this.motionCoreRing) this.motionCoreRing.rotation.y += dt * 0.16;
      if (this.motionYardLoom) this.motionYardLoom.rotation.y -= dt * 0.22;
      if (this.motionFarmCrops) {
        this.motionFarmCrops.rotation.z = Math.sin(this.elapsed * 1.35) * 0.016;
        this.motionFarmCrops.rotation.x = Math.sin(this.elapsed * 0.93 + 0.8) * 0.009;
      }
    }
    if (this.transition) {
      this.transition.elapsed += dt;
      const linear = Math.min(1, this.transition.elapsed / this.transition.duration);
      const eased = 1 - Math.pow(1 - linear, 3);
      this.transition.group.position.y *= 1 - eased;
      this.transition.group.scale.setScalar(0.94 + eased * 0.06);
      if (linear >= 1) {
        this.transition.group.position.y = 0;
        this.transition.group.scale.setScalar(1);
        this.transition = null;
      }
    }
    const activeFire = this.state === "critical" || this.state === "destroyed";
    for (const material of this.animatedMaterials) {
      const base = material.userData.baseEmissiveIntensity ?? 1;
      if (material.userData.isEmber) {
        material.emissiveIntensity = activeFire
          ? base * (0.82 + Math.sin(this.elapsed * 7.2) * 0.18)
          : 0;
      } else {
        material.emissiveIntensity = this.state === "destroyed"
          ? base * 0.25
          : base * (0.94 + Math.sin(this.elapsed * 1.8) * 0.06);
      }
    }
  }

  dispose() {
    for (const material of this.instanceMaterials) material.dispose();
    this.instanceMaterials.length = 0;
    this.animatedMaterials.length = 0;
  }
}

/** Loads each Blender GLB once and clones it for every visual instance. */
export class GltfBuildingLibrary {
  constructor() {
    this.loader = new GLTFLoader();
    this.buffers = new Map();
    this.prototypes = new Map();
    this.pending = new Map();
  }

  registerBuffer(kind, dataUrl) {
    this.buffers.set(kind, dataUrlToBuffer(dataUrl));
  }

  async preload(kinds = [...this.buffers.keys()]) {
    await Promise.all(kinds.map((kind) => this.#load(kind)));
  }

  async ready() {
    await Promise.all([...this.pending.values()]);
  }

  #load(kind) {
    if (this.prototypes.has(kind)) return Promise.resolve(this.prototypes.get(kind));
    if (this.pending.has(kind)) return this.pending.get(kind);
    const buffer = this.buffers.get(kind);
    if (!buffer) return Promise.reject(new Error(`no GLB buffer registered for ${kind}`));
    const pending = new Promise((resolve, reject) => {
      this.loader.parse(
        buffer,
        "",
        (gltf) => {
          const prototype = { scene: gltf.scene, animations: gltf.animations ?? [] };
          this.prototypes.set(kind, prototype);
          resolve(prototype);
        },
        reject
      );
    });
    this.pending.set(kind, pending);
    return pending.finally(() => this.pending.delete(kind));
  }

  instantiate(kind, options = {}) {
    const prototype = this.prototypes.get(kind);
    if (!prototype) throw new Error(`${kind} building prototype is not preloaded`);
    return new GltfBuildingInstance(prototype, { ...options, kind });
  }
}
