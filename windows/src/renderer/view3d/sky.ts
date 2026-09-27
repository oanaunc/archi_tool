// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Procedural HDR skies and the meadow ground texture, ported line by line from ArchiApp/BeautyLighting.swift
// (BeautyNoise, BeautySky.radiance, BeautySky.horizonColor, BeautyGround.texture) so both platforms draw the
// same clouds, sun glow, stars and grass. Directions here are in the Mac's SceneKit convention (Y up, −Z north);
// `toSK` converts from model space (X east, Y north, Z up).

import type { V3 } from "./math";
import type { SkyKind } from "./look";

// MARK: noise (BeautyNoise)

export function hash(x: number, y: number, seed = 0): number {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(seed | 0, 1442695041)) >>> 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return (h & 0xffffff) / 0xffffff;
}

function wrap(i: number, p: number) { return ((i % p) + p) % p; }

export function valueNoise(x: number, y: number, period = 0, seed = 0): number {
  const fx0 = Math.floor(x), fy0 = Math.floor(y);
  let x0 = fx0 | 0, y0 = fy0 | 0;
  const fx = x - fx0, fy = y - fy0;
  let x1 = (x0 + 1) | 0, y1 = (y0 + 1) | 0;
  if (period > 0) { x0 = wrap(x0, period); y0 = wrap(y0, period); x1 = wrap(x1, period); y1 = wrap(y1, period); }
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  const a = hash(x0, y0, seed), b = hash(x1, y0, seed), c = hash(x0, y1, seed), d = hash(x1, y1, seed);
  const ab = a + (b - a) * ux, cd = c + (d - c) * ux;
  return ab + (cd - ab) * uy;
}

export function fbm(x: number, y: number, octaves: number, period = 0, seed = 0): number {
  let sum = 0, amp = 0.5, n = 0, f = 1, p = period;
  for (let o = 0; o < octaves; o++) {
    sum += amp * valueNoise(x * f, y * f, p, (seed + Math.imul(o, 17)) | 0);
    n += amp; amp *= 0.5; f *= 2; p = p > 0 ? p * 2 : 0;
  }
  return sum / Math.max(n, 1e-6);
}

// MARK: sky radiance (BeautySky)

const smooth = (a: number, b: number, x: number) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const mix = (a: V3, b: V3, t: number): V3 => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const mul = (a: V3, k: number): V3 => [a[0] * k, a[1] * k, a[2] * k];
const addv = (a: V3, b: V3): V3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];

/** Model (X east, Y north, Z up) → SceneKit (Y up, −Z north). */
export const toSK = (m: V3): V3 => [m[0], m[2], -m[1]];

