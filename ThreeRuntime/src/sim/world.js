// The authored, seed-locked map: one continent cut by void water.
//
// Ported from `Sources/Domain/WorldMap.swift` and `Sources/Domain/LandShape.swift`.
// Land is a signed *field*, not a union of discs (AGENTS.md CP-14): shaped plates
// give the bulk, `LandErosion` moves the shoreline of the assembled landmass so
// plate seams stop reading as overlapping circles, and `VoidBody` rivers, lakes
// and inlets are subtracted from the result.
//
// Fairness is one rule and only one (CP-14): both Cores sit the same distance
// from the Dominion. `coreAnchor()` makes that structural — both home plates come
// off one shared radius — so nothing else has to be mirrored, and none of these
// layouts is a half-turn of itself.
//
// Two deliberate departures from the Swift original, both forced by the pinned
// contract rather than chosen:
//
//   1. `types.js` closes `REGION_IDS` at five. Swift authors seven plates,
//      including `neutralOutcropNorth` / `neutralOutcropSouth`. Those two plates
//      are kept here for their **shape** — dropping them empties the theatre
//      corners and land coverage falls out of the 75–80% band — but they own no
//      region, so their ground is annexed by whichever of the five territories
//      scores nearest. `region()` therefore only ever answers with a `REGION_IDS`
//      member.
//   2. `isLand` is gated on `bounds`. Swift treats `bounds` as a camera limit with
//      land continuing past it; here "off-map" is one concept — outside `bounds`
//      is not land, has no region, and cannot be stood on — so no system can place
//      an entity the camera cannot show. The fit is floored at `MIN_RETAINED_LAND`,
//      so what this clips is the outermost tips of the coast and nothing more.
//
// Determinism: nothing in this file draws from an RNG stream. Coast fray, erosion
// and water wander are pure functions of world position, exactly as
// `LandNoise` is in Swift — the mesh, the minimap, the movement clamp and the
// deposit placer all ask "is this land?" in different orders on different frames
// and every one of them must get the same answer. The seed enters only through
// `LandNoise.salt`, so `create()` reads its generator's state and never advances
// it: building the same map twice cannot shift another system's numbers.

import { REGION_IDS } from "./types.js";

export const MAP_IDS = Object.freeze(["riverlands", "basin", "fjords"]);

export const DEFAULT_MAP_ID = "riverlands";

/**
 * Resolves a launch-argument value to a map id.
 *
 * Ported from `WorldMapID.fromLaunchArgument`. The CP-12/CP-13 names still
 * resolve so older notes, scripts and QA commands keep working rather than
 * silently loading the wrong map.
 */
export function resolveMapID(raw) {
  if (raw === null || raw === undefined) return DEFAULT_MAP_ID;
  const key = String(raw).toLowerCase();
  switch (key) {
    case "riverlands":
    case "coastland":
    case "continental":
    case "river":
    case "map1":
    case "1":
      return "riverlands";
    case "basin":
    case "isthmus":
    case "crescent":
    case "lake":
    case "lakes":
    case "map2":
    case "2":
      return "basin";
    case "fjords":
    case "fjord":
    case "inlets":
    case "coast":
    case "map3":
    case "3":
      return "fjords";
    default:
      return MAP_IDS.includes(key) ? key : DEFAULT_MAP_ID;
  }
}

// MARK: - LandNoise
//
// Deterministic scalar noise for shaping coastlines and water edges. A pure
// function of position: no state, no draw order, no stream to perturb.

/** A well-mixed hash of two integer lattice coordinates, in `0 ..< 1`. */
function landHash(x, y, salt) {
  let h = Math.imul(x | 0, 0x27d4eb2d) >>> 0;
  h = (h ^ (Math.imul(y | 0, 0x165667b1) >>> 0)) >>> 0;
  h = (h ^ (Math.imul(salt | 0, 0x9e3779b9) >>> 0)) >>> 0;
  h = (h ^ (h >>> 15)) >>> 0;
  h = Math.imul(h, 0x85ebca6b) >>> 0;
  h = (h ^ (h >>> 13)) >>> 0;
  h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return h / 4294967295;
}

/**
 * Smooth value noise in `-1 ... 1`. `cell` is the lattice spacing in metres, so
 * callers think in "how long is a wobble" rather than in cell counts.
 *
 * The interpolant is smoothstepped, not the samples: bilinear alone leaves
 * visible lattice creases along every cell boundary, which on a coastline reads
 * as a grid rather than as erosion.
 */
function noiseValue(x, z, cell, salt) {
  const spacing = cell > 0.001 ? cell : 0.001;
  const sx = x / spacing;
  const sz = z / spacing;
  const bx = Math.floor(sx);
  const bz = Math.floor(sz);
  const fx = sx - bx;
  const fz = sz - bz;
  const ex = fx * fx * (3 - 2 * fx);
  const ez = fz * fz * (3 - 2 * fz);

  const a = landHash(bx, bz, salt);
  const b = landHash(bx + 1, bz, salt);
  const c = landHash(bx, bz + 1, salt);
  const d = landHash(bx + 1, bz + 1, salt);
  const top = a + (b - a) * ex;
  const bottom = c + (d - c) * ex;
  return (top + (bottom - top) * ez) * 2 - 1;
}

/** Layered `noiseValue`. Two or three octaves is enough — the shapes are authored. */
function fbm(x, z, cell, octaves, salt) {
  let total = 0;
  let amplitude = 1;
  let normaliser = 0;
  let spacing = cell;
  const count = octaves > 1 ? octaves : 1;
  for (let octave = 0; octave < count; octave += 1) {
    total += noiseValue(x, z, spacing, (salt + Math.imul(octave, 7919)) >>> 0) * amplitude;
    normaliser += amplitude;
    amplitude *= 0.5;
    spacing *= 0.5;
  }
  return total / (normaliser > 0.001 ? normaliser : 0.001);
}

/**
 * Mixes a 64-bit world seed into an authored salt.
 *
 * The authored constant says *which* feature this is — this plate's fray, that
 * river's wander — and the seed says which world we are in. One seed change
 * re-rolls every coastline on the map at once while the layout's intent survives.
 */
