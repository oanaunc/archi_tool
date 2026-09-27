// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The model of the 3D view: decodes the engine's model.meshes result (base64 or binary Float32 / Uint32 buffers,
// model millimetres, Z up) into GPU buffers, keeps CPU copies for picking and walk collisions, and resolves the
// material looks of Scene3DBuilder.material / BeautyLighting.enhance.

import { GL, imageTexture } from "./gl";
import { V3, hex } from "./math";

// MARK: protocol types (model.meshes)

export type Buffer64 = string | { offset: number; length: number };

export interface EngineMesh {
  id: number | string | null;
  kind: string;
  material: string;
  color: string;
  opacity: number;
  roughness?: number;
  metalness?: number;
  emissive?: number;
  vertexCount?: number;
  triangleCount?: number;
  positions: Buffer64;
  normals?: Buffer64;
  indices: Buffer64;
  uvs?: Buffer64;
  texture?: string;
  textureScale?: number;
  edges?: Buffer64;
}

export interface EngineLight {
  id: number | string;
  kind: string;             // point | spot | ies | area | line
  position: V3;
  target?: V3;
  lumens: number;
  cct: number;
  beam: number;
  size?: [number, number];
  fixture?: boolean;
}

export interface MeshesResult {
  meshes: EngineMesh[];
  lights?: EngineLight[];
  sun?: { azimuth: number; altitude: number; direction?: V3; preset?: string };
  units?: string;
  bounds?: [V3, V3] | null;
  binary?: string;
}

/** PBR maps of a material (MATMAPS:<NAME> on the Mac: JSON with normal, roughness, metallic, ao, normalStrength). */
export interface MaterialMaps { normal?: string; roughness?: string; metallic?: string; ao?: string; normalStrength?: number }

/** A saved 3D camera (ArchiCore Camera / named view), model units. */
export interface SavedCamera { name: string; eye: V3; target: V3; fov?: number; orthographic?: boolean }

// MARK: decoding

function bytesOf(b: Buffer64 | undefined, bin?: ArrayBuffer): Uint8Array | null {
  if (b == null) return null;
  if (typeof b === "string") {
    if (typeof atob === "function") {
      const s = atob(b);
      const out = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
      return out;
    }
    return new Uint8Array((globalThis as any).Buffer.from(b, "base64"));
  }
  if (!bin) return null;
  return new Uint8Array(bin, b.offset, b.length);
}
export function floats(b: Buffer64 | undefined, bin?: ArrayBuffer): Float32Array | null {
  const u = bytesOf(b, bin);
  if (!u) return null;
  const copy = new Uint8Array(u.length); copy.set(u);
  return new Float32Array(copy.buffer, 0, u.length >> 2);
}
export function uints(b: Buffer64 | undefined, bin?: ArrayBuffer): Uint32Array | null {
  const u = bytesOf(b, bin);
  if (!u) return null;
  const copy = new Uint8Array(u.length); copy.set(u);
  return new Uint32Array(copy.buffer, 0, u.length >> 2);
}

// MARK: materials

/** Materials treated as tree foliage (BeautyLighting.isFoliage). */
export function isFoliage(name: string): boolean {
  const n = name.toLowerCase();
  return (n.includes("lea") || n.includes("foliage") || n.includes("crown") || n.includes("canopy tree")) && !n.includes("hedge") && !n.includes("lead");
}

export interface Material {
  name: string;
  color: V3;           // sRGB
  opacity: number;
  roughness: number;
  metalness: number;
  emissive: number;    // MATEMIT strength
  texture?: string;
  textureScale: number;
  maps?: MaterialMaps;
}

// MARK: GPU mesh

export interface MeshGPU {
  index: number;
  id: string | null;
  kind: string;
  mat: Material;
  vao: WebGLVertexArrayObject;
  count: number;
  hasUV: boolean;
  /** CPU copies (model mm) for picking / collisions. */
  positions: Float32Array;
  indices: Uint32Array;
  min: V3; max: V3;
  /** Range of this mesh in the shared edge buffer (vertices). */
  edgeStart: number; edgeCount: number;
  rawEdges: Float32Array | null;
  transparent: boolean;
  foliage: boolean;
  buffers: WebGLBuffer[];
}

export interface Textures {
  albedo?: WebGLTexture; normal?: WebGLTexture; rough?: WebGLTexture;
  /** Normal map derived from the albedo (BumpTextures.normalMap) for textures without maps. */
  derived?: WebGLTexture;
}

