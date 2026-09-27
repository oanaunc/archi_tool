// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// What the output windows need from the main window: the app model and the 3D view (created on demand, loaded with
// the model, like the Mac render window uses the 3D viewport's scene and camera).
import type { App } from "../app";
import type { View3D } from "../view3d";
import type { ModelCamera } from "./render";

export interface OutputHooks {
  /** The 3D view, created (and its model loaded) when needed. */
  view3d(): Promise<View3D | null>;
  /** Visible 2D view in drawing units [x0, y0, x1, y1] (PLOTAREA Display). */
  displayBox(): number[] | null;
}
export const outCtx: { app: App | null; hooks: OutputHooks | null } = { app: null, hooks: null };

export async function view3d(): Promise<View3D> {
  const v = await outCtx.hooks?.view3d();
  if (!v) throw new Error("The 3D view is not available (WebGL 2).");
  return v;
}

/** The 3D view's camera in model millimetres (for the engine and saved paths). */
export function modelCamera(v: View3D): ModelCamera {
  const c = v.getCamera();
  return { eye: [c.eye[0] * 1000, c.eye[1] * 1000, c.eye[2] * 1000], target: [c.target[0] * 1000, c.target[1] * 1000, c.target[2] * 1000], fov: c.fov, orthographic: c.ortho };
}

export interface SiteInfo { latitude: number; longitude: number; northAngle: number }
export async function renderWindowInfo(app: App, day = 172, hour = 15): Promise<any> {
  return (await app.tryCall("render.window", { day, hour })) ?? {
    presets: [], resolutions: ["1280×720", "1920×1080", "2560×1440", "3840×2160", "5120×2880", "7680×4320", "1080×1080", "Custom"],
    passes: ["Beauty", "Alpha", "Depth", "Normal", "Material ID"], styles: ["Photographic", "Sketch", "Watercolour"], backgrounds: ["Sky", "White", "Transparent"],
    environments: ["Physical Sky", "Clear Sky", "Overcast", "Sunset", "Studio", "Night", "HDRI File"], shadowQualities: ["Off", "Low", "Medium", "High", "Ultra"],
    looks: ["Daylight", "Golden hour", "Overcast", "Night"], latitude: 44.43, longitude: 26.1, northAngle: 0, site: "Site 44.430°, 26.100°", cameras: [], sunText: "", title: "Render",
  };
}
