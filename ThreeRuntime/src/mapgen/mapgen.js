// mapgen/mapgen.js — procedural WorldMap generator for Sunfold Greenfield.
//
// Implements the documented WorldMap contract (AGENTS.md CP-14 / PROJECT_STATE
// / 00-CONTENT-SPEC.md):
//   • One continent cut by void water (rivers, lakes, inlets) — not disc unions.
//   • Land coverage 75–80% of the playable bounds.
//   • Cores equidistant from the Dominion; everything else free to be organic.
//   • Land is civilization-independent (neutral terrain; faction identity lives
//     on units/buildings/HUD).
//   • Provisions + Matter (+Lumen) on the home fragments; Aether ONLY on the
//     expansions, the Dominion and the neutral outcrops (the Voyager map gate).
//   • Docks on the outer coast via a deterministic void finder.
//   • Causeway lanes: home↔expansion dormant until the Outpost weaves them;
//     expansion↔Dominion spine always open. Spars draw only across the wet
//     stretch of a dock-to-dock line — never a slab over dry ground.
//   • Determinism: locked seed 20260726, per-subsystem tagged streams.
//
// Pure logic — no three.js dependency, so the same generator can later feed
// the Swift simulation (it only reads what it produces).

import { stream, fbm2, fnv1a } from './rng.js';

export const CONTRACT = {
  seed: 20260726,
  bounds: { w: 120, h: 90 }, // playable rectangle, metres
  step: 1.5, // grid cell size, metres
  coverageTarget: 0.775, // land fraction of bounds (band 0.75–0.80)
  reliefMax: 2.0, // metres, "relief runs to 2 m"
  plazaKeepClear: 7.5, // metres around each Core ("keep-clear +7.5 m")
  plazaRadius: 11.0, // flat settlement pan radius
};

export const LAYOUTS = ['riverlands', 'basin', 'fjords'];

export const DEPOSIT_KINDS = {
  provisions: { amount: 10000, color: '#e8a33d' }, // ∞ for gameplay; big number here
  matter: { amount: 700, color: '#7a8b99' },
  lumen: { amount: 550, color: '#f2d06b' },
  aether: { amount: 180, color: '#9d8cff' },
};

export const REGION_NAMES = {
  hs: 'home-sunwoven',
  hg: 'home-gravemark',
  es: 'expansion-sunwoven',
  eg: 'expansion-gravemark',
  do: 'dominion',
  n1: 'neutral-1',
  n2: 'neutral-2',
  open: 'open',
};

/* ------------------------------------------------------------------ *
 *  Grid helpers                                                       *
 * ------------------------------------------------------------------ */

function makeGrid(opts) {
  const { bounds, step } = opts;
  const cols = Math.round(bounds.w / step);
  const rows = Math.round(bounds.h / step);
  const halfW = bounds.w / 2;
  const halfH = bounds.h / 2;
  const idx = (c, r) => r * cols + c;
  return {
    cols, rows, halfW, halfH,
    col: (x) => Math.min(cols - 1, Math.max(0, Math.floor((x + halfW) / step))),
    row: (z) => Math.min(rows - 1, Math.max(0, Math.floor((z + halfH) / step))),
    cx: (c) => -halfW + (c + 0.5) * step,
    cz: (r) => -halfH + (r + 0.5) * step,
    idx,
    inBounds: (c, r) => c >= 0 && r >= 0 && c < cols && r < rows,
  };
}

/* ------------------------------------------------------------------ *
 *  Coast field: gaussian lobes + void bodies + erosion                *
 * ------------------------------------------------------------------ */

/** Gaussian-blob continent field. Land where field ≥ threshold. */
function continentField(x, z, lobes) {
  let s = 0;
  for (const l of lobes) {
    const dx = (x - l.cx) / l.sx;
    const dz = (z - l.cz) / l.sz;
    s += l.w * Math.exp(-0.5 * (dx * dx + dz * dz));
  }
  return s;
}

