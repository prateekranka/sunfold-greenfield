// Procedural unit builders — visible debug fallbacks.
//
// Fidelity Ladder: "Procedural primitives are permitted only as debug
// fallbacks." These stand in whenever an authored representation is missing or
// fails to load, so simulation tests and headless runs still see every unit.
// Each kind gets a distinct silhouette (visual bible: unit scale & formations);
// faction palettes tint cloth/trim so ownership reads at zoom. They are
// deliberately primitive and are never the shipping visual target.

import * as THREE from "three";

export const PROCEDURAL_PALETTES = Object.freeze({
  sunwoven: Object.freeze({
    cloth: 0xf0e4c8, // warm ivory
    trim: 0x3fa7a6, // turquoise
    gold: 0xdea84f, // woven gold
    dark: 0x8a743a
  }),
  gravemark: Object.freeze({
    cloth: 0x4a4a55, // layered slate
    trim: 0x6b7f9e, // mineral blue
    gold: 0xb87333, // copper
    dark: 0x2c2c34
  })
});

function palette(faction) {
  return PROCEDURAL_PALETTES[faction] ?? PROCEDURAL_PALETTES.sunwoven;
}

function mat(color, opts = {}) {
  return new THREE.MeshStandardMaterial({
    color,
    roughness: opts.roughness ?? 0.8,
    metalness: opts.metalness ?? 0.05,
    ...(opts.emissive
      ? { emissive: opts.emissive, emissiveIntensity: opts.emissiveIntensity ?? 0.5 }
      : {})
  });
}

/** Uniformly scale a built group so its bounding height equals `meters`. */
export function fitToHeight(group, meters) {
  const box = new THREE.Box3().setFromObject(group);
  const height = box.max.y - box.min.y;
  if (height > 1e-4 && Math.abs(height - meters) > 1e-3) {
    group.scale.multiplyScalar(meters / height);
  }
  return group;
}

// ---- per-kind silhouettes (all heights ~1.8 m pre-fit; fitToHeight normalises)

function buildCitizen(group, p) {
  // Small biped: robe + head + sash + handheld tool.
  const robe = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.3, 0.62, 10), mat(p.cloth));
  robe.position.y = 0.31;
  const hem = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.05, 10), mat(p.trim));
  hem.position.y = 0.05;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.13, 10, 8), mat(p.cloth));
  head.position.y = 0.78;
  const sash = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.07, 0.24), mat(p.trim));
  sash.position.y = 0.5;
  const tool = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.03, 0.42, 6), mat(p.gold, { metalness: 0.4 }));
  tool.position.set(0.16, 0.5, 0);
  tool.rotation.z = 0.5;
  group.add(robe, hem, head, sash, tool);
}

function buildPathfinder(group, p) {
  // Slim, tall, elevated sensor/pack + staff.
  const robe = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.2, 0.68, 8), mat(p.cloth));
  robe.position.y = 0.34;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), mat(p.cloth));
  head.position.y = 0.86;
  const staff = new THREE.Mesh(new THREE.CylinderGeometry(0.024, 0.024, 1.15, 6), mat(p.dark));
  staff.position.set(0.17, 0.62, 0);
  const staffTip = new THREE.Mesh(
    new THREE.SphereGeometry(0.045, 8, 6),
    mat(p.gold, { emissive: p.gold, emissiveIntensity: 0.9 })
  );
  staffTip.position.set(0.17, 1.24, 0);
  const pack = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.24, 0.12), mat(p.trim));
  pack.position.set(-0.1, 0.52, 0);
  group.add(robe, head, staff, staffTip, pack);
}

function buildVanguard(group, p) {
  // Broad-shouldered, shield + weapon.
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.52, 0.3), mat(p.cloth));
  body.position.y = 0.52;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.14, 10, 8), mat(p.dark));
  head.position.y = 0.96;
  const shield = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.24, 0.06, 12), mat(p.gold, { metalness: 0.35 }));
  shield.position.set(0.31, 0.62, 0);
  shield.rotation.z = Math.PI / 2;
  const weapon = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.6, 6), mat(p.dark));
  weapon.position.set(-0.3, 0.56, 0);
  weapon.rotation.z = 0.2;
  group.add(body, head, shield, weapon);
}

