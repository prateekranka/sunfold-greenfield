// Builds Three.js terrain meshes from MapDefinition terrain specs.
// Sunfold palette: warm brass platforms, turquoise energy, void space.

import * as THREE from "three";

const PALETTE = {
  platform: 0x8a7a62,
  platformEdge: 0xc29b5d,
  energy: 0x3ecfc0,
  solar: 0xffa030,
  solarCore: 0xff6a18,
  void: 0x050711,
  debris: 0x4a4540,
  bridge: 0x9a8a70,
  bridgeBroken: 0x5a5048
};

/**
 * @param {import('./map-definition.js').TerrainSpec} terrain
 * @param {import('./map-definition.js').BridgeSpec[]} bridges
 * @returns {{ group: THREE.Group, platformMeshes: Map<string, THREE.Mesh>, bridgeMeshes: Map<string, THREE.Group> }}
 */
export function buildTerrain(terrain, bridges = []) {
  const group = new THREE.Group();
  group.name = "rts-terrain";
  const platformMeshes = new Map();
  const bridgeMeshes = new Map();

  const palette = { ...PALETTE, ...terrain.palette };

  // Starfield backdrop — simple points
  const starGeo = new THREE.BufferGeometry();
  const starCount = 400;
  const positions = new Float32Array(starCount * 3);
  for (let i = 0; i < starCount; i += 1) {
    const theta = (i / starCount) * Math.PI * 2 * 7.3;
    const r = 80 + (i % 17) * 2.1;
    const y = ((i % 31) - 15) * 1.8;
    positions[i * 3] = Math.cos(theta) * r;
    positions[i * 3 + 1] = y;
    positions[i * 3 + 2] = Math.sin(theta) * r;
  }
  starGeo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  const stars = new THREE.Points(
    starGeo,
    new THREE.PointsMaterial({ color: 0xd4c8a8, size: 0.35, sizeAttenuation: true })
  );
  group.add(stars);

  for (const p of terrain.platforms) {
    const mesh = makePlatform(p, palette);
    platformMeshes.set(p.id, mesh);
    group.add(mesh);
  }

  for (const d of terrain.debris ?? []) {
    group.add(makeDebris(d, palette));
  }

  for (const b of bridges) {
    const bg = makeBridge(b, palette, b.startsEnabled !== false);
    bridgeMeshes.set(b.id, bg);
    group.add(bg);
  }

  return { group, platformMeshes, bridgeMeshes };
}

/**
 * @param {import('./map-definition.js').PlatformSpec} spec
 * @param {Record<string, number>} palette
 */
function makePlatform(spec, palette) {
  const g = new THREE.Group();
  g.name = `platform-${spec.id}`;
  const h = spec.height ?? 0;
  g.position.set(spec.center.x, h, spec.center.z);
  if (spec.yaw) g.rotation.y = spec.yaw;

  const radius = spec.radius;
  const arc = spec.arc ?? Math.PI * 0.55;

  // Main deck — ring segment or disc
  const segments = 32;
  const shape = new THREE.Shape();
  if (arc >= Math.PI * 1.9) {
    shape.absarc(0, 0, radius, 0, Math.PI * 2, false);
  } else {
    const a0 = -arc / 2;
    const a1 = arc / 2;
    shape.moveTo(0, 0);
    shape.lineTo(Math.cos(a0) * radius, Math.sin(a0) * radius);
    shape.absarc(0, 0, radius, a0, a1, false);
    shape.lineTo(0, 0);
  }

  const geo = new THREE.ExtrudeGeometry(shape, { depth: 0.35, bevelEnabled: false });
  geo.rotateX(-Math.PI / 2);
  const mat = new THREE.MeshBasicMaterial({ color: palette.platform });
  const deck = new THREE.Mesh(geo, mat);
  deck.position.y = 0.02;
  g.add(deck);

  // Brass rim
  const rim = new THREE.Mesh(
    new THREE.TorusGeometry(radius * 0.92, 0.06, 6, segments, arc),
    new THREE.MeshBasicMaterial({ color: palette.platformEdge, transparent: true, opacity: 0.85 })
  );
  rim.rotation.x = Math.PI / 2;
  if (arc < Math.PI * 1.9) rim.rotation.z = -arc / 2;
  rim.position.y = 0.12;
  g.add(rim);

  // Turquoise energy veins (simple lines)
  const veinMat = new THREE.MeshBasicMaterial({
    color: palette.energy,
    transparent: true,
    opacity: 0.55
  });
  for (let i = 0; i < 3; i += 1) {
    const a = ((i - 1) * arc) / 4;
    const vein = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.04, radius * 0.7), veinMat);
    vein.position.set(Math.sin(a) * radius * 0.35, 0.18, Math.cos(a) * radius * 0.35);
    vein.rotation.y = a;
    g.add(vein);
  }

  return /** @type {THREE.Mesh} */ (/** @type {unknown} */ (g));
}