/** Signed distance to a polyline. */
function distToPolyline(x, z, pts) {
  let best = Infinity;
  for (let i = 0; i < pts.length - 1; i++) {
    const [ax, az] = pts[i];
    const [bx, bz] = pts[i + 1];
    const abx = bx - ax, abz = bz - az;
    const len2 = abx * abx + abz * abz;
    let t = ((x - ax) * abx + (z - az) * abz) / len2;
    t = Math.max(0, Math.min(1, t));
    const px = ax + t * abx, pz = az + t * abz;
    const d = Math.hypot(x - px, z - pz);
    if (d < best) best = d;
  }
  return best;
}

/** Ellipse distance (normalized < 1 inside). */
function ellipseField(x, z, e) {
  const dx = (x - e.cx) / e.rx;
  const dz = (z - e.cz) / e.rz;
  return dx * dx + dz * dz;
}

/**
 * Build the land mask:
 *   1. gaussian coast lobes (organic continent, not disc union),
 *   2. carve void bodies (rivers / lakes / inlets),
 *   3. morphological erosion to make coasts ragged and natural.
 * Returns { land, coverage }.
 */
function buildLand(opts, lobes, voidBodies, scale) {
  const g = makeGrid(opts);
  const land = new Uint8Array(g.cols * g.rows);
  const threshold = 0.55;
  const applied = lobes.map((l) => ({
    ...l, sx: l.sx * scale, sz: l.sz * scale,
  }));
  for (let r = 0; r < g.rows; r++) {
    const z = g.cz(r);
    for (let c = 0; c < g.cols; c++) {
      const x = g.cx(c);
      let isLand = continentField(x, z, applied) >= threshold;
      if (isLand) {
        // carve void bodies
        for (const v of voidBodies) {
          if (v.kind === 'river') {
            const w = v.width(x, z);
            if (distToPolyline(x, z, v.pts) < w) { isLand = false; break; }
          } else if (v.kind === 'lake') {
            if (ellipseField(x, z, v) < 1) { isLand = false; break; }
          } else if (v.kind === 'ring') {
            // donut lake: carve annulus, keep the island inside
            const d = Math.hypot(x - v.cx, z - v.cz);
            if (d > v.inner && d < v.outer) { isLand = false; break; }
          }
        }
      }
      land[g.idx(c, r)] = isLand ? 1 : 0;
    }
  }
  // erosion: erode → dilate → erode (crisp but organic coasts)
  let cur = land;
  for (const pass of ['erode', 'dilate', 'erode']) {
    const next = new Uint8Array(g.cols * g.rows);
    for (let r = 0; r < g.rows; r++) {
      for (let c = 0; c < g.cols; c++) {
        let n = 0;
        for (let dr = -1; dr <= 1; dr++) {
          for (let dc = -1; dc <= 1; dc++) {
            if (dr === 0 && dc === 0) continue;
            const rr = r + dr, cc = c + dc;
            if (g.inBounds(cc, rr) && cur[g.idx(cc, rr)]) n++;
          }
        }
        const self = cur[g.idx(c, r)];
        if (pass === 'erode') next[g.idx(c, r)] = self && n >= 4 ? 1 : 0;
        else next[g.idx(c, r)] = self || n >= 6 ? 1 : 0;
      }
    }
    cur = next;
  }
  // scallop the map border so no straight edge parallels the frame
  // (the island must read as carved rock, not a rectangular board)
  {
    const border = 3;
    for (let r = 0; r < g.rows; r++) {
      for (let c = 0; c < g.cols; c++) {
        if (!cur[g.idx(c, r)]) continue;
        const dEdge = Math.min(c, g.cols - 1 - c, r, g.rows - 1 - r);
        if (dEdge < border && fbm2(g.cx(c) * 0.16, g.cz(r) * 0.16, 0x5eedc0de ^ 0) > 0.42 + dEdge * 0.12) {
          cur[g.idx(c, r)] = 0;
        }
      }
    }
  }
  let count = 0;
  for (let i = 0; i < cur.length; i++) count += cur[i];
  return { land: cur, coverage: count / cur.length };
}

/* ------------------------------------------------------------------ *
 *  Heights                                                            *
 * ------------------------------------------------------------------ */

/**
 * Relief runs to reliefMax, pinned to zero across the settlement plazas,
 * dock landings, and banks. distToVoid via BFS from void cells.
 */
