// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Material images, ported from the Mac app: the library's pattern textures (PatternTextures: brick, tiles, planks, stone,
// ceiling grid), procedural materials with height and roughness maps (ProceduralMaterial, VIS-066: the same periodic value
// noise, 64-bit hash and parameters, so a seed gives the same pixels), materials from a photo (PhotoMaterial, VIS-067),
// Sobel normal maps (BumpMap) and the rendered-sphere thumbnails of the material library (MaterialThumbnails).

// ---- 64-bit unsigned arithmetic on [hi, lo] pairs (the Swift UInt64 &* ^ >>) ----
type U64 = [number, number];
function mul32(a: number, b: number): U64 {
  const a0 = a & 0xffff, a1 = a >>> 16, b0 = b & 0xffff, b1 = b >>> 16;
  const p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
  const mid = (p00 >>> 16) + (p01 & 0xffff) + (p10 & 0xffff);
  const lo = (((mid & 0xffff) << 16) | (p00 & 0xffff)) >>> 0;
  const hi = (p11 + (p01 >>> 16) + (p10 >>> 16) + (mid >>> 16)) >>> 0;
  return [hi, lo];
}
function mul(a: U64, b: U64): U64 { const [h, l] = mul32(a[1], b[1]); return [(h + Math.imul(a[1], b[0]) + Math.imul(a[0], b[1])) >>> 0, l]; }
function add(a: U64, b: U64): U64 { const lo = a[1] + b[1]; return [(a[0] + b[0] + (lo > 0xffffffff ? 1 : 0)) >>> 0, lo >>> 0]; }
const xor = (a: U64, b: U64): U64 => [(a[0] ^ b[0]) >>> 0, (a[1] ^ b[1]) >>> 0];
function shr(a: U64, n: number): U64 { return n >= 32 ? [0, a[0] >>> (n - 32)] : [a[0] >>> n, ((a[1] >>> n) | (a[0] << (32 - n))) >>> 0]; }
const fromInt = (x: number): U64 => [x < 0 ? 0xffffffff : Math.floor(x / 4294967296) >>> 0, x >>> 0];
const hex = (s: string): U64 => [parseInt(s.slice(0, 8), 16) >>> 0, parseInt(s.slice(8), 16) >>> 0];
const K_GOLD = hex("9E3779B97F4A7C15"), K_Y = hex("C2B2AE3D27D4EB4F"), K_S = hex("165667B19E3779F9"), M1 = hex("BF58476D1CE4E5B9"), M2 = hex("94D049BB133111EB");
function mix(z: U64): U64 { z = mul(xor(z, shr(z, 30)), M1); z = mul(xor(z, shr(z, 27)), M2); return xor(z, shr(z, 31)); }
const unit = (z: U64) => ((z[0] * 2097152) + (z[1] >>> 11)) / 9007199254740992;

/** ProceduralMaterial.hash(x, y, seed) → [0, 1). */
export function hash(x: number, y: number, seed: U64): number {
  const z = xor(xor(mul(fromInt(x), K_GOLD), mul(fromInt(y), K_Y)), mul(seed, K_S));
  return unit(mix(z));
}
/** SplitMix64 (PatternTextures.SplitMix). */
export class SplitMix {
  private s: U64;
  constructor(seed: U64) { this.s = add(seed, K_GOLD); }
  next(): number { this.s = add(this.s, K_GOLD); return unit(mix(this.s)); }
}
export function seedOf(n: number): U64 { return fromInt(Math.max(0, Math.round(n))); }
function addSeed(s: U64, k: number): U64 { return add(s, fromInt(k)); }

