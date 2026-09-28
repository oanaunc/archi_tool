// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Photographic renders for the output windows (RenderController.swift RenderEngine.render / renderAdvanced /
// renderNPR, BeautyRender.swift RENDERSAVE, RenderAnimation.swift frames): the render settings of the Render window,
// the output presets, the look they give the 3D view's renderer (lighting preset or the custom environment with the
// site's sun at the render date), white balance on the finished image (CITemperatureAndTint), regions, the Sketch and
// Watercolour styles, and frames at explicit cameras and sun positions for videos.
import type { View3D, Look, CameraState, FrameOptions } from "../view3d";
import { PRESETS, presetNamed, lookFrom, UNIT } from "../view3d";
import { fromSaved } from "../view3d/camera";
import { environmentFromBytes, type EnvImage } from "../view3d/hdri";
import { out, webFiles } from "./native";

export type V3 = [number, number, number];
export interface ModelCamera { eye: V3; target: V3; fov?: number; orthographic?: boolean; name?: string }

/** RenderSettings of the Mac render window. */
export interface RenderSettings {
  width: number; height: number;
  day: number; hour: number;
  exposure: number;
  background: "Sky" | "White" | "Transparent";
  antialias: boolean;
  environment: string; hdriPath: string; environmentIntensity: number;
  shadowQuality: "Off" | "Low" | "Medium" | "High" | "Ultra"; shadowSoftness: number; shadowSamples: number | null;
  ambientOcclusion: number;
  depthOfField: boolean; focusDistance: number; fStop: number;
  whiteBalance: number; bloom: number; clay: boolean;
  /** Photographic lighting preset (Daylight, Golden hour, Overcast, Night); null = the environment settings. */
  beauty: string | null;
  supersample: number;
}
export const SHADOW_SAMPLES: Record<string, number> = { Off: 1, Low: 4, Medium: 8, High: 16, Ultra: 32 };

export function defaultSettings(): RenderSettings {
  return {
    width: 1920, height: 1080, day: 172, hour: 15, exposure: 0, background: "Sky", antialias: true,
    environment: "Clear Sky", hdriPath: "", environmentIntensity: 1.3, shadowQuality: "High", shadowSoftness: 4, shadowSamples: null,
    ambientOcclusion: 1, depthOfField: false, focusDistance: 0, fStop: 2.8, whiteBalance: 6500, bloom: 0.15, clay: false, beauty: null, supersample: 1,
  };
}

/** A saved render preset (RenderPreset): resolution, antialiasing, exposure, background and the optional extras. */
export interface OutputPreset {
  name: string; width: number; height: number; antialias: boolean; exposure: number; background: string;
  environment?: string; environmentIntensity?: number; shadowQuality?: string; shadowSoftness?: number; ambientOcclusion?: number;
  depthOfField?: boolean; fStop?: number; whiteBalance?: number; clay?: boolean; hour?: number;
}

export function applyPreset(p: OutputPreset, s: RenderSettings) {
  const d = defaultSettings();
  s.width = p.width; s.height = p.height; s.antialias = p.antialias; s.exposure = p.exposure;
  s.background = (["Sky", "White", "Transparent"].includes(p.background) ? p.background : "Sky") as RenderSettings["background"];
  s.environment = p.environment ?? d.environment;
  s.environmentIntensity = p.environmentIntensity ?? d.environmentIntensity;
  s.shadowQuality = (p.shadowQuality as RenderSettings["shadowQuality"]) ?? d.shadowQuality;
  s.shadowSoftness = p.shadowSoftness ?? d.shadowSoftness;
  s.ambientOcclusion = p.ambientOcclusion ?? d.ambientOcclusion;
  s.depthOfField = p.depthOfField ?? false;
  s.fStop = p.fStop ?? d.fStop;
  s.whiteBalance = p.whiteBalance ?? d.whiteBalance;
  s.clay = p.clay ?? false;
  if (p.hour != null) s.hour = p.hour;
}
export function presetFrom(s: RenderSettings, name: string): OutputPreset {
  return { name, width: s.width, height: s.height, antialias: s.antialias, exposure: s.exposure, background: s.background, environment: s.environment,
    environmentIntensity: s.environmentIntensity, shadowQuality: s.shadowQuality, shadowSoftness: s.shadowSoftness, ambientOcclusion: s.ambientOcclusion,
    depthOfField: s.depthOfField, fStop: s.fStop, whiteBalance: s.whiteBalance, clay: s.clay };
}

