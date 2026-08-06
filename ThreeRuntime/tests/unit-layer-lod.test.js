// End-to-end LOD switching: a real preloaded GLB prototype, a real camera,
// and the presentation layer switching tiers by projected screen size.
//
// The sprite tier of the citizen ladder cannot load headless (no texture IO),
// so the ladder in these tests is [gltf, procedural] — which still proves the
// switch mechanics: visibility toggling, mixer pause/resume, and hysteresis.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as THREE from "three";

import { createRegistry, assetIdForUnit } from "../src/asset-registry.js";
import { GltfUnitLibrary } from "../src/gltf-units.js";
import { UnitPresentationLayer } from "../src/sprites/unit-layer.js";
import { createProceduralUnit } from "../src/procedural-units.js";

const here = dirname(fileURLToPath(import.meta.url));
const registry = createRegistry(
  JSON.parse(readFileSync(resolve(here, "../assets/asset-registry.json"), "utf8"))
);

const glbPath = resolve(here, "../assets/units/citizen_villager.glb");
const library = new GltfUnitLibrary();
library.registerBuffer(
  "units/citizen_villager.glb",
  `data:model/gltf-binary;base64,${readFileSync(glbPath).toString("base64")}`
);

function makeCamera(distance) {
  const camera = new THREE.PerspectiveCamera(38, 16 / 9, 0.1, 500);
  camera.position.set(0, distance * 0.3, distance * 0.95);
  camera.lookAt(0, 0, 0);
  camera.updateProjectionMatrix();
  return camera;
}

function syncAndSettle(layer, state, camera, dt = 0.05) {
  layer.sync(state, dt);
  return new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
}

test("citizen view switches gltf → procedural when zoomed out, with hysteresis", async () => {
  await library.preload(["units/citizen_villager.glb"]);
  const scene = new THREE.Scene();
  const camera = makeCamera(30); // fraction ≈ 0.084 → gltf tier
  const layer = new UnitPresentationLayer({
    scene,
    registry,
    assetId: assetIdForUnit,
    gltfLibrary: library,
    camera,
    proceduralFactory: createProceduralUnit
  });
  await layer.init();

  const unit = { id: 1, kind: "citizen", faction: "sunwoven", position: { x: 0, z: 0 }, facing: 0 };
  const state = { age: { sunwoven: "foundation" }, units: { ordered: () => [unit] } };

  await syncAndSettle(layer, state, camera);
  const view = layer.views.get(1);
  assert.ok(view, "view created");
  assert.equal(view.tiers[0].kind, "gltf", "closest tier is the skinned model");
  assert.equal(view.tiers[1].kind, "procedural", "sprite tier skipped headless");
  assert.equal(view.activeTier, 0, "close camera → gltf active");
  assert.equal(view.userData.procedural, false);
  assert.equal(view.tiers[0].object.root.visible, true);
  assert.equal(view.tiers[1].object.visible, false);
  let skinned = 0;
  view.tiers[0].object.root.traverse((o) => {
    if (o.isSkinnedMesh) skinned += 1;
  });
  assert.ok(skinned > 0, "real skinned prototype is on screen");

  // Advance animation while visible.
  await syncAndSettle(layer, state, camera, 0.2);
  assert.ok(view.tiers[0].object.mixer.time > 0, "mixer advances while active");

  // Zoom out to fraction ≈ 0.028 → below the 0.06 gltf threshold (past the
  // 0.0528 hysteresis edge) → switches to the procedural tier. The layer
  // reads its own camera, so repoint it before the sync.
  const far = new THREE.PerspectiveCamera(38, 16 / 9, 0.1, 500);
  far.position.set(0, 36, 114);
  far.lookAt(0, 0, 0);
  far.updateProjectionMatrix();
  layer.camera = far;
  await syncAndSettle(layer, state, far);
  assert.equal(view.activeTier, 1, "far camera → procedural tier");
  assert.equal(view.tiers[0].object.root.visible, false, "gltf hidden");
  assert.equal(view.tiers[1].object.visible, true, "procedural visible");

  // Hysteresis: just inside the 0.06 boundary (fraction ≈ 0.050) stays on
  // the procedural tier instead of thrashing back to gltf.
  const nearish = new THREE.PerspectiveCamera(38, 16 / 9, 0.1, 500);
  nearish.position.set(0, 15.6, 49.4);
  nearish.lookAt(0, 0, 0);
  nearish.updateProjectionMatrix();
  layer.camera = nearish;
  await syncAndSettle(layer, state, nearish);
  assert.equal(view.activeTier, 1, "inside deadband → stays procedural");
  assert.equal(view.tiers[0].object.root.visible, false);

  // Well inside the gltf band (fraction ≈ 0.07 → past 0.0672) → back to gltf.
  const close = new THREE.PerspectiveCamera(38, 16 / 9, 0.1, 500);
  close.position.set(0, 11.4, 36.1);
  close.lookAt(0, 0, 0);
  close.updateProjectionMatrix();
  layer.camera = close;
  await syncAndSettle(layer, state, close);
  assert.equal(view.activeTier, 0, "close again → gltf resumes");
  assert.equal(view.tiers[0].object.root.visible, true);
  assert.equal(view.tiers[1].object.visible, false);

  layer.dispose();
  assert.equal(scene.children.length, 0);
});

test("unit yaw drives the gltf instance facing", async () => {
  const scene = new THREE.Scene();
  const camera = makeCamera(30);
  const layer = new UnitPresentationLayer({
    scene,
    registry,
    assetId: assetIdForUnit,
    gltfLibrary: library,
    camera,
    proceduralFactory: createProceduralUnit
  });
  await layer.init();
  const unit = { id: 7, kind: "citizen", faction: "sunwoven", position: { x: 0, z: 0 }, facing: Math.PI / 2 };
  const state = { age: { sunwoven: "foundation" }, units: { ordered: () => [unit] } };
  await syncAndSettle(layer, state, camera);
  const view = layer.views.get(7);
  assert.equal(view.activeTier, 0);
  assert.ok(Math.abs(view.tiers[0].object.root.rotation.y - Math.PI / 2) < 1e-6);
  layer.dispose();
});
