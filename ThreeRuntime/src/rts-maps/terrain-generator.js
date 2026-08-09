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

// Shared Helios debris geometry. The field can contain many rocks, so avoid
// allocating one geometry per sample while keeping deterministic transforms.
const HELIOS_DEBRIS_GEOMETRY = new THREE.IcosahedronGeometry(1, 0);
const HELIOS_DEBRIS_CRYSTAL_GEOMETRY = new THREE.ConeGeometry(1, 1, 5);

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
  const visual = terrain.visual?.style === "broken-ring" ? terrain.visual : null;
  const visualPalette = visual ? { ...palette, ...visual.palette } : palette;
  const visualMaterials = visual ? createHeliosMaterials(visualPalette) : null;

  // Helios uses a deterministic presentation path. Other maps retain the
  // original low-cost starfield and platform rendering below.
  if (visual) addHeliosStarfield(group, visual, visualPalette, visualMaterials);
  else addLegacyStarfield(group);

  for (const p of terrain.platforms) {
    const mesh = visual
      ? makeHeliosPlatform(p, visual, visualPalette, visualMaterials)
      : makePlatform(p, palette);
    platformMeshes.set(p.id, mesh);
    group.add(mesh);
  }

  for (const d of terrain.debris ?? []) {
    group.add(visual ? makeHeliosDebris(d, visual, visualMaterials) : makeDebris(d, palette));
  }

  if (visual) {
    addHeliosDebrisField(group, visual, visualMaterials);
    addHeliosMarkers(group, visual, visualPalette, visualMaterials);
  }

  for (const b of bridges) {
    const bg = makeBridge(
      b,
      visual ? visualPalette : palette,
      b.startsEnabled !== false,
      visualMaterials
    );
    bridgeMeshes.set(b.id, bg);
    group.add(bg);
  }

  return { group, platformMeshes, bridgeMeshes };
}

function addLegacyStarfield(group) {
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
  group.add(
    new THREE.Points(
      starGeo,
      new THREE.PointsMaterial({ color: 0xd4c8a8, size: 0.35, sizeAttenuation: true })
    )
  );
}

/**
 * Helios material bundle. One material instance is shared by every matching
 * cosmetic mesh in this map, which keeps the dense ring inexpensive.
 */
function createHeliosMaterials(palette) {
  const metal = (color, roughness, metalness = 0.8, extra = {}) =>
    new THREE.MeshStandardMaterial({ color, roughness, metalness, ...extra });
  const glow = (color, intensity = 1.1, opacity = 1) =>
    new THREE.MeshStandardMaterial({
      color,
      emissive: color,
      emissiveIntensity: intensity,
      roughness: 0.32,
      metalness: 0.35,
      transparent: opacity < 1,
      opacity
    });

  return {
    understructure: metal(palette.understructure ?? 0x0b1017, 0.9, 0.9),
    basalt: metal(palette.basalt ?? 0x171d25, 0.84, 0.86),
    basaltEdge: metal(palette.basaltEdge ?? 0x29323c, 0.74, 0.9),
    deck: metal(palette.deck ?? 0x59616a, 0.66, 0.92),
    deckLight: metal(palette.deckLight ?? 0x76808a, 0.58, 0.94),
    seam: metal(palette.seam ?? 0x252d36, 0.9, 0.62),
    gold: glow(palette.gold ?? 0xe9a749, 0.9),
    goldBright: glow(palette.goldBright ?? 0xffcf72, 1.45),
    conduit: glow(palette.conduit ?? 0x35d8ce, 1.15, 0.86),
    conduitBright: glow(palette.conduitBright ?? 0x83fff1, 1.75),
    spawn: glow(palette.spawn ?? 0x328dff, 1.2, 0.88),
    resource: glow(palette.resource ?? 0x3ed9b5, 1.2, 0.9),
    crystal: glow(palette.crystal ?? 0x46e5e2, 1.45),
    rock: metal(palette.rock ?? 0x1a232d, 0.95, 0.78),
    goldLine: line(palette.gold ?? 0xe9a749, 0.78),
    seamLine: line(palette.seam ?? 0x252d36, 0.9),
    conduitLine: line(palette.conduit ?? 0x35d8ce, 0.8),
    conduitBrightLine: line(palette.conduitBright ?? 0x83fff1, 0.96),
    star: new THREE.PointsMaterial({
      color: palette.star ?? 0xb7d8ff,
      size: 0.28,
      sizeAttenuation: true,
      transparent: true,
      opacity: 0.82,
      depthWrite: false
    }),
    starBright: new THREE.PointsMaterial({
      color: palette.goldBright ?? 0xffcf72,
      size: 0.48,
      sizeAttenuation: true,
      transparent: true,
      opacity: 0.92,
      depthWrite: false
    }),
    voidRing: new THREE.MeshBasicMaterial({
      color: palette.void ?? 0x030812,
      transparent: true,
      opacity: 0.52,
      depthWrite: false
    })
  };

  function line(color, opacity) {
    return new THREE.LineBasicMaterial({
      color,
      transparent: opacity < 1,
      opacity,
      depthWrite: false
    });
  }
}

