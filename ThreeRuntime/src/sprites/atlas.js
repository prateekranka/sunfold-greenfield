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
 * @param {{ repeat: { set: Function }, offset: { set: Function }, needsUpdate?: boolean }} texture
 * @param {{ repeatX: number, repeatY: number, offsetX: number, offsetY: number }} uv
 * @param {boolean} [mirror=false]  flip horizontally within the cell
 */
export function applyAtlasUV(texture, uv, mirror = false) {
  if (mirror) {
    texture.repeat.set(-uv.repeatX, uv.repeatY);
    texture.offset.set(uv.offsetX + uv.repeatX, uv.offsetY);
  } else {
    texture.repeat.set(uv.repeatX, uv.repeatY);
    texture.offset.set(uv.offsetX, uv.offsetY);
  }
  texture.needsUpdate = true;
}
