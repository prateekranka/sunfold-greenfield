// Locked AoE2-style RTS camera — fixed pitch/yaw, smooth pan + zoom only.
//
// Gameplay and sprite baking share these angles so painted/baked frames match
// what the player sees. Orbit is intentionally absent; the world does not spin
// under the cursor.

import * as THREE from "three";
import { TUNING } from "./sim/tuning.js";

/** Canonical gameplay camera — keep in sync with Tools/citizens/bake_sprites.py */
export const RTS_CAMERA = Object.freeze({
  /** Degrees above the ground plane (0 = horizon, 90 = top-down). */
  pitchDegrees: TUNING.cameraPitchDegrees,
  /** Degrees about +Y; 45° = classic dimetric “NE corner” view. */
  yawDegrees: 45,
  /** Horizontal distance from look-at target (metres). */
  defaultDistance: TUNING.cameraDefaultZoom / 4,
  minDistance: TUNING.cameraMinZoom / 4,
  maxDistance: TUNING.cameraMaxZoom / 4,
  /** Vertical field of view (degrees). */
  fovDegrees: 38,
  /** Default look-at height above ground (citizen torso). */
  targetHeight: 0.9,
  near: 0.1,
  far: 120,
});

/**
 * World-space offset from target to camera for the locked RTS rig.
 * @param {number} [distance]
 * @param {{ pitchDegrees?: number, yawDegrees?: number }} [presentation]
 * @returns {THREE.Vector3}
 */
export function rtsCameraOffset(distance = RTS_CAMERA.defaultDistance, presentation = {}) {
  const pitch = THREE.MathUtils.degToRad(presentation.pitchDegrees ?? RTS_CAMERA.pitchDegrees);
  const yaw = THREE.MathUtils.degToRad(presentation.yawDegrees ?? RTS_CAMERA.yawDegrees);
  const horiz = distance * Math.cos(pitch);
  const y = distance * Math.sin(pitch);
  const x = horiz * Math.sin(yaw);
  const z = horiz * Math.cos(yaw);
  return new THREE.Vector3(x, y, z);
}

/**
 * Apply the locked RTS transform to a PerspectiveCamera.
 * @param {THREE.PerspectiveCamera} camera
 * @param {THREE.Vector3} target ground-plane look-at (y = targetHeight applied)
 * @param {number} [distance]
 * @param {{ fovDegrees?: number, far?: number, pitchDegrees?: number, yawDegrees?: number }} [presentation]
 */
export function applyRtsCamera(camera, target, distance = RTS_CAMERA.defaultDistance, presentation = {}) {
  const look = target.clone();
  look.y = RTS_CAMERA.targetHeight;
  camera.position.copy(look).add(rtsCameraOffset(distance, presentation));
  camera.lookAt(look);
  camera.fov = presentation.fovDegrees ?? RTS_CAMERA.fovDegrees;
  camera.near = RTS_CAMERA.near;
  camera.far = presentation.far ?? RTS_CAMERA.far;
  camera.updateProjectionMatrix();
}

/**
 * @param {number} aspect width / height
 * @param {{ fovDegrees?: number, far?: number }} [presentation]
 * @returns {THREE.PerspectiveCamera}
 */
export function createRtsCamera(aspect = 16 / 9, presentation = {}) {
  const camera = new THREE.PerspectiveCamera(
    presentation.fovDegrees ?? RTS_CAMERA.fovDegrees,
    aspect,
    RTS_CAMERA.near,
    presentation.far ?? RTS_CAMERA.far
  );
  applyRtsCamera(camera, new THREE.Vector3(0, 0, 0), RTS_CAMERA.defaultDistance, presentation);
  return camera;
}

/**
 * Smooth pan + zoom controller. Yaw/pitch stay locked at the AoE rig.
 * Wheel / pinch dolly with lerp; middle/right-drag and WASD/arrows pan the
 * look-at on the ground plane with light momentum.
 */