function buildHeights(opts, land, anchors, docks, reliefRng) {
  const g = makeGrid(opts);
  const h = new Float32Array(g.cols * g.rows);
  const dist = new Float32Array(g.cols * g.rows).fill(1e9);
  // BFS from void cells
  const q = [];
  for (let i = 0; i < land.length; i++) {
    if (!land[i]) { dist[i] = 0; q.push(i); }
  }
  for (let head = 0; head < q.length; head++) {
    const i = q[head];
    const c = i % g.cols, r = (i / g.cols) | 0;
    for (let dr = -1; dr <= 1; dr++) {
      for (let dc = -1; dc <= 1; dc++) {
        if (dr === 0 && dc === 0) continue;
        const cc = c + dc, rr = r + dr;
        if (!g.inBounds(cc, rr)) continue;
        const ni = g.idx(cc, rr);
        if (land[ni] && dist[ni] > dist[i] + 1) { dist[ni] = dist[i] + 1; q.push(ni); }
      }
    }
  }
  for (let r = 0; r < g.rows; r++) {
    const z = g.cz(r);
    for (let c = 0; c < g.cols; c++) {
      const i = g.idx(c, r);
      if (!land[i]) { h[i] = 0; continue; }
      const x = g.cx(c);
      const d = dist[i] * opts.step;
      // characterful relief: rolling macro-dunes + mid detail + fine grain,
      // with a raised rim lip near the coast (carved golden-stone continent)
      const macro = Math.max(0, fbm2(x * 0.042 + 9.2, z * 0.042 - 3.1, reliefRng.seed ^ 0x51f) - 0.38) * 2.0;
      const n = fbm2(x * 0.14, z * 0.14, reliefRng.seed);
      const far = Math.pow(Math.min(d / 34, 1), 1.5);
      let hh = opts.reliefMax * (0.42 * Math.pow(macro, 1.2) + 0.38 * Math.pow(Math.min(d / 20, 1), 1.2) * (0.35 + 0.65 * n) + 0.20 * far);
      // rim lip: raised band ~3–12 m from the water's edge, gentler ramp
      const rim = Math.exp(-Math.pow((d - 6.5) / 4.5, 2)) * 0.5 * (1 - Math.min(d / 3.5, 1));
      hh += rim;
      // plaza flats
      for (const a of anchors) {
        if (!a.plaza) continue;
        const dp = Math.hypot(x - a.cx, z - a.cz);
        if (dp < opts.plazaRadius) hh = 0;
        else if (dp < opts.plazaRadius + 4) hh *= (dp - opts.plazaRadius) / 4;
      }
      // dock landing flats
      for (const dk of docks) {
        const dd = Math.hypot(x - dk.landX, z - dk.landZ);
        if (dd < 5) hh = 0;
        else if (dd < 8) hh *= (dd - 5) / 3;
      }
      // low banks at the water's edge
      if (d < 1.6) hh = Math.min(hh, 0.12);
      h[i] = Math.min(hh, opts.reliefMax);
    }
  }
  return h;
}

/* ------------------------------------------------------------------ *
 *  Regions                                                            *
 * ------------------------------------------------------------------ */

function buildRegions(opts, land, anchors) {
  const g = makeGrid(opts);
  const reg = new Array(g.cols * g.rows).fill(0);
  for (let r = 0; r < g.rows; r++) {
    const z = g.cz(r);
    for (let c = 0; c < g.cols; c++) {
      const i = g.idx(c, r);
      if (!land[i]) { reg[i] = 0; continue; }
      const x = g.cx(c);
      let best = null, bestD = Infinity;
      for (let a = 0; a < anchors.length; a++) {
        const an = anchors[a];
        const d = Math.hypot(x - an.cx, z - an.cz);
        if (d < an.regionR && d < bestD) { bestD = d; best = a; }
      }
      reg[i] = best === null ? 'open' : anchors[best].id;
    }
  }
  return reg;
}

/* ------------------------------------------------------------------ *
 *  Docks + causeway lanes                                             *
 * ------------------------------------------------------------------ */