/** Linear radiance of the sky in SceneKit direction `d` (unit) for the SceneKit sun direction `s` (unit). */
export function radiance(d: V3, s: V3, sky: SkyKind, px = 0, py = 0): V3 {
  const up = Math.max(d[1], 0);
  const cosA = Math.max(-1, Math.min(1, d[0] * s[0] + d[1] * s[1] + d[2] * s[2]));
  const ang = Math.acos(cosA);
  const dhl = Math.hypot(d[0], d[2]), shl = Math.hypot(s[0], s[2]);
  const sunward = dhl > 1e-4 && shl > 1e-4 ? ((d[0] * s[0] + d[2] * s[2]) / (dhl * shl)) * 0.5 + 0.5 : 0.5;
  const cpx = d[0] / (d[1] + 0.12), cpy = d[2] / (d[1] + 0.12);
  let col: V3, ground: V3, horizon: V3;
  switch (sky) {
    case "daylight": {
      const zen: V3 = [0.05, 0.17, 0.66], hor: V3 = [0.62, 0.75, 0.94];
      horizon = hor;
      col = mix(zen, hor, Math.pow(1 - up, 3.2));
      const glow = mul([1.0, 0.93, 0.8], 0.3 * Math.exp(-ang * 2.2) + 1.1 * Math.exp(-ang * 14));
      col = addv(col, glow);
      if (d[1] > 0.005) {
        const n = fbm(cpx * 1.3 + 11, cpy * 1.3 - 7, 6, 0, 3);
        const cover = smooth(0.5, 0.78, n) * smooth(0.01, 0.22, d[1]);
        const shade = 0.72 + 0.4 * fbm(cpx * 3.1 + 5, cpy * 3.1 + 2, 4, 0, 9);
        const lit = addv(mul([1.05, 1.05, 1.08], shade), mul(glow, 0.8));
        col = mix(col, lit, cover * 0.9);
      }
      if (ang < 0.012) col = addv(col, mul([1.0, 0.96, 0.9], 45));
      ground = [0.15, 0.145, 0.13];
      break;
    }
    case "golden": {
      const zen: V3 = [0.09, 0.13, 0.3];
      const warm: V3 = [1.15, 0.56, 0.24], cool: V3 = [0.42, 0.44, 0.58];
      const hor = mix(cool, warm, Math.pow(sunward, 2.5));
      horizon = hor;
      col = mix(zen, hor, Math.pow(1 - up, 2.6));
      const glow = mul([1.0, 0.52, 0.22], 0.7 * Math.exp(-ang * 2.8) + 2.6 * Math.exp(-ang * 16));
      col = addv(col, glow);
      if (d[1] > 0.005) {
        const n = fbm(cpx * 1.1 - 3, cpy * 1.1 + 13, 6, 0, 5);
        const cover = smooth(0.56, 0.8, n) * smooth(0.01, 0.25, d[1]);
        const lit = addv(mix([0.32, 0.26, 0.36], [1.35, 0.66, 0.42], Math.pow(sunward, 1.5)), mul(glow, 0.9));
        col = mix(col, lit, cover * 0.85);
      }
      if (ang < 0.014) col = addv(col, mul([1.0, 0.62, 0.32], 30));
      ground = [0.07, 0.058, 0.05];
      break;
    }
    case "overcast": {
      const base = mul([0.78, 0.81, 0.86], 1.12);
      col = mul(base, (1 + 2 * up) / 3);
      horizon = mul(base, 1.05 / 3);
      const n = fbm(cpx * 0.9, cpy * 0.9, 5, 0, 7);
      col = mul(col, 0.82 + 0.34 * n);
      col = addv(col, mul([0.26, 0.26, 0.25], Math.exp(-ang * 2.2) * smooth(-0.1, 0.2, d[1])));
      ground = [0.11, 0.11, 0.105];
      break;
    }
    default: {
      const zen: V3 = [0.0025, 0.0045, 0.013], hor: V3 = [0.018, 0.024, 0.045];
      horizon = hor;
      col = mix(zen, hor, Math.pow(1 - up, 3));
      col = addv(col, mul([0.055, 0.036, 0.02], Math.pow(1 - up, 12)));
      col = addv(col, mul([0.03, 0.04, 0.07], Math.exp(-ang * 5)));
      if (d[1] > 0.04) {
        const h = hash(px, py, 77);
        if (h > 0.9975) col = addv(col, mul([0.9, 0.93, 1.0], ((h - 0.9975) / 0.0025) * 1.4 * smooth(0.04, 0.3, d[1])));
      }
      if (ang < 0.011) col = addv(col, mul([0.9, 0.94, 1.0], 5));
      ground = [0.006, 0.006, 0.007];
    }
  }
  if (d[1] < 0) return mix(ground, mul(horizon, 0.75), Math.exp(d[1] * 18));
  return col;
}

/** Average horizon colour around the scene (linear): the colour of the distance haze. */
export function horizonColor(sky: SkyKind, s: V3): V3 {
  let acc: V3 = [0, 0, 0];
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * 2 * Math.PI;
    const d: V3 = [Math.sin(a), 0.035, -Math.cos(a)];
    const l = Math.hypot(d[0], d[1], d[2]);
    acc = addv(acc, radiance([d[0] / l, d[1] / l, d[2] / l], s, sky));
  }
  return mul(acc, 1 / 16);
}

/** Panorama.direction: equirectangular (u right, v down, 0…1) → SceneKit direction. */
export function panoramaDirection(u: number, v: number): V3 {
  const lon = (u - 0.5) * 2 * Math.PI, lat = (0.5 - v) * Math.PI;
  return [Math.cos(lat) * Math.sin(lon), Math.sin(lat), -Math.cos(lat) * Math.cos(lon)];
}

export interface SkyImage { width: number; height: number; data: Float32Array; key: string }
const skyCache = new Map<string, SkyImage>();

/** Linear RGBA float pixels (row 0 at the top) of the sky, cached per look / sun / width. */
export function skyPixels(sky: SkyKind, sunSK: V3, width: number): SkyImage {
  const key = `${sky}-${width}-${sunSK.map((v) => v.toFixed(2)).join("_")}`;
  const hit = skyCache.get(key);
  if (hit) return hit;
  const h = width / 2;
  const out = new Float32Array(width * h * 4);
  for (let y = 0; y < h; y++) {
    const v = (y + 0.5) / h;
    for (let x = 0; x < width; x++) {
      const c = radiance(panoramaDirection((x + 0.5) / width, v), sunSK, sky, x, y);
      const i = (y * width + x) * 4;
      out[i] = c[0]; out[i + 1] = c[1]; out[i + 2] = c[2]; out[i + 3] = 1;
    }
  }
  const img = { width, height: h, data: out, key };
  if (skyCache.size > 12) skyCache.clear();
  skyCache.set(key, img);
  return img;
}

