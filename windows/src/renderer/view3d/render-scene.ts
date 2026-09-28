// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Render window's scene without a photographic preset, ported from ArchiApp/RenderController.swift
// (EnvironmentMaps.image, RenderEngine.makeScene) and AppAlgorithms.swift / RenderAnimation.swift (SkyModel, PhysicalSky):
// the procedural environment maps (Clear Sky, Overcast, Sunset, Studio, Night gradients and the Physical Sky), the sun
// of the render date at the site, the ambient light, shadow quality and the plain HDR camera (exposure, bloom, SSAO,
// vignette). 360° panoramas (RenderEngine.panorama / stereoPanorama) render their cube faces with the same scene.

import type { V3 } from "./math";
import { toLinear } from "./math";
import type { Look } from "./look";
import { PRESETS, presetNamed, lookFrom, sunDirection } from "./look";
import { sunStudy } from "./effects";
import { panoramaDirection, toSK } from "./sky";
import type { EnvImage } from "./hdri";
import type { FrameOptions } from "./renderer";

/** The RenderSettings fields makeScene reads (output/render.ts RenderSettings has them all). */
export interface SceneSettings {
  day: number; hour: number; exposure: number;
  background: "Sky" | "White" | "Transparent";
  environment: string; hdriPath: string; environmentIntensity: number;
  shadowQuality: "Off" | "Low" | "Medium" | "High" | "Ultra"; shadowSoftness: number; shadowSamples: number | null;
  ambientOcclusion: number; bloom: number; clay: boolean; depthOfField: boolean;
  beauty: string | null;
}

/** RenderSettings() of the Mac (PANORAMA and STEREOPANORAMA render with these). */
export function defaultSceneSettings(): SceneSettings {
  return { day: 172, hour: 15, exposure: 0, background: "Sky", environment: "Clear Sky", hdriPath: "", environmentIntensity: 1.3,
    shadowQuality: "High", shadowSoftness: 4, shadowSamples: null, ambientOcclusion: 1, bloom: 0.15, clay: false, depthOfField: false, beauty: null };
}

/** RenderSettings.ShadowQuality: shadow map size, soft-shadow samples. */
export const SHADOW_MAP: Record<string, number> = { Off: 2048, Low: 2048, Medium: 4096, High: 4096, Ultra: 8192 };
export const SHADOW_SAMPLE_COUNT: Record<string, number> = { Off: 1, Low: 4, Medium: 8, High: 16, Ultra: 32 };

// MARK: environment maps (EnvironmentMaps.image)

type RGB = [number, number, number];
const GRADIENTS: Record<string, { zenith: RGB; horizon: RGB; ground: RGB; glow: RGB | null }> = {
  "Clear Sky": { zenith: [0.24, 0.45, 0.78], horizon: [0.78, 0.86, 0.94], ground: [0.36, 0.35, 0.32], glow: null },
  Overcast: { zenith: [0.72, 0.72, 0.72], horizon: [0.88, 0.88, 0.88], ground: [0.42, 0.42, 0.42], glow: null },
  Sunset: { zenith: [0.18, 0.22, 0.45], horizon: [1.0, 0.62, 0.35], ground: [0.25, 0.2, 0.18], glow: [1, 0.8, 0.5] },
  Studio: { zenith: [0.95, 0.95, 0.95], horizon: [0.8, 0.8, 0.8], ground: [0.55, 0.55, 0.55], glow: [1, 1, 1] },
  Night: { zenith: [0.02, 0.03, 0.07], horizon: [0.08, 0.1, 0.16], ground: [0.03, 0.03, 0.03], glow: null },
};
export const ENVIRONMENTS = ["Physical Sky", "Clear Sky", "Overcast", "Sunset", "Studio", "Night", "HDRI File"];

const mixRGB = (a: RGB, b: RGB, t: number): RGB => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const cache = new Map<string, EnvImage>();

/**
 * The 1024 × 512 gradient map of an environment, as the Mac draws it into an NSImage (sRGB): the sky from the horizon
 * colour up to the zenith colour, the ground from the ground colour up to the horizon/ground mix, and for Sunset and
 * Studio a soft radial glow (the sun or a softbox). Returned as linear floats, row 0 at the top (the sky's layout).
 */
