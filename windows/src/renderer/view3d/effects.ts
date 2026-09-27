// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Pure logic of the Mac 3D extras, number for number: the gizmo maths (ArchiApp/Viewport3DTools.swift GizmoMath),
// 3D measuring (Measure3D), levels in 3D (Studio3D.swift LevelView3D, FieldOfView), object and door animations
// (SceneEffects.swift ObjectAnimation / ObjectAnimations.splitDoor), weather and seasons (WeatherSettings), water
// waves (WaterSurface), the sun study (RenderController.swift SunPosition + ArchiCore SolarCalculator) and the
// omni-directional stereo offsets of StereoPanorama.swift.

import { V3, M4, ident, mul } from "./math";

/** ArchiCore `fmt`: rounded to `decimals`, trailing zeros removed. */
export function fmt(v: number, decimals = 4): string {
  if (Number.isNaN(v)) return "NaN";
  const k = Math.pow(10, decimals);
  const r = Math.round(v * k) / k;
  if (r === Math.round(r) && Math.abs(r) < 1e15) return String(Math.round(r) === 0 ? 0 : Math.round(r));
  let s = r.toFixed(decimals);
  while (s.endsWith("0")) s = s.slice(0, -1);
  if (s.endsWith(".")) s = s.slice(0, -1);
  return s === "-0" ? "0" : s;
}

// MARK: gizmo

export type GizmoMode = "Off" | "Move" | "Rotate" | "Scale";
export const GIZMO_MODES: GizmoMode[] = ["Off", "Move", "Rotate", "Scale"];

export const GizmoMath = {
  /** Model displacement along an axis for a drag, given the screen projection of the axis per model unit. */
  axisDelta(drag: [number, number], axisScreen: [number, number]): number {
    const l2 = axisScreen[0] * axisScreen[0] + axisScreen[1] * axisScreen[1];
    if (l2 <= 1e-12) return 0;
    return (drag[0] * axisScreen[0] + drag[1] * axisScreen[1]) / l2;
  },
  /** Signed angle (radians, counter-clockwise on screen with y up) swept from a to b around c. */
  sweep(c: [number, number], a: [number, number], b: [number, number]): number {
    const a0 = Math.atan2(a[1] - c[1], a[0] - c[0]), a1 = Math.atan2(b[1] - c[1], b[0] - c[0]);
    let d = a1 - a0;
    while (d > Math.PI) d -= 2 * Math.PI;
    while (d < -Math.PI) d += 2 * Math.PI;
    return d;
  },
  axisName(axis: number): string { return ["X", "Y", "rotation", "Z", "scale"][Math.min(Math.max(axis, 0), 4)]; },
  scaleFactor(c: [number, number], a: [number, number], b: [number, number], step = 0): number {
    const d0 = Math.hypot(a[0] - c[0], a[1] - c[1]), d1 = Math.hypot(b[0] - c[0], b[1] - c[1]);
    if (d0 <= 1e-6) return 1;
    return Math.min(Math.max(GizmoMath.snap(d1 / d0, step), 0.01), 100);
  },
  snap(v: number, step: number): number { return step > 0 ? Math.round(v / step) * step : v; },
  /** Live readout (model.live.snapHint of the Mac). */
  hint(axis: number, amount: number): string {
    if (axis === 4) return `Scale ×${fmt(amount > 0 ? amount : 1, 3)} in plan (Shift snaps 0.1)`;
    if (axis === 2) return `Rotate ${fmt((amount * 180) / Math.PI, 1)}° (Shift snaps 15°)`;
    return `Move ${GizmoMath.axisName(axis)} ${fmt(amount, 1)}`;
  },
  /** Preview transform of the selected meshes (model mm): axis 0/1/3 move, 2 rotate about Z through the pivot, 4 scale in plan. */
  matrix(axis: number, amount: number, pivot: V3): M4 {
    const m = ident();
    if (axis === 4) {
      const f = amount > 0 ? amount : 1;
      m[0] = f; m[5] = f; m[12] = pivot[0] * (1 - f); m[13] = pivot[1] * (1 - f);
    } else if (axis === 2) {
      const c = Math.cos(amount), s = Math.sin(amount);
      m[0] = c; m[1] = s; m[4] = -s; m[5] = c;
      m[12] = pivot[0] - c * pivot[0] + s * pivot[1];
      m[13] = pivot[1] - s * pivot[0] - c * pivot[1];
    } else {
      m[12] = axis === 0 ? amount : 0; m[13] = axis === 1 ? amount : 0; m[14] = axis === 3 ? amount : 0;
    }
    return m;
  },
};

