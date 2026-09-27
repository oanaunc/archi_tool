// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Photographic lighting presets and visual styles, number for number from the Mac app
// (ArchiApp/BeautyLighting.swift BeautyPreset.look, ArchiCore/Host/EngineRenderPresets.swift, Viewport3DView.swift).

import { V3, deg } from "./math";

export type SkyKind = "daylight" | "golden" | "overcast" | "night";

/** Everything a preset sets (colours linear RGB). Field names match the engine's render.settings result. */
export interface Look {
  preset: string; keyword: string; sky: SkyKind;
  sunAltitude: number; sunAzimuth: number; sunColor: V3; sunIntensity: number;
  shadowRadius: number; shadowAlpha: number; envIntensity: number; ambient: number;
  exposure: number; whitePoint: number; bloom: number; bloomThreshold: number;
  saturation: number; contrast: number; ao: number; windowGlow: number; artificial: number; lampGlow: number;
  /** Optional, from render.settings. */
  sunDirection?: V3; northAngle?: number;
}

export const PRESETS: Record<string, Look> = {
  Daylight: { preset: "Daylight", keyword: "Daylight", sky: "daylight", sunAltitude: 46, sunAzimuth: 222, sunColor: [1.0, 0.955, 0.89], sunIntensity: 3300,
    shadowRadius: 2.5, shadowAlpha: 0.94, envIntensity: 1.05, ambient: 0, exposure: 0.6, whitePoint: 1.7,
    bloom: 0.10, bloomThreshold: 1.1, saturation: 1.06, contrast: 0.06, ao: 0.85, windowGlow: 0, artificial: 0, lampGlow: 0.3 },
  "Golden hour": { preset: "Golden hour", keyword: "Goldenhour", sky: "golden", sunAltitude: 11, sunAzimuth: 228, sunColor: [1.0, 0.66, 0.38], sunIntensity: 3400,
    shadowRadius: 5, shadowAlpha: 0.9, envIntensity: 0.95, ambient: 0, exposure: 0.75, whitePoint: 1.7,
    bloom: 0.22, bloomThreshold: 0.95, saturation: 1.1, contrast: 0.08, ao: 0.9, windowGlow: 0.12, artificial: 0.3, lampGlow: 1.0 },
  Overcast: { preset: "Overcast", keyword: "Overcast", sky: "overcast", sunAltitude: 58, sunAzimuth: 200, sunColor: [0.93, 0.96, 1.0], sunIntensity: 420,
    shadowRadius: 22, shadowAlpha: 0.7, envIntensity: 1.55, ambient: 0, exposure: 0.8, whitePoint: 1.5,
    bloom: 0.05, bloomThreshold: 1.3, saturation: 0.98, contrast: 0.1, ao: 1.25, windowGlow: 0, artificial: 0.05, lampGlow: 0.4 },
  Night: { preset: "Night", keyword: "Night", sky: "night", sunAltitude: 38, sunAzimuth: 135, sunColor: [0.62, 0.72, 1.0], sunIntensity: 70,
    shadowRadius: 6, shadowAlpha: 0.85, envIntensity: 1.0, ambient: 8, exposure: 1.6, whitePoint: 1.2,
    bloom: 0.55, bloomThreshold: 0.75, saturation: 1.0, contrast: 0.05, ao: 0.8, windowGlow: 1.6, artificial: 1.6, lampGlow: 3.0 },
};
export const PRESET_NAMES = ["Daylight", "Golden hour", "Overcast", "Night"];
export const PRESET_KEYWORDS = ["Daylight", "Goldenhour", "Overcast", "Night"];

/** Lenient preset names, as BeautyPreset.named ("golden", "sunset", "cloudy", "dusk" …). */
export function presetNamed(s: string | undefined | null): string | null {
  const k = (s ?? "").toLowerCase().replace(/[^a-z]/g, "");
  if (["daylight", "day", "sunny", "clear", "clearsky", "noon"].includes(k)) return "Daylight";
  if (["goldenhour", "golden", "sunset", "sunrise", "evening", "warm"].includes(k)) return "Golden hour";
  if (["overcast", "cloudy", "soft", "grey", "gray"].includes(k)) return "Overcast";
  if (["night", "dusk", "dark", "nightlights", "bluehour"].includes(k)) return "Night";
  return null;
}

/** A look from the engine's render.settings / render.preset result (any missing field from the named preset). */
export function lookFrom(settings: Partial<Look> | null | undefined): Look {
  const base = PRESETS[presetNamed(settings?.preset ?? settings?.keyword) ?? "Daylight"];
  return { ...base, ...(settings ?? {}), sky: (settings?.sky as SkyKind) ?? base.sky } as Look;
}

/** Direction towards the sun, model coordinates (X east, Y north, Z up), as SunPosition.direction. */
export function sunDirection(altitudeDeg: number, azimuthDeg: number, northAngleDeg = 0): V3 {
  const alt = altitudeDeg * deg, az = azimuthDeg * deg, n = northAngleDeg * deg;
  const x = Math.sin(az), y = Math.cos(az);
  const c = Math.cos(n), s = Math.sin(n);
  const rx = x * c - y * s, ry = x * s + y * c;
  return [rx * Math.cos(alt), ry * Math.cos(alt), Math.sin(alt)];
}

export const VISUAL_STYLES = ["Wireframe", "Hidden Line", "Shaded", "Shaded with Edges", "Conceptual", "Realistic", "X-Ray", "Sketchy"] as const;
export type VisualStyle = (typeof VISUAL_STYLES)[number];

/** Canonical style name ("xray", "hidden", "realistic" …). */
export function styleNamed(s: string): VisualStyle {
  const k = s.toLowerCase().replace(/[^a-z]/g, "");
  const map: Record<string, VisualStyle> = {
    wireframe: "Wireframe", wire: "Wireframe", "2dwireframe": "Wireframe", "3dwireframe": "Wireframe",
    hiddenline: "Hidden Line", hidden: "Hidden Line", shaded: "Shaded", shadedwithedges: "Shaded with Edges", shadededges: "Shaded with Edges",
    conceptual: "Conceptual", realistic: "Realistic", xray: "X-Ray", sketchy: "Sketchy", sketch: "Sketchy",
  };
  return map[k] ?? "Shaded";
}

/** Edge colour (sRGB) and whether the style draws edges (Scene3DBuilder.showsEdges / configureEnvironment). */
export function styleEdges(style: VisualStyle): { show: boolean; color: V3; alpha: number; depthTest: boolean } {
  const show = ["Wireframe", "Hidden Line", "Shaded with Edges", "Conceptual", "X-Ray", "Sketchy"].includes(style);
  switch (style) {
    case "Wireframe": return { show, color: [0.85, 0.85, 0.85], alpha: 1, depthTest: true };
    case "Hidden Line": return { show, color: [0.08, 0.08, 0.08], alpha: 1, depthTest: true };
    case "Sketchy": return { show, color: SKETCH_INK, alpha: 1, depthTest: true };
    case "X-Ray": return { show, color: [0.9, 0.9, 0.9], alpha: 0.9, depthTest: false };
    default: return { show, color: [0.12, 0.12, 0.12], alpha: 1, depthTest: true };
  }
}

export const SKETCH_PAPER: V3 = [0.975, 0.965, 0.94];
export const SKETCH_INK: V3 = [0.16, 0.16, 0.19];
/** Mac accent #F5C518. */
export const ACCENT: V3 = [0.961, 0.773, 0.094];
