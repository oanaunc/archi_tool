// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Camera of the 3D view (world metres, Z up) and the navigation of the Mac viewport: turntable orbit around a pivot,
// pan, dolly, standard views and the view cube (Viewport3DView.swift setView / zoomExtents / toggleProjection,
// Viewport3DExtras.swift setViewDirection, Navigation3DPlus.swift wheel* and two-point perspective).

import { V3, M4, add, sub, scale, len, norm, cross, dot, lookAt, perspective, ortho, deg, clamp } from "./math";

export interface CameraState {
  eye: V3;
  target: V3;
  up: V3;
  /** Vertical field of view, degrees. */
  fov: number;
  ortho: boolean;
  /** Orthographic half height (m), SceneKit orthographicScale. */
  orthoScale: number;
  /** Vertical lens shift in NDC (two-point perspective / vertical correction); 0 = none. */
  shiftY: number;
}

export function cloneCamera(c: CameraState): CameraState {
  return { eye: [...c.eye] as V3, target: [...c.target] as V3, up: [...c.up] as V3, fov: c.fov, ortho: c.ortho, orthoScale: c.orthoScale, shiftY: c.shiftY };
}

export function defaultCamera(): CameraState {
  // SceneKit's initial camera: position (−20, 15, 20) looking at the origin, 45°.
  return { eye: [-20, -20, 15], target: [0, 0, 0], up: [0, 0, 1], fov: 45, ortho: false, orthoScale: 10, shiftY: 0 };
}

export function viewMatrix(c: CameraState): M4 { return lookAt(c.eye, c.target, c.up); }

/** Near / far planes from the distance to the scene (SceneKit automaticallyAdjustsZRange). */
export function zRange(c: CameraState, center: V3, radius: number, groundExtent: number): [number, number] {
  const d = len(sub(c.eye, center));
  const near = clamp((d - radius) * 0.25, 0.05, 2);
  const far = Math.max(d + radius * 4, groundExtent * 0.8, 100);
  return [near, far];
}

export function projMatrix(c: CameraState, aspect: number, near: number, far: number): M4 {
  if (c.ortho) {
    const h = c.orthoScale, w = h * aspect;
    const d = len(sub(c.eye, c.target));
    return ortho(-w, w, -h, h, -Math.max(far, d * 4), Math.max(far, d * 4));
  }
  return perspective(c.fov * deg, aspect, near, far, c.shiftY);
}

/** Direction names of setView, in model/world coordinates (SceneKit (x, y, z) → model (x, −z, y)). */
export function viewDirection(name: string): { dir: V3; up: V3 } | null {
  const k = name.toLowerCase().replace(/[\s_-]/g, "");
  const n = (v: V3) => norm(v);
  switch (k) {
    case "top": case "plan": return { dir: [0, 0, 1], up: [0, 1, 0] };
    case "bottom": return { dir: [0, 0, -1], up: [0, -1, 0] };
    case "front": case "south": return { dir: [0, -1, 0], up: [0, 0, 1] };
    case "back": case "north": return { dir: [0, 1, 0], up: [0, 0, 1] };
    case "right": case "east": return { dir: [1, 0, 0], up: [0, 0, 1] };
    case "left": case "west": return { dir: [-1, 0, 0], up: [0, 0, 1] };
    case "seiso": return { dir: n([1, -1, 0.9]), up: [0, 0, 1] };
    case "neiso": return { dir: n([1, 1, 0.9]), up: [0, 0, 1] };
    case "nwiso": return { dir: n([-1, 1, 0.9]), up: [0, 0, 1] };
    case "iso": case "swiso": case "home": return { dir: n([-1, -1, 0.9]), up: [0, 0, 1] };
    default: return null;
  }
}

