// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// View cube (Viewport3DExtras.swift ViewCubeView): a small cube mirroring the camera orientation; clicking a face,
// edge or corner looks from that direction. Drawn with Canvas 2D (orthographic, like the Mac's SceneKit cube).

import { V3, dot } from "./math";
import { CameraState, basis } from "./camera";

interface Face { label: string; n: V3; r: V3; u: V3 }
// Model axes: FRONT = south (−Y), RIGHT = east (+X), BACK = north (+Y), LEFT = west (−X), TOP (+Z), BOTTOM (−Z).
const FACES: Face[] = [
  { label: "FRONT", n: [0, -1, 0], r: [1, 0, 0], u: [0, 0, 1] },
  { label: "RIGHT", n: [1, 0, 0], r: [0, 1, 0], u: [0, 0, 1] },
  { label: "BACK", n: [0, 1, 0], r: [-1, 0, 0], u: [0, 0, 1] },
  { label: "LEFT", n: [-1, 0, 0], r: [0, -1, 0], u: [0, 0, 1] },
  { label: "TOP", n: [0, 0, 1], r: [1, 0, 0], u: [0, 1, 0] },
  { label: "BOTTOM", n: [0, 0, -1], r: [1, 0, 0], u: [0, -1, 0] },
];

export class ViewCube {
  readonly canvas: HTMLCanvasElement;
  private cam: CameraState | null = null;
  onPick: ((dir: V3) => void) | null = null;
  constructor(readonly size = 96) {
    const c = document.createElement("canvas");
    c.className = "v3d-cube";
    c.title = "View cube: click a face, edge or corner";
    c.style.width = c.style.height = size + "px";
    this.canvas = c;
    c.addEventListener("mousedown", (e) => { e.stopPropagation(); this.click(e); });
  }

  private project(p: V3, b: { r: V3; u: V3 }, px: number): [number, number] {
    // SceneKit orthographicScale 1.05: half the view height is 1.05 cube units.
    const k = (px / 2) / 1.05;
    return [px / 2 + dot(p, b.r) * k, px / 2 - dot(p, b.u) * k];
  }

  sync(cam: CameraState) {
    const same = this.cam && this.cam.eye.every((v, i) => v === cam.eye[i]) && this.cam.target.every((v, i) => v === cam.target[i]) && this.cam.up.every((v, i) => v === cam.up[i]);
    if (same) return;
    this.cam = { ...cam, eye: [...cam.eye] as V3, target: [...cam.target] as V3, up: [...cam.up] as V3 };
    this.draw();
  }

  draw() {
    const c = this.canvas, cam = this.cam;
    if (!cam) return;
    const dpr = Math.max(1, window.devicePixelRatio || 1);
    const px = Math.round(this.size * dpr);
    if (c.width !== px) { c.width = px; c.height = px; }
    const ctx = c.getContext("2d")!;
    ctx.clearRect(0, 0, px, px);
    const b = basis(cam);
    const vis = FACES.map((f) => ({ f, d: -dot(f.n, b.f) })).filter((x) => x.d > 1e-3).sort((a, z) => a.d - z.d);
    for (const { f } of vis) {
      const corner = (a: number, bb: number): V3 => [f.n[0] * 0.5 + f.r[0] * a + f.u[0] * bb, f.n[1] * 0.5 + f.r[1] * a + f.u[1] * bb, f.n[2] * 0.5 + f.r[2] * a + f.u[2] * bb];
      const pts = [corner(-0.5, -0.5), corner(0.5, -0.5), corner(0.5, 0.5), corner(-0.5, 0.5)].map((p) => this.project(p, b, px));
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
      ctx.closePath();
      ctx.fillStyle = "rgb(56,59,66)";
      ctx.fill();
      // Face texture: inner border and the label, mapped onto the face (affine).
      const o = this.project(corner(0, 0), b, px);
      const ex = this.project(corner(0.5, 0), b, px), ey = this.project(corner(0, 0.5), b, px);
      ctx.save();
      ctx.transform((ex[0] - o[0]) / 64, (ex[1] - o[1]) / 64, -(ey[0] - o[0]) / 64, -(ey[1] - o[1]) / 64, o[0], o[1]);
      ctx.strokeStyle = "rgba(255,255,255,0.12)";
      ctx.lineWidth = 3;
      ctx.strokeRect(-62, -62, 124, 124);
      ctx.fillStyle = "rgb(235,235,235)";
      ctx.font = `600 ${f.label.length > 5 ? 20 : 24}px system-ui, "Segoe UI", sans-serif`;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText(f.label, 0, 0);
      ctx.restore();
    }
    // Cube edges (0.75 white).
    const h = 0.505;
    const cs: V3[] = [[-h, -h, -h], [h, -h, -h], [h, h, -h], [-h, h, -h], [-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h]];
    const idx = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7];
    ctx.strokeStyle = "rgba(191,191,191,0.9)";
    ctx.lineWidth = Math.max(1, dpr);
    ctx.beginPath();
    for (let i = 0; i < idx.length; i += 2) {
      const a = cs[idx[i]], z = cs[idx[i + 1]];
      // Hidden edges (both faces turned away) are skipped.
      const mid: V3 = [(a[0] + z[0]) / 2, (a[1] + z[1]) / 2, (a[2] + z[2]) / 2];
      if (dot(mid, b.f) > 0.2) continue;
      const p = this.project(a, b, px), q = this.project(z, b, px);
      ctx.moveTo(p[0], p[1]); ctx.lineTo(q[0], q[1]);
    }
    ctx.stroke();
  }

  /** Direction (towards the eye) of the face / edge / corner under a click, as the Mac's hit test with the 0.28 threshold. */
  directionAt(x: number, y: number): V3 | null {
    if (!this.cam) return null;
    const b = basis(this.cam);
    const px = this.size;
    const vis = FACES.map((f) => ({ f, d: -dot(f.n, b.f) })).filter((q) => q.d > 1e-3).sort((a, z) => z.d - a.d);
    for (const { f } of vis) {
      const P = (a: number, bb: number) => this.project([f.n[0] * 0.5 + f.r[0] * a + f.u[0] * bb, f.n[1] * 0.5 + f.r[1] * a + f.u[1] * bb, f.n[2] * 0.5 + f.r[2] * a + f.u[2] * bb], b, px);
      const o = P(0, 0), ex = P(1, 0), ey = P(0, 1);
      const ax = ex[0] - o[0], ay = ex[1] - o[1], bx = ey[0] - o[0], by = ey[1] - o[1];
      const det = ax * by - ay * bx;
      if (Math.abs(det) < 1e-6) continue;
      const dx = x - o[0], dy = y - o[1];
      const a = (dx * by - dy * bx) / det, bb = (ax * dy - ay * dx) / det;
      if (Math.abs(a) > 0.5 || Math.abs(bb) > 0.5) continue;
      const p: V3 = [f.n[0] * 0.5 + f.r[0] * a + f.u[0] * bb, f.n[1] * 0.5 + f.r[1] * a + f.u[1] * bb, f.n[2] * 0.5 + f.r[2] * a + f.u[2] * bb];
      const axis = (v: number) => (v > 0.28 ? 1 : v < -0.28 ? -1 : 0);
      const d: V3 = [axis(p[0]), axis(p[1]), axis(p[2])];
      return d[0] || d[1] || d[2] ? d : f.n;
    }
    return null;
  }

  private click(e: MouseEvent) {
    const r = this.canvas.getBoundingClientRect();
    const d = this.directionAt(e.clientX - r.left, e.clientY - r.top);
    if (d) this.onPick?.(d);
  }
}