/** Sun towards the site sun at a day / local hour (SunPosition.compute, UTC offset round(longitude / 15)). */
export function sunAt(day: number, hour: number, lat: number, lon: number, northDeg: number): { dir: V3; altitude: number; azimuth: number } {
  const tz = Math.round(lon / 15);
  const utc = Date.UTC(new Date().getFullYear(), 0, 1) + (day - 1) * 86400000 + (hour - tz) * 3600000;
  const p = solar(utc, lat, lon);
  const alt = p.altitude * Math.PI / 180, az = p.azimuth * Math.PI / 180, n = northDeg * Math.PI / 180;
  const x = Math.sin(az), y = Math.cos(az);
  const rx = x * Math.cos(n) - y * Math.sin(n), ry = x * Math.sin(n) + y * Math.cos(n);
  return { dir: [rx * Math.cos(alt), ry * Math.cos(alt), Math.sin(alt)], altitude: p.altitude, azimuth: p.azimuth };
}
/** NOAA solar position (degrees; azimuth clockwise from north), with refraction. */
export function solar(utcMs: number, lat: number, lon: number): { altitude: number; azimuth: number } {
  const jd = utcMs / 86400000 + 2440587.5, T = (jd - 2451545) / 36525;
  const L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360;
  const M = 357.52911 + T * (35999.05029 - 0.0001537 * T), Mr = M * Math.PI / 180;
  const e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T);
  const C = Math.sin(Mr) * (1.914602 - T * (0.004817 + 0.000014 * T)) + Math.sin(2 * Mr) * (0.019993 - 0.000101 * T) + Math.sin(3 * Mr) * 0.000289;
  const om = 125.04 - 1934.136 * T;
  const lambda = L0 + C - 0.00569 - 0.00478 * Math.sin(om * Math.PI / 180);
  const eps0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60;
  const eps = (eps0 + 0.00256 * Math.cos(om * Math.PI / 180)) * Math.PI / 180;
  const decl = Math.asin(Math.sin(eps) * Math.sin(lambda * Math.PI / 180));
  const y = Math.tan(eps / 2) ** 2, L0r = L0 * Math.PI / 180;
  const eot = 4 * (180 / Math.PI) * (y * Math.sin(2 * L0r) - 2 * e * Math.sin(Mr) + 4 * e * y * Math.sin(Mr) * Math.cos(2 * L0r) - 0.5 * y * y * Math.sin(4 * L0r) - 1.25 * e * e * Math.sin(2 * Mr));
  const minutes = ((utcMs / 60000) % 1440 + 1440) % 1440;
  const tst = (minutes + eot + 4 * lon) % 1440;
  let ha = tst / 4 < 0 ? tst / 4 + 180 : tst / 4 - 180;
  const latr = lat * Math.PI / 180, har = ha * Math.PI / 180;
  const cz = Math.min(1, Math.max(-1, Math.sin(latr) * Math.sin(decl) + Math.cos(latr) * Math.cos(decl) * Math.cos(har)));
  const zen = Math.acos(cz);
  let alt = 90 - zen * 180 / Math.PI;
  const azr = Math.acos(Math.min(1, Math.max(-1, (Math.sin(latr) * Math.cos(zen) - Math.sin(decl)) / (Math.cos(latr) * Math.sin(zen) || 1e-9))));
  let az = ha > 0 ? (azr * 180 / Math.PI + 180) % 360 : (540 - azr * 180 / Math.PI) % 360;
  if (alt > -0.575) {
    const te = Math.tan(alt * Math.PI / 180);
    const r = alt > 5 ? 58.1 / te - 0.07 / te ** 3 + 0.000086 / te ** 5 : alt > -0.575 ? 1735 + alt * (-518.2 + alt * (103.4 + alt * (-12.79 + alt * 0.711))) : -20.772 / te;
    alt += r / 3600;
  }
  ha = 0;
  return { altitude: alt, azimuth: az };
}

