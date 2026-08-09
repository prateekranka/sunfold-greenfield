import test from "node:test";
import assert from "node:assert/strict";

import {
  damageStateForLife,
  visibleGroupNamesForState
} from "../src/buildings/gltf-buildings.js";

test("building damage thresholds map exact HP boundaries to authored states", () => {
  assert.equal(damageStateForLife(600, 600), "healthy");
  assert.equal(damageStateForLife(451, 600), "healthy");
  assert.equal(damageStateForLife(450, 600), "damaged");
  assert.equal(damageStateForLife(301, 600), "damaged");
  assert.equal(damageStateForLife(300, 600), "critical");
  assert.equal(damageStateForLife(1, 600), "critical");
  assert.equal(damageStateForLife(0, 600), "destroyed");
  assert.equal(damageStateForLife(-20, 600), "destroyed");
});
test("every state exposes one coherent visibility composition", () => {
  assert.deepEqual(visibleGroupNamesForState("healthy"), [
    "state_shared",
    "state_healthy_damaged",
    "state_healthy_only"
  ]);
  assert.deepEqual(visibleGroupNamesForState("damaged"), [
    "state_shared",
    "state_healthy_damaged",
    "state_damaged_plus"
  ]);
  assert.deepEqual(visibleGroupNamesForState("critical"), [
    "state_shared",
    "state_damaged_plus",
    "state_critical_plus"
  ]);
  assert.deepEqual(visibleGroupNamesForState("destroyed"), ["state_destroyed_only"]);
});
