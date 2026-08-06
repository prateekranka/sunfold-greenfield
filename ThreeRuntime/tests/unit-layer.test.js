// Unit presentation layer — registry cascade behaviour.
//
// The layer must resolve every unit kind through the asset registry, land on
// the procedural debug stand-in when authored art is missing or unloadable,
// and never throw in sync(). These tests run headless: THREE.Groups work in
// Node; sprite texture/URL IO does not, which is exactly the failure path the
// cascade must absorb.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as THREE from "three";

import { createRegistry, assetIdForUnit } from "../src/asset-registry.js";
import { UnitPresentationLayer, CitizenSpriteLayer, clipForUnit } from "../src/sprites/unit-layer.js";

const here = dirname(fileURLToPath(import.meta.url));
const registry = createRegistry(
  JSON.parse(readFileSync(resolve(here, "../assets/asset-registry.json"), "utf8"))
);

/** Stub factory recording the kinds/factions the layer asked for. */
function stubFactory(calls) {
  return ({ kind, faction, height }) => {
    calls.push({ kind, faction, height });
    const group = new THREE.Group();
    group.userData.procedural = true;
    return group;
  };
}

function fakeState(units, age = {}) {
  return {
    age,
    units: { ordered: () => units }
  };
}

function fakeUnit(id, kind, faction, extra = {}) {
  return { id, kind, faction, position: { x: 0, z: 0 }, facing: 0, ...extra };
}

test("clipForUnit maps sim activity to clip names", () => {
  assert.equal(clipForUnit(fakeUnit(1, "citizen", "sunwoven")), "idle");
  assert.equal(
    clipForUnit(fakeUnit(1, "citizen", "sunwoven", { movementPath: [{ x: 1, z: 1 }] })),
    "walk"
  );
  assert.equal(
    clipForUnit(fakeUnit(1, "citizen", "sunwoven", { activity: { tag: "gathering" } })),
    "gather"
  );
  assert.equal(
    clipForUnit(fakeUnit(1, "citizen", "sunwoven", { activity: { tag: "constructing" } })),
    "build"
  );
});

test("CitizenSpriteLayer remains available as a legacy alias", () => {
  assert.equal(CitizenSpriteLayer, UnitPresentationLayer);
});

test("procedural stand-ins are created for units without authored art", async () => {
  const calls = [];
  const scene = new THREE.Scene();
  const layer = new UnitPresentationLayer({
    scene,
    registry,
    assetId: assetIdForUnit,
    proceduralFactory: stubFactory(calls)
  });
  await layer.init();
  layer.sync(
    fakeState(
      [
        fakeUnit(1, "citizen", "sunwoven"),
        fakeUnit(2, "vanguard", "gravemark"),
        fakeUnit(3, "bastionWalker", "gravemark")
      ],
      { sunwoven: "foundation", gravemark: "voyager" }
    ),
    0.016
  );
  // Views are created asynchronously; allow the cascade to settle.
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
  assert.equal(layer.views.size, 3, "one view per unit");
  assert.deepEqual(calls.map((c) => `${c.faction}/${c.kind}`).sort(), [
    "gravemark/bastionWalker",
    "gravemark/vanguard",
    "sunwoven/citizen"
  ]);
  // The Sunwoven citizen has a LOD ladder whose authored sources cannot load
  // headless — it bottoms out on its procedural floor while keeping the
  // authored entry id. Units without art resolve to their procedural.* id.
  const citizen = layer.views.get(1);
  assert.equal(citizen.userData.procedural, true);
  assert.equal(citizen.userData.entryId, "sunwoven.citizen.foundation");
  assert.equal(layer.views.get(2).userData.entryId, "procedural.vanguard");
  assert.equal(layer.views.get(3).userData.entryId, "procedural.bastionWalker");
  for (const view of layer.views.values()) {
    assert.equal(view.userData.procedural, true, "every headless view is procedural");
  }
  layer.dispose();
});

test("authored citizen art is attempted, then the cascade lands on procedural", async () => {
  // No manifests are provided and relative fetches fail under Node, so the
  // authored directionalSprite path must fail softly into the procedural
  // stand-in — exactly what a CSP-blocked device sees.
  const calls = [];
  const scene = new THREE.Scene();
  const layer = new UnitPresentationLayer({
    scene,
    registry,
    assetId: assetIdForUnit,
    proceduralFactory: stubFactory(calls)
  });
  await layer.init();
  layer.sync(fakeState([fakeUnit(1, "citizen", "sunwoven")], { sunwoven: "foundation" }), 0.016);
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
  assert.equal(layer.views.size, 1);
  const view = layer.views.get(1);
  assert.equal(view.userData.procedural, true, "cascade must not throw or skip");
  assert.equal(view.userData.entryId, "sunwoven.citizen.foundation");
  layer.dispose();
});

test("forceProcedural skips authored art entirely", async () => {
  const calls = [];
  const scene = new THREE.Scene();
  const layer = new UnitPresentationLayer({
    scene,
    registry,
    assetId: assetIdForUnit,
    proceduralFactory: stubFactory(calls),
    forceProcedural: true
  });
  await layer.init();
  layer.sync(fakeState([fakeUnit(1, "citizen", "sunwoven")], { sunwoven: "foundation" }), 0.016);
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
  assert.equal(layer.views.size, 1);
  assert.equal(calls.length, 1, "exactly one procedural build");
  layer.dispose();
});

test("stale views are removed when units leave the sim", async () => {
  const calls = [];
  const scene = new THREE.Scene();
  const layer = new UnitPresentationLayer({
    scene,
    registry,
    assetId: assetIdForUnit,
    proceduralFactory: stubFactory(calls),
    forceProcedural: true
  });
  await layer.init();
  layer.sync(fakeState([fakeUnit(1, "citizen", "sunwoven")]), 0.016);
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
  assert.equal(layer.views.size, 1);
  layer.sync(fakeState([]), 0.016);
  assert.equal(layer.views.size, 0, "departed units are pruned");
  assert.equal(scene.children.length, 0, "their groups leave the scene");
  layer.dispose();
});

test("sync is safe with no registry or factory wired", () => {
  const scene = new THREE.Scene();
  const layer = new UnitPresentationLayer({ scene });
  layer.sync(fakeState([fakeUnit(1, "citizen", "sunwoven")]), 0.016);
  assert.equal(layer.views.size, 0, "nothing to build without a factory");
});
