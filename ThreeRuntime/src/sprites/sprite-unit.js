// AoE2-style billboard sprite unit — picks sheet frame from yaw + clip.
//
// Two playback modes (manifest.playback):
//   - "frames" (default): one PNG per clip/facing/frame (legacy bake tree)
//   - "atlas": one packed sprite sheet; UVs advance via texture.offset/repeat
//     (Gemini-style sheet integration)

import * as THREE from "three";
import {
  yawToFacing,
  yawToFacing16,
  yawToFacingStable,
  yawToFacing16Stable,
  facingMirror,
  facing16ToIdle8Column
} from "./facing.js";
import { atlasCellUV, atlasFrameCell, applyAtlasUV, applyAtlasUVGeometry } from "./atlas.js";

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
    /** Playback rate; 0 freezes the current frame (idle standing hold). */
    this.playbackSpeed = 1;
    this.yaw = 0;
    this.facing = 0;
    this.textures = new Map();
    /** @type {THREE.Texture | null} */
    this._atlasTexture = null;
    /** When true, `_atlasTexture` is a clone sharing an image with other units. */
    this._atlasTextureIsClone = false;
    /** When true, atlas cell UVs are written to mesh geometry (shared Texture). */
    this._atlasUvOnGeometry = false;
    /** @type {Map<string, THREE.Texture>} per-clip override atlases (e.g. dedicated idle). */
    this._clipAtlasTextures = new Map();
    this._worldHeight = 1.25;
    if (manifest?.frameWidth) this._syncWorldHeight();
  }

  /**
   * Bind a shared atlas image with a per-unit UV transform.
   * Mutating `texture.offset`/`repeat` must not race across citizens.
   * @param {THREE.Texture} texture
   */
  /**
   * Bind a shared atlas image. UV is applied per-mesh via geometry attributes
   * so units must NOT clone() the texture (each clone = full GPU re-upload).
   * @param {THREE.Texture} texture
   */
  useSharedAtlas(texture) {
    if (!texture) return;
    // Keep offset/repeat identity — cell windows live on geometry UVs.
    texture.offset.set(0, 0);
    texture.repeat.set(1, 1);
    texture.wrapS = THREE.ClampToEdgeWrapping;
    texture.wrapT = THREE.ClampToEdgeWrapping;
    this._atlasTexture = texture;
    this._atlasTextureIsClone = false;
    this._atlasUvOnGeometry = true;
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
    // Idle is a standing hold — never advance into a walk/gather cycle.
    if (clip === "idle") this.playbackSpeed = 0;
    else if (this.playbackSpeed === 0) this.playbackSpeed = 1;
    // Show a stand-in billboard immediately so camera framing / match proofs
    // still see citizens if the atlas PNG is slow or fails under WKWebView.
    this._ensurePlaceholder();
    await this._applyFrame(facing, 0);
  }

  /**
   * Freeze on a specific standing cell (idle hold without clip advance).
   * @param {number} [frame=0]
   */
  freezeStanding(frame = 0) {
    this.playbackSpeed = 0;
    this.frameIndex = Math.max(0, frame | 0);
    this.frameTime = 0;
    return this._applyFrame(this.facing, this.frameIndex);
  }

  /**
   * Gameplay API alias: `unit.setState("walk")` → clip switch.
   * Accepted states: idle | walk | carry | gather | build (sheet-dependent).
   * @param {string} state
   * @param {number} [facing]
   */
  async setState(state, facing = this.facing) {
    return this.setClip(state, facing);
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

  /** Facing count from the manifest (8 classic AoE2 or 16 golden sheets). */
  get _facingCount() {
    const n = this.manifest?.facings?.length ?? this.manifest?.directionCount ?? 8;
    return n === 16 ? 16 : 8;
  }

  /** @param {number} yawRadians */
  setYaw(yawRadians) {
    this.yaw = yawRadians;
    const next =
      this._facingCount === 16
        ? yawToFacing16Stable(yawRadians, this.facing)
        : yawToFacingStable(yawRadians, this.facing);
    if (next !== this.facing) {
      this.facing = next;
      if (this._isAtlas && (this._atlasTexture || this._clipAtlasTextures.has(this.clip))) {
        this._applyAtlasFrameSync(next, this.frameIndex);
      } else {
        this._applyFrame(next, this.frameIndex).catch(console.error);
      }
    }
  }

  /**
   * Force facing from yaw without hysteresis (spawn / explicit snaps).
   * @param {number} yawRadians
   */
  setYawImmediate(yawRadians) {
    this.yaw = yawRadians;
    const next =
      this._facingCount === 16 ? yawToFacing16(yawRadians) : yawToFacing(yawRadians);
    if (next !== this.facing) {
      this.facing = next;
      this._applyFrame(next, this.frameIndex).catch(console.error);
    }
  }

  /** @param {number} facingIndex 0–7 or 0–15 */
  setFacing(facingIndex) {
    const steps = this._facingCount;
    const next = ((facingIndex % steps) + steps) % steps;
    this.facing = next;
    this.yaw = (next * Math.PI * 2) / steps;
    this._applyFrame(next, this.frameIndex).catch(console.error);
  }

  /** @param {number} dt seconds */
  update(dt) {
    const clips = this.manifest?.clips;
    if (!clips) return;
    const def = clips[this.clip];
    if (!def || def.frames <= 1) return;
    const speed = this.playbackSpeed;
    if (!speed || speed <= 0) return;
    // Cap catch-up so a hitch does not skip half a clip in one paint.
    const fps = Math.max(1, def.fps ?? this.manifest.fps ?? 10);
    const frameDuration = 1 / fps;
    this.frameTime += Math.min(dt * speed, frameDuration * 2.5);
    let advanced = false;
    while (this.frameTime >= frameDuration) {
      this.frameTime -= frameDuration;
      this.frameIndex += 1;
      if (this.frameIndex >= def.frames) {
        this.frameIndex = def.loop ? 0 : def.frames - 1;
      }
      advanced = true;
    }
    if (advanced) {
      // Atlas UV swap is sync once textures are warm — avoid Promise churn.
      if (this._isAtlas) {
        this._applyAtlasFrameSync(this.facing, this.frameIndex);
      } else {
        this._applyFrame(this.facing, this.frameIndex).catch(console.error);
      }
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
    const clip = this.manifest.clips[this.clip];
    if (!clip) return;
    const atlas = clip.atlas || this.manifest.atlas;
    if (!atlas) return;
    const tex = clip.atlas
      ? await this._loadClipAtlasTexture(this.clip, atlas)
      : await this._loadAtlasTexture();
    this._bindAtlasCell(tex, atlas, clip, facing, frame);
  }

  /**
   * Hot path: atlas already loaded — no await / Promise.
   * @param {number} facing
   * @param {number} frame
   */
  _applyAtlasFrameSync(facing, frame) {
    const clip = this.manifest.clips[this.clip];
    if (!clip) return;
    const atlas = clip.atlas || this.manifest.atlas;
    if (!atlas) return;
    const tex = clip.atlas
      ? this._clipAtlasTextures.get(this.clip)
      : this._atlasTexture;
    if (!tex) {
      this._applyAtlasFrame(facing, frame).catch(console.error);
      return;
    }
    this._bindAtlasCell(tex, atlas, clip, facing, frame);
  }

  /**
   * Share a per-clip atlas (e.g. dedicated idle strip) without cloning.
   * @param {string} clipName
   * @param {THREE.Texture} texture
   */
  useSharedClipAtlas(clipName, texture) {
    if (!clipName || !texture) return;
    texture.offset.set(0, 0);
    texture.repeat.set(1, 1);
    texture.wrapS = THREE.ClampToEdgeWrapping;
    texture.wrapT = THREE.ClampToEdgeWrapping;
    this._clipAtlasTextures.set(clipName, texture);
    this._atlasUvOnGeometry = true;
  }

  /**
   * @param {THREE.Texture} tex
   * @param {import("./atlas.js").AtlasSpec} atlas
   * @param {SpriteClipDef & { atlas?: import("./atlas.js").AtlasSpec, facingCount?: number }} clip
   * @param {number} facing
   * @param {number} frame
   */
  _bindAtlasCell(tex, atlas, clip, facing, frame) {
    let row;
    let column;
    // Dedicated idle strip: 1 row × 8 compass columns (NE…N), not facing-grid rows.
    if (clip.atlas && atlas.rows === 1 && (clip.facingCount === 8 || atlas.columns === 8)) {
      row = 0;
      column = facing16ToIdle8Column(facing);
    } else {
      const facingCount = this.manifest.facings?.length ?? 8;
      ({ row, column } = atlasFrameCell(atlas, clip, facing, frame, facingCount));
    }
    const uv = atlasCellUV(
      atlas,
      this.manifest.frameWidth,
      this.manifest.frameHeight,
      row,
      column
    );
    const mirror =
      this._mirrorAtRuntime &&
      !atlas.singleFacing &&
      facingMirror(facing).mirror;
    this._ensureMesh(tex);
    if (this._atlasUvOnGeometry && this.mesh?.geometry) {
      // Shared Texture: keep identity transform; cell window on the plane UVs.
      tex.offset.set(0, 0);
      tex.repeat.set(1, 1);
      applyAtlasUVGeometry(this.mesh.geometry, uv, mirror);
    } else {
      applyAtlasUV(tex, uv, mirror);
    }
    // Atlas mirror is already in the UV; keep mesh scale identity.
    this.mesh.scale.x = 1;
  }

  /**
   * Load a per-clip override atlas (dedicated idle sheet, etc.).
   * @param {string} clipName
   * @param {import("./atlas.js").AtlasSpec} atlas
   */
  async _loadClipAtlasTexture(clipName, atlas) {
    if (this._clipAtlasTextures.has(clipName)) return this._clipAtlasTextures.get(clipName);
    const image = atlas.image;
    const isDirect =
      typeof image === "string" &&
      (image.startsWith("data:") ||
        image.startsWith("blob:") ||
        image.startsWith("http:") ||
        image.startsWith("https:") ||
        image.startsWith("file:"));
    const candidates = [];
    if (isDirect) {
      candidates.push(image);
    } else if (typeof window !== "undefined" && window.location?.href) {
      const base = window.location.href;
      candidates.push(new URL(`${this.basePath}${image}`, base).href);
      candidates.push(new URL(image, base).href);
    } else {
      candidates.push(`${this.basePath}${image}`);
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
              if (this.manifest?.premultipliedAlpha) {
                t.premultiplyAlpha = false;
              }
              resolve(t);
            },
            undefined,
            (err) => reject(err || new Error(`clip atlas failed: ${String(path).slice(0, 64)}`))
          );
        });
        this._clipAtlasTextures.set(clipName, tex);
        return tex;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError || new Error(`clip atlas failed for ${clipName}`);
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
      const premul = this.manifest?.premultipliedAlpha === true;
      const mat = new THREE.MeshBasicMaterial({
        map: tex,
        transparent: true,
        alphaTest: premul ? 0.05 : 0.25,
        premultipliedAlpha: premul,
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
    // Only flag material.needsUpdate when the map object actually changes —
    // flipping it every clip frame forces program rebuilds and kills FPS.
    const mat = this.mesh.material;
    const mapChanged = mat.map !== tex;
    if (mapChanged) mat.map = tex;
    if (mat.color && mat.color.getHex() !== 0xffffff) mat.color.set(0xffffff);
    if (mat.opacity !== 1) mat.opacity = 1;
    const wantAlpha = this.manifest?.premultipliedAlpha === true ? 0.05 : 0.25;
    if (mat.alphaTest !== wantAlpha) mat.alphaTest = wantAlpha;
    if (mapChanged) mat.needsUpdate = true;
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
      // UV matrix only — never re-upload pixels.
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
              // Premultiplied atlases must not be re-premultiplied by the GPU sampler path.
              if (this.manifest?.premultipliedAlpha) {
                t.premultiplyAlpha = false;
              }
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
