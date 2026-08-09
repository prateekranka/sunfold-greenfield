// Golden Sunwoven Foundation Citizen — 16-direction masked billboard.
//
// Plays sunfold.sprite-manifest/2 sheets (playback "atlas16"): per-clip
// albedo / normal / emissive atlases, 16 direction columns, one clip atlas
// per channel. Lighting is computed at runtime from the baked WORLD-space
// normal mask; emissive accents are added unlit so the post-process bloom
// picks them up. Textures are cached per (sheet, clip, channel) and shared by
// every unit — per-frame UV motion is carried by shader uniforms, so a crowd
// of units costs 12 textures total, not 12 × N.
//
// The sheet is baked at the locked RTS angles (pitch 57°, yaw 45°), so the
// billboard faces the camera at yaw 45° and picks cell = round(worldYaw/22.5°)
// — exactly what the 3D model would show under the gameplay camera.

import * as THREE from "three";
import { yawToFacing16 } from "./facing.js";

const VERTEX_SHADER = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const FRAGMENT_SHADER = /* glsl */ `
  uniform sampler2D uAlbedo;
  uniform sampler2D uNormal;
  uniform sampler2D uEmissive;
  uniform vec2 uRepeat;
  uniform vec2 uOffset;
  uniform vec3 uLightDir;
  uniform float uKeyIntensity;
  uniform float uAmbient;
  uniform float uEmissiveBoost;
  uniform vec3 uTint;
  varying vec2 vUv;

  void main() {
    vec2 cellUv = vUv * uRepeat + uOffset;
    vec4 albedo = texture2D(uAlbedo, cellUv);
    if (albedo.a < 0.25) discard;
    vec3 n = normalize(texture2D(uNormal, cellUv).rgb * 2.0 - 1.0);
    float diff = max(dot(n, uLightDir), 0.0);
    vec3 emissive = texture2D(uEmissive, cellUv).rgb * uEmissiveBoost;
    vec3 color = albedo.rgb * uTint * (uAmbient + uKeyIntensity * diff) + emissive;
    gl_FragColor = vec4(color, albedo.a);
  }
`;

/** Shared per-(sheet, clip, channel) texture cache — one texture, all units. */
const textureCache = new Map();
const textureLoader = new THREE.TextureLoader();

function cacheKey(basePath, clip, channel) {
  return `${basePath}|${clip}|${channel}`;
}

function loadTexture(url, linear) {
  return new Promise((resolve, reject) => {
    textureLoader.load(
      url,
      (texture) => {
        texture.colorSpace = linear ? THREE.NoColorSpace : THREE.SRGBColorSpace;
        texture.magFilter = THREE.LinearFilter;
        texture.minFilter = THREE.LinearFilter;
        texture.generateMipmaps = false;
        texture.wrapS = THREE.ClampToEdgeWrapping;
        texture.wrapT = THREE.ClampToEdgeWrapping;
        resolve(texture);
      },
      undefined,
      reject
    );
  });
}

/** @param {object} manifest sunfold.sprite-manifest/2 (playback atlas16) */
export function isGoldenManifest(manifest) {
  return Boolean(manifest && (manifest.playback === "atlas16" || manifest.schema === "sunfold.sprite-manifest/2"));
}

/**
 * @param {object} manifest
 * @param {{basePath?: string}} [opts]
 */
export class GoldenSpriteUnit {
  constructor(manifest = null, opts = {}) {
    this.manifest = manifest;
    this.basePath = opts.basePath ?? "";
    this.group = new THREE.Group();
    this.material = null;
    this.mesh = null;
    this.clip = "idle";
    this.frameIndex = 0;
    this.frameTime = 0;
    this.yaw = 0;
    this.facing = 0;
    this._worldHeight = manifest?.worldHeight ?? 2.6;
    if (manifest) this._initMesh();
  }

