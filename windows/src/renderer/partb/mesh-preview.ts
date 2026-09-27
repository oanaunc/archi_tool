// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Small shaded 3D preview for tool windows (node editor output, family editor): the engine's mesh groups (model.meshes
// format: base64 Float32 positions/normals, Uint32 indices, Z up) drawn flat-shaded with the painter's algorithm, like the
// Mac FamilyPreviewProjection; drag to orbit, wheel to zoom.
import { h } from "../dom";

interface Tri { a: number[]; b: number[]; c: number[]; color: [number, number, number]; opacity: number }

function b64(s: string): ArrayBuffer {
  const bin = atob(s);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u.buffer;
}
function hexRGB(hex: string): [number, number, number] {
  const t = (hex || "#cccccc").replace("#", "");
  return [parseInt(t.slice(0, 2), 16) || 200, parseInt(t.slice(2, 4), 16) || 200, parseInt(t.slice(4, 6), 16) || 200];
}

export function decodeMeshes(meshes: any[], limit = 60000): Tri[] {
  const out: Tri[] = [];
  for (const m of meshes ?? []) {
    if (typeof m.positions !== "string" || typeof m.indices !== "string") continue;
    const p = new Float32Array(b64(m.positions)), idx = new Uint32Array(b64(m.indices));
    const color = hexRGB(m.color);
    for (let i = 0; i + 2 < idx.length && out.length < limit; i += 3) {
      const a = idx[i] * 3, b = idx[i + 1] * 3, c = idx[i + 2] * 3;
      out.push({ a: [p[a], p[a + 1], p[a + 2]], b: [p[b], p[b + 1], p[b + 2]], c: [p[c], p[c + 1], p[c + 2]], color, opacity: m.opacity ?? 1 });
    }
  }
  return out;
}

export class MeshPreview {
  el: HTMLElement;
  private cv: HTMLCanvasElement;
  private tris: Tri[] = [];
  yaw = -0.8;
  pitch = 0.62;
  private zoom = 1;
  private center = [0, 0, 0];
  private radius = 1;
  message = "";
  constructor(private background = "#1A1A1A") {
    this.cv = h("canvas", { style: { width: "100%", height: "100%", display: "block" } }) as HTMLCanvasElement;
    this.el = h("div", { style: { position: "relative", flex: "1", minHeight: "0", background } }, this.cv);
    this.cv.addEventListener("mousedown", (e) => {
      const x0 = e.clientX, y0 = e.clientY, yaw0 = this.yaw, p0 = this.pitch;
      const mv = (ev: MouseEvent) => { this.yaw = yaw0 + (ev.clientX - x0) * 0.01; this.pitch = Math.max(-1.5, Math.min(1.5, p0 + (ev.clientY - y0) * 0.01)); this.draw(); };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up);
    });
    this.cv.addEventListener("wheel", (e) => { e.preventDefault(); this.zoom = Math.max(0.2, Math.min(8, this.zoom * Math.exp(-e.deltaY * 0.0015))); this.draw(); }, { passive: false });
    new ResizeObserver(() => this.draw()).observe(this.el);
  }
  set(meshes: any[], frame = true) {
    this.tris = decodeMeshes(meshes);
    if (frame || this.radius <= 1) {
      let lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
      for (const t of this.tris) for (const v of [t.a, t.b, t.c]) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], v[k]); hi[k] = Math.max(hi[k], v[k]); }
      if (isFinite(lo[0])) {
        const r = Math.hypot(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]) / 2;
        const moved = Math.abs(r - this.radius) > this.radius * 0.5;
        if (frame || moved) { this.center = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2]; this.radius = Math.max(r, 1e-6); }
      }
    }
    this.draw();
  }
  draw() {
    const w = this.el.clientWidth, hh = this.el.clientHeight, dpr = devicePixelRatio || 1;
    if (!w || !hh) return;
    this.cv.width = w * dpr; this.cv.height = hh * dpr;
    const g = this.cv.getContext("2d")!;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.fillStyle = this.background; g.fillRect(0, 0, w, hh);
    if (!this.tris.length) {
      g.fillStyle = "#6B6C72"; g.font = "11px 'Segoe UI', sans-serif"; g.textAlign = "center";
      g.fillText(this.message || "No output", w / 2, hh / 2);
      return;
    }
    const cy = Math.cos(this.yaw), sy = Math.sin(this.yaw), cp = Math.cos(this.pitch), sp = Math.sin(this.pitch);
    const s = (Math.min(w, hh) / (2.2 * this.radius)) * this.zoom;
    const view = (v: number[]) => {
      const x = v[0] - this.center[0], y = v[1] - this.center[1], z = v[2] - this.center[2];
      const x1 = x * cy - y * sy, y1 = x * sy + y * cy;       // yaw about Z
      const y2 = y1 * cp - z * sp, z2 = y1 * sp + z * cp;     // tilt
      return [x1, z2, y2];                                     // screen x, screen up, depth (towards the viewer = -)
    };
    const L = [0.35, 0.8, -0.5];
    const faces: { p: number[][]; d: number; c: string }[] = [];
    for (const t of this.tris) {
      const a = view(t.a), b = view(t.b), c = view(t.c);
      const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2], vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
      let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      const nl = Math.hypot(nx, ny, nz) || 1; nx /= nl; ny /= nl; nz /= nl;
      if (nz > 0) { nx = -nx; ny = -ny; nz = -nz; }
      const lam = Math.max(0, nx * L[0] + ny * L[1] + nz * L[2]);
      const k = 0.42 + 0.58 * lam;
      faces.push({ p: [a, b, c], d: (a[2] + b[2] + c[2]) / 3, c: `rgba(${Math.round(t.color[0] * k)},${Math.round(t.color[1] * k)},${Math.round(t.color[2] * k)},${t.opacity})` });
    }
    faces.sort((f1, f2) => f2.d - f1.d);
    g.lineJoin = "round";
    for (const f of faces) {
      g.beginPath();
      g.moveTo(w / 2 + f.p[0][0] * s, hh / 2 - f.p[0][1] * s);
      g.lineTo(w / 2 + f.p[1][0] * s, hh / 2 - f.p[1][1] * s);
      g.lineTo(w / 2 + f.p[2][0] * s, hh / 2 - f.p[2][1] * s);
      g.closePath();
      g.fillStyle = f.c; g.fill();
      g.strokeStyle = f.c; g.lineWidth = 0.5; g.stroke();
    }
  }
}
