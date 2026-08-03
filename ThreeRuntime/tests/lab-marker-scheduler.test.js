import assert from "node:assert/strict";
import test from "node:test";

import { MarkerScheduler } from "../src/lab-marker-scheduler.js";

test("a contact marker emits once in each of three loop repetitions", () => {
  const scheduler = new MarkerScheduler([
    { clip: "slender_gather_loop_R", name: "gather_contact", time_s: 0.4 },
  ]);
  const emitted = [];
  for (let repetition = 0; repetition < 3; repetition += 1) {
    emitted.push(...scheduler.advance("slender_gather_loop_R", 0.39));
    emitted.push(...scheduler.advance("slender_gather_loop_R", 0.4));
    emitted.push(...scheduler.advance("slender_gather_loop_R", 1.19));
    if (repetition < 2) emitted.push(...scheduler.advance("slender_gather_loop_R", 0.01));
  }
  assert.deepEqual(emitted.map((marker) => marker.name), [
    "gather_contact",
    "gather_contact",
    "gather_contact",
  ]);
});