function addHeliosStarfield(group, visual, palette, materials) {
  const field = visual.starfield ?? {};
  const count = field.count ?? 520;
  const innerRadius = field.innerRadius ?? 74;
  const outerRadius = field.outerRadius ?? 106;
  const height = field.height ?? 42;
  const random = seededRandom((visual.seed ?? 1) ^ 0x51a7);
  const starPositions = [];
  const brightPositions = [];

  for (let i = 0; i < count; i += 1) {
    const theta = random() * Math.PI * 2;
    const radius = innerRadius + Math.sqrt(random()) * (outerRadius - innerRadius);
    const y = (random() - 0.46) * height;
    const target = i % 13 === 0 ? brightPositions : starPositions;
    target.push(new THREE.Vector3(Math.cos(theta) * radius, y, Math.sin(theta) * radius));
  }

  const stars = makePoints(starPositions, materials.star);
  const bright = makePoints(brightPositions, materials.starBright);
  group.add(stars, bright);
  disableCosmeticRaycast(stars);
  disableCosmeticRaycast(bright);
}

function makePoints(points, material) {
  const geometry = new THREE.BufferGeometry().setFromPoints(points);
  return new THREE.Points(geometry, material);
}

function makeHeliosPlatform(spec, visual, palette, materials) {
  const fragment = visual.fragments?.find((entry) => entry.id === spec.id);
  let platform;
  if (fragment) {
    platform = makeHeliosRingFragment(spec, visual, fragment, materials);
  } else if (spec.id.startsWith("isle-")) {
    platform = makeHeliosIslet(spec, materials, (visual.seed ?? 1) + hashString(spec.id));
  } else if (spec.id === "core-platform") {
    platform = makeHeliosCoreVoid(spec, materials);
  } else {
    platform = makePlatform(spec, palette);
  }
  platform.userData.logicalPlatformId = spec.id;
  disableCosmeticRaycast(platform);
  return platform;
}