function saltFor(authored, seed) {
  let mixed = ((authored >>> 0) ^ (seed.lo >>> 0)) >>> 0;
  mixed = (mixed ^ (Math.imul(seed.hi >>> 0, 0x9e3779b9) >>> 0)) >>> 0;
  mixed = (mixed ^ (mixed >>> 16)) >>> 0;
  return Math.imul(mixed, 0x7feb352d) >>> 0;
}

// MARK: - CoastProfile
//
// The authored outline of one land plate, as a radial profile. Harmonic 2 makes a
// plate oval, 3 a rounded triangle with three capes, 5 a starfish of headlands;
// the combination gives the lopsided bay-and-promontory outline a coast has.
// Kept star-shaped on purpose — concavity a star cannot express is the job of
// `VoidBody`.

function coast({ lobes = [], fray = 0.05, frayScale = 26, salt = 0x51ed2c17 }) {
  return {
    lobes: lobes.map(([harmonic, amplitude, phase]) => ({ harmonic, amplitude, phase })),
    fray,
    frayScale,
    salt: salt >>> 0
  };
}

/**
 * The same outline rotated by 180°.
 *
 * Rotating `cos(h·θ + φ)` by π is a phase shift for odd harmonics and a no-op for
 * even ones. Mirrored pairs are authored through this rather than by eye: the two
 * sides no longer have to be identical, but a plate and its opposite number
 * should still be the same size and character.
 */
function halfTurned(profile) {
  return {
    lobes: profile.lobes.map((lobe) => ({
      harmonic: lobe.harmonic,
      amplitude: lobe.amplitude,
      phase: lobe.phase + lobe.harmonic * Math.PI
    })),
    fray: profile.fray,
    frayScale: profile.frayScale,
    salt: profile.salt
  };
}

/** Radius multiplier at a bearing, measured as `atan2(offset.z, offset.x)`. */
function coastReach(profile, bearing, centerX, centerZ, nominal) {
  let reach = 1;
  const lobes = profile.lobes;
  for (let index = 0; index < lobes.length; index += 1) {
    const lobe = lobes[index];
    reach += lobe.amplitude * Math.cos(lobe.harmonic * bearing + lobe.phase);
  }
  if (profile.fray !== 0) {
    const rimX = centerX + Math.cos(bearing) * nominal;
    const rimZ = centerZ + Math.sin(bearing) * nominal;
    reach += profile.fray * fbm(rimX, rimZ, profile.frayScale, 2, profile.salt);
  }
  // Never let an authored mistake collapse a plate to a point or invert it.
  if (reach < 0.25) return 0.25;
  if (reach > 1.9) return 1.9;
  return reach;
}

// MARK: - Fragment
//
// One authored land plate. `radius` is its *nominal* size — still the scale every
// other system reasons in — and `coast` bends that into an outline with capes and
// bays. Water carved by the map's void bodies then removes parts of it.

function plate({ region = null, center, radius, depth, coast: profile }) {
  return { region, center, radius, depth, coast: profile };
}

function plateReachAtBearing(fragment, bearing) {
  return fragment.radius * coastReach(fragment.coast, bearing, fragment.center.x, fragment.center.z, fragment.radius);
}

/** The largest distance the outline reaches from the centre, for camera fitting. */
function plateMaxReach(fragment) {
  let largest = 0;
  for (let step = 0; step < 64; step += 1) {
    const reach = plateReachAtBearing(fragment, (step / 64) * 2 * Math.PI);
    if (reach > largest) largest = reach;
  }
  return largest;
}

// MARK: - LandErosion
//
// A perturbation applied to the **whole** land field rather than to one plate.
// The field is signed — metres inside the coast — so adding noise to it moves the
// shoreline in and out by metres wherever the shoreline happens to be, with no
// knowledge of which plate put it there. That carries one continuous grain across
// a plate seam, can cut a genuinely concave bay into a star shape, and can span a
// shallow waist so two plates fuse into one headland.

function erosionOf({ amplitude, scale = 40, octaves = 3, bias = 0, salt }) {
  return { amplitude, scale, octaves, bias, salt: salt >>> 0 };
}

function erosionDisplacement(erosion, x, z) {
  if (erosion.amplitude === 0) return erosion.bias;
  return erosion.bias + erosion.amplitude * fbm(x, z, erosion.scale, erosion.octaves, erosion.salt);
}

// MARK: - VoidBody
//
// A body of void carved out of the land: a river, a lake, a sea inlet. Reports a
// signed depth, so the same authored shape serves the legality test, the carved
// mesh, the bank geometry and the minimap contour.

function basinBody({ center, radius, outline, wander = 4.5, wanderScale = 30, salt }) {
  return { form: "basin", center, radius, outline, wander, wanderScale, salt: salt >>> 0 };
}

function channelBody({ path, halfWidths, wander = 3.0, wanderScale = 20, salt }) {
  if (path.length !== halfWidths.length || path.length < 2) {
    throw new RangeError("a channel needs at least two nodes and one half-width each");
  }
  return { form: "channel", path, halfWidths, wander, wanderScale, salt: salt >>> 0 };
}

/**
 * Metres of water at a point: positive inside the body, zero at the bank,
 * negative on dry land. Magnitude is a distance, so callers can ask for a margin
 * in the units they already think in.
 */