/** Distance from point to segment AB. */
function distToSegment(x, z, ax, az, bx, bz) {
  const abx = bx - ax, abz = bz - az;
  const len2 = abx * abx + abz * abz || 1;
  const t = Math.max(0, Math.min(1, ((x - ax) * abx + (z - az) * abz) / len2));
  return Math.hypot(x - (ax + abx * t), z - (az + abz * t));
}

/**
 * Deterministic void finder: dock on the outer coast of a region, biased
 * toward the lane line so docks face each other across the channel.
 * laneA/laneB are the two region centres of the lane.
 */
function findDock(opts, land, regionMap, regionId, laneA, laneB) {
  const g = makeGrid(opts);
  let best = null, bestScore = Infinity;
  for (let r = 0; r < g.rows; r++) {
    const z = g.cz(r);
    for (let c = 0; c < g.cols; c++) {
      const i = g.idx(c, r);
      if (!land[i] || regionMap[i] !== regionId) continue;
      // adjacent to void?
      let touchesVoid = false, voidCell = -1, voidBest = Infinity;
      for (let dr = -1; dr <= 1; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          const cc = c + dc, rr = r + dr;
          if (!g.inBounds(cc, rr)) continue;
          const ni = g.idx(cc, rr);
          if (!land[ni]) {
            touchesVoid = true;
            const dx = g.cx(cc) - laneB.cx, dz = g.cz(rr) - laneB.cz;
            const d = dx * dx + dz * dz;
            if (d < voidBest) { voidBest = d; voidCell = ni; }
          }
        }
      }
      if (!touchesVoid) continue;
      const x = g.cx(c);
      const s2 = Math.hypot(x - laneB.cx, z - laneB.cz) + 2.0 * distToSegment(x, z, laneA.cx, laneA.cz, laneB.cx, laneB.cz);
      if (s2 < bestScore) {
        bestScore = s2;
        best = {
          region: regionId,
          landX: x, landZ: z,
          voidX: g.cx(voidCell % g.cols), voidZ: g.cz((voidCell / g.cols) | 0),
        };
      }
    }
  }
  return best;
}

/** Wet-run spars along a dock-to-dock line: only over void cells. */
function buildSpars(opts, land, a, b) {
  const g = makeGrid(opts);
  const dx = b.voidX - a.voidX, dz = b.voidZ - a.voidZ;
  const len = Math.hypot(dx, dz);
  const n = Math.max(2, Math.round(len / (opts.step * 0.5)));
  const spars = [];
  let runStart = null, prev = null;
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const x = a.voidX + dx * t, z = a.voidZ + dz * t;
    const c = g.col(x), r = g.row(z);
    const wet = !land[g.idx(c, r)];
    if (wet) {
      if (runStart === null) runStart = { x, z };
      prev = { x, z };
    } else if (runStart !== null && prev !== null) {
      pushRun(spars, runStart, prev);
      runStart = null; prev = null;
    }
  }
  if (runStart !== null && prev !== null) pushRun(spars, runStart, prev);
  // A6: every spar's midpoint must sit over void — the bank cells are ragged,
  // so drop segments whose midpoint cell is land (validates what the assert
  // checks: landAt((x1+x2)/2, (z1+z2)/2))
  return spars.filter((s) => {
    const c = g.col((s.x1 + s.x2) / 2), r = g.row((s.z1 + s.z2) / 2);
    return !land[g.idx(c, r)];
  });
}

/** Chunk a wet run into ≤ 4 m deck segments. */
function pushRun(spars, from, to) {
  const dx = to.x - from.x, dz = to.z - from.z;
  const len = Math.hypot(dx, dz);
  if (len < 0.75) return;
  const segs = Math.ceil(len / 4);
  for (let s = 0; s < segs; s++) {
    const t0 = s / segs, t1 = (s + 1) / segs;
    spars.push({
      x1: from.x + dx * t0, z1: from.z + dz * t0,
      x2: from.x + dx * t1, z2: from.z + dz * t1,
    });
  }
}

/* ------------------------------------------------------------------ *
 *  Deposits                                                            *
 * ------------------------------------------------------------------ */

