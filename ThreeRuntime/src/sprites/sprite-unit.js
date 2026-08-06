// AoE2-style billboard sprite unit — picks sheet frame from yaw + clip.
//
// Two playback modes (manifest.playback):
//   - "frames" (default): one PNG per clip/facing/frame (legacy bake tree)
//   - "atlas": one packed sprite sheet; UVs advance via texture.offset/repeat
//     (Gemini-style sheet integration)

import * as THREE from "three";
import { yawToFacing, facingMirror } from "./facing.js";
import { atlasCellUV, atlasFrameCell, applyAtlasUV } from "./atlas.js";

/**
 * @typedef {object} SpriteClipDef
 * @property {number} frames
 * @property {boolean} loop
 * @property {"real"|"stub"|"partial"} source
 * @property {number} [fps]
 * @property {number} [originRow]
 */

/**
 * @typedef {object} SpriteManifest
 * @property {string} unit
 * @property {number} frameWidth
 * @property {number} frameHeight
 * @property {number} fps
 * @property {string[]} facings
 * @property {Record<string, SpriteClipDef>} clips
 * @property {Record<string, string>} [paths] clip → directory prefix
 * @property {number} [worldHeight] whole frame height in metres
 * @property {{x: number, y: number}} [anchor] where the figure meets the ground,
 *   as a fraction of the frame measured from the top-left
 * @property {boolean} [mirrorAtRuntime] false when facings 5–7 are already
 *   mirrored on disk. Absent means true, which is what the older sheets expect.
 * @property {"frames"|"atlas"} [playback]
 * @property {import("./atlas.js").AtlasSpec} [atlas]
 */

export class SpriteUnit {
  /**
   * @param {SpriteManifest} manifest
   * @param {{ basePath?: string }} [opts]
   */
  constructor(manifest, opts = {}) {
    this.manifest = manifest;
    this.basePath = opts.basePath ?? "";
    this.group = new THREE.Group();
    this.mesh = null;
    this.clip = "idle";
    this.frameIndex = 0;
    this.frameTime = 0;
    this.yaw = 0;
    this.facing = 0;
    this.textures = new Map();
    /** @type {THREE.Texture | null} */
    this._atlasTexture = null;
    this._worldHeight = 1.25;
    if (manifest?.frameWidth) this._syncWorldHeight();
  }

  get _isAtlas() {
    return this.manifest?.playback === "atlas" && Boolean(this.manifest?.atlas);
  }

  /** Recompute billboard height once manifest dimensions are known. */
  _syncWorldHeight() {
    const { frameHeight, frameWidth, worldHeight } = this.manifest;
    if (worldHeight > 0) {
      // The bake measured this: the frame in metres, padding included.
      this._worldHeight = worldHeight;
    } else if (frameHeight > 0 && frameWidth > 0) {
      // Older sheets carry no world height; citizens are authored with padding,
      // so scale up for a readable in-world height.
      this._worldHeight = (frameHeight / frameWidth) * 3.5;
    }
  }

  /** Fraction of the frame below the figure's ground line. */
  get _footroom() {
    const y = this.manifest?.anchor?.y;
    return typeof y === "number" ? 1 - y : 0;
  }

  /** True when facings 5–7 must be flipped by the player rather than on disk. */
  get _mirrorAtRuntime() {
    return this.manifest?.mirrorAtRuntime !== false;
  }