function bodyDepth(body, x, z) {
  let raw;
  if (body.form === "basin") {
    const dx = x - body.center.x;
    const dz = z - body.center.z;
    const reach = coastReach(body.outline, Math.atan2(dz, dx), body.center.x, body.center.z, body.radius);
    raw = body.radius * reach - Math.sqrt(dx * dx + dz * dz);
  } else {
    const path = body.path;
    const widths = body.halfWidths;
    raw = -Infinity;
    for (let index = 0; index < path.length - 1; index += 1) {
      const a = path[index];
      const b = path[index + 1];
      const spanX = b.x - a.x;
      const spanZ = b.z - a.z;
      const lengthSquared = spanX * spanX + spanZ * spanZ;
      let t = 0;
      if (lengthSquared >= 1e-6) {
        t = ((x - a.x) * spanX + (z - a.z) * spanZ) / lengthSquared;
        if (t < 0) t = 0;
        else if (t > 1) t = 1;
      }
      const closestX = a.x + spanX * t;
      const closestZ = a.z + spanZ * t;
      const halfWidth = widths[index] + (widths[index + 1] - widths[index]) * t;
      const dx = x - closestX;
      const dz = z - closestZ;
      const value = halfWidth - Math.sqrt(dx * dx + dz * dz);
      if (value > raw) raw = value;
    }
  }

  if (body.wander === 0) return raw;
  return raw + body.wander * fbm(x, z, body.wanderScale, 2, body.salt);
}

// MARK: - Water authoring

/**
 * A channel laid along the territory boundary between two plates.
 *
 * Authoring rivers in absolute coordinates does not survive contact with a packed
 * layout: a channel guessed onto the map cuts a corner off whichever plate it
 * clips, and that plate's land is then in two pieces with a rule saying both
 * halves are the same region. Running the water down the *boundary* removes the
 * whole class of problem — `region()` picks the nearest centre relative to plate
 * size, so on the line between two centres the boundary sits at `rA / (rA + rB)`,
 * exactly where this puts the channel's spine.
 *
 * The channel runs outward from that boundary and dies inland: a symmetric one
 * keeps going once it has done its job and ploughs into whatever is on the other
 * side of the map, and water that widens toward the void is also simply what a
 * river mouth looks like.
 */
function strait(a, b, options) {
  const {
    head,
    mouth,
    inland,
    seaward,
    bow = 0,
    meander = 0,
    meanderTurns = 1.5,
    wander = 2.6,
    wanderScale = 19,
    salt
  } = options;

  const spanX = b.center.x - a.center.x;
  const spanZ = b.center.z - a.center.z;
  const span = Math.sqrt(spanX * spanX + spanZ * spanZ);
  const axis = span > 0.0001 ? { x: spanX / span, z: spanZ / span } : { x: 1, z: 0 };
  const across = { x: -axis.z, z: axis.x };
  const along = (span * a.radius) / Math.max(a.radius + b.radius, 0.001);
  const spine = { x: a.center.x + axis.x * along, z: a.center.z + axis.z * along };

  const spineLength = Math.sqrt(spine.x * spine.x + spine.z * spine.z);
  const reference = spineLength > 0.0001 ? { x: spine.x / spineLength, z: spine.z / spineLength } : axis;
  const facesOut = across.x * reference.x + across.z * reference.z >= 0;
  const outward = facesOut ? across : { x: -across.x, z: -across.z };

  const steps = 16;
  const path = [];
  const halfWidths = [];
  for (let step = 0; step <= steps; step += 1) {
    const t = step / steps; // 0 inland … 1 seaward
    const distance = -inland + (inland + seaward) * t;
    const bend = bow * Math.sin(t * Math.PI) + meander * Math.sin(t * 2 * Math.PI * meanderTurns);
    path.push({
      x: spine.x + outward.x * distance + axis.x * bend,
      z: spine.z + outward.z * distance + axis.z * bend
    });
    halfWidths.push(head + (mouth - head) * t * t);
  }
  return channelBody({ path, halfWidths, wander, wanderScale, salt });
}

// MARK: - Layouts

/**
 * Where a home plate's centre goes, given a bearing.
 *
 * **The whole of this game's map fairness is this one function** (CP-14): the two
 * Cores must be the same distance from the Dominion, and nothing else has to
 * match. Placing both homes off one shared radius makes the rule structural.
 * Typed as two coordinate pairs it would be an invariant that holds by arithmetic
 * nobody re-checks, and the failure — one player a few metres closer to the
 * contested middle for the whole match — is invisible on screen.
 */
function coreAnchor(degrees, reach) {
  const radians = (degrees * Math.PI) / 180;
  return { x: Math.cos(radians) * reach, z: Math.sin(radians) * reach };
}

function findPlate(plates, region) {
  const found = plates.find((entry) => entry.region === region);
  if (!found) throw new RangeError(`layout is missing authored plate ${region}`);
  return found;
}

/**
 * **Riverlands.** A broad continent carrying a great void river system.
 *
 * Two rivers reach in from opposite outer edges along the seam between each home
 * and its expansion, each dying short of the middle so home plateaus stay open for
 * fights. What they leave between them is the Dominion: a neck of land with water
 * on both flanks, which is the one place an army can cross the map on foot.
 */