function placeDeposit(opts, land, baseX, baseZ, angle, radius, depRng, g) {
  let x = baseX + Math.cos(angle) * radius;
  let z = baseZ + Math.sin(angle) * radius;
  const c0 = g.col(x), r0 = g.row(z);
  if (land[g.idx(c0, r0)]) return { x, z };
  // march inward along the ray, then outward, until land
  for (let s = 1; s <= 8; s++) {
    const xi = baseX + Math.cos(angle) * (radius - s * 0.75);
    const zi = baseZ + Math.sin(angle) * (radius - s * 0.75);
    if (land[g.idx(g.col(xi), g.row(zi))]) return { x: xi, z: zi };
  }
  for (let s = 1; s <= 8; s++) {
    const xo = baseX + Math.cos(angle) * (radius + s * 0.75);
    const zo = baseZ + Math.sin(angle) * (radius + s * 0.75);
    if (land[g.idx(g.col(xo), g.row(zo))]) return { x: xo, z: zo };
  }
  return { x: baseX, z: baseZ }; // degenerate: will be flagged by assertions
}

function buildDeposits(opts, land, anchors, rng) {
  const g = makeGrid(opts);
  const out = [];
  const kinds = ['provisions', 'provisions', 'matter', 'matter', 'lumen'];
  for (const a of anchors) {
    if (!a.deposits) continue;
    const r = rng();
    const base = rng();
    for (let k = 0; k < a.deposits.length; k++) {
      const kind = a.deposits[k];
      const angle = (k / a.deposits.length) * Math.PI * 2 + (base - 0.5) * 0.7 + r * 0.001 * k;
      const radius = a.depositR + (rng() - 0.5) * 6;
      const p = placeDeposit(opts, land, a.cx, a.cz, angle, radius, rng, g);
      out.push({
        id: `${a.id}-${kind}-${k}`,
        kind,
        amount: DEPOSIT_KINDS[kind].amount,
        x: p.x, z: p.z,
        region: a.id,
      });
    }
  }
  return out;
}

/* ------------------------------------------------------------------ *
 *  Layouts                                                            *
 * ------------------------------------------------------------------ */

const ANCHOR_SHARED = {
  dominion: { id: 'do', cx: 0, cz: 0, regionR: 13, plaza: true },
  homeSunwoven: { id: 'hs', cx: -32, cz: 14, regionR: 14, plaza: true },
  homeGravemark: { id: 'hg', cx: 32, cz: -14, regionR: 14, plaza: true },
  neutral1: { id: 'n1', cx: 0, cz: 38, regionR: 9 },
  neutral2: { id: 'n2', cx: 0, cz: -38, regionR: 9 },
};

function anchorsFor(layout) {
  const a = {
    ...ANCHOR_SHARED,
    expansionSunwoven: { id: 'es', cx: -50, cz: 30, regionR: 11 },
    expansionGravemark: { id: 'eg', cx: 50, cz: -30, regionR: 11 },
  };
  a.expansionSunwoven.deposits = ['matter', 'lumen', 'aether'];
  a.expansionGravemark.deposits = ['matter', 'lumen', 'aether'];
  a.dominion.deposits = ['aether'];
  a.neutral1.deposits = ['matter', 'aether'];
  a.neutral2.deposits = ['matter', 'aether'];
  a.homeSunwoven.deposits = ['provisions', 'provisions', 'matter', 'matter', 'lumen'];
  a.homeGravemark.deposits = ['provisions', 'provisions', 'matter', 'matter', 'lumen'];
  a.homeSunwoven.depositR = 14;
  a.homeGravemark.depositR = 14;
  a.expansionSunwoven.depositR = 10;
  a.expansionGravemark.depositR = 10;
  a.dominion.depositR = 7;
  a.neutral1.depositR = 6;
  a.neutral2.depositR = 6;
  if (layout === 'basin') {
    a.expansionSunwoven = { ...a.expansionSunwoven, cx: -50, cz: 22 };
    a.expansionGravemark = { ...a.expansionGravemark, cx: 50, cz: -22 };
  }
  if (layout === 'riverlands') {
    // expansions sit north/south of the homes, clear of the corner water
    // (the opening frames the home with void on its far side — P1)
    a.expansionSunwoven = { ...a.expansionSunwoven, cx: -36, cz: 34, regionR: 11 };
    a.expansionGravemark = { ...a.expansionGravemark, cx: 36, cz: -34, regionR: 11 };
  }
  if (layout === 'fjords') {
    a.expansionSunwoven = { ...a.expansionSunwoven, cx: -52, cz: 28 };
    a.expansionGravemark = { ...a.expansionGravemark, cx: 52, cz: -28 };
  }
  return a;
}