/**
 * The look of a render: the photographic preset (BeautyLighting replaces the sun, sky and camera response), or the
 * custom environment mapped onto the renderer's skies with the site sun at the render date; then exposure, bloom,
 * ambient occlusion, shadow quality / softness and the environment intensity of the window.
 */
export function lookFor(s: RenderSettings, site: { latitude: number; longitude: number; northAngle: number }): { look: Look; sun: V3 | null; sunLight: { intensity: number; color: V3 } | null } {
  let look: Look;
  let sun: V3 | null = null, sunLight: { intensity: number; color: V3 } | null = null;
  if (s.beauty) {
    look = lookFrom({ ...PRESETS[presetNamed(s.beauty) ?? "Daylight"], northAngle: site.northAngle });
    look = { ...look, exposure: look.exposure + s.exposure };
  } else {
    const env = s.environment;
    const base = env === "Sunset" ? "Golden hour" : env === "Overcast" || env === "Studio" ? "Overcast" : env === "Night" ? "Night" : "Daylight";
    look = lookFrom({ ...PRESETS[base], northAngle: site.northAngle });
    const p = sunAt(s.day, s.hour, site.latitude, site.longitude, site.northAngle);
    const altR = p.altitude * Math.PI / 180;
    if (env !== "Studio") {
      sun = p.dir;
      // RenderEngine.makeScene: dusk dims and warms the sun; night keeps it at most 60.
      let intensity = altR <= 0 ? 0 : 1800 * Math.min(1, Math.sin(altR) * 2.2 + 0.1);
      if (env === "Night") intensity = Math.min(intensity, 60);
      sunLight = { intensity: intensity / 1000, color: altR < 0.25 ? [1, 0.78, 0.55] : [1, 0.97, 0.92] };
    }
    look = {
      ...look, exposure: look.exposure + s.exposure, bloom: s.bloom, ao: look.ao * s.ambientOcclusion,
      envIntensity: look.envIntensity * (s.environmentIntensity / 1.3),
      shadowRadius: Math.max(0.5, s.shadowSoftness * 0.6), shadowAlpha: s.shadowQuality === "Off" ? 0 : look.shadowAlpha,
    };
  }
  return { look, sun, sunLight };
}

/** White balance of the finished image (BeautyRenderer.whiteBalance: neutral K → 6500 K), in linear light. */
export function whiteBalance(px: Uint8Array, kelvin: number) {
  if (Math.abs(kelvin - 6500) <= 50) return;
  const src = blackBody(kelvin), dst = blackBody(6500);
  const g = [dst[0] / src[0], dst[1] / src[1], dst[2] / src[2]];
  const lum = 0.2126 * g[0] + 0.7152 * g[1] + 0.0722 * g[2];
  const k = g.map((v) => v / lum);
  const toLin = new Float32Array(256);
  for (let i = 0; i < 256; i++) { const c = i / 255; toLin[i] = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; }
  const toS = (v: number) => { const c = Math.max(0, Math.min(1, v)); return Math.round((c <= 0.0031308 ? c * 12.92 : 1.055 * c ** (1 / 2.4) - 0.055) * 255); };
  for (let i = 0; i < px.length; i += 4) {
    px[i] = toS(toLin[px[i]] * k[0]); px[i + 1] = toS(toLin[px[i + 1]] * k[1]); px[i + 2] = toS(toLin[px[i + 2]] * k[2]);
  }
}
/** Linear RGB of a black body (Tanner Helland's fit, the PTSceneBuilder.kelvinRGB curve). */
export function blackBody(k: number): number[] {
  const t = k / 100;
  let r: number, g: number;
  if (t <= 66) { r = 255; g = 99.47 * Math.log(t) - 161.12; } else { r = 329.7 * (t - 60) ** -0.1332; g = 288.1 * (t - 60) ** -0.0755; }
  const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5 * Math.log(t - 10) - 305.04;
  const lin = (v: number) => { const c = Math.min(Math.max(v, 0), 255) / 255; return Math.max(1e-4, c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4); };
  return [lin(r), lin(g), lin(b)];
}

export interface Pixels { width: number; height: number; data: Uint8Array }