function riverlands(seed) {
  // Fray is deliberately low on all three maps. Roughening each plate's own
  // outline puts a different grain on either side of every seam, and the kink
  // where two of them meet is a tell that the coast is made of discs. Erosion
  // does that job once, for the whole landmass. What is left here is the plate's
  // *character* — which way it is stretched, where its capes are.
  const homeCoast = coast({
    lobes: [[2, 0.1, 0.4], [3, 0.06, 2.1], [5, 0.03, 0.9]],
    fray: 0.01,
    frayScale: 24,
    salt: saltFor(0x51ed2c17, seed)
  });
  const expansionCoast = coast({
    lobes: [[2, 0.09, 1.8], [3, 0.06, 0.5], [5, 0.03, 2.4]],
    fray: 0.01,
    frayScale: 20,
    salt: saltFor(0x1a77c3b9, seed)
  });
  const outcropCoast = coast({
    lobes: [[2, 0.1, 1.1], [3, 0.07, 2.7]],
    fray: 0.012,
    frayScale: 15,
    salt: saltFor(0x66c120d3, seed)
  });

  // Homes sit nearly east/west on the fairness ring so the continent fills an
  // axis-aligned theatre. Expansions take north/south; the shoulders pin the
  // remaining corners.
  const plates = [
    plate({ region: "sunwovenHome", center: coreAnchor(188, 44), radius: 58, depth: 30, coast: homeCoast }),
    plate({ region: "gravemarkHome", center: coreAnchor(8, 44), radius: 56, depth: 30, coast: halfTurned(homeCoast) }),
    plate({
      region: "dominion",
      center: { x: 0, z: 0 },
      radius: 52,
      depth: 22,
      coast: coast({
        lobes: [[2, 0.07, 1.55], [3, 0.04, 0.4]],
        fray: 0.01,
        frayScale: 14,
        salt: saltFor(0x2b849e11, seed)
      })
    }),
    plate({ region: "sunwovenExpansion", center: { x: -8, z: 46 }, radius: 54, depth: 22, coast: expansionCoast }),
    plate({
      region: "gravemarkExpansion",
      center: { x: 12, z: -44 },
      radius: 52,
      depth: 22,
      coast: halfTurned(expansionCoast)
    }),
    plate({ region: null, center: { x: 50, z: 44 }, radius: 46, depth: 18, coast: outcropCoast }),
    plate({ region: null, center: { x: -48, z: -42 }, radius: 48, depth: 18, coast: halfTurned(outcropCoast) })
  ];

  const sunRiver = strait(findPlate(plates, "sunwovenHome"), findPlate(plates, "sunwovenExpansion"), {
    head: 2.6,
    mouth: 6.0,
    inland: 10,
    seaward: 100,
    bow: -5,
    meander: 3.0,
    wander: 1.4,
    wanderScale: 28,
    salt: saltFor(0x7a3c11e5, seed)
  });
  const graveRiver = strait(findPlate(plates, "gravemarkHome"), findPlate(plates, "gravemarkExpansion"), {
    head: 2.8,
    mouth: 4.8,
    inland: 9,
    seaward: 92,
    bow: 4,
    meander: 1.8,
    meanderTurns: 2.0,
    wander: 1.5,
    wanderScale: 22,
    salt: saltFor(0x35c802bf, seed)
  });
  const tarn = basinBody({
    center: { x: -42, z: 30 },
    radius: 4.5,
    outline: coast({
      lobes: [[2, 0.18, 1.1], [3, 0.08, 2.4]],
      fray: 0.06,
      frayScale: 9,
      salt: saltFor(0x4a119c05, seed)
    }),
    wander: 0.9,
    wanderScale: 11,
    salt: saltFor(0x9b27d410, seed)
  });
  const poolOutline = coast({
    lobes: [[2, 0.2, 2.7], [3, 0.08, 0.8]],
    fray: 0.06,
    frayScale: 8,
    salt: saltFor(0x2d5f8b41, seed)
  });
  const pool = basinBody({
    center: { x: 40, z: -18 },
    radius: 5.0,
    outline: poolOutline,
    wander: 0.9,
    wanderScale: 13,
    salt: saltFor(0x2e74c1b8, seed)
  });
  // The pool remains a readable landmark, but it is not a lake without a route
  // out. This short, curved outlet joins the grave river on the near bank.
  const poolOutlet = channelBody({
    path: [
      { x: 40, z: -18 },
      { x: 45, z: -20 },
      { x: 48, z: -24 },
      { x: 47, z: -28 },
      { x: 43, z: -30 }
    ],
    halfWidths: [2.5, 2.4, 2.2, 2.0, 1.8],
    wander: 0.6,
    wanderScale: 12,
    salt: saltFor(0x8e427a19, seed)
  });

  return {
    plates,
    water: [sunRiver, graveRiver, tarn, pool, poolOutlet],
    erosion: erosionOf({ amplitude: 2.6, scale: 44, octaves: 2, bias: 16.5, salt: saltFor(0x6d2b79f5, seed) })
  };
}

/**
 * **Basin.** Lake country: two great void basins either side of the Dominion.
 *
 * One lake on the origin is the shape this map wants and the one shape it cannot
 * have — the fairness contract pins the Dominion there, and a basin centred on it
 * leaves nothing to fight over. A pair keeps the read and the contract, and gives
 * the Dominion a shoreline on both sides.
 */