function makeHeliosRingFragment(spec, visual, fragment, materials) {
  const g = new THREE.Group();
  g.name = `platform-${spec.id}`;
  g.position.set(visual.center?.x ?? 0, 0, visual.center?.z ?? 0);
  // The visual data uses the conventional world angle: 0=east, +PI/2=south.
  // The local annular sector is authored in the same XZ basis.
  g.rotation.y = -(fragment.centerAngle ?? 0);

  const span = fragment.span ?? visual.fragmentSpan ?? Math.PI * 0.42;
  const inner = fragment.innerRadius ?? visual.innerRadius ?? spec.radius * 1.9;
  const outer = fragment.outerRadius ?? visual.outerRadius ?? spec.radius * 3.9;
  const underDepth = visual.understructureDepth ?? visual.platformDepth ?? 1.8;
  const panelCount = visual.panelCount ?? 6;
  const conduitCount = visual.conduitCount ?? 4;
  const surfaceY = visual.surfaceY ?? 0.04;
  const start = -span / 2 + 0.035;
  const end = span / 2 - 0.035;
  const midRadius = (inner + outer) * 0.5;

  const under = new THREE.Mesh(
    makeAnnularSectorGeometry(inner, outer, span, underDepth, 30),
    materials.understructure
  );
  under.position.y = surfaceY - underDepth * 0.5 - 0.18;
  g.add(under);

  const armorDepth = 0.28;
  const armor = new THREE.Mesh(
    makeAnnularSectorGeometry(inner + 0.18, outer - 0.18, span - 0.025, armorDepth, 30),
    materials.basaltEdge
  );
  armor.position.y = surfaceY - armorDepth * 0.5 - 0.06;
  g.add(armor);

  const deckInset = visual.deckInset ?? 0.78;
  const deckDepth = 0.14;
  const deck = new THREE.Mesh(
    makeAnnularSectorGeometry(inner + deckInset, outer - deckInset, span - 0.04, deckDepth, 30),
    materials.deck
  );
  deck.position.y = surfaceY - deckDepth * 0.5;
  g.add(deck);

  const highlightDepth = 0.025;
  const deckHighlight = new THREE.Mesh(
    makeAnnularSectorGeometry(inner + deckInset + 0.16, outer - deckInset - 0.2, span - 0.075, highlightDepth, 30),
    materials.deckLight
  );
  deckHighlight.position.y = surfaceY + highlightDepth * 0.5;
  g.add(deckHighlight);

  addArcLine(g, outer - 0.24, start, end, surfaceY + 0.035, materials.goldLine, 24);
  addArcLine(g, inner + 0.24, start, end, surfaceY + 0.035, materials.goldLine, 24);
  addArcLine(g, midRadius, start + 0.04, end - 0.04, surfaceY + 0.04, materials.seamLine, 24);

  for (let i = 0; i <= panelCount; i += 1) {
    const a = THREE.MathUtils.lerp(start, end, i / panelCount);
    addRadialBar(
      g,
      a,
      inner + deckInset + 0.2,
      outer - deckInset - 0.2,
      0.08,
      0.055,
      materials.seam,
      surfaceY + 0.045
    );
    if (i > 0 && i < panelCount) {
      const ribY = surfaceY - underDepth * 0.55;
      addEdgeRib(g, outer - 0.2, a, 0.72, 0.72, materials.basaltEdge, ribY);
      addEdgeRib(g, inner + 0.2, a, 0.62, 0.72, materials.basaltEdge, ribY);
    }
  }

  const random = seededRandom((visual.seed ?? 1) + hashString(spec.id));
  for (let i = 0; i < conduitCount; i += 1) {
    const a = THREE.MathUtils.lerp(start + 0.1, end - 0.22, random());
    const length = 0.16 + random() * 0.25;
    const radius = inner + 2.1 + random() * (outer - inner - 4.2);
    const material = i % 3 === 0 ? materials.conduitBrightLine : materials.conduitLine;
    const meshMaterial = i % 3 === 0 ? materials.conduitBright : materials.conduit;
    addArcLine(g, radius, a, Math.min(end, a + length), surfaceY + 0.065, material, 8);
    addRadialBar(
      g,
      a + length,
      radius - 0.42,
      radius + 0.42,
      0.045,
      0.05,
      meshMaterial,
      surfaceY + 0.07
    );
  }

  for (const a of [start, end]) {
    addHeliosSocket(g, outer - 0.55, a, 0.52, materials, surfaceY);
    addHeliosSocket(g, inner + 0.7, a, 0.38, materials, surfaceY);
  }

  g.userData.visualStyle = "broken-ring-fragment";
  g.userData.platformSpec = spec;
  return g;
}

function makeAnnularSectorGeometry(inner, outer, span, depth, segments) {
  const start = -span / 2;
  const step = span / segments;
  const halfDepth = depth * 0.5;
  const positions = [];
  const indices = [];

  for (let i = 0; i <= segments; i += 1) {
    const angle = start + step * i;
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    positions.push(
      c * outer,
      halfDepth,
      s * outer,
      c * inner,
      halfDepth,
      s * inner,
      c * outer,
      -halfDepth,
      s * outer,
      c * inner,
      -halfDepth,
      s * inner
    );
  }

  const quad = (a, b, c, d) => indices.push(a, b, c, a, c, d);
  for (let i = 0; i < segments; i += 1) {
    const a = i * 4;
    const b = (i + 1) * 4;
    quad(a + 1, b + 1, b, a); // top
    quad(a + 2, b + 2, b + 3, a + 3); // bottom
    quad(a, b, b + 2, a + 2); // outer wall
    quad(a + 3, b + 3, b + 1, a + 1); // inner wall
  }
  const last = segments * 4;
  quad(0, 2, 3, 1); // start cap
  quad(last + 1, last + 3, last + 2, last); // end cap

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function addArcLine(parent, radius, start, end, y, material, segments = 16) {
  const points = [];
  for (let i = 0; i <= segments; i += 1) {
    const angle = THREE.MathUtils.lerp(start, end, i / segments);
    points.push(new THREE.Vector3(Math.cos(angle) * radius, y, Math.sin(angle) * radius));
  }
  const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(points), material);
  parent.add(line);
  return line;
}