export function gradientEnvironment(name: string): EnvImage {
  const g = GRADIENTS[name] ?? GRADIENTS["Clear Sky"];
  const key = "gradient|" + (GRADIENTS[name] ? name : "Clear Sky");
  const hit = cache.get(key);
  if (hit) return hit;
  const w = 1024, h = 512, half = h / 2;
  const studio = name === "Studio";
  const lowGround = mixRGB(g.horizon, g.ground, 0.5);
  // Glow centre in AppKit coordinates (y up) and radius, in points.
  const cx = w * 0.3, cy = studio ? h * 0.85 : h * 0.56, r = studio ? 160 : 120;
  const data = new Float32Array(w * h * 4);
  for (let yt = 0; yt < h; yt++) {
    const y = h - yt - 0.5; // AppKit y of the pixel centre
    const base = y >= half ? mixRGB(g.horizon, g.zenith, Math.min(1, (y - half) / half)) : mixRGB(g.ground, lowGround, Math.max(0, y / half));
    for (let x = 0; x < w; x++) {
      let c = base;
      if (g.glow) {
        const d = Math.hypot(x + 0.5 - cx, y - cy);
        if (d <= r) {
          const a = 0.95 * (1 - d / r);
          c = [g.glow[0] * a + c[0] * (1 - a), g.glow[1] * a + c[1] * (1 - a), g.glow[2] * a + c[2] * (1 - a)];
        }
      }
      const i = (yt * w + x) * 4;
      data[i] = toLinear(c[0]); data[i + 1] = toLinear(c[1]); data[i + 2] = toLinear(c[2]); data[i + 3] = 1;
    }
  }
  const img = { key, width: w, height: h, data };
  cache.set(key, img);
  return img;
}

/** SkyModel.color: linear radiance-like colour of the sky in SceneKit direction `d` for the SceneKit sun `s` (Y up). */
export function skyModelColor(d0: V3, s0: V3): RGB {
  const ld = Math.hypot(d0[0], d0[1], d0[2]) || 1, ls = Math.hypot(s0[0], s0[1], s0[2]) || 1;
  const d: V3 = [d0[0] / ld, d0[1] / ld, d0[2] / ld], s: V3 = [s0[0] / ls, s0[1] / ls, s0[2] / ls];
  const alt = Math.asin(Math.max(-1, Math.min(1, s[1])));
  const day = Math.max(0, Math.min(1, (alt + 0.1) / 0.35));
  const warm = Math.max(0, Math.min(1, 1 - alt / 0.4));
  if (d[1] < 0) { const g = 0.18 * day + 0.02; return [g * 1.05, g, g * 0.92]; }
  const hh = Math.pow(1 - d[1], 3);
  const zen: RGB = [0.18 * day + 0.01, 0.36 * day + 0.015, 0.78 * day + 0.04];
  const hor: RGB = [0.75 * day + 0.25 * warm * day + 0.03, 0.82 * day - 0.2 * warm * day + 0.03, 0.9 * day - 0.45 * warm * day + 0.05];
  let r = zen[0] + (hor[0] - zen[0]) * hh, g = zen[1] + (hor[1] - zen[1]) * hh, b = zen[2] + (hor[2] - zen[2]) * hh;
  const cosA = Math.max(-1, Math.min(1, d[0] * s[0] + d[1] * s[1] + d[2] * s[2]));
  const angle = Math.acos(cosA);
  const glow = Math.exp(-angle * 4.5) * 0.9 * day;
  r += glow; g += glow * (0.85 - 0.25 * warm); b += glow * (0.65 - 0.35 * warm);
  if (angle < 0.012 && s[1] > -0.02) { r += 4; g += 3.6 * (1 - 0.3 * warm); b += 3.2 * (1 - 0.5 * warm); }
  return [r, g, b];
}

/** PhysicalSky.image: SkyModel tone-mapped into an 8-bit 1024 × 512 image (as SceneKit reads it: sRGB → linear). */
export function physicalSkyEnvironment(sunModel: V3): EnvImage {
  const s = toSK(sunModel);
  const key = "physical|" + s.map((v) => v.toFixed(2)).join(",");
  const hit = cache.get(key);
  if (hit) return hit;
  const w = 1024, h = 512;
  const tone = (v: number) => Math.max(0, Math.min(255, Math.round(Math.pow(Math.max(0, v) / (1 + Math.max(0, v)) * 1.6, 1 / 2.2) * 255)));
  const data = new Float32Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const c = skyModelColor(panoramaDirection((x + 0.5) / w, (y + 0.5) / h), s);
    const i = (y * w + x) * 4;
    data[i] = toLinear(tone(c[0]) / 255); data[i + 1] = toLinear(tone(c[1]) / 255); data[i + 2] = toLinear(tone(c[2]) / 255); data[i + 3] = 1;
  }
  const img = { key, width: w, height: h, data };
  if (cache.size > 24) cache.clear();
  cache.set(key, img);
  return img;
}