/**
 * Diffuse irradiance of the sky as 9 spherical-harmonic coefficients (RGB), in MODEL space (Z up), so the shader
 * evaluates E(n) for a model-space normal. Computed from a small equirect of the sky.
 */
export function irradianceSH(img: SkyImage): Float32Array {
  const sh = new Float64Array(27);
  const w = img.width, h = img.height;
  const step = Math.max(1, Math.floor(w / 128));
  let wsum = 0;
  for (let y = 0; y < h; y += step) {
    const v = (y + 0.5) / h;
    const lat = (0.5 - v) * Math.PI;
    const dw = Math.cos(lat);
    for (let x = 0; x < w; x += step) {
      const d = panoramaDirection((x + 0.5) / w, v);
      // The texel made for Panorama direction d is seen along model direction (d.z, d.x, d.y) (SceneKit's
      // orientation of equirect environment images; see equirect() in shaders.ts).
      const mx = d[2], my = d[0], mz = d[1];
      const i = (y * w + x) * 4;
      const r = img.data[i], g = img.data[i + 1], b = img.data[i + 2];
      const basis = [0.282095, 0.488603 * my, 0.488603 * mz, 0.488603 * mx, 1.092548 * mx * my, 1.092548 * my * mz,
        0.315392 * (3 * mz * mz - 1), 1.092548 * mx * mz, 0.546274 * (mx * mx - my * my)];
      for (let k = 0; k < 9; k++) { sh[k * 3] += r * basis[k] * dw; sh[k * 3 + 1] += g * basis[k] * dw; sh[k * 3 + 2] += b * basis[k] * dw; }
      wsum += dw;
    }
  }
  const norm = (4 * Math.PI) / wsum;
  // Convolution with the clamped cosine lobe (Ramamoorthi & Hanrahan), divided by π so a white Lambert surface under
  // a uniform sky of radiance L receives L.
  const A = [Math.PI, (2 * Math.PI) / 3, (2 * Math.PI) / 3, (2 * Math.PI) / 3, Math.PI / 4, Math.PI / 4, Math.PI / 4, Math.PI / 4, Math.PI / 4];
  const out = new Float32Array(27);
  for (let k = 0; k < 9; k++) for (let c = 0; c < 3; c++) out[k * 3 + c] = (sh[k * 3 + c] * norm * A[k]) / Math.PI;
  return out;
}

// MARK: ground (BeautyGround)

let groundCache: Uint8Array | null = null;
export const GROUND_TILE_METRES = 8;

/** 512² sRGB RGBA meadow tile (seamless, 8 m). */
export function groundTexture(): { size: number; data: Uint8Array } {
  const s = 512;
  if (groundCache) return { size: s, data: groundCache };
  const px = new Uint8Array(s * s * 4);
  const period = 8;
  for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) {
    const u = (x / s) * period, v = (y / s) * period;
    const broad = fbm(u, v, 3, period, 21);
    const fine = fbm(u * 8, v * 8, 3, period * 8, 5);
    const blade = valueNoise(u * 64, v * 16, period * 16, 8);
    const dry = Math.max(0, Math.min(1, (broad - 0.55) * 3));
    let r = 0.2 + 0.1 * fine + 0.04 * blade, g = 0.33 + 0.12 * fine + 0.05 * blade, b = 0.12 + 0.05 * fine;
    r += dry * 0.14; g += dry * 0.07; b += dry * 0.03;
    const shade = 0.82 + 0.3 * broad;
    const i = (y * s + x) * 4;
    px[i] = Math.min(255, r * shade * 255); px[i + 1] = Math.min(255, g * shade * 255); px[i + 2] = Math.min(255, b * shade * 255); px[i + 3] = 255;
  }
  groundCache = px;
  return { size: s, data: px };
}

/** One 5 m grid tile (Scene3DBuilder.gridImage): 1 m minor lines and a stronger 5 m line; sRGB bytes. */
export function gridTexture(base: V3, line: V3): { size: number; data: Uint8Array } {
  const s = 500;
  const px = new Uint8Array(s * s * 4);
  for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) {
    let c = base;
    const minor = [100, 200, 300, 400].some((p) => Math.abs(x + 0.5 - p) <= 0.75 || Math.abs(y + 0.5 - p) <= 0.75);
    if (minor) c = mix(base, line, 0.45);
    if (x < 3 || y < 3) c = line;
    const i = (y * s + x) * 4;
    px[i] = c[0] * 255; px[i + 1] = c[1] * 255; px[i + 2] = c[2] * 255; px[i + 3] = 255;
  }
  return { size: s, data: px };
}