function addRadialBar(parent, angle, inner, outer, width, height, material, y = 0.06) {
  const length = Math.max(0.1, outer - inner);
  const bar = new THREE.Mesh(new THREE.BoxGeometry(width, height, length), material);
  bar.position.set(Math.cos(angle) * (inner + outer) * 0.5, y, Math.sin(angle) * (inner + outer) * 0.5);
  bar.rotation.y = Math.PI / 2 - angle;
  parent.add(bar);
  return bar;
}

function addEdgeRib(parent, radius, angle, width, height, material, y) {
  const rib = new THREE.Mesh(new THREE.BoxGeometry(width, height, 0.62), material);
  rib.position.set(Math.cos(angle) * radius, y, Math.sin(angle) * radius);
  rib.rotation.y = Math.PI / 2 - angle;
  parent.add(rib);
  return rib;
}

function addHeliosSocket(parent, radius, angle, size, materials, surfaceY = 0.04) {
  const socket = new THREE.Group();
  socket.position.set(Math.cos(angle) * radius, surfaceY + 0.03, Math.sin(angle) * radius);
  const cap = new THREE.Mesh(new THREE.CylinderGeometry(size, size * 0.9, 0.12, 10), materials.gold);
  socket.add(cap);
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(size * 0.92, Math.max(0.05, size * 0.12), 6, 12),
    materials.goldBright
  );
  ring.rotation.x = Math.PI / 2;
  ring.position.y = 0.045;
  socket.add(ring);
  parent.add(socket);
  return socket;
}

function makeHeliosCoreVoid(spec, materials) {
  const g = new THREE.Group();
  g.name = `platform-${spec.id}`;
  g.position.set(spec.center.x, -0.96, spec.center.z);
  const ring = new THREE.Mesh(new THREE.RingGeometry(6.4, 8.45, 48), materials.voidRing);
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.04;
  g.add(ring);
  g.userData.visualStyle = "central-void-support";
  return g;
}

function makeHeliosIslet(spec, materials, seed) {
  const g = new THREE.Group();
  g.name = `platform-${spec.id}`;
  g.position.set(spec.center.x, -1.05, spec.center.z);
  const random = seededRandom(seed);
  const radius = spec.radius;

  const rock = new THREE.Mesh(new THREE.IcosahedronGeometry(1, 1), materials.rock);
  rock.scale.set(radius * 1.05, radius * 0.34, radius * 0.92);
  rock.rotation.set(random() * 0.3, random() * Math.PI * 2, random() * 0.25);
  g.add(rock);

  const cap = new THREE.Mesh(
    new THREE.CylinderGeometry(radius * 0.84, radius * 0.96, 0.26, 9),
    materials.basaltEdge
  );
  cap.position.y = radius * 0.28;
  cap.rotation.y = random() * 0.4;
  g.add(cap);

  for (let i = 0; i < 3; i += 1) {
    const angle = random() * Math.PI * 2;
    const crystal = new THREE.Mesh(
      new THREE.ConeGeometry(0.28 + random() * 0.1, 0.72 + random() * 0.28, 5),
      materials.crystal
    );
    crystal.position.set(Math.cos(angle) * (0.55 + random() * 0.6), radius * 0.28 + 0.35, Math.sin(angle) * (0.55 + random() * 0.6));
    crystal.rotation.z = (random() - 0.5) * 0.45;
    crystal.rotation.x = (random() - 0.5) * 0.45;
    g.add(crystal);
  }

  g.userData.visualStyle = "mineral-islet";
  return g;
}

