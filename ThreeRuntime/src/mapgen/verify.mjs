// mapgen/verify.mjs — contract assertion runner (node).
// Mirrors the lab's assertion panel so tuning can iterate without a browser.
import { generateMap, determinismCheck, CONTRACT, LAYOUTS } from './mapgen.js';

function landBFS(map, fromX, fromZ, toX, toZ) {
  const { cols, rows } = map.grid;
  const idx = (c, r) => r * cols + c;
  const start = idx(map.grid.col(fromX), map.grid.row(fromZ));
  const goal = idx(map.grid.col(toX), map.grid.row(toZ));
  if (!map.land[start] || !map.land[goal]) return false;
  const seen = new Uint8Array(cols * rows);
  const q = [start]; seen[start] = 1;
  for (let h = 0; h < q.length; h++) {
    const i = q[h];
    if (i === goal) return true;
    const c = i % cols, r = (i / cols) | 0;
    for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
      if (!dr && !dc) continue;
      const cc = c + dc, rr = r + dr;
      if (cc < 0 || rr < 0 || cc >= cols || rr >= rows) continue;
      const ni = idx(cc, rr);
      if (map.land[ni] && !seen[ni]) { seen[ni] = 1; q.push(ni); }
    }
  }
  return false;
}

export function runAsserts(map, layout) {
  const A = [];
  const bounds = map.grid.bounds;
  const byId = {}; for (const a of map.anchors) byId[a.id] = a;
  const add = (name, ok, detail) => A.push({ name, ok, detail });

  add('A1 coverage 75-80%', map.stats.coverage >= 0.75 && map.stats.coverage <= 0.80, (map.stats.coverage * 100).toFixed(1) + '%');

  const d1 = Math.hypot(map.cores[0].x - map.dominion.x, map.cores[0].z - map.dominion.z);
  const d2 = Math.hypot(map.cores[1].x - map.dominion.x, map.cores[1].z - map.dominion.z);
  add('A2 cores equidistant', Math.abs(d1 - d2) < 0.5, `${d1.toFixed(1)}/${d2.toFixed(1)}`);

  const aetherBad = map.deposits.filter(d => d.kind === 'aether' && !['es', 'eg', 'do', 'n1', 'n2'].includes(d.region));
  add('A3 aether gated off home', aetherBad.length === 0, `${map.deposits.filter(d => d.kind === 'aether').length} aether`);

  const offLand = map.deposits.filter(d => !map.landAt(d.x, d.z));
  add('A4 deposits on land', offLand.length === 0, `${map.deposits.length} deposits`);

  const badDocks = map.docks.filter(d => !map.landAt(d.landX, d.landZ) || map.landAt(d.voidX, d.voidZ));
  add('A5 docks on coast', badDocks.length === 0, `${map.docks.length} docks`);

  let badSpars = 0;
  for (const lane of map.causeways) for (const s of lane.spars) {
    if (map.landAt((s.x1 + s.x2) / 2, (s.z1 + s.z2) / 2)) badSpars++;
  }
  add('A6 spars only over void', badSpars === 0, `${map.stats.spars} spars`);

  const reliefOK = map.stats.reliefMax <= 2.05;
  let plazaMax = 0;
  for (const core of map.cores) {
    for (let r = 0; r < map.grid.rows; r += 2) for (let c = 0; c < map.grid.cols; c += 2) {
      const h = map.heights[r * map.grid.cols + c];
      const x = -bounds.w / 2 + (c + 0.5) * map.grid.step, z = -bounds.h / 2 + (r + 0.5) * map.grid.step;
      if (Math.hypot(x - core.x, z - core.z) < 8) plazaMax = Math.max(plazaMax, Math.abs(h));
    }
  }
  add('A7 relief/plazas', reliefOK && plazaMax < 0.05, `max ${map.stats.reliefMax.toFixed(2)} plaza ${plazaMax.toFixed(3)}`);

  add('A8 determinism', determinismCheck(map.contract.seed, layout).ok, map.hash.slice(0, 8));

  const es = byId['es'], eg = byId['eg'], dA = byId['do'];
  const lES = map.causeways.find(l => l.id === 'lane-es-do');
  const lEG = map.causeways.find(l => l.id === 'lane-eg-do');
  const rES = landBFS(map, es.cx, es.cz, dA.cx, dA.cz) || (!lES.dormant && lES.spars.length > 0);
  const rEG = landBFS(map, eg.cx, eg.cz, dA.cx, dA.cz) || (!lEG.dormant && lEG.spars.length > 0);
  add('A9 expansion->Dominion open', rES && rEG, `${landBFS(map, es.cx, es.cz, dA.cx, dA.cz) ? 'land' : 'causeway'}/${landBFS(map, eg.cx, eg.cz, dA.cx, dA.cz) ? 'land' : 'causeway'}`);

  const strike = landBFS(map, map.cores[0].x, map.cores[0].z, map.cores[1].x, map.cores[1].z);
  add('A10 strike route home<->home', strike, strike ? 'land route' : 'BLOCKED');

  const laneH = map.causeways.filter(l => l.dormant);
  const allDocked = laneH.every(l => map.docks.some(d => d.region === l.a) && map.docks.some(d => d.region === l.b));
  const laneWet = laneH.every(l => {
    const lane = map.causeways.find(x => x.id === l.id);
    return lane.spars.length > 0; // dormant crossing must actually cross water
  });
  add('A11 dormant lanes docked + wet', laneH.length === 2 && allDocked && laneWet, `${laneH.length} lanes ${laneWet ? 'wet' : 'DRY!'}`);

  return A;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const seed = parseInt(process.argv[2] || CONTRACT.seed, 10);
  let allOk = true;
  for (const layout of LAYOUTS) {
    const map = generateMap({ seed, layout });
    const A = runAsserts(map, layout);
    console.log(`\n=== ${layout} (seed ${seed}) ===`);
    let ok = true;
    for (const a of A) {
      console.log(`  ${a.ok ? 'PASS' : 'FAIL'}  ${a.name.padEnd(28)} ${a.detail}`);
      if (!a.ok) ok = false;
    }
    console.log(`  spars per lane: ${map.causeways.map(l => `${l.id.split('-')[1]}-${l.id.split('-')[2]}:${l.spars.length}${l.dormant ? '(d)' : ''}`).join('  ')}`);
    console.log(`  docks: ${map.docks.map(d => `${d.region}@(${d.landX.toFixed(0)},${d.landZ.toFixed(0)})`).join('  ')}`);
    if (!ok) allOk = false;
  }
  console.log(allOk ? '\nALL LAYOUTS PASS' : '\nSOME ASSERTIONS FAILED');
  process.exit(allOk ? 0 : 1);
}