// MARK: measure

export function describeMeasure(a: V3, b: V3, precision = 1): string {
  const d: V3 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  return `Distance ${fmt(Math.hypot(d[0], d[1], d[2]), precision)} · ΔX ${fmt(d[0], precision)} · ΔY ${fmt(d[1], precision)} · ΔZ ${fmt(d[2], precision)}`
    + ` · plan ${fmt(Math.hypot(d[0], d[1]), precision)}`;
}

// MARK: levels in 3D, field of view

export interface LevelInfo { id: number; name: string; elevation: number; height?: number }

/** Vertical offset of each level for an exploded view: sorted by elevation, the lowest stays put. */
export function levelOffsets(levels: LevelInfo[], gap: number): Map<number, number> {
  const out = new Map<number, number>();
  [...levels].sort((a, b) => a.elevation - b.elevation || a.id - b.id).forEach((l, k) => out.set(l.id, k * gap));
  return out;
}
export function levelVisible(level: number | null | undefined, isolate: number | null | undefined): boolean {
  if (isolate == null || level == null) return true;
  return level === isolate;
}
export const FieldOfView = {
  clamp: (v: number) => Math.min(Math.max(v, 15), 120),
  focalLength: (fov: number) => 12 / Math.tan((FieldOfView.clamp(fov) * Math.PI) / 360),
  fov: (f: number) => FieldOfView.clamp((2 * Math.atan(12 / Math.max(f, 1e-6)) * 180) / Math.PI),
};

// MARK: object animation (OBJANIM)

export interface DoorLeaf { hinge: [number, number]; sign: number; s0: number; s1: number; origin: [number, number]; dir: [number, number]; normal: [number, number]; wallHalf: number }
export interface ObjectAnimation {
  id: number; target: number; kind: "Rotate" | "Move" | "Door" | string;
  pivot?: V3 | { x: number; y: number; z: number }; angle?: number; offset?: V3 | { x: number; y: number; z: number };
  start?: number; duration?: number; pingPong?: boolean; name?: string;
  leafIndex?: number; leaf?: DoorLeaf;
}

function v3of(v: any): V3 {
  if (!v) return [0, 0, 0];
  if (Array.isArray(v)) return [v[0] ?? 0, v[1] ?? 0, v[2] ?? 0];
  return [v.x ?? 0, v.y ?? 0, v.z ?? 0];
}

export const Anim = {
  end(a: ObjectAnimation): number { return (a.start ?? 0) + Math.max(a.duration ?? 2, 1e-6) * ((a.pingPong ?? true) ? 2 : 1); },
  duration(list: ObjectAnimation[]): number { return list.reduce((m, a) => Math.max(m, Anim.end(a)), 0); },
  /** Eased progress 0…1 at time t (smoothstep; back to 0 in the second half of a ping-pong). */
  progress(a: ObjectAnimation, t: number): number {
    const d = Math.max(a.duration ?? 2, 1e-6);
    let x = (t - (a.start ?? 0)) / d;
    if (x <= 0) return 0;
    if (a.pingPong ?? true) x = x >= 2 ? 0 : x > 1 ? 2 - x : x; else x = Math.min(x, 1);
    return x * x * (3 - 2 * x);
  },
  /** Model-mm transform at time t: rotation about +Z through the pivot, then the offset. */
  matrix(a: ObjectAnimation, t: number): M4 {
    const f = Anim.progress(a, t);
    const ang = ((a.angle ?? 90) * Math.PI / 180) * f;
    const off = v3of(a.offset), p = v3of(a.pivot);
    const c = Math.cos(ang), s = Math.sin(ang);
    const m = ident();
    m[0] = c; m[1] = s; m[4] = -s; m[5] = c;
    m[12] = p[0] - c * p[0] + s * p[1] + off[0] * f;
    m[13] = p[1] - s * p[0] - c * p[1] + off[1] * f;
    m[14] = off[2] * f;
    return m;
  },
};

/**
 * Splits a door mesh into the frame and one part per leaf (ObjectAnimations.splitDoor): a triangle belongs to a leaf
 * when all its vertices lie within the leaf span along the wall and clear of the wall faces. Returns the reordered
 * index buffer (rest first, then each leaf) and the ranges (in indices).
 */
