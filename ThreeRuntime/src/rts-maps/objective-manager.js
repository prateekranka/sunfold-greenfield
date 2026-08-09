// Objective zones — capture areas with gameplay effects.

import * as THREE from "three";
import { TERRAIN_PALETTE } from "./terrain-generator.js";

let solarHaloTexture = null;
let solarGlareTexture = null;
let solarSparkTexture = null;
let solarSurfaceTexture = null;

function deterministicUnit(index, salt = 0) {
  const value = Math.sin((index + 1) * 12.9898 + (salt + 1) * 78.233) * 43758.5453;
  return value - Math.floor(value);
}

function getSolarSurfaceTexture() {
  if (solarSurfaceTexture) return solarSurfaceTexture;
  const canvas = document.createElement("canvas");
  const width = 384;
  const height = 192;
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  const image = context.createImageData(width, height);
  const cells = [];
  const cellCount = 92;
  for (let index = 0; index < cellCount; index += 1) {
    cells.push({
      x: deterministicUnit(index, 1) * width,
      y: (0.06 + deterministicUnit(index, 2) * 0.88) * height,
      heat: deterministicUnit(index, 3)
    });
  }

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      let nearest = Number.POSITIVE_INFINITY;
      let second = Number.POSITIVE_INFINITY;
      let nearestHeat = 0;
      const sampleX =
        (x + Math.sin(y * 0.067) * 13 + Math.sin((x + y) * 0.031) * 7 + width) % width;
      const sampleY = y + Math.sin(x * 0.051) * 9 + Math.sin((x - y) * 0.027) * 6;
      for (const cell of cells) {
        const rawDx = Math.abs(sampleX - cell.x);
        const dx = Math.min(rawDx, width - rawDx);
        const dy = (sampleY - cell.y) * 1.15;
        const distance = dx * dx + dy * dy;
        if (distance < nearest) {
          second = nearest;
          nearest = distance;
          nearestHeat = cell.heat;
        } else if (distance < second) {
          second = distance;
        }
      }

      const boundaryGap = Math.sqrt(second) - Math.sqrt(nearest);
      const fissure = Math.max(0, Math.min(1, 1 - boundaryGap / 4.2));
      const turbulence =
        Math.sin(x * 0.071 + y * 0.019) * 0.5 +
        Math.sin(y * 0.113 - x * 0.027) * 0.3 +
        Math.sin((x + y) * 0.041) * 0.2;
      const emberCloud = 0.5 + Math.sin(x * 0.029 + Math.sin(y * 0.061) * 2.4) * 0.25 +
        Math.sin(y * 0.047 - Math.sin(x * 0.037) * 2.1) * 0.25;
      const microHeat =
        Math.sin(x * 0.31 + Math.sin(y * 0.17) * 1.8) * 0.5 +
        Math.sin(y * 0.27 - Math.sin(x * 0.13) * 2.1) * 0.5;
      const plate = Math.max(
        0.04,
        Math.min(
          0.82,
          0.07 + nearestHeat * 0.18 + (turbulence * 0.5 + 0.5) * 0.31 + emberCloud * 0.21 + microHeat * 0.07
        )
      );
      const hotEdge = Math.pow(fissure, 2);
      const centerHeat =
        nearestHeat > 0.72
          ? Math.max(0, 1 - Math.sqrt(nearest) / (10 + nearestHeat * 9)) * (nearestHeat - 0.72) * 2.8
          : 0;
      const cloudHeat = Math.max(0, (turbulence * 0.5 + 0.5) * 0.62 + emberCloud * 0.5 - 0.78);
      const heat = Math.min(1, hotEdge + centerHeat * (1 - hotEdge) + cloudHeat * 0.34 * (1 - hotEdge));
      const pixel = (y * width + x) * 4;
      image.data[pixel] = Math.round(38 + plate * 202 + heat * (217 - plate * 138));
      image.data[pixel + 1] = Math.round(4 + plate * 112 + heat * (241 - plate * 82));
      image.data[pixel + 2] = Math.round(1 + plate * 11 + heat * (122 - plate * 8));
      image.data[pixel + 3] = 255;
    }
  }
  context.putImageData(image, 0, 0);
  solarSurfaceTexture = new THREE.CanvasTexture(canvas);
  solarSurfaceTexture.colorSpace = THREE.SRGBColorSpace;
  solarSurfaceTexture.wrapS = THREE.RepeatWrapping;
  solarSurfaceTexture.wrapT = THREE.ClampToEdgeWrapping;
  return solarSurfaceTexture;
}