function basin(seed) {
  const homeCoast = coast({
    lobes: [[2, 0.1, 1.7], [3, 0.06, 0.4], [4, 0.04, 2.1]],
    fray: 0.01,
    frayScale: 23,
    salt: saltFor(0x40b27cd5, seed)
  });
  const expansionCoast = coast({
    lobes: [[2, 0.09, 0.3], [3, 0.06, 1.5], [5, 0.03, 2.7]],
    fray: 0.01,
    frayScale: 19,
    salt: saltFor(0x77e31109, seed)
  });
  const outcropCoast = coast({
    lobes: [[2, 0.1, 2.2], [3, 0.07, 0.7]],
    fray: 0.012,
    frayScale: 15,
    salt: saltFor(0x0cd95ea7, seed)
  });

  // Same rectangular packing as riverlands, rotated bearings so the three maps do
  // not share one silhouette. Lakes sit inland of the fill.
  const plates = [
    plate({ region: "sunwovenHome", center: coreAnchor(200, 46), radius: 58, depth: 29, coast: homeCoast }),
    plate({ region: "gravemarkHome", center: coreAnchor(20, 46), radius: 55, depth: 29, coast: halfTurned(homeCoast) }),
    plate({
      region: "dominion",
      center: { x: 0, z: 0 },
      radius: 50,
      depth: 22,
      coast: coast({
        lobes: [[2, 0.05, 0.2], [3, 0.03, 2.1]],
        fray: 0.01,
        frayScale: 17,
        salt: saltFor(0x11c46be8, seed)
      })
    }),
    plate({ region: "sunwovenExpansion", center: { x: -8, z: 48 }, radius: 54, depth: 22, coast: expansionCoast }),
    plate({
      region: "gravemarkExpansion",
      center: { x: 10, z: -46 },
      radius: 56,
      depth: 22,
      coast: halfTurned(expansionCoast)
    }),
    plate({ region: null, center: { x: 48, z: 46 }, radius: 46, depth: 18, coast: outcropCoast }),
    plate({ region: null, center: { x: -46, z: -44 }, radius: 48, depth: 18, coast: halfTurned(outcropCoast) })
  ];

  const greatLake = basinBody({
    center: { x: -32, z: 12 },
    radius: 9.0,
    outline: coast({
      lobes: [[2, 0.2, 0.65], [3, 0.1, 2.3], [5, 0.05, 1.1]],
      fray: 0.05,
      frayScale: 13,
      salt: saltFor(0x5c902e37, seed)
    }),
    wander: 1.2,
    wanderScale: 22,
    salt: saltFor(0x6e22a18d, seed)
  });
  const farLake = basinBody({
    center: { x: 30, z: -10 },
    radius: 7.5,
    outline: coast({
      lobes: [[2, 0.22, 2.05], [3, 0.09, 0.7], [4, 0.06, 2.6]],
      fray: 0.06,
      frayScale: 11,
      salt: saltFor(0xa6f41d82, seed)
    }),
    wander: 1.2,
    wanderScale: 19,
    salt: saltFor(0x0e8366c1, seed)
  });
  // Arms stay seaward-biased — short inland so home plateaus are not sliced into
  // fight corridors between lake and channel.
  const sunArm = strait(findPlate(plates, "sunwovenHome"), findPlate(plates, "sunwovenExpansion"), {
    head: 3.2,
    mouth: 7.0,
    inland: 6,
    seaward: 36,
    bow: 5,
    meander: 2.6,
    wander: 1.4,
    wanderScale: 28,
    salt: saltFor(0x18af3c60, seed)
  });
  const graveArm = strait(findPlate(plates, "gravemarkHome"), findPlate(plates, "gravemarkExpansion"), {
    head: 3.0,
    mouth: 7.2,
    inland: 7,
    seaward: 34,
    bow: -6,
    meander: 2.0,
    meanderTurns: 2.0,
    wander: 1.4,
    wanderScale: 24,
    salt: saltFor(0x93d75a04, seed)
  });

  return {
    plates,
    water: [greatLake, farLake, sunArm, graveArm],
    erosion: erosionOf({ amplitude: 2.2, scale: 40, octaves: 2, bias: 16.8, salt: saltFor(0x3f19c24b, seed) })
  };
}

/**
 * **Fjords.** A ragged coast bitten into by long void sounds.
 *
 * Nothing here is a lake: every piece of water opens onto the outer void, so the
 * read is all headland and sound. The plates carry the strongest coast profiles of
 * the three and the sounds run narrow and deep, which makes this the most
 * irregular silhouette — and the most defensible interior.
 */
function fjords(seed) {
  const homeCoast = coast({
    lobes: [[2, 0.1, 0.7], [3, 0.06, 2.4], [5, 0.03, 1.2]],
    fray: 0.01,
    frayScale: 19,
    salt: saltFor(0x2c6db913, seed)
  });
  const expansionCoast = coast({
    lobes: [[2, 0.09, 2.0], [3, 0.06, 0.8], [5, 0.03, 2.6]],
    fray: 0.01,
    frayScale: 17,
    salt: saltFor(0x69f044c2, seed)
  });
  const outcropCoast = coast({
    lobes: [[2, 0.1, 0.5], [3, 0.06, 1.8]],
    fray: 0.012,
    frayScale: 13,
    salt: saltFor(0x3e51a8d6, seed)
  });

  const plates = [
    plate({ region: "sunwovenHome", center: coreAnchor(170, 45), radius: 56, depth: 28, coast: homeCoast }),
    plate({ region: "gravemarkHome", center: coreAnchor(-10, 45), radius: 54, depth: 28, coast: halfTurned(homeCoast) }),
    plate({
      region: "dominion",
      center: { x: 0, z: 0 },
      radius: 50,
      depth: 22,
      coast: coast({
        lobes: [[2, 0.05, 1.2], [3, 0.03, 0.3], [5, 0.02, 2.4]],
        fray: 0.01,
        frayScale: 15,
        salt: saltFor(0x59a2d704, seed)
      })
    }),
    plate({ region: "sunwovenExpansion", center: { x: -14, z: -44 }, radius: 54, depth: 22, coast: expansionCoast }),
    plate({
      region: "gravemarkExpansion",
      center: { x: 16, z: 46 },
      radius: 52,
      depth: 22,
      coast: halfTurned(expansionCoast)
    }),
    plate({ region: null, center: { x: 48, z: 48 }, radius: 46, depth: 18, coast: outcropCoast }),
    plate({ region: null, center: { x: -46, z: -46 }, radius: 48, depth: 18, coast: halfTurned(outcropCoast) })
  ];

  // Two primary sounds keep the fjord read; a third inland bite was carving the
  // Dominion approaches into peninsula corridors.
  const sunSound = strait(findPlate(plates, "sunwovenHome"), findPlate(plates, "sunwovenExpansion"), {
    head: 2.4,
    mouth: 5.6,
    inland: 14,
    seaward: 40,
    bow: -6,
    meander: 2.4,
    wander: 1.1,
    wanderScale: 24,
    salt: saltFor(0x44771be9, seed)
  });
  const graveSound = strait(findPlate(plates, "gravemarkHome"), findPlate(plates, "gravemarkExpansion"), {
    head: 2.5,
    mouth: 4.8,
    inland: 10,
    seaward: 34,
    bow: 5,
    meander: 1.8,
    meanderTurns: 1.0,
    wander: 1.2,
    wanderScale: 20,
    salt: saltFor(0xe60b9317, seed)
  });
  const outerBite = strait(findPlate(plates, "sunwovenHome"), plates[5], {
    head: 1.6,
    mouth: 4.0,
    inland: 8,
    seaward: 24,
    bow: -4,
    meander: 1.8,
    wander: 0.9,
    wanderScale: 16,
    salt: saltFor(0x1d937f42, seed)
  });

  return {
    plates,
    water: [sunSound, graveSound, outerBite],
    erosion: erosionOf({ amplitude: 3.2, scale: 32, octaves: 2, bias: 16.0, salt: saltFor(0x8c5106ad, seed) })
  };
}