function addHeliosMarkers(group, visual, palette, materials) {
  const markers = new THREE.Group();
  markers.name = "helios-visual-markers";
  const surfaceY = visual.surfaceY ?? 0.04;

  for (const pad of visual.spawnPads ?? []) {
    const g = new THREE.Group();
    g.name = `spawn-pad-${pad.id}`;
    g.position.set(pad.position.x, surfaceY, pad.position.z);
    const radius = pad.radius ?? 2;
    const color = pad.color ?? palette.spawn;
    const material = color === palette.spawn ? materials.spawn : createMarkerMaterial(color, materials.spawn);
    const base = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius * 0.93, 0.12, 20), material);
    g.add(base);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(radius * 0.98, 0.1, 6, 20), materials.conduit);
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.09;
    g.add(ring);
    markers.add(g);
  }

  for (const landmark of visual.landmarks ?? []) {
    const g = new THREE.Group();
    g.name = `landmark-${landmark.id}`;
    g.position.set(landmark.position.x, surfaceY, landmark.position.z);
    const radius = landmark.radius ?? 1.5;
    const material = landmark.color === palette.gold || landmark.color === undefined
      ? materials.gold
      : createMarkerMaterial(landmark.color, materials.gold);
    const base = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius * 0.86, 0.18, 12), material);
    g.add(base);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(radius * 0.92, 0.1, 6, 16), materials.goldBright);
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.13;
    g.add(ring);
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.2, 0.5, 8), materials.goldBright);
    post.position.y = 0.3;
    g.add(post);
    markers.add(g);
  }

  for (const zone of visual.resourceZones ?? []) {
    const g = new THREE.Group();
    g.name = `resource-zone-${zone.id}`;
    const isletElevation = zone.id.startsWith("zone-isle-") ? 0.58 : 0;
    g.position.set(zone.position.x, surfaceY + isletElevation, zone.position.z);
    const radius = zone.radius ?? 1.5;
    const color = zone.color ?? palette.resource;
    const material = color === palette.resource ? materials.resource : createMarkerMaterial(color, materials.resource);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(radius, 0.08, 6, 18), material);
    ring.rotation.x = Math.PI / 2;
    g.add(ring);
    const marker = new THREE.Mesh(new THREE.ConeGeometry(radius * 0.18, radius * 0.75, 5), material);
    marker.position.y = 0.42;
    marker.rotation.z = 0.18;
    g.add(marker);
    markers.add(g);
  }

  disableCosmeticRaycast(markers);
  group.add(markers);
}

function createMarkerMaterial(color, fallback) {
  if (color === undefined || color === null) return fallback;
  return new THREE.MeshStandardMaterial({
    color,
    emissive: color,
    emissiveIntensity: 0.85,
    roughness: 0.35,
    metalness: 0.5,
    transparent: true,
    opacity: 0.9
  });
}

function addHeliosDebrisField(group, visual, materials) {
  const field = visual.debrisField ?? {};
  const count = field.count ?? 96;
  const coreRadius = field.coreRadius ?? field.innerRadius ?? 10;
  const ringInnerRadius = visual.innerRadius ?? 23.5;
  const ringOuterRadius = visual.outerRadius ?? 45;
  const ringClearance = field.ringClearance ?? visual.debrisClearance ?? 2.4;
  const innerMin = coreRadius + ringClearance;
  const innerMax = ringInnerRadius - ringClearance;
  const outerMin = ringOuterRadius + ringClearance;
  const outerMax = field.outerRadius ?? 67;
  const innerSpan = Math.max(0, innerMax - innerMin);
  const outerSpan = Math.max(0, outerMax - outerMin);
  const random = seededRandom((visual.seed ?? 1) ^ 0x9e3779b9);
  const rocks = new THREE.Group();
  rocks.name = "helios-debris-field";

  for (let i = 0; i < count; i += 1) {
    const theta = random() * Math.PI * 2;
    const size = 0.22 + random() * 0.82;
    const useInnerPocket = innerSpan > 0 && (outerSpan <= 0 || random() < 0.36);
    const radius = useInnerPocket
      ? innerMin + Math.sqrt(random()) * innerSpan
      : outerMin + Math.sqrt(random()) * outerSpan;
    const rock = new THREE.Mesh(HELIOS_DEBRIS_GEOMETRY, materials.rock);
    rock.position.set(Math.cos(theta) * radius, -1.7 + random() * 3.4, Math.sin(theta) * radius);
    rock.scale.set(size * (0.75 + random() * 0.6), size * (0.55 + random() * 0.5), size * (0.72 + random() * 0.55));
    rock.rotation.set(random() * Math.PI, random() * Math.PI, random() * Math.PI);
    rocks.add(rock);

    if (i % 11 === 0) {
      const crystal = new THREE.Mesh(HELIOS_DEBRIS_CRYSTAL_GEOMETRY, materials.crystal);
      crystal.position.copy(rock.position);
      crystal.position.y += size * 0.55;
      crystal.scale.set(size * 0.22, size * 0.9, size * 0.22);
      crystal.rotation.z = (random() - 0.5) * 0.5;
      rocks.add(crystal);
    }
  }

  disableCosmeticRaycast(rocks);
  group.add(rocks);
}