function buildQuarrel(group, p) {
  // Crouched, long weapon.
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.34, 0.26), mat(p.cloth));
  body.position.y = 0.34;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.12, 10, 8), mat(p.cloth));
  head.position.y = 0.63;
  const bow = new THREE.Mesh(
    new THREE.TorusGeometry(0.26, 0.018, 6, 20, Math.PI * 0.85),
    mat(p.trim, { metalness: 0.2 })
  );
  bow.position.set(-0.27, 0.52, 0);
  bow.rotation.z = Math.PI / 2;
  const quiver = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.3, 8), mat(p.dark));
  quiver.position.set(0.14, 0.42, 0.08);
  group.add(body, head, bow, quiver);
}

function buildTransport(group, p) {
  // Flat barge/skiff with rails.
  const hull = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.14, 0.9), mat(p.cloth));
  hull.position.y = 0.18;
  const railL = new THREE.Mesh(new THREE.BoxGeometry(1.5, 0.05, 0.05), mat(p.trim));
  railL.position.set(0, 0.34, -0.36);
  const railR = railL.clone();
  railR.position.z = 0.36;
  const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.7, 6), mat(p.dark));
  mast.position.set(0, 0.52, 0);
  const lamp = new THREE.Mesh(
    new THREE.SphereGeometry(0.07, 8, 6),
    mat(p.gold, { emissive: p.gold, emissiveIntensity: 1.0 })
  );
  lamp.position.set(0, 0.9, 0);
  group.add(hull, railL, railR, mast, lamp);
}

function buildBastionWalker(group, p) {
  // Heavy quadruped walker: body + 4 legs + head + cannon.
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.85, 0.4, 0.5), mat(p.dark));
  body.position.y = 0.78;
  const head = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.26, 0.36), mat(p.cloth));
  head.position.set(0.42, 1.02, 0);
  const eyeL = new THREE.Mesh(
    new THREE.SphereGeometry(0.05, 8, 6),
    mat(p.gold, { emissive: p.gold, emissiveIntensity: 1.2 })
  );
  eyeL.position.set(0.56, 1.06, 0.08);
  const eyeR = eyeL.clone();
  eyeR.position.z = -0.08;
  const cannon = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.11, 0.65, 8), mat(p.gold, { metalness: 0.4 }));
  cannon.position.set(0.5, 0.72, 0);
  cannon.rotation.z = Math.PI / 2;
  const legs = [];
  for (const [sx, sz] of [[-0.28, 0.22], [-0.28, -0.22], [0.28, 0.22], [0.28, -0.22]]) {
    const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.09, 0.52, 8), mat(p.cloth));
    leg.position.set(sx, 0.34, sz);
    legs.push(leg);
  }
  group.add(body, head, eyeL, eyeR, cannon, ...legs);
}

function buildStoneguard(group, p) {
  // Heavy defensive infantry: tower body + tower shield + spear.
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.44, 0.7, 0.34), mat(p.cloth));
  body.position.y = 0.55;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.13, 10, 8), mat(p.dark));
  head.position.y = 1.05;
  const shield = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.72, 0.08), mat(p.trim, { metalness: 0.3 }));
  shield.position.set(0.33, 0.6, 0);
  shield.rotation.z = Math.PI / 2;
  const spear = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.026, 1.1, 6), mat(p.dark));
  spear.position.set(-0.28, 0.75, 0);
  const tip = new THREE.Mesh(
    new THREE.ConeGeometry(0.05, 0.16, 6),
    mat(p.gold, { emissive: p.gold, emissiveIntensity: 0.6 })
  );
  tip.position.set(-0.28, 1.34, 0);
  group.add(body, head, shield, spear, tip);
}

/**
 * Build a visible debug-fallback unit from primitives.
 * @param {{kind: string, faction?: string, height?: number}} opts
 * @returns {THREE.Group} group.userData.procedural === true
 */
export function createProceduralUnit({ kind, faction = "sunwoven", height = 1.8 }) {
  const p = palette(faction);
  const group = new THREE.Group();
  switch (kind) {
    case "pathfinder":
      buildPathfinder(group, p);
      break;
    case "vanguard":
      buildVanguard(group, p);
      break;
    case "quarrel":
      buildQuarrel(group, p);
      break;
    case "lightTransport":
      buildTransport(group, p);
      break;
    case "bastionWalker":
      buildBastionWalker(group, p);
      break;
    case "stoneguard":
      buildStoneguard(group, p);
      break;
    case "citizen":
    default:
      buildCitizen(group, p);
      break;
  }
  fitToHeight(group, height);
  group.userData.procedural = true;
  group.userData.kind = kind;
  group.userData.faction = faction;
  return group;
}