const LAYOUTS = Object.freeze({ riverlands, basin, fjords });

// MARK: - Sampling grid

/**
 * Metres between land-field samples.
 *
 * `isLand` must be O(1) — movement calls it thousands of times per tick at
 * benchmark density — so the field is evaluated once per grid node at `create()`
 * and every later query is a bilinear read. Half a metre is well inside the
 * narrowest authored feature (a 2.4 m half-width river head) and inside a
 * citizen's 1.15 m footprint, so nothing the rules care about falls between
 * samples. On a ~215 m theatre that is ~190k nodes, about 750 KB.
 */
const GRID_CELL = 0.5;

/** Metres between samples when fitting camera bounds and measuring coverage. */
const FIT_STEP = 2.5;
const COVERAGE_STEP = 1.0;

/**
 * The land fraction the camera rectangle is fitted to (CP-14 band: 75–80%).
 *
 * Swift fits by a proxy — shrink the land AABB until it would drop more than
 * 2.5% of the land cells, then add a rim — and then hand-tunes `retaining` and
 * `rim` per layout until the coverage that falls out lands in the band. Three
 * layouts and a free seed is too many degrees of freedom for two constants: the
 * same pair gave 0.73 / 0.78 / 0.73 here, and re-tuning them per layout would
 * have to be re-done for every seed. Solving for the stated target directly is
 * the same intent with the proxy removed, and it holds across seeds.
 */
const LAND_COVERAGE_TARGET = 0.775;

/**
 * The share of authored land the fit must keep inside the rectangle.
 *
 * The floor is what stops the fit from reaching the coverage band the cheap way,
 * by amputating the coast until only the solid interior is left. When it binds,
 * coverage lands wherever the honest rectangle puts it.
 */
const MIN_RETAINED_LAND = 0.96;

// MARK: - WorldMap

export class WorldMap {
  /**
   * Builds the map for `mapID` under `seedSource`.
   *
   * `seedSource` may be a 64-bit seed `{ hi, lo }` — how `simulation.js` and
   * `snapshot.js` call it — or a `DeterministicRandom` stream, in which case its
   * *state* is read and **no draw is taken**. That is deliberate: the map has to
   * be a pure function of `(mapID, seed)` so a snapshot can store only those two,
   * and a generator that advanced here would hand every later system different
   * numbers depending on whether the map had been rebuilt.
   */
  static create(mapID, seedSource) {
    const id = MAP_IDS.includes(mapID) ? mapID : DEFAULT_MAP_ID;
    const seed = normaliseSeed(seedSource);
    const layout = LAYOUTS[id](seed);
    return new WorldMap(id, seed, layout);
  }

  constructor(id, seed, layout) {
    this.id = id;
    this.seed = seed;
    this.plates = layout.plates;
    this.water = layout.water;
    this.erosion = layout.erosion;

    /** Only the five contract regions own ground; see the file header. */
    this.regionPlates = new Map();
    for (const fragment of this.plates) {
      if (fragment.region === null) continue;
      if (!REGION_IDS.includes(fragment.region)) {
        throw new RangeError(`layout authors an unknown region: ${fragment.region}`);
      }
      this.regionPlates.set(fragment.region, fragment);
    }
    for (const region of REGION_IDS) {
      if (!this.regionPlates.has(region)) {
        throw new RangeError(`layout ${id} is missing authored plate ${region}`);
      }
    }

    this.#buildGrid();
    this.bounds = this.#fitBounds();
    this.coverage = this.#coverageWithin(this.bounds.maxX, this.bounds.maxZ);
    this.retainedLandFraction = this.#measureRetainedLand();
  }

  // MARK: - Land

  /**
   * The signed land field at a point: metres of dry ground, negative in void,
   * zero at the shore. Off the sampled grid it is `-Infinity`.
   *
   * **This is the map's definition of land**, and everything else — the legality
   * tests, the carved mesh, the bank walls, the minimap contour — is a reading of
   * it. Read from the precomputed grid, so it is O(1).
   */
  landField(point) {
    return this.#sampleField(point.x, point.z);
  }

  /** True anywhere a land unit could legally stand, and inside the playable rectangle. */
  isLand(point) {
    const bounds = this.bounds;
    const x = point.x;
    const z = point.z;
    if (x < bounds.minX || x > bounds.maxX || z < bounds.minZ || z > bounds.maxZ) return false;
    return this.#sampleField(x, z) > 0;
  }

  /**
   * The region containing `point`, or `null` when it is off-map or on void.
   *
   * Whether it is land at all is the field's answer, not this one's. This only
   * decides *whose* it is, and the nearer centre wins *relative to its own size*,
   * so boundaries fall midway between neighbours instead of at whichever region
   * happens to come first in the list. A big home plate does not swallow a small
   * neighbour it merely reaches over.
   *
   * There is no `distance <= reach` gate: erosion can push the coast a few metres
   * past every plate's nominal outline, and that ground is real, walkable and has
   * to belong to somebody.
   */
  region(point) {
    if (!this.isLand(point)) return null;
    let best = null;
    let bestScore = Infinity;
    for (const region of REGION_IDS) {
      const fragment = this.regionPlates.get(region);
      const dx = point.x - fragment.center.x;
      const dz = point.z - fragment.center.z;
      const reach = plateReachAtBearing(fragment, Math.atan2(dz, dx));
      const score = Math.sqrt(dx * dx + dz * dz) / Math.max(reach, 0.001);
      if (score < bestScore) {
        bestScore = score;
        best = region;
      }
    }
    return best;
  }

  /** True when `point` lies on solid land owned by `region`. */
  contains(point, region) {
    return this.region(point) === region;
  }

  /**
   * Whether a land unit of `margin` footprint fits at `point`.
   *
   * One test covers both hazards the Swift original split across `isStandable`
   * and `isTraversable`: because the field is `min(ground, -water)`, requiring
   * `margin` metres of it at once keeps a citizen's feet out of a river *and* off
   * the last texel of the outer coast.
   */
  isStandable(point, margin = 0) {
    if (!this.isLand(point)) return false;
    if (!(margin > 0)) return true;
    return this.#sampleField(point.x, point.z) >= Math.max(margin, 0.25);
  }