/** Camera looking at the scene sphere from a direction, at the Mac's framing distance (radius / sin(fov/2) × 1.15). */
export function framed(prev: CameraState, center: V3, radius: number, dir: V3, up: V3, factor = 1.15): CameraState {
  const d = (radius / Math.sin((prev.fov * deg) / 2)) * factor;
  const eye = add(center, scale(norm(dir), d));
  let u = up;
  if (Math.abs(dot(norm(dir), [0, 0, 1])) > 0.98) u = dir[2] > 0 ? [0, 1, 0] : [0, -1, 0];
  return { ...cloneCamera(prev), eye, target: [...center] as V3, up: u, orthoScale: radius * 1.1, shiftY: 0 };
}

/** Turntable orbit around the target (Navigation3DPlus.wheelOrbit: 0.01 rad per point, elevation within ±1.45 rad). */
export function orbit(c: CameraState, dx: number, dy: number): CameraState {
  const o = sub(c.eye, c.target);
  const r = len(o);
  const yaw = -dx * 0.01;
  const cs = Math.cos(yaw), sn = Math.sin(yaw);
  let ox = o[0] * cs - o[1] * sn, oy = o[0] * sn + o[1] * cs;
  const el = clamp(Math.asin(clamp(o[2] / Math.max(r, 1e-9), -1, 1)) + dy * 0.01, -1.45, 1.45);
  const h = Math.hypot(ox, oy);
  if (h > 1e-9) { ox /= h; oy /= h; } else {
    // Looking straight down: keep the heading of the up vector.
    ox = -c.up[0]; oy = -c.up[1]; const l = Math.hypot(ox, oy) || 1; ox /= l; oy /= l;
  }
  const eye: V3 = [c.target[0] + ox * r * Math.cos(el), c.target[1] + oy * r * Math.cos(el), c.target[2] + r * Math.sin(el)];
  return { ...cloneCamera(c), eye, up: [0, 0, 1], shiftY: 0 };
}

/** Screen axes of the camera. */
export function basis(c: CameraState): { f: V3; r: V3; u: V3 } {
  const f = norm(sub(c.target, c.eye));
  let r = cross(f, c.up);
  if (len(r) < 1e-9) r = cross(f, [0, 1, 0]);
  r = norm(r);
  return { f, r, u: cross(r, f) };
}

/** Pan by screen points (grab the scene): Navigation3DPlus.wheelPan, 0.25 % of the distance per point. */
export function pan(c: CameraState, dx: number, dy: number, viewHeight: number): CameraState {
  const { r, u } = basis(c);
  const dist = Math.max(len(sub(c.eye, c.target)), 1);
  // Perspective: the scene point at the target follows the cursor; orthographic: exactly one pixel per pixel.
  const k = c.ortho ? (2 * c.orthoScale) / Math.max(viewHeight, 1) : (2 * dist * Math.tan((c.fov * deg) / 2)) / Math.max(viewHeight, 1);
  const t = add(scale(r, -dx * k), scale(u, dy * k));
  return { ...cloneCamera(c), eye: add(c.eye, t), target: add(c.target, t) };
}

/** Dolly towards the target (Navigation3DPlus.wheelZoom: factor exp(−d · 0.01)). */
export function zoom(c: CameraState, d: number): CameraState {
  const k = Math.exp(-d * 0.01);
  if (c.ortho) return { ...cloneCamera(c), orthoScale: Math.max(0.05, c.orthoScale * k) };
  const off = sub(c.eye, c.target);
  if (len(off) * k < 0.05) return c;
  return { ...cloneCamera(c), eye: add(c.target, scale(off, k)) };
}

/** Dolly towards a point under the cursor (keeps that point fixed on screen). */
export function zoomAt(c: CameraState, d: number, point: V3): CameraState {
  const k = Math.exp(-d * 0.01);
  if (c.ortho) {
    const n = zoom(c, d);
    const t = scale(sub(point, c.target), 1 - k);
    return { ...n, eye: add(n.eye, t), target: add(n.target, t) };
  }
  const eye = add(point, scale(sub(c.eye, point), k));
  const target = add(point, scale(sub(c.target, point), k));
  if (len(sub(eye, target)) < 0.05) return c;
  return { ...cloneCamera(c), eye, target };
}