export class RtsCameraController {
  /**
   * @param {THREE.PerspectiveCamera} camera
   * @param {HTMLElement} domElement
   * @param {{
   *   target?: THREE.Vector3,
   *   distance?: number,
   *   minDistance?: number,
   *   maxDistance?: number,
   *   fovDegrees?: number,
   *   far?: number,
   *   pitchDegrees?: number,
   *   yawDegrees?: number,
   *   panRadius?: number,
   *   zoomSmooth?: number,
   *   panSmooth?: number,
   *   panFriction?: number,
   *   keyPanSpeed?: number,
   *   dragPanScale?: number,
   * }} [opts]
   */
  constructor(camera, domElement, opts = {}) {
    this.camera = camera;
    this.domElement = domElement;

    this.target = opts.target?.clone() ?? new THREE.Vector3(0, 0, 0);
    this.distance = opts.distance ?? RTS_CAMERA.defaultDistance;
    this.minDistance = opts.minDistance ?? RTS_CAMERA.minDistance;
    this.maxDistance = opts.maxDistance ?? RTS_CAMERA.maxDistance;
    this.fovDegrees = opts.fovDegrees ?? RTS_CAMERA.fovDegrees;
    this.far = opts.far ?? RTS_CAMERA.far;
    this.pitchDegrees = opts.pitchDegrees ?? RTS_CAMERA.pitchDegrees;
    this.yawDegrees = opts.yawDegrees ?? RTS_CAMERA.yawDegrees;

    /** @type {THREE.Vector3} smoothed look-at (XZ); y ignored */
    this._desiredTarget = this.target.clone();
    this._desiredDistance = this.distance;
    this._panVel = new THREE.Vector3();

    this.panRadius = opts.panRadius ?? 42;
    // Higher k → snappier exponential smoothing at 60 Hz (alpha = 1-exp(-k*dt)).
    this.zoomSmooth = opts.zoomSmooth ?? 18;
    this.panSmooth = opts.panSmooth ?? 20;
    this.panFriction = opts.panFriction ?? 10;
    this.keyPanSpeed = opts.keyPanSpeed ?? 26;
    this.dragPanScale = opts.dragPanScale ?? 0.00135;

    this._dragging = false;
    this._dragButton = -1;
    this._lastX = 0;
    this._lastY = 0;
    /** @type {Set<string>} */
    this._keys = new Set();
    this._enabled = true;

    const yaw = THREE.MathUtils.degToRad(this.yawDegrees);
    const right = new THREE.Vector3(Math.cos(yaw), 0, -Math.sin(yaw));
    const forward = new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw));
    this._right = right;
    this._forward = forward;

    this._onPointerDown = (e) => {
      if (!this._enabled) return;
      // Middle (1) or right (2) drag pans. Left stays free for selection.
      if (e.button !== 1 && e.button !== 2) return;
      this._dragging = true;
      this._dragButton = e.button;
      this._lastX = e.clientX;
      this._lastY = e.clientY;
      this._panVel.set(0, 0, 0);
      try {
        this.domElement.setPointerCapture?.(e.pointerId);
      } catch {
        /* ignore */
      }
      e.preventDefault();
    };
    this._onPointerUp = (e) => {
      if (e.button !== this._dragButton && this._dragging && e.type === "pointerup") {
        // ignore other button releases while dragging
      }
      if (!this._dragging) return;
      if (e.button !== undefined && e.button !== this._dragButton && e.type === "pointerup") return;
      this._dragging = false;
      this._dragButton = -1;
      try {
        this.domElement.releasePointerCapture?.(e.pointerId);
      } catch {
        /* ignore */
      }
    };
    this._onPointerMove = (e) => {
      if (!this._enabled || !this._dragging) return;
      const dx = e.clientX - this._lastX;
      const dy = e.clientY - this._lastY;
      this._lastX = e.clientX;
      this._lastY = e.clientY;
      const panScale = this.distance * this.dragPanScale;
      // Instant desired nudge + short-lived velocity for gentle momentum.
      const step = new THREE.Vector3()
        .addScaledVector(this._right, -dx * panScale)
        .addScaledVector(this._forward, dy * panScale);
      this._desiredTarget.add(step);
      this._clampDesired();
      this._panVel.copy(step).multiplyScalar(18);
    };
    this._onWheel = (e) => {
      if (!this._enabled) return;
      e.preventDefault();
      // Trackpad pinch often arrives as ctrl+wheel; treat the same as dolly.
      const raw = e.deltaY;
      const factor = 1 + raw * (e.ctrlKey ? 0.012 : 0.00115);
      this._desiredDistance = THREE.MathUtils.clamp(
        this._desiredDistance * factor,
        this.minDistance,
        this.maxDistance
      );
    };
    this._onContextMenu = (e) => {
      e.preventDefault();
    };
    this._onKeyDown = (e) => {
      if (!this._enabled) return;
      const k = e.key.toLowerCase();
      if (
        k === "w" ||
        k === "a" ||
        k === "s" ||
        k === "d" ||
        k === "arrowup" ||
        k === "arrowdown" ||
        k === "arrowleft" ||
        k === "arrowright" ||
        k === "=" ||
        k === "+" ||
        k === "-" ||
        k === "_"
      ) {
        this._keys.add(k);
        e.preventDefault();
      }
    };
    this._onKeyUp = (e) => {
      this._keys.delete(e.key.toLowerCase());
    };
    this._onBlur = () => {
      this._keys.clear();
      this._dragging = false;
    };

    domElement.addEventListener("pointerdown", this._onPointerDown);
    window.addEventListener("pointerup", this._onPointerUp);
    window.addEventListener("pointercancel", this._onPointerUp);
    domElement.addEventListener("pointermove", this._onPointerMove);
    domElement.addEventListener("wheel", this._onWheel, { passive: false });
    domElement.addEventListener("contextmenu", this._onContextMenu);
    window.addEventListener("keydown", this._onKeyDown);
    window.addEventListener("keyup", this._onKeyUp);
    window.addEventListener("blur", this._onBlur);

    this.update();
  }

  setEnabled(on) {
    this._enabled = !!on;
    if (!on) {
      this._dragging = false;
      this._keys.clear();
      this._panVel.set(0, 0, 0);
    }
  }

  _clampDesired() {
    const r = Math.hypot(this._desiredTarget.x, this._desiredTarget.z);
    if (r > this.panRadius && r > 1e-6) {
      const s = this.panRadius / r;
      this._desiredTarget.x *= s;
      this._desiredTarget.z *= s;
    }
    this._desiredTarget.y = 0;
    this._desiredDistance = THREE.MathUtils.clamp(
      this._desiredDistance,
      this.minDistance,
      this.maxDistance
    );
  }

  /**
   * Smoothly (or immediately) move look-at to a world XZ position.
   * @param {number} x
   * @param {number} z
   * @param {{ immediate?: boolean }} [opts]
   */
  panTo(x, z, opts = {}) {
    this._desiredTarget.set(x, 0, z);
    this._clampDesired();
    this._panVel.set(0, 0, 0);
    if (opts.immediate) {
      this.target.copy(this._desiredTarget);
      this.update();
    }
  }

  /**
   * Set zoom distance (smooth unless immediate).
   * @param {number} distance
   * @param {{ immediate?: boolean }} [opts]
   */
  setDistance(distance, opts = {}) {
    this._desiredDistance = THREE.MathUtils.clamp(
      distance,
      this.minDistance,
      this.maxDistance
    );
    if (opts.immediate) {
      this.distance = this._desiredDistance;
      this.update();
    }
  }

  /**
   * Advance smooth zoom/pan. Call once per frame.
   * @param {number} dt seconds
   */
  tick(dt) {
    if (!this._enabled) {
      this.update();
      return;
    }
    // Clamp to ~3 frames @ 60 Hz so a hitch does not overshoot lerps.
    const t = Math.max(0, Math.min(1 / 20, dt));

    // Keyboard pan (camera-relative on ground plane).
    let kx = 0;
    let kz = 0;
    if (this._keys.has("w") || this._keys.has("arrowup")) kz -= 1;
    if (this._keys.has("s") || this._keys.has("arrowdown")) kz += 1;
    if (this._keys.has("a") || this._keys.has("arrowleft")) kx -= 1;
    if (this._keys.has("d") || this._keys.has("arrowright")) kx += 1;
    if (kx !== 0 || kz !== 0) {
      const len = Math.hypot(kx, kz) || 1;
      kx /= len;
      kz /= len;
      const speed = this.keyPanSpeed * (0.55 + 0.45 * (this.distance / RTS_CAMERA.defaultDistance));
      this._desiredTarget.addScaledVector(this._right, kx * speed * t);
      this._desiredTarget.addScaledVector(this._forward, kz * speed * t);
      this._clampDesired();
      this._panVel.set(0, 0, 0);
    }

    if (this._keys.has("=") || this._keys.has("+")) {
      this._desiredDistance = THREE.MathUtils.clamp(
        this._desiredDistance * (1 - 1.1 * t),
        this.minDistance,
        this.maxDistance
      );
    }
    if (this._keys.has("-") || this._keys.has("_")) {
      this._desiredDistance = THREE.MathUtils.clamp(
        this._desiredDistance * (1 + 1.1 * t),
        this.minDistance,
        this.maxDistance
      );
    }

    // Light momentum after drag release.
    if (!this._dragging && this._panVel.lengthSq() > 1e-6) {
      this._desiredTarget.addScaledVector(this._panVel, t);
      this._clampDesired();
      const damp = Math.exp(-this.panFriction * t);
      this._panVel.multiplyScalar(damp);
      if (this._panVel.lengthSq() < 1e-4) this._panVel.set(0, 0, 0);
    }

    const zoomAlpha = 1 - Math.exp(-this.zoomSmooth * t);
    const panAlpha = 1 - Math.exp(-this.panSmooth * t);
    this.distance += (this._desiredDistance - this.distance) * zoomAlpha;
    this.target.x += (this._desiredTarget.x - this.target.x) * panAlpha;
    this.target.z += (this._desiredTarget.z - this.target.z) * panAlpha;
    this.target.y = 0;

    this.update();
  }

  /**
   * Intersect camera frustum corners with y=0 and return XZ polygon (TL,TR,BR,BL).
   * @returns {THREE.Vector3[]}
   */
  getGroundViewportCorners() {
    const cam = this.camera;
    cam.updateMatrixWorld(true);
    const ndc = [
      new THREE.Vector3(-1, 1, 0.5),
      new THREE.Vector3(1, 1, 0.5),
      new THREE.Vector3(1, -1, 0.5),
      new THREE.Vector3(-1, -1, 0.5)
    ];
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const out = [];
    const hit = new THREE.Vector3();
    for (const p of ndc) {
      p.unproject(cam);
      const dir = p.sub(cam.position).normalize();
      const ray = new THREE.Ray(cam.position, dir);
      if (ray.intersectPlane(plane, hit)) {
        out.push(hit.clone());
      } else {
        // Parallel / behind — fall back near target in that screen direction.
        out.push(this.target.clone());
      }
    }
    return out;
  }

  update() {
    applyRtsCamera(this.camera, this.target, this.distance, {
      fovDegrees: this.fovDegrees,
      far: this.far,
      pitchDegrees: this.pitchDegrees,
      yawDegrees: this.yawDegrees
    });
  }

  dispose() {
    this.domElement.removeEventListener("pointerdown", this._onPointerDown);
    window.removeEventListener("pointerup", this._onPointerUp);
    window.removeEventListener("pointercancel", this._onPointerUp);
    this.domElement.removeEventListener("pointermove", this._onPointerMove);
    this.domElement.removeEventListener("wheel", this._onWheel);
    this.domElement.removeEventListener("contextmenu", this._onContextMenu);
    window.removeEventListener("keydown", this._onKeyDown);
    window.removeEventListener("keyup", this._onKeyUp);
    window.removeEventListener("blur", this._onBlur);
  }
}

