// Minimal PNG decoder (RGBA8, non-interlaced) for asset contract tests.
// No dependencies — zlib is built into Node. Handles the five filter types.

import { inflateSync } from "node:zlib";

/**
 * @param {Buffer|Uint8Array} data PNG file bytes
 * @returns {{ width: number, height: number, rgba: Uint8Array }}
 */
export function decodePng(data) {
  const buf = Buffer.from(data);
  if (buf.length < 8 || buf.toString("ascii", 1, 4) !== "PNG") {
    throw new Error("not a PNG");
  }
  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let idat = [];
  while (offset < buf.length) {
    const length = buf.readUInt32BE(offset);
    const type = buf.toString("ascii", offset + 4, offset + 8);
    const chunk = buf.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") {
      width = chunk.readUInt32BE(0);
      height = chunk.readUInt32BE(4);
      bitDepth = chunk[8];
      colorType = chunk[9];
      const interlace = chunk[12];
      if (interlace !== 0) throw new Error("interlaced PNG unsupported");
    } else if (type === "IDAT") {
      idat.push(chunk);
    } else if (type === "IEND") {
      break;
    }
    offset += 12 + length;
  }
  if (bitDepth !== 8) throw new Error(`bit depth ${bitDepth} unsupported`);
  let channels = 0;
  if (colorType === 6) channels = 4; // RGBA
  else if (colorType === 2) channels = 3; // RGB
  else if (colorType === 0) channels = 1; // grey
  else if (colorType === 4) channels = 2; // grey+alpha
  else throw new Error(`color type ${colorType} unsupported`);

  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(width * height * 4);
  const prev = Buffer.alloc(stride);

  const paeth = (a, b, c) => {
    const p = a + b - c;
    const pa = Math.abs(p - a);
    const pb = Math.abs(p - b);
    const pc = Math.abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  };

  let rowStart = 0;
  for (let y = 0; y < height; y += 1) {
    const filter = raw[rowStart];
    const line = raw.subarray(rowStart + 1, rowStart + 1 + stride);
    const recon = Buffer.alloc(stride);
    for (let i = 0; i < stride; i += 1) {
      const x = line[i];
      const a = i >= channels ? recon[i - channels] : 0;
      const b = prev[i];
      const c = i >= channels ? prev[i - channels] : 0;
      let v = 0;
      if (filter === 0) v = x;
      else if (filter === 1) v = x + a;
      else if (filter === 2) v = x + b;
      else if (filter === 3) v = x + (a + b) >> 1;
      else if (filter === 4) v = x + paeth(a, b, c);
      else throw new Error(`bad filter ${filter}`);
      recon[i] = v & 0xff;
    }
    for (let i = 0; i < width; i += 1) {
      const s = i * channels;
      const d = (y * width + i) * 4;
      out[d] = recon[s];
      out[d + 1] = channels >= 2 ? recon[s + 1] : recon[s];
      out[d + 2] = channels >= 3 ? recon[s + 2] : recon[s];
      out[d + 3] = channels === 4 ? recon[s + 3] : channels === 2 ? recon[s + 1] : 255;
    }
    prev.set(recon);
    rowStart += 1 + stride;
  }
  return { width, height, rgba: new Uint8Array(out.buffer, out.byteOffset, out.byteLength) };
}

/** Pixel stats for contract checks. */
export function pixelStats(rgba) {
  let covered = 0;
  let sumR = 0;
  let sumG = 0;
  let sumB = 0;
  let maxLuma = 0;
  for (let i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] > 8) {
      covered += 1;
      sumR += rgba[i];
      sumG += rgba[i + 1];
      sumB += rgba[i + 2];
      maxLuma = Math.max(maxLuma, 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2]);
    }
  }
  return {
    coveredPixels: covered,
    coverage: covered / (rgba.length / 4),
    meanRgb: covered
      ? [sumR / covered, sumG / covered, sumB / covered]
      : [0, 0, 0],
    maxLuma
  };
}