// ---- periodic value noise ----
export function noise(u: number, v: number, p: number, seed: U64): number {
  const x = u * p, y = v * p, x0 = Math.floor(x), y0 = Math.floor(y);
  const fx = x - x0, fy = y - y0, sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  const hh = (i: number, j: number) => hash(((i % p) + p) % p, ((j % p) + p) % p, seed);
  const a = hh(x0, y0) * (1 - sx) + hh(x0 + 1, y0) * sx;
  const b = hh(x0, y0 + 1) * (1 - sx) + hh(x0 + 1, y0 + 1) * sx;
  return a * (1 - sy) + b * sy;
}
export function fbm(u: number, v: number, base: number, octaves: number, seed: U64): number {
  let s = 0, a = 0.5, p = base, norm = 0;
  for (let o = 0; o < octaves; o++) { s += a * noise(u, v, p, addSeed(seed, o)); norm += a; a *= 0.5; p *= 2; }
  return s / norm;
}

export interface RGB { r: number; g: number; b: number }
export type ProcKind = "Wood" | "Brick" | "Tile" | "Marble" | "Stone" | "Concrete" | "Terrazzo";
export const PROC_KINDS: ProcKind[] = ["Wood", "Brick", "Tile", "Marble", "Stone", "Concrete", "Terrazzo"];
export interface ProcParams { kind: ProcKind; color1: RGB; color2: RGB; tileSize: number; rows: number; columns: number; joint: number; variation: number; seed: number; pixels: number }

/** ProceduralMaterial.Params(kind:) defaults. */
export function procDefaults(kind: ProcKind): ProcParams {
  const p: ProcParams = { kind, color1: { r: 0.62, g: 0.30, b: 0.22 }, color2: { r: 0.80, g: 0.78, b: 0.74 }, tileSize: 1000, rows: 8, columns: 4, joint: 0.012, variation: 0.12, seed: 1, pixels: 512 };
  switch (kind) {
    case "Wood": Object.assign(p, { color1: { r: 0.62, g: 0.43, b: 0.26 }, color2: { r: 0.45, g: 0.29, b: 0.16 }, rows: 6, columns: 1, joint: 0.003, variation: 0.1 }); break;
    case "Tile": Object.assign(p, { color1: { r: 0.90, g: 0.90, b: 0.88 }, color2: { r: 0.62, g: 0.62, b: 0.60 }, rows: 4, columns: 4, joint: 0.008, variation: 0.04, tileSize: 1200 }); break;
    case "Marble": Object.assign(p, { color1: { r: 0.93, g: 0.92, b: 0.90 }, color2: { r: 0.45, g: 0.45, b: 0.48 }, rows: 1, columns: 1, joint: 0, variation: 0.05 }); break;
    case "Stone": Object.assign(p, { color1: { r: 0.62, g: 0.59, b: 0.53 }, color2: { r: 0.40, g: 0.38, b: 0.35 }, rows: 5, columns: 5, joint: 0.015, variation: 0.15 }); break;
    case "Concrete": Object.assign(p, { color1: { r: 0.70, g: 0.70, b: 0.68 }, color2: { r: 0.55, g: 0.55, b: 0.53 }, rows: 1, columns: 1, joint: 0, variation: 0.06 }); break;
    case "Terrazzo": Object.assign(p, { color1: { r: 0.88, g: 0.87, b: 0.84 }, color2: { r: 0.35, g: 0.33, b: 0.32 }, rows: 1, columns: 1, joint: 0, variation: 0.25 }); break;
  }
  return p;
}

export interface Maps { albedo: Uint8ClampedArray; height: Float64Array; roughness: Float64Array; size: number }