function lobesFor(layout) {
  if (layout === 'riverlands') {
    return [
      { cx: 12, cz: -6, sx: 46, sz: 34.5, w: 1.0 }, // main mass (east/south)
      // NW/SE home masses — pulled off the map corners (P1: the opening
      // frames the settlement with void on its far side; the corners are
      // open water so sky + rim read behind the home)
      { cx: -24, cz: 16, sx: 28, sz: 17, w: 0.95 }, // NW: sunwoven home
      { cx: 24, cz: -16, sx: 28, sz: 17, w: 0.95 }, // SE: gravemark home
      { cx: -36, cz: 34, sx: 12, sz: 14, w: 1.0 },  // sunwoven expansion lobe
      { cx: 36, cz: -34, sx: 12, sz: 14, w: 1.0 },  // gravemark expansion lobe
      { cx: 0, cz: 38, sx: 13, sz: 8, w: 0.85 },    // neutral-1 bump
      { cx: 0, cz: -38, sx: 13, sz: 8, w: 0.85 },   // neutral-2 bump
    ];
  }
  if (layout === 'basin') {
    return [
      { cx: 0, cz: -20, sx: 36, sz: 20, w: 1.0 },   // south mass
      { cx: 0, cz: 20, sx: 36, sz: 20, w: 1.0 },    // north mass
      { cx: -52, cz: 0, sx: 15, sz: 25, w: 0.95 },  // west arm
      { cx: 52, cz: 0, sx: 15, sz: 25, w: 0.95 },   // east arm
      { cx: 0, cz: 40, sx: 11, sz: 7, w: 0.85 },
      { cx: 0, cz: -40, sx: 11, sz: 7, w: 0.85 },
    ];
  }
  // fjords
  return [
    { cx: -4, cz: -2, sx: 49, sz: 35, w: 1.0 },     // central continent
    { cx: -48, cz: 28, sx: 13, sz: 15, w: 0.9 },    // sunwoven expansion peninsula
    { cx: 48, cz: -28, sx: 13, sz: 15, w: 0.9 },    // gravemark expansion peninsula
    { cx: -30, cz: 24, sx: 24, sz: 13, w: 0.85 },   // NW bridge (peninsula neck)
    { cx: 30, cz: -24, sx: 24, sz: 13, w: 0.85 },   // SE bridge
    { cx: 0, cz: 40, sx: 10, sz: 7, w: 0.85 },
    { cx: 0, cz: -40, sx: 10, sz: 7, w: 0.85 },
  ];
}