export type AssetResolver = (path: string) => string;
export type ImageLoader = (url: string) => Promise<TexImageSource>;

export async function defaultImageLoader(url: string): Promise<TexImageSource> {
  const img = new Image();
  img.crossOrigin = "anonymous";
  img.decoding = "async";
  img.src = url;
  await img.decode();
  return img;
}

/** Luminance → normal map (Sobel), as BumpTextures.normalMap(strength:). */
export function normalFromImage(img: TexImageSource, strength: number): HTMLCanvasElement | OffscreenCanvas | null {
  const w0 = (img as any).width as number, h0 = (img as any).height as number;
  if (!w0 || !h0) return null;
  const k = Math.min(1, 1024 / Math.max(w0, h0));
  const w = Math.max(1, Math.round(w0 * k)), h = Math.max(1, Math.round(h0 * k));
  const cv: any = typeof OffscreenCanvas !== "undefined" ? new OffscreenCanvas(w, h) : Object.assign(document.createElement("canvas"), { width: w, height: h });
  const ctx = cv.getContext("2d") as CanvasRenderingContext2D;
  ctx.drawImage(img as any, 0, 0, w, h);
  const src = ctx.getImageData(0, 0, w, h);
  const lum = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) lum[i] = (src.data[i * 4] * 0.3 + src.data[i * 4 + 1] * 0.59 + src.data[i * 4 + 2] * 0.11) / 255;
  const out = ctx.createImageData(w, h);
  const L = (x: number, y: number) => lum[((y + h) % h) * w + ((x + w) % w)];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const dx = (L(x + 1, y - 1) + 2 * L(x + 1, y) + L(x + 1, y + 1)) - (L(x - 1, y - 1) + 2 * L(x - 1, y) + L(x - 1, y + 1));
    const dy = (L(x - 1, y + 1) + 2 * L(x, y + 1) + L(x + 1, y + 1)) - (L(x - 1, y - 1) + 2 * L(x, y - 1) + L(x + 1, y - 1));
    let nx = -dx * strength * 2, ny = dy * strength * 2, nz = 1;
    const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l;
    const i = (y * w + x) * 4;
    out.data[i] = (nx * 0.5 + 0.5) * 255; out.data[i + 1] = (ny * 0.5 + 0.5) * 255; out.data[i + 2] = (nz * 0.5 + 0.5) * 255; out.data[i + 3] = 255;
  }
  ctx.putImageData(out, 0, 0);
  return cv;
}

/** Deterministic noise of SketchyStyle.noise (FNV-1a over the rounded coordinates, then a SplitMix finaliser). */
function sketchNoise(p: V3, salt: number): number {
  const M = (1n << 64n) - 1n;
  let h = (1469598103934665603n + BigInt.asUintN(64, BigInt(salt))) & M;
  for (const v of p) {
    h = ((h ^ BigInt.asUintN(64, BigInt(Math.round(v * 10)))) * 1099511628211n) & M;
  }
  h ^= h >> 29n; h = (h * 0xbf58476d1ce4e5b9n) & M; h ^= h >> 32n;
  return Number(h % 20001n) / 10000 - 1;
}