  /** @param {string} url */
  async loadManifest(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`manifest ${url}: HTTP ${res.status}`);
    this.manifest = await res.json();
    this._syncWorldHeight();
    await this.setClip("idle");
    return this.manifest;
  }

  /**
   * Apply an already-parsed manifest (avoids fetch under strict CSP).
   * @param {SpriteManifest} manifest
   */
  async applyManifest(manifest) {
    this.manifest = manifest;
    this._syncWorldHeight();
    await this.setClip("idle");
    return this.manifest;
  }

  /**
   * @param {string} clip
   * @param {number} [facing]
   */
  async setClip(clip, facing = this.facing) {
    this.clip = clip;
    this.frameIndex = 0;
    this.frameTime = 0;
    // Show a stand-in billboard immediately so camera framing / match proofs
    // still see citizens if the atlas PNG is slow or fails under WKWebView.
    this._ensurePlaceholder();
    await this._applyFrame(facing, 0);
  }

  /** Solid-color billboard until the atlas texture binds. */
  _ensurePlaceholder() {
    if (this.mesh) return;
    const aspect = (this.manifest?.frameWidth || 1) / (this.manifest?.frameHeight || 1);
    const height = this._worldHeight;
    const width = height * aspect;
    const geo = new THREE.PlaneGeometry(width, height);
    geo.translate(0, height * (0.5 - this._footroom), 0);
    const mat = new THREE.MeshBasicMaterial({
      color: 0x7ec8e3,
      transparent: true,
      opacity: 0.85,
      side: THREE.DoubleSide,
      depthWrite: false
    });
    this.mesh = new THREE.Mesh(geo, mat);
    this.group.rotation.y = THREE.MathUtils.degToRad(45);
    this.group.add(this.mesh);
  }

  /** @param {number} yawRadians */
  setYaw(yawRadians) {
    this.yaw = yawRadians;
    const next = yawToFacing(yawRadians);
    if (next !== this.facing) {
      this.facing = next;
      this._applyFrame(next, this.frameIndex).catch(console.error);
    }
  }

  /** @param {number} facingIndex 0–7 */
  setFacing(facingIndex) {
    const next = ((facingIndex % 8) + 8) % 8;
    this.facing = next;
    this.yaw = (next * Math.PI * 2) / 8;
    this._applyFrame(next, this.frameIndex).catch(console.error);
  }

  /** @param {number} dt seconds */
  update(dt) {
    const clips = this.manifest?.clips;
    if (!clips) return;
    const def = clips[this.clip];
    if (!def || def.frames <= 1) return;
    const fps = def.fps ?? this.manifest.fps;
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

  /**
   * @param {THREE.Vector3} position
   */
  setPosition(position) {
    this.group.position.copy(position);
  }

  /** @param {number} facing @param {number} frame */
  async _applyFrame(facing, frame) {
    if (this._isAtlas) {
      await this._applyAtlasFrame(facing, frame);
      return;
    }
    const tex = await this._loadTexture(this.clip, facing, frame);
    this._ensureMesh(tex);
    this.mesh.material.map = tex;
    this.mesh.material.needsUpdate = true;
    this._applyMirror(facing);
  }

  /** @param {number} facing @param {number} frame */
  async _applyAtlasFrame(facing, frame) {
    const tex = await this._loadAtlasTexture();
    const clip = this.manifest.clips[this.clip];
    if (!clip) return;
    const { row, column } = atlasFrameCell(
      this.manifest.atlas,
      clip,
      facing,
      frame,
      this.manifest.facings?.length ?? 8
    );
    const uv = atlasCellUV(
      this.manifest.atlas,
      this.manifest.frameWidth,
      this.manifest.frameHeight,
      row,
      column
    );
    const mirror =
      this._mirrorAtRuntime &&
      !this.manifest.atlas.singleFacing &&
      facingMirror(facing).mirror;
    applyAtlasUV(tex, uv, mirror);
    this._ensureMesh(tex);
    // Atlas mirror is already in the UV; keep mesh scale identity.
    this.mesh.scale.x = 1;
  }

  /** @param {THREE.Texture} tex */
  _ensureMesh(tex) {
    const aspect = this.manifest.frameWidth / this.manifest.frameHeight;
    const height = this._worldHeight;
    const width = height * aspect;

    if (!this.mesh) {
      const geo = new THREE.PlaneGeometry(width, height);
      // Sit the figure's ground line on y = 0, not the bottom edge of the frame.
      // The frame keeps footroom under the feet so a stride or a dropped tool is
      // not clipped; without this offset the unit floats by exactly that much.
      geo.translate(0, height * (0.5 - this._footroom), 0);
      const mat = new THREE.MeshBasicMaterial({
        map: tex,
        transparent: true,
        alphaTest: 0.25,
        side: THREE.DoubleSide,
        depthWrite: false,
      });
      this.mesh = new THREE.Mesh(geo, mat);
      // Locked RTS camera sits at yaw 45° — face the billboard toward it.
      this.group.rotation.y = THREE.MathUtils.degToRad(45);
      this.group.add(this.mesh);
      return;
    }

    // Upgrade placeholder (or prior map) to the atlas texture.
    const mat = this.mesh.material;
    mat.map = tex;
    mat.color?.set?.(0xffffff);
    mat.opacity = 1;
    mat.alphaTest = 0.25;
    mat.needsUpdate = true;
  }

  /** @param {number} facing */
  _applyMirror(facing) {
    if (!this.mesh) return;
    // A sheet baked with all eight facings already flipped must not be flipped
    // again here, or NW, W and SW come out facing backwards.
    const mirror = this._mirrorAtRuntime && facingMirror(facing).mirror;
    this.mesh.scale.x = 1;
    const map = this.mesh.material.map;
    if (map) {
      map.wrapS = THREE.RepeatWrapping;
      map.repeat.x = mirror ? -1 : 1;
      map.offset.x = mirror ? 1 : 0;
      map.needsUpdate = true;
    }
  }

  async _loadAtlasTexture() {
    if (this._atlasTexture) return this._atlasTexture;
    const image = this.manifest.atlas.image;
    // data: URLs (esbuild dataurl loader) and absolute http(s)/file URLs load as-is.
    const isDirect =
      typeof image === "string" &&
      (image.startsWith("data:") ||
        image.startsWith("blob:") ||
        image.startsWith("http:") ||
        image.startsWith("https:") ||
        image.startsWith("file:"));
    const unit = this.manifest.unit || "unit";
    const candidates = [];
    if (isDirect) {
      candidates.push(image);
    } else if (typeof window !== "undefined" && window.location?.href) {
      const base = window.location.href;
      candidates.push(new URL(`${this.basePath}${image}`, base).href);
      candidates.push(new URL(`${unit}-runtime-atlas.png`, base).href);
      candidates.push(new URL(image, base).href);
    } else {
      candidates.push(`${this.basePath}${image}`);
      candidates.push(`${unit}-runtime-atlas.png`);
    }
    let lastError = null;
    for (const path of candidates) {
      try {
        const tex = await new Promise((resolve, reject) => {
          const loader = new THREE.TextureLoader();
          loader.load(
            path,
            (t) => {
              t.colorSpace = THREE.SRGBColorSpace;
              t.magFilter = THREE.LinearFilter;
              t.minFilter = THREE.LinearFilter;
              t.generateMipmaps = false;
              t.wrapS = THREE.RepeatWrapping;
              t.wrapT = THREE.RepeatWrapping;
              resolve(t);
            },
            undefined,
            (err) => reject(err || new Error(`atlas texture failed: ${String(path).slice(0, 64)}`))
          );
        });
        this._atlasTexture = tex;
        return tex;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError || new Error("atlas texture failed");
  }

  /**
   * @param {string} clip
   * @param {number} facing
   * @param {number} frame
   */
  async _loadTexture(clip, facing, frame) {
    const key = `${clip}/${facing}/${frame}`;
    if (this.textures.has(key)) return this.textures.get(key);

    const def = this.manifest?.clips?.[clip];
    const multi = def && def.frames > 1;
    const path = multi
      ? `${this.basePath}${clip}/${facing}/${frame}.png`
      : `${this.basePath}${clip}/${facing}.png`;

    const tex = await new Promise((resolve, reject) => {
      const loader = new THREE.TextureLoader();
      loader.load(
        path,
        (t) => {
          // Leave flipY at Three's default. The sheets are ordinary top-down
          // PNGs, and forcing it off stood every unit on its head.
          t.colorSpace = THREE.SRGBColorSpace;
          t.magFilter = THREE.LinearFilter;
          t.minFilter = THREE.LinearMipmapLinearFilter;
          resolve(t);
        },
        undefined,
        reject
      );
    });
    this.textures.set(key, tex);
    return tex;
  }
}