function voidsFor(layout) {
  const river = (pts, w0, w1) => ({
    kind: 'river',
    pts,
    width: (x, z) => {
      // taper along the polyline by projected progress
      let total = 0;
      for (let i = 1; i < pts.length; i++) total += Math.hypot(pts[i][0] - pts[i-1][0], pts[i][1] - pts[i-1][1]);
      let best = 0, d = 0;
      for (let i = 1; i < pts.length; i++) {
        d += Math.hypot(pts[i][0] - pts[i-1][0], pts[i][1] - pts[i-1][1]);
        // find projection of (x,z) onto segment i-1..i
        const [ax, az] = pts[i-1], [bx, bz] = pts[i];
        const abx = bx - ax, abz = bz - az;
        const len2 = abx*abx + abz*abz || 1;
        const t = Math.max(0, Math.min(1, ((x - ax)*abx + (z - az)*abz) / len2));
        const u = (d - (1 - t) * Math.hypot(abx, abz)) / total;
        if (u > best) best = u;
      }
      return w0 + (w1 - w0) * best;
    },
  });
  const lake = (e) => ({ kind: 'lake', ...e });
  if (layout === 'riverlands') {
    return [
      // bay between sunwoven home and its expansion — starts in the open
      // water of the map corner, channels north of the home, cuts the
      // separation between home and expansion (P1: wide, reads as space)
      river([[-63, 40], [-52, 37], [-42, 32], [-36, 27]], 6.5, 3.0),
      // mirrored bay between gravemark home and its expansion
      river([[63, -40], [52, -37], [42, -32], [36, -27]], 6.5, 3.0),
      // small flank tarns, away from cores
      lake({ cx: -14, cz: 8, rx: 5.0, rz: 3.6 }),
      lake({ cx: 14, cz: -8, rx: 5.0, rz: 3.6 }),
      // interior river for character (short, off the lanes)
      river([[-2, 34], [8, 30], [14, 24]], 3.6, 2.2),
    ];
  }
  if (layout === 'basin') {
    return [
      { kind: 'ring', cx: 0, cz: 0, inner: 7.5, outer: 16 }, // great lake ring around the Dominion island
      river([[-9, 2], [-24, 6], [-40, 12], [-52, 19]], 5.8, 3.0),  // west arm: home↔expansion channel
      river([[9, -2], [24, -6], [40, -12], [52, -19]], 5.8, 3.0),   // east arm
      river([[0, 10], [4, 22], [3, 34]], 4.2, 2.4),                 // north arm
      river([[0, -10], [-4, -22], [-3, -34]], 4.2, 2.4),            // south arm
    ];
  }
  // fjords
  return [
    river([[-40, 45], [-44, 36], [-44, 22.5]], 6.0, 2.8), // NW sound (home↔expansion separation)
    river([[40, -45], [44, -36], [44, -22.5]], 6.0, 2.8), // SE sound
    river([[-12, 45], [-9, 34], [-5, 24]], 3.8, 2.2),     // north sound
    river([[12, -45], [9, -34], [5, -24]], 3.8, 2.2),     // south sound
  ];
}

/* ------------------------------------------------------------------ *
 *  Main entry                                                         *
 * ------------------------------------------------------------------ */