/** Hand-drawn strokes of one edge (SketchyStyle.strokes), model millimetres. */
export function sketchStrokes(a: V3, b: V3): V3[][] {
  const d: V3 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  const len = Math.hypot(d[0], d[1], d[2]);
  if (len < 1e-6) return [];
  const u: V3 = [d[0] / len, d[1] / len, d[2] / len];
  const crossv = (x: V3, y: V3): V3 => [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]];
  const nrm = (x: V3): V3 => { const l = Math.hypot(x[0], x[1], x[2]) || 1; return [x[0] / l, x[1] / l, x[2] / l]; };
  let side = crossv(u, [0, 0, 1]);
  if (Math.hypot(side[0], side[1], side[2]) < 0.1) side = crossv(u, [1, 0, 0]);
  side = nrm(side);
  const up = nrm(crossv(u, side));
  const amp = Math.min(25, Math.max(2, len * 0.008));
  const out: V3[][] = [];
  for (let pass = 0; pass < 2; pass++) {
    const over = Math.min(60, len * 0.04) * (0.6 + 0.4 * Math.abs(sketchNoise(a, pass * 7 + 1)));
    const k0 = over * (pass === 0 ? 1 : 0.5), k1 = over * (pass === 0 ? 0.5 : 1);
    const s0: V3 = [a[0] - u[0] * k0, a[1] - u[1] * k0, a[2] - u[2] * k0];
    const s1: V3 = [b[0] + u[0] * k1, b[1] + u[1] * k1, b[2] + u[2] * k1];
    const ns = amp * sketchNoise(b, pass * 13 + 3), nu = amp * 0.5 * sketchNoise([a[0] + b[0], a[1] + b[1], a[2] + b[2]], pass * 17 + 5);
    const bow: V3 = [side[0] * ns + up[0] * nu, side[1] * ns + up[1] * nu, side[2] * ns + up[2] * nu];
    const n = Math.max(3, Math.min(12, Math.floor(len / 400)));
    const pts: V3[] = [];
    for (let i = 0; i <= n; i++) {
      const t = i / n;
      const base: V3 = [s0[0] + (s1[0] - s0[0]) * t, s0[1] + (s1[1] - s0[1]) * t, s0[2] + (s1[2] - s0[2]) * t];
      const w = 4 * t * (1 - t), j = amp * 0.15 * sketchNoise(base, pass);
      pts.push([base[0] + bow[0] * w + side[0] * j, base[1] + bow[1] * w + side[1] * j, base[2] + bow[2] * w + side[2] * j]);
    }
    out.push(pts);
  }
  return out;
}

export class SceneModel {
  meshes: MeshGPU[] = [];
  lights: EngineLight[] = [];
  /** Model-space bounds (mm). */
  min: V3 = [0, 0, 0]; max: V3 = [0, 0, 0]; empty = true;
  edgeVAO: WebGLVertexArrayObject | null = null;
  edgeCount = 0;
  sketchVAO: WebGLVertexArrayObject | null = null;
  sketchRanges: { start: number; count: number }[] = [];
  private edgeBuffers: WebGLBuffer[] = [];
  private texCache = new Map<string, Promise<WebGLTexture | null>>();
  readonly textures = new Map<string, Textures>();
  onTextureLoaded: (() => void) | null = null;
  /** Look for `<name>_n` / `<name>_r` maps beside a texture when the document gives no MATMAPS. */
  guessMaps = true;

  constructor(readonly gl: GL, readonly resolve: AssetResolver = (p) => p, readonly loadImage: ImageLoader = defaultImageLoader,
    public materialMaps: Record<string, MaterialMaps> = {}) {}