function getSolarHaloTexture() {
  if (solarHaloTexture) return solarHaloTexture;
  const canvas = document.createElement("canvas");
  canvas.width = 256;
  canvas.height = 256;
  const context = canvas.getContext("2d");
  const gradient = context.createRadialGradient(128, 128, 0, 128, 128, 124);
  gradient.addColorStop(0, "rgba(255,104,18,0)");
  gradient.addColorStop(0.34, "rgba(255,104,18,0)");
  gradient.addColorStop(0.46, "rgba(255,145,26,0.18)");
  gradient.addColorStop(0.52, "rgba(255,182,48,0.96)");
  gradient.addColorStop(0.6, "rgba(255,112,20,0.38)");
  gradient.addColorStop(0.78, "rgba(255,82,14,0.1)");
  gradient.addColorStop(1, "rgba(255,68,8,0)");
  context.fillStyle = gradient;
  context.fillRect(0, 0, 256, 256);
  solarHaloTexture = new THREE.CanvasTexture(canvas);
  solarHaloTexture.colorSpace = THREE.SRGBColorSpace;
  return solarHaloTexture;
}

function getSolarGlareTexture() {
  if (solarGlareTexture) return solarGlareTexture;
  const canvas = document.createElement("canvas");
  canvas.width = 256;
  canvas.height = 256;
  const context = canvas.getContext("2d");
  context.globalCompositeOperation = "lighter";
  for (let index = 0; index < 16; index += 1) {
    const angle = (index / 16) * Math.PI * 2;
    const outerRadius = index % 4 === 0 ? 120 : index % 2 === 0 ? 82 : 56;
    const x = 128 + Math.cos(angle) * outerRadius;
    const y = 128 + Math.sin(angle) * outerRadius;
    const ray = context.createLinearGradient(128, 128, x, y);
    ray.addColorStop(0, "rgba(255,252,220,0.92)");
    ray.addColorStop(0.22, "rgba(255,214,98,0.72)");
    ray.addColorStop(1, "rgba(255,129,28,0)");
    context.strokeStyle = ray;
    context.lineWidth = index % 4 === 0 ? 2.6 : index % 2 === 0 ? 1.8 : 1.1;
    context.beginPath();
    context.moveTo(128, 128);
    context.lineTo(x, y);
    context.stroke();
  }
  const glow = context.createRadialGradient(128, 128, 1, 128, 128, 44);
  glow.addColorStop(0, "rgba(255,255,244,1)");
  glow.addColorStop(0.18, "rgba(255,244,184,0.98)");
  glow.addColorStop(0.52, "rgba(255,177,52,0.42)");
  glow.addColorStop(1, "rgba(255,103,18,0)");
  context.fillStyle = glow;
  context.fillRect(0, 0, 256, 256);
  solarGlareTexture = new THREE.CanvasTexture(canvas);
  solarGlareTexture.colorSpace = THREE.SRGBColorSpace;
  return solarGlareTexture;
}