/** ProceduralMaterial.generate. */
export function generate(p: ProcParams): Maps {
  const n = Math.max(16, Math.min(p.pixels, 2048));
  const albedo = new Uint8ClampedArray(n * n * 4).fill(255);
  const height = new Float64Array(n * n), rough = new Float64Array(n * n).fill(0.8);
  const rows = Math.max(1, p.rows), cols = Math.max(1, p.columns), j = Math.max(0, p.joint);
  const seed = seedOf(p.seed);
  const mixc = (a: RGB, b: RGB, t: number): [number, number, number] => [a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t];
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const u = (x + 0.5) / n, v = (y + 0.5) / n;
    let c: [number, number, number] = [p.color1.r, p.color1.g, p.color1.b];
    let hgt = 0.5, r = 0.8;
    const grain = fbm(u, v, 8, 4, seed);
    switch (p.kind) {
      case "Brick": case "Tile": {
        const row = Math.floor(v * rows) % rows;
        const off = p.kind === "Brick" && row % 2 === 1 ? 0.5 : 0;
        const cu = u * cols + off, cv = v * rows;
        const col = Math.floor(cu) % cols;
        const fu = cu - Math.floor(cu), fv = cv - Math.floor(cv);
        const d = Math.min(Math.min(fu, 1 - fu) / cols, Math.min(fv, 1 - fv) / rows);
        const tone = (hash(col, row, seed) - 0.5) * p.variation * 2;
        if (d < j / 2) { c = [p.color2.r, p.color2.g, p.color2.b]; hgt = 0.1; r = 0.95; const k = (grain - 0.5) * 0.08; c = [c[0] + k, c[1] + k, c[2] + k]; }
        else {
          const k = tone + (grain - 0.5) * p.variation;
          c = [p.color1.r + k, p.color1.g + k, p.color1.b + k * 0.9];
          const bevel = Math.min(1, (d - j / 2) / Math.max(j, 0.002));
          hgt = 0.35 + 0.55 * bevel + (grain - 0.5) * 0.1;
          r = p.kind === "Tile" ? 0.22 + grain * 0.1 : 0.82 + grain * 0.1;
        }
        break;
      }
      case "Wood": {
        const board = Math.floor(v * rows) % rows;
        const bshift = hash(board, 7, seed);
        const fv = v * rows - Math.floor(v * rows);
        const warp = fbm(u, v, 4, 4, addSeed(seed, 11)) * 3;
        const ring = (fv * 3 + warp + bshift * 5) % 1;
        const t = Math.pow(Math.abs(Math.sin(ring * Math.PI)), 3) * 0.7 + (grain - 0.5) * 0.3;
        c = mixc(p.color1, p.color2, Math.max(0, Math.min(1, t + (bshift - 0.5) * p.variation * 2)));
        const seam = Math.min(fv, 1 - fv) / rows < j / 2;
        if (seam) { c = [c[0] * 0.5, c[1] * 0.5, c[2] * 0.5]; hgt = 0.2; } else hgt = 0.6 - t * 0.2;
        r = 0.5 + t * 0.2;
        break;
      }
      case "Marble": {
        const w = fbm(u, v, 4, 5, seed) * 4;
        const vein = Math.pow(1 - Math.abs(Math.sin((u * 2 + v + w) * Math.PI)), 12);
        c = mixc(p.color1, p.color2, Math.min(1, vein * 0.9 + (grain - 0.5) * p.variation));
        hgt = 0.5; r = 0.12 + vein * 0.1;
        break;
      }
      case "Stone": {
        const gx = cols, gy = rows;
        let f1 = 9, f2 = 9, cell = [0, 0];
        const cx = Math.floor(u * gx), cy = Math.floor(v * gy);
        for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) {
          const ix = cx + ox, iy = cy + oy, wx = ((ix % cols) + cols) % cols, wy = ((iy % rows) + rows) % rows;
          const px = (ix + 0.15 + 0.7 * hash(wx, wy, seed)) / gx, py = (iy + 0.15 + 0.7 * hash(wx, wy, addSeed(seed, 3))) / gy;
          const dd = Math.hypot(u - px, v - py);
          if (dd < f1) { f2 = f1; f1 = dd; cell = [wx, wy]; } else if (dd < f2) f2 = dd;
        }
        const edge = (f2 - f1) / 2;
        const tone = (hash(cell[0], cell[1], addSeed(seed, 5)) - 0.5) * p.variation * 2;
        if (edge < j) { c = [p.color2.r, p.color2.g, p.color2.b]; hgt = 0.1; r = 0.95; }
        else { const k = tone + (grain - 0.5) * p.variation; c = [p.color1.r + k, p.color1.g + k, p.color1.b + k]; hgt = 0.4 + Math.min(1, (edge - j) / 0.02) * 0.4 + (grain - 0.5) * 0.15; r = 0.85; }
        break;
      }
      case "Concrete": {
        const k = (grain - 0.5) * p.variation * 2 + (fbm(u, v, 64, 2, addSeed(seed, 9)) - 0.5) * 0.08;
        c = [p.color1.r + k, p.color1.g + k, p.color1.b + k];
        const pore = noise(u, v, 128, addSeed(seed, 21)) > 0.93;
        hgt = pore ? 0.2 : 0.5 + (grain - 0.5) * 0.2; r = 0.88;
        if (pore) c = [c[0] * 0.7, c[1] * 0.7, c[2] * 0.7];
        break;
      }
      case "Terrazzo": {
        const chip = noise(u, v, 48, addSeed(seed, 31));
        const k = (grain - 0.5) * 0.05;
        if (chip > 0.72) c = mixc(p.color2, { r: 0.72, g: 0.52, b: 0.40 }, hash(Math.floor(u * 48), Math.floor(v * 48), seed));
        else c = [p.color1.r + k, p.color1.g + k, p.color1.b + k];
        hgt = 0.5; r = 0.2;
        break;
      }
    }
    const i = y * n + x;
    albedo[i * 4] = Math.round(c[0] * 255); albedo[i * 4 + 1] = Math.round(c[1] * 255); albedo[i * 4 + 2] = Math.round(c[2] * 255);
    height[i] = Math.max(0, Math.min(1, hgt)); rough[i] = Math.max(0.02, Math.min(1, r));
  }
  return { albedo, height, roughness: rough, size: n };
}