/** EnvironmentMaps.image for an environment name (HDRI File: null — the caller loads the file, else the clear sky). */
export function environmentImage(name: string, sunModel: V3): EnvImage | null {
  if (name === "Physical Sky") return physicalSkyEnvironment(sunModel);
  if (name === "HDRI File") return null;
  return gradientEnvironment(name);
}

// MARK: RenderEngine.makeScene

export interface SceneState {
  /** Look of the drawing's preset (RENDERPRESET) or of the default Realistic view, and whether one was chosen. */
  look: Look;
  explicit: boolean;
  site: { latitude: number; longitude: number; northAngle: number };
}

/**
 * Frame options of a render with the Render window's settings, as RenderEngine.makeScene builds the scene:
 * - a photographic preset (`beauty`) replaces the sun, sky and camera response (BeautyLighting.apply / configure),
 *   plus the window's exposure, background and clay;
 * - otherwise the Realistic view of the drawing (with its preset's haze, meadow and lamps when one is chosen) lit by the
 *   site sun at the render date (dimmed and warmed at dusk, at most 60 with the Night map), 260 ambient, the chosen
 *   environment map for image-based light (× environmentIntensity) and background, the shadow quality and softness,
 *   and a plain HDR camera: exposure, bloom (threshold 0.9), SSAO (radius 0.45) and vignetting 0.3.
 */
export function sceneOptions(s: SceneSettings, st: SceneState): Partial<FrameOptions> & { look: Look; explicitPreset: boolean } {
  if (s.beauty) {
    const look = lookFrom({ ...PRESETS[presetNamed(s.beauty) ?? "Daylight"], northAngle: st.site.northAngle });
    return { look: { ...look, exposure: look.exposure + s.exposure }, explicitPreset: true, renderScene: null, envImage: null };
  }
  const p = sunStudy(s.day, s.hour, st.site.latitude, st.site.longitude);
  const altR = p.altitude * Math.PI / 180;
  const dir = sunDirection(p.altitude, p.azimuth, st.site.northAngle);
  let intensity = altR <= 0 ? 0 : 1800 * Math.min(1, Math.sin(altR) * 2.2 + 0.1);
  if (s.environment === "Night") intensity = Math.min(intensity, 60);
  // Sun colour: the preset's (linear) or the default warm white (sRGB); dusk warms it.
  const sunColor: V3 = altR < 0.25 ? srgb([1, 0.78, 0.55]) : st.explicit ? [...st.look.sunColor] as V3 : srgb([1, 0.97, 0.92]);
  const env = environmentImage(s.environment, dir);
  return {
    look: st.look, explicitPreset: st.explicit, sunOverride: dir, sunLight: null,
    envImage: env ?? (s.environment === "HDRI File" ? null : gradientEnvironment("Clear Sky")),
    renderScene: {
      sunIntensity: intensity / 1000, sunColor, ambient: altR <= 0 ? 90 : 260,
      ambientColor: st.explicit ? [0.8, 0.85, 1.0] : [0.9, 0.9, 0.9],
      envIntensity: s.environmentIntensity,
      shadows: s.shadowQuality !== "Off", shadowRadius: Math.max(0, s.shadowSoftness), shadowAlpha: st.explicit ? st.look.shadowAlpha : 0.45,
      shadowMap: SHADOW_MAP[s.shadowQuality] ?? 4096,
      shadowSamples: Math.max(1, Math.min(64, s.shadowSamples ?? SHADOW_SAMPLE_COUNT[s.shadowQuality] ?? 16)),
      exposure: s.exposure, bloom: s.bloom, bloomThreshold: 0.9, ao: s.ambientOcclusion, aoRadius: 0.45, vignette: 0.3, vignettePower: 0.6,
    },
  };
}

function srgb(c: V3): V3 { return [toLinear(c[0]), toLinear(c[1]), toLinear(c[2])]; }