function getSolarSparkTexture() {
  if (solarSparkTexture) return solarSparkTexture;
  const canvas = document.createElement("canvas");
  canvas.width = 32;
  canvas.height = 32;
  const context = canvas.getContext("2d");
  const glow = context.createRadialGradient(16, 16, 0, 16, 16, 15);
  glow.addColorStop(0, "rgba(255,255,224,1)");
  glow.addColorStop(0.25, "rgba(255,201,82,0.95)");
  glow.addColorStop(1, "rgba(255,100,16,0)");
  context.fillStyle = glow;
  context.fillRect(0, 0, 32, 32);
  solarSparkTexture = new THREE.CanvasTexture(canvas);
  solarSparkTexture.colorSpace = THREE.SRGBColorSpace;
  return solarSparkTexture;
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
      const surfaceTexture = getSolarSurfaceTexture();
      const surfaceTint = new THREE.Color(coreColor).lerp(new THREE.Color(0xffffff), 0.86);
      const coreMaterial = new THREE.MeshStandardMaterial({
        map: surfaceTexture,
        color: surfaceTint,
        emissive: visual.emissive ?? 0x6a1300,
        emissiveMap: surfaceTexture,
        emissiveIntensity: Math.min(visual.emissiveIntensity ?? 0.72, 1.1),
        roughness: 0.86,
        metalness: 0,
        transparent: coreOpacity < 1,
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
        new THREE.SphereGeometry(coronaRadius, 32, 20),
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
      corona.material.side = THREE.BackSide;
      corona.userData.restingOpacity = coronaOpacity;
      corona.userData.flareOpacity = visual.flareCoronaOpacity ?? Math.min(0.32, coronaOpacity * 1.8);
      g.add(corona);

      const limb = new THREE.Mesh(
        new THREE.SphereGeometry(coreRadius * 1.035, 40, 28),
        new THREE.MeshBasicMaterial({
          color: visual.limbColor ?? 0xffd264,
          transparent: true,
          opacity: visual.limbOpacity ?? 0.78,
          side: THREE.BackSide,
          depthWrite: false,
          blending: THREE.AdditiveBlending
        })
      );
      limb.position.y = coreHeight;
      limb.name = "solar-limb";
      g.add(limb);

      const halo = new THREE.Sprite(
        new THREE.SpriteMaterial({
          map: getSolarHaloTexture(),
          color: visual.haloColor ?? coronaColor,
          transparent: true,
          opacity: visual.haloOpacity ?? 0.62,
          blending: THREE.AdditiveBlending,
          depthWrite: false,
          depthTest: false
        })
      );
      const haloSize = visual.haloSize ?? coronaRadius * 3;
      halo.position.y = coreHeight;
      halo.scale.set(haloSize, haloSize, 1);
      halo.name = "solar-halo";
      halo.renderOrder = -2;
      g.add(halo);

      const glare = new THREE.Sprite(
        new THREE.SpriteMaterial({
          map: getSolarGlareTexture(),
          color: visual.glareColor ?? 0xffd982,
          transparent: true,
          opacity: visual.glareOpacity ?? 0.9,
          blending: THREE.AdditiveBlending,
          depthWrite: false,
          depthTest: false
        })
      );
      const glareSize = visual.glareSize ?? coreRadius * 2.7;
      glare.position.y = coreHeight;
      glare.scale.set(glareSize, glareSize, 1);
      glare.name = "solar-glare";
      glare.renderOrder = 4;
      g.add(glare);

      const sparkCount = visual.sparkCount ?? 42;
      const sparkInnerRadius = visual.sparkInnerRadius ?? coronaRadius * 1.05;
      const sparkOuterRadius = visual.sparkOuterRadius ?? coronaRadius * 2.1;
      const sparkPositions = new Float32Array(sparkCount * 3);
      for (let index = 0; index < sparkCount; index += 1) {
        const angle = deterministicUnit(index, 11) * Math.PI * 2;
        const radius = sparkInnerRadius + deterministicUnit(index, 12) * (sparkOuterRadius - sparkInnerRadius);
        sparkPositions[index * 3] = Math.cos(angle) * radius;
        sparkPositions[index * 3 + 1] = coreHeight + (deterministicUnit(index, 13) - 0.5) * coreRadius * 1.8;
        sparkPositions[index * 3 + 2] = Math.sin(angle) * radius;
      }
      const sparkGeometry = new THREE.BufferGeometry();
      sparkGeometry.setAttribute("position", new THREE.BufferAttribute(sparkPositions, 3));
      const sparks = new THREE.Points(
        sparkGeometry,
        new THREE.PointsMaterial({
          map: getSolarSparkTexture(),
          color: visual.sparkColor ?? 0xffb13b,
          size: visual.sparkSize ?? 0.32,
          transparent: true,
          opacity: visual.sparkOpacity ?? 0.82,
          blending: THREE.AdditiveBlending,
          depthWrite: false,
          depthTest: false,
          sizeAttenuation: true
        })
      );
      sparks.name = "solar-sparks";
      g.add(sparks);

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
