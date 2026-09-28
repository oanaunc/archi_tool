// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Camera-facing cut-outs of the 3D view and renders (ArchiApp/SceneExtras.swift Billboards, BILLBOARD): the built-in
// person, tree and shrub silhouettes drawn as on the Mac, or a PNG with transparency, on a plane of the given height
// that turns about the vertical axis towards the camera (SCNBillboardConstraint freeAxes .Y), cut out by alpha.
import { V3, M4 } from "./math";
import type { SceneModel, MeshGPU, Material } from "./scene";

export interface BillboardItem { id: number | string; position: V3; height: number; source: string }

const drawn = new Map<string, { url: string; aspect: number }>();

/** The Mac's built-in cut-outs (NSBezierPath drawings, origin bottom-left) as PNG data URLs. */
export function builtinBillboard(source: string): { url: string; aspect: number } | null {
  const k = source.toLowerCase();
  if (!["person", "tree", "shrub"].includes(k)) return null;
  const hit = drawn.get(k);
  if (hit) return hit;
  const size = k === "person" ? [120, 400] : k === "tree" ? [300, 400] : [300, 180];
  const c = document.createElement("canvas");
  c.width = size[0]; c.height = size[1];
  const g = c.getContext("2d")!;
  // Flip to the Mac's bottom-left origin.
  g.translate(0, size[1]); g.scale(1, -1);
  const oval = (x: number, y: number, w: number, h: number) => { g.beginPath(); g.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2); g.fill(); };
  const round = (x: number, y: number, w: number, h: number, r: number) => { g.beginPath(); g.roundRect(x, y, w, h, r); g.fill(); };
  if (k === "person") {
    g.fillStyle = "rgb(64,64,64)";
    oval(42, 330, 36, 44);
    round(26, 190, 68, 140, 22);
    round(32, 0, 24, 200, 10);
    round(64, 0, 24, 200, 10);
  } else if (k === "tree") {
    g.fillStyle = "rgb(102,71,46)";
    g.fillRect(138, 0, 24, 190);
    g.fillStyle = "rgba(66,122,56,0.95)";
    for (const [x, y, s] of [[150, 270, 170], [95, 230, 120], [205, 235, 120], [150, 330, 120]]) oval(x - s / 2, y - s / 2, s, s);
  } else {
    g.fillStyle = "rgba(77,133,64,0.95)";
    for (const [x, y, s] of [[80, 70, 130], [150, 95, 160], [220, 70, 130]]) oval(x - s / 2, y - s / 2, s, s);
  }
  const r = { url: c.toDataURL("image/png"), aspect: size[0] / size[1] };
  drawn.set(k, r);
  return r;
}

/** Aspect (width / height) of an image file, 0.5 when it cannot be read. */
async function imageAspect(url: string): Promise<number> {
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    return img.naturalWidth / Math.max(img.naturalHeight, 1);
  } catch { return 0.5; }
}

/** Replaces the scene's billboards (kind "billboard" meshes) with `items`. */
export async function setBillboards(scene: SceneModel, items: BillboardItem[], resolve: (p: string) => string): Promise<void> {
  const gl = scene.gl;
  for (const m of scene.meshes.filter((x) => x.kind === "billboard")) { gl.deleteVertexArray(m.vao); for (const b of m.buffers) gl.deleteBuffer(b); }
  scene.meshes = scene.meshes.filter((x) => x.kind !== "billboard");
  for (const it of items) {
    const b = builtinBillboard(it.source);
    const texture = b ? b.url : it.source;
    const aspect = b ? b.aspect : await imageAspect(resolve(it.source));
    const h = Math.max(it.height, 10), w = h * aspect;
    const [x, y, z] = it.position;
    // Plane facing −Y through the base point (turned towards the camera by orientBillboards).
    const pos = new Float32Array([x - w / 2, y, z, x + w / 2, y, z, x + w / 2, y, z + h, x - w / 2, y, z + h]);
    const nor = new Float32Array([0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0]);
    // Texture coordinates in metres of texture space × textureScale 1000 → one image over the plane.
    const uv = new Float32Array([0, 1, 1, 1, 1, 0, 0, 0]);
    const idx = new Uint32Array([0, 1, 2, 0, 2, 3]);
    const vao = gl.createVertexArray()!;
    gl.bindVertexArray(vao);
    const buffers: WebGLBuffer[] = [];
    const attr = (loc: number, data: Float32Array, size: number) => {
      const buf = gl.createBuffer()!; buffers.push(buf);
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 0, 0);
    };
    attr(0, pos, 3); attr(1, nor, 3); attr(2, uv, 2);
    const ib = gl.createBuffer()!; buffers.push(ib);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
    gl.bindVertexArray(null);
    const mat: Material = { name: "Billboard " + it.source, color: [1, 1, 1], opacity: 1, roughness: 1, metalness: 0, emissive: 0, texture, textureScale: 1000 };
    const mesh: MeshGPU = {
      index: scene.meshes.length, id: String(it.id), kind: "billboard", mat, vao, count: 6, hasUV: true,
      positions: pos, indices: idx, min: [x - w / 2, y - w / 2, z], max: [x + w / 2, y + w / 2, z + h], edgeStart: 0, edgeCount: 0, rawEdges: null, buffers,
      transparent: false, foliage: false, level: null, ib, xf: null, hidden: false, parts: null,
    };
    scene.meshes.push(mesh);
  }
}

/** Turns every billboard about its vertical axis towards the eye (model mm). */
export function orientBillboards(scene: SceneModel, eye: V3) {
  for (const m of scene.meshes) {
    if (m.kind !== "billboard") continue;
    const bx = (m.min[0] + m.max[0]) / 2, by = (m.min[1] + m.max[1]) / 2;
    const dx = eye[0] - bx, dy = eye[1] - by;
    if (Math.hypot(dx, dy) < 1e-6) continue;
    const t = Math.atan2(dx, -dy), c = Math.cos(t), s = Math.sin(t);
    const xf: M4 = new Float32Array(16);
    xf[0] = c; xf[1] = s; xf[4] = -s; xf[5] = c; xf[10] = 1; xf[15] = 1;
    xf[12] = bx - c * bx + s * by; xf[13] = by - s * bx - c * by;
    m.xf = xf;
  }
}