/** BumpMap.normals: tangent-space normal map from a height map (Sobel, wrapping). */
export function normals(hmap: Float64Array | number[], w: number, h: number, strength: number): Uint8ClampedArray {
  const out = new Uint8ClampedArray(w * h * 4).fill(255);
  const hv = (x: number, y: number) => hmap[(((y % h) + h) % h) * w + (((x % w) + w) % w)];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const dx = (hv(x + 1, y - 1) + 2 * hv(x + 1, y) + hv(x + 1, y + 1)) - (hv(x - 1, y - 1) + 2 * hv(x - 1, y) + hv(x - 1, y + 1));
    const dy = (hv(x - 1, y + 1) + 2 * hv(x, y + 1) + hv(x + 1, y + 1)) - (hv(x - 1, y - 1) + 2 * hv(x, y - 1) + hv(x + 1, y - 1));
    let nx = -dx * strength, ny = dy * strength, nz = 1;
    const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l;
    const i = (y * w + x) * 4;
    out[i] = Math.round((nx * 0.5 + 0.5) * 255); out[i + 1] = Math.round((ny * 0.5 + 0.5) * 255); out[i + 2] = Math.round((nz * 0.5 + 0.5) * 255);
  }
  return out;
}
export function gray(v: ArrayLike<number>): Uint8ClampedArray {
  const out = new Uint8ClampedArray(v.length * 4).fill(255);
  for (let i = 0; i < v.length; i++) { const b = Math.round(Math.max(0, Math.min(1, v[i])) * 255); out[i * 4] = b; out[i * 4 + 1] = b; out[i * 4 + 2] = b; }
  return out;
}
/** RGBA pixels → PNG as base64 (no data: prefix). */
export function pngBase64(rgba: Uint8ClampedArray, w: number, h: number): string {
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  const g = c.getContext("2d")!;
  const img = g.createImageData(w, h);
  img.data.set(rgba);
  for (let i = 3; i < img.data.length; i += 4) img.data[i] = 255;
  g.putImageData(img, 0, 0);
  const url = c.toDataURL("image/png");
  return url.slice(url.indexOf(",") + 1);
}

