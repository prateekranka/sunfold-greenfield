// Objective zones — capture areas with gameplay effects.

import * as THREE from "three";
import { TERRAIN_PALETTE } from "./terrain-generator.js";

/**
 * @typedef {object} ObjectiveInstance
 * @property {string} id
 * @property {string} type
 * @property {number} captureRadius
 * @property {{ x: number, z: number }} position
 * @property {number | null} controllingPlayer
 * @property {number} captureProgress
 * @property {THREE.Group} mesh
 * @property {Record<string, unknown>} effects
 */

/**
 * @param {import('./map-definition.js').ObjectiveSpec[]} specs
 * @param {THREE.Group} parent
 * @returns {ObjectiveInstance[]}
 */
export function spawnObjectives(specs, parent) {
  return specs.map((spec) => {
    const g = new THREE.Group();
    g.name = `objective-${spec.id}`;
    g.position.set(spec.position.x, 0, spec.position.z);

    if (spec.type === "solar_core") {
      const core = new THREE.Mesh(
        new THREE.SphereGeometry(2.8, 24, 16),
        new THREE.MeshBasicMaterial({
          color: TERRAIN_PALETTE.solarCore,
          transparent: true,
          opacity: 0.85
        })
      );
      core.position.y = 3.2;
      g.add(core);

      const corona = new THREE.Mesh(
        new THREE.SphereGeometry(4.2, 16, 12),
        new THREE.MeshBasicMaterial({
          color: TERRAIN_PALETTE.solar,
          transparent: true,
          opacity: 0.25,
          depthWrite: false
        })
      );
      corona.position.y = 3.2;
      corona.name = "corona";
      g.add(corona);

      const beam = new THREE.Mesh(
        new THREE.CylinderGeometry(0.15, 0.4, 6, 8),
        new THREE.MeshBasicMaterial({ color: TERRAIN_PALETTE.energy, transparent: true, opacity: 0.5 })
      );
      beam.position.y = 0.3;
      g.add(beam);
    }

    const zone = new THREE.Mesh(
      new THREE.RingGeometry(spec.captureRadius * 0.85, spec.captureRadius, 48),
      new THREE.MeshBasicMaterial({
        color: 0xffffff,
        transparent: true,
        opacity: 0.2,
        side: THREE.DoubleSide,
        depthWrite: false
      })
    );
    zone.rotation.x = -Math.PI / 2;
    zone.position.y = 0.08;
    zone.name = "capture-zone";
    g.add(zone);

    parent.add(g);

    return {
      id: spec.id,
      type: spec.type,
      captureRadius: spec.captureRadius,
      position: { ...spec.position },
      controllingPlayer: null,
      captureProgress: 0,
      mesh: g,
      effects: spec.effects ?? {}
    };
  });
}

/**
 * @param {ObjectiveInstance} obj
 * @param {number} dt
 * @param {{ playerId: number, x: number, z: number }[]} unitsNearby
 */
export function tickObjectiveCapture(obj, dt, unitsNearby) {
  const inZone = unitsNearby.filter(
    (u) => Math.hypot(u.x - obj.position.x, u.z - obj.position.z) <= obj.captureRadius
  );
  if (inZone.length === 0) {
    obj.captureProgress = Math.max(0, obj.captureProgress - dt * 0.15);
    return;
  }

  const counts = new Map();
  for (const u of inZone) counts.set(u.playerId, (counts.get(u.playerId) ?? 0) + 1);
  let dominant = null;
  let dominantN = 0;
  for (const [pid, n] of counts) {
    if (n > dominantN) {
      dominantN = n;
      dominant = pid;
    }
  }
  if (dominant === null) return;

  const rate = 0.12 + dominantN * 0.04;
  if (obj.controllingPlayer === dominant) {
    obj.captureProgress = Math.min(1, obj.captureProgress + dt * rate * 0.3);
  } else {
    obj.captureProgress += dt * rate;
    if (obj.captureProgress >= 1) {
      obj.controllingPlayer = dominant;
      obj.captureProgress = 1;
    }
  }

  const zone = obj.mesh.getObjectByName("capture-zone");
  if (zone?.material) {
    const colors = [0xffffff, 0x5ad4ff, 0xff6a6a, 0x9dff6a, 0xffd45a];
    zone.material.color.setHex(colors[(obj.controllingPlayer ?? 0) + 1] ?? 0xffffff);
    zone.material.opacity = 0.15 + obj.captureProgress * 0.35;
  }
}
