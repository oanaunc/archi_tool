// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Video export of the renderer (RenderEngine.writeVideo / walkthrough / sunStudy / turntable and the camera path
// editor's Export Video): frames rendered one by one by the 3D view, encoded with WebCodecs (H.264, else VP9) and
// written as MP4 (mp4.ts) at w × h × 6 bits per second, like the Mac's AVAssetWriter settings.
import { mp4, Mp4Sample } from "./mp4";
import { sleep } from "./native";

export interface VideoJob {
  width: number; height: number; fps: number; frames: number;
  /** RGBA pixels (top row first) of frame i. */
  render(i: number): Promise<{ width: number; height: number; data: Uint8Array }>;
  progress?(p: number): void;
  cancelled?(): boolean;
}

const AVC = ["avc1.640033", "avc1.64002a", "avc1.640028", "avc1.4d0028", "avc1.42e028", "avc1.42e01f"];
const VP9 = ["vp09.00.40.08", "vp09.00.31.08", "vp09.00.10.08"];

async function pickCodec(w: number, h: number, fps: number): Promise<{ codec: string; kind: "avc1" | "vp09" } | null> {
  const VE = (globalThis as any).VideoEncoder;
  if (!VE) return null;
  for (const [list, kind] of [[AVC, "avc1"], [VP9, "vp09"]] as const) {
    for (const codec of list) {
      const cfg: any = { codec, width: w, height: h, bitrate: w * h * 6, framerate: fps };
      if (kind === "avc1") cfg.avc = { format: "avc" };
      try { const r = await VE.isConfigSupported(cfg); if (r?.supported) return { codec, kind }; } catch { /* next */ }
    }
  }
  return null;
}

/** Renders and encodes the frames; returns the MP4 bytes (throws when this Chromium has no video encoder). */
export async function encodeVideo(job: VideoJob): Promise<{ bytes: Uint8Array; codec: string; frames: number }> {
  const w = Math.max(2, job.width - (job.width % 2)), h = Math.max(2, job.height - (job.height % 2));
  const pick = await pickCodec(w, h, job.fps);
  if (!pick) throw new Error("Video export needs H.264 or VP9 encoding (WebCodecs), which this system does not offer.");
  const VE = (globalThis as any).VideoEncoder, VF = (globalThis as any).VideoFrame;
  const samples: Mp4Sample[] = [];
  let description: Uint8Array | undefined;
  let failure: any = null;
  const enc = new VE({
    output: (chunk: any, meta: any) => {
      const d = new Uint8Array(chunk.byteLength);
      chunk.copyTo(d);
      samples.push({ data: d, key: chunk.type === "key" });
      const desc = meta?.decoderConfig?.description;
      if (desc && !description) description = desc instanceof ArrayBuffer ? new Uint8Array(desc.slice(0)) : new Uint8Array(desc.buffer.slice(desc.byteOffset, desc.byteOffset + desc.byteLength));
    },
    error: (e: any) => { failure = e; },
  });
  const cfg: any = { codec: pick.codec, width: w, height: h, bitrate: w * h * 6, framerate: job.fps, latencyMode: "quality" };
  if (pick.kind === "avc1") cfg.avc = { format: "avc" };
  enc.configure(cfg);
  const n = Math.max(1, job.frames);
  for (let i = 0; i < n; i++) {
    if (job.cancelled?.()) break;
    if (failure) throw failure;
    const px = await job.render(i);
    let data = px.data;
    if (px.width !== w || px.height !== h) data = crop(px, w, h);
    const frame = new VF(data, { format: "RGBA", codedWidth: w, codedHeight: h, timestamp: Math.round((i * 1e6) / job.fps), duration: Math.round(1e6 / job.fps) });
    enc.encode(frame, { keyFrame: i % (job.fps * 2) === 0 });
    frame.close();
    while (enc.encodeQueueSize > 3) await sleep(2);
    job.progress?.((i + 1) / n);
  }
  await enc.flush();
  enc.close();
  if (failure) throw failure;
  if (!samples.length) throw new Error("No frames were encoded.");
  return { bytes: mp4({ codec: pick.kind, width: w, height: h, fps: job.fps, description, samples }), codec: pick.codec, frames: samples.length };
}

function crop(px: { width: number; height: number; data: Uint8Array }, w: number, h: number): Uint8Array {
  const out = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) out.set(px.data.subarray(y * px.width * 4, y * px.width * 4 + w * 4), y * w * 4);
  return out;
}