/** Box blur with wrap-around (MapImages.blur). */
function blur(v: Float64Array, w: number, h: number, r: number): Float64Array {
  if (r <= 0) return v;
  const tmp = new Float64Array(v.length), out = new Float64Array(v.length), k = 2 * r + 1;
  for (let y = 0; y < h; y++) {
    let s = 0;
    for (let x = -r; x <= r; x++) s += v[y * w + (((x % w) + w) % w)];
    for (let x = 0; x < w; x++) { tmp[y * w + x] = s / k; s += v[y * w + ((x + r + 1) % w)] - v[y * w + ((((x - r) % w) + w) % w)]; }
  }
  for (let x = 0; x < w; x++) {
    let s = 0;
    for (let y = -r; y <= r; y++) s += tmp[(((y % h) + h) % h) * w + x];
    for (let y = 0; y < h; y++) { out[y * w + x] = s / k; s += tmp[((y + r + 1) % h) * w + x] - tmp[((((y - r) % h) + h) % h) * w + x]; }
  }
  return out;
}

export interface PhotoResult { albedo: Uint8ClampedArray; normal: Uint8ClampedArray; roughness: Float64Array; ao: Float64Array; width: number; height: number; meanColor: RGB; meanRoughness: number }

/** PhotoMaterial.derive: de-lighting, seamless blend, height / normal / roughness / AO from the de-lit luminance. */
export function derivePhoto(px0: Uint8ClampedArray, w: number, h: number, delight = 1, seamless = true): PhotoResult {
  const n = w * h;
  const px = new Uint8ClampedArray(px0);
  if (seamless && w > 8 && h > 8) {
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const fx = Math.abs(x / (w - 1) - 0.5) * 2, fy = Math.abs(y / (h - 1) - 0.5) * 2;
      const t = Math.max(0, Math.min(1, (Math.max(fx, fy) - 0.6) / 0.4)), s = t * t * (3 - 2 * t);
      const jj = ((y + (h >> 1)) % h) * w + (x + (w >> 1)) % w, i = y * w + x;
      for (let c = 0; c < 3; c++) px[i * 4 + c] = Math.round(px0[i * 4 + c] * (1 - s) + px0[jj * 4 + c] * s);
    }
  }
  const lum = new Float64Array(n);
  for (let i = 0; i < n; i++) lum[i] = (0.2126 * px[i * 4] + 0.7152 * px[i * 4 + 1] + 0.0722 * px[i * 4 + 2]) / 255;
  let meanL = 0; for (const l of lum) meanL += l; meanL = Math.max(meanL / Math.max(n, 1), 1e-4);
  const low = blur(lum, w, h, Math.max(1, Math.floor(Math.min(w, h) / 8)));
  const albedo = new Uint8ClampedArray(px), delit = new Float64Array(n);
  let s0 = 0, s1 = 0, s2 = 0;
  for (let i = 0; i < n; i++) {
    const k = Math.pow(meanL / Math.max(low[i], 0.02), Math.max(0, Math.min(delight, 1)));
    for (let c = 0; c < 3; c++) albedo[i * 4 + c] = Math.round(px[i * 4 + c] * k);
    albedo[i * 4 + 3] = 255;
    delit[i] = Math.min(1, lum[i] * k);
    s0 += albedo[i * 4]; s1 += albedo[i * 4 + 1]; s2 += albedo[i * 4 + 2];
  }
  let lo = Infinity, hi = -Infinity;
  for (const v of delit) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
  const height = delit.map((v) => (hi - lo > 1e-6 ? (v - lo) / (hi - lo) : 0.5));
  const normal = normals(height, w, h, 2);
  const hb = blur(height, w, h, Math.max(1, Math.floor(Math.min(w, h) / 64)));
  const ao = new Float64Array(n), rough = new Float64Array(n);
  let rs = 0;
  for (let i = 0; i < n; i++) { ao[i] = Math.max(0.2, Math.min(1, 1 - (hb[i] - height[i]) * 3)); rough[i] = Math.max(0.05, Math.min(1, 0.95 - 0.45 * height[i])); rs += rough[i]; }
  const d = Math.max(n, 1) * 255;
  return { albedo, normal, roughness: rough, ao, width: w, height: h, meanColor: { r: s0 / d, g: s1 / d, b: s2 / d }, meanRoughness: rs / Math.max(n, 1) };
}

// ---- library pattern textures (PatternTextures.image) ----
export type Pattern = "none" | "brick" | "tiles" | "planks" | "stone" | "grid";

