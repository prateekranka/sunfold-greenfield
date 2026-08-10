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
const HELIOS_DEBRIS_ISLET_GEOMETRY = new THREE.IcosahedronGeometry(1, 1);
const HELIOS_DEBRIS_CRYSTAL_GEOMETRY = new THREE.ConeGeometry(1, 1, 5);
const HELIOS_DEBRIS_CRYSTAL_CLUSTER_GEOMETRY = new THREE.OctahedronGeometry(1, 0);
const HELIOS_SIDEWALL_BLOCK_GEOMETRY = makeHeliosMasonryBlockGeometry();
const HELIOS_SIDEWALL_RIB_GEOMETRY = new THREE.BoxGeometry(1, 1, 1);
const HELIOS_DECK_LIFE_PLANTER_GEOMETRY = new THREE.CylinderGeometry(0.42, 0.7, 0.3, 8);
const HELIOS_DECK_LIFE_STEM_GEOMETRY = new THREE.CylinderGeometry(0.03, 0.055, 1, 5);
const HELIOS_DECK_LIFE_LEAF_GEOMETRY = makeHeliosFabricLeafGeometry();
const HELIOS_DECK_LIFE_BUD_GEOMETRY = new THREE.OctahedronGeometry(0.14, 0);
const HELIOS_WINCH_BASE_GEOMETRY = new THREE.BoxGeometry(1.36, 0.22, 0.92);
const HELIOS_WINCH_YOKE_GEOMETRY = new THREE.BoxGeometry(0.15, 0.78, 0.2);
const HELIOS_WINCH_DRUM_GEOMETRY = new THREE.CylinderGeometry(0.27, 0.27, 0.82, 10);
const HELIOS_WINCH_COIL_GEOMETRY = new THREE.TorusGeometry(0.32, 0.055, 6, 12);
const HELIOS_WINCH_BRACE_GEOMETRY = new THREE.BoxGeometry(1.18, 0.1, 0.18);

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
  const visualMaterials = visual ? createHeliosMaterials(visualPalette, visual.seed ?? 2749) : null;

  // Helios uses a deterministic presentation path. Other maps retain the
  // original low-cost starfield and platform rendering below.
  if (visual) {
    addHeliosNebulaBackdrop(group, visual, visualMaterials);
    addHeliosStarfield(group, visual, visualPalette, visualMaterials);
  }
  else addLegacyStarfield(group);

  for (const p of terrain.platforms) {
    const mesh = visual
      ? makeHeliosPlatform(p, visual, visualPalette, visualMaterials)
      : makePlatform(p, palette);
    platformMeshes.set(p.id, mesh);
    group.add(mesh);
  }

  if (visual) {
    addHeliosDeckLife(group, visual, visualMaterials);
    addHeliosMaintenanceMechanisms(group, visual, visualMaterials);
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
function createHeliosMaterials(palette, seed = 2749) {
  const metal = (color, roughness, metalness = 0.8, extra = {}) =>
    new THREE.MeshStandardMaterial({ color, roughness, metalness, ...extra });
  const glow = (color, intensity = 1.1, opacity = 1, metalness = 0.3, roughness = 0.28) =>
    new THREE.MeshStandardMaterial({
      color,
      emissive: color,
      emissiveIntensity: intensity,
      roughness,
      metalness,
      transparent: opacity < 1,
      opacity
    });

  // One small deterministic field texture drives every Broken Ring terrain
  // material in world space. This keeps the surface continuous across sectors
  // and avoids the per-pixel cost of evaluating several noise octaves on iPad.
  const terrainField = makeHeliosTerrainFieldTexture(seed);
  const terrainDeck = makeHeliosTerrainMaterial(terrainField, {
    variant: "sunworn-deck",
    shadow: palette.terrainShadow ?? 0x2d2f31,
    warm: palette.terrainWarm ?? 0x55534f,
    sunlit: palette.terrainSunlit ?? 0x817c70,
    cool: palette.terrainCool ?? 0x33464d,
    roughness: 0.86,
    metalness: 0.12,
    bumpStrength: 0.42
  });
  const terrainArmor = makeHeliosTerrainMaterial(terrainField, {
    variant: "gravity-weathered-armor",
    shadow: palette.terrainArmorShadow ?? 0x191e23,
    warm: palette.terrainArmorWarm ?? 0x31363a,
    sunlit: palette.terrainArmorSunlit ?? 0x515457,
    cool: palette.terrainArmorCool ?? 0x243940,
    roughness: 0.92,
    metalness: 0.16,
    bumpStrength: 0.48
  });
  const sidewallMasonry = metal(0xffffff, 0.82, 0.26, { flatShading: true });
  sidewallMasonry.name = "helios-sidewall-masonry";
  sidewallMasonry.userData.instancePalette = [
    palette.sidewallShadow ?? 0x181b1d,
    palette.sidewallMid ?? 0x302f2c,
    palette.sidewallWarm ?? 0x4b3c2e,
    palette.sidewallCool ?? 0x203036
  ];
  const sidewallSolarMasonry = metal(0xffffff, 0.8, 0.24, {
    flatShading: true,
    emissive: palette.solarBounce ?? 0x5a2108,
    emissiveIntensity: Math.min(palette.solarBounceIntensity ?? 0.24, 0.5)
  });
  sidewallSolarMasonry.name = "helios-sidewall-solar-masonry";
  sidewallSolarMasonry.userData.instancePalette = [
    palette.sidewallSolarShadow ?? 0x2a211c,
    palette.sidewallSolarMid ?? 0x443126,
    palette.sidewallSolarWarm ?? 0x62452d,
    palette.sidewallSolarCool ?? 0x354044
  ];
  const nebulaTexture = makeHeliosNebulaTexture(seed ^ 0x51ed270b, palette);

  return {
    understructure: metal(palette.understructure ?? 0x0b1017, 0.68, 0.72),
    sidewallMasonry,
    sidewallSolarMasonry,
    sidewallShadow: metal(palette.sidewallContactShadow ?? 0x080b0e, 0.96, 0.08),
    sidewallRib: metal(palette.sidewallRib ?? 0x98602f, 0.52, 0.68, {
      emissive: palette.sidewallRibEmissive ?? 0x2c1508,
      emissiveIntensity: 0.1
    }),
    basalt: terrainArmor,
    basaltEdge: terrainArmor,
    deckShadow: terrainDeck,
    deck: terrainDeck,
    // All deck cells share one world-space material. Geometry and seams remain,
    // but the old alternating light/dark striping no longer defines the land.
    deckLight: terrainDeck,
    seam: metal(palette.seam ?? 0x252d36, 0.9, 0.18),
    gold: glow(palette.gold ?? 0xe9a749, 0.95, 1, 0.82, 0.3),
    goldBright: glow(palette.goldBright ?? 0xffcf72, 1.55, 1, 0.74, 0.22),
    conduit: glow(palette.conduit ?? 0x35d8ce, 1.15, 0.86, 0.18, 0.2),
    conduitBright: glow(palette.conduitBright ?? 0x83fff1, 1.75, 1, 0.12, 0.16),
    spawn: glow(palette.spawn ?? 0x328dff, 1.2, 0.88, 0.18, 0.2),
    resource: glow(palette.resource ?? 0x3ed9b5, 1.2, 0.9, 0.16, 0.22),
    crystal: glow(palette.crystal ?? 0x1ca7a8, 0.92, 1, 0.12, 0.2),
    crystalBright: glow(palette.crystalBright ?? 0x59ddd3, 1.32, 1, 0.08, 0.16),
    deckLifePlanter: metal(palette.deckLifePlanter ?? 0x433f38, 0.88, 0.22, {
      flatShading: true
    }),
    deckLifeStem: metal(palette.deckLifeStem ?? 0x3f684e, 0.9, 0.04, {
      flatShading: true
    }),
    deckLifeLeaf: metal(palette.deckLifeLeaf ?? 0x78a35f, 0.82, 0.03, {
      flatShading: true,
      side: THREE.DoubleSide
    }),
    deckLifeBud: glow(palette.deckLifeBud ?? 0x45c99a, 0.46, 1, 0.06, 0.38),
    rock: metal(palette.rock ?? 0x303437, 0.94, 0.1, { flatShading: true }),
    rockWarm: metal(palette.rockWarm ?? 0x55504a, 0.9, 0.08, { flatShading: true }),
    nebula: new THREE.MeshBasicMaterial({
      map: nebulaTexture,
      color: 0xffffff,
      depthTest: false,
      depthWrite: false,
      fog: false,
      toneMapped: false,
      side: THREE.BackSide
    }),
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

function makeHeliosMasonryBlockGeometry() {
  const shape = new THREE.Shape();
  const corner = 0.1;
  shape.moveTo(-0.5 + corner, -0.5);
  shape.lineTo(0.5 - corner, -0.5);
  shape.lineTo(0.5, -0.5 + corner);
  shape.lineTo(0.5, 0.5 - corner);
  shape.lineTo(0.5 - corner, 0.5);
  shape.lineTo(-0.5 + corner, 0.5);
  shape.lineTo(-0.5, 0.5 - corner);
  shape.lineTo(-0.5, -0.5 + corner);
  shape.closePath();
  const geometry = new THREE.ExtrudeGeometry(shape, {
    depth: 0.82,
    bevelEnabled: true,
    bevelSegments: 1,
    bevelSize: 0.045,
    bevelThickness: 0.045,
    curveSegments: 1
  });
  geometry.center();
  geometry.computeVertexNormals();
  return geometry;
}

function makeHeliosFabricLeafGeometry() {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute(
    "position",
    new THREE.Float32BufferAttribute(
      [
        0, -0.5, 0,
        -0.28, -0.1, 0,
        -0.18, 0.22, 0.05,
        0, 0.55, 0.09,
        0.18, 0.22, -0.05,
        0.28, -0.1, 0
      ],
      3
    )
  );
  geometry.setIndex([0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5]);
  geometry.computeVertexNormals();
  return geometry;
}

function makeHeliosTerrainFieldTexture(seed, size = 256) {
  const data = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y += 1) {
    const v = y / size;
    for (let x = 0; x < size; x += 1) {
      const u = x / size;
      const broad = periodicFbm(u, v, 3, 4, seed);
      const warpX = periodicFbm(u + 0.19, v - 0.11, 5, 3, seed ^ 0x632be59b) - 0.5;
      const warpY = periodicFbm(u - 0.07, v + 0.23, 5, 3, seed ^ 0x85157af5) - 0.5;
      const weather = periodicWeatheredFbm(
        u + warpX * 0.12,
        v + warpY * 0.12,
        7,
        4,
        seed ^ 0x9e3779b9
      );
      const ridgeSource = periodicFbm(u + warpY * 0.08, v - warpX * 0.08, 11, 3, seed ^ 0x68bc21eb);
      const ridge = 1 - Math.abs(ridgeSource * 2 - 1);
      const cellular = periodicCellularNoise(
        u + warpY * 0.04,
        v - warpX * 0.04,
        19,
        seed ^ 0x27d4eb2d
      );
      const grain = THREE.MathUtils.clamp(
        periodicValueNoise(u, v, 41, seed ^ 0x165667b1) * 0.62 + (1 - cellular) * 0.38,
        0,
        1
      );
      const index = (y * size + x) * 4;
      data[index] = Math.round(THREE.MathUtils.clamp(broad, 0, 1) * 255);
      data[index + 1] = Math.round(THREE.MathUtils.clamp(weather, 0, 1) * 255);
      data[index + 2] = Math.round(THREE.MathUtils.clamp(ridge, 0, 1) * 255);
      data[index + 3] = Math.round(THREE.MathUtils.clamp(grain, 0, 1) * 255);
    }
  }

  const texture = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  texture.name = "helios-world-terrain-field";
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.magFilter = THREE.LinearFilter;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  texture.generateMipmaps = true;
  texture.colorSpace = THREE.NoColorSpace;
  texture.anisotropy = 4;
  texture.needsUpdate = true;
  texture.userData = {
    seed,
    size,
    channels: ["broad-fbm", "weathered-fbm", "ridged-fbm", "cellular-grain"],
    sourceTechnique: "weathered-fbm-ridged-cellular"
  };
  return texture;
}

function makeHeliosNebulaTexture(seed, palette, size = 256) {
  const data = new Uint8Array(size * size * 4);
  const shadow = hexRgb(palette.nebulaShadow ?? 0x01040b);
  const blue = hexRgb(palette.nebulaBlue ?? 0x0b2346);
  const violet = hexRgb(palette.nebulaViolet ?? 0x261b3f);
  const teal = hexRgb(palette.nebulaTeal ?? 0x0b3544);

  for (let y = 0; y < size; y += 1) {
    const v = y / size;
    for (let x = 0; x < size; x += 1) {
      const u = x / size;
      const warpX = periodicFbm(u + 0.17, v - 0.23, 2, 4, seed) - 0.5;
      const warpY = periodicFbm(u - 0.29, v + 0.13, 3, 4, seed ^ 0x68bc21eb) - 0.5;
      const broad = periodicFbm(
        u + warpX * 0.18,
        v + warpY * 0.18,
        2,
        5,
        seed ^ 0x9e3779b9
      );
      const weather = periodicFbm(
        u - warpY * 0.12,
        v + warpX * 0.12,
        5,
        4,
        seed ^ 0x7f4a7c15
      );
      const ridgeSource = periodicFbm(
        u + warpX * 0.08,
        v - warpY * 0.08,
        9,
        3,
        seed ^ 0x2c9277b5
      );
      const ridge = 1 - Math.abs(ridgeSource * 2 - 1);
      const distanceFromCenter = Math.hypot(u - 0.5, v - 0.5);
      const outerWeight = 0.55 + smoothstepRange(0.1, 0.5, distanceFromCenter) * 0.45;
      const cloud = smoothstepRange(0.47, 0.6, broad * 0.55 + weather * 0.45) * outerWeight;
      const violetCloud = smoothstepRange(0.52, 0.69, weather) * outerWeight * 0.78;
      const filament = smoothstepRange(0.58, 0.8, ridge) * outerWeight * 0.46;
      const darkLane = smoothstepRange(0.48, 0.72, 1 - ridge) * 0.5;

      let red = mixByte(shadow[0], blue[0], cloud * 0.78);
      let green = mixByte(shadow[1], blue[1], cloud * 0.78);
      let blueChannel = mixByte(shadow[2], blue[2], cloud * 0.78);
      red = mixByte(red, violet[0], violetCloud);
      green = mixByte(green, violet[1], violetCloud);
      blueChannel = mixByte(blueChannel, violet[2], violetCloud);
      red = mixByte(red, teal[0], filament);
      green = mixByte(green, teal[1], filament);
      blueChannel = mixByte(blueChannel, teal[2], filament);
      const darken = 1 - darkLane;
      const index = (y * size + x) * 4;
      data[index] = Math.round(red * darken);
      data[index + 1] = Math.round(green * darken);
      data[index + 2] = Math.round(blueChannel * darken);
      data[index + 3] = 255;
    }
  }

  const texture = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  texture.name = "helios-nebula-field";
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(3.2, 1.8);
  texture.offset.set(0.13, 0.07);
  texture.magFilter = THREE.LinearFilter;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  texture.generateMipmaps = true;
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.needsUpdate = true;
  texture.userData = { seed, size, style: "warped-fbm-ridged-nebula" };
  return texture;
}

function hexRgb(value) {
  return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

function mixByte(from, to, amount) {
  return THREE.MathUtils.lerp(from, to, THREE.MathUtils.clamp(amount, 0, 1));
}

function smoothstepRange(minimum, maximum, value) {
  const t = THREE.MathUtils.clamp((value - minimum) / Math.max(0.0001, maximum - minimum), 0, 1);
  return t * t * (3 - 2 * t);
}

function makeHeliosTerrainMaterial(fieldTexture, options) {
  const material = new THREE.MeshStandardMaterial({
    color: 0xffffff,
    roughness: options.roughness,
    metalness: options.metalness
  });
  const colors = {
    shadow: new THREE.Color(options.shadow),
    warm: new THREE.Color(options.warm),
    sunlit: new THREE.Color(options.sunlit),
    cool: new THREE.Color(options.cool)
  };

  material.name = `helios-terrain-${options.variant}`;
  material.userData.sunfoldTerrainSurface = {
    version: 2,
    variant: options.variant,
    fieldTexture: fieldTexture.name,
    fieldTextureSize: fieldTexture.image.width,
    mapping: "world-xz",
    fieldModel: fieldTexture.userData.sourceTechnique,
    colorBlend: "continuous-multiscale",
    hardColorBands: false,
    geometryDisplacement: false,
    bumpStrength: options.bumpStrength
  };
  material.customProgramCacheKey = () => `sunfold-helios-terrain-v2-${options.variant}`;
  material.onBeforeCompile = (shader) => {
    shader.uniforms.sunfoldTerrainField = { value: fieldTexture };
    shader.uniforms.sunfoldTerrainShadow = { value: colors.shadow };
    shader.uniforms.sunfoldTerrainWarm = { value: colors.warm };
    shader.uniforms.sunfoldTerrainSunlit = { value: colors.sunlit };
    shader.uniforms.sunfoldTerrainCool = { value: colors.cool };
    shader.uniforms.sunfoldTerrainRoughness = { value: options.roughness };
    shader.uniforms.sunfoldTerrainMetalness = { value: options.metalness };
    shader.uniforms.sunfoldTerrainBumpStrength = { value: options.bumpStrength };

    shader.vertexShader = replaceShaderChunk(
      shader.vertexShader,
      "#include <common>",
      `#include <common>
varying vec3 vSunfoldTerrainWorldPosition;
varying vec3 vSunfoldTerrainWorldNormal;`
    );
    shader.vertexShader = replaceShaderChunk(
      shader.vertexShader,
      "#include <normal_vertex>",
      `#include <normal_vertex>
vSunfoldTerrainWorldNormal = normalize(inverseTransformDirection(transformedNormal, viewMatrix));`
    );
    shader.vertexShader = replaceShaderChunk(
      shader.vertexShader,
      "#include <project_vertex>",
      `vec4 sunfoldTerrainWorldPosition = vec4(transformed, 1.0);
#ifdef USE_BATCHING
  sunfoldTerrainWorldPosition = batchingMatrix * sunfoldTerrainWorldPosition;
#endif
#ifdef USE_INSTANCING
  sunfoldTerrainWorldPosition = instanceMatrix * sunfoldTerrainWorldPosition;
#endif
vSunfoldTerrainWorldPosition = (modelMatrix * sunfoldTerrainWorldPosition).xyz;
#include <project_vertex>`
    );

    shader.fragmentShader = replaceShaderChunk(
      shader.fragmentShader,
      "#include <common>",
      `#include <common>
varying vec3 vSunfoldTerrainWorldPosition;
varying vec3 vSunfoldTerrainWorldNormal;
uniform sampler2D sunfoldTerrainField;
uniform vec3 sunfoldTerrainShadow;
uniform vec3 sunfoldTerrainWarm;
uniform vec3 sunfoldTerrainSunlit;
uniform vec3 sunfoldTerrainCool;
uniform float sunfoldTerrainRoughness;
uniform float sunfoldTerrainMetalness;
uniform float sunfoldTerrainBumpStrength;

vec3 sunfoldPerturbTerrainNormal(
  vec3 surfacePosition,
  vec3 surfaceNormal,
  float terrainHeight,
  float strength,
  float direction
) {
  vec2 heightDerivative = vec2(dFdx(terrainHeight), dFdy(terrainHeight));
  vec3 sigmaX = dFdx(surfacePosition);
  vec3 sigmaY = dFdy(surfacePosition);
  vec3 r1 = cross(sigmaY, surfaceNormal);
  vec3 r2 = cross(surfaceNormal, sigmaX);
  float determinant = dot(sigmaX, r1) * direction;
  vec3 gradient = sign(determinant) * (heightDerivative.x * r1 + heightDerivative.y * r2);
  return normalize(abs(determinant) * surfaceNormal - strength * gradient);
}`
    );
    shader.fragmentShader = replaceShaderChunk(
      shader.fragmentShader,
      "#include <map_fragment>",
      `#include <map_fragment>
vec2 sunfoldTerrainBroadUv = vSunfoldTerrainWorldPosition.xz * 0.0155;
mat2 sunfoldTerrainRotation = mat2(0.8192, -0.5736, 0.5736, 0.8192);
vec2 sunfoldTerrainDetailUv = sunfoldTerrainRotation * vSunfoldTerrainWorldPosition.xz * 0.078;
vec4 sunfoldTerrainBroad = texture2D(sunfoldTerrainField, sunfoldTerrainBroadUv);
vec4 sunfoldTerrainDetail = texture2D(sunfoldTerrainField, sunfoldTerrainDetailUv);
vec4 sunfoldTerrainMicro = texture2D(
  sunfoldTerrainField,
  sunfoldTerrainDetailUv * 2.37 + vec2(0.173, 0.419)
);
float sunfoldTerrainSlope = smoothstep(
  0.08,
  0.86,
  1.0 - abs(normalize(vSunfoldTerrainWorldNormal).y)
);
float sunfoldTerrainWeather = mix(sunfoldTerrainBroad.g, sunfoldTerrainDetail.g, 0.62);
float sunfoldTerrainRidge = mix(sunfoldTerrainBroad.b, sunfoldTerrainDetail.b, 0.58);
float sunfoldTerrainGrain = mix(sunfoldTerrainDetail.a, sunfoldTerrainMicro.a, 0.52);
float sunfoldTerrainHeight =
  sunfoldTerrainBroad.r * 0.13 +
  sunfoldTerrainWeather * 0.31 +
  sunfoldTerrainRidge * 0.24 +
  sunfoldTerrainGrain * 0.17 +
  sunfoldTerrainMicro.b * 0.15;
vec2 sunfoldTerrainHeightDerivative = vec2(
  dFdx(sunfoldTerrainHeight),
  dFdy(sunfoldTerrainHeight)
);
float sunfoldTerrainRelief = clamp(length(sunfoldTerrainHeightDerivative) * 9.0, 0.0, 1.0);
float sunfoldTerrainBase = clamp(
  0.48 +
  (sunfoldTerrainBroad.r - 0.5) * 0.34 +
  (sunfoldTerrainWeather - 0.5) * 0.18,
  0.16,
  0.78
);
vec3 sunfoldTerrainColor = mix(
  sunfoldTerrainShadow,
  sunfoldTerrainWarm,
  sunfoldTerrainBase
);
float sunfoldTerrainExposure = smoothstep(
  0.57,
  0.86,
  sunfoldTerrainWeather * 0.66 + sunfoldTerrainGrain * 0.34
);
sunfoldTerrainColor = mix(
  sunfoldTerrainColor,
  sunfoldTerrainSunlit,
  sunfoldTerrainExposure * 0.28 * (1.0 - sunfoldTerrainSlope * 0.72)
);
float sunfoldGravityWear = clamp(
  sunfoldTerrainSlope * 0.62 +
  smoothstep(0.70, 0.96, sunfoldTerrainRidge) * 0.21 +
  sunfoldTerrainRelief * 0.16,
  0.0,
  0.76
);
sunfoldTerrainColor = mix(sunfoldTerrainColor, sunfoldTerrainCool, sunfoldGravityWear);
sunfoldTerrainColor *= 0.965 + (sunfoldTerrainGrain - 0.5) * 0.10;
diffuseColor.rgb = sunfoldTerrainColor;`
    );
    shader.fragmentShader = replaceShaderChunk(
      shader.fragmentShader,
      "#include <roughnessmap_fragment>",
      `#include <roughnessmap_fragment>
roughnessFactor = clamp(
  sunfoldTerrainRoughness +
  (sunfoldTerrainWeather - 0.5) * 0.08 +
  sunfoldTerrainSlope * 0.05 +
  sunfoldTerrainRelief * 0.035,
  0.58,
  0.98
);`
    );
    shader.fragmentShader = replaceShaderChunk(
      shader.fragmentShader,
      "#include <metalnessmap_fragment>",
      `#include <metalnessmap_fragment>
metalnessFactor = clamp(
  sunfoldTerrainMetalness + sunfoldTerrainRidge * 0.035 - sunfoldTerrainSlope * 0.025,
  0.04,
  0.24
);`
    );
    shader.fragmentShader = replaceShaderChunk(
      shader.fragmentShader,
      "#include <normal_fragment_maps>",
      `#include <normal_fragment_maps>
normal = sunfoldPerturbTerrainNormal(
  -vViewPosition,
  normal,
  sunfoldTerrainHeight,
  sunfoldTerrainBumpStrength,
  faceDirection
);`
    );
  };
  return material;
}

function addHeliosNebulaBackdrop(group, visual, materials) {
  const backdrop = visual.nebulaBackdrop ?? {};
  if (backdrop.enabled === false) return;
  const radius = backdrop.radius ?? 200;
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(radius, 32, 16), materials.nebula);
  mesh.name = "helios-nebula-backdrop";
  mesh.rotation.y = backdrop.rotation ?? 0;
  mesh.renderOrder = -1000;
  mesh.frustumCulled = false;
  mesh.onBeforeRender = (_renderer, _scene, camera) => {
    mesh.position.copy(camera.position);
  };
  mesh.userData.visualStyle = "procedural-nebula-backdrop";
  mesh.userData.visualDetail = {
    texture: materials.nebula.map?.name ?? null,
    textureSize: materials.nebula.map?.image?.width ?? null,
    projection: "camera-centered-sphere",
    drawGroups: 1,
    createsWalkableGround: false
  };
  disableCosmeticRaycast(mesh);
  group.add(mesh);
}

function replaceShaderChunk(source, marker, replacement) {
  if (!source.includes(marker)) {
    throw new Error(`Helios terrain shader marker missing: ${marker}`);
  }
  return source.replace(marker, replacement);
}

function periodicFbm(u, v, baseCells, octaves, seed) {
  let value = 0;
  let amplitude = 0.5;
  let normalization = 0;
  let cells = baseCells;
  for (let octave = 0; octave < octaves; octave += 1) {
    value += periodicValueNoise(u, v, cells, seed + octave * 0x9e3779b9) * amplitude;
    normalization += amplitude;
    amplitude *= 0.5;
    cells *= 2;
  }
  return value / Math.max(0.0001, normalization);
}

function periodicWeatheredFbm(u, v, baseCells, octaves, seed) {
  let value = 0;
  let amplitude = 0.5;
  let normalization = 0;
  let cells = baseCells;
  let derivativeX = 0;
  let derivativeY = 0;

  for (let octave = 0; octave < octaves; octave += 1) {
    const octaveSeed = seed + octave * 0x9e3779b9;
    const step = 0.35 / cells;
    const sample = periodicValueNoise(u, v, cells, octaveSeed) - 0.5;
    derivativeX += (
      periodicValueNoise(u + step, v, cells, octaveSeed) -
      periodicValueNoise(u - step, v, cells, octaveSeed)
    ) * amplitude;
    derivativeY += (
      periodicValueNoise(u, v + step, cells, octaveSeed) -
      periodicValueNoise(u, v - step, cells, octaveSeed)
    ) * amplitude;
    const erosion = 1 + (derivativeX * derivativeX + derivativeY * derivativeY) * 5.5;
    value += (sample * amplitude) / erosion;
    normalization += amplitude;
    amplitude *= 0.5;
    cells *= 2;
  }

  return THREE.MathUtils.clamp(0.5 + (value / Math.max(0.0001, normalization)) * 1.5, 0, 1);
}

function periodicCellularNoise(u, v, cells, seed) {
  const x = wrap01(u) * cells;
  const y = wrap01(v) * cells;
  const cellX = Math.floor(x);
  const cellY = Math.floor(y);
  const localX = x - cellX;
  const localY = y - cellY;
  let nearest = Number.POSITIVE_INFINITY;

  for (let offsetY = -1; offsetY <= 1; offsetY += 1) {
    for (let offsetX = -1; offsetX <= 1; offsetX += 1) {
      const wrappedX = ((cellX + offsetX) % cells + cells) % cells;
      const wrappedY = ((cellY + offsetY) % cells + cells) % cells;
      const pointX = terrainHash(wrappedX, wrappedY, seed);
      const pointY = terrainHash(wrappedX, wrappedY, seed ^ 0x68bc21eb);
      const dx = offsetX + pointX - localX;
      const dy = offsetY + pointY - localY;
      nearest = Math.min(nearest, Math.hypot(dx, dy));
    }
  }

  return THREE.MathUtils.clamp(nearest / 0.78, 0, 1);
}

function periodicValueNoise(u, v, cells, seed) {
  const x = wrap01(u) * cells;
  const y = wrap01(v) * cells;
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = smoothInterpolation(x - x0);
  const ty = smoothInterpolation(y - y0);
  const x1 = (x0 + 1) % cells;
  const y1 = (y0 + 1) % cells;
  const ix0 = ((x0 % cells) + cells) % cells;
  const iy0 = ((y0 % cells) + cells) % cells;
  const a = terrainHash(ix0, iy0, seed);
  const b = terrainHash(x1, iy0, seed);
  const c = terrainHash(ix0, y1, seed);
  const d = terrainHash(x1, y1, seed);
  return THREE.MathUtils.lerp(
    THREE.MathUtils.lerp(a, b, tx),
    THREE.MathUtils.lerp(c, d, tx),
    ty
  );
}

function terrainHash(x, y, seed) {
  let value = (x * 0x1f123bb5) ^ (y * 0x5f356495) ^ seed;
  value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
  value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
  value ^= value >>> 16;
  return (value >>> 0) / 0xffffffff;
}

function smoothInterpolation(value) {
  return value * value * (3 - 2 * value);
}

function wrap01(value) {
  return value - Math.floor(value);
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
  const armorBlockCount = visual.armorBlockCount ?? panelCount * 2 + 1;
  const sidewallTierCount = visual.sidewallTierCount ?? 3;
  const sidewallBlockCount = visual.sidewallBlockCount ?? armorBlockCount;
  const sidewallRibCount = visual.sidewallRibCount ?? 5;
  const terminalTierCount = visual.terminalTierCount ?? 3;
  const terminalBlockCount = visual.terminalBlockCount ?? 6;
  const terminalRibCount = visual.terminalRibCount ?? 4;
  const armorBandWidth = visual.armorBandWidth ?? 1.5;
  const wallJitter = visual.wallJitter ?? 0.48;
  const crackCount = visual.cracksPerFragment ?? panelCount;
  const conduitCount = visual.conduitCount ?? 4;
  const surfaceY = visual.surfaceY ?? 0.04;
  const start = -span / 2 + 0.035;
  const end = span / 2 - 0.035;
  const midRadius = (inner + outer) * 0.5;

  const fragmentSeed = (visual.seed ?? 1) + hashString(spec.id);
  const random = seededRandom(fragmentSeed);

  const under = new THREE.Mesh(
    makeJaggedAnnularSectorGeometry(
      inner - 0.16,
      outer + 0.22,
      span,
      underDepth,
      24,
      fragmentSeed,
      wallJitter * 0.72,
      wallJitter
    ),
    materials.understructure
  );
  under.position.y = surfaceY - underDepth * 0.5 - 0.18;
  g.add(under);

  const armorDepth = 0.42;
  const armor = new THREE.Mesh(
    makeAnnularSectorGeometry(inner + 0.1, outer - 0.1, span - 0.025, armorDepth, 24),
    materials.basaltEdge
  );
  armor.position.y = surfaceY - armorDepth * 0.5 - 0.08;
  g.add(armor);

  const outerArmor = new THREE.Mesh(
    makeJaggedAnnularSectorGeometry(
      outer - armorBandWidth,
      outer + 0.18,
      span - 0.018,
      0.62,
      18,
      fragmentSeed ^ 0x4f1bbcdc,
      wallJitter * 0.2,
      wallJitter * 0.48
    ),
    materials.basalt
  );
  outerArmor.position.y = surfaceY - 0.2;
  g.add(outerArmor);

  const innerArmor = new THREE.Mesh(
    makeJaggedAnnularSectorGeometry(
      inner - 0.18,
      inner + armorBandWidth,
      span - 0.018,
      0.58,
      18,
      fragmentSeed ^ 0x7f4a7c15,
      wallJitter * 0.42,
      wallJitter * 0.18
    ),
    materials.basalt
  );
  innerArmor.position.y = surfaceY - 0.18;
  g.add(innerArmor);

  const outerCrown = new THREE.Mesh(
    makeJaggedAnnularSectorGeometry(
      outer - armorBandWidth * 0.62,
      outer - 0.12,
      span - 0.035,
      0.24,
      18,
      fragmentSeed ^ 0x2c9277b5,
      0.08,
      wallJitter * 0.22
    ),
    materials.basaltEdge
  );
  outerCrown.position.y = surfaceY + 0.06;
  g.add(outerCrown);

  const innerCrown = new THREE.Mesh(
    makeJaggedAnnularSectorGeometry(
      inner + 0.12,
      inner + armorBandWidth * 0.62,
      span - 0.035,
      0.22,
      18,
      fragmentSeed ^ 0x165667b1,
      wallJitter * 0.2,
      0.08
    ),
    materials.basaltEdge
  );
  innerCrown.position.y = surfaceY + 0.05;
  g.add(innerCrown);

  const outerGoldRail = new THREE.Mesh(
    makeAnnularSectorGeometry(outer - 0.28, outer - 0.1, span - 0.045, 0.07, 24),
    materials.gold
  );
  outerGoldRail.position.y = surfaceY + 0.225;
  g.add(outerGoldRail);

  const innerGoldRail = new THREE.Mesh(
    makeAnnularSectorGeometry(inner + 0.1, inner + 0.28, span - 0.045, 0.07, 24),
    materials.gold
  );
  innerGoldRail.position.y = surfaceY + 0.215;
  g.add(innerGoldRail);

  const deckInset = visual.deckInset ?? 0.78;
  const deckDepth = 0.14;
  const deck = new THREE.Mesh(
    makeAnnularSectorGeometry(inner + deckInset, outer - deckInset, span - 0.04, deckDepth, 30),
    materials.deckShadow
  );
  deck.position.y = surfaceY - deckDepth * 0.5;
  g.add(deck);

  addHeliosDeckCracks(
    g,
    inner + deckInset + 0.5,
    outer - deckInset - 0.5,
    start,
    end,
    crackCount,
    materials.seamLine,
    surfaceY + 0.09,
    random
  );

  addArcLine(g, outer - 0.2, start, end, surfaceY + 0.27, materials.goldLine, 24);
  addArcLine(g, inner + 0.2, start, end, surfaceY + 0.26, materials.goldLine, 24);
  addArcLine(g, midRadius, start + 0.04, end - 0.04, surfaceY + 0.1, materials.seamLine, 24);

  for (let i = 0; i <= panelCount; i += 1) {
    const a = THREE.MathUtils.lerp(start, end, i / panelCount);
    if (i > 0 && i < panelCount && i % 2 === 0) {
      const lightY = surfaceY - underDepth * 0.42;
      addEdgeRib(g, outer - 0.58, a, 0.12, underDepth * 0.32, materials.gold, lightY);
      addEdgeRib(g, inner + 0.58, a, 0.12, underDepth * 0.32, materials.gold, lightY);
    }
  }

  // Three hairline structural inlays retain an authored spacecraft rhythm
  // without dividing the terrain into alternating deck strips.
  const terrainSeamCount = 3;
  for (let i = 1; i <= terrainSeamCount; i += 1) {
    const a = THREE.MathUtils.lerp(start, end, i / (terrainSeamCount + 1));
    addRadialBar(
      g,
      a,
      inner + deckInset + 0.34,
      outer - deckInset - 0.34,
      0.032,
      0.018,
      materials.seam,
      surfaceY + 0.035
    );
  }

  addHeliosArmorBlocks(
    g,
    inner,
    outer,
    start,
    end,
    armorBlockCount,
    underDepth,
    materials.basaltEdge,
    surfaceY,
    random
  );

  const sidewallDetail = addHeliosSidewallArchitecture(
    g,
    inner,
    outer,
    start,
    end,
    underDepth,
    sidewallTierCount,
    sidewallBlockCount,
    sidewallRibCount,
    materials,
    surfaceY,
    random
  );
  const terminalDetail = addHeliosTerminalArchitecture(
    g,
    inner,
    outer,
    start,
    end,
    underDepth,
    terminalTierCount,
    terminalBlockCount,
    terminalRibCount,
    materials,
    surfaceY,
    seededRandom(fragmentSeed ^ 0x3c6ef372)
  );

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

  for (const a of [start, end]) addHeliosEndAssembly(g, inner, outer, a, materials, surfaceY);

  g.userData.visualStyle = "broken-ring-fragment";
  g.userData.visualDetail = {
    armorBlocks: armorBlockCount * 2,
    deckPanels: 0,
    deckCracks: crackCount,
    layeredArmorBands: 4,
    sidewallTiers: sidewallDetail.tiers,
    sidewallBlocks: sidewallDetail.blocks,
    sidewallRibs: sidewallDetail.ribs,
    sidewallRibBrackets: sidewallDetail.ribBrackets,
    contactShadowBands: sidewallDetail.contactShadowBands,
    sidewallDrawGroups: sidewallDetail.drawGroups,
    terminalTiers: terminalDetail.tiers,
    terminalBlocks: terminalDetail.blocks,
    terminalRibs: terminalDetail.ribs,
    terminalRibBrackets: terminalDetail.ribBrackets,
    terminalDrawGroups: terminalDetail.drawGroups,
    solarBounceInnerBlocks: sidewallDetail.solarBounceBlocks,
    solarBounceTerminalBlocks: terminalDetail.solarBounceBlocks,
    materialDrivenSolarBounce: true,
    terrainSeams: terrainSeamCount,
    materialDrivenSurface: true
  };
  g.userData.platformSpec = spec;
  return g;
}

function addHeliosDeckLife(group, visual, materials) {
  const requested = visual.deckLife?.clusters ?? [];
  if (requested.length === 0) return null;

  const deckLife = new THREE.Group();
  deckLife.name = "helios-deck-life";
  const planterMatrices = [];
  const stemMatrices = [];
  const leafMatrices = [];
  const budMatrices = [];
  const dummy = new THREE.Object3D();
  const surfaceY = visual.surfaceY ?? 0;

  for (const cluster of requested) {
    const fragment = visual.fragments?.find((entry) => entry.id === cluster.fragmentId);
    if (!fragment) continue;
    const worldAngle = (fragment.centerAngle ?? 0) + (cluster.angleOffset ?? 0);
    const radius = cluster.radius ?? (visual.innerRadius + visual.outerRadius) * 0.5;
    const scale = cluster.scale ?? 1;
    const radialX = Math.cos(worldAngle);
    const radialZ = Math.sin(worldAngle);
    const tangentX = -radialZ;
    const tangentZ = radialX;
    const centerX = radialX * radius;
    const centerZ = radialZ * radius;
    const random = seededRandom((visual.seed ?? 1) ^ hashString(cluster.id ?? cluster.fragmentId));

    dummy.position.set(centerX, surfaceY + 0.13 * scale, centerZ);
    dummy.rotation.set(0, worldAngle, 0);
    dummy.scale.set(scale, scale, scale);
    dummy.updateMatrix();
    planterMatrices.push(dummy.matrix.clone());

    for (let stem = 0; stem < 5; stem += 1) {
      const phase = (stem / 5) * Math.PI * 2 + (random() - 0.5) * 0.22;
      const radialOffset = Math.cos(phase) * 0.2 * scale;
      const tangentOffset = Math.sin(phase) * 0.23 * scale;
      const stemHeight = (0.76 + random() * 0.3) * scale;
      const stemX = centerX + radialX * radialOffset + tangentX * tangentOffset;
      const stemZ = centerZ + radialZ * radialOffset + tangentZ * tangentOffset;
      const leanX = Math.sin(phase) * 0.2;
      const leanZ = Math.cos(phase) * 0.2;

      dummy.position.set(stemX, surfaceY + 0.24 * scale + stemHeight * 0.5, stemZ);
      dummy.rotation.set(leanX, worldAngle + phase, leanZ);
      dummy.scale.set(scale, stemHeight, scale);
      dummy.updateMatrix();
      stemMatrices.push(dummy.matrix.clone());

      const leafHeight = (0.86 + random() * 0.18) * scale;
      dummy.position.set(
        stemX + radialX * radialOffset * 0.45,
        surfaceY + 0.22 * scale + stemHeight * 0.8,
        stemZ + radialZ * radialOffset * 0.45
      );
      dummy.rotation.set(leanX * 2.15, worldAngle + phase + Math.PI * 0.5, leanZ * 2.15);
      dummy.scale.set(scale, leafHeight, scale);
      dummy.updateMatrix();
      leafMatrices.push(dummy.matrix.clone());

      if (stem % 2 === 0) {
        dummy.position.set(
          stemX + radialX * radialOffset * 0.72,
          surfaceY + 0.24 * scale + stemHeight,
          stemZ + radialZ * radialOffset * 0.72
        );
        dummy.rotation.set(leanX, worldAngle + phase, leanZ);
        dummy.scale.set(scale * 0.88, scale, scale * 0.88);
        dummy.updateMatrix();
        budMatrices.push(dummy.matrix.clone());
      }
    }
  }

  addStaticInstances(
    deckLife,
    "deck-life-ceramic-planters",
    HELIOS_DECK_LIFE_PLANTER_GEOMETRY,
    materials.deckLifePlanter,
    planterMatrices
  );
  addStaticInstances(
    deckLife,
    "deck-life-woven-stems",
    HELIOS_DECK_LIFE_STEM_GEOMETRY,
    materials.deckLifeStem,
    stemMatrices
  );
  addStaticInstances(
    deckLife,
    "deck-life-fabric-leaves",
    HELIOS_DECK_LIFE_LEAF_GEOMETRY,
    materials.deckLifeLeaf,
    leafMatrices
  );
  addStaticInstances(
    deckLife,
    "deck-life-lumen-buds",
    HELIOS_DECK_LIFE_BUD_GEOMETRY,
    materials.deckLifeBud,
    budMatrices
  );

  deckLife.userData.visualStyle = "sunwoven-deck-life";
  deckLife.userData.visualDetail = {
    clusters: planterMatrices.length,
    planters: planterMatrices.length,
    stems: stemMatrices.length,
    fabricLeaves: leafMatrices.length,
    lumenBuds: budMatrices.length,
    instancedDrawGroups: deckLife.children.length,
    createsWalkableGround: false,
    affectsPathing: false
  };
  disableCosmeticRaycast(deckLife);
  group.add(deckLife);
  return deckLife;
}

function addHeliosMaintenanceMechanisms(group, visual, materials) {
  const requested = visual.maintenance?.winches ?? [];
  if (requested.length === 0) return null;

  const maintenance = new THREE.Group();
  maintenance.name = "helios-terminal-maintenance";
  const baseMatrices = [];
  const yokeMatrices = [];
  const drumMatrices = [];
  const coilMatrices = [];
  const braceMatrices = [];
  const dummy = new THREE.Object3D();
  const upAxis = new THREE.Vector3(0, 1, 0);
  const forwardAxis = new THREE.Vector3(0, 0, 1);
  const surfaceY = visual.surfaceY ?? 0;

  for (const winch of requested) {
    const fragment = visual.fragments?.find((entry) => entry.id === winch.fragmentId);
    if (!fragment) continue;
    const worldAngle = (fragment.centerAngle ?? 0) + (winch.angleOffset ?? 0);
    const radius = winch.radius ?? (visual.innerRadius + visual.outerRadius) * 0.5;
    const scale = winch.scale ?? 1;
    const centerX = Math.cos(worldAngle) * radius;
    const centerZ = Math.sin(worldAngle) * radius;
    const axisAngle = worldAngle + Math.PI / 2;
    const axis = new THREE.Vector3(Math.cos(axisAngle), 0, Math.sin(axisAngle));

    dummy.position.set(centerX, surfaceY + 0.11 * scale, centerZ);
    dummy.rotation.set(0, -axisAngle, 0);
    dummy.scale.setScalar(scale);
    dummy.updateMatrix();
    baseMatrices.push(dummy.matrix.clone());

    for (const side of [-1, 1]) {
      dummy.position.set(
        centerX + axis.x * side * 0.5 * scale,
        surfaceY + 0.52 * scale,
        centerZ + axis.z * side * 0.5 * scale
      );
      dummy.rotation.set(0, -axisAngle, 0);
      dummy.scale.setScalar(scale);
      dummy.updateMatrix();
      yokeMatrices.push(dummy.matrix.clone());
    }

    dummy.position.set(centerX, surfaceY + 0.62 * scale, centerZ);
    dummy.quaternion.setFromUnitVectors(upAxis, axis);
    dummy.scale.setScalar(scale);
    dummy.updateMatrix();
    drumMatrices.push(dummy.matrix.clone());

    for (const side of [-1, 1]) {
      dummy.position.set(
        centerX + axis.x * side * 0.31 * scale,
        surfaceY + 0.62 * scale,
        centerZ + axis.z * side * 0.31 * scale
      );
      dummy.quaternion.setFromUnitVectors(forwardAxis, axis);
      dummy.scale.setScalar(scale);
      dummy.updateMatrix();
      coilMatrices.push(dummy.matrix.clone());
    }

    dummy.position.set(centerX, surfaceY + 0.96 * scale, centerZ);
    dummy.rotation.set(0, -axisAngle, 0);
    dummy.scale.setScalar(scale);
    dummy.updateMatrix();
    braceMatrices.push(dummy.matrix.clone());
  }

  addStaticInstances(
    maintenance,
    "maintenance-winch-plinths",
    HELIOS_WINCH_BASE_GEOMETRY,
    materials.deckLifePlanter,
    baseMatrices
  );
  addStaticInstances(
    maintenance,
    "maintenance-winch-yokes",
    HELIOS_WINCH_YOKE_GEOMETRY,
    materials.sidewallRib,
    yokeMatrices
  );
  addStaticInstances(
    maintenance,
    "maintenance-winch-drums",
    HELIOS_WINCH_DRUM_GEOMETRY,
    materials.deckLifePlanter,
    drumMatrices
  );
  addStaticInstances(
    maintenance,
    "maintenance-lumen-coil-rings",
    HELIOS_WINCH_COIL_GEOMETRY,
    materials.conduit,
    coilMatrices
  );
  addStaticInstances(
    maintenance,
    "maintenance-winch-top-braces",
    HELIOS_WINCH_BRACE_GEOMETRY,
    materials.sidewallRib,
    braceMatrices
  );

  maintenance.userData.visualStyle = "sunwoven-gravity-winches";
  maintenance.userData.visualDetail = {
    winches: baseMatrices.length,
    plinths: baseMatrices.length,
    yokes: yokeMatrices.length,
    drums: drumMatrices.length,
    lumenCoilRings: coilMatrices.length,
    topBraces: braceMatrices.length,
    instancedDrawGroups: maintenance.children.length,
    createsWalkableGround: false,
    affectsPathing: false
  };
  disableCosmeticRaycast(maintenance);
  group.add(maintenance);
  return maintenance;
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

function makeJaggedAnnularSectorGeometry(
  inner,
  outer,
  span,
  depth,
  segments,
  seed,
  innerJitter,
  outerJitter
) {
  const start = -span / 2;
  const step = span / segments;
  const halfDepth = depth * 0.5;
  const positions = [];
  const indices = [];
  const random = seededRandom(seed);

  for (let i = 0; i <= segments; i += 1) {
    const angle = start + step * i;
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    const edgeWeight = i === 0 || i === segments ? 0.35 : 1;
    const outerRadius = outer + (random() * 2 - 1) * outerJitter * edgeWeight;
    const innerRadius = inner + (random() * 2 - 1) * innerJitter * edgeWeight;
    positions.push(
      c * outerRadius,
      halfDepth,
      s * outerRadius,
      c * innerRadius,
      halfDepth,
      s * innerRadius,
      c * outerRadius,
      -halfDepth,
      s * outerRadius,
      c * innerRadius,
      -halfDepth,
      s * innerRadius
    );
  }

  const quad = (a, b, c, d) => indices.push(a, b, c, a, c, d);
  for (let i = 0; i < segments; i += 1) {
    const a = i * 4;
    const b = (i + 1) * 4;
    quad(a + 1, b + 1, b, a);
    quad(a + 2, b + 2, b + 3, a + 3);
    quad(a, b, b + 2, a + 2);
    quad(a + 3, b + 3, b + 1, a + 1);
  }
  const last = segments * 4;
  quad(0, 2, 3, 1);
  quad(last + 1, last + 3, last + 2, last);

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function addHeliosDeckCracks(parent, inner, outer, start, end, count, material, y, random) {
  const positions = [];
  const radialSpan = Math.max(1, outer - inner);

  for (let i = 0; i < count; i += 1) {
    const angle = THREE.MathUtils.lerp(start + 0.05, end - 0.05, (i + 0.5) / count);
    const originRadius = inner + radialSpan * (0.18 + random() * 0.5);
    const length = radialSpan * (0.12 + random() * 0.12);
    let previousAngle = angle + (random() - 0.5) * 0.05;
    let previousRadius = originRadius;

    for (let segment = 0; segment < 3; segment += 1) {
      const nextRadius = Math.min(outer, previousRadius + length / 3);
      const nextAngle = previousAngle + (random() - 0.5) * 0.045;
      positions.push(
        Math.cos(previousAngle) * previousRadius,
        y,
        Math.sin(previousAngle) * previousRadius,
        Math.cos(nextAngle) * nextRadius,
        y,
        Math.sin(nextAngle) * nextRadius
      );
      previousAngle = nextAngle;
      previousRadius = nextRadius;
    }
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  const cracks = new THREE.LineSegments(geometry, material);
  cracks.name = "deck-cracks";
  parent.add(cracks);
}

function addHeliosArmorBlocks(
  parent,
  inner,
  outer,
  start,
  end,
  count,
  underDepth,
  material,
  surfaceY,
  random
) {
  const geometry = new THREE.DodecahedronGeometry(1, 0);
  const blocks = new THREE.InstancedMesh(geometry, material, count * 2);
  const dummy = new THREE.Object3D();
  const slotAngle = count > 1 ? (end - start) / (count - 1) : 0;

  for (let i = 0; i < count; i += 1) {
    const baseAngle = THREE.MathUtils.lerp(start, end, count === 1 ? 0.5 : i / (count - 1));

    for (let edge = 0; edge < 2; edge += 1) {
      const endpoint = i === 0 || i === count - 1;
      const angle = baseAngle + (endpoint ? 0 : (random() - 0.5) * slotAngle * 0.42);
      const tangentWidth = 2.2 + random() * 1.25;
      const height = Math.min(underDepth * 0.48, 0.95 + random() * 0.7);
      const radialDepth = edge === 0 ? 1.35 + random() * 0.5 : 1.12 + random() * 0.42;
      const radius = (edge === 0 ? outer + 0.08 : inner - 0.08) + (random() - 0.5) * 0.38;
      const top = surfaceY + 0.2 + random() * 0.18;
      dummy.position.set(
        Math.cos(angle) * radius,
        top - height * 0.5,
        Math.sin(angle) * radius
      );
      dummy.rotation.set(
        (random() - 0.5) * 0.14,
        Math.PI / 2 - angle + (random() - 0.5) * 0.12,
        (random() - 0.5) * 0.12
      );
      dummy.scale.set(tangentWidth * 0.5, height * 0.5, radialDepth * 0.5);
      dummy.updateMatrix();
      blocks.setMatrixAt(i * 2 + edge, dummy.matrix);
    }
  }

  blocks.name = "fragment-armor-blocks";
  blocks.instanceMatrix.needsUpdate = true;
  parent.add(blocks);
}

function addHeliosSidewallArchitecture(
  parent,
  inner,
  outer,
  start,
  end,
  underDepth,
  requestedTierCount,
  requestedBlockCount,
  requestedRibCount,
  materials,
  surfaceY,
  random
) {
  const tierCount = Math.max(1, Math.round(requestedTierCount));
  const blockCount = Math.max(4, Math.round(requestedBlockCount));
  const ribCount = Math.max(2, Math.round(requestedRibCount));
  const palettes = [materials.sidewallMasonry, materials.sidewallSolarMasonry]
    .map((material) => (material.userData.instancePalette ?? [0x2b2d2f])
      .map((color) => new THREE.Color(color)));
  const topClearance = 0.44;
  const bottomClearance = 0.38;
  const tierPitch = Math.max(0.55, (underDepth - topClearance - bottomClearance) / tierCount);
  const blocksPerEdge = tierCount * blockCount;
  const edgeBlocks = [
    new THREE.InstancedMesh(
      HELIOS_SIDEWALL_BLOCK_GEOMETRY,
      materials.sidewallMasonry,
      blocksPerEdge
    ),
    new THREE.InstancedMesh(
      HELIOS_SIDEWALL_BLOCK_GEOMETRY,
      materials.sidewallSolarMasonry,
      blocksPerEdge
    )
  ];
  const dummy = new THREE.Object3D();
  const usableStart = start + 0.055;
  const usableEnd = end - 0.055;
  const usableSpan = Math.max(0.1, usableEnd - usableStart);
  const edgeBlockIndices = [0, 0];

  for (let tier = 0; tier < tierCount; tier += 1) {
    const stagger = tier % 2 === 0 ? 0 : 0.34;
    const tierCenterY = surfaceY - topClearance - tierPitch * (tier + 0.5);

    for (let i = 0; i < blockCount; i += 1) {
      const normalized = THREE.MathUtils.clamp((i + 0.5 + stagger) / blockCount, 0.02, 0.98);
      const angle = THREE.MathUtils.lerp(usableStart, usableEnd, normalized);

      for (let edge = 0; edge < 2; edge += 1) {
        const radiusBase = edge === 0 ? outer + 0.03 : inner - 0.03;
        const radius = radiusBase + (edge === 0 ? 1 : -1) * tier * 0.025;
        const slotWidth = Math.max(1.65, radius * usableSpan / blockCount);
        const tangentWidth = slotWidth * (0.92 + random() * 0.045);
        const blockHeight = tierPitch * (0.83 + random() * 0.055);
        const radialDepth = (edge === 0 ? 0.88 : 0.76) * (0.94 + random() * 0.08);
        const angleJitter = (random() - 0.5) * usableSpan / blockCount * 0.025;
        const finalAngle = angle + angleJitter;

        dummy.position.set(
          Math.cos(finalAngle) * radius,
          tierCenterY + (random() - 0.5) * tierPitch * 0.025,
          Math.sin(finalAngle) * radius
        );
        dummy.rotation.set(
          (random() - 0.5) * 0.012,
          Math.PI / 2 - finalAngle + (random() - 0.5) * 0.012,
          (random() - 0.5) * 0.016
        );
        dummy.scale.set(tangentWidth * 0.9, blockHeight * 0.9, radialDepth * 0.95);
        dummy.updateMatrix();
        const blocks = edgeBlocks[edge];
        const blockIndex = edgeBlockIndices[edge];
        const palette = palettes[edge];
        blocks.setMatrixAt(blockIndex, dummy.matrix);
        const colorIndex = (tier * 2 + i + edge + Math.floor(random() * palette.length)) % palette.length;
        blocks.setColorAt(blockIndex, palette[colorIndex]);
        edgeBlockIndices[edge] += 1;
      }
    }
  }

  edgeBlocks[0].name = "fragment-outer-sidewall-masonry";
  edgeBlocks[1].name = "fragment-inner-solar-bounce-masonry";
  for (const blocks of edgeBlocks) {
    blocks.instanceMatrix.needsUpdate = true;
    if (blocks.instanceColor) blocks.instanceColor.needsUpdate = true;
    parent.add(blocks);
  }

  // Each structural frame uses one vertical rib and two short brackets. They
  // share one instanced draw group, so the warm rhythm stays inexpensive.
  const structuralPiecesPerRib = 3;
  const ribs = new THREE.InstancedMesh(
    HELIOS_SIDEWALL_RIB_GEOMETRY,
    materials.sidewallRib,
    ribCount * 2 * structuralPiecesPerRib
  );
  const ribHeight = Math.max(1.2, underDepth * 0.74);
  const ribTop = surfaceY - 0.34;
  let ribPieceIndex = 0;

  for (let i = 0; i < ribCount; i += 1) {
    const angle = THREE.MathUtils.lerp(
      usableStart + 0.06,
      usableEnd - 0.06,
      ribCount === 1 ? 0.5 : i / (ribCount - 1)
    );

    for (let edge = 0; edge < 2; edge += 1) {
      const radius = edge === 0 ? outer + 0.47 : inner - 0.41;
      const radialDepth = edge === 0 ? 0.14 : 0.12;
      dummy.position.set(
        Math.cos(angle) * radius,
        ribTop - ribHeight * 0.5,
        Math.sin(angle) * radius
      );
      dummy.rotation.set(0, Math.PI / 2 - angle, 0);
      dummy.scale.set(0.12, ribHeight, radialDepth);
      dummy.updateMatrix();
      ribs.setMatrixAt(ribPieceIndex, dummy.matrix);
      ribPieceIndex += 1;

      for (let bracket = 0; bracket < 2; bracket += 1) {
        const bracketY = bracket === 0 ? ribTop - 0.06 : ribTop - ribHeight * 0.58;
        dummy.position.set(Math.cos(angle) * radius, bracketY, Math.sin(angle) * radius);
        dummy.rotation.set(0, Math.PI / 2 - angle, 0);
        dummy.scale.set(0.44, 0.085, radialDepth * 1.5);
        dummy.updateMatrix();
        ribs.setMatrixAt(ribPieceIndex, dummy.matrix);
        ribPieceIndex += 1;
      }
    }
  }

  ribs.name = "fragment-sidewall-structural-ribs";
  ribs.instanceMatrix.needsUpdate = true;
  parent.add(ribs);

  const contactBandDepth = 0.5;
  const contactBandSpan = Math.max(0.1, end - start);
  const outerShadow = new THREE.Mesh(
    makeAnnularSectorGeometry(outer - 0.38, outer + 0.3, contactBandSpan, contactBandDepth, 24),
    materials.sidewallShadow
  );
  outerShadow.name = "fragment-outer-contact-shadow";
  outerShadow.position.y = surfaceY - 0.37;
  parent.add(outerShadow);

  const innerShadow = new THREE.Mesh(
    makeAnnularSectorGeometry(inner - 0.3, inner + 0.38, contactBandSpan, contactBandDepth, 24),
    materials.sidewallShadow
  );
  innerShadow.name = "fragment-inner-contact-shadow";
  innerShadow.position.y = surfaceY - 0.37;
  parent.add(innerShadow);

  return {
    tiers: tierCount,
    blocks: tierCount * blockCount * 2,
    ribs: ribCount * 2,
    ribBrackets: ribCount * 4,
    contactShadowBands: 2,
    solarBounceBlocks: blocksPerEdge,
    drawGroups: 5
  };
}

function addHeliosTerminalArchitecture(
  parent,
  inner,
  outer,
  start,
  end,
  underDepth,
  requestedTierCount,
  requestedBlockCount,
  requestedRibCount,
  materials,
  surfaceY,
  random
) {
  const tierCount = Math.max(1, Math.round(requestedTierCount));
  const blockCount = Math.max(4, Math.round(requestedBlockCount));
  const ribCount = Math.max(2, Math.round(requestedRibCount));
  const terminalMaterial = materials.sidewallSolarMasonry ?? materials.sidewallMasonry;
  const palette = (terminalMaterial.userData.instancePalette ?? [0x2b2d2f])
    .map((color) => new THREE.Color(color));
  const blocks = new THREE.InstancedMesh(
    HELIOS_SIDEWALL_BLOCK_GEOMETRY,
    terminalMaterial,
    tierCount * blockCount * 2
  );
  const dummy = new THREE.Object3D();
  const radialStart = inner + 0.62;
  const radialEnd = outer - 0.62;
  const radialSlot = (radialEnd - radialStart) / blockCount;
  const tierPitch = Math.min(0.88, Math.max(0.64, (underDepth - 0.9) / tierCount));
  let blockIndex = 0;

  for (let endpoint = 0; endpoint < 2; endpoint += 1) {
    const baseAngle = endpoint === 0 ? start : end;
    const gapDirection = endpoint === 0 ? -1 : 1;
    for (let tier = 0; tier < tierCount; tier += 1) {
      // The center stays on the fragment's chipped cut plane. The deeper
      // extrusion reaches into the gap while its back remains attached to the
      // existing understructure, so the terminal reads as masonry rather than
      // a detached rail.
      const faceAngle = baseAngle + gapDirection * (0.039 + tier * 0.003);
      const centerY = surfaceY - 0.3 - tierPitch * (tier + 0.5);
      for (let block = 0; block < blockCount; block += 1) {
        const stagger = tier % 2 === 0 ? 0 : radialSlot * 0.16;
        const radius = THREE.MathUtils.clamp(
          radialStart + radialSlot * (block + 0.5) + stagger,
          radialStart + radialSlot * 0.42,
          radialEnd - radialSlot * 0.42
        );
        const radialWidth = radialSlot * (0.88 + random() * 0.035);
        const blockHeight = tierPitch * (0.8 + random() * 0.045);
        const tangentialDepth = (1.42 + tier * 0.08) * (0.96 + random() * 0.05);
        dummy.position.set(
          Math.cos(faceAngle) * radius,
          centerY + (random() - 0.5) * 0.025,
          Math.sin(faceAngle) * radius
        );
        dummy.rotation.set(
          (random() - 0.5) * 0.016,
          -faceAngle + (random() - 0.5) * 0.012,
          (random() - 0.5) * 0.014
        );
        dummy.scale.set(radialWidth * 0.9, blockHeight * 0.9, tangentialDepth);
        dummy.updateMatrix();
        blocks.setMatrixAt(blockIndex, dummy.matrix);
        blocks.setColorAt(
          blockIndex,
          palette[(tier + block + endpoint + Math.floor(random() * palette.length)) % palette.length]
        );
        blockIndex += 1;
      }
    }
  }

  blocks.name = "fragment-terminal-masonry";
  blocks.instanceMatrix.needsUpdate = true;
  if (blocks.instanceColor) blocks.instanceColor.needsUpdate = true;
  parent.add(blocks);

  const structuralPiecesPerRib = 3;
  const ribs = new THREE.InstancedMesh(
    HELIOS_SIDEWALL_RIB_GEOMETRY,
    materials.sidewallRib,
    ribCount * 2 * structuralPiecesPerRib
  );
  const ribHeight = Math.min(underDepth * 0.72, 2.8);
  const ribTop = surfaceY - 0.28;
  let ribPieceIndex = 0;

  for (let endpoint = 0; endpoint < 2; endpoint += 1) {
    const baseAngle = endpoint === 0 ? start : end;
    const gapDirection = endpoint === 0 ? -1 : 1;
    const faceAngle = baseAngle + gapDirection * 0.043;
    for (let rib = 0; rib < ribCount; rib += 1) {
      const radius = THREE.MathUtils.lerp(
        inner + 1.12,
        outer - 1.12,
        ribCount === 1 ? 0.5 : rib / (ribCount - 1)
      );
      dummy.position.set(
        Math.cos(faceAngle) * radius,
        ribTop - ribHeight * 0.5,
        Math.sin(faceAngle) * radius
      );
      dummy.rotation.set(0, -faceAngle, 0);
      dummy.scale.set(0.13, ribHeight, 0.18);
      dummy.updateMatrix();
      ribs.setMatrixAt(ribPieceIndex, dummy.matrix);
      ribPieceIndex += 1;

      for (let bracket = 0; bracket < 2; bracket += 1) {
        const bracketY = bracket === 0 ? ribTop - 0.08 : ribTop - ribHeight * 0.58;
        dummy.position.set(Math.cos(faceAngle) * radius, bracketY, Math.sin(faceAngle) * radius);
        dummy.rotation.set(0, -faceAngle, 0);
        dummy.scale.set(0.68, 0.085, 0.28);
        dummy.updateMatrix();
        ribs.setMatrixAt(ribPieceIndex, dummy.matrix);
        ribPieceIndex += 1;
      }
    }
  }

  ribs.name = "fragment-terminal-structural-ribs";
  ribs.instanceMatrix.needsUpdate = true;
  parent.add(ribs);

  return {
    tiers: tierCount,
    blocks: tierCount * blockCount * 2,
    ribs: ribCount * 2,
    ribBrackets: ribCount * 4,
    solarBounceBlocks: tierCount * blockCount * 2,
    drawGroups: 2
  };
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
  socket.position.set(Math.cos(angle) * radius, surfaceY + 0.04, Math.sin(angle) * radius);
  const pedestal = new THREE.Mesh(
    new THREE.CylinderGeometry(size * 1.28, size * 1.46, 0.5, 10),
    materials.basalt
  );
  pedestal.position.y = -0.22;
  socket.add(pedestal);
  const cap = new THREE.Mesh(
    new THREE.CylinderGeometry(size, size * 1.08, 0.16, 10),
    materials.basaltEdge
  );
  socket.add(cap);
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(size * 0.73, Math.max(0.045, size * 0.085), 6, 12),
    materials.gold
  );
  ring.rotation.x = Math.PI / 2;
  ring.position.y = 0.1;
  socket.add(ring);
  const hub = new THREE.Mesh(
    new THREE.CylinderGeometry(size * 0.22, size * 0.28, 0.12, 8),
    materials.gold
  );
  hub.position.y = 0.11;
  socket.add(hub);
  parent.add(socket);
  return socket;
}

function addHeliosEndAssembly(parent, inner, outer, angle, materials, surfaceY) {
  addRadialBar(parent, angle, inner + 0.3, outer - 0.3, 0.86, 0.56, materials.basaltEdge, surfaceY - 0.16);
  addRadialBar(parent, angle, inner + 0.75, outer - 0.75, 0.16, 0.11, materials.gold, surfaceY + 0.1);
  addHeliosSocket(parent, outer - 0.72, angle, 0.86, materials, surfaceY);
  addHeliosSocket(parent, inner + 0.82, angle, 0.66, materials, surfaceY);
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
  const looseDarkMatrices = [];
  const looseWarmMatrices = [];
  const looseCrystalMatrices = [];
  const anchorDarkMatrices = [];
  const anchorWarmMatrices = [];
  const anchorCrystalMatrices = [];
  const anchorBrightCrystalMatrices = [];
  const dummy = new THREE.Object3D();

  for (let i = 0; i < count; i += 1) {
    const theta = random() * Math.PI * 2;
    const size = 0.22 + random() * 0.82;
    const useInnerPocket = innerSpan > 0 && (outerSpan <= 0 || random() < 0.36);
    const radius = useInnerPocket
      ? innerMin + Math.sqrt(random()) * innerSpan
      : outerMin + Math.sqrt(random()) * outerSpan;
    dummy.position.set(Math.cos(theta) * radius, -2.4 + random() * 5.2, Math.sin(theta) * radius);
    dummy.scale.set(
      size * (0.75 + random() * 0.6),
      size * (0.55 + random() * 0.5),
      size * (0.72 + random() * 0.55)
    );
    dummy.rotation.set(random() * Math.PI, random() * Math.PI, random() * Math.PI);
    dummy.updateMatrix();
    const looseTarget = i % 4 === 0 ? looseWarmMatrices : looseDarkMatrices;
    looseTarget.push(dummy.matrix.clone());

    if (i % 11 === 0) {
      dummy.position.y += size * 0.62;
      dummy.scale.set(size * 0.2, size * 0.92, size * 0.2);
      dummy.rotation.set((random() - 0.5) * 0.45, random() * Math.PI * 2, (random() - 0.5) * 0.45);
      dummy.updateMatrix();
      looseCrystalMatrices.push(dummy.matrix.clone());
    }
  }

  for (const [anchorIndex, anchor] of (field.anchors ?? []).entries()) {
    const anchorRandom = seededRandom((visual.seed ?? 1) ^ hashString(anchor.id ?? `anchor-${anchorIndex}`));
    const angle = anchor.angle ?? anchorRandom() * Math.PI * 2;
    const radius = anchor.radius ?? outerMin + anchorRandom() * outerSpan;
    const size = anchor.size ?? 3;
    const centerX = Math.cos(angle) * radius;
    const centerZ = Math.sin(angle) * radius;
    const centerY = anchor.y ?? -0.8;
    const lobeCount = anchor.lobes ?? 6;

    for (let lobe = 0; lobe < lobeCount; lobe += 1) {
      const lobeAngle = anchorRandom() * Math.PI * 2;
      const lobeDistance = lobe === 0 ? 0 : size * (0.18 + anchorRandom() * 0.42);
      const lobeSize = lobe === 0 ? size : size * (0.32 + anchorRandom() * 0.34);
      dummy.position.set(
        centerX + Math.cos(lobeAngle) * lobeDistance,
        centerY + (anchorRandom() - 0.54) * size * 0.32,
        centerZ + Math.sin(lobeAngle) * lobeDistance
      );
      dummy.scale.set(
        lobeSize * (0.72 + anchorRandom() * 0.48),
        lobeSize * (0.45 + anchorRandom() * 0.34),
        lobeSize * (0.68 + anchorRandom() * 0.5)
      );
      dummy.rotation.set(anchorRandom() * Math.PI, anchorRandom() * Math.PI, anchorRandom() * Math.PI);
      dummy.updateMatrix();
      const anchorTarget = (anchorIndex + lobe) % 3 === 0 ? anchorWarmMatrices : anchorDarkMatrices;
      anchorTarget.push(dummy.matrix.clone());
    }

    const crystalCount = anchor.crystals ?? 0;
    for (let crystal = 0; crystal < crystalCount; crystal += 1) {
      const crystalAngle = anchorRandom() * Math.PI * 2;
      const crystalDistance = size * (0.1 + anchorRandom() * 0.46);
      const crystalHeight = size * (0.34 + anchorRandom() * 0.38);
      const crystalWidth = crystalHeight * (0.24 + anchorRandom() * 0.07);
      dummy.position.set(
        centerX + Math.cos(crystalAngle) * crystalDistance,
        centerY + size * 0.48 + crystalHeight * 0.3,
        centerZ + Math.sin(crystalAngle) * crystalDistance
      );
      dummy.scale.set(crystalWidth, crystalHeight, crystalWidth);
      dummy.rotation.set(
        (anchorRandom() - 0.5) * 0.38,
        anchorRandom() * Math.PI * 2,
        (anchorRandom() - 0.5) * 0.38
      );
      dummy.updateMatrix();
      const crystalTarget = crystal % 3 === 0 ? anchorBrightCrystalMatrices : anchorCrystalMatrices;
      crystalTarget.push(dummy.matrix.clone());
    }
  }

  addStaticInstances(rocks, "debris-loose-dark", HELIOS_DEBRIS_GEOMETRY, materials.rock, looseDarkMatrices);
  addStaticInstances(rocks, "debris-loose-warm", HELIOS_DEBRIS_GEOMETRY, materials.rockWarm, looseWarmMatrices);
  addStaticInstances(
    rocks,
    "debris-loose-crystals",
    HELIOS_DEBRIS_CRYSTAL_GEOMETRY,
    materials.crystal,
    looseCrystalMatrices
  );
  addStaticInstances(
    rocks,
    "debris-anchor-dark",
    HELIOS_DEBRIS_ISLET_GEOMETRY,
    materials.rock,
    anchorDarkMatrices
  );
  addStaticInstances(
    rocks,
    "debris-anchor-warm",
    HELIOS_DEBRIS_ISLET_GEOMETRY,
    materials.rockWarm,
    anchorWarmMatrices
  );
  addStaticInstances(
    rocks,
    "debris-anchor-crystals",
    HELIOS_DEBRIS_CRYSTAL_CLUSTER_GEOMETRY,
    materials.crystal,
    anchorCrystalMatrices
  );
  addStaticInstances(
    rocks,
    "debris-anchor-crystals-bright",
    HELIOS_DEBRIS_CRYSTAL_CLUSTER_GEOMETRY,
    materials.crystalBright,
    anchorBrightCrystalMatrices
  );

  rocks.userData.visualStyle = "authored-crystal-islet-field";
  rocks.userData.visualDetail = {
    looseRocks: count,
    anchorCount: field.anchors?.length ?? 0,
    anchorRockLobes: anchorDarkMatrices.length + anchorWarmMatrices.length,
    looseCrystals: looseCrystalMatrices.length,
    anchorCrystals: anchorCrystalMatrices.length + anchorBrightCrystalMatrices.length,
    instancedDrawGroups: rocks.children.length,
    createsWalkableGround: false
  };

  disableCosmeticRaycast(rocks);
  group.add(rocks);
}

function addStaticInstances(parent, name, geometry, material, matrices) {
  if (matrices.length === 0) return null;
  const instances = new THREE.InstancedMesh(geometry, material, matrices.length);
  instances.name = name;
  for (let i = 0; i < matrices.length; i += 1) instances.setMatrixAt(i, matrices[i]);
  instances.instanceMatrix.setUsage(THREE.StaticDrawUsage);
  instances.instanceMatrix.needsUpdate = true;
  instances.computeBoundingSphere();
  parent.add(instances);
  return instances;
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

function makeBridgeRepairRibbonGeometry(segmentPoints, width = 0.045) {
  const positions = [];
  const indices = [];
  const halfWidth = width * 0.5;

  for (let i = 0; i + 1 < segmentPoints.length; i += 2) {
    const start = segmentPoints[i];
    const end = segmentPoints[i + 1];
    const dx = end.x - start.x;
    const dz = end.z - start.z;
    const inverseLength = 1 / Math.max(0.0001, Math.hypot(dx, dz));
    const offsetX = -dz * inverseLength * halfWidth;
    const offsetZ = dx * inverseLength * halfWidth;
    const base = positions.length / 3;
    positions.push(
      start.x + offsetX, start.y, start.z + offsetZ,
      start.x - offsetX, start.y, start.z - offsetZ,
      end.x - offsetX, end.y, end.z - offsetZ,
      end.x + offsetX, end.y, end.z + offsetZ
    );
    indices.push(
      base, base + 1, base + 2,
      base, base + 2, base + 3,
      base + 2, base + 1, base,
      base + 3, base + 2, base
    );
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
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

  const deckWidth = enabled ? fullDeckWidth : fullDeckWidth * 0.88;
  let fracturedDeckPieces = 0;
  let exposedBraces = 0;
  let repairFilamentSegments = 0;

  if (enabled) {
    const enabledPieces = 4;
    const gap = Math.min(0.2, len * 0.04);
    const pieceLen = Math.max(0.35, (len - gap * (enabledPieces - 1)) / enabledPieces);
    for (let i = 0; i < enabledPieces; i += 1) {
      const deck = new THREE.Mesh(
        new THREE.BoxGeometry(deckWidth, 0.12, pieceLen),
        materials.deck
      );
      deck.name = "bridge-restored-deck-slab";
      deck.position.z = -len * 0.5 + pieceLen * 0.5 + i * (pieceLen + gap);
      deck.position.y = surfaceY - 0.06;
      g.add(deck);
    }
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
    const terminalLength = Math.max(0.7, Math.min(len * 0.24, underStubLength * 0.7));
    const tongueLength = Math.max(0.42, Math.min(len * 0.11, underStubLength * 0.34));
    const fractureGap = Math.min(0.28, len * 0.025);
    const filamentPoints = [];

    for (const endSign of [-1, 1]) {
      const endpointZ = endSign * len * 0.5;
      const terminal = new THREE.Mesh(
        new THREE.BoxGeometry(deckWidth, 0.13, terminalLength),
        materials.basaltEdge
      );
      terminal.name = "bridge-fractured-terminal-slab";
      terminal.position.set(
        endSign * deckWidth * 0.018,
        surfaceY - 0.065,
        endpointZ - endSign * terminalLength * 0.5
      );
      terminal.rotation.y = endSign * 0.012;
      g.add(terminal);
      fracturedDeckPieces += 1;

      const tongue = new THREE.Mesh(
        new THREE.BoxGeometry(deckWidth * 0.72, 0.12, tongueLength),
        materials.basaltEdge
      );
      tongue.name = "bridge-fractured-tongue-slab";
      tongue.position.set(
        -endSign * deckWidth * 0.08,
        surfaceY - 0.11,
        endpointZ - endSign * (terminalLength + fractureGap + tongueLength * 0.5)
      );
      tongue.rotation.set(endSign * 0.025, endSign * 0.075, endSign * 0.018);
      g.add(tongue);
      fracturedDeckPieces += 1;

      const tornEdgeZ = endpointZ - endSign * (terminalLength + fractureGap + tongueLength);
      for (const lateral of [-0.28, 0, 0.28]) {
        const brace = new THREE.Mesh(HELIOS_SIDEWALL_RIB_GEOMETRY, materials.sidewallRib);
        brace.name = "bridge-exposed-torn-brace";
        brace.position.set(
          lateral * deckWidth,
          surfaceY - 0.02,
          tornEdgeZ - endSign * 0.3
        );
        brace.scale.set(0.075, 0.075, 0.68);
        brace.rotation.y = endSign * 0.055;
        g.add(brace);
        exposedBraces += 1;
      }

      for (const lateral of [-0.2, 0.2]) {
        const start = new THREE.Vector3(
          lateral * deckWidth,
          surfaceY + 0.08,
          tornEdgeZ - endSign * 0.62
        );
        const finish = new THREE.Vector3(
          lateral * deckWidth * 0.42,
          surfaceY + 0.1,
          endSign * len * 0.09
        );
        let previous = start;
        for (let segment = 1; segment <= 4; segment += 1) {
          const progress = segment / 4;
          const point = start.clone().lerp(finish, progress);
          point.y -= Math.sin(progress * Math.PI) * 0.42;
          filamentPoints.push(previous, point);
          previous = point;
          repairFilamentSegments += 1;
        }
      }

      const repairLight = new THREE.Mesh(
        new THREE.CylinderGeometry(0.11, 0.11, 0.08, 8),
        materials.gold
      );
      repairLight.name = "bridge-repair-beacon";
      repairLight.position.set(0, surfaceY + 0.08, tornEdgeZ + endSign * 0.18);
      g.add(repairLight);
    }

    const filaments = new THREE.Mesh(
      makeBridgeRepairRibbonGeometry(filamentPoints),
      materials.conduit
    );
    filaments.name = "bridge-broken-repair-ribbons";
    g.add(filaments);

    const spark = new THREE.Mesh(new THREE.SphereGeometry(0.09, 8, 6), materials.conduit);
    spark.name = "bridge-spark";
    spark.position.y = surfaceY + 0.12;
    g.add(spark);
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
  g.userData.visualStyle = enabled ? "restored-sunwoven-bridge" : "fractured-sunwoven-bridge";
  g.userData.visualDetail = {
    enabled,
    restoredDeckSlabs: enabled ? 4 : 0,
    fracturedDeckPieces,
    exposedBraces,
    repairFilamentSegments,
    createsWalkableGround: enabled
  };
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
  bridgeGroup.userData.visualStyle = rebuilt.userData.visualStyle;
  bridgeGroup.userData.visualDetail = rebuilt.userData.visualDetail;
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
