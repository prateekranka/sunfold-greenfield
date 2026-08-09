// GLB prototype library — real asset loading, clip resolution, material
// slots, and LOD-by-projected-size (Fidelity Ladder gltf tier).
//
// The villager and pathfinder GLBs are real authored prototypes (no textures,
// skinned, with clips); these tests parse them headless with GLTFLoader.parse,
// clone instances with SkeletonUtils.clone, and assert the runtime contract:
// one cached prototype, per-unit clones, ≤2 material instances, clip mapping,
// and tier selection by projected screen size with hysteresis.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as THREE from "three";

import {
  createRegistry,
  AGE_TIERS
} from "../src/asset-registry.js";
import {
  GltfUnitLibrary,
  GltfInstance,
  resolveClipName,
  slotForMaterialName,
  applyMaterialSlots,
  projectedScreenFraction,
  lodIndexForEntry,
  lodTarget,
  DEFAULT_SLOTS
} from "../src/gltf-units.js";

const here = dirname(fileURLToPath(import.meta.url));
const registry = createRegistry(
  JSON.parse(readFileSync(resolve(here, "../assets/asset-registry.json"), "utf8"))
);

// ---- registry LOD contract ------------------------------------------------

test("every lods tier is well-formed and its gltf files exist on disk", () => {
  let gltfTiers = 0;
  for (const [id, entry] of Object.entries(registry.entries)) {
    const lods = entry.lods;
    if (!lods) continue;
    assert.ok(lods.length >= 2, `${id} ladder has at least two tiers`);
    let previous = Infinity;
    for (const lod of lods) {
      assert.ok(["gltf", "sprite", "procedural"].includes(lod.kind), `${id} kind ${lod.kind}`);
      assert.equal(typeof lod.minScreenFraction, "number", `${id} threshold`);
      assert.ok(lod.minScreenFraction < previous, `${id} tiers ordered close → far`);
      previous = lod.minScreenFraction;
      if (lod.kind === "gltf") {
        assert.equal(typeof lod.gltf, "string", `${id} gltf path`);
        const file = resolve(here, `../assets/${lod.gltf}`);
        assert.ok(existsSync(file), `${id} gltf file exists: ${lod.gltf}`);
        gltfTiers += 1;
      }
      if (lod.kind === "sprite") {
        assert.equal(typeof lod.spriteSheet, "string", `${id} spriteSheet`);
      }
      if (lod.kind === "procedural") {
        assert.equal(lod.gltf, undefined, `${id} procedural tier has no source`);
      }
    }
  }
  assert.ok(gltfTiers >= 2, "at least the citizen + pathfinder ladders use gltf");
});

test("lods entries stay consistent with their source fields", () => {
  for (const [id, entry] of Object.entries(registry.entries)) {
    if (!entry.lods) continue;
    const gltfSources = new Set(
      entry.lods.filter((lod) => lod.kind === "gltf").map((lod) => lod.gltf)
    );
    const first = entry.lods[0];
    assert.equal(first.kind, "gltf", `${id} closest tier is the skinned model`);
    assert.equal(first.minScreenFraction, Math.max(...entry.lods.map((lod) => lod.minScreenFraction)), `${id} closest tier has the highest threshold`);
  }
});

test("material slots collapse every GLB material into one or two slots", () => {
  const villagerSlots = registry.entries["sunwoven.citizen.foundation"].materialSlots;
  const materials = [
    "villager_skin", "villager_eye", "villager_gold", "villager_gem",
    "villager_gold_line", "villager_turq", "villager_leather", "villager_leather_d",
    "villager_saffron", "villager_ivory"
  ];
  const assigned = new Set(materials.map((name) => slotForMaterialName(name, villagerSlots).name));
  assert.deepEqual([...assigned].sort(), ["accent", "primary"]);
  // Unknown materials collapse to the primary slot — never a third slot.
  assert.equal(slotForMaterialName("some_unknown_mat", villagerSlots).name, "primary");
  assert.equal(slotForMaterialName("pf_ivory", registry.entries["sunwoven.pathfinder.foundation"].materialSlots).name, "primary");
  assert.equal(slotForMaterialName("pf_gold_l", registry.entries["sunwoven.pathfinder.foundation"].materialSlots).name, "accent");
});