  /** Replaces the model with a model.meshes result (`binary`: the buffer file when the engine wrote one). */
  set(result: MeshesResult, binary?: ArrayBuffer) {
    this.dispose();
    const gl = this.gl;
    const lo: V3 = [Infinity, Infinity, Infinity], hi: V3 = [-Infinity, -Infinity, -Infinity];
    const edgeParts: Float32Array[] = [];
    let edgeTotal = 0;
    result.meshes.forEach((m, index) => {
      const pos = floats(m.positions, binary);
      const idx = uints(m.indices, binary);
      if (!pos || !idx || pos.length < 9 || idx.length < 3) {
        // Line-only groups still contribute edges.
        const e = floats(m.edges, binary);
        if (e && e.length) { for (let i = 0; i < e.length; i += 3) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], e[i + k]); hi[k] = Math.max(hi[k], e[i + k]); } }
        return;
      }
      let nor = floats(m.normals, binary);
      if (!nor || nor.length !== pos.length) nor = computeNormals(pos, idx);
      let uv = floats(m.uvs, binary);
      if ((!uv || uv.length / 2 !== pos.length / 3) && m.texture) uv = generateUVs(pos, nor, isFoliage(m.material));
      const hasUV = !!uv && uv.length / 2 === pos.length / 3;
      const mn: V3 = [Infinity, Infinity, Infinity], mx: V3 = [-Infinity, -Infinity, -Infinity];
      for (let i = 0; i < pos.length; i += 3) for (let k = 0; k < 3; k++) { const v = pos[i + k]; if (v < mn[k]) mn[k] = v; if (v > mx[k]) mx[k] = v; }
      for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], mn[k]); hi[k] = Math.max(hi[k], mx[k]); }
      const vao = gl.createVertexArray()!;
      gl.bindVertexArray(vao);
      const buffers: WebGLBuffer[] = [];
      const attr = (loc: number, data: Float32Array, size: number) => {
        const b = gl.createBuffer()!; buffers.push(b);
        gl.bindBuffer(gl.ARRAY_BUFFER, b);
        gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
        gl.enableVertexAttribArray(loc);
        gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 0, 0);
      };
      attr(0, pos, 3);
      attr(1, nor, 3);
      if (hasUV) attr(2, uv!, 2); else { gl.disableVertexAttribArray(2); gl.vertexAttrib2f(2, 0, 0); }
      const ib = gl.createBuffer()!; buffers.push(ib);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
      gl.bindVertexArray(null);
      const mat: Material = {
        name: m.material, color: hex(m.color), opacity: m.opacity ?? 1, roughness: m.roughness ?? 0.8, metalness: m.metalness ?? 0,
        emissive: m.emissive ?? 0, texture: m.texture || undefined, textureScale: m.textureScale ?? 1000,
        maps: this.materialMaps[m.material.toUpperCase()],
      };
      // Feature edges, nudged 2 mm outward from the group's centre (Scene3DBuilder.edgeGeometry).
      const raw = floats(m.edges, binary);
      let edgeStart = edgeTotal, edgeCount = 0;
      if (raw && raw.length >= 6) {
        const c: V3 = [(mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2];
        const e = new Float32Array(raw.length);
        for (let i = 0; i < raw.length; i += 3) {
          const dx = raw[i] - c[0], dy = raw[i + 1] - c[1], dz = raw[i + 2] - c[2];
          const l = Math.hypot(dx, dy, dz) || 1;
          e[i] = raw[i] + (dx / l) * 2; e[i + 1] = raw[i + 1] + (dy / l) * 2; e[i + 2] = raw[i + 2] + (dz / l) * 2;
        }
        edgeParts.push(e); edgeCount = e.length / 3; edgeTotal += edgeCount;
      }
      this.meshes.push({
        index, id: m.id == null ? null : String(m.id), kind: m.kind, mat, vao, count: idx.length, hasUV,
        positions: pos, indices: idx, min: mn, max: mx, edgeStart, edgeCount, rawEdges: raw, buffers,
        transparent: (1 - (m.opacity ?? 1)) > 0.3 || (m.opacity ?? 1) < 1, foliage: isFoliage(m.material),
      });
    });
    if (edgeTotal > 0) {
      const all = new Float32Array(edgeTotal * 3);
      let o = 0;
      for (const p of edgeParts) { all.set(p, o); o += p.length; }
      this.edgeVAO = this.lineVAO(all);
      this.edgeCount = edgeTotal;
    }
    this.lights = result.lights ?? [];
    this.empty = !isFinite(lo[0]);
    if (!this.empty) { this.min = lo; this.max = hi; }
    else { this.min = [0, 0, 0]; this.max = [0, 0, 0]; }
  }

  private lineVAO(data: Float32Array): WebGLVertexArrayObject {
    const gl = this.gl;
    const vao = gl.createVertexArray()!;
    gl.bindVertexArray(vao);
    const b = gl.createBuffer()!;
    this.edgeBuffers.push(b);
    gl.bindBuffer(gl.ARRAY_BUFFER, b);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
    gl.bindVertexArray(null);
    return vao;
  }

  /** Builds (once) the hand-drawn stroke lines of the Sketchy style. */
  ensureSketch() {
    if (this.sketchVAO) return;
    const out: number[] = [];
    this.sketchRanges = [];
    for (const m of this.meshes) {
      const start = out.length / 3;
      const e = m.rawEdges;
      if (e) for (let i = 0; i + 5 < e.length; i += 6) {
        for (const st of sketchStrokes([e[i], e[i + 1], e[i + 2]], [e[i + 3], e[i + 4], e[i + 5]])) {
          for (let k = 0; k + 1 < st.length; k++) out.push(...st[k], ...st[k + 1]);
        }
      }
      this.sketchRanges.push({ start, count: out.length / 3 - start });
    }
    if (out.length) this.sketchVAO = this.lineVAO(new Float32Array(out));
  }

  get center(): V3 { return [(this.min[0] + this.max[0]) / 2, (this.min[1] + this.max[1]) / 2, (this.min[2] + this.max[2]) / 2]; }
  /** Bounding sphere radius (mm): half the bounds diagonal (Scene3DBuilder.worldSphere). */
  get radius(): number { return this.empty ? 10000 : Math.max(1000, Math.hypot(this.max[0] - this.min[0], this.max[1] - this.min[1], this.max[2] - this.min[2]) / 2); }

  /** Loads (once) and returns the textures of a material; `onTextureLoaded` fires when one arrives. */
  texturesFor(mat: Material, derivedNormal: boolean): Textures {
    const key = mat.name + "|" + (mat.texture ?? "");
    let t = this.textures.get(key);
    if (!t) {
      t = {};
      this.textures.set(key, t);
      const tt = t;
      if (mat.texture) {
        this.load(mat.texture, true).then((tex) => { if (tex) { tt.albedo = tex; this.onTextureLoaded?.(); } });
        const maps = mat.maps ?? this.conventionalMaps(mat.texture);
        if (maps?.normal) this.load(maps.normal, false).then((tex) => { if (tex) { tt.normal = tex; this.onTextureLoaded?.(); } });
        if (maps?.roughness) this.load(maps.roughness, false).then((tex) => { if (tex) { tt.rough = tex; this.onTextureLoaded?.(); } });
      }
    }
    if (derivedNormal && mat.texture && !t.derived && !t.normal && !mat.maps && !this.conventionalMaps(mat.texture)) {
      const tt = t;
      tt.derived = undefined;
      this.loadDerived(mat.texture).then((tex) => { if (tex) { tt.derived = tex; this.onTextureLoaded?.(); } });
    }
    return t;
  }

  /** "textures/cedar.jpg" → cedar_n.jpg / cedar_r.jpg when the document gives no MATMAPS (the demo textures' naming). */
  conventionalMaps(texture: string): MaterialMaps | undefined {
    if (!this.guessMaps) return undefined;
    const m = /^(.*)\.(jpe?g|png)$/i.exec(texture);
    if (!m || /_(n|r)$/i.test(m[1])) return undefined;
    return { normal: `${m[1]}_n.${m[2]}`, roughness: `${m[1]}_r.${m[2]}`, normalStrength: 1 };
  }

  private load(path: string, srgb: boolean): Promise<WebGLTexture | null> {
    const key = path + (srgb ? "|s" : "|l");
    let p = this.texCache.get(key);
    if (!p) {
      p = this.loadImage(this.resolve(path)).then((img) => imageTexture(this.gl, img, srgb, 16)).catch(() => null);
      this.texCache.set(key, p);
    }
    return p;
  }

  private loadDerived(path: string): Promise<WebGLTexture | null> {
    const key = path + "|derived";
    let p = this.texCache.get(key);
    if (!p) {
      p = this.loadImage(this.resolve(path)).then((img) => {
        const c = normalFromImage(img, 0.6);
        return c ? imageTexture(this.gl, c as any, false, 16) : null;
      }).catch(() => null);
      this.texCache.set(key, p);
    }
    return p;
  }

  dispose() {
    const gl = this.gl;
    for (const m of this.meshes) { gl.deleteVertexArray(m.vao); for (const b of m.buffers) gl.deleteBuffer(b); }
    for (const b of this.edgeBuffers) gl.deleteBuffer(b);
    if (this.edgeVAO) gl.deleteVertexArray(this.edgeVAO);
    if (this.sketchVAO) gl.deleteVertexArray(this.sketchVAO);
    this.meshes = []; this.edgeBuffers = []; this.edgeVAO = null; this.sketchVAO = null; this.edgeCount = 0;
  }

  // MARK: ray casts (picking and walk collisions), model millimetres

  /** Parameter t ∈ [0, 1] of the first triangle hit on segment a→b and the mesh hit (WalkPhysics.firstHit). */
  firstHit(a: V3, b: V3, filter?: (m: MeshGPU) => boolean): { t: number; mesh: MeshGPU } | null {
    const d: V3 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let best = Infinity, bestMesh: MeshGPU | null = null;
    for (const m of this.meshes) {
      if (filter && !filter(m)) continue;
      let t0 = 0, t1 = Math.min(best, 1), miss = false;
      for (let k = 0; k < 3; k++) {
        const o = a[k], dd = d[k], lo = m.min[k] - 1, hi = m.max[k] + 1;
        if (Math.abs(dd) < 1e-12) { if (o < lo || o > hi) { miss = true; break; } continue; }
        let ta = (lo - o) / dd, tb = (hi - o) / dd;
        if (ta > tb) { const s = ta; ta = tb; tb = s; }
        t0 = Math.max(t0, ta); t1 = Math.min(t1, tb);
        if (t0 > t1) { miss = true; break; }
      }
      if (miss) continue;
      const P = m.positions, I = m.indices;
      for (let i = 0; i + 2 < I.length; i += 3) {
        const i0 = I[i] * 3, i1 = I[i + 1] * 3, i2 = I[i + 2] * 3;
        const e1x = P[i1] - P[i0], e1y = P[i1 + 1] - P[i0 + 1], e1z = P[i1 + 2] - P[i0 + 2];
        const e2x = P[i2] - P[i0], e2y = P[i2 + 1] - P[i0 + 1], e2z = P[i2 + 2] - P[i0 + 2];
        const hx = d[1] * e2z - d[2] * e2y, hy = d[2] * e2x - d[0] * e2z, hz = d[0] * e2y - d[1] * e2x;
        const det = e1x * hx + e1y * hy + e1z * hz;
        if (Math.abs(det) < 1e-12) continue;
        const f = 1 / det;
        const sx = a[0] - P[i0], sy = a[1] - P[i0 + 1], sz = a[2] - P[i0 + 2];
        const u = f * (sx * hx + sy * hy + sz * hz);
        if (u < 0 || u > 1) continue;
        const qx = sy * e1z - sz * e1y, qy = sz * e1x - sx * e1z, qz = sx * e1y - sy * e1x;
        const v = f * (d[0] * qx + d[1] * qy + d[2] * qz);
        if (v < 0 || u + v > 1) continue;
        const t = f * (e2x * qx + e2y * qy + e2z * qz);
        if (t >= 0 && t <= 1 && t < best) { best = t; bestMesh = m; }
      }
    }
    return bestMesh ? { t: best, mesh: bestMesh } : null;
  }
}

