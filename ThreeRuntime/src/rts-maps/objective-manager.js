// Objective zones — capture areas with gameplay effects.

import * as THREE from "three";
import { TERRAIN_PALETTE } from "./terrain-generator.js";

let solarHaloTexture = null;

function getSolarHaloTexture() {
  if (solarHaloTexture) return solarHaloTexture;
  const canvas = document.createElement("canvas");
  canvas.width = 128;
  canvas.height = 128;
  const context = canvas.getContext("2d");
  const gradient = context.createRadialGradient(64, 64, 2, 64, 64, 62);
  gradient.addColorStop(0, "rgba(255,248,198,1)");
  gradient.addColorStop(0.16, "rgba(255,181,54,0.95)");
  gradient.addColorStop(0.46, "rgba(255,100,20,0.42)");
  gradient.addColorStop(1, "rgba(255,68,8,0)");
  context.fillStyle = gradient;
  context.fillRect(0, 0, 128, 128);
  solarHaloTexture = new THREE.CanvasTexture(canvas);
  solarHaloTexture.colorSpace = THREE.SRGBColorSpace;
  return solarHaloTexture;
}

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
    const visual = spec.visual ?? {};
    const captureZone = visual.captureZone ?? {};
    const captureZoneRadius =
      visual.captureZoneRadius ?? visual.captureRadius ?? captureZone.outerRadius ?? captureZone.radius ?? spec.captureRadius;
    const captureZoneInnerRadius =
      visual.captureZoneInnerRadius ?? captureZone.innerRadius ?? captureZoneRadius * 0.85;
    const captureZoneColor =
      visual.captureZoneColor ?? visual.captureColor ?? captureZone.color ?? 0xffffff;
    const captureZoneOpacity =
      visual.captureZoneOpacity ?? visual.captureOpacity ?? captureZone.opacity ?? 0.2;

    if (spec.type === "solar_core") {
      const light = visual.light ?? {};
      const coreRadius = visual.radius ?? 2.8;
      const coronaRadius = visual.coronaRadius ?? 4.2;
      const coreColor = visual.coreColor ?? visual.color ?? TERRAIN_PALETTE.solarCore;
      const coronaColor = visual.coronaColor ?? TERRAIN_PALETTE.solar;
      const beamColor = visual.beamColor ?? TERRAIN_PALETTE.energy;
      const coreOpacity = visual.coreOpacity ?? 0.85;
      const coronaOpacity = visual.coronaOpacity ?? 0.25;
      const coreHeight = visual.height ?? 3.2;
      const beamSpec = visual.beam ?? {};
      const beamHeight = visual.beamHeight ?? beamSpec.height ?? 6;
      const beamOpacity = visual.beamOpacity ?? beamSpec.opacity ?? 0.5;
      const beamTopRadius = visual.beamRadiusTop ?? beamSpec.radiusTop ?? 0.15;
      const beamBottomRadius = visual.beamRadiusBottom ?? beamSpec.radiusBottom ?? 0.4;
      const hasEmissive = visual.emissive !== undefined || visual.emissiveIntensity !== undefined;
      const coreMaterial = hasEmissive
        ? new THREE.MeshStandardMaterial({
            color: coreColor,
            emissive: visual.emissive ?? coreColor,
            emissiveIntensity: visual.emissiveIntensity ?? 1,
            transparent: true,
            opacity: coreOpacity
          })
        : new THREE.MeshBasicMaterial({
            color: coreColor,
            transparent: true,
            opacity: coreOpacity
          });
      const core = new THREE.Mesh(
        new THREE.SphereGeometry(coreRadius, 40, 28),
        coreMaterial
      );
      core.position.y = coreHeight;
      core.name = "solar-core-sphere";
      g.add(core);

      const corona = new THREE.Mesh(
        new THREE.SphereGeometry(coronaRadius, 16, 12),
        new THREE.MeshBasicMaterial({
          color: coronaColor,
          transparent: true,
          opacity: coronaOpacity,
          depthWrite: false,
          blending: THREE.AdditiveBlending
        })
      );
      corona.position.y = coreHeight;
      corona.name = "corona";
      g.add(corona);

      const halo = new THREE.Sprite(
        new THREE.SpriteMaterial({
          map: getSolarHaloTexture(),
          color: coronaColor,
          transparent: true,
          opacity: visual.haloOpacity ?? 0.62,
          blending: THREE.AdditiveBlending,
          depthWrite: false
        })
      );
      const haloSize = visual.haloSize ?? coronaRadius * 3;
      halo.position.y = coreHeight;
      halo.scale.set(haloSize, haloSize, 1);
      halo.name = "solar-halo";
      g.add(halo);

      const beam = new THREE.Mesh(
        new THREE.CylinderGeometry(beamTopRadius, beamBottomRadius, beamHeight, 8),
        new THREE.MeshBasicMaterial({
          color: beamSpec.color ?? beamColor,
          transparent: true,
          opacity: beamOpacity,
          depthWrite: false
        })
      );
      beam.position.y = coreHeight - beamHeight * 0.5;
      g.add(beam);

      const lightColor = visual.lightColor ?? light.color;
      const lightIntensity = visual.lightIntensity ?? light.intensity;
      if (lightColor !== undefined || lightIntensity !== undefined) {
        const pointLight = new THREE.PointLight(
          lightColor ?? coronaColor,
          Math.min(lightIntensity ?? 1, 8),
          Math.min(visual.lightDistance ?? light.distance ?? 20, 64),
          Math.min(visual.lightDecay ?? light.decay ?? 2, 2)
        );
        pointLight.position.y = coreHeight;
        pointLight.name = "solar-light";
        g.add(pointLight);
      }
    }

    const zone = new THREE.Mesh(
      new THREE.RingGeometry(captureZoneInnerRadius, captureZoneRadius, 48),
      new THREE.MeshBasicMaterial({
        color: captureZoneColor,
        transparent: true,
        opacity: captureZoneOpacity,
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
