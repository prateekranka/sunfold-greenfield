// Sprite-sheet (atlas) UV helpers for AoE2-style unit playback.
//
// Gemini's packed sheet suggestion: one texture, many frames. The player sets
// `texture.repeat` / `texture.offset` so a single MeshBasicMaterial map shows
// the active clip × facing × frame without loading hundreds of PNGs.

/**
 * @typedef {object} AtlasClipDef
 * @property {number} frames
 * @property {number} [fps]
 * @property {boolean} [loop]
 * @property {number} originRow  facing-row index from the top of the atlas
 *   (multi-facing) OR clip-row index when `layout === "clip-rows"`.
 */

/**
 * @typedef {object} AtlasSpec
 * @property {string} image
 * @property {number} width
 * @property {number} height
 * @property {number} columns
 * @property {number} rows
 * @property {"facing-grid"|"clip-rows"} [layout]
 * @property {boolean} [singleFacing]
 */

/**
 * UV window for one cell. Three.js default `flipY=true` means V=0 is the
 * bottom of the image, so row 0 (top of the PNG) maps to high V.
 *
 * @param {AtlasSpec} atlas
 * @param {number} frameWidth
 * @param {number} frameHeight
 * @param {number} row  zero-based row from the top of the atlas
 * @param {number} column  zero-based column from the left
 * @returns {{ repeatX: number, repeatY: number, offsetX: number, offsetY: number }}
 */
export function atlasCellUV(atlas, frameWidth, frameHeight, row, column) {
  const repeatX = frameWidth / atlas.width;
  const repeatY = frameHeight / atlas.height;
  const offsetX = column * repeatX;
  // Top row (row 0) sits just under V=1 after flipY.
  const offsetY = 1 - (row + 1) * repeatY;
  return { repeatX, repeatY, offsetX, offsetY };
}

/**
 * Resolve the atlas row/column for a clip frame.
 *
 * - `facing-grid` (default): each clip owns `facings.length` consecutive rows
 *   starting at `clip.originRow`; column = frame index.
 * - `clip-rows`: one row per clip (`originRow`); facing is ignored; column = frame.
 *
 * @param {AtlasSpec} atlas
 * @param {AtlasClipDef} clip
 * @param {number} facing
 * @param {number} frame
 * @param {number} [facingCount=8]
 * @returns {{ row: number, column: number }}
 */
export function atlasFrameCell(atlas, clip, facing, frame, facingCount = 8) {
  const column = ((frame % clip.frames) + clip.frames) % clip.frames;
  if (atlas.layout === "clip-rows" || atlas.singleFacing) {
    return { row: clip.originRow, column };
  }
  const facingIndex = ((facing % facingCount) + facingCount) % facingCount;
  return { row: clip.originRow + facingIndex, column };
}

/**
 * Apply a cell UV to a Three.js texture (mutates in place).
 * Prefer {@link applyAtlasUVGeometry} when many meshes share one atlas image —
 * texture.offset/repeat cannot be shared without racing, and Texture.clone()
 * allocates a separate GPU upload of the full sheet per unit.
 * @param {{ repeat: { set: Function }, offset: { set: Function }, needsUpdate?: boolean }} texture
 * @param {{ repeatX: number, repeatY: number, offsetX: number, offsetY: number }} uv
 * @param {boolean} [mirror=false]  flip horizontally within the cell
 */
export function applyAtlasUV(texture, uv, mirror = false) {
  // offset/repeat are matrix uniforms — do NOT set texture.needsUpdate.
  // needsUpdate re-uploads image pixels; on a shared 2048×16384 atlas that
  // thrash drops activity mode to ~8–10 FPS.
  if (mirror) {
    texture.repeat.set(-uv.repeatX, uv.repeatY);
    texture.offset.set(uv.offsetX + uv.repeatX, uv.offsetY);
  } else {
    texture.repeat.set(uv.repeatX, uv.repeatY);
    texture.offset.set(uv.offsetX, uv.offsetY);
  }
}

/**
 * Bake an atlas cell into a PlaneGeometry's UV attribute (4 verts).
 * Lets many meshes share one Texture without clone()/offset races.
 * @param {{ getAttribute: Function }} geometry
 * @param {{ repeatX: number, repeatY: number, offsetX: number, offsetY: number }} uv
 * @param {boolean} [mirror=false]
 */
export function applyAtlasUVGeometry(geometry, uv, mirror = false) {
  const attr = geometry.getAttribute("uv");
  if (!attr || attr.count < 4) return;
  const rx = mirror ? -uv.repeatX : uv.repeatX;
  const ox = mirror ? uv.offsetX + uv.repeatX : uv.offsetX;
  const ry = uv.repeatY;
  const oy = uv.offsetY;
  // PlaneGeometry default UVs (no segments): (0,1) (1,1) (0,0) (1,0)
  attr.setXY(0, ox + 0 * rx, oy + 1 * ry);
  attr.setXY(1, ox + 1 * rx, oy + 1 * ry);
  attr.setXY(2, ox + 0 * rx, oy + 0 * ry);
  attr.setXY(3, ox + 1 * rx, oy + 0 * ry);
  attr.needsUpdate = true;
}