/** Serialisable snapshot for docs / bake scripts. */
export function rtsCameraSpec() {
  const pitch = THREE.MathUtils.degToRad(RTS_CAMERA.pitchDegrees);
  const yaw = THREE.MathUtils.degToRad(RTS_CAMERA.yawDegrees);
  return {
    pitchDegrees: RTS_CAMERA.pitchDegrees,
    yawDegrees: RTS_CAMERA.yawDegrees,
    fovDegrees: RTS_CAMERA.fovDegrees,
    defaultDistance: RTS_CAMERA.defaultDistance,
    targetHeight: RTS_CAMERA.targetHeight,
    /** glTF/Three.js position when target is origin. */
    defaultPosition: rtsCameraOffset(RTS_CAMERA.defaultDistance).toArray(),
    /** Blender Z-up equivalent (x, y, z) for bake_sprites.py */
    blenderPosition: [
      Number((RTS_CAMERA.defaultDistance * Math.cos(pitch) * Math.sin(yaw)).toFixed(4)),
      Number((-RTS_CAMERA.defaultDistance * Math.cos(pitch) * Math.cos(yaw)).toFixed(4)),
      Number((RTS_CAMERA.defaultDistance * Math.sin(pitch)).toFixed(4)),
    ],
    note: "Sprite bakes must use this rig; gameplay never orbits away from it.",
  };
}
