// Resource node spawning from MapDefinition.

import * as THREE from "three";
import { TERRAIN_PALETTE } from "./terrain-generator.js";

const RESOURCE_COLORS = {
  provisions: 0xe8a33d,
  matter: 0x7a8b99,
  lumen: 0xf2d06b,
  aether: 0x9d8cff,
  energy_materials: 0x3ecfc0
};

/**
 * @typedef {object} ResourceInstance
 * @property {string} id
 * @property {string} kind
 * @property {number} amount
 * @property {THREE.Group} mesh
 * @property {{ x: number, z: number }} position
 */

/**
 * @param {import('./map-definition.js').ResourceNodeSpec[]} specs
 * @param {THREE.Group} parent
 * @returns {ResourceInstance[]}
 */
export function spawnResources(specs, parent) {
  /** @type {ResourceInstance[]} */
  const instances = [];

  for (const spec of specs) {
    const color = RESOURCE_COLORS[spec.kind] ?? 0xffffff;
    const g = new THREE.Group();
    g.name = `resource-${spec.id}`;
    g.position.set(spec.position.x, 0.35, spec.position.z);

    const core = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.55, 0),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.92 })
    );
    core.position.y = 0.5;
    g.add(core);

    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.75, 0.04, 6, 24),
      new THREE.MeshBasicMaterial({ color: TERRAIN_PALETTE.energy, transparent: true, opacity: 0.6 })
    );
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.15;
    g.add(ring);

    const glow = new THREE.Mesh(
      new THREE.CircleGeometry(1.1, 24),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.18, depthWrite: false })
    );
    glow.rotation.x = -Math.PI / 2;
    glow.position.y = 0.05;
    g.add(glow);

    g.userData.resourceId = spec.id;
    g.userData.kind = spec.kind;
    parent.add(g);

    instances.push({
      id: spec.id,
      kind: spec.kind,
      amount: spec.amount ?? 500,
      mesh: g,
      position: { ...spec.position }
    });
  }

  return instances;
}