  /** `isStandable`, additionally requiring the ground belong to `region`. */
  isStandableIn(point, region, margin = 0) {
    if (!this.isStandable(point, margin)) return false;
    return this.region(point) === region;
  }

  /**
   * The nearest point to `proposed` a land unit of `margin` footprint may occupy,
   * or `null` when the map offers none.
   *
   * The contract's signature carries no `from`, so this cannot walk back along an
   * attempted move the way Swift's clamp does. It searches outward in
   * deterministic rings instead — ascending radius, then ascending bearing index,
   * ties broken by the lower index — which is order-independent and so gives the
   * same answer to every caller, but does not inherit the Swift version's
   * guarantee that the result is reachable without crossing water. Movement owns
   * that guarantee; this owns legality.
   */
  clampToLand(point, margin = 0) {
    if (this.isStandable(point, margin)) return { x: point.x, z: point.z };

    const bounds = this.bounds;
    const limit = Math.max(bounds.maxX - bounds.minX, bounds.maxZ - bounds.minZ);
    const samples = 32;
    for (let radius = GRID_CELL; radius <= limit; radius += GRID_CELL * 2) {
      let best = null;
      let bestDistanceSquared = Infinity;
      for (let index = 0; index < samples; index += 1) {
        const bearing = (index / samples) * 2 * Math.PI;
        const candidate = {
          x: point.x + Math.cos(bearing) * radius,
          z: point.z + Math.sin(bearing) * radius
        };
        if (!this.isStandable(candidate, margin)) continue;
        const dx = candidate.x - point.x;
        const dz = candidate.z - point.z;
        const distanceSquared = dx * dx + dz * dz;
        if (distanceSquared < bestDistanceSquared) {
          bestDistanceSquared = distanceSquared;
          best = candidate;
        }
      }
      if (best) return best;
    }
    return null;
  }

  /** The authored anchor of a region — its plate centre, where its Core stands. */
  regionAnchor(region) {
    const fragment = this.regionPlates.get(region);
    if (!fragment) throw new RangeError(`unknown region: ${region}`);
    return { x: fragment.center.x, z: fragment.center.z };
  }

  /**
   * The authored land radius of `region`'s plate in the direction of `point`.
   *
   * Deposit placement measures its outer limit per bearing off this rather than
   * off a fixed radius: a fixed one would put deposits in the void wherever the
   * coast cuts in.
   */
  regionReachToward(region, point) {
    const fragment = this.regionPlates.get(region);
    if (!fragment) throw new RangeError(`unknown region: ${region}`);
    const dx = point.x - fragment.center.x;
    const dz = point.z - fragment.center.z;
    return plateReachAtBearing(fragment, Math.atan2(dz, dx));
  }

  /**
   * Fraction of the playable rectangle that is dry land.
   *
   * This is the coverage the layouts are tuned against (CP-14: 75–80%): land
   * should fill most of the camera map, with rivers, lakes and inlets remaining as
   * readable void cuts rather than dominating the frame.
   */
  landCoverage() {
    return this.coverage;
  }

  // MARK: - Build

  #buildGrid() {
    // A generous first box so a coarse land sample cannot clip headlands; bounds
    // are tightened to the measured land envelope afterwards.
    let extentX = 0;
    let extentZ = 0;
    for (const fragment of this.plates) {
      const reach = plateMaxReach(fragment);
      extentX = Math.max(extentX, Math.abs(fragment.center.x) + reach);
      extentZ = Math.max(extentZ, Math.abs(fragment.center.z) + reach);
    }
    const pad = Math.max(this.erosion.bias + this.erosion.amplitude, 0) + 4;
    extentX += pad;
    extentZ += pad;

    const columns = Math.ceil((extentX * 2) / GRID_CELL) + 3;
    const rows = Math.ceil((extentZ * 2) / GRID_CELL) + 3;
    this.gridColumns = columns;
    this.gridRows = rows;
    this.gridOriginX = -extentX - GRID_CELL;
    this.gridOriginZ = -extentZ - GRID_CELL;
    this.gridExtentX = extentX;
    this.gridExtentZ = extentZ;

