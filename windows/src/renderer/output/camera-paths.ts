// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Camera path editor (ArchiApp/RenderQueue.swift CameraPathWindow / CameraPathEditor, VIS-042): named paths of camera
// keys at times (stored in the drawing, CAMERAPATHS), keys from the current 3D view or saved cameras, even timing,
// a timeline with scrubbing and playback in the 3D view, FPS, video export and queueing one render per key.
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, picker, flatButton, note, label, row, stepper, slider, textField } from "../dialogs/ui";
import { showMenu } from "../ui/menu";
import { sym } from "./icons";
import { view3d, modelCamera, renderWindowInfo } from "./context";
import { defaultSettings, ModelCamera, V3 } from "./render";
import { exportVideo } from "./videos";
import { saveDialog, docName, fileName } from "./native";
import { queue, openRenderQueue } from "./render-queue";
import { fromSaved } from "../view3d/camera";
import { UNIT } from "../view3d";

export interface CameraKey { name: string; time: number; camera: ModelCamera }
export interface CameraPath { name: string; fps: number; keys: CameraKey[]; duration?: number }

function catmull(p0: V3, p1: V3, p2: V3, p3: V3, u: number): V3 {
  const u2 = u * u, u3 = u2 * u;
  return [0, 1, 2].map((k) => 0.5 * (2 * p1[k] + (p2[k] - p0[k]) * u + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u2 + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * u3)) as V3;
}
/** CameraPath.sample: smooth path through the key cameras, t ∈ [0, 1], equal time per segment. */
export function sampleKeys(keys: ModelCamera[], t: number): ModelCamera | null {
  if (!keys.length) return null;
  if (keys.length === 1) return keys[0];
  const x = Math.min(Math.max(t, 0), 1) * (keys.length - 1);
  const i = Math.min(Math.floor(x), keys.length - 2), u = x - i;
  const at = (k: number) => keys[Math.min(Math.max(k, 0), keys.length - 1)];
  const f0 = at(i).fov ?? 50, f1 = at(i + 1).fov ?? 50;
  return { eye: catmull(at(i - 1).eye, at(i).eye, at(i + 1).eye, at(i + 2).eye, u), target: catmull(at(i - 1).target, at(i).target, at(i + 1).target, at(i + 2).target, u), fov: f0 + (f1 - f0) * u, orthographic: false };
}
/** CameraPathDef.sample(at:): the key cameras at the key times, smooth in between, clamped at both ends. */
export function sampleAt(p: CameraPath, time: number): ModelCamera | null {
  const k = [...p.keys].sort((a, b) => a.time - b.time);
  if (!k.length) return null;
  if (k.length === 1 || time <= k[0].time) return k[0].camera;
  if (time >= k[k.length - 1].time) return k[k.length - 1].camera;
  let i = 0;
  while (i + 1 < k.length - 1 && k[i + 1].time <= time) i++;
  const u = Math.min(Math.max((time - k[i].time) / Math.max(k[i + 1].time - k[i].time, 1e-9), 0), 1);
  return sampleKeys(k.map((x) => x.camera), (i + u) / (k.length - 1));
}
const duration = (p: CameraPath) => Math.max(0, ...p.keys.map((k) => k.time));

/** Shows a camera in the 3D view (RenderEngine.place on the viewport camera). */
export async function showCamera(c: ModelCamera) {
  const v: any = await view3d();
  const cam = fromSaved(c, UNIT, false);
  if (typeof v.moveTo === "function") v.moveTo(cam, false); else { v.camera = cam; v.invalidate(); }
}