export function patternCanvas(p: Pattern, c: RGB, hexName: string, s = 512): HTMLCanvasElement | null {
  if (p === "none") return null;
  const cv = document.createElement("canvas");
  cv.width = s; cv.height = s;
  const g = cv.getContext("2d")!;
  // Canvas y goes down, AppKit y goes up: flip so the patterns line up with the Mac images.
  g.translate(0, s); g.scale(1, -1);
  const css = (r: number, gg: number, b: number, a = 1) => `rgba(${Math.round(Math.max(0, Math.min(1, r)) * 255)},${Math.round(Math.max(0, Math.min(1, gg)) * 255)},${Math.round(Math.max(0, Math.min(1, b)) * 255)},${a})`;
  let h0: U64 = hex("CBF29CE484222325");
  for (const ch of hexName) h0 = mul(xor(h0, fromInt(ch.codePointAt(0)!)), hex("00000100000001B3"));
  const rng = new SplitMix(h0);
  const vary = (k: number) => { const d = (rng.next() - 0.5) * k; return css(c.r + d, c.g + d, c.b + d * 0.9); };
  const joint = css(c.r * 0.55 + 0.35, c.g * 0.55 + 0.33, c.b * 0.55 + 0.3);
  g.fillStyle = css(c.r, c.g, c.b); g.fillRect(0, 0, s, s);
  if (p === "brick") {
    g.fillStyle = joint; g.fillRect(0, 0, s, s);
    const rows = 8, cols = 4, hh = s / rows, w = s / cols, j = s / 128;
    for (let r = 0; r < rows; r++) for (let k = -1; k < cols; k++) {
      const x = k * w + (r % 2 === 0 ? 0 : w / 2);
      g.fillStyle = vary(0.12); g.fillRect(x + j / 2, r * hh + j / 2, w - j, hh - j);
    }
  } else if (p === "tiles" || p === "grid") {
    g.fillStyle = joint; g.fillRect(0, 0, s, s);
    const n = p === "grid" ? 2 : 4, w = s / n, j = p === "grid" ? s / 90 : s / 160;
    for (let r = 0; r < n; r++) for (let k = 0; k < n; k++) { g.fillStyle = vary(p === "grid" ? 0.02 : 0.06); g.fillRect(k * w + j / 2, r * w + j / 2, w - j, w - j); }
  } else if (p === "planks") {
    const n = 6, hh = s / n;
    for (let r = 0; r < n; r++) {
      g.fillStyle = vary(0.1); g.fillRect(0, r * hh, s, hh);
      for (let i = 0; i < 10; i++) {
        const y = r * hh + rng.next() * hh;
        g.strokeStyle = `rgba(0,0,0,${0.06 + rng.next() * 0.06})`;
        g.beginPath(); g.moveTo(0, y);
        g.bezierCurveTo(s * 0.33, y + (rng.next() - 0.5) * hh * 0.4, s * 0.66, y + (rng.next() - 0.5) * hh * 0.4, s, y);
        g.lineWidth = 1 + rng.next() * 1.5; g.stroke();
      }
      g.fillStyle = joint.replace(/,1\)$/, ",0.6)"); g.fillRect(0, r * hh, s, Math.max(1, s / 256));
    }
  } else if (p === "stone") {
    for (let i = 0; i < 900; i++) {
      const r = 2 + rng.next() * 7;
      g.fillStyle = vary(0.22).replace(/,1\)$/, ",0.55)");
      const x = rng.next() * s, y = rng.next() * s;
      for (const dx of [-s, 0, s]) for (const dy of [-s, 0, s]) { g.beginPath(); g.ellipse(x + dx, y + dy, r, r, 0, 0, Math.PI * 2); g.fill(); }
    }
  }
  return cv;
}