export interface RenderOptions {
  settings: RenderSettings;
  site: { latitude: number; longitude: number; northAngle: number };
  camera?: ModelCamera | null;
  /** Explicit sun (sun study frames): direction and light. */
  sun?: { dir: V3; intensity: number; color: V3 } | null;
  region?: [number, number, number, number] | null;
  style?: "Photographic" | "Sketch" | "Watercolour";
  /** Supersampling of this render (default: the settings, 1 when antialiasing is off). */
  supersample?: number;
  verticalCorrection?: boolean;
}

/** Renders with the 3D view's renderer (full size, then the region is cut out, as the tiled Mac render gives). */
export async function renderImage(view: View3D, o: RenderOptions): Promise<Pixels> {
  const s = o.settings;
  const w = Math.round(s.width), h = Math.round(s.height);
  if (!(w >= 16 && h >= 16 && w <= 7680 && h <= 4320)) throw new Error("Use a size from 16×16 to 7680×4320.");
  // Textures of the Realistic style are loaded by a tiny render first.
  await view.renderPixels({ width: 16, height: 16, supersample: 1 });
  const v = view as any;
  let cam: CameraState = view.getCamera();
  if (o.camera) cam = fromSaved(o.camera, UNIT, o.verticalCorrection !== false);
  const { look, sun, sunLight } = lookFor(s, o.site);
  const ss = o.supersample ?? (s.antialias ? Math.max(1, s.supersample) : 1);
  const style = o.style === "Sketch" ? "Sketchy" : "Realistic";
  const fo: FrameOptions = {
    width: w, height: h, camera: cam, style, look, explicitPreset: true, quality: "final", supersample: ss, selection: new Set(),
    sectionBox: v.box ?? null, sectionPlane: v.plane ?? null, northAngle: o.site.northAngle,
    sunOverride: o.sun ? o.sun.dir : sun, sunLight: o.sun ? { intensity: o.sun.intensity, color: o.sun.color } : sunLight,
    weather: v.weather ?? null, fog: v.fog ?? null, water: v.water ?? null, time: 1, particles: false,
    background: s.background === "White" ? "white" : s.background === "Transparent" ? "transparent" : "sky",
    // Render window extras (RenderEngine.makeScene): clay model, depth of field, HDRI environment.
    // AODIALOG (AOForm.viewport): the stronger of the window's occlusion and the drawing's, with the drawing's radius;
    // a photographic preset sets its own (BeautyLighting.configure runs last).
    aoOverride: !s.beauty && v.aoOverride ? { intensity: Math.max(look.ao, v.aoOverride.intensity), radius: v.aoOverride.radius } : null,
    clay: !!s.clay,
    dof: s.depthOfField ? { focus: Math.max(0, s.focusDistance ?? 0), fStop: s.fStop ?? 2.8 } : null,
    envImage: !s.beauty && s.environment === "HDRI File" && s.hdriPath ? await hdriImage(s.hdriPath) : null,
  };
  let px: Pixels = view.renderer.renderPixels(view.scene, fo);
  view.invalidate();
  if (s.background === "Transparent") px = alphaFromBackground(view, fo, px);
  whiteBalance(px.data, s.whiteBalance);
  if (o.style === "Watercolour") px = watercolour(px);
  if (o.region) px = cut(px, o.region);
  return px;
}

/** The HDRI file of the Render window as an environment image (null: missing or unreadable → the clear sky, as the Mac). */
export async function hdriImage(path: string): Promise<EnvImage | null> {
  try {
    const n = out();
    const bytes = n ? await n.readBytes(path) : webFiles.get(path) ?? null;
    if (!bytes) return null;
    return await environmentFromBytes(path, bytes);
  } catch { return null; }
}