export async function openCameraPaths(app: App) {
  let data = await app.tryCall("camerapath.list");
  if (!data) return;
  let current = "", time = 0, playing = 0, status = "", progress = -1, exporting = false;
  const paths = (): CameraPath[] => data.paths;
  const pathOf = () => paths().find((p) => p.name === current) ?? paths()[0] ?? null;
  const edit = async (labelText: string, f: (ps: CameraPath[]) => void) => {
    const ps: CameraPath[] = JSON.parse(JSON.stringify(paths()));
    f(ps);
    const r = await app.tryCall("camerapath.set", { paths: ps.map((p) => ({ name: p.name, fps: p.fps, keys: p.keys })), label: labelText });
    if (r) data = r;
    await app.refresh(["document", "history"]);
    render();
  };
  const unique = (base: string) => { let n = base, k = 2; while (paths().some((p) => p.name.toLowerCase() === n.toLowerCase())) n = `${base} ${k++}`; return n; };
  let body: HTMLElement;
  const stop = () => { if (playing) cancelAnimationFrame(playing); playing = 0; };
  const render = () => {
    clear(body);
    const p = pathOf();
    const head = row(picker(paths().map((x) => ({ value: x.name, title: x.name })), p?.name ?? "", (v) => { current = v; time = 0; render(); }, { label: "Path", width: 180 }),
      flatButton("New", () => void edit("New Camera Path", (ps) => { const n = unique("Path"); ps.push({ name: n, fps: 30, keys: [] }); current = n; }), { compact: true }),
      p ? flatButton("Delete", () => { const n = p.name; current = ""; void edit("Delete Camera Path", (ps) => { const i = ps.findIndex((x) => x.name === n); if (i >= 0) ps.splice(i, 1); }); }, { compact: true }) : null);
    body.append(head);
    if (!p) {
      body.append(note("Create a path, then add keys from the current 3D view or from saved cameras. Keys are played back along a smooth path at their times."), h("div", { class: "spacer" }));
      if (status) body.append(note(status));
      return;
    }
    const dur = duration(p);
    const addKey = (name: string, camera: ModelCamera) => {
      const t = p.keys.length ? dur + 3 : 0;
      time = t;
      void edit("Add Camera Key", (ps) => { ps.find((x) => x.name === p.name)!.keys.push({ name, time: t, camera }); });
    };
    const savedBtn = flatButton("Add Saved Camera", () => {
      const cams: ModelCamera[] = data.cameras ?? [];
      showMenu(cams.map((c) => ({ title: c.name ?? "Camera", action: () => addKey(c.name ?? "Camera", c) })), savedBtn);
    }, { compact: true });
    body.append(row(
      flatButton("Add Current View", async () => { try { addKey(`Key ${p.keys.length + 1}`, modelCamera(await view3d())); } catch { status = "Open the 3D view first."; render(); } }, { compact: true }),
      savedBtn, h("span", { class: "spacer" }),
      flatButton("Even Timing", () => void edit("Retime Camera Path", (ps) => {
        const q = ps.find((x) => x.name === p.name)!;
        const total = Math.max(dur, Math.max(q.keys.length - 1, 1) * 3);
        q.keys.sort((a, b) => a.time - b.time).forEach((k, i) => { k.time = q.keys.length > 1 ? (total * i) / (q.keys.length - 1) : 0; });
      }), { compact: true, disabled: p.keys.length < 2 })));
    const list = h("div", { class: "dlist cp-list" });
    [...p.keys].sort((a, b) => a.time - b.time).forEach((k, i) => {
      const tf = textField("s", k.time.toFixed(1), () => {}, { width: 56, onBlur: (v) => { const n = Number(v); if (Number.isFinite(n) && n !== k.time) void edit("Camera Key Time", (ps) => { const q = ps.find((x) => x.name === p.name)!; const j = q.keys.findIndex((x) => x.name === k.name && x.time === k.time); if (j >= 0) q.keys[j].time = Math.max(0, n); }); }, onSubmit: (v) => tf.blur() });
      const eye = h("button", { class: "iconbtn", title: "Show this key in the 3D view" }, sym("eye", 12));
      eye.addEventListener("click", () => { time = k.time; void showCamera(k.camera); render(); });
      const del = h("button", { class: "iconbtn", title: "Delete the key" }, sym("trash", 12));
      del.addEventListener("click", () => void edit("Delete Camera Key", (ps) => { const q = ps.find((x) => x.name === p.name)!; const j = q.keys.findIndex((x) => x.name === k.name && x.time === k.time); if (j >= 0) q.keys.splice(j, 1); }));
      list.append(h("div", { class: "li small cp-key" }, h("span", { class: "mono dim cp-i", text: String(i + 1) }), h("span", { text: k.name }), h("span", { class: "spacer" }), tf, label("s", { dim: true }), eye, del));
    });
    body.append(list);
    const tl = label(`${time.toFixed(1)} / ${dur.toFixed(1)} s`, { mono: true, width: 90 });
    const play = h("button", { class: "iconbtn cp-play", title: playing ? "Pause" : "Play" }, sym(playing ? "pause.fill" : "play.fill", 12)) as HTMLButtonElement;
    play.disabled = p.keys.length < 2;
    const sl = slider(0, Math.max(dur, 0.1), 0.01, time, (v) => { time = v; tl.textContent = `${time.toFixed(1)} / ${dur.toFixed(1)} s`; const c = sampleAt(p, time); if (c) void showCamera(c); }, 260);
    play.addEventListener("click", () => {
      if (playing) { stop(); render(); return; }
      if (time >= dur) time = 0;
      const t0 = performance.now(), start = time;
      const tick = () => {
        time = Math.min(dur, start + (performance.now() - t0) / 1000);
        sl.value = String(time); tl.textContent = `${time.toFixed(1)} / ${dur.toFixed(1)} s`;
        const c = sampleAt(p, time); if (c) void showCamera(c);
        if (time >= dur) { playing = 0; render(); return; }
        playing = requestAnimationFrame(tick);
      };
      playing = requestAnimationFrame(tick);
      render();
    });
    body.append(row(play, sl, tl));
    const marks = h("div", { class: "cp-marks" }, h("div", { class: "cp-line" }));
    for (const k of p.keys) { const m = h("span", { class: "cp-mark" }, sym("diamond.fill", 8)); m.style.left = `calc(${(k.time / Math.max(dur, 0.1)) * 100}% - 4px)`; marks.append(m); }
    body.append(marks);
    body.append(row(stepper((v) => `FPS ${v}`, p.fps, 1, 60, (v) => void edit("Camera Path FPS", (ps) => { ps.find((x) => x.name === p.name)!.fps = Math.max(1, Math.min(60, v)); })),
      h("span", { class: "spacer" }),
      flatButton("Export Video…", () => void exportPath(p), { disabled: p.keys.length < 2 || exporting }),
      flatButton("Queue Frames", () => { for (const k of [...p.keys].sort((a, b) => a.time - b.time)) queue.add(`${p.name} – ${k.name}`, k.camera, null); void openRenderQueue(app); }, { compact: true, disabled: !p.keys.length, help: "Adds one render job per key to the render queue" })));
    if (exporting) body.append(h("progress", { class: "cp-progress", max: 1, value: Math.max(0, progress) }));
    if (status) body.append(note(status));
  };
  async function exportPath(p: CameraPath) {
    const path = await saveDialog(app, "Export Video", `${docName(app)} ${p.name}.mp4`, [{ name: "MPEG-4 movie", extensions: ["mp4"] }]);
    if (!path) return;
    exporting = true; progress = 0; render();
    const info = await renderWindowInfo(app);
    const s = defaultSettings(); s.width = 1280; s.height = 720;
    try {
      await exportVideo(app, { kind: "cameraPath", pathName: p.name, settings: s, site: { latitude: info.latitude, longitude: info.longitude, northAngle: info.northAngle }, path,
        progress: (x) => { progress = x; const pr = body.querySelector(".cp-progress") as HTMLProgressElement | null; if (pr) pr.value = x; } });
      const frames = (window as any).archiLastVideo?.frames ?? Math.max(2, Math.floor(duration(p) * p.fps) + 1);
      status = `Saved ${fileName(path)} (${frames} frames).`;
    } catch (e: any) { status = `Video export failed: ${e?.message ?? e}`; }
    exporting = false; render();
  }
  toolWindow("cameraPaths", "Camera Paths", 460, 560, (b) => { body = h("div", { class: "dcol cp" }); b.append(body); render(); }, () => stop());
}