    const field = new Float32Array(columns * rows);
    for (let row = 0; row < rows; row += 1) {
      const z = this.gridOriginZ + row * GRID_CELL;
      const base = row * columns;
      for (let column = 0; column < columns; column += 1) {
        field[base + column] = this.#computeField(this.gridOriginX + column * GRID_CELL, z);
      }
    }
    this.field = field;
  }

  /**
   * The land field, evaluated from the authored shapes. Three terms, in order of
   * how much they matter:
   *
   *   1. The deepest plate. `reach - distance` is positive inside a plate's
   *      authored outline, so the max over plates is the union of them.
   *   2. Erosion, added to that union. Because the field is signed, adding to it
   *      moves the *shoreline* rather than any particular plate's outline — which
   *      is what makes seven overlapping plates stop reading as seven overlapping
   *      circles.
   *   3. Water, which wins outright: `-depth` is negative wherever a river or lake
   *      stands, and taking the min subtracts it from the land.
   */
  #computeField(x, z) {
    let ground = -Infinity;
    const plates = this.plates;
    for (let index = 0; index < plates.length; index += 1) {
      const fragment = plates[index];
      const dx = x - fragment.center.x;
      const dz = z - fragment.center.z;
      const reach = plateReachAtBearing(fragment, Math.atan2(dz, dx));
      const inside = reach - Math.sqrt(dx * dx + dz * dz);
      if (inside > ground) ground = inside;
    }

    let deepestWater = -Infinity;
    const water = this.water;
    for (let index = 0; index < water.length; index += 1) {
      const depth = bodyDepth(water[index], x, z);
      if (depth > deepestWater) deepestWater = depth;
    }

    const land = ground + erosionDisplacement(this.erosion, x, z);
    // `deepestWater` is `-Infinity` on a map with no water, so negating it leaves
    // the min a no-op rather than a special case.
    return Math.min(land, -deepestWater);
  }

  /** Bilinear read of the sampled field. O(1); off-grid is void. */
  #sampleField(x, z) {
    const fx = (x - this.gridOriginX) / GRID_CELL;
    const fz = (z - this.gridOriginZ) / GRID_CELL;
    if (!(fx >= 0) || !(fz >= 0)) return -Infinity;
    const column = fx | 0;
    const row = fz | 0;
    if (column >= this.gridColumns - 1 || row >= this.gridRows - 1) return -Infinity;

    const tx = fx - column;
    const tz = fz - row;
    const field = this.field;
    const base = row * this.gridColumns + column;
    const a = field[base];
    const b = field[base + 1];
    const c = field[base + this.gridColumns];
    const d = field[base + this.gridColumns + 1];
    const top = a + (b - a) * tx;
    const bottom = c + (d - c) * tx;
    return top + (bottom - top) * tz;
  }

  /**
   * Camera half-extent fitted so land covers `LAND_COVERAGE_TARGET` of the
   * rectangle, keeping at least `MIN_RETAINED_LAND` of the coast inside it.
   *
   * A raw land AABB always wastes its corners on void — a circular continent can
   * never beat π/4 ≈ 78% of its own box, and an irregular coast sits lower — so
   * the box is scaled off the land envelope, keeping the envelope's aspect. Both
   * searches are on that one scale, and coverage falls monotonically as it grows,
   * so the larger of the two answers satisfies both.
   */
  #fitBounds() {
    const stride = Math.max(1, Math.round(FIT_STEP / GRID_CELL));
    let envelopeX = 0;
    let envelopeZ = 0;
    const landX = [];
    const landZ = [];
    for (let row = 0; row < this.gridRows; row += stride) {
      const z = Math.abs(this.gridOriginZ + row * GRID_CELL);
      const base = row * this.gridColumns;
      for (let column = 0; column < this.gridColumns; column += stride) {
        if (!(this.field[base + column] > 0)) continue;
        const x = Math.abs(this.gridOriginX + column * GRID_CELL);
        landX.push(x);
        landZ.push(z);
        if (x > envelopeX) envelopeX = x;
        if (z > envelopeZ) envelopeZ = z;
      }
    }
    if (landX.length === 0 || envelopeX <= 0 || envelopeZ <= 0) {
      return { minX: -this.gridExtentX, maxX: this.gridExtentX, minZ: -this.gridExtentZ, maxZ: this.gridExtentZ };
    }

    const retainedAt = (scale) => {
      const limitX = envelopeX * scale;
      const limitZ = envelopeZ * scale;
      let kept = 0;
      for (let index = 0; index < landX.length; index += 1) {
        if (landX[index] <= limitX && landZ[index] <= limitZ) kept += 1;
      }
      return kept / landX.length;
    };

    // Smallest scale that still keeps the coast. Monotonically rising in scale,
    // and 1.0 keeps everything by construction, so the bracket is always valid.
    let retainLow = 0.5;
    let retainHigh = 1.0;
    for (let iteration = 0; iteration < 22; iteration += 1) {
      const mid = (retainLow + retainHigh) * 0.5;
      if (retainedAt(mid) >= MIN_RETAINED_LAND) retainHigh = mid;
      else retainLow = mid;
    }

    // Smallest scale whose coverage has fallen to the target. Coverage only ever
    // falls as the box grows, because everything the growth adds is outer void.
    let coverLow = 0.5;
    let coverHigh = 1.7;
    for (let iteration = 0; iteration < 22; iteration += 1) {
      const mid = (coverLow + coverHigh) * 0.5;
      if (this.#coverageWithin(envelopeX * mid, envelopeZ * mid) > LAND_COVERAGE_TARGET) coverLow = mid;
      else coverHigh = mid;
    }

    const scale = Math.max(retainHigh, coverHigh);
    return {
      minX: -envelopeX * scale,
      maxX: envelopeX * scale,
      minZ: -envelopeZ * scale,
      maxZ: envelopeZ * scale
    };
  }

  /** Land fraction of the axis-aligned box of these half-extents. */
  #coverageWithin(halfX, halfZ) {
    let land = 0;
    let total = 0;
    for (let z = -halfZ; z <= halfZ; z += COVERAGE_STEP) {
      for (let x = -halfX; x <= halfX; x += COVERAGE_STEP) {
        total += 1;
        if (this.#sampleField(x, z) > 0) land += 1;
      }
    }
    return total > 0 ? land / total : 0;
  }

  /**
   * How much of the authored land survives the camera fit. Reported so the fit can
   * be judged: a rectangle that hits the coverage band by amputating the coast is
   * not the same result as one that hits it by dropping empty corners.
   */
  #measureRetainedLand() {
    const stride = Math.max(1, Math.round(FIT_STEP / GRID_CELL));
    const bounds = this.bounds;
    let inside = 0;
    let total = 0;
    for (let row = 0; row < this.gridRows; row += stride) {
      const z = this.gridOriginZ + row * GRID_CELL;
      const base = row * this.gridColumns;
      for (let column = 0; column < this.gridColumns; column += stride) {
        if (!(this.field[base + column] > 0)) continue;
        total += 1;
        const x = this.gridOriginX + column * GRID_CELL;
        if (x >= bounds.minX && x <= bounds.maxX && z >= bounds.minZ && z <= bounds.maxZ) inside += 1;
      }
    }
    return total > 0 ? inside / total : 1;
  }
}

/** Accepts a `{ hi, lo }` seed or a `DeterministicRandom`, without drawing from it. */
function normaliseSeed(source) {
  if (source && typeof source.next === "function" && source.state) {
    return { hi: source.state.hi >>> 0, lo: source.state.lo >>> 0 };
  }
  if (source && typeof source.hi === "number" && typeof source.lo === "number") {
    return { hi: source.hi >>> 0, lo: source.lo >>> 0 };
  }
  throw new TypeError("WorldMap.create needs a { hi, lo } seed or a DeterministicRandom");
}