/**
 * Texture coordinates (metres of texture space) for meshes that come without them (the engine's LOD meshes):
 * spherical around the centre for foliage (TextureMapping .spherical), per-face box projection otherwise.
 */
export function generateUVs(pos: Float32Array, nor: Float32Array, spherical: boolean): Float32Array {
  const n = pos.length / 3, uv = new Float32Array(n * 2);
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < pos.length; i += 3) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], pos[i + k]); hi[k] = Math.max(hi[k], pos[i + k]); }
  const c = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2];
  const r = Math.max(Math.hypot(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]) / 2, 1);
  for (let i = 0; i < n; i++) {
    const x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
    if (spherical) {
      const dx = x - c[0], dy = y - c[1], dz = z - c[2], l = Math.max(Math.hypot(dx, dy, dz), 1e-9);
      uv[i * 2] = (Math.atan2(dy, dx) * r) / 1000; uv[i * 2 + 1] = (Math.asin(Math.max(-1, Math.min(1, dz / l))) * r) / 1000;
    } else {
      const ax = Math.abs(nor[i * 3]), ay = Math.abs(nor[i * 3 + 1]), az = Math.abs(nor[i * 3 + 2]);
      if (az >= ax && az >= ay) { uv[i * 2] = x / 1000; uv[i * 2 + 1] = y / 1000; }
      else if (ax >= ay) { uv[i * 2] = y / 1000; uv[i * 2 + 1] = z / 1000; }
      else { uv[i * 2] = x / 1000; uv[i * 2 + 1] = z / 1000; }
    }
  }
  return uv;
}

export function computeNormals(pos: Float32Array, idx: Uint32Array): Float32Array {
  const n = new Float32Array(pos.length);
  for (let i = 0; i + 2 < idx.length; i += 3) {
    const a = idx[i] * 3, b = idx[i + 1] * 3, c = idx[i + 2] * 3;
    const ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1], uz = pos[b + 2] - pos[a + 2];
    const vx = pos[c] - pos[a], vy = pos[c + 1] - pos[a + 1], vz = pos[c + 2] - pos[a + 2];
    const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    for (const k of [a, b, c]) { n[k] += nx; n[k + 1] += ny; n[k + 2] += nz; }
  }
  for (let i = 0; i < n.length; i += 3) { const l = Math.hypot(n[i], n[i + 1], n[i + 2]) || 1; n[i] /= l; n[i + 1] /= l; n[i + 2] /= l; }
  return n;
}