export function splitDoor(pos: Float32Array, idx: Uint32Array, leaves: DoorLeaf[], e = 0.5): { indices: Uint32Array; ranges: { start: number; count: number }[] } {
  const parts: number[][] = leaves.map(() => []);
  const rest: number[] = [];
  const nv = pos.length / 3;
  for (let i = 0; i + 2 < idx.length; i += 3) {
    const ids = [idx[i], idx[i + 1], idx[i + 2]];
    if (ids.some((j) => j >= nv)) continue;
    let placed = false;
    for (let k = 0; k < leaves.length; k++) {
      const l = leaves[k];
      const inLeaf = ids.every((j) => {
        const px = pos[j * 3] - l.origin[0], py = pos[j * 3 + 1] - l.origin[1];
        const s = px * l.dir[0] + py * l.dir[1], t = px * l.normal[0] + py * l.normal[1];
        return s >= l.s0 - e && s <= l.s1 + e && Math.abs(t) < l.wallHalf - e;
      });
      if (inLeaf) { parts[k].push(...ids); placed = true; break; }
    }
    if (!placed) rest.push(...ids);
  }
  const out = new Uint32Array(rest.length + parts.reduce((n, p) => n + p.length, 0));
  out.set(rest, 0);
  const ranges = [{ start: 0, count: rest.length }];
  let o = rest.length;
  for (const p of parts) { out.set(p, o); ranges.push({ start: o, count: p.length }); o += p.length; }
  return { indices: out, ranges };
}

/** Which door part (0 = frame, k + 1 = leaf k) an edge segment belongs to. */
export function doorPartOfSegment(a: V3, b: V3, leaves: DoorLeaf[], e = 0.5): number {
  for (let k = 0; k < leaves.length; k++) {
    const l = leaves[k];
    const inside = (p: V3) => {
      const px = p[0] - l.origin[0], py = p[1] - l.origin[1];
      const s = px * l.dir[0] + py * l.dir[1], t = px * l.normal[0] + py * l.normal[1];
      return s >= l.s0 - e && s <= l.s1 + e && Math.abs(t) < l.wallHalf - e;
    };
    if (inside(a) && inside(b)) return k + 1;
  }
  return 0;
}

// MARK: weather, seasons, water

export type WeatherKind = "Clear" | "Rain" | "Snow" | "Fog";
export type Season = "Spring" | "Summer" | "Autumn" | "Winter";
export interface Weather {
  kind: WeatherKind; intensity: number; season: Season; snowCover: number;
  wetness?: number; snow?: number; fogDistance?: number | null;
  particles?: { birthRatePerM2: number; speed: number; size: number; life: number; stretch: number } | null;
}
export const CLEAR_WEATHER: Weather = { kind: "Clear", intensity: 0.5, season: "Summer", snowCover: 0 };

/** WEATHER = "kind;intensity;season;snowCover" → settings with the derived values of WeatherSettings. */
export function parseWeather(s: string | null | undefined): Weather {
  const w: Weather = { ...CLEAR_WEATHER };
  if (s) {
    const p = s.split(";");
    const kinds: WeatherKind[] = ["Clear", "Rain", "Snow", "Fog"], seasons: Season[] = ["Spring", "Summer", "Autumn", "Winter"];
    const k = kinds.find((x) => x.toLowerCase() === (p[0] ?? "").toLowerCase());
    if (k) {
      w.kind = k;
      if (p.length > 1 && isFinite(+p[1]) && p[1] !== "") w.intensity = Math.min(Math.max(+p[1], 0), 1);
      const se = seasons.find((x) => x.toLowerCase() === (p[2] ?? "").toLowerCase());
      if (se) w.season = se;
      if (p.length > 3 && isFinite(+p[3]) && p[3] !== "") w.snowCover = Math.min(Math.max(+p[3], 0), 1);
    }
  }
  return withDerived(w);
}

export function withDerived(w: Weather): Weather {
  const wet = w.kind === "Rain" ? w.intensity : 0;
  const snow = w.snowCover > 0 ? w.snowCover : w.kind === "Snow" ? w.intensity * 0.8 : 0;
  const fog = w.kind === "Fog" ? 30 + 400 * (1 - w.intensity) : w.kind === "Rain" ? 300 + 1500 * (1 - w.intensity) : w.kind === "Snow" ? 150 + 800 * (1 - w.intensity) : null;
  const particles = w.kind === "Rain" ? { birthRatePerM2: 40 * w.intensity, speed: 6 + 3 * w.intensity, size: 0.006, life: 2.2, stretch: 12 }
    : w.kind === "Snow" ? { birthRatePerM2: 12 * w.intensity, speed: 0.8 + 0.4 * w.intensity, size: 0.02 + 0.015 * w.intensity, life: 12, stretch: 0 } : null;
  return { ...w, wetness: wet, snow, fogDistance: fog, particles };
}

