// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Environment images of the Render window (RenderController.swift EnvironmentMaps, RenderSettings.Environment
// "HDRI File"): Radiance .hdr (flat or run-length encoded RGBE) and 8-bit images (JPEG, PNG) decoded to linear RGBA
// floats, equirectangular with row 0 at the top — the layout of the procedural skies, so SceneKit's orientation holds.

export interface EnvImage { key: string; width: number; height: number; data: Float32Array }

/** Decodes a Radiance RGBE file (RLE or flat scanlines), or null when it is not one. */
export function decodeHDR(bytes: Uint8Array): { width: number; height: number; data: Float32Array } | null {
  let i = 0;
  const line = () => { let s = ""; while (i < bytes.length && bytes[i] !== 0x0a) s += String.fromCharCode(bytes[i++]); i++; return s; };
  const first = line();
  if (!first.startsWith("#?")) return null;
  for (;;) { if (i >= bytes.length) return null; const l = line(); if (l === "") break; }
  const res = line().trim().split(/\s+/);
  if (res.length !== 4) return null;
  const h = Number(res[1]), w = Number(res[3]);
  const flipY = res[0] === "+Y";
  if (!(w > 0 && h > 0)) return null;
  const rgbe = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const row = rgbe.subarray(y * w * 4, (y + 1) * w * 4);
    if (w >= 8 && w < 32768 && bytes[i] === 2 && bytes[i + 1] === 2 && ((bytes[i + 2] << 8) | bytes[i + 3]) === w) {
      i += 4;
      for (let c = 0; c < 4; c++) {
        let x = 0;
        while (x < w && i < bytes.length) {
          let n = bytes[i++];
          if (n > 128) { n -= 128; const v = bytes[i++]; for (let k = 0; k < n && x < w; k++) row[(x++) * 4 + c] = v; }
          else for (let k = 0; k < n && x < w; k++) row[(x++) * 4 + c] = bytes[i++];
        }
      }
    } else {
      row.set(bytes.subarray(i, i + w * 4)); i += w * 4;
    }
  }
  const out = new Float32Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const sy = flipY ? h - 1 - y : y;
    for (let x = 0; x < w; x++) {
      const s = (sy * w + x) * 4, d = (y * w + x) * 4;
      const e = rgbe[s + 3];
      const f = e ? Math.pow(2, e - 136) : 0;
      out[d] = (rgbe[s] + 0.5) * f * (e ? 1 : 0); out[d + 1] = (rgbe[s + 1] + 0.5) * f * (e ? 1 : 0); out[d + 2] = (rgbe[s + 2] + 0.5) * f * (e ? 1 : 0); out[d + 3] = 1;
    }
  }
  return { width: w, height: h, data: out };
}

/** 8-bit sRGB pixels → linear floats. */
export function linearFromRGBA8(px: Uint8ClampedArray | Uint8Array, w: number, h: number): Float32Array {
  const lut = new Float32Array(256);
  for (let k = 0; k < 256; k++) { const c = k / 255; lut[k] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
  const out = new Float32Array(w * h * 4);
  for (let i = 0; i < w * h; i++) { out[i * 4] = lut[px[i * 4]]; out[i * 4 + 1] = lut[px[i * 4 + 1]]; out[i * 4 + 2] = lut[px[i * 4 + 2]]; out[i * 4 + 3] = 1; }
  return out;
}

/** Box-resamples a float image to at most `maxWidth` wide (2:1 kept as given). */
export function shrink(img: { width: number; height: number; data: Float32Array }, maxWidth = 2048): { width: number; height: number; data: Float32Array } {
  let { width: w, height: h, data } = img;
  while (w > maxWidth && w % 2 === 0 && h % 2 === 0) {
    const nw = w >> 1, nh = h >> 1, nd = new Float32Array(nw * nh * 4);
    for (let y = 0; y < nh; y++) for (let x = 0; x < nw; x++) for (let c = 0; c < 4; c++) {
      const q = (xx: number, yy: number) => data[(yy * w + xx) * 4 + c];
      nd[(y * nw + x) * 4 + c] = (q(2 * x, 2 * y) + q(2 * x + 1, 2 * y) + q(2 * x, 2 * y + 1) + q(2 * x + 1, 2 * y + 1)) / 4;
    }
    w = nw; h = nh; data = nd;
  }
  return { width: w, height: h, data };
}

const cache = new Map<string, EnvImage>();

/** An environment image from file bytes (`name` picks the decoder by extension); null when it cannot be read. */
export async function environmentFromBytes(name: string, bytes: Uint8Array): Promise<EnvImage | null> {
  const key = name + "|" + bytes.length;
  const hit = cache.get(key);
  if (hit) return hit;
  let img: { width: number; height: number; data: Float32Array } | null = null;
  if (/\.hdr$/i.test(name) || (bytes[0] === 0x23 && bytes[1] === 0x3f)) img = decodeHDR(bytes);
  else {
    try {
      const bmp = await createImageBitmap(new Blob([bytes as BlobPart]));
      const c = new OffscreenCanvas(bmp.width, bmp.height);
      const g = c.getContext("2d")!;
      g.drawImage(bmp, 0, 0);
      const d = g.getImageData(0, 0, bmp.width, bmp.height).data;
      img = { width: bmp.width, height: bmp.height, data: linearFromRGBA8(d, bmp.width, bmp.height) };
    } catch { img = null; }
  }
  if (!img) return null;
  const s = shrink(img);
  const env = { key, ...s };
  if (cache.size > 4) cache.clear();
  cache.set(key, env);
  return env;
}
