// UnitPresentationLayer — golden-unit integration tests (Node-safe: no DOM).
//
// The golden sprite tier is exercised through a manifests override so no
// fetch is needed; TextureLoader throws in Node (no Image), which the golden
// unit absorbs, leaving a valid view with null textures — exactly what the
// fallback path sees when a texture fails to load.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as THREE from "three";
import { createRegistry } from "../src/asset-registry.js";
import { UnitPresentationLayer, clipForUnit } from "../src/sprites/unit-layer.js";
import { GoldenSpriteUnit } from "../src/sprites/golden-unit.js";
import { createProceduralUnit } from "../src/procedural-units.js";

const registry = createRegistry(
  JSON.parse(readFileSync("assets/asset-registry.json", "utf8"))
);

const goldenManifest = JSON.parse(
  readFileSync("assets/citizens/sprites/sunwoven-golden/atlas-manifest.json", "utf8")
);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(38, 16 / 9, 0.1, 100);

function makeLayer(opts = {}) {
  return new UnitPresentationLayer({
    scene,
    registry,
    camera,
    proceduralFactory: createProceduralUnit,
    manifests: {
      "sunwoven.citizen.foundation": { manifest: goldenManifest }
    },
    ...opts
  });
}

function unit(overrides = {}) {
  return {
    id: 1,
    kind: "citizen",
    faction: "sunwoven",
    position: { x: 0, z: 0 },
    facing: 0,
    ...overrides
  };
}

const simState = (unitsList) => ({
  age: { sunwoven: "foundation" },
  units: { ordered: () => unitsList }
});

test("forceArt sprite: only the sprite tier is built", async () => {
  const layer = makeLayer({ forceArt: "sprite" });
  await layer.init();
  const u = unit();
  layer.sync(simState([u]), 0.016);
  await new Promise((r) => setTimeout(r, 10));
  const view = layer.views.get(u.id);
  assert.ok(view, "view created");
  assert.equal(view.tiers[0].kind, "sprite");
  assert.ok(view.tiers[0].object instanceof GoldenSpriteUnit, "golden unit class");
  // The gltf tier (registry lods entry 0) must NOT be built under forceArt.
  assert.equal(view.tiers.length, 1);
  // Faction ring lands on the next tick (view creation is async).
  layer.sync(simState([u]), 0.016);
  assert.ok(scene.getObjectByName("faction-ring"), "faction ring added");
});

test("golden unit facing follows sim yaw through the 16-cell atlas", async () => {
  const layer = makeLayer({ forceArt: "sprite" });
  await layer.init();
  const u = unit({ facing: Math.PI / 4 }); // ESE → cell 2
  layer.sync(simState([u]), 0.016);
  await new Promise((r) => setTimeout(r, 10));
  const view = layer.views.get(u.id);
  assert.equal(view.tiers[0].object.facing, 2);
  u.facing = Math.PI; // N → cell 8
  layer.sync(simState([u]), 0.016);
  assert.equal(view.tiers[0].object.facing, 8);
});

test("clip mapping: carry wins over movement, gather/build map, idle default", () => {
  assert.equal(clipForUnit(unit({ activity: { tag: "carrying" }, destination: { x: 3, z: 0 } })), "carry");
  assert.equal(clipForUnit(unit({ carrying: true, destination: { x: 3, z: 0 } })), "carry");
  assert.equal(clipForUnit(unit({ destination: { x: 3, z: 0 } })), "walk");
  assert.equal(clipForUnit(unit({ activity: { tag: "gathering" } })), "gather");
  assert.equal(clipForUnit(unit({ activity: { tag: "constructing" } })), "build");
  assert.equal(clipForUnit(unit({})), "idle");
});

test("selection rings appear for unit.selected and vanish otherwise", async () => {
  const layer = makeLayer({ forceArt: "sprite" });
  await layer.init();
  const u = unit({ selected: true });
  layer.sync(simState([u]), 0.016);
  await new Promise((r) => setTimeout(r, 10));
  layer.sync(simState([u]), 0.016);
  const view = layer.views.get(u.id);
  assert.ok(view.container.getObjectByName("selection-ring"), "ring added");
  u.selected = false;
  layer.sync(simState([u]), 0.016);
  // three's getObjectByName returns undefined (falsy) once removed.
  assert.ok(!view.container.getObjectByName("selection-ring"), "ring removed");
});

test("blob shadows are skipped without a DOM (graceful), rings still work", async () => {
  const layer = makeLayer({ forceArt: "sprite", blobShadows: true });
  await layer.init();
  const u = unit({ selected: true });
  layer.sync(simState([u]), 0.016);
  await new Promise((r) => setTimeout(r, 10));
  layer.sync(simState([u]), 0.016);
  const view = layer.views.get(u.id);
  assert.ok(!view.container.getObjectByName("blob-shadow"), "no DOM → no blob");
  assert.ok(view.container.getObjectByName("selection-ring"), "selection ring unaffected");
});

test("golden manifest override resolves without fetch in Node", async () => {
  const layer = makeLayer(); // forceArt null — normal path
  await layer.init();
  const u = unit();
  layer.sync(simState([u]), 0.016);
  await new Promise((r) => setTimeout(r, 10));
  const view = layer.views.get(u.id);
  assert.ok(view, "view created via bundled override");
  assert.equal(view.tiers[0].kind, "sprite", "sprite tier built from the override");
  assert.ok(view.tiers[0].object instanceof GoldenSpriteUnit);
});