export function isVegetation(material: string): boolean {
  const n = material.toLowerCase();
  return ["grass", "lawn", "leaf", "leaves", "foliage", "tree", "hedge", "shrub", "plant", "ivy", "moss"].some((k) => n.includes(k));
}

/** Seasonal colour of vegetation (sRGB): spring fresh green, summer unchanged, autumn orange-brown, winter brown-grey. */
export function seasonTint(c: V3, s: Season): V3 {
  const mix = (t: V3, k: number): V3 => [c[0] + (t[0] - c[0]) * k, c[1] + (t[1] - c[1]) * k, c[2] + (t[2] - c[2]) * k];
  switch (s) {
    case "Spring": return mix([0.55, 0.78, 0.30], 0.35);
    case "Autumn": return mix([0.78, 0.45, 0.14], 0.6);
    case "Winter": return mix([0.45, 0.40, 0.33], 0.7);
    default: return c;
  }
}

/** Water materials: MATWATER:<name> = 1, or the material named "Water" (WaterSurface.isWater). */
export function isWater(material: string, water: Set<string> | null): boolean {
  if (water) return water.has(material) || water.has(material.toUpperCase());
  return material.toLowerCase() === "water";
}

// MARK: sun study (NOAA solar calculator, SunPosition.compute)

const rad = (d: number) => (d * Math.PI) / 180, dg = (r: number) => (r * 180) / Math.PI;

function ephemeris(jd: number) {
  const t = (jd - 2451545.0) / 36525.0;
  const l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360;
  const m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  const e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  const mr = rad(m);
  const c = Math.sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) + Math.sin(2 * mr) * (0.019993 - 0.000101 * t) + Math.sin(3 * mr) * 0.000289;
  const trueLong = l0 + c;
  const omega = 125.04 - 1934.136 * t;
  const lambda = trueLong - 0.00569 - 0.00478 * Math.sin(rad(omega));
  const eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
  const eps = eps0 + 0.00256 * Math.cos(rad(omega));
  const decl = dg(Math.asin(Math.sin(rad(eps)) * Math.sin(rad(lambda))));
  const y = Math.pow(Math.tan(rad(eps / 2)), 2);
  const l0r = rad(l0);
  const eot = 4 * dg(y * Math.sin(2 * l0r) - 2 * e * Math.sin(mr) + 4 * e * y * Math.sin(mr) * Math.cos(2 * l0r) - 0.5 * y * y * Math.sin(4 * l0r) - 1.25 * e * e * Math.sin(2 * mr));
  return { decl, eot };
}

function refraction(e: number): number {
  if (e > 85) return 0;
  const te = Math.tan(rad(e));
  let arcsec: number;
  if (e > 5) arcsec = 58.1 / te - 0.07 / Math.pow(te, 3) + 0.000086 / Math.pow(te, 5);
  else if (e > -0.575) arcsec = 1735 + e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711)));
  else arcsec = -20.772 / te;
  return arcsec / 3600;
}

/** Sun altitude and azimuth (degrees, azimuth clockwise from north) for a UTC time in ms. */
export function solarPosition(utcMs: number, latitude: number, longitude: number): { altitude: number; azimuth: number } {
  const jd = utcMs / 86400000 + 2440587.5;
  const eph = ephemeris(jd);
  const minutesUTC = (jd + 0.5 - Math.floor(jd + 0.5)) * 1440;
  let tst = (minutesUTC + eph.eot + 4 * longitude) % 1440;
  if (tst < 0) tst += 1440;
  let ha = tst / 4 - 180;
  if (ha < -180) ha += 360;
  const lat = rad(latitude), dec = rad(eph.decl), h = rad(ha);
  const cosZ = Math.max(-1, Math.min(1, Math.sin(lat) * Math.sin(dec) + Math.cos(lat) * Math.cos(dec) * Math.cos(h)));
  let alt = 90 - dg(Math.acos(cosZ));
  let az = dg(Math.atan2(Math.sin(h), Math.cos(h) * Math.sin(lat) - Math.tan(dec) * Math.cos(lat))) + 180;
  az = az % 360; if (az < 0) az += 360;
  alt += refraction(alt);
  return { altitude: alt, azimuth: az };
}