/** A transparent background: the model's coverage from a white and a black background render. */
function alphaFromBackground(view: View3D, fo: FrameOptions, px: Pixels): Pixels {
  const white = view.renderer.renderPixels(view.scene, { ...fo, background: "white", hideGround: true });
  const black = view.renderer.renderPixels(view.scene, { ...fo, background: "transparent", hideGround: true });
  const out = new Uint8Array(px.data.length);
  for (let i = 0; i < out.length; i += 4) {
    const a = 1 - ((white.data[i] - black.data[i]) + (white.data[i + 1] - black.data[i + 1]) + (white.data[i + 2] - black.data[i + 2])) / (3 * 255);
    const al = Math.max(0, Math.min(1, a));
    out[i] = al > 0.004 ? Math.min(255, Math.round(black.data[i] / al)) : 0;
    out[i + 1] = al > 0.004 ? Math.min(255, Math.round(black.data[i + 1] / al)) : 0;
    out[i + 2] = al > 0.004 ? Math.min(255, Math.round(black.data[i + 2] / al)) : 0;
    out[i + 3] = Math.round(al * 255);
  }
  view.invalidate();
  return { width: px.width, height: px.height, data: out };
}

/** Alpha pass: white where the model covers the background (RenderEngine.alphaMask). */
export function alphaMask(px: Pixels): Pixels {
  const out = new Uint8Array(px.data.length);
  for (let i = 0; i < out.length; i += 4) { const a = px.data[i + 3]; out[i] = a; out[i + 1] = a; out[i + 2] = a; out[i + 3] = 255; }
  return { width: px.width, height: px.height, data: out };
}

/** Region as fractions of the frame (top-left origin): x0, y0, x1, y1. */
export function cut(px: Pixels, r: [number, number, number, number]): Pixels {
  const x0 = Math.round(r[0] * px.width), y0 = Math.round(r[1] * px.height);
  const w = Math.max(1, Math.round(r[2] * px.width) - x0), h = Math.max(1, Math.round(r[3] * px.height) - y0);
  const out = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) out.set(px.data.subarray(((y0 + y) * px.width + x0) * 4, ((y0 + y) * px.width + x0 + w) * 4), y * w * 4);
  return { width: w, height: h, data: out };
}

/** Pastes a region render over the previous frame (render region only, re-rendered over the last image). */
export function paste(base: Pixels, part: Pixels, r: [number, number, number, number]): Pixels {
  const out = new Uint8Array(base.data);
  const x0 = Math.round(r[0] * base.width), y0 = Math.round(r[1] * base.height);
  for (let y = 0; y < part.height && y0 + y < base.height; y++) {
    const w = Math.min(part.width, base.width - x0);
    out.set(part.data.subarray(y * part.width * 4, (y * part.width + w) * 4), ((y0 + y) * base.width + x0) * 4);
  }
  return { width: base.width, height: base.height, data: out };
}

/** Watercolour (NPRStyle.watercolour): softened colour fields, edge darkening and paper grain. */
export function watercolour(px: Pixels): Pixels {
  const { width: w, height: h, data } = px;
  const blur = boxBlur(data, w, h, Math.max(1, Math.round(Math.min(w, h) / 300)));
  const out = new Uint8Array(data.length);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const grain = 0.94 + 0.06 * fract(Math.sin(x * 12.9898 + y * 78.233) * 43758.5453);
      for (let c = 0; c < 3; c++) {
        const v = blur[i + c] / 255, q = Math.round(v * 6) / 6;
        const edge = Math.abs(data[i + c] - blur[i + c]) / 255;
        const m = (0.55 * q + 0.45 * v) * (1 - edge * 0.8);
        out[i + c] = Math.round(255 * Math.min(1, (0.97 - (0.97 - m) * 0.85) * grain));
      }
      out[i + 3] = data[i + 3];
    }
  }
  return { width: w, height: h, data: out };
}
const fract = (v: number) => v - Math.floor(v);
function boxBlur(src: Uint8Array, w: number, h: number, r: number): Float32Array {
  const tmp = new Float32Array(src.length), out = new Float32Array(src.length);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let c = 0; c < 3; c++) {
    let s = 0, n = 0;
    for (let k = -r; k <= r; k++) { const xx = Math.min(w - 1, Math.max(0, x + k)); s += src[(y * w + xx) * 4 + c]; n++; }
    tmp[(y * w + x) * 4 + c] = s / n;
  }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let c = 0; c < 3; c++) {
    let s = 0, n = 0;
    for (let k = -r; k <= r; k++) { const yy = Math.min(h - 1, Math.max(0, y + k)); s += tmp[(yy * w + x) * 4 + c]; n++; }
    out[(y * w + x) * 4 + c] = s / n;
  }
  return out;
}