function makeHeliosDebris(spec, visual, materials) {
  const g = new THREE.Group();
  g.name = `debris-${spec.id}`;
  const position = safeDebrisPosition(spec, visual);
  g.position.set(position.x, -0.55 + (spec.radius % 3) * 0.22, position.z);
  const rock = new THREE.Mesh(HELIOS_DEBRIS_GEOMETRY, materials.rock);
  rock.scale.set(spec.radius * 1.15, spec.radius * 0.72, spec.radius * 0.95);
  rock.rotation.set(spec.radius * 0.13, spec.radius * 0.61, spec.radius * 0.19);
  g.add(rock);
  if (spec.radius > 1.8) {
    const crystal = new THREE.Mesh(new THREE.ConeGeometry(0.3, 0.9, 5), materials.crystal);
    crystal.position.y = spec.radius * 0.65;
    g.add(crystal);
  }
  g.userData.visualStyle = "debris-rock";
  g.userData.safeDebrisPosition = position;
  disableCosmeticRaycast(g);
  return g;
}

function safeDebrisPosition(spec, visual) {
  const ringInnerRadius = visual.innerRadius ?? 23.5;
  const ringOuterRadius = visual.outerRadius ?? 45;
  const field = visual.debrisField ?? {};
  const coreRadius = field.coreRadius ?? field.innerRadius ?? 10;
  const clearance = Math.max(field.ringClearance ?? visual.debrisClearance ?? 2.4, spec.radius * 1.4);
  const currentRadius = Math.hypot(spec.center.x, spec.center.z);
  const innerMin = coreRadius + clearance;
  const innerMax = ringInnerRadius - clearance;
  const outerMin = ringOuterRadius + clearance;

  if (currentRadius >= innerMin && currentRadius <= innerMax) return { ...spec.center };

  let targetRadius = outerMin;
  if (currentRadius < innerMin && innerMax > innerMin) targetRadius = innerMin + Math.min(1.5, (innerMax - innerMin) * 0.35);
  const angle = currentRadius > 1e-6 ? Math.atan2(spec.center.z, spec.center.x) : seededRandom(hashString(spec.id))() * Math.PI * 2;
  return { x: Math.cos(angle) * targetRadius, z: Math.sin(angle) * targetRadius };
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
function makeBridge(spec, palette, enabled, visualMaterials = null) {
  if (spec.visual?.from && spec.visual?.to) {
    return makeHeliosBridge(spec, palette, enabled, visualMaterials);
  }

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
  g.userData.spec = spec;
  return g;
}

function makeHeliosBridge(spec, palette, enabled, visualMaterials = null) {
  const materials = visualMaterials ?? createHeliosMaterials({ ...palette, ...spec.visual?.palette });
  const from = spec.visual?.from ?? spec.from;
  const to = spec.visual?.to ?? spec.to;
  const dx = to.x - from.x;
  const dz = to.z - from.z;
  const len = Math.hypot(dx, dz);
  const midX = (from.x + to.x) * 0.5;
  const midZ = (from.z + to.z) * 0.5;
  const yaw = Math.atan2(dx, dz);
  const surfaceY = spec.visual?.surfaceY ?? 0.04;
  const bridgeWidth = spec.visual?.width ?? 3.8;
  const understructureWidth = spec.visual?.understructureWidth ?? bridgeWidth;
  const fullDeckWidth = spec.visual?.deckWidth ?? bridgeWidth * 0.82;
  const g = new THREE.Group();
  g.name = `bridge-${spec.id}`;
  g.position.set(midX, 0, midZ);
  g.rotation.y = yaw;

  // A disabled bridge must read as a broken crossing. Keep only terminal
  // understructure stubs until the bridge is enabled; enabled bridges remain
  // continuous below the deck.
  const underStubLength = Math.min(len * 0.26, spec.visual?.disabledStubLength ?? 4.8);
  const underSegments = enabled
    ? [{ center: 0, length: len }]
    : [
        { center: -len * 0.5 + underStubLength * 0.5, length: underStubLength },
        { center: len * 0.5 - underStubLength * 0.5, length: underStubLength }
      ];
  for (const segment of underSegments) {
    const under = new THREE.Mesh(
      new THREE.BoxGeometry(understructureWidth, 0.85, segment.length),
      materials.understructure
    );
    under.position.set(0, surfaceY - 0.5, segment.center);
    under.name = enabled ? "bridge-understructure" : "bridge-understructure-stub";
    g.add(under);
  }

  const enabledPieces = enabled ? 4 : 2;
  const gap = enabled ? Math.min(0.2, len * 0.04) : len * 0.2;
  const pieceLen = Math.max(0.35, (len - gap * (enabledPieces - 1)) / enabledPieces);
  const deckWidth = enabled ? fullDeckWidth : fullDeckWidth * 0.88;
  for (let i = 0; i < enabledPieces; i += 1) {
    const deck = new THREE.Mesh(
      new THREE.BoxGeometry(deckWidth, 0.12, pieceLen),
      enabled ? materials.deck : materials.basaltEdge
    );
    deck.position.z = -len * 0.5 + pieceLen * 0.5 + i * (pieceLen + gap);
    deck.position.y = surfaceY - 0.06;
    g.add(deck);
  }

  if (enabled) {
    const railOffset = Math.max(0.55, deckWidth * 0.5 - 0.12);
    for (const side of [-railOffset, railOffset]) {
      const rail = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.18, len * 0.88), materials.gold);
      rail.position.set(side, surfaceY + 0.12, 0);
      g.add(rail);
    }
    const conduit = new THREE.Mesh(new THREE.BoxGeometry(0.075, 0.08, len * 0.74), materials.conduit);
    conduit.position.y = surfaceY + 0.04;
    g.add(conduit);
  } else {
    const spark = new THREE.Mesh(new THREE.SphereGeometry(0.28, 8, 6), materials.conduitBright);
    spark.name = "bridge-spark";
    spark.position.y = surfaceY + 0.3;
    g.add(spark);
    for (const side of [-1, 1]) {
      const repairLight = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.1, 8), materials.goldBright);
      repairLight.position.set(0, surfaceY + 0.08, side * len * 0.22);
      g.add(repairLight);
    }
  }

  const socketRadius = Math.min(0.42, bridgeWidth * 0.12);
  const capRadius = Math.min(0.2, bridgeWidth * 0.056);
  for (const z of [-len * 0.5, len * 0.5]) {
    const socket = new THREE.Mesh(
      new THREE.CylinderGeometry(socketRadius, socketRadius * 1.14, 0.16, 10),
      materials.gold
    );
    socket.position.set(0, surfaceY + 0.06, z);
    g.add(socket);
    const cap = new THREE.Mesh(
      new THREE.CylinderGeometry(capRadius * 0.9, capRadius, 0.2, 8),
      materials.goldBright
    );
    cap.position.set(0, surfaceY + 0.19, z);
    g.add(cap);
  }

  g.userData.bridgeId = spec.id;
  g.userData.enabled = enabled;
  g.userData.spec = spec;
  g.userData.materials = materials;
  g.userData.understructureMode = enabled ? "continuous" : "terminal-stubs";
  disableCosmeticRaycast(g);
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
  const visualPalette = spec.visual?.palette ? { ...palette, ...spec.visual.palette } : palette;
  const rebuilt = makeBridge(spec, visualPalette, enabled, bridgeGroup.userData.materials ?? null);
  bridgeGroup.userData.spec = spec;
  bridgeGroup.userData.materials = rebuilt.userData.materials ?? bridgeGroup.userData.materials;
  bridgeGroup.userData.understructureMode = rebuilt.userData.understructureMode;
  while (rebuilt.children.length) {
    bridgeGroup.add(rebuilt.children[0]);
  }
}

function disableCosmeticRaycast(root) {
  root.traverse((object) => {
    if (!object.isMesh && !object.isLine && !object.isPoints) return;
    object.raycast = () => {};
    object.userData.cosmetic = true;
  });
  root.userData.cosmetic = true;
  return root;
}

function seededRandom(seed) {
  let value = (seed >>> 0) || 1;
  return () => {
    value = (value * 1664525 + 1013904223) >>> 0;
    return value / 0x100000000;
  };
}

function hashString(value) {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export { PALETTE as TERRAIN_PALETTE };