/** SunStudyPanel: sun for a day of the year and local hour (UTC offset = round(longitude / 15)). */
export function sunStudy(day: number, hour: number, latitude: number, longitude: number, year = new Date().getFullYear()) {
  const tz = Math.round(longitude / 15);
  const utc = Date.UTC(year, 0, 1) + (day - 1) * 86400000 + (hour - tz) * 3600000;
  const p = solarPosition(utc, latitude, longitude);
  const altR = rad(p.altitude);
  return {
    altitude: p.altitude, azimuth: p.azimuth,
    /** SceneKit sun intensity (/1000) and colour of Viewport3DController.applySun. */
    intensity: altR <= 0 ? 0 : (1400 * Math.min(1, Math.sin(altR) * 2.2 + 0.1)) / 1000,
    color: (altR < 0.25 ? [1, 0.78, 0.55] : [1, 0.97, 0.92]) as V3,
  };
}

export function sunStudyText(day: number, hour: number, lat: number, lon: number): { date: string; sun: string } {
  const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  const d = new Date(Date.UTC(2025, 0, day));
  const hh = Math.floor(hour), mm = Math.floor((hour - Math.floor(hour)) * 60) % 60;
  const date = `${d.getUTCDate()} ${months[d.getUTCMonth()]}  ${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
  const s = sunStudy(day, hour, lat, lon);
  const sun = s.altitude <= 0 ? "Sun below the horizon" : `Altitude ${fmt(s.altitude, 1)}°, azimuth ${fmt(s.azimuth, 1)}° · site ${fmt(lat, 2)}°, ${fmt(lon, 2)}°`;
  return { date, sun };
}

// MARK: panoramas (Panorama.faces / lookup, StereoPanorama.odsOffset) in model axes (X east, Y north, Z up)

export interface CubeFace { front: V3; up: V3 }
/** +X, −X, +Y, −Y, +Z (up), −Z (down), model axes. */
export const CUBE_FACES: CubeFace[] = [
  { front: [1, 0, 0], up: [0, 0, 1] }, { front: [-1, 0, 0], up: [0, 0, 1] },
  { front: [0, 1, 0], up: [0, 0, 1] }, { front: [0, -1, 0], up: [0, 0, 1] },
  { front: [0, 0, 1], up: [0, -1, 0] }, { front: [0, 0, -1], up: [0, 1, 0] },
];

/** Direction of an equirectangular pixel (u, v ∈ 0…1; u = 0.5 looks along `heading`, v = 0 up), model axes. */
export function panoDirection(u: number, v: number, heading: V3): V3 {
  const lon = (u - 0.5) * 2 * Math.PI, lat = (0.5 - v) * Math.PI;
  const h = Math.atan2(heading[1], heading[0]);
  const a = h - lon;
  return [Math.cos(lat) * Math.cos(a), Math.cos(lat) * Math.sin(a), Math.sin(lat)];
}

/** Cube face and face coordinates (s, t ∈ 0…1, t = 0 top) of a direction. */
export function cubeLookup(d: V3): { face: number; s: number; t: number } {
  let best = 0, bv = -Infinity;
  CUBE_FACES.forEach((f, i) => { const v = f.front[0] * d[0] + f.front[1] * d[1] + f.front[2] * d[2]; if (v > bv) { bv = v; best = i; } });
  const f = CUBE_FACES[best];
  const r: V3 = [f.front[1] * f.up[2] - f.front[2] * f.up[1], f.front[2] * f.up[0] - f.front[0] * f.up[2], f.front[0] * f.up[1] - f.front[1] * f.up[0]];
  const x = (d[0] * r[0] + d[1] * r[1] + d[2] * r[2]) / bv, y = (d[0] * f.up[0] + d[1] * f.up[1] + d[2] * f.up[2]) / bv;
  return { face: best, s: Math.min(Math.max((x + 1) / 2, 0), 1), t: Math.min(Math.max((1 - y) / 2, 0), 1) };
}

/** Sideways eye offset (model mm) of an omni-directional stereo slice looking along `dir` (−1 left eye, +1 right). */
export function odsOffset(dir: V3, ipdMM: number, eye: number): V3 {
  const l = Math.hypot(dir[0], dir[1]) || 1;
  const right: V3 = [dir[1] / l, -dir[0] / l, 0];
  const k = (eye * ipdMM) / 2;
  return [right[0] * k, right[1] * k, 0];
}

export function composeM4(...ms: M4[]): M4 { return ms.reduce((a, b) => mul(a, b), ident()); }