  _initMesh() {
    if (this.mesh) return;
    const aspect = (this.manifest.frameWidth || 160) / (this.manifest.frameHeight || 160);
    const height = this._worldHeight;
    const width = height * aspect;
    const geo = new THREE.PlaneGeometry(width, height);
    // Sit the figure's ground line (anchor.y from the top) on y = 0.
    const footroom = 1 - (this.manifest.anchor?.y ?? 0.8);
    geo.translate(0, height * (0.5 - footroom), 0);
    this.material = new THREE.ShaderMaterial({
      uniforms: {
        uAlbedo: { value: null },
        uNormal: { value: null },
        uEmissive: { value: null },
        uRepeat: { value: new THREE.Vector2(1 / 16, 1) },
        uOffset: { value: new THREE.Vector2(0, 0) },
        uLightDir: { value: new THREE.Vector3(0.33, -0.83, -0.41).normalize() },
        uKeyIntensity: { value: 0.7 },
        uAmbient: { value: 0.25 },
        uEmissiveBoost: { value: 1.6 },
        uTint: { value: new THREE.Color(1, 1, 1) }
      },
      vertexShader: VERTEX_SHADER,
      fragmentShader: FRAGMENT_SHADER,
      transparent: true,
      alphaTest: 0.25,
      depthWrite: false,
      side: THREE.DoubleSide
    });
    this.mesh = new THREE.Mesh(geo, this.material);
    // Locked RTS camera sits at yaw 45° — face the billboard toward it.
    this.group.rotation.y = THREE.MathUtils.degToRad(45);
    this.group.add(this.mesh);
  }

  async loadManifest(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`golden manifest ${url}: HTTP ${res.status}`);
    this.manifest = await res.json();
    this._initMesh();
    await this.setClip("idle");
    return this.manifest;
  }

  async applyManifest(manifest) {
    this.manifest = manifest;
    this._initMesh();
    await this.setClip("idle");
    return this.manifest;
  }

  async setClip(clip, facing = this.facing) {
    this.clip = clip;
    this.frameIndex = 0;
    this.frameTime = 0;
    await this._applyFrame(facing, 0);
  }

  setYaw(yawRadians) {
    this.yaw = yawRadians;
    const next = yawToFacing16(yawRadians);
    if (next !== this.facing) {
      this.facing = next;
      this._applyFrame(next, this.frameIndex).catch(console.error);
    }
  }

  setFacing(facingIndex) {
    const next = ((facingIndex % 16) + 16) % 16;
    this.facing = next;
    this.yaw = (next * Math.PI * 2) / 16;
    this._applyFrame(next, this.frameIndex).catch(console.error);
  }

  update(dt) {
    const def = this.manifest?.clips?.[this.clip];
    if (!def || def.frames <= 1) return;
    const fps = def.fps ?? this.manifest.fps ?? 10;
    this.frameTime += dt;
    const frameDuration = 1 / fps;
    while (this.frameTime >= frameDuration) {
      this.frameTime -= frameDuration;
      this.frameIndex += 1;
      if (this.frameIndex >= def.frames) {
        this.frameIndex = def.loop ? 0 : def.frames - 1;
      }
      this._applyFrame(this.facing, this.frameIndex).catch(console.error);
    }
  }

  setPosition(position) {
    this.group.position.copy(position);
  }

  async _applyFrame(facing, frame) {
    const def = this.manifest.clips[this.clip];
    if (!def) return;
    const textures = await this._loadClipTextures(this.clip, def);
    if (!textures) return;
    const columns = this.manifest.directionColumns ?? 16;
    const col = ((facing % columns) + columns) % columns;
    const row = ((frame % def.frames) + def.frames) % def.frames;
    const repeatX = 1 / columns;
    const repeatY = 1 / def.frames;
    const u = this.material.uniforms;
    u.uAlbedo.value = textures.albedo;
    u.uNormal.value = textures.normal;
    u.uEmissive.value = textures.emissive;
    u.uRepeat.value.set(repeatX, repeatY);
    // Row 0 of the PNG is the top; flipY means V=1 is the top.
    u.uOffset.value.set(col * repeatX, 1 - (row + 1) * repeatY);
  }

  async _loadClipTextures(clip, def) {
    const channels = def.channels ?? {};
    const keys = ["albedo", "normal", "emissive"];
    const out = {};
    for (const channel of keys) {
      const file = channels[channel];
      if (!file) return null;
      const key = cacheKey(this.basePath, clip, channel);
      let promise = textureCache.get(key);
      if (!promise) {
        promise = loadTexture(`${this.basePath}${file}`, channel !== "albedo");
        textureCache.set(key, promise);
      }
      try {
        out[channel] = await promise;
      } catch (error) {
        console.error(`golden texture ${file}: ${error?.message ?? error}`);
        return null;
      }
    }
    return out;
  }
}
