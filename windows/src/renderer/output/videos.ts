// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Videos of the renderer (RenderController.swift RenderEngine.turntable, RenderAnimation.swift walkthrough /
// sunStudy / writeVideo, RenderQueue.swift CameraPathEditor export): the camera or sun of every frame, rendered by the
// 3D view and encoded to MP4 (video.ts). Walkthrough and camera-path cameras and the sun-study sun come from the engine
// (camerapath.frames, render.sunFrames), the same Catmull-Rom path and solar calculator as the Mac.
import type { App } from "../app";
import { renderImage, RenderSettings, ModelCamera, V3 } from "./render";
import { view3d, modelCamera } from "./context";
import { encodeVideo } from "./video";
import { writeBytes } from "./native";

export interface VideoRequest {
  kind: "turntable" | "walkthrough" | "sunStudy" | "cameraPath";
  settings: RenderSettings;
  site: { latitude: number; longitude: number; northAngle: number };
  path: string;
  seconds?: number;
  fps?: number;
  day?: number; fromHour?: number; toHour?: number;
  camera?: ModelCamera | null;
  cameras?: ModelCamera[];
  pathName?: string;
  progress?(p: number): void;
  cancelled?(): boolean;
}

/** Renders, encodes and writes the video; returns the path. */
export async function exportVideo(app: App, r: VideoRequest): Promise<string> {
  const v = await view3d();
  const fps = r.fps ?? 30;
  const s: RenderSettings = { ...r.settings, supersample: 1 };
  let cameras: ModelCamera[] = [];
  let suns: { dir: V3; intensity: number; color: V3 }[] | null = null;
  let frames = 0, rate = fps;
  const start = r.camera ?? modelCamera(v);
  if (r.kind === "turntable") {
    // 360° orbit at the camera's height, radius at least 1.2 × the model's bounding sphere.
    const c = v.scene.center as V3, radius = v.scene.radius;
    const rel: V3 = [start.eye[0] - c[0], start.eye[1] - c[1], start.eye[2] - c[2]];
    const R = Math.max(radius * 1.2, Math.hypot(rel[0], rel[1]));
    const a0 = Math.atan2(rel[0], -rel[1]);
    frames = Math.max(2, Math.round((r.seconds ?? 8) * fps));
    for (let i = 0; i < frames; i++) {
      const a = a0 + (i / frames) * 2 * Math.PI;
      cameras.push({ eye: [c[0] + Math.sin(a) * R, c[1] - Math.cos(a) * R, c[2] + rel[2]], target: c, fov: start.fov ?? 45 });
    }
  } else if (r.kind === "walkthrough" || r.kind === "cameraPath") {
    const q: any = r.kind === "cameraPath" ? { path: r.pathName } : { seconds: r.seconds ?? 10, fps, ...(r.cameras ? { cameras: r.cameras } : {}) };
    const res = await app.engine.call("camerapath.frames", q);
    cameras = res.frames;
    rate = res.fps ?? fps;
    frames = cameras.length;
  } else {
    const res = await app.engine.call("render.sunFrames", { day: r.day ?? 172, fromHour: r.fromHour ?? 7, toHour: r.toHour ?? 19, seconds: r.seconds ?? 10, fps });
    suns = res.frames.map((f: any) => {
      const alt = (f.altitude * Math.PI) / 180;
      return { dir: f.direction as V3, intensity: alt <= 0 ? 0 : (1800 * Math.min(1, Math.sin(alt) * 2.2 + 0.1)) / 1000, color: (alt < 0.25 ? [1, 0.78, 0.55] : [1, 0.97, 0.92]) as V3 };
    });
    frames = suns!.length;
  }
  const out = await encodeVideo({
    width: s.width, height: s.height, fps: rate, frames,
    render: (i) => renderImage(v, { settings: s, site: r.site, camera: suns ? start : cameras[i], sun: suns ? suns[i] : null, supersample: 1, verticalCorrection: false }),
    progress: r.progress, cancelled: r.cancelled,
  });
  await writeBytes(r.path, out.bytes);
  (window as any).archiLastVideo = { path: r.path, bytes: out.bytes.length, codec: out.codec, frames: out.frames };
  return r.path;
}
