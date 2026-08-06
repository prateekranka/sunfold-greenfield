// Locked AoE2-style RTS camera — fixed pitch/yaw, pan + zoom only.
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

const PITCH = THREE.MathUtils.degToRad(RTS_CAMERA.pitchDegrees);
const YAW = THREE.MathUtils.degToRad(RTS_CAMERA.yawDegrees);

/**
 * World-space offset from target to camera for the locked RTS rig.
 * @param {number} [distance]
 * @returns {THREE.Vector3}
 */
export function rtsCameraOffset(distance = RTS_CAMERA.defaultDistance) {
  const horiz = distance * Math.cos(PITCH);
  const y = distance * Math.sin(PITCH);
  const x = horiz * Math.sin(YAW);
  const z = horiz * Math.cos(YAW);
  return new THREE.Vector3(x, y, z);
}

/**
 * Apply the locked RTS transform to a PerspectiveCamera.
 * @param {THREE.PerspectiveCamera} camera
 * @param {THREE.Vector3} target ground-plane look-at (y = targetHeight applied)
 * @param {number} [distance]
 */
export function applyRtsCamera(camera, target, distance = RTS_CAMERA.defaultDistance) {
  const look = target.clone();
  look.y = RTS_CAMERA.targetHeight;
  camera.position.copy(look).add(rtsCameraOffset(distance));
  camera.lookAt(look);
  camera.fov = RTS_CAMERA.fovDegrees;
  camera.near = RTS_CAMERA.near;
  camera.far = RTS_CAMERA.far;
  camera.updateProjectionMatrix();
}

/**
 * @param {number} aspect width / height
 * @returns {THREE.PerspectiveCamera}
 */
export function createRtsCamera(aspect = 16 / 9) {
  const camera = new THREE.PerspectiveCamera(
    RTS_CAMERA.fovDegrees,
    aspect,
    RTS_CAMERA.near,
    RTS_CAMERA.far
  );
  applyRtsCamera(camera, new THREE.Vector3(0, 0, 0));
  return camera;
}

/**
 * Pan-only controller: wheel zooms, drag pans on the XZ plane.
 * No orbit — yaw and pitch stay locked.
 */
export class RtsCameraController {
  /**
   * @param {THREE.PerspectiveCamera} camera
   * @param {HTMLElement} domElement
   * @param {{ target?: THREE.Vector3, distance?: number }} [opts]
   */
  constructor(camera, domElement, opts = {}) {
    this.camera = camera;
    this.domElement = domElement;
    this.target = opts.target?.clone() ?? new THREE.Vector3(0, 0, 0);
    this.distance = opts.distance ?? RTS_CAMERA.defaultDistance;
    this._dragging = false;
    this._lastX = 0;
    this._lastY = 0;

    this._onPointerDown = (e) => {
      this._dragging = true;
      this._lastX = e.clientX;
      this._lastY = e.clientY;
    };
    this._onPointerUp = () => {
      this._dragging = false;
    };
    this._onPointerMove = (e) => {
      if (!this._dragging) return;
      const dx = e.clientX - this._lastX;
      const dy = e.clientY - this._lastY;
      this._lastX = e.clientX;
      this._lastY = e.clientY;
      const panScale = this.distance * 0.0012;
      const right = new THREE.Vector3(Math.cos(YAW), 0, -Math.sin(YAW));
      const forward = new THREE.Vector3(-Math.sin(YAW), 0, -Math.cos(YAW));
      this.target.addScaledVector(right, -dx * panScale);
      this.target.addScaledVector(forward, dy * panScale);
      this.update();
    };
    this._onWheel = (e) => {
      e.preventDefault();
      const factor = 1 + e.deltaY * 0.001;
      this.distance = THREE.MathUtils.clamp(
        this.distance * factor,
        RTS_CAMERA.minDistance,
        RTS_CAMERA.maxDistance
      );
      this.update();
    };

    domElement.addEventListener("pointerdown", this._onPointerDown);
    window.addEventListener("pointerup", this._onPointerUp);
    domElement.addEventListener("pointermove", this._onPointerMove);
    domElement.addEventListener("wheel", this._onWheel, { passive: false });
  }

  update() {
    applyRtsCamera(this.camera, this.target, this.distance);
  }

  dispose() {
    this.domElement.removeEventListener("pointerdown", this._onPointerDown);
    window.removeEventListener("pointerup", this._onPointerUp);
    this.domElement.removeEventListener("pointermove", this._onPointerMove);
    this.domElement.removeEventListener("wheel", this._onWheel);
  }
}

/** Serialisable snapshot for docs / bake scripts. */
export function rtsCameraSpec() {
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
      Number((RTS_CAMERA.defaultDistance * Math.cos(PITCH) * Math.sin(YAW)).toFixed(4)),
      Number((-RTS_CAMERA.defaultDistance * Math.cos(PITCH) * Math.cos(YAW)).toFixed(4)),
      Number((RTS_CAMERA.defaultDistance * Math.sin(PITCH)).toFixed(4)),
    ],
    note: "Sprite bakes must use this rig; gameplay never orbits away from it.",
  };
}
