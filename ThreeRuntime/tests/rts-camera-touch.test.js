import assert from "node:assert/strict";
import test from "node:test";

import * as THREE from "three";
import { RtsCameraController } from "../src/rts-camera.js";

class FakeEventTarget {
  constructor() {
    this.listeners = new Map();
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  removeEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? [];
    this.listeners.set(type, listeners.filter((candidate) => candidate !== listener));
  }

  dispatch(type, init) {
    let prevented = false;
    const event = {
      type,
      button: 0,
      clientX: 0,
      clientY: 0,
      pointerId: 1,
      pointerType: "touch",
      preventDefault() { prevented = true; },
      ...init
    };
    for (const listener of this.listeners.get(type) ?? []) listener(event);
    return prevented;
  }

  setPointerCapture() {}
  releasePointerCapture() {}
}

function makeController() {
  const dom = new FakeEventTarget();
  const windowTarget = new FakeEventTarget();
  globalThis.window = windowTarget;
  const camera = new THREE.PerspectiveCamera();
  const controller = new RtsCameraController(camera, dom, {
    distance: 80,
    pitchDegrees: 43,
    yawDegrees: 45,
    panRadius: 80
  });
  return { controller, dom, windowTarget };
}

test("one-finger touch drag pans the RTS camera without browser handling", () => {
  const { controller, dom, windowTarget } = makeController();
  assert.equal(dom.dispatch("pointerdown", { clientX: 100, clientY: 100, pointerId: 11 }), true);
  assert.equal(dom.dispatch("pointermove", { clientX: 145, clientY: 118, pointerId: 11 }), true);
  controller.tick(1 / 60);
  assert.ok(Math.hypot(controller.target.x, controller.target.z) > 0.1);
  assert.equal(windowTarget.dispatch("pointerup", { clientX: 145, clientY: 118, pointerId: 11 }), true);
  controller.dispose();
});

test("two-finger touch pinch changes camera distance instead of page scale", () => {
  const { controller, dom, windowTarget } = makeController();
  dom.dispatch("pointerdown", { clientX: 100, clientY: 100, pointerId: 21 });
  dom.dispatch("pointerdown", { clientX: 200, clientY: 100, pointerId: 22 });
  dom.dispatch("pointermove", { clientX: 270, clientY: 100, pointerId: 22 });
  for (let index = 0; index < 6; index += 1) controller.tick(1 / 60);
  assert.ok(controller.distance < 70, `expected zoom-in distance below 70, got ${controller.distance}`);
  windowTarget.dispatch("pointerup", { clientX: 270, clientY: 100, pointerId: 22 });
  windowTarget.dispatch("pointerup", { clientX: 100, clientY: 100, pointerId: 21 });
  controller.dispose();
});