export function generateMap(opts = {}) {
  const seed = opts.seed ?? CONTRACT.seed;
  const layout = opts.layout ?? 'riverlands';
  if (!LAYOUTS.includes(layout)) throw new Error(`unknown layout: ${layout}`);

  const cfg = { ...CONTRACT, seed, layout };
  const g = makeGrid(cfg);

  const lobes = lobesFor(layout);
  const voidBodies = voidsFor(layout);
  const anchors = Object.values(anchorsFor(layout));

  // Solve the coast-lobe scale so final coverage lands in the 75–80% band.
  // A closed-form σ² scaling is wrong when lobes overlap heavily, so iterate:
  // coverage ≈ raw0·s² only locally, and each buildLand is cheap.
  const TARGET = 0.775;
  let scale = 1.0;
  let land, coverage;
  for (let i = 0; i < 4; i++) {
    const r = buildLand(cfg, lobes, voidBodies, scale);
    land = r.land; coverage = r.coverage;
    const err = coverage - TARGET;
    if (Math.abs(err) < 0.004) break;
    scale = Math.min(1.35, Math.max(0.85, scale * Math.sqrt(TARGET / coverage)));
  }

  const reliefRng = stream(seed, `relief-${layout}`);
  const depRng = stream(seed, `deposits-${layout}`);
  const starRng = stream(seed, `stars-${layout}`);

  // Docks + lanes
  const lanes = [
    { id: 'lane-hs-es', a: 'hs', b: 'es', dormant: true },
    { id: 'lane-hg-eg', a: 'hg', b: 'eg', dormant: true },
    { id: 'lane-es-do', a: 'es', b: 'do', dormant: false },
    { id: 'lane-eg-do', a: 'eg', b: 'do', dormant: false },
  ];
  const regionByAnchor = {};
  for (const a of anchors) regionByAnchor[a.id] = a;

  // pass 1: regions needed for the dock finder
  const regionMap = buildRegions(cfg, land, anchors);

  const docks = {};
  for (const lane of lanes) {
    const a = regionByAnchor[lane.a];
    const b = regionByAnchor[lane.b];
    // A region with no coast (landlocked, e.g. the riverlands Dominion)
    // simply has no dock: the crossing is dry land and spars are suppressed.
    docks[lane.a] = docks[lane.a] || findDock(cfg, land, regionMap, lane.a, a, b);
    docks[lane.b] = docks[lane.b] || findDock(cfg, land, regionMap, lane.b, a, b);
  }

  const causeways = lanes.map((lane) => {
    const da = docks[lane.a], db = docks[lane.b];
    const spars = da && db ? buildSpars(cfg, land, da, db) : [];
    return { id: lane.id, a: lane.a, b: lane.b, dormant: lane.dormant, spars };
  });

  const dockList = Object.values(docks).filter(Boolean);
  const heights = buildHeights(cfg, land, anchors, dockList, reliefRng);

  // Deposits (needs anchors + land; region tag from nearest anchor)
  const deposits = buildDeposits(cfg, land, anchors, depRng);

  // Starfield plan (drawn by the renderer from these params)
  const starfield = {
    count: 650,
    seed: starRng().toString(36),
    bodyAngle: starRng() * Math.PI * 2,
    bodyRadius: 140 + starRng() * 60,
    nebulaCount: 3,
  };

  const cores = [
    { id: 'hs', faction: 'sunwoven', x: -32, z: 14 },
    { id: 'hg', faction: 'gravemark', x: 32, z: -14 },
  ];
  const dominion = { x: 0, z: 0 };

  // Map identity hash (determinism check)
  const parts = [seed, layout];
  for (let i = 0; i < land.length; i += 2) parts.push(land[i]);
  for (let i = 0; i < heights.length; i += 4) parts.push(heights[i].toFixed(3));
  for (const d of deposits) parts.push(d.kind, d.x.toFixed(2), d.z.toFixed(2));
  for (const dk of dockList) parts.push(dk.landX.toFixed(2), dk.landZ.toFixed(2));
  for (const cw of causeways) for (const s of cw.spars) parts.push(s.x1.toFixed(2), s.z1.toFixed(2), s.x2.toFixed(2), s.z2.toFixed(2));

  const stats = {
    coverage,
    landCells: land.reduce((s, v) => s + v, 0),
    totalCells: land.length,
    reliefMax: Math.max(...heights),
    deposits: deposits.length,
    docks: dockList.length,
    spars: causeways.reduce((s, c) => s + c.spars.length, 0),
  };

  return {
    contract: cfg,
    grid: { cols: g.cols, rows: g.rows, step: cfg.step, bounds: cfg.bounds, col: g.col, row: g.row },
    land, heights, regions: regionMap,
    anchors, cores, dominion,
    deposits, docks: dockList, causeways,
    starfield,
    stats,
    hash: fnv1a(parts.join('|')),
    // cell lookups for the renderer / assertions
    landAt(x, z) { return !!land[g.idx(g.col(x), g.row(z))]; },
    heightAt(x, z) { return heights[g.idx(g.col(x), g.row(z))]; },
    regionAt(x, z) { return regionMap[g.idx(g.col(x), g.row(z))]; },
    regionName(id) { return REGION_NAMES[id] || String(id); },
  };
}

/** Two generations from the same seed must hash identically. */
export function determinismCheck(seed = CONTRACT.seed, layout = 'riverlands') {
  const a = generateMap({ seed, layout });
  const b = generateMap({ seed, layout });
  return { ok: a.hash === b.hash, hash: a.hash };
}

/** Tuning aid: report the solved scale for a layout. */
export function debugScale(layout, seed = CONTRACT.seed) {
  const cfg = { ...CONTRACT, seed, layout };
  const TARGET = 0.775;
  let scale = 1.0, cov = 0;
  for (let i = 0; i < 4; i++) {
    const r = buildLand(cfg, lobesFor(layout), voidsFor(layout), scale);
    cov = r.coverage;
    if (Math.abs(cov - TARGET) < 0.004) break;
    scale = Math.min(1.35, Math.max(0.85, scale * Math.sqrt(TARGET / cov)));
  }
  return { raw0: buildLand(cfg, lobesFor(layout), [], 1.0).coverage, scale, solvedCoverage: cov };
}