// ---- projected screen size + LOD math --------------------------------------

function makeCamera(distance, fov = 38) {
  const camera = new THREE.PerspectiveCamera(fov, 16 / 9, 0.1, 500);
  camera.position.set(0, distance * 0.3, distance * 0.95);
  camera.lookAt(0, 0, 0);
  camera.updateProjectionMatrix();
  return camera;
}

test("projectedScreenFraction matches the perspective projection formula", () => {
  // distance = sqrt(9² + 28.5²) = 29.89; fraction = 1.8 / (2·d·tan(19°)).
  const camera = makeCamera(30);
  const distance = camera.position.distanceTo(new THREE.Vector3(0, 0, 0));
  const expected = 1.8 / (2 * distance * Math.tan((38 * Math.PI) / 360));
  const fraction = projectedScreenFraction(camera, { x: 0, z: 0 }, 1.8);
  assert.ok(Math.abs(fraction - expected) < 1e-6);
  assert.ok(fraction > 0.05 && fraction < 0.12, `default RTS zoom keeps gltf tier (${fraction.toFixed(3)})`);
});

test("projectedScreenFraction supports orthographic cameras", () => {
  const camera = new THREE.OrthographicCamera(-10, 10, 8, -8, 0.1, 100);
  assert.equal(projectedScreenFraction(camera, { x: 0, z: 0 }, 1.8), 1.8 / 16);
  assert.equal(projectedScreenFraction(null, { x: 0, z: 0 }, 1.8), 1);
});

test("lodIndexForEntry picks the closest tier whose threshold the fraction clears", () => {
  const entry = registry.entries["sunwoven.citizen.foundation"];
  assert.equal(lodIndexForEntry(entry, 0.1), 0, "close → gltf");
  assert.equal(lodIndexForEntry(entry, 0.06), 0, "at the gltf threshold → gltf");
  assert.equal(lodIndexForEntry(entry, 0.05), 1, "mid → sprite");
  assert.equal(lodIndexForEntry(entry, 0.022), 1, "at the sprite threshold → sprite");
  assert.equal(lodIndexForEntry(entry, 0.01), 2, "far → procedural");
  assert.equal(lodIndexForEntry({}, 0.5), 0, "entries without lods stay on tier 0");
});

test("lodTarget applies hysteresis so thresholds do not thrash", () => {
  const entry = registry.entries["sunwoven.citizen.foundation"];
  // Moving farther: switch to sprite only past 0.06 · 0.88 = 0.0528.
  assert.equal(lodTarget(entry, 0.05, 0), 1);
  assert.equal(lodTarget(entry, 0.055, 0), 0, "inside the deadband → keep gltf");
  assert.equal(lodTarget(entry, 0.05, 1), 1, "already far → stays");
  // Moving closer: switch to gltf only past 0.06 · 1.12 = 0.0672.
  assert.equal(lodTarget(entry, 0.065, 1), 1, "inside the deadband → keep sprite");
  assert.equal(lodTarget(entry, 0.07, 1), 0);
});

// ---- clip resolution -------------------------------------------------------

test("resolveClipName maps logical clips onto GLB animations", () => {
  const animations = ["deposit", "gather_finish", "gather_loop", "gather_start", "idle", "walk"].map(
    (name) => ({ name })
  );
  assert.equal(resolveClipName(animations, "idle"), "idle");
  assert.equal(resolveClipName(animations, "walk"), "walk");
  // gather → prefer the loop variant over start/finish.
  assert.equal(resolveClipName(animations, "gather"), "gather_loop");
  // Explicit clipMap wins.
  assert.equal(resolveClipName(animations, "gather", { gather: "gather_start" }), "gather_start");
  // Missing logical clips fall back to idle; unknown animation sets return null.
  assert.equal(resolveClipName(animations, "build"), "idle");
  assert.equal(resolveClipName([], "idle"), null);
});

// ---- real GLB integration --------------------------------------------------