/** A rendered-looking PBR sphere (MaterialThumbnails): environment gradient, key light, roughness / metalness, texture. */
export function sphereThumbnail(m: { color?: RGB; roughness?: number; metalness?: number; transparency?: number }, tex: CanvasImageSource | null, size = 88): HTMLCanvasElement {
  const dpr = 2, n = size * dpr;
  const cv = document.createElement("canvas");
  cv.width = n; cv.height = n;
  const g = cv.getContext("2d")!;
  let texData: ImageData | null = null, tw = 0, th = 0;
  if (tex) {
    const t = document.createElement("canvas");
    tw = 256; th = 256; t.width = tw; t.height = th;
    const tg = t.getContext("2d")!;
    try { tg.drawImage(tex as any, 0, 0, tw, th); texData = tg.getImageData(0, 0, tw, th); } catch { texData = null; }
  }
  const img = g.createImageData(n, n);
  const base = m.color ?? { r: 0.8, g: 0.8, b: 0.8 };
  const rough = Math.min(Math.max(m.roughness ?? 0.8, 0.03), 1), metal = Math.min(Math.max(m.metalness ?? 0, 0), 1);
  const alpha = 1 - Math.min(m.transparency ?? 0, 0.9);
  const L = [-0.45, 0.55, 0.7]; const Ll = Math.hypot(L[0], L[1], L[2]); for (let k = 0; k < 3; k++) L[k] /= Ll;
  const shin = 2 / (rough * rough * rough + 0.01);
  const toLin = (c: number) => Math.pow(c, 2.2), toSRGB = (c: number) => Math.pow(Math.max(0, Math.min(1, c)), 1 / 2.2);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const i = (y * n + x) * 4;
    const nx = (x + 0.5) / n * 2 - 1, ny = 1 - (y + 0.5) / n * 2;
    const r2 = nx * nx + ny * ny;
    if (r2 > 1) { img.data[i] = 41; img.data[i + 1] = 41; img.data[i + 2] = 41; img.data[i + 3] = 255; continue; }
    const nz = Math.sqrt(1 - r2);
    let cr = base.r, cg = base.g, cb = base.b;
    if (texData) {
      const u = 0.5 + Math.atan2(nx, nz) / Math.PI, v = 0.5 - Math.asin(ny) / Math.PI;
      const tx = Math.floor(((u * 2) % 1) * tw), ty = Math.floor(v * th) % th;
      const k = (ty * tw + tx) * 4;
      cr = texData.data[k] / 255; cg = texData.data[k + 1] / 255; cb = texData.data[k + 2] / 255;
    }
    const lr = toLin(cr), lg = toLin(cg), lb = toLin(cb);
    const diff = Math.max(0, nx * L[0] + ny * L[1] + nz * L[2]);
    const env = 0.25 + 0.55 * (ny * 0.5 + 0.5);                    // sky above, dark ground below
    const hx = L[0], hy = L[1], hz = L[2] + 1, hl = Math.hypot(hx, hy, hz);
    const spec = Math.pow(Math.max(0, (nx * hx + ny * hy + nz * hz) / hl), shin) * (1 - rough * 0.85);
    const fres = Math.pow(1 - nz, 4) * (1 - rough) * 0.5;
    const kd = (1 - metal) * (0.9 * diff + env * 0.6);
    const specTint = [lr * metal + (1 - metal), lg * metal + (1 - metal), lb * metal + (1 - metal)];
    const envSpec = metal * env * 0.9;
    let or = lr * kd + (spec * 1.4 + fres) * specTint[0] + lr * envSpec;
    let og = lg * kd + (spec * 1.4 + fres) * specTint[1] + lg * envSpec;
    let ob = lb * kd + (spec * 1.4 + fres) * specTint[2] + lb * envSpec;
    const bg = toLin(41 / 255);
    or = or * alpha + bg * (1 - alpha); og = og * alpha + bg * (1 - alpha); ob = ob * alpha + bg * (1 - alpha);
    img.data[i] = Math.round(toSRGB(or) * 255); img.data[i + 1] = Math.round(toSRGB(og) * 255); img.data[i + 2] = Math.round(toSRGB(ob) * 255); img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  cv.style.width = size + "px"; cv.style.height = size + "px";
  return cv;
}