/**
 * @param {import('./map-definition.js').DebrisSpec} spec
 * @param {Record<string, number>} palette
 */
function makeDebris(spec, palette) {
  const g = new THREE.Group();
  g.position.set(spec.center.x, -0.5 + (spec.radius % 3) * 0.2, spec.center.z);
  const rock = new THREE.Mesh(
    new THREE.IcosahedronGeometry(spec.radius, 0),
    new THREE.MeshBasicMaterial({ color: palette.debris })
  );
  rock.scale.set(1.2, 0.7, 1.1);
  g.add(rock);
  return g;
}

/**
 * @param {import('./map-definition.js').BridgeSpec} spec
 * @param {Record<string, number>} palette
 * @param {boolean} enabled
 */
function makeBridge(spec, palette, enabled) {
  const g = new THREE.Group();
  g.name = `bridge-${spec.id}`;
  const dx = spec.to.x - spec.from.x;
  const dz = spec.to.z - spec.from.z;
  const len = Math.hypot(dx, dz);
  const midX = (spec.from.x + spec.to.x) / 2;
  const midZ = (spec.from.z + spec.to.z) / 2;
  const yaw = Math.atan2(dx, dz);

  g.position.set(midX, 0.08, midZ);
  g.rotation.y = yaw;

  const mat = new THREE.MeshBasicMaterial({
    color: enabled ? palette.bridge : palette.bridgeBroken,
    transparent: !enabled,
    opacity: enabled ? 1 : 0.45
  });

  if (enabled) {
    const deck = new THREE.Mesh(new THREE.BoxGeometry(2.8, 0.12, len), mat);
    g.add(deck);
    // Energy railings
    for (const side of [-1.2, 1.2]) {
      const rail = new THREE.Mesh(
        new THREE.BoxGeometry(0.06, 0.35, len * 0.95),
        new THREE.MeshBasicMaterial({ color: palette.energy, transparent: true, opacity: 0.7 })
      );
      rail.position.x = side;
      rail.position.y = 0.2;
      g.add(rail);
    }
  } else {
    // Broken — two fragments with gap
    const fragLen = len * 0.38;
    for (const sign of [-1, 1]) {
      const frag = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.1, fragLen), mat);
      frag.position.z = sign * (len * 0.28);
      g.add(frag);
    }
    const spark = new THREE.Mesh(
      new THREE.SphereGeometry(0.25, 8, 8),
      new THREE.MeshBasicMaterial({ color: palette.energy, transparent: true, opacity: 0.8 })
    );
    spark.position.y = 0.35;
    spark.name = "bridge-spark";
    g.add(spark);
  }

  g.userData.bridgeId = spec.id;
  g.userData.enabled = enabled;
  return g;
}

/**
 * @param {THREE.Group} bridgeGroup
 * @param {boolean} enabled
 * @param {Record<string, number>} [palette]
 */
export function setBridgeVisual(bridgeGroup, enabled, palette = PALETTE) {
  bridgeGroup.userData.enabled = enabled;
  bridgeGroup.clear();
  const spec = bridgeGroup.userData.spec;
  if (!spec) return;
  const rebuilt = makeBridge(spec, palette, enabled);
  while (rebuilt.children.length) {
    bridgeGroup.add(rebuilt.children[0]);
  }
}

export { PALETTE as TERRAIN_PALETTE };