/** Switches perspective ↔ orthographic keeping the apparent size at the target (toggleProjection). */
export function toggleProjection(c: CameraState): CameraState {
  const n = cloneCamera(c);
  n.ortho = !c.ortho;
  if (n.ortho) n.orthoScale = Math.max(0.5, len(sub(c.eye, c.target)) * Math.tan((c.fov * deg) / 2));
  else {
    const d = n.orthoScale / Math.tan((c.fov * deg) / 2);
    n.eye = add(c.target, scale(norm(sub(c.eye, c.target)), d));
  }
  n.shiftY = 0;
  return n;
}

/**
 * A saved camera (model mm) as a view camera. With `verticalCorrection` a near-level eye (pitch ≤ 20°) is levelled
 * and the lens shifted so verticals stay vertical (BeautyRenderer.shiftProjection).
 */
export function fromSaved(cam: { eye: V3; target: V3; fov?: number; orthographic?: boolean }, unit: number, verticalCorrection: boolean): CameraState {
  const eye = scale(cam.eye, unit), target = scale(cam.target, unit);
  const fov = clamp(cam.fov ?? 45, 10, 120);
  const c: CameraState = { eye, target, up: [0, 0, 1], fov, ortho: !!cam.orthographic, orthoScale: len(sub(target, eye)) * 0.45, shiftY: 0 };
  if (!verticalCorrection || c.ortho) return c;
  const d = sub(target, eye);
  const horiz = Math.hypot(d[0], d[1]);
  if (horiz <= 1 * unit) return c;
  const pitch = Math.atan2(d[2], horiz);
  if (Math.abs(pitch) / deg > 20) return c;
  const f = 1 / Math.tan((fov * deg) / 2);
  return { ...c, target: [target[0], target[1], eye[2]], shiftY: Math.tan(pitch) * f };
}

/** Levels the camera and shifts the lens so the target keeps its height on screen (TWOPOINT, setTwoPoint). */
export function twoPoint(c: CameraState, on: boolean): CameraState {
  if (!on) return { ...cloneCamera(c), shiftY: 0 };
  const n = cloneCamera(c);
  n.ortho = false;
  const d = sub(c.target, c.eye);
  const horiz = Math.hypot(d[0], d[1]);
  if (horiz < 1e-6) return n;
  const pitch = Math.atan2(d[2], horiz);
  n.target = [c.target[0], c.target[1], c.eye[2]];
  n.up = [0, 0, 1];
  n.shiftY = clamp(Math.tan(pitch) / Math.tan((c.fov * deg) / 2), -3, 3);
  return n;
}

/** Smooth interpolation between two cameras (SCNTransaction animations, 0.45 s ease in-out). */
export function interpolate(a: CameraState, b: CameraState, t: number): CameraState {
  const s = t * t * (3 - 2 * t);
  const target = add(a.target, scale(sub(b.target, a.target), s));
  const da = sub(a.eye, a.target), db = sub(b.eye, b.target);
  const la = len(da), lb = len(db);
  let dir = add(scale(norm(da), 1 - s), scale(norm(db), s));
  if (len(dir) < 1e-6) dir = norm(db);
  const dist = la + (lb - la) * s;
  const up = norm(add(scale(a.up, 1 - s), scale(b.up, s)));
  return {
    eye: add(target, scale(norm(dir), dist)), target, up: len(up) > 0.1 ? up : b.up,
    fov: a.fov + (b.fov - a.fov) * s, ortho: s < 0.5 ? a.ortho : b.ortho, orthoScale: a.orthoScale + (b.orthoScale - a.orthoScale) * s,
    shiftY: a.shiftY + (b.shiftY - a.shiftY) * s,
  };
}