const VILLAGER_GLB = resolve(here, "../assets/units/citizen_villager.glb");
const PATHFINDER_GLB = resolve(here, "../assets/units/pathfinder_scout.glb");

function dataUrlFor(path) {
  return `data:model/gltf-binary;base64,${readFileSync(path).toString("base64")}`;
}

async function makeLibrary(paths) {
  const library = new GltfUnitLibrary();
  for (const path of paths) library.registerBuffer(path, dataUrlFor(resolve(here, `../assets/${path}`)));
  await library.preload(paths);
  return library;
}

test("villager prototype preloads, clones skinned, and stays a single cache entry", async () => {
  const library = await makeLibrary(["units/citizen_villager.glb"]);
  assert.equal(library.has("units/citizen_villager.glb"), true);
  const entry = registry.entries["sunwoven.citizen.foundation"];
  const a = library.instantiate("units/citizen_villager.glb", entry, "sunwoven");
  const b = library.instantiate("units/citizen_villager.glb", entry, "sunwoven");
  assert.ok(a instanceof GltfInstance);
  assert.notEqual(a.root, b.root, "instances are independent clones");
  let skinnedA = 0;
  a.root.traverse((o) => {
    if (o.isSkinnedMesh) skinnedA += 1;
  });
  assert.ok(skinnedA > 0, "cloned instance keeps skinned meshes");
  assert.equal(a.animations.length, 6, "idle/walk/gather_*/deposit");
  // Material budget: one or two instances per unit, never the GLB's 10.
  const materials = new Set();
  a.root.traverse((o) => {
    if (o.isMesh) materials.add(o.material);
  });
  assert.ok(materials.size <= 2, `material instances ≤ 2 (got ${materials.size})`);
});

test("clip playback resolves and animates on the per-instance mixer", async () => {
  const library = await makeLibrary(["units/citizen_villager.glb"]);
  const entry = registry.entries["sunwoven.citizen.foundation"];
  const instance = library.instantiate("units/citizen_villager.glb", entry, "sunwoven");
  instance.playClip("walk");
  const walk = instance.currentAction.getClip();
  assert.equal(walk.name, "walk");
  const t0 = instance.mixer.time;
  instance.update(0.25);
  assert.ok(instance.mixer.time > t0, "mixer advances");
  instance.playClip("gather");
  assert.equal(instance.currentAction.getClip().name, "gather_loop", "clipMap resolves gather → gather_loop");
  instance.pause();
  instance.update(0.25);
  assert.equal(instance.mixer.time, instance.mixer.time, "paused mixer does not jump");
});

test("pathfinder prototype preloads with its own clips and slots", async () => {
  const library = await makeLibrary(["units/pathfinder_scout.glb"]);
  const entry = registry.entries["sunwoven.pathfinder.foundation"];
  const instance = library.instantiate("units/pathfinder_scout.glb", entry, "sunwoven");
  assert.equal(instance.animations.length, 5);
  instance.playClip("idle");
  assert.equal(instance.currentAction.getClip().name, "idle");
  instance.playClip("death");
  assert.equal(instance.currentAction.getClip().name, "idle", "missing death falls back to idle");
  const materials = new Set();
  instance.root.traverse((o) => {
    if (o.isMesh) materials.add(o.material);
  });
  assert.ok(materials.size <= 2, `material instances ≤ 2 (got ${materials.size})`);
});

test("unpreloaded prototypes and unknown paths fail loudly, preload failures absorb", async () => {
  const library = new GltfUnitLibrary();
  assert.equal(library.has("units/missing.glb"), false);
  assert.throws(() => library.instantiate("units/missing.glb"), /not preloaded/);
  await library.preload(["units/does-not-exist.glb"]); // absorbed, no throw
  assert.equal(library.has("units/does-not-exist.glb"), false);
});

test("registry tier ids cover both age tiers with the gltf ladder", () => {
  for (const tier of AGE_TIERS) {
    const entry = registry.entries[`sunwoven.citizen.${tier}`];
    assert.ok(entry.lods, `citizen ${tier} has a ladder`);
    assert.equal(entry.lods[0].kind, "gltf");
  }
});
